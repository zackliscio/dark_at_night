# Dark At Night Plugin

Automatically dims the tablet screen to black at specified times each day, with optional manual sleep button. Touch the screen to wake normally.

## Features

- **Time-based Dark Mode**: Automatically dims the screen during configured hours (e.g., 5 PM to 6 AM)
- **Scheduler-Aware**: Respects the DE1 scheduler's forced-awake window and won't dim during that time
- **Customizable Brightness**: Set the brightness level during dark mode (0-100%, default 0 for completely black)
- **Manual Sleep Button**: Optional button on the idle screen to immediately activate dark mode
- **Touch to Wake**: Touching the screen restores normal brightness, just like the standard screensaver
- **Smart Activation**: Only activates when machine is idle or asleep, never during active use

## Installation

1. The plugin is already installed in `de1plus/plugins/dark_at_night/`
2. Enable it from the DE1 app: Settings → Extensions → Dark At Night
3. Configure your preferences in the plugin settings page

## Settings

- **Enable time-based dark mode**: Toggle on/off for automatic time-based dimming
- **Start time**: When to begin dark mode (default: 5:00 PM / 17:00)
- **End time**: When to stop dark mode (default: 6:00 AM / 06:00)
- **Screen brightness during dark mode**: Brightness level 0-100% (default: 0%)
- **Show manual sleep button**: Display a moon icon button on the idle screen to manually trigger dark mode

## Usage

### Time-based Mode
1. Enable the plugin and set your preferred start/end times
2. The screen will automatically dim at the start time each day
3. Touch the screen anytime to wake and restore brightness
4. Brightness automatically restores at the end time

### Manual Sleep Button
1. Enable "Show manual sleep button" in settings
2. A small moon icon (🌙) appears in the top-right corner of the idle screen
3. Tap it anytime to immediately dim the screen
4. Touch anywhere to wake and restore brightness

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
show_manual_button 1      # Manual button enabled
```

## Notes

- The plugin respects machine state and won't activate during espresso extraction, steaming, etc.
- Works independently but cooperatively with the standard DE1 screensaver
- **Scheduler-aware**: Won't dim the screen during the scheduler's forced-awake window
- Time window can cross midnight (e.g., 5 PM to 6 AM)
- Brightness is automatically restored when navigating away from the idle screen
- Manual sleep button works even during forced-awake time if you want to dim the screen anyway

## Author

Zack Liscio (github.com/zackliscio)

## Version

1.2

## Changelog

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

