# 50 MHz board oscillator on CLOCK_50
create_clock -name CLOCK_50 -period 20.000 [get_ports clk_i]

# MCLK and DIVCLK are PLL outputs; derive_pll_clocks picks up both
# automatically. SMCLK is no longer a PLL output - it is a synchronous
# branch of MCLK (smclk_w <= mclk_w in MCU.vhd), so it needs no clock
# of its own here. BTCLK (SMCLK through BT_CLKDIV's BTSSEL divider,
# once basic_timer is instantiated) is still a clock generated in
# fabric and still needs its own create_generated_clock for the /2,
# /4 and /8 taps plus set_clock_groups -exclusive between them, as
# BT_CLKDIV.vhd's header describes - that requirement is unchanged by
# this file and not yet added below.
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