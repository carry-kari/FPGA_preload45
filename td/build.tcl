import_device eagle_s20.db -package EG4S20BG256
open_project {@ROOT@/hx4s20c.al}
top_module top
reset_runs syn_1
launch_runs -step gate syn_1
wait_run syn_1 -quiet
close_project
exit
