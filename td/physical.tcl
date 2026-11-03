import_device eagle_s20.db -package EG4S20BG256
open_project {@ROOT@/hx4s20c.al}
reset_runs phy_1
launch_runs -step bitgen phy_1
wait_run phy_1 -quiet
close_project
exit
