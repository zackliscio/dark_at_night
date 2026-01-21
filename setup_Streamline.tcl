# Dark At Night - Streamline Skin Integration
#
# MANUAL BUTTON: Currently disabled
# 
# The manual "Dark Mode" button is commented out below because it blocks part of the screen.
# The plugin works perfectly with just the smart sleep button and auto-schedule features.
# 
# To re-enable the manual button: Uncomment lines 14-28 below
#

proc ::plugins::dark_at_night::setup_ui_Streamline {} {
    msg -INFO "Dark At Night: Setting up for Streamline (manual button disabled)"
    
    # MANUAL BUTTON CODE - Uncomment to re-enable:
    
    # # Simple button in bottom-right area
    # set btn_x1 2200
    # set btn_y1 1400
    # set btn_x2 2500
    # set btn_y2 1550
    # 
    # # Button text
    # add_de1_text "off off_zoomed" 2350 1475 \
    #     -text "⬛ DARK MODE ⬛" -font Helv_10_bold -fill "#FFFFFF" -anchor "center" -tags dark_at_night_text
    # 
    # # Clickable button
    # add_de1_button "off off_zoomed" {
    #     msg "Dark At Night: Button clicked!"
    #     ::plugins::dark_at_night::manual_dark_mode
    # } $btn_x1 $btn_y1 $btn_x2 $btn_y2
    # 
    # msg -INFO "Dark At Night: Button created at bottom-right ($btn_x1,$btn_y1)"
}

proc ::plugins::dark_at_night::cleanup_ui_Streamline {} {
    # Cleanup for manual button (currently disabled)
    catch {
        .can delete dark_at_night_text
    }
}
