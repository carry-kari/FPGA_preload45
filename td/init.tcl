import_device eagle_s20.db -package EG4S20BG256
create_project hx4s20c {@ROOT@} -family eg4 -device EG4S20BG256
top_module top
set_param place fix_hold high -run phy_1
set_param route hold_fix_iteration 10 -run phy_1
add_dir {@ROOT@/rtl}
add_files {@ROOT@/vendor_ip/hdmi_1_4b_transmitter_core_wrapper.enc.v}
add_files {@ROOT@/constraints/hx4s20c.adc}
add_files {@ROOT@/constraints/hx4s20c.sdc}
close_project
exit
