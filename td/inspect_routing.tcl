import_device eagle_s20.db -package EG4S20BG256
import_db {@ROOT@/hx4s20c_Runs/phy_1/hx4s20c_pr.db}
write_verilog {@ROOT@/build/td/physical_netlist.v}
exit
