--============================================================================
-- Copyright 2026 Hananya Ribo 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Conditional Compilation Parameters
--============================================================================ 
library IEEE;
use ieee.std_logic_1164.all;


package cond_compilation_package is
-- Use Conditional Compilation to define 6-Parameters lines 51-56
------------------------------------------------------------------
-- M9K(and ModelSim) Memory configuration constants
------------------------------------------------------------------
	constant M9K_TCM1KiB_ADDRWIDTH 		: integer := 8;
	constant M9K_TCM2KiB_ADDRWIDTH 		: integer := 9;
	constant M9K_TCM4KiB_ADDRWIDTH 		: integer := 10;
	constant M9K_TCM8KiB_ADDRWIDTH 		: integer := 11;
	
	constant M9K_TCM1KiB_WORDSNUM 		: integer := 256;
	constant M9K_TCM2KiB_WORDSNUM 		: integer := 512;
	constant M9K_TCM4KiB_WORDSNUM 		: integer := 1024;
	constant M9K_TCM8KiB_WORDSNUM 		: integer := 2048;
-----------------------------------------------------------
-- M4K Memory configuration constants
-----------------------------------------------------------	
	constant M4K_TCM1KiB_ADDRWIDTH 		: integer := 10;
	constant M4K_TCM2KiB_ADDRWIDTH 		: integer := 11;
	constant M4K_TCM4KiB_ADDRWIDTH 		: integer := 12;
	constant M4K_TCM8KiB_ADDRWIDTH 		: integer := 13;
	
	constant M4K_TCM1KiB_WORDSNUM 		: integer := 1024;
	constant M4K_TCM2KiB_WORDSNUM 		: integer := 2048;
	constant M4K_TCM4KiB_WORDSNUM 		: integer := 4095;
	constant M4K_TCM8KiB_WORDSNUM 		: integer := 8190;
----------------------------------------------------------------------
-- PC_WIDTH and MA_WIDTH configuration constants for M9K_M4K_MODELSIM
----------------------------------------------------------------------		
	constant PC_WIDTH_TCM1KiB			: integer := 10;
	constant PC_WIDTH_TCM2KiB 		: integer := 11;
	constant PC_WIDTH_TCM4KiB 		: integer := 12;
	constant PC_WIDTH_TCM8KiB 		: integer := 13;
-----------------------------------------------------------------------	
	constant MA_WIDTH_TCM1KiB 		: integer := 10;
	constant MA_WIDTH_TCM2KiB 		: integer := 11;
	constant MA_WIDTH_TCM4KiB 		: integer := 12;
	constant MA_WIDTH_TCM8KiB 		: integer := 13;
--==================================================================================================================
-- 															Conditional Compilation defined by 8-Parameters
--==================================================================================================================
	constant G_MODELSIM					: integer	:= 0;											-- options{1=MODELSIM,0=FPGA}
	-- Clause 7: only the MCU I/O devices get pin locations. The observation
	-- outputs of MCU.vhd exist for verification and for routing signals to
	-- pins during validation; with G_SIGTAP=0 their port ranges collapse to
	-- null and they occupy no pins at all. Signal-Tap itself needs none of
	-- them - it taps internal nodes over JTAG.
	constant G_SIGTAP						: integer	:= 0;											-- options{1=observation ports exposed,0=FPGA}
	constant G_WORD_GRANULARITY : boolean := True;									-- options{True,False}
	constant G_ADDRWIDTH 				: integer := M9K_TCM8KiB_ADDRWIDTH;	-- options{M9K_MODELSIM_ADDRWIDTH,M4K_ADDRWIDTH} 
	constant G_DATA_WORDSNUM 		: integer := M9K_TCM8KiB_WORDSNUM;	-- options{M9K_MODELSIM_WORDSNUM,M4K_WORDSNUM}
	constant G_PC_WIDTH 				: integer := PC_WIDTH_TCM8KiB;			-- options{PC_WIDTH_TCM1KiB,PC_WIDTH_TCM2KiB,...}
	constant G_MA_WIDTH 				: integer := MA_WIDTH_TCM8KiB;			-- options{MA_WIDTH_TCM1KiB,MA_WIDTH_TCM2KiB,...}
	constant DBUS_WIDTH 				: integer	:= 32;
	-- Width of the byte address the core drives onto the data bus (Figure 2).
	-- One bit wider than the DTCM itself, so that the top bit distinguishes
	-- the DTCM (0x0000-0x1FFF) from memory-mapped I/O (0x2000-0x3FFF).
	-- MCU.vhd owns the decode; the core just presents the full byte address.
	constant G_DA_WIDTH 				: integer := MA_WIDTH_TCM8KiB + 1;	-- 14

	--==================================================================================================================
	-- Default TCM images
	--==================================================================================================================
	-- These are the values a design elaborated with no -GITCM_INIT_FILE /
	-- -GDTCM_INIT_FILE override gets. run_benchmark.do always overrides them
	-- to select an application; check_io_bus.do does NOT, because it drives
	-- the bus by hand and runs no program - so these defaults are the only
	-- thing standing between that script and an altsyncram that cannot open
	-- its init file, which aborts the simulation at time 0 and makes every
	-- one of its checks read U or X.
	--
	-- They used to be absolute paths into one developer's home directory,
	-- which meant check_io_bus.do failed on every other machine. The project
	-- definition makes a clean ModelSim and Quartus build a condition of
	-- submission and the grader runs on his own machine, so an absolute path
	-- from this side of the handover is not usable.
	--
	-- PATHS ARE RELATIVE TO THE SIMULATOR'S WORKING DIRECTORY, which for every
	-- script in this project is SIM/RV32IMscMCU - the same "../../" convention
	-- compile.do already uses to reach DUT/ and TB/. Run ModelSim from
	-- anywhere else and these will not resolve; that is what the overrides in
	-- run_benchmark.do are for.
	--
	-- The image chosen is the canonical RV32IM test1, the one the golden
	-- model in its own output/RARS/DTCM.h matches and the one that exercises
	-- div, mul and rem. See README.md for the benchmark table.
	constant G_ITCM_INIT_FILE	: string := "../../Benchmark apps-20260827T145317Z-1-001/Benchmark apps/RV32IM/test1/man_compiled/bin/M9K-intel/ITCM.hex";
	constant G_DTCM_INIT_FILE	: string := "../../Benchmark apps-20260827T145317Z-1-001/Benchmark apps/RV32IM/test1/man_compiled/bin/M9K-intel/DTCM.hex";
	-- G_PLL_DIV and G_PLL_MUL are gone with PLL.vhd. MCU.vhd derives MCLK
	-- from clk_i with a toggle flip-flop, which is the same divide-by-2 the
	-- PLL was configured for.

-- Explanation:
-----------------------------------------------------------
--	if G_MODELSIM=1 then 
--		IDE=Modelsim 
--  elsif G_MODELSIM=0 then
--    IDE=Quartus
--------------------------------------------------------
--  if G_WORD_GRANULARITY=True then 
--		Each WORD has a unike address
--	elsif G_WORD_GRANULARITY=False
-- 		Each BYTE has a unike address
--------------------------------------------------------
--  if G_ADDRWIDTH=M9K_MODELSIM_ADDRWIDTH then
--		ITCM_ADDR_WIDTH=DTCM_ADDR_WIDTH=M9K_TCM_ADDR_WIDTH
--	elsif  G_ADDRWIDTH=M4K_ADDRWIDTH then
--		ITCM_ADDR_WIDTH=DTCM_ADDR_WIDTH=M4K_TCM_ADDR_WIDTH
--------------------------------------------------------
--	if G_DATA_WORDSNUM=M9K_MODELSIM_ADDRWIDTH then
--		ITCM_WORDS_NUM=DTCM_WORDS_NUM=M9K_TCM_WORDSNUM
--	elsif  G_DATA_WORDSNUM=M4K_WORDSNUM then
--		ITCM_WORDS_NUM=DTCM_WORDS_NUM=M4K_TCM_WORDSNUM
--===================================================================================================================

end cond_compilation_package;

