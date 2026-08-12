--============================================================================
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Clock frequencies. GENERATED FILE - DO NOT EDIT.
--
-- Written by QUARTUS/gen_plls.tcl, which also generates the PLL IP from the
-- same numbers. To change a clock, edit the CLOCKS list in that script and
-- re-run QUARTUS\gen_plls.bat - never edit this file, it will be overwritten.
--
-- MODELSIM = 1 makes MCU.vhd build its clocks behaviourally from these
-- constants; MODELSIM = 0 makes it instantiate the PLLs instead. The two
-- paths therefore run at identical frequencies by construction.
--============================================================================
library IEEE;
use ieee.std_logic_1164.all;


package clk_config_package is

	constant G_REFCLK_MHZ	: real := 50.0;	-- board oscillator
	constant G_MCLK_MHZ	: real := 25.0;	-- CPU clock
	constant G_DIVCLK_MHZ	: real := 100.0;	-- division accelerator
	constant G_SMCLK_MHZ	: real := 25.0;	-- Basic Timer source clock

end clk_config_package;
