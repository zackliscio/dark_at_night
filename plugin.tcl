set plugin_name "dark_at_night"

namespace eval ::plugins::${plugin_name} {

    # Plugin metadata - shown in plugin selection page
    variable author "Zack Liscio"
    variable contact "github.com/zackliscio"
    variable version 1.1
    variable description "Automatically dims the tablet screen to black at specified times each day, with optional manual sleep button. Touch screen to wake."
    variable name "Dark At Night"

    # Plugin settings
    variable settings
    array set settings {}

    # Internal state variables
    variable timer_handle ""
    variable is_dark_mode 0
    variable stored_brightness 0
    variable manual_sleep_active 0

    # Helper proc to get current time in seconds since midnight
    proc get_seconds_since_midnight {} {
        set now [clock seconds]
        set midnight [clock scan "00:00:00" -base $now]
        return [expr {$now - $midnight}]
    }

    # Check if current time is within dark mode window
    proc is_in_dark_window {} {
        variable settings
        
        set current_seconds [get_seconds_since_midnight]
        set start $settings(start_time)
        set end $settings(end_time)
        
        # Handle case where window crosses midnight
        if {$start > $end} {
            # Window crosses midnight (e.g., 22:00 to 07:00)
            return [expr {$current_seconds >= $start || $current_seconds < $end}]
        } else {
            # Normal window (e.g., 01:00 to 05:00)
            return [expr {$current_seconds >= $start && $current_seconds < $end}]
        }
    }

    # Activate dark mode (dim the screen)
    proc activate_dark_mode {} {
        variable settings
        variable is_dark_mode
        variable stored_brightness
        variable manual_sleep_active

        # Don't activate if already in dark mode
        if {$is_dark_mode == 1} {
            return
        }

        # Check if machine state variables exist and are valid
        if {![info exists ::de1(state)] || ![info exists ::de1_num_state($::de1(state))]} {
            msg -DEBUG [namespace current] "Machine state not yet initialized"
            return
        }

        # Don't activate if machine is actively being used
        if {$::de1_num_state($::de1(state)) != "Idle" && 
            $::de1_num_state($::de1(state)) != "Sleep"} {
            msg -DEBUG [namespace current] "Not activating dark mode - machine is active: $::de1_num_state($::de1(state))"
            return
        }

        # Don't activate during scheduler's forced-awake window (unless manual sleep)
        if {$manual_sleep_active == 0 && [info exists ::settings(scheduler_enable)] && $::settings(scheduler_enable) == 1} {
            if {[info exists ::settings(scheduler_wake)] && [info exists ::settings(scheduler_sleep)]} {
                set wake [current_alarm_time $::settings(scheduler_wake)]
                set sleep [current_alarm_time $::settings(scheduler_sleep)]
                if {[clock seconds] > $wake && [clock seconds] < $sleep} {
                    msg -DEBUG [namespace current] "Not activating dark mode - during scheduled forced-awake time"
                    return
                }
            }
        }

        # Don't activate if not on the off page (unless manual sleep)
        if {[info exists ::de1(current_context)] && $::de1(current_context) != "off" && $manual_sleep_active == 0} {
            return
        }

        # Store current brightness to restore later
        if {[info exists ::settings(app_brightness)]} {
            set stored_brightness $::settings(app_brightness)
        } else {
            set stored_brightness 50
        }
        
        # Dim the screen
        catch {
            display_brightness $settings(brightness_level)
            set is_dark_mode 1
            msg -INFO [namespace current] "Dark mode activated (brightness: $settings(brightness_level)%)"
        }
    }

    # Deactivate dark mode (restore brightness)
    proc deactivate_dark_mode {} {
        variable is_dark_mode
        variable stored_brightness
        variable manual_sleep_active

        # Don't deactivate if not in dark mode
        if {$is_dark_mode == 0} {
            return
        }

        # Restore previous brightness
        catch {
            if {$stored_brightness > 0} {
                display_brightness $stored_brightness
            } elseif {[info exists ::settings(app_brightness)]} {
                display_brightness $::settings(app_brightness)
            } else {
                display_brightness 50
            }
        }
        
        set is_dark_mode 0
        set manual_sleep_active 0
        
        msg -INFO [namespace current] "Dark mode deactivated (brightness restored to $stored_brightness%)"
    }

    # Manual sleep button handler
    proc manual_sleep {} {
        variable manual_sleep_active
        variable settings
        
        msg -INFO [namespace current] "Manual sleep button pressed"
        
        set manual_sleep_active 1
        activate_dark_mode
    }

    # Periodic check for time-based dark mode
    proc check_dark_mode_schedule {} {
        variable settings
        variable timer_handle
        variable manual_sleep_active

        # Cancel any existing timer first
        if {$timer_handle != ""} {
            catch {after cancel $timer_handle}
        }

        # Only run if plugin is enabled
        if {![info exists settings(enabled)] || $settings(enabled) != 1} {
            # If dark mode is active, deactivate it
            deactivate_dark_mode
            
            # Reschedule for next check (keep monitoring in case plugin is re-enabled)
            set timer_handle [after 60000 ::plugins::dark_at_night::check_dark_mode_schedule]
            return
        }

        # Check if we're in the dark window
        catch {
            set in_window [is_in_dark_window]
            
            if {$in_window} {
                # We should be in dark mode
                activate_dark_mode
            } else {
                # We should not be in dark mode (unless manual sleep is active)
                if {$manual_sleep_active == 0} {
                    deactivate_dark_mode
                }
            }
        }

        # Schedule next check in 60 seconds
        set timer_handle [after 60000 ::plugins::dark_at_night::check_dark_mode_schedule]
    }

    # Hook into page changes to restore brightness when user interacts
    proc on_page_change {page_to_hide page_to_show} {
        variable is_dark_mode
        variable manual_sleep_active

        # If we're in dark mode and user navigates away from off page, restore brightness
        if {$is_dark_mode == 1 && $page_to_show != "off" && $page_to_show != "saver"} {
            deactivate_dark_mode
        }
    }

    # Build the settings UI
    proc build_ui {} {
        variable settings

        set page_name "plugin_dark_at_night_page_default"

        # Background image and Done button
        add_de1_page "$page_name" "settings_message.png" "default"
        add_de1_text $page_name 1280 1310 -text [translate "Done"] -font Helv_10_bold -fill "#fAfBff" -anchor "center"
        add_de1_button $page_name {
            say [translate {Done}] $::settings(sound_button_in)
            save_plugin_settings dark_at_night
            page_to_show_when_off extensions
        } 980 1210 1580 1410 ""

        # Headline
        add_de1_text $page_name 1280 300 -text [translate "Dark At Night"] -font Helv_20_bold -width 1200 -fill "#444444" -anchor "center" -justify "center"

        # Enable/disable toggle
        add_de1_text $page_name 280 450 -text [translate "Enable time-based dark mode"] -font Helv_10_bold -fill "#444444" -anchor "nw" -justify "left"
        add_de1_widget $page_name checkbutton 280 520 {} -text "" -indicatoron true -font Helv_10 -bg #FFFFFF -anchor nw -foreground #4e85f4 -variable ::plugins::dark_at_night::settings(enabled) -borderwidth 0 -highlightthickness 0 -command {save_plugin_settings dark_at_night}

        # Start time slider
        add_de1_text $page_name 280 630 -text [translate "Start time (begin dark mode)"] -font Helv_10_bold -fill "#444444" -anchor "nw"
        add_de1_widget $page_name scale 280 720 {} -from 0 -to 86340 -background #e4d1c1 -borderwidth 1 -bigincrement 3600 -showvalue 0 -resolution 60 -length [rescale_x_skin 800] -width [rescale_y_skin 120] -variable ::plugins::dark_at_night::settings(start_time) -font Helv_10_bold -sliderlength [rescale_x_skin 100] -relief flat -orient horizontal -foreground #FFFFFF -troughcolor #c0c4e1 -borderwidth 0 -highlightthickness 0 -command {save_plugin_settings dark_at_night}
        add_de1_variable $page_name 280 860 -text "" -font Helv_7 -fill "#7f879a" -anchor "nw" -width 800 -justify "left" -textvariable {[format_alarm_time $::plugins::dark_at_night::settings(start_time)]}

        # End time slider
        add_de1_text $page_name 1380 630 -text [translate "End time (stop dark mode)"] -font Helv_10_bold -fill "#444444" -anchor "nw"
        add_de1_widget $page_name scale 1380 720 {} -from 0 -to 86340 -background #e4d1c1 -borderwidth 1 -bigincrement 3600 -showvalue 0 -resolution 60 -length [rescale_x_skin 800] -width [rescale_y_skin 120] -variable ::plugins::dark_at_night::settings(end_time) -font Helv_10_bold -sliderlength [rescale_x_skin 100] -relief flat -orient horizontal -foreground #FFFFFF -troughcolor #c0c4e1 -borderwidth 0 -highlightthickness 0 -command {save_plugin_settings dark_at_night}
        add_de1_variable $page_name 1380 860 -text "" -font Helv_7 -fill "#7f879a" -anchor "nw" -width 800 -justify "left" -textvariable {[format_alarm_time $::plugins::dark_at_night::settings(end_time)]}

        # Brightness level slider
        add_de1_text $page_name 280 980 -text [translate "Screen brightness during dark mode"] -font Helv_10_bold -fill "#444444" -anchor "nw"
        add_de1_widget $page_name scale 280 1070 {} -from 0 -to 100 -background #e4d1c1 -borderwidth 1 -bigincrement 10 -showvalue 0 -resolution 1 -length [rescale_x_skin 800] -width [rescale_y_skin 120] -variable ::plugins::dark_at_night::settings(brightness_level) -font Helv_10_bold -sliderlength [rescale_x_skin 100] -relief flat -orient horizontal -foreground #FFFFFF -troughcolor #c0c4e1 -borderwidth 0 -highlightthickness 0 -command {save_plugin_settings dark_at_night}
        add_de1_variable $page_name 280 1200 -text "" -font Helv_7 -fill "#7f879a" -anchor "nw" -textvariable {$::plugins::dark_at_night::settings(brightness_level)%}

        # Manual sleep button toggle
        add_de1_text $page_name 1380 980 -text [translate "Show manual sleep button"] -font Helv_10_bold -fill "#444444" -anchor "nw" -justify "left"
        add_de1_widget $page_name checkbutton 1380 1050 {} -text "" -indicatoron true -font Helv_10 -bg #FFFFFF -anchor nw -foreground #4e85f4 -variable ::plugins::dark_at_night::settings(show_manual_button) -borderwidth 0 -highlightthickness 0 -command {save_plugin_settings dark_at_night; ::plugins::dark_at_night::update_manual_button_visibility}

        # Current time display
        add_de1_variable $page_name 1280 420 -text "" -font Helv_8 -fill "#7f879a" -anchor "center" -textvariable {[translate "Current time:"] [time_format [clock seconds]]}

        return $page_name
    }

    # Preload - called for all plugins during UI startup
    proc preload {} {
        variable settings

        # Build the settings UI
        set page_name [build_ui]

        # Add manual sleep button to the "off" page if enabled
        # This will be shown/hidden based on settings
        # Using a small button in the top-right corner
        add_de1_text "off" 2450 50 -text "🌙" -font Helv_10_bold -fill "#7f879a" -anchor "ne" -tags dark_at_night_manual_button
        add_de1_button "off" {
            ::plugins::dark_at_night::manual_sleep
        } 2300 20 2540 150

        return $page_name
    }

    # Main - plugin initialization
    proc main {} {
        variable settings
        variable timer_handle

        msg -INFO [namespace current] "Dark At Night plugin initializing"
        
        # Log current settings
        if {[info exists settings(enabled)]} {
            msg -INFO [namespace current] "Settings: enabled=$settings(enabled), start=[format_alarm_time $settings(start_time)], end=[format_alarm_time $settings(end_time)], brightness=$settings(brightness_level)%, manual_button=$settings(show_manual_button)"
        }

        # Register page change handler to restore brightness on user interaction
        # Using trace on the current_context variable
        catch {
            trace add variable ::de1(current_context) write ::plugins::dark_at_night::on_page_change_trace
        }

        # Do an initial check after a short delay (avoid startup race conditions)
        after 2000 ::plugins::dark_at_night::check_dark_mode_schedule

        # Show/hide manual button based on settings
        after 2500 ::plugins::dark_at_night::update_manual_button_visibility

        # Register the settings page
        plugins gui dark_at_night [build_ui]
        
        msg -INFO [namespace current] "Dark At Night plugin initialized successfully"
    }

    # Trace handler for page changes
    proc on_page_change_trace {varname key op} {
        on_page_change "" $::de1(current_context)
    }

    # Update visibility of manual sleep button
    proc update_manual_button_visibility {} {
        variable settings
        
        # Use modern DUI approach for show/hide
        if {$settings(show_manual_button) == 1} {
            catch {
                dui item show off dark_at_night_manual_button
            }
        } else {
            catch {
                dui item hide off dark_at_night_manual_button
            }
        }
    }

    # Cleanup when plugin is disabled (future-proofing)
    proc cleanup {} {
        variable timer_handle
        variable is_dark_mode

        msg -INFO [namespace current] "Cleaning up Dark At Night plugin"

        # Cancel timer
        if {$timer_handle != ""} {
            catch {after cancel $timer_handle}
            set timer_handle ""
        }

        # Restore brightness if dark mode is active
        if {$is_dark_mode == 1} {
            deactivate_dark_mode
        }

        # Remove trace
        catch {
            trace remove variable ::de1(current_context) write ::plugins::dark_at_night::on_page_change_trace
        }
    }
}

