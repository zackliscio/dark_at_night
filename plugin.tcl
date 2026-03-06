set plugin_name "dark_at_night"

namespace eval ::plugins::${plugin_name} {

    variable author "Zack Liscio"
    variable contact "github.com/zackliscio"
    variable version 3.0
    variable description "Activates screensaver/sleep mode with dimmed screen during dark hours. Machine goes to standby with black screen instead of bright screensaver images."
    variable name "Dark At Night"

    variable settings
    array set settings {}

    variable timer_handle ""
    variable is_dark_mode 0
    # User's real screensaver settings, captured once at startup
    variable saved_saver_interval 1
    variable saved_saver_brightness 100

    proc get_seconds_since_midnight {} {
        set now [clock seconds]
        set midnight [clock scan "00:00:00" -base $now]
        return [expr {$now - $midnight}]
    }

    proc is_in_dark_window {} {
        variable settings

        set current_seconds [get_seconds_since_midnight]
        set start $settings(start_time)
        set end $settings(end_time)

        if {$start > $end} {
            return [expr {$current_seconds >= $start || $current_seconds < $end}]
        } else {
            return [expr {$current_seconds >= $start && $current_seconds < $end}]
        }
    }

    # Idempotent: always sets ::settings to dark values
    proc apply_dark_settings {} {
        variable settings
        set ::settings(screen_saver_change_interval) 0
        set ::settings(saver_brightness) $settings(brightness_level)
        msg -DEBUG [namespace current] "apply_dark_settings: interval=0, saver_brightness=$settings(brightness_level)"
    }

    # Idempotent: always restores ::settings to the user's real values
    proc apply_normal_settings {} {
        variable saved_saver_interval
        variable saved_saver_brightness
        set ::settings(screen_saver_change_interval) $saved_saver_interval
        set ::settings(saver_brightness) $saved_saver_brightness
        msg -DEBUG [namespace current] "apply_normal_settings: interval=$saved_saver_interval, saver_brightness=$saved_saver_brightness"
    }

    # The intercept: called whenever the app wants to go to sleep.
    # Sets ::settings to the correct values BEFORE calling the original,
    # so saver_page_onload reads the right brightness.
    proc intercepted_show_going_to_sleep_page {} {
        variable settings
        variable is_dark_mode

        if {![info exists settings(enabled)] || $settings(enabled) != 1} {
            apply_normal_settings
            set is_dark_mode 0
            if {[catch {::original_show_going_to_sleep_page} err]} {
                msg -ERROR [namespace current] "Intercept: original_show_going_to_sleep_page error (disabled path): $err"
            }
            return
        }

        if {[catch {is_in_dark_window} in_window]} {
            msg -WARNING [namespace current] "Error checking dark window: $in_window"
            set in_window 0
        }

        if {$in_window} {
            msg -INFO [namespace current] "Intercept: dark window active, applying dark settings"
            apply_dark_settings
            set is_dark_mode 1
        } else {
            msg -INFO [namespace current] "Intercept: outside dark window, applying normal settings"
            apply_normal_settings
            set is_dark_mode 0
        }

        if {[catch {::original_show_going_to_sleep_page} err]} {
            msg -ERROR [namespace current] "Intercept: original_show_going_to_sleep_page error: $err"
        }
    }

    # Periodic timer: handles dark window transitions while on saver or idle.
    # Calls ::original_show_going_to_sleep_page directly to avoid recursive intercept.
    proc check_dark_mode_schedule {} {
        variable settings
        variable timer_handle
        variable is_dark_mode
        variable saved_saver_interval
        variable saved_saver_brightness

        if {$timer_handle ne ""} {
            catch {after cancel $timer_handle}
        }

        if {![info exists settings(enabled)] || $settings(enabled) != 1} {
            if {$is_dark_mode} {
                apply_normal_settings
                set is_dark_mode 0
                msg -INFO [namespace current] "Timer: plugin disabled, restored normal settings"
            }
            set timer_handle [after 60000 ::plugins::dark_at_night::check_dark_mode_schedule]
            return
        }

        if {[catch {is_in_dark_window} in_window]} {
            msg -WARNING [namespace current] "Timer: error checking dark window: $in_window"
            set in_window 0
        }

        set ctx ""
        catch {set ctx $::de1(current_context)}

        if {$in_window && !$is_dark_mode} {
            apply_dark_settings
            set is_dark_mode 1
            msg -INFO [namespace current] "Timer: dark window started (ctx=$ctx)"

            if {$ctx eq "saver"} {
                catch {display_brightness $settings(brightness_level)}
            } elseif {$ctx eq "off" || [string match "off_*" $ctx]} {
                msg -INFO [namespace current] "Timer: triggering sleep for dark mode"
                if {[catch {::original_show_going_to_sleep_page} err]} {
                    msg -ERROR [namespace current] "Timer: original_show_going_to_sleep_page error: $err"
                }
            }
        } elseif {!$in_window && $is_dark_mode} {
            apply_normal_settings
            set is_dark_mode 0
            msg -INFO [namespace current] "Timer: dark window ended (ctx=$ctx)"

            if {$ctx eq "saver"} {
                if {$saved_saver_interval == 0} {
                    catch {display_brightness 0}
                } else {
                    catch {display_brightness $saved_saver_brightness}
                }
            }
        }

        set timer_handle [after 60000 ::plugins::dark_at_night::check_dark_mode_schedule]
    }

    # Trace on ::de1(current_context): belt-and-suspenders brightness enforcement
    # and settings restoration when user navigates away from saver.
    proc on_page_change_trace {varname key op} {
        variable is_dark_mode
        variable settings

        set page $::de1(current_context)

        if {$is_dark_mode && $page eq "saver"} {
            catch {
                apply_dark_settings
                display_brightness $settings(brightness_level)
            }
            return
        }

        if {$is_dark_mode && $page ne "saver" && $page ne "off" && ![string match "off_*" $page]} {
            msg -INFO [namespace current] "Trace: user left saver/off (page=$page), restoring normal settings"
            apply_normal_settings
            set is_dark_mode 0
        }
    }

    proc on_slider_change {args} {
        save_plugin_settings dark_at_night
    }

    proc dark_button_pressed {} {
        catch {
            say [translate {Dark}] $::settings(sound_button_out)
        }
        manual_dark_mode
    }

    # Manual activation: apply dark settings then trigger sleep directly (bypass intercept)
    proc manual_dark_mode {} {
        variable is_dark_mode

        msg -INFO [namespace current] "Manual dark mode requested"
        apply_dark_settings
        set is_dark_mode 1
        if {[catch {::original_show_going_to_sleep_page} err]} {
            msg -ERROR [namespace current] "Manual: original_show_going_to_sleep_page error: $err"
        }
    }

    proc build_ui {} {
        variable settings

        set page_name "plugin_dark_at_night_page_default"

        add_de1_page "$page_name" "settings_message.png" "default"
        add_de1_text $page_name 1280 1310 -text [translate "Done"] -font Helv_10_bold -fill "#fAfBff" -anchor "center"
        add_de1_button $page_name {
            say [translate {Done}] $::settings(sound_button_in)
            save_plugin_settings dark_at_night
            page_to_show_when_off extensions
        } 980 1210 1580 1410 ""

        add_de1_text $page_name 1280 300 -text [translate "Dark At Night"] -font Helv_20_bold -width 1200 -fill "#444444" -anchor "center" -justify "center"

        add_de1_text $page_name 280 450 -text [translate "Enable time-based dark mode"] -font Helv_10_bold -fill "#444444" -anchor "nw" -justify "left"
        add_de1_widget $page_name checkbutton 280 520 {} -text "" -indicatoron true -font Helv_10 -bg #FFFFFF -anchor nw -foreground #4e85f4 -variable ::plugins::dark_at_night::settings(enabled) -borderwidth 0 -highlightthickness 0 -command {save_plugin_settings dark_at_night}

        add_de1_text $page_name 280 630 -text [translate "Start time (begin dark mode)"] -font Helv_10_bold -fill "#444444" -anchor "nw"
        add_de1_widget $page_name scale 280 720 {} -from 0 -to 86340 -background #e4d1c1 -borderwidth 1 -bigincrement 3600 -showvalue 0 -resolution 60 -length [rescale_x_skin 800] -width [rescale_y_skin 120] -variable ::plugins::dark_at_night::settings(start_time) -font Helv_10_bold -sliderlength [rescale_x_skin 100] -relief flat -orient horizontal -foreground #FFFFFF -troughcolor #c0c4e1 -borderwidth 0 -highlightthickness 0 -command {::plugins::dark_at_night::on_slider_change}
        add_de1_variable $page_name 280 860 -text "" -font Helv_7 -fill "#7f879a" -anchor "nw" -width 800 -justify "left" -textvariable {[format_alarm_time $::plugins::dark_at_night::settings(start_time)]}

        add_de1_text $page_name 1380 630 -text [translate "End time (stop dark mode)"] -font Helv_10_bold -fill "#444444" -anchor "nw"
        add_de1_widget $page_name scale 1380 720 {} -from 0 -to 86340 -background #e4d1c1 -borderwidth 1 -bigincrement 3600 -showvalue 0 -resolution 60 -length [rescale_x_skin 800] -width [rescale_y_skin 120] -variable ::plugins::dark_at_night::settings(end_time) -font Helv_10_bold -sliderlength [rescale_x_skin 100] -relief flat -orient horizontal -foreground #FFFFFF -troughcolor #c0c4e1 -borderwidth 0 -highlightthickness 0 -command {::plugins::dark_at_night::on_slider_change}
        add_de1_variable $page_name 1380 860 -text "" -font Helv_7 -fill "#7f879a" -anchor "nw" -width 800 -justify "left" -textvariable {[format_alarm_time $::plugins::dark_at_night::settings(end_time)]}

        add_de1_text $page_name 280 950 -text [translate "Screen brightness during dark mode"] -font Helv_10_bold -fill "#444444" -anchor "nw"
        add_de1_widget $page_name scale 280 1020 {} -from 0 -to 100 -background #e4d1c1 -borderwidth 1 -bigincrement 10 -showvalue 0 -resolution 1 -length [rescale_x_skin 800] -width [rescale_y_skin 120] -variable ::plugins::dark_at_night::settings(brightness_level) -font Helv_10_bold -sliderlength [rescale_x_skin 100] -relief flat -orient horizontal -foreground #FFFFFF -troughcolor #c0c4e1 -borderwidth 0 -highlightthickness 0 -command {::plugins::dark_at_night::on_slider_change}
        add_de1_variable $page_name 280 1150 -text "" -font Helv_7 -fill "#7f879a" -anchor "nw" -textvariable {$::plugins::dark_at_night::settings(brightness_level)%}

        add_de1_text $page_name 1380 980 -text [translate "Tip: The sleep button activates dark mode during dark hours"] -font Helv_7 -fill "#7f879a" -anchor "nw" -justify "left" -width 800

        add_de1_variable $page_name 1280 420 -text "" -font Helv_8 -fill "#7f879a" -anchor "center" -textvariable {[translate "Current time:"] [time_format [clock seconds]]}

        return $page_name
    }

    proc preload {} {
        variable settings
        set page_name [build_ui]
        return $page_name
    }

    proc main {} {
        variable settings
        variable timer_handle
        variable saved_saver_interval
        variable saved_saver_brightness

        msg -INFO [namespace current] "v3.0 initializing"

        if {[info exists settings(enabled)]} {
            msg -INFO [namespace current] "Settings: enabled=$settings(enabled), start=[format_alarm_time $settings(start_time)], end=[format_alarm_time $settings(end_time)], brightness=$settings(brightness_level)%"
        }

        # Capture the user's real screensaver settings once, before we ever modify them.
        # These are the values we restore when leaving dark mode.
        if {[info exists ::settings(screen_saver_change_interval)]} {
            set saved_saver_interval $::settings(screen_saver_change_interval)
        }
        if {[info exists ::settings(saver_brightness)]} {
            set saved_saver_brightness $::settings(saver_brightness)
        }
        msg -INFO [namespace current] "Captured user settings: interval=$saved_saver_interval, saver_brightness=$saved_saver_brightness"

        # Load skin-specific integration
        regsub -all { } $::settings(skin) "_" skin
        set skin_src_fn "[plugin_directory]/dark_at_night/setup_${skin}.tcl"

        if { [file exists $skin_src_fn] } {
            msg -INFO [namespace current] "Loading skin-specific setup: $skin_src_fn"
            source $skin_src_fn
        }

        if { [namespace which -command "::plugins::dark_at_night::setup_ui_$skin"] ne "" } {
            ::plugins::dark_at_night::setup_ui_$skin
        } else {
            catch {
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
            }
        }

        # Install intercept on show_going_to_sleep_page
        if {[info commands ::original_show_going_to_sleep_page] eq ""} {
            if {[info commands ::show_going_to_sleep_page] ne ""} {
                rename ::show_going_to_sleep_page ::original_show_going_to_sleep_page
                proc ::show_going_to_sleep_page {} {
                    ::plugins::dark_at_night::intercepted_show_going_to_sleep_page
                }
                msg -INFO [namespace current] "Intercepted show_going_to_sleep_page"
            } else {
                msg -WARNING [namespace current] "show_going_to_sleep_page not found, cannot intercept"
            }
        }

        # Register context trace
        catch {
            trace add variable ::de1(current_context) write ::plugins::dark_at_night::on_page_change_trace
        }

        # Start periodic check with margin for app startup
        set timer_handle [after 5000 ::plugins::dark_at_night::check_dark_mode_schedule]

        msg -INFO [namespace current] "Initialization complete"
    }

    proc cleanup {} {
        variable timer_handle
        variable is_dark_mode

        msg -INFO [namespace current] "Cleaning up"

        if {$timer_handle ne ""} {
            catch {after cancel $timer_handle}
            set timer_handle ""
        }

        if {$is_dark_mode} {
            apply_normal_settings
            set is_dark_mode 0
        }

        # Skin-specific cleanup
        regsub -all { } $::settings(skin) "_" skin
        if { [namespace which -command "::plugins::dark_at_night::cleanup_ui_$skin"] ne "" } {
            ::plugins::dark_at_night::cleanup_ui_$skin
        } else {
            catch {
                .can delete dark_at_night_moon_icon
                .can delete dark_at_night_button
            }
        }

        if {[info commands ::original_show_going_to_sleep_page] ne ""} {
            rename ::show_going_to_sleep_page ""
            rename ::original_show_going_to_sleep_page ::show_going_to_sleep_page
            msg -INFO [namespace current] "Restored original show_going_to_sleep_page"
        }

        catch {
            trace remove variable ::de1(current_context) write ::plugins::dark_at_night::on_page_change_trace
        }
    }
}
