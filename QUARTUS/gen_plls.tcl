#=============================================================================
# Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
# Generate the three clock PLLs - MCLK, DIVCLK and SMCLK.
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
# style of the PLL supplied with LAB4 (a single outclk_0 per core). Forum
# row 13 requires exactly this - "No - from three different instances of the
# PLL module" - and row 8 that all three take the same 50 MHz base clock as
# their reference.
#=============================================================================

package require -exact qsys 21.1

# ----------------------------------------------------------------------------
# EDIT HERE:  { entity_name  output_MHz  what_it_drives }
#
# This one list drives both the .qsys generation and the VHDL constant
# emission at the bottom of the script, so an IP core and its matching VHDL
# constant cannot get out of step.
#
# MCLK AND SMCLK ARE THE SAME FREQUENCY ON PURPOSE, AND MUST STAY THAT WAY.
# Forum row 16: "in the basic case of a single-cycle CPU running at a low
# frequency, the separation is required and necessary, but their value may be
# identical, i.e. MCLK=SMCLK". Row 15 is what makes the equal value safe:
# because both PLLs take the same 50 MHz physical source, an integer MCLK to
# SMCLK ratio "guarantees full synchronisation with no need for edge
# synchronisation". At equal frequencies the ratio is 1.
#
# BASIC_TIMER_INTERFACE.vhd carries a concurrent ASSERT on exactly that
# condition: it refuses to elaborate if G_SMCLK_MHZ and G_MCLK_MHZ differ,
# because the design carries no CDC hardware on the CPU-to-timer path and
# needs none only while the condition holds. Retuning MCLK without retuning
# SMCLK to match will trip that assert rather than silently build an
# unsynchronised design.
# ----------------------------------------------------------------------------
set REFCLK_MHZ 50.0
set CLOCKS {
	{PLL_MCLK    25.0   "CPU clock"}
	{PLL_DIVCLK  200.0  "division accelerator"}
	{PLL_SMCLK   25.0   "Basic Timer source clock - equal to MCLK, see row 15"}
}

# DIVCLK is measured, not guessed. It was briefly dropped to 100 MHz on a
# secondhand report of the divider closing at only about 130 MHz; the Quartus
# Timing Analyzer then gave this design's actual figures on the
# Slow 1100mV 85C model:
#
#   MCLK   domain fmax    29.04 MHz   <- the design's real critical path
#   DIVCLK domain fmax   238.61 MHz
#
# So 200 MHz has 19% margin and the 130 MHz figure does not apply here.
# Back to 200. The frequency costs nothing but cycles, and the golden model
# matches at every setting measured in ModelSim:
#
#   DIVCLK    ratio   benchmark cycles   golden model
#   200 MHz     8:1        276              matches
#   150 MHz     6:1        292              matches
#   100 MHz     4:1        340              matches
#    50 MHz     2:1        484              matches
#
# Note that MCLK is the tight one: 25 MHz requested against 29.04 MHz
# achievable is only 16% margin, and it is where the critical path lives.

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
