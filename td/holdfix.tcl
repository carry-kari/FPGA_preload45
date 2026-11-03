import_device eagle_s20.db -package EG4S20BG256
import_db {@ROOT@/hx4s20c_Runs/phy_1/hx4s20c_pr.db}
clear_sdc
read_sdc {@ROOT@/constraints/hx4s20c.sdc}
set_cross_domain_timing all
update_timing -mode final
# Explicit post-route ECO is required when automatic hold fixing skips a dense pack.
fix_hold -eco
route -eco
update_timing -mode final
report_timing_summary -include_ignored -file {@ROOT@/build/td/holdfix_timing.rpt}
set timing_file [open {@ROOT@/build/td/holdfix_timing.rpt} r]
set timing_text [read $timing_file]
close $timing_file
if {![regexp {SWNS:\s+(-?[0-9.]+)ns} $timing_text ignored setup_slack] ||
    ![regexp {HWNS:\s+(-?[0-9.]+)ns} $timing_text ignored hold_slack] ||
    $setup_slack < 0 || $hold_slack < 0} {
    puts "ERROR: post-route ECO has unresolved internal timing; bitstream publication stopped"
    exit 1
}
report_area -io_info -file {@ROOT@/hx4s20c_Runs/phy_1/hx4s20c_phy.area}
write_verilog {@ROOT@/build/td/holdfix_physical_netlist.v}
export_db {@ROOT@/hx4s20c_Runs/phy_1/hx4s20c_pr.db}
bitgen -bit {@ROOT@/hx4s20c_Runs/phy_1/hx4s20c.bit}
file mkdir {@ROOT@/hx4s20c_Runs/best_result}
file mkdir {@ROOT@/download}
foreach dst {{@ROOT@/hx4s20c_Runs/best_result/hx4s20c.bit} {@ROOT@/download/hx4s20c.bit}} {
    file copy -force {@ROOT@/hx4s20c_Runs/phy_1/hx4s20c.bit} $dst
}
file copy -force {@ROOT@/hx4s20c_Runs/phy_1/hx4s20c_pr.db} {@ROOT@/hx4s20c_Runs/best_result/hx4s20c_pr.db}
file copy -force {@ROOT@/hx4s20c_Runs/phy_1/hx4s20c_phy.area} {@ROOT@/hx4s20c_Runs/best_result/hx4s20c_phy.area}
exit
