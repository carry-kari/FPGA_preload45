create_clock -name clk_50m -period 20.000 [get_ports {clk_50m}]
create_generated_clock -name pix_clk -source [get_ports {clk_50m}] -divide_by 1.984126984126984 [get_pins {u_pll/pll.clkc[0]}]
create_generated_clock -name serial_clk_5x -source [get_ports {clk_50m}] -multiply_by 2.52 [get_pins {u_pll/pll.clkc[1]}]
create_generated_clock -name mem_clk -source [get_ports {clk_50m}] -divide_by 1.1904761904761905 [get_pins {u_pll/pll.clkc[2]}]
create_generated_clock -name sdram_clk -source [get_ports {clk_50m}] -divide_by 1.1904761904761905 -phase 168 [get_pins {u_pll/pll.clkc[3]}]
# Include the related PLL pixel-to-serializer paths explicitly.
set_cross_domain_timing all
# External buttons/switches enter synchronizers;
# sw_reset_run asserts reset asynchronously and release is synchronized.
# These exceptions start at board ports; internal synchronizer/reset paths
# retain setup/hold and recovery/removal checks.
set_false_path -from [get_ports {key1_n key2_n key3_n sw1_n sw2_n sw_audio_enable sw_reset_run}]
# Status LEDs have no external clocked receiver.
set_false_path -to [get_ports {status_fault status_image_ready status_pll_locked status_video_locked}]
# SD, DDC and TMDS external timing remains pending measured/specification
# parameters. Keep the vendor reset distribution in recovery/removal STA.
