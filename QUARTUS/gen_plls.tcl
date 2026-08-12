#=============================================================================
# Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
# Generate the three clock PLLs.
#
# THIS FILE IS THE SINGLE SOURCE OF TRUTH FOR THE CLOCK FREQUENCIES.
# To retune a clock, change one number in CLOCKS below and re-run:
#
#     QUARTUS\gen_plls.bat
#
# That regenerates the IP *and* rewrites clk_config_package.vhd, so the
# simulation clock generators and the FPGA PLLs can never drift apart.
#
# Each clock gets its own PLL instance, one IP core per clock, matching the
# style of the PLL supplied with LAB4 (a single outclk_0 per core).
#=============================================================================

package require -exact qsys 21.1

# ----------------------------------------------------------------------------
# EDIT HERE:  { entity_name  output_MHz  what_it_drives }
# ----------------------------------------------------------------------------
set REFCLK_MHZ 50.0
set CLOCKS {
	{PLL_MCLK    25.0   "CPU clock"}
	{PLL_DIVCLK  100.0  "division accelerator"}
	{PLL_SMCLK   25.0   "Basic Timer source clock"}
}

# DIVCLK was 200 MHz, which is well above what the divider is likely to close
# timing at - a figure of about 130 MHz has been reported for this datapath.
# 100 MHz leaves a comfortable margin for the first FPGA validation run and
# keeps a clean 4:1 ratio with MCLK. It costs cycles and nothing else:
#
#   DIVCLK    ratio   benchmark cycles   golden model
#   200 MHz     8:1        276              matches
#   150 MHz     6:1        292              matches
#   100 MHz     4:1        340              matches
#    50 MHz     2:1        484              matches
#
# Raise it again once the real fmax of the DIVCLK domain is known from the
# Timing Analyzer, then re-run gen_plls.bat and re-verify.

# DE10-Standard, Cyclone V SoC
set DEVICE_FAMILY {Cyclone V}
set DEVICE        {5CSXFC6D6F31C6}

# ----------------------------------------------------------------------------
# Build one .qsys per clock
# ----------------------------------------------------------------------------
foreach c $CLOCKS {
	set name [lindex $c 0]
	set freq [lindex $c 1]

	create_system $name
	set_project_property DEVICE_FAMILY $DEVICE_FAMILY
	set_project_property DEVICE        $DEVICE

	add_instance pll_0 altera_pll
	set_instance_parameter_value pll_0 {gui_reference_clock_frequency} $REFCLK_MHZ
	set_instance_parameter_value pll_0 {gui_number_of_clocks}          {1}
	set_instance_parameter_value pll_0 {gui_output_clock_frequency0}   $freq
	# locked left unused, as in the PLL supplied with LAB4
	set_instance_parameter_value pll_0 {gui_use_locked}                {false}

	add_interface refclk clock sink
	set_interface_property refclk EXPORT_OF pll_0.refclk
	add_interface rst reset sink
	set_interface_property rst EXPORT_OF pll_0.reset
	add_interface outclk_0 clock source
	set_interface_property outclk_0 EXPORT_OF pll_0.outclk0

	save_system "${name}.qsys"
	puts "wrote ${name}.qsys  (${freq} MHz)"
}

# ----------------------------------------------------------------------------
# Emit the matching VHDL constants.
#
# Written rather than hand-maintained on purpose: the simulation clock
# generators in MCU.vhd read these, so if they disagreed with the IP the
# design would behave one way in ModelSim and another on the board.
# ----------------------------------------------------------------------------
set out [open "../DUT/RV32IMscMCU/clk_config_package.vhd" w]
puts $out "--============================================================================"
puts $out "-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU"
puts $out "-- Clock frequencies. GENERATED FILE - DO NOT EDIT."
puts $out "--"
puts $out "-- Written by QUARTUS/gen_plls.tcl, which also generates the PLL IP from the"
puts $out "-- same numbers. To change a clock, edit the CLOCKS list in that script and"
puts $out "-- re-run QUARTUS\\gen_plls.bat - never edit this file, it will be overwritten."
puts $out "--"
puts $out "-- MODELSIM = 1 makes MCU.vhd build its clocks behaviourally from these"
puts $out "-- constants; MODELSIM = 0 makes it instantiate the PLLs instead. The two"
puts $out "-- paths therefore run at identical frequencies by construction."
puts $out "--============================================================================"
puts $out "library IEEE;"
puts $out "use ieee.std_logic_1164.all;"
puts $out ""
puts $out ""
puts $out "package clk_config_package is"
puts $out ""
puts $out "\tconstant G_REFCLK_MHZ\t: real := $REFCLK_MHZ;\t-- board oscillator"
foreach c $CLOCKS {
	set name [lindex $c 0]
	set freq [lindex $c 1]
	set what [lindex $c 2]
	# PLL_MCLK -> G_MCLK_MHZ
	set sig [string range $name 4 end]
	puts $out "\tconstant G_${sig}_MHZ\t: real := $freq;\t-- $what"
}
puts $out ""
puts $out "end clk_config_package;"
close $out
puts "wrote ../DUT/RV32IMscMCU/clk_config_package.vhd"
