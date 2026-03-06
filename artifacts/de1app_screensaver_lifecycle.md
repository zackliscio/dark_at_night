# de1app Screensaver and Display Brightness Lifecycle

Reference document for plugin developers working with the de1app screensaver,
sleep, and display brightness systems. All line numbers and file paths are
relative to `de1plus/` in the de1app source tree.

---

## 1. Settings Reference

### Screensaver timing

| Variable | Type | Range | Purpose |
|---|---|---|---|
| `::settings(screen_saver_delay)` | int | 0-120 | Minutes of inactivity before the screensaver activates. 0 = never auto-sleep. |
| `::settings(screen_saver_change_interval)` | int | 0-120 | Minutes between screensaver image rotations. **0 = black screen mode** (no images shown, brightness forced to 0). |

### Brightness

| Variable | Type | Range | Purpose |
|---|---|---|---|
| `::settings(app_brightness)` | int | 0-100 | Display brightness during normal (non-saver) use. Automatically applied on every non-saver page load. |
| `::settings(saver_brightness)` | int | 0-100 | Display brightness while on the saver page. **Only used when `screen_saver_change_interval > 0`**. When interval is 0, brightness is hardcoded to 0 regardless of this setting. |

### Screen lock

| Variable | Type | Purpose |
|---|---|---|
| `::settings(lock_screen_during_screensaver)` | bool | When 1, enables `sdltk screensaver on` during sleep, which is an OS-level touch lock that prevents taps from reaching the app. Cleared by `start_idle`. |

### Scheduler (forced-awake window)

| Variable | Type | Purpose |
|---|---|---|
| `::settings(scheduler_enable)` | bool | Enables the scheduler system. |
| `::settings(scheduler_wake)` | int | Seconds-since-midnight for the forced-awake window start. |
| `::settings(scheduler_sleep)` | int | Seconds-since-midnight for the forced-awake window end. |

When the scheduler is enabled and the current time is between `scheduler_wake`
and `scheduler_sleep`, `show_going_to_sleep_page` refuses to activate the
screensaver and instead calls `delay_screen_saver` to retry later.

### Runtime state

| Variable | Purpose |
|---|---|
| `::de1(current_context)` | The current page name (e.g. `"off"`, `"saver"`, `"espresso"`). Set by DUI **after** page load actions run. |
| `::de1(state)` | Raw DE1 machine state number. |
| `::de1_num_state($::de1(state))` | Human-readable machine state: `"Idle"`, `"Sleep"`, `"Espresso"`, etc. |
| `::screen_saver_alarm_handle` | The Tcl `after` handle for the pending sleep timer. |
| `::change_screen_saver_image_handle` | The Tcl `after` handle for the pending image rotation timer. |

---

## 2. Going-to-Sleep Event Chain

### 2.1 The sleep timer: `delay_screen_saver`

**File:** `gui.tcl:851`

```tcl
proc delay_screen_saver {} {
    stop_screen_saver_timer
    if {$::settings(screen_saver_delay) != 0} {
        set ::screen_saver_alarm_handle \
            [after [expr {60 * 1000 * $::settings(screen_saver_delay)}] \
                "show_going_to_sleep_page"]
    }
}
```

This is the inactivity timer. It cancels any existing timer, then schedules
`show_going_to_sleep_page` to run after `screen_saver_delay` minutes.

**What resets the timer (calls `delay_screen_saver`):**
- Every `dui page load` call (`dui.tcl:6374`) -- any page navigation
- DE1 BLE state changes (`de1_comms.tcl:1368`)
- Various skin-specific interactions (DSx2, Insight, etc.)
- Settings saves (`vars.tcl`)
- MQTT plugin activity

### 2.2 The sleep entry point: `show_going_to_sleep_page`

**File:** `gui.tcl:888`

This is the single entry point for all screensaver activation. It has four
guard clauses that can cause an early return:

```
show_going_to_sleep_page
  |
  |-- Guard 1: Scheduler forced-awake window active?
  |     YES -> delay_screen_saver, return
  |
  |-- Guard 2: Machine not Idle and not Refill?
  |     YES -> delay_screen_saver, return
  |
  |-- Guard 3: App updating?
  |     YES -> delay_screen_saver, return
  |
  |-- Guard 4: Firmware updating?
  |     YES -> delay_screen_saver, return
  |
  |-- Guard 5: Already on "sleep" or "saver" page?
  |     YES -> return (no delay_screen_saver!)
  |
  |-- page_display_change(current_context, "saver")
  |-- start_sleep()
```

**Critical detail:** Guards 1-4 call `delay_screen_saver` before returning,
which reschedules the sleep timer. Guard 5 simply returns with no rescheduling.

**Critical detail for plugin interceptors:** When guards 1-4 trigger, the
function returns without any page transition. If a plugin modified `::settings`
before calling this function, those modifications persist even though no saver
page was loaded.

### 2.3 The page transition: `dui page load`

**File:** `dui.tcl:6364`

`page_display_change` is a thin wrapper that calls `dui page load`. The
internal execution order within `dui page load` is critical:

```
dui page load "saver"
  |
  |-- [1] delay_screen_saver (line 6374)
  |       Resets the sleep timer on every page load.
  |
  |-- [2] General load actions (line 6386)
  |       Runs actions registered with: dui page add_action {} load ...
  |       Includes:
  |         - ::adjust_machine_nextpage
  |         - ::page_onload  <-- restores app_brightness for non-saver pages
  |
  |-- [3] Early exit if already on this page (line 6401)
  |
  |-- [4] Page-specific load actions (line 6435)
  |       Runs actions registered with: dui page add_action saver load ...
  |       Includes:
  |         - ::saver_page_onload  <-- READS ::settings, SETS BRIGHTNESS
  |
  |-- [5] Page stack management (line 6462)
  |
  |-- [6] Context update (line 6487-6488)
  |       set current_page $page_to_show
  |       set ::de1(current_context) $page_to_show
  |       ^^ THIS IS AFTER ALL LOAD ACTIONS ^^
  |
  |-- [7] Hide actions for old page (line 6507)
  |       Run via "after idle" -- deferred to next event loop
  |
  |-- [8] Show/hide canvas items, widget visibility (rest of proc)
```

### 2.4 The brightness decision: `saver_page_onload`

**File:** `utils.tcl:478`

```tcl
proc saver_page_onload { page_to_hide page_to_show } {
    if {[ifexists ::exit_app_on_sleep] == 1} {
        get_set_tablet_brightness 0
        close_all_ble_and_exit
    } else {
        if {$::settings(screen_saver_change_interval) == 0} {
            display_brightness 0          ;# BLACK SCREEN
        } else {
            display_brightness $::settings(saver_brightness)
        }
        borg systemui $::android_full_screen_flags
    }
}
```

This is the **sole decision point** for saver brightness. The logic:
- If `screen_saver_change_interval == 0`: brightness is forced to 0 (black).
  The `saver_brightness` setting is completely ignored.
- If `screen_saver_change_interval > 0`: brightness is set to `saver_brightness`.

### 2.5 Machine sleep: `start_sleep`

**File:** `machine.tcl:1109`

Called by `show_going_to_sleep_page` after the page transition. Actions:
1. Fan threshold workaround for firmware bug
2. Additional guards (app updating, firmware updating) -- can bail with `delay_screen_saver`
3. `change_screen_saver_img` -- loads a random saver image
4. `stop_screen_saver_timer` -- cancels the sleep timer (we're already asleep)
5. `de1_send_state "go to sleep"` -- tells the DE1 hardware to enter sleep
6. Disconnects scale if configured
7. On non-Android (simulator): fakes GoingToSleep/Sleep state transitions
8. If `lock_screen_during_screensaver`: `sdltk screensaver on`

---

## 3. Waking Event Chain

### 3.1 User taps the saver page

Skins register a full-screen button on the saver page. Typical handler:

```tcl
add_de1_button "saver" {
    set_next_page off off
    page_show off
    start_idle
}
```

### 3.2 `start_idle`

**File:** `machine.tcl:1011`

1. `sdltk screensaver off` -- removes OS-level touch lock
2. If DE1 not connected: fakes Idle state, attempts BLE reconnect
3. `de1_send_state "go idle"` -- tells DE1 hardware to wake up
4. Re-enables scale LCD

### 3.3 DE1 reports Idle state

The BLE state change callback triggers:

```
update_de1_state -> skins_page_change_due_to_de1_state_change
  -> page_change_due_to_de1_state_change (gui.tcl:49)
    -> if "Idle": page_display_change(current_context, "off")
```

### 3.4 Brightness restoration on wake

`page_display_change "off"` triggers `dui page load "off"`, which runs:

1. **`page_onload`** (`utils.tcl:494`): Since `page_to_show` is `"off"` (not
   `"saver"`), it calls `display_brightness $::settings(app_brightness)`.
   **This automatically restores full brightness.** Plugins do not need to
   manage brightness on wake.

2. **`::de1(current_context)`** is set to `"off"` (line 6488).

---

## 4. Brightness Control Stack

### 4.1 `display_brightness`

**File:** `gui.tcl:1476`

```tcl
proc display_brightness {percentage} {
    set percentage [check_battery_low $percentage]
    get_set_tablet_brightness $percentage
}
```

Applies a battery-low override, then delegates to the tablet brightness API.

### 4.2 `get_set_tablet_brightness`

**File:** `utils.tcl:1192`

```tcl
proc get_set_tablet_brightness { {setting ""} } {
    set actual [borg brightness]
    if {$setting == ""} {
        return $actual
    }
    if {$actual != $setting} {
        borg brightness $setting
        borg systemui $::android_full_screen_flags
    }
}
```

- `borg brightness` is the low-level Android API call.
- Only calls the API if the value actually changed (optimization).
- Hides the Android brightness slider bar after changing.

### 4.3 When brightness is set

| Event | Brightness value | Source |
|---|---|---|
| Any non-saver page loads | `$::settings(app_brightness)` | `page_onload` (utils.tcl:494) |
| Saver page loads, interval == 0 | `0` (hardcoded) | `saver_page_onload` (utils.tcl:483) |
| Saver page loads, interval > 0 | `$::settings(saver_brightness)` | `saver_page_onload` (utils.tcl:487) |

---

## 5. Screensaver Image Rotation

**File:** `gui.tcl:939`

`change_screen_saver_img` loads a random `.jpg` from the saver directory and
optionally schedules the next rotation:

```tcl
proc change_screen_saver_img {} {
    # ... loads random image ...

    if {$::settings(screen_saver_change_interval) != 0} {
        set ::change_screen_saver_image_handle \
            [after [expr {60 * 1000 * $::settings(screen_saver_change_interval)}] \
                change_screen_saver_img]
    }
}
```

When `screen_saver_change_interval == 0`, one image is still loaded (it will
be invisible at brightness 0), but no rotation timer is scheduled.

The saver image directory defaults to `de1plus/saver/` but can be overridden
by plugins (e.g. `DPx_Screen_Saver` sets it to `~/MySaver/`).

---

## 6. Critical Timing for Plugin Developers

### 6.1 The ordering problem

Within `dui page load`, the execution order is:

1. `saver_page_onload` runs -- reads `::settings`, sets brightness
2. `::de1(current_context)` is updated

This means:
- **A `trace` on `::de1(current_context)` fires AFTER brightness is already
  set.** You cannot use a context trace to control the initial saver brightness.
  You can only use it to override brightness after the fact.
- **To control what brightness `saver_page_onload` applies, you must modify
  `::settings(screen_saver_change_interval)` and/or `::settings(saver_brightness)`
  BEFORE the page transition occurs.**

### 6.2 The early-return trap

`show_going_to_sleep_page` has four early-return paths where it calls
`delay_screen_saver` and returns without any page transition. If your plugin
modifies `::settings` before calling `show_going_to_sleep_page`, and the
function returns early:

- Your modified settings persist in `::settings`
- No page transition occurred, so `saver_page_onload` never ran
- The next time the sleep timer fires, `show_going_to_sleep_page` is called
  again -- if your plugin uses conditional save/restore logic, it may read
  the already-modified values and lose the originals

**Mitigation:** Use idempotent settings management. Always write the correct
values (either dark or normal) before every call, rather than trying to
save-before-modify and conditionally restore.

### 6.3 The `delay_screen_saver` callback is a string

```tcl
set ::screen_saver_alarm_handle \
    [after [expr {60 * 1000 * $::settings(screen_saver_delay)}] \
        "show_going_to_sleep_page"]
```

The callback is the **string** `"show_going_to_sleep_page"`, which resolves at
call time. If a plugin has renamed `::show_going_to_sleep_page` (intercept
pattern), the `after` callback will invoke the plugin's replacement proc, not
the original. This is the desired behavior for intercept-based plugins.

### 6.4 The `rename` intercept pattern

Multiple de1app plugins use this pattern to intercept core functions:

```tcl
rename ::show_going_to_sleep_page ::original_show_going_to_sleep_page
proc ::show_going_to_sleep_page {} {
    # plugin logic here
    ::original_show_going_to_sleep_page
}
```

This is the standard approach. Other plugins that use it:
- `skip_first_step_notice` (renames `append_live_data_to_espresso_chart`)
- `history_exclusion_filter` (renames `reset_gui_starting_espresso`, `save_this_espresso_to_history`)
- `Graphical_Flow_Calibrator` (renames `page_show`, `select_profile`, `delete_selected_profile`)
- `D_Flow_Espresso_Profile` (renames several chart/profile procs)

### 6.5 Avoiding recursive intercepts

If your plugin's timer or manual activation path needs to trigger sleep, call
`::original_show_going_to_sleep_page` directly -- not the intercepted version.
Otherwise you get a recursive call chain where the intercept logic runs twice,
potentially corrupting state.

### 6.6 The `sdltk screensaver` layer is separate

`sdltk screensaver on/off` is an OS-level screen lock that prevents touch
events from reaching the app. It is orthogonal to display brightness:

- Enabled in `start_sleep` when `lock_screen_during_screensaver == 1`
- Disabled in `start_idle` (and `start_schedIdle`)
- Plugins controlling brightness do not need to interact with this

---

## 7. Page Action Registration

**File:** `utils.tcl:37-40`

```tcl
dui page add_action off load ::off_page_onload
dui page add_action saver load ::saver_page_onload
dui page add_action {} load ::adjust_machine_nextpage
dui page add_action {} load ::page_onload
```

- Actions registered with `{}` (empty page) run for ALL page loads.
- Actions registered with a specific page name run only for that page.
- General actions run first (line 6386), then page-specific actions (line 6435).
- Actions receive `(page_to_hide, page_to_show)` as arguments.
- Returning `0` from an action aborts the page load.
- Returning a string changes the target page.

---

## 8. Complete Sleep/Wake Sequence Diagram

```
GOING TO SLEEP:

  User idle for screen_saver_delay minutes
    |
    v
  delay_screen_saver's "after" fires
    |
    v
  show_going_to_sleep_page()
    |-- [guard: scheduler awake?] --> delay_screen_saver --> return
    |-- [guard: not idle?]        --> delay_screen_saver --> return
    |-- [guard: app updating?]    --> delay_screen_saver --> return
    |-- [guard: fw updating?]     --> delay_screen_saver --> return
    |-- [guard: already on saver?] --> return
    |
    v
  page_display_change(ctx, "saver")
    |
    v
  dui page load "saver"
    |-- delay_screen_saver (reset timer)
    |-- page_onload: skip brightness (page is "saver")
    |-- saver_page_onload:
    |     if interval == 0: display_brightness 0
    |     else: display_brightness $saver_brightness
    |-- set ::de1(current_context) = "saver"   <-- AFTER brightness set
    |
    v
  start_sleep()
    |-- change_screen_saver_img (load random image)
    |-- stop_screen_saver_timer
    |-- de1_send_state "go to sleep"
    |-- [optional] sdltk screensaver on


WAKING UP:

  User taps saver page
    |
    v
  start_idle()
    |-- sdltk screensaver off
    |-- de1_send_state "go idle"
    |
    v
  DE1 reports Idle via BLE
    |
    v
  page_change_due_to_de1_state_change("Idle")
    |
    v
  page_display_change(ctx, "off")
    |
    v
  dui page load "off"
    |-- delay_screen_saver (restart inactivity timer)
    |-- page_onload: display_brightness $app_brightness  <-- auto-restore
    |-- set ::de1(current_context) = "off"
```
