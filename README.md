# Dark At Night Plugin

Automatically dims the tablet screen to black at specified times each day. The existing sleep button intelligently switches between screensaver and dark mode based on the time of day.

## Features

- **Time-based Dark Mode**: Automatically dims the screen during configured hours (e.g., 10 PM to 6 AM)
- **Smart Sleep Button**: During dark hours, the sleep button activates dark mode instead of screensaver - one button, context-aware behavior
- **Scheduler-Aware**: Respects the DE1 scheduler's forced-awake window and won't dim during that time
- **Customizable Brightness**: Set the brightness level during dark mode (0-100%, default 0 for completely black)
- **Touch to Wake**: Touching the screen restores normal brightness, just like the standard screensaver
- **Smart Activation**: Only activates when machine is idle or asleep, never during active use

## Installation

1. The plugin is already installed in `de1plus/plugins/dark_at_night/`
2. Enable it from the DE1 app: Settings → Extensions → Dark At Night
3. Configure your preferences in the plugin settings page

## Settings

- **Enable time-based dark mode**: Toggle on/off for automatic time-based dimming and smart sleep button behavior
- **Start time**: When to begin dark mode window (default: 10:00 PM / 22:00)
- **End time**: When to end dark mode window (default: 6:00 AM / 06:00)
- **Screen brightness during dark mode**: Brightness level 0-100% (default: 0%)

## Usage

### Automatic Time-based Mode
1. Enable the plugin and set your preferred start/end times
2. The screen will automatically dim at the start time each day
3. Touch the screen anytime to wake and restore brightness
4. Brightness automatically restores at the end time

### Smart Sleep Button
The existing sleep button (location varies by skin) now behaves intelligently:
- **Outside dark hours**: Normal behavior - activates screensaver
- **During dark hours**: Activates dark mode (black screen) instead
- **Wake up**: Touch anywhere on the screen to restore brightness

No extra buttons needed - the sleep button just does the right thing based on time of day!

## Technical Details

- **Namespace**: `::plugins::dark_at_night`
- **Settings file**: `settings.tdb`
- **Check interval**: Every 60 seconds
- **Touch-to-wake**: Automatic via existing page navigation handlers

## Default Settings

```tcl
enabled 0                  # Plugin disabled by default
start_time 61200          # 5:00 PM (17:00)
end_time 21600            # 6:00 AM (06:00)
brightness_level 0        # Completely black
```

## Notes

- The plugin respects machine state and won't activate during espresso extraction, steaming, etc.
- Works by intercepting the `start_sleep` function to add smart time-based behavior
- **Scheduler-aware**: Won't auto-dim during the scheduler's forced-awake window (but manual sleep button still works)
- Time window can cross midnight (e.g., 10 PM to 6 AM)
- Brightness is automatically restored when navigating away from the idle screen
- The sleep button during dark hours works even during forced-awake time if you want to manually dim the screen

## Author

Zack Liscio (github.com/zackliscio)

## Version

1.3

## Changelog

### v1.3
- **MAJOR IMPROVEMENT:** Removed separate manual button in favor of smart sleep button interception
- Sleep button now intelligently switches between screensaver (wake hours) and dark mode (dark hours)
- Cleaner UI with no additional buttons - uses existing sleep button location (skin-dependent)
- Plugin intercepts `start_sleep` function to add time-aware behavior
- Removed `show_manual_button` setting (no longer needed)
- Updated default times to 10 PM - 6 AM (more typical sleep hours)

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

