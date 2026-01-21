# Dark At Night Plugin

Activates screensaver/sleep mode with a **dimmed/black screen** during dark hours instead of bright screensaver images. Machine goes to standby normally, but screen is black to avoid disturbing sleep.

## Features

- **Screensaver with Black Screen**: Machine goes to sleep/standby normally, but screen is completely black instead of showing bright images
- **Time-based Activation**: During dark hours (default 2 PM - 6 AM), sleep button activates black screensaver
- **Smart Sleep Button**: Outside dark hours, normal colorful screensaver; during dark hours, black screen
- **Scheduler-Aware**: Respects the DE1 scheduler's forced-awake window
- **Customizable Brightness**: Set the screen brightness during sleep (0-100%, default 0 for completely black)
- **Proper Sleep Mode**: Machine actually goes to standby/sleep (turns off heater, etc.) - not just dimming the screen
- **Wake Normally**: Touch screen to wake - everything works as usual
- **Manual Button** (optional): Can be enabled in setup file for instant black screensaver activation

## Installation

1. The plugin is already installed in `de1plus/plugins/dark_at_night/`
2. Enable it from the DE1 app: Settings → Extensions → Dark At Night
3. Configure your preferences in the plugin settings page

## Settings

- **Enable time-based dark mode**: Toggle on/off for automatic time-based dimming and smart sleep button behavior
- **Start time**: When to begin dark mode window (default: 2:00 PM / 14:00)
- **End time**: When to end dark mode window (default: 6:00 AM / 06:00)
- **Screen brightness during dark mode**: Brightness level 0-100% (default: 0%)

## Usage

### Automatic Time-based Sleep
1. Enable the plugin and set your preferred start/end times (default: 2 PM - 6 AM)
2. During dark hours, auto-schedule activates screensaver with black screen
3. Touch the screen anytime to wake
4. Outside dark hours, screensaver returns to normal brightness

### Smart Sleep Button
The existing sleep button now behaves intelligently based on time:
- **Outside dark hours**: Normal screensaver (images at normal brightness)
- **During dark hours**: Black screensaver (0% brightness, no images)
- **Both modes**: Machine properly goes to sleep/standby
- **Wake up**: Touch screen - everything returns to normal

**The key difference:** During dark hours, the screensaver screen is BLACK instead of showing bright images!

### Optional Manual Button

The manual dark mode button is **disabled by default** because it blocks part of the screen. The plugin works great with just the smart sleep button and auto-schedule.

**To re-enable the manual button:**
1. Open `setup_Streamline_Dark.tcl` (or `setup_Streamline.tcl`)
2. Uncomment lines 14-28 (the button creation code)
3. Restart the DE1 app
4. You'll see a "⬛ DARK MODE ⬛" button in the bottom-right corner

## Technical Details

- **Namespace**: `::plugins::dark_at_night`
- **Settings file**: `settings.tdb`
- **Check interval**: Every 60 seconds
- **Touch-to-wake**: Automatic via existing page navigation handlers

## Default Settings

```tcl
enabled 0                  # Plugin disabled by default
start_time 50400          # 2:00 PM (14:00)
end_time 21600            # 6:00 AM (06:00)
brightness_level 0        # Completely black
```

## Notes

- The plugin respects machine state and won't activate during espresso extraction, steaming, etc.
- Works by intercepting the `start_sleep` function to add smart time-based behavior
- **Scheduler-aware**: Won't auto-dim during the scheduler's forced-awake window (but manual sleep button still works)
- Time window can cross midnight (e.g., 2 PM to 6 AM)
- Brightness is automatically restored when navigating away from the idle screen
- The sleep button during dark hours works even during forced-awake time if you want to manually dim the screen

## Author

Zack Liscio (github.com/zackliscio)

## Version

2.3.1

## Changelog

### v2.3.1
- **UI:** Manual button disabled by default (commented out in setup files)
- Button code preserved for easy re-enabling if needed
- Plugin works perfectly with just smart sleep button and auto-schedule

### v2.3
- **CRITICAL FIX:** Now sets `screen_saver_change_interval` to 0 for TRUE black screensaver
- **FIX:** Saves and restores BOTH `screen_saver_change_interval` and `saver_brightness`
- The screensaver has two modes: interval=0 (black screen) or interval>0 (show images)
- We need to set interval=0 to activate black screensaver mode, not just change brightness
- After wake, both settings are restored automatically
- This is the fix that actually makes the screen go BLACK during sleep!
- **UI:** Manual button disabled by default (code commented out but can be re-enabled)

### v2.2
- **MAJOR FIX:** Now actually activates SCREENSAVER/SLEEP MODE (machine goes to standby)
- **CORRECT BEHAVIOR:** Temporarily sets `saver_brightness` to dim/black, then activates screensaver
- Machine properly goes to sleep/standby (heater off, etc.) with black screen
- Manual button now activates screensaver with black screen (not just dimming)
- Auto-schedule now calls `show_going_to_sleep_page` to properly put machine to sleep
- Fixed fundamental misunderstanding of what the plugin should do

### v2.0
- **CRITICAL FIX:** Fixed `rounded_rectangle` error - now uses canvas directly
- **IMPROVEMENT:** Button creation now works on all skins without dependencies
- Manually creates rounded rectangle using canvas ovals and rectangles
- More reliable and compatible across different DE1 app versions

### v1.9
- **SETTINGS:** Changed default start time from 5:00 PM to 2:00 PM for easier testing
- **DEBUGGING:** Added comprehensive logging for sleep button and auto-schedule
- **FIX:** Fixed variable scoping in `intercepted_start_sleep` (variables were inside catch block)
- **IMPROVEMENT:** Better error messages show why dark mode isn't activating
- Logs now show: current time, dark window, whether conditions are met
- Use DE1 app logs to diagnose issues

### v1.8
- **CRITICAL FIX:** Button now actually clickable! Switched from DUI to standard DE1 button system
- Uses `rounded_rectangle` for button background (matches Streamline style)
- More reliable button creation using proven DE1 app methods
- Works consistently across plugin load timing

### v1.7
- **UI FIX:** Fixed overlapping text on settings screen
- Improved layout spacing for better readability
- Shortened info text to fit properly: "Tip: The sleep button activates dark mode during dark hours"
- Fixed DUI button command handler to ensure button clicks work properly

### v1.6
- **MAJOR IMPROVEMENT:** Skin-specific button positioning (following DYE plugin pattern)
- **NEW:** Dedicated setup files for Streamline and Streamline Dark skins
- Button now positioned correctly using each skin's native button system
- Streamline: Uses DUI (Decent User Interface) system with proper styling
- Button appears at (1870, 66) to (2070, 155) - perfectly aligned with Settings/Sleep buttons
- Fallback positioning for skins without specific setup files
- Easier for skin developers to add custom positioning

### v1.5
- **CRITICAL FIX:** Button now appears on zoomed pages (off_zoomed, etc.)
- **CRITICAL FIX:** Auto-dimming now works on all off page variants (off, off_zoomed, off_*, saver)
- **CRITICAL FIX:** Resolution-independent button positioning (works on 2560x1600 and 1280x800)
- **CRITICAL FIX:** Proper button cleanup - removes both icon and button
- **IMPROVEMENT:** Added screensaver brightness override to prevent conflicts
- **IMPROVEMENT:** Added audio feedback when pressing dark mode button
- Button now uses relative positioning (73% width, 4% height from top-left)

### v1.4
- **CRITICAL FIX:** Auto-dimming now works on screensaver page (was only working on "off" page)
- **NEW FEATURE:** Added manual dark mode button on main "off" page (moon icon ☾)
- Manual button allows instant dark mode activation anytime, regardless of schedule
- Both features work together: auto-schedule + manual button for maximum flexibility
- Button positioned to the left of typical sleep button location

### v1.3
- **MAJOR IMPROVEMENT:** Removed separate manual button in favor of smart sleep button interception
- Sleep button now intelligently switches between screensaver (wake hours) and dark mode (dark hours)
- Cleaner UI with no additional buttons - uses existing sleep button location (skin-dependent)
- Plugin intercepts `start_sleep` function to add time-aware behavior
- Removed `show_manual_button` setting (no longer needed)
- Updated default times to 2 PM - 6 AM (for easier testing and daytime use)

### v1.2
- **CRITICAL FIX:** Removed duplicate `build_ui()` call that prevented Settings page from opening
- The UI was being built twice (once in `preload()`, once in `main()`), breaking page registration
- Settings button now works correctly when clicked in Extensions menu

### v1.1
- Fixed critical bug in `add_de1_button` call that prevented plugin from loading
- Added robust error handling with `info exists` checks for all global variables
- Improved initialization timing to avoid startup race conditions
- Added automatic cleanup procedure for proper resource management
- Enhanced visibility control using modern DUI show/hide functions
- Added catch blocks around all critical operations for better stability
- Improved logging with DEBUG and INFO levels
- Fixed manual button visibility toggle to update immediately when settings change
- Better timer management to prevent duplicate timers

### v1.0
- Initial release

