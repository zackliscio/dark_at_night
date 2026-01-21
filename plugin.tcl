set plugin_name "dark_at_night"

namespace eval ::plugins::${plugin_name} {

    # Plugin metadata - shown in plugin selection page
    variable author "Zack Liscio"
    variable contact "github.com/zackliscio"
    variable version 2.3
    variable description "Activates screensaver/sleep mode with dimmed screen during dark hours. Machine goes to standby with black screen instead of bright screensaver images."
    variable name "Dark At Night"

    # Plugin settings
    variable settings
    array set settings {}

    # Internal state variables
    variable timer_handle ""
    variable is_dark_mode 0
    variable saved_saver_interval 0
    variable saved_saver_brightness 100

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

    # Activate screensaver with dimmed screen (for auto-schedule)
    proc activate_dark_mode {} {
        variable settings
        variable is_dark_mode
        variable saved_saver_interval
        variable saved_saver_brightness

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
            msg -DEBUG [namespace current] "Not activating - machine is active: $::de1_num_state($::de1(state))"
            return
        }

        # Don't activate during scheduler's forced-awake window
        if {[info exists ::settings(scheduler_enable)] && $::settings(scheduler_enable) == 1} {
            if {[info exists ::settings(scheduler_wake)] && [info exists ::settings(scheduler_sleep)]} {
                set wake [current_alarm_time $::settings(scheduler_wake)]
                set sleep [current_alarm_time $::settings(scheduler_sleep)]
                if {[clock seconds] > $wake && [clock seconds] < $sleep} {
                    msg -DEBUG [namespace current] "Not activating - during scheduled forced-awake time"
                    return
                }
            }
        }

        # Only activate on idle pages
        if {[info exists ::de1(current_context)]} {
            set ctx $::de1(current_context)
            if {$ctx != "off" && $ctx != "saver" && ![string match "off_*" $ctx]} {
                msg -DEBUG [namespace current] "Not activating - not on idle page (current page: $ctx)"
                return
            }
        }

        # Save current screensaver settings
        if {[info exists ::settings(screen_saver_change_interval)]} {
            set saved_saver_interval $::settings(screen_saver_change_interval)
        } else {
            set saved_saver_interval 5
        }
        
        if {[info exists ::settings(saver_brightness)]} {
            set saved_saver_brightness $::settings(saver_brightness)
        } else {
            set saved_saver_brightness 100
        }
        
        # Set to black screensaver mode
        set ::settings(screen_saver_change_interval) 0
        set ::settings(saver_brightness) $settings(brightness_level)
        
        # Activate the screensaver (puts machine to sleep AND shows black screen)
        msg -INFO [namespace current] "Auto-activating BLACK screensaver (interval=0, brightness=$settings(brightness_level)%)"
        show_going_to_sleep_page
        
        # Restore settings after wake
        after 3000 {
            set ::settings(screen_saver_change_interval) $::plugins::dark_at_night::saved_saver_interval
            set ::settings(saver_brightness) $::plugins::dark_at_night::saved_saver_brightness
            msg "Dark At Night: Restored screensaver settings (auto-schedule)"
        }
        
        set is_dark_mode 1
    }

    # Deactivate dark mode (restore screensaver settings)
    proc deactivate_dark_mode {} {
        variable is_dark_mode
        variable saved_saver_interval
        variable saved_saver_brightness

        # Don't deactivate if not in dark mode
        if {$is_dark_mode == 0} {
            return
        }

        # Restore screensaver settings
        if {[info exists saved_saver_interval]} {
            set ::settings(screen_saver_change_interval) $saved_saver_interval
            msg -INFO [namespace current] "Restored screen_saver_change_interval to $saved_saver_interval"
        }
        
        if {[info exists saved_saver_brightness]} {
            set ::settings(saver_brightness) $saved_saver_brightness
            msg -INFO [namespace current] "Restored saver_brightness to $saved_saver_brightness%"
        }
        
        set is_dark_mode 0
        
        msg -INFO [namespace current] "Dark mode deactivated"
    }

    # Intercept sleep button to activate screensaver with black screen during dark hours
    proc intercepted_start_sleep {} {
        variable settings
        variable saved_saver_interval
        variable saved_saver_brightness
        
        msg "Dark At Night: Sleep button pressed"
        
        # Check if plugin is enabled
        set enabled 0
        if {[info exists settings(enabled)]} {
            set enabled $settings(enabled)
        }
        
        if {$enabled != 1} {
            msg "Dark At Night: Plugin disabled - normal sleep"
            ::original_start_sleep
            return
        }
        
        # Check if we're in dark window
        if {[catch {
            set in_window [is_in_dark_window]
            msg "Dark At Night: In dark window: $in_window"
            
            if {$in_window} {
                msg "Dark At Night: Activating screensaver with BLACK screen (dark hours)"
                
                # Save current screensaver settings
                if {[info exists ::settings(screen_saver_change_interval)]} {
                    set saved_saver_interval $::settings(screen_saver_change_interval)
                } else {
                    set saved_saver_interval 5
                }
                
                if {[info exists ::settings(saver_brightness)]} {
                    set saved_saver_brightness $::settings(saver_brightness)
                } else {
                    set saved_saver_brightness 100
                }
                
                # Set to black screensaver mode (interval=0 means black screen)
                set ::settings(screen_saver_change_interval) 0
                set ::settings(saver_brightness) $settings(brightness_level)
                
                msg "Dark At Night: Set screensaver to BLACK mode (interval=0, brightness=$settings(brightness_level))"
                
                # Now activate normal sleep/screensaver (machine goes to standby, screen is black)
                ::original_start_sleep
                
                # Restore original settings after wake (delay to let screensaver activate first)
                after 3000 {
                    set ::settings(screen_saver_change_interval) $::plugins::dark_at_night::saved_saver_interval
                    set ::settings(saver_brightness) $::plugins::dark_at_night::saved_saver_brightness
                    msg "Dark At Night: Restored screensaver settings"
                }
                return
            }
        } err]} {
            msg "Dark At Night: Error checking window: $err"
        }
        
        # Default: normal sleep with normal screensaver
        msg "Dark At Night: Normal screensaver (outside dark hours)"
        ::original_start_sleep
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
            msg -DEBUG [namespace current] "Auto-schedule check: Plugin disabled"
            # If dark mode is active, deactivate it
            deactivate_dark_mode
            
            # Reschedule for next check (keep monitoring in case plugin is re-enabled)
            set timer_handle [after 60000 ::plugins::dark_at_night::check_dark_mode_schedule]
            return
        }

        # Check if we're in the dark window
        catch {
            set in_window [is_in_dark_window]
            set current_time [time_format [clock seconds]]
            
            msg -DEBUG [namespace current] "Auto-schedule check: in_window=$in_window, time=$current_time, window=[format_alarm_time $settings(start_time)]-[format_alarm_time $settings(end_time)]"
            
            if {$in_window} {
                # We should be in dark mode
                msg -DEBUG [namespace current] "Auto-schedule: Should be in dark mode - activating"
                activate_dark_mode
            } else {
                # We should not be in dark mode (unless manual sleep is active)
                if {$manual_sleep_active == 0} {
                    msg -DEBUG [namespace current] "Auto-schedule: Should not be in dark mode - deactivating"
                    deactivate_dark_mode
                } else {
                    msg -DEBUG [namespace current] "Auto-schedule: Manual sleep active, not deactivating"
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

        # If we're in dark mode and user navigates away from idle/screensaver pages, restore brightness
        # Check if new page is NOT an off variant or saver
        if {$is_dark_mode == 1} {
            if {$page_to_show != "off" && $page_to_show != "saver" && ![string match "off_*" $page_to_show]} {
                deactivate_dark_mode
            }
        }
    }

    # Helper proc for scale widgets - they pass their value as a parameter
    proc on_slider_change {args} {
        save_plugin_settings dark_at_night
    }

    # Button press handler (called by skin-specific buttons)
    proc dark_button_pressed {} {
        # Play sound feedback
        catch {
            say [translate {Dark}] $::settings(sound_button_out)
        }
        # Activate dark mode
        manual_dark_mode
    }

    # Manual dark mode activation (from button press)
    proc manual_dark_mode {} {
        variable settings
        variable saved_saver_interval
        variable saved_saver_brightness
        
        msg "Dark At Night: Manual button pressed - activating screensaver with black screen"
        
        # Save current screensaver settings
        if {[info exists ::settings(screen_saver_change_interval)]} {
            set saved_saver_interval $::settings(screen_saver_change_interval)
        } else {
            set saved_saver_interval 5
        }
        
        if {[info exists ::settings(saver_brightness)]} {
            set saved_saver_brightness $::settings(saver_brightness)
        } else {
            set saved_saver_brightness 100
        }
        
        # Set to black screensaver mode
        set ::settings(screen_saver_change_interval) 0
        set ::settings(saver_brightness) 0
        
        msg "Dark At Night: Set screensaver to BLACK mode (interval=0, brightness=0)"
        
        # Activate screensaver (puts machine to sleep)
        show_going_to_sleep_page
        
        # Restore settings after wake
        after 3000 {
            set ::settings(screen_saver_change_interval) $::plugins::dark_at_night::saved_saver_interval
            set ::settings(saver_brightness) $::plugins::dark_at_night::saved_saver_brightness
            msg "Dark At Night: Restored screensaver settings"
        }
        
        msg "Dark At Night: Screensaver activated with black screen"
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
        add_de1_widget $page_name scale 280 720 {} -from 0 -to 86340 -background #e4d1c1 -borderwidth 1 -bigincrement 3600 -showvalue 0 -resolution 60 -length [rescale_x_skin 800] -width [rescale_y_skin 120] -variable ::plugins::dark_at_night::settings(start_time) -font Helv_10_bold -sliderlength [rescale_x_skin 100] -relief flat -orient horizontal -foreground #FFFFFF -troughcolor #c0c4e1 -borderwidth 0 -highlightthickness 0 -command {::plugins::dark_at_night::on_slider_change}
        add_de1_variable $page_name 280 860 -text "" -font Helv_7 -fill "#7f879a" -anchor "nw" -width 800 -justify "left" -textvariable {[format_alarm_time $::plugins::dark_at_night::settings(start_time)]}

        # End time slider
        add_de1_text $page_name 1380 630 -text [translate "End time (stop dark mode)"] -font Helv_10_bold -fill "#444444" -anchor "nw"
        add_de1_widget $page_name scale 1380 720 {} -from 0 -to 86340 -background #e4d1c1 -borderwidth 1 -bigincrement 3600 -showvalue 0 -resolution 60 -length [rescale_x_skin 800] -width [rescale_y_skin 120] -variable ::plugins::dark_at_night::settings(end_time) -font Helv_10_bold -sliderlength [rescale_x_skin 100] -relief flat -orient horizontal -foreground #FFFFFF -troughcolor #c0c4e1 -borderwidth 0 -highlightthickness 0 -command {::plugins::dark_at_night::on_slider_change}
        add_de1_variable $page_name 1380 860 -text "" -font Helv_7 -fill "#7f879a" -anchor "nw" -width 800 -justify "left" -textvariable {[format_alarm_time $::plugins::dark_at_night::settings(end_time)]}

        # Brightness level slider
        add_de1_text $page_name 280 950 -text [translate "Screen brightness during dark mode"] -font Helv_10_bold -fill "#444444" -anchor "nw"
        add_de1_widget $page_name scale 280 1020 {} -from 0 -to 100 -background #e4d1c1 -borderwidth 1 -bigincrement 10 -showvalue 0 -resolution 1 -length [rescale_x_skin 800] -width [rescale_y_skin 120] -variable ::plugins::dark_at_night::settings(brightness_level) -font Helv_10_bold -sliderlength [rescale_x_skin 100] -relief flat -orient horizontal -foreground #FFFFFF -troughcolor #c0c4e1 -borderwidth 0 -highlightthickness 0 -command {::plugins::dark_at_night::on_slider_change}
        add_de1_variable $page_name 280 1150 -text "" -font Helv_7 -fill "#7f879a" -anchor "nw" -textvariable {$::plugins::dark_at_night::settings(brightness_level)%}

        # Info text about sleep button behavior
        add_de1_text $page_name 1380 980 -text [translate "Tip: The sleep button activates dark mode during dark hours"] -font Helv_7 -fill "#7f879a" -anchor "nw" -justify "left" -width 800

        # Current time display
        add_de1_variable $page_name 1280 420 -text "" -font Helv_8 -fill "#7f879a" -anchor "center" -textvariable {[translate "Current time:"] [time_format [clock seconds]]}

        return $page_name
    }

    # Preload - called for all plugins during UI startup
    proc preload {} {
        variable settings

        # Build the settings UI
        set page_name [build_ui]

        return $page_name
    }

    # Main - plugin initialization
    proc main {} {
        variable settings
        variable timer_handle

        msg "========================================="
        msg "DARK AT NIGHT PLUGIN v2.0 INITIALIZING"
        msg "========================================="
        
        # Log current settings
        if {[info exists settings(enabled)]} {
            msg "Settings: enabled=$settings(enabled)"
            msg "Start time: [format_alarm_time $settings(start_time)]"
            msg "End time: [format_alarm_time $settings(end_time)]"
            msg "Brightness: $settings(brightness_level)%"
        } else {
            msg "WARNING: Settings not loaded!"
        }

        # Load skin-specific integration code (following DYE plugin pattern)
        # This allows each skin to position the dark mode button appropriately
        regsub -all { } $::settings(skin) "_" skin
        set skin_src_fn "[plugin_directory]/dark_at_night/setup_${skin}.tcl"
        
        if { [file exists $skin_src_fn] } {
            msg -INFO [namespace current] "Loading skin-specific setup: $skin_src_fn"
            source $skin_src_fn
        } else {
            msg -INFO [namespace current] "No skin-specific setup found for: $skin"
        }
        
        # Call skin-specific UI setup function if it exists
        if { [namespace which -command "::plugins::dark_at_night::setup_ui_$skin"] ne "" } {
            msg -INFO [namespace current] "Calling setup_ui_$skin"
            ::plugins::dark_at_night::setup_ui_$skin
        } else {
            # Fallback: Add button in a generic location if no skin-specific setup exists
            msg -INFO [namespace current] "Using fallback button placement (no skin-specific setup)"
            catch {
                # Use old-style add_de1_button for skins without DUI support
                # Position: 73% from left, 4% from top (generic top-right area)
                set btn_x1 [expr {int([winfo width .can] * 0.73)}]
                set btn_y1 [expr {int([winfo height .can] * 0.04)}]
                set btn_x2 [expr {int([winfo width .can] * 0.81)}]
                set btn_y2 [expr {int([winfo height .can] * 0.10)}]
                
                set text_x [expr {($btn_x1 + $btn_x2) / 2}]
                set text_y [expr {($btn_y1 + $btn_y2) / 2}]
                
                add_de1_text "off off_zoomed" $text_x $text_y -text "\u263E" -font Helv_20_bold -fill "#7f879a" -anchor "center" -tags dark_at_night_moon_icon
                add_de1_button "off off_zoomed" {
                    say [translate {Dark}] $::settings(sound_button_in)
                    ::plugins::dark_at_night::manual_dark_mode
                } $btn_x1 $btn_y1 $btn_x2 $btn_y2 "" -tags dark_at_night_button
                
                msg -INFO [namespace current] "Added fallback dark mode button at ($btn_x1,$btn_y1) to ($btn_x2,$btn_y2)"
            }
        }

        # Intercept the start_sleep function to add dark mode behavior
        # Save the original function and replace it with our wrapper
        if {[info commands ::original_start_sleep] eq ""} {
            rename ::start_sleep ::original_start_sleep
            proc ::start_sleep {} {
                ::plugins::dark_at_night::intercepted_start_sleep
            }
            msg -INFO [namespace current] "Intercepted start_sleep function"
        }

        # Register page change handler to restore brightness on user interaction
        # Using trace on the current_context variable
        catch {
            trace add variable ::de1(current_context) write ::plugins::dark_at_night::on_page_change_trace
        }

        # Do an initial check after a short delay (avoid startup race conditions)
        after 2000 ::plugins::dark_at_night::check_dark_mode_schedule

        # NOTE: UI registration is already done in preload() which returns the page name
        # The plugin system automatically stores it in ${plugin}::ui_entry
        # No need to call 'plugins gui' here or it will create duplicate UI elements
        
        msg "========================================="
        msg "DARK AT NIGHT PLUGIN INITIALIZED!"
        msg "Look for button in BOTTOM-RIGHT corner"
        msg "========================================="
    }

    # Trace handler for page changes
    proc on_page_change_trace {varname key op} {
        on_page_change "" $::de1(current_context)
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

        # Call skin-specific cleanup if it exists
        regsub -all { } $::settings(skin) "_" skin
        if { [namespace which -command "::plugins::dark_at_night::cleanup_ui_$skin"] ne "" } {
            msg -INFO [namespace current] "Calling cleanup_ui_$skin"
            ::plugins::dark_at_night::cleanup_ui_$skin
        } else {
            # Fallback: Remove generic button elements
            catch {
                .can delete dark_at_night_moon_icon
                .can delete dark_at_night_button
            }
        }

        # Restore original start_sleep function
        if {[info commands ::original_start_sleep] ne ""} {
            rename ::start_sleep ""
            rename ::original_start_sleep ::start_sleep
            msg -INFO [namespace current] "Restored original start_sleep function"
        }

        # Remove trace
        catch {
            trace remove variable ::de1(current_context) write ::plugins::dark_at_night::on_page_change_trace
        }
    }
}

