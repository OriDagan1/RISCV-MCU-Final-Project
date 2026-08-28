# 50 MHz board oscillator on CLOCK_50
create_clock -name CLOCK_50 -period 20.000 [get_ports clk_i]

# MCLK 25, DIVCLK 200 and SMCLK 25 are PLL outputs, one PLL instance
# each (forum rows 8 and 13), all referenced to CLOCK_50 above.
# derive_pll_clocks picks up all three automatically.
#
# MCLK and SMCLK are deliberately the same frequency from separate PLLs
# (row 16), which per row 15 is fully synchronised because both come
# from the one 50 MHz source at an integer ratio - so no false path or
# clock group is wanted between them here. They must stay analysed
# together.
#
# BTCLK (SMCLK through BT_CLKDIV's BTSSEL divider) is a further clock
# generated in fabric and still needs its own create_generated_clock
# for the /2, /4 and /8 taps plus set_clock_groups -exclusive between
# them, as BT_CLKDIV.vhd's header describes - not yet added below.
derive_pll_clocks
derive_clock_uncertainty

# Switches and the reset pushbutton are asynchronous to
# every clock; the displays and LEDs are human-speed.
# Constraining them would report meaningless I/O timing
# failures and hide the real core critical path.
set_false_path -from [get_ports {SW_i[*]}] -to [all_clocks]
set_false_path -from [get_ports rst_i]     -to [all_clocks]
set_false_path -from * -to [get_ports {LEDR_o[*]}]
set_false_path -from * -to [get_ports {HEX0_o[*]}]
set_false_path -from * -to [get_ports {HEX1_o[*]}]
set_false_path -from * -to [get_ports {HEX2_o[*]}]
set_false_path -from * -to [get_ports {HEX3_o[*]}]
set_false_path -from * -to [get_ports {HEX4_o[*]}]
set_false_path -from * -to [get_ports {HEX5_o[*]}]