# 50 MHz board oscillator on CLOCK_50
create_clock -name CLOCK_50 -period 20.000 [get_ports clk_i]

# MCLK 25, DIVCLK 100 and SMCLK 25 are PLL outputs.
# derive_pll_clocks picks up all three automatically.
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