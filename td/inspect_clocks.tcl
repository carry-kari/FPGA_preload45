import_device eagle_s20.db -package EG4S20BG256
import_db {@ROOT@/hx4s20c_Runs/phy_1/hx4s20c_pr.db}
clear_sdc
read_sdc {@ROOT@/constraints/hx4s20c.sdc}
update_timing -mode final
set_cross_domain_timing all
update_timing -mode final
report_timing_summary -include_ignored -file {@ROOT@/build/td/probe_timing.rpt}
report_timing_ignored -file {@ROOT@/build/td/ignored_timing.rpt}
check_timing -verbose -file {@ROOT@/build/td/check_timing.rpt}
report_timing_path -from [get_clocks pix_clk] -to [get_clocks serial_clk_5x] -file {@ROOT@/build/td/serializer_cross.rpt}
exit
