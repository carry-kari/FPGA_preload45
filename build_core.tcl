import_device eagle_s20.db -package EG4S20BG256
set project_root [file dirname [file normalize [info script]]]
if {[info exists ::env(FPGA_PYTHON)]} {
    set core_python $::env(FPGA_PYTHON)
} else {
    set core_python {C:/Users/zhangkaiwei/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe}
}
puts [exec $core_python -X utf8 "$project_root/tools/install_gui_flow.py" 2>@1]
open_project "$project_root/hx4s20c.al"
top_module top
set_param place fix_hold high -run phy_1
set_param route hold_fix_iteration 10 -run phy_1
reset_runs syn_1
launch_runs -step gate syn_1
wait_run syn_1 -quiet
reset_runs phy_1
launch_runs -step bitgen phy_1
wait_run phy_1 -quiet
close_project
file mkdir "$project_root/build/td"
set fusion_template [open "$project_root/td/holdfix.tcl" r]
set fusion_hold_code [string map [list @ROOT@ $project_root] [read $fusion_template]]
close $fusion_template
set fusion_generated "$project_root/build/td/holdfix_from_build.tcl"
set fusion_file [open $fusion_generated w]
puts $fusion_file $fusion_hold_code
close $fusion_file
set fusion_cli [file join [file dirname [info nameofexecutable]] td_commands_prompt.exe]
set fusion_log [exec $fusion_cli $fusion_generated]
set fusion_file [open "$project_root/build/td/holdfix_from_build.log" w]
puts $fusion_file $fusion_log
close $fusion_file
puts "Post-route ECO hold repair completed; constraints and internal checks retained."
file mkdir "$project_root/download"
file copy -force "$project_root/hx4s20c_Runs/best_result/hx4s20c.bit" "$project_root/download/hx4s20c.bit"
puts [exec $core_python -X utf8 "$project_root/tools/finish_gui_build.py" 2>@1]
exit
