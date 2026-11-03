# Project-local hooks called from the TD physical run's editable zones.
namespace eval ::fusion_gui {
    variable root [file dirname [file dirname [file normalize [info script]]]]
}
proc ::fusion_gui::timing_gate {} {
    variable root
    set_cross_domain_timing all
    update_timing -mode final
    set report "$root/hx4s20c_Runs/phy_1/final_timing.rpt"
    report_timing_summary -include_ignored -file $report
    set f [open $report r]
    set text [read $f]
    close $f
    foreach key {SWNS HWNS STNS HTNS} {
        if {![regexp [format {%s:\s+(-?[0-9.]+)ns} $key] $text unused value] || $value < 0} {
            error "GUI timing gate failed: $key; bitstream publication stopped"
        }
    }
}
proc ::fusion_gui::after_route {} {
    variable root
    file mkdir "$root/build/td"
    puts "FUSION_GUI_HOLDFIX_BEGIN"
    set_cross_domain_timing all
    update_timing -mode final
    fix_hold -eco
    route -eco
    ::fusion_gui::timing_gate
    check_timing -verbose -file "$root/hx4s20c_Runs/phy_1/check_timing.rpt"
    write_verilog "$root/build/td/audit_physical_netlist.v"
    puts "FUSION_GUI_HOLDFIX_PASS"
}
proc ::fusion_gui::after_bitgen {} {
    variable root
    foreach dir {download hx4s20c_Runs/best_result} { file mkdir "$root/$dir" }
    foreach dir {download hx4s20c_Runs/best_result} {
        file copy -force "$root/hx4s20c_Runs/phy_1/hx4s20c.bit" "$root/$dir/hx4s20c.bit"
    }
    foreach ext {db area} {
        if {$ext eq "db"} {set name hx4s20c_pr.db} else {set name hx4s20c_phy.area}
        file copy -force "$root/hx4s20c_Runs/phy_1/$name" "$root/hx4s20c_Runs/best_result/$name"
    }
    if {[info exists ::env(FPGA_PYTHON)]} {
        set python $::env(FPGA_PYTHON)
    } else {
        set python {C:/Users/zhangkaiwei/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe}
    }
    if {![file executable $python]} { error "Set FPGA_PYTHON to a Python executable for GUI release verification" }
    set output [exec $python -X utf8 "$root/tools/finish_gui_build.py" 2>@1]
    puts $output
    puts "FUSION_GUI_RELEASE_PASS"
}
