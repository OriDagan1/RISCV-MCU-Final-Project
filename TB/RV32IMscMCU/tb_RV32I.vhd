---------------------------------------------------------------------------------------------
-- Copyright 2025 Hananya Ribo 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
---------------------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
use ieee.std_logic_unsigned.all;
USE work.cond_compilation_package.all;
USE work.aux_package.all;


ENTITY tb_RV32I IS
	generic( 
		WORD_GRANULARITY 	: boolean 	:= G_WORD_GRANULARITY;
	  MODELSIM 					: integer 	:= G_MODELSIM;
		-- 1, not G_SIGTAP: simulation always wants the observation ports.
		-- G_SIGTAP is 0 so that Quartus builds the MCU with board I/O only.
		SIGTAP						: integer 	:= 1;
		DATA_BUS_WIDTH 		: integer 	:= 32;
		ITCM_ADDR_WIDTH 	: integer 	:= G_ADDRWIDTH;
		DTCM_ADDR_WIDTH 	: integer 	:= G_ADDRWIDTH;
		PC_WIDTH 					: integer 	:= G_PC_WIDTH;
		MA_WIDTH 					: integer 	:= G_MA_WIDTH;
		DATA_WORDS_NUM 		: integer 	:= G_DATA_WORDSNUM;
		DA_WIDTH			: integer 	:= G_DA_WIDTH;
		CLK_CNT_WIDTH 		: integer 	:= 16;
		-- Benchmark under test. Override on the command line, e.g.
		--   vsim -gITCM_INIT_FILE=<path>/ITCM.hex -gDTCM_INIT_FILE=<path>/DTCM.hex work.tb_RV32I
		--
		-- This testbench's defaults are what a plain "vsim work.tb_RV32I"
		-- gets, and they are what check_io_bus.do runs on, since that script
		-- drives the bus by hand and passes no override. They shadow MCU.vhd's
		-- own defaults, so BOTH have to be right - fixing only MCU.vhd leaves
		-- this file still pointing somewhere that does not exist.
		--
		-- Relative to the simulator's working directory, SIM/RV32IMscMCU. See
		-- the note on G_ITCM_INIT_FILE in cond_compilation_package.vhd.
		ITCM_INIT_FILE		: string	:= G_ITCM_INIT_FILE;
		DTCM_INIT_FILE		: string	:= G_DTCM_INIT_FILE
	);
END tb_RV32I ;


ARCHITECTURE struct OF tb_RV32I IS
	--Inputs
	SIGNAL rst_i		 					:	STD_LOGIC;
	SIGNAL clk_i							:	STD_LOGIC;
	
	--Outputs (used for Verification and FPGA Velidation(Signal-TAP))
	SIGNAL pc_o								:	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
	SIGNAL instruction_o			:	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	
	SIGNAL RegWrite_ctrl_o		: STD_LOGIC;
	SIGNAL MemWrite_ctrl_o		: STD_LOGIC;
	SIGNAL Branch_ctrl_o			: STD_LOGIC;
	
	SIGNAL read_data1_o 			:	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL read_data2_o 			:	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL write_data_o				:	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	
	SIGNAL alu_res_o 					:	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);															
	SIGNAL brTaken_o					: STD_LOGIC; 
	
	SIGNAL dtcm_addr_o				: STD_LOGIC_VECTOR(DA_WIDTH-1 DOWNTO 0);
	SIGNAL dtcm_data_wr_o			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL dtcm_data_rd_o			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	
	SIGNAL smclk_o						: STD_LOGIC;

	SIGNAL mclk_cnt_o					:	STD_LOGIC_VECTOR(CLK_CNT_WIDTH-1 DOWNTO 0);

	-- Memory-mapped I/O pins. None of the supplied benchmarks touches I/O, so
	-- the switches are held at a fixed pattern and the outputs are only
	-- observed: this testbench exists to prove the GPIO changed nothing. The
	-- ports themselves are verified by the five tb_GPIO_* unit testbenches.
	SIGNAL SW_i								: STD_LOGIC_VECTOR(7 DOWNTO 0) := x"A5";
	-- "111" is all keys released: the pushbuttons are active low and held
	-- high by the pull-ups of Figure 6. No benchmark touches PORT_PB either,
	-- so KEY_i is held constant - pushbutton behaviour is covered by
	-- tb_GPIO_PB_Interface.vhd, not here.
	SIGNAL KEY_i							: STD_LOGIC_VECTOR(3 DOWNTO 1) := "111";
	-- No benchmark touches the Basic Timer capture pins either, so they are
	-- held low and only observed through btcapr/BTIFG via the register
	-- file - basic_timer_interface's own testbench and tb_basic_timer.vhd
	-- exercise the capture path.
	SIGNAL CAPIN1_i							: STD_LOGIC := '0';
	SIGNAL CAPIN2_i							: STD_LOGIC := '0';
	SIGNAL PWMout_o							: STD_LOGIC;
	SIGNAL LEDR_o							: STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL HEX0_o							: STD_LOGIC_VECTOR(6 DOWNTO 0);
	SIGNAL HEX1_o							: STD_LOGIC_VECTOR(6 DOWNTO 0);
	SIGNAL HEX2_o							: STD_LOGIC_VECTOR(6 DOWNTO 0);
	SIGNAL HEX3_o							: STD_LOGIC_VECTOR(6 DOWNTO 0);
	SIGNAL HEX4_o							: STD_LOGIC_VECTOR(6 DOWNTO 0);
	SIGNAL HEX5_o							: STD_LOGIC_VECTOR(6 DOWNTO 0);

BEGIN
	-- The DUT is the whole MCU. Since Sprint 0 the core is a bus master with
	-- no data memory of its own, so it cannot run a program on its own.
	CORE : MCU
	generic map(
		WORD_GRANULARITY 	=> WORD_GRANULARITY,
	  MODELSIM 					=> MODELSIM,
		SIGTAP						=> SIGTAP,
		DATA_BUS_WIDTH		=> DATA_BUS_WIDTH,
		ITCM_ADDR_WIDTH		=> ITCM_ADDR_WIDTH,
		DTCM_ADDR_WIDTH		=> DTCM_ADDR_WIDTH,
		PC_WIDTH					=> PC_WIDTH,
		MA_WIDTH					=> MA_WIDTH,
		DATA_WORDS_NUM		=> DATA_WORDS_NUM,
		DA_WIDTH					=> DA_WIDTH,
		CLK_CNT_WIDTH			=> CLK_CNT_WIDTH,
		ITCM_INIT_FILE		=> ITCM_INIT_FILE,
		DTCM_INIT_FILE		=> DTCM_INIT_FILE
	)
	PORT MAP (
		--Inputs
		rst_i           	=> rst_i,
		clk_i           	=> clk_i,
		SW_i							=> SW_i,							-- PORT_SW  0x2010
		KEY_i							=> KEY_i,							-- PORT_PB 0x2014
		CAPIN1_i					=> CAPIN1_i,					-- Basic Timer capture input 1
		CAPIN2_i					=> CAPIN2_i,					-- Basic Timer capture input 2

		--Memory-mapped I/O pins
		LEDR_o						=> LEDR_o,						-- PORT_LEDR 0x2000
		PWMout_o					=> PWMout_o,					-- Basic Timer PWM output
		HEX0_o						=> HEX0_o,						-- 0x2004
		HEX1_o						=> HEX1_o,						-- 0x2005
		HEX2_o						=> HEX2_o,						-- 0x2008
		HEX3_o						=> HEX3_o,						-- 0x2009
		HEX4_o						=> HEX4_o,						-- 0x200C
		HEX5_o						=> HEX5_o,						-- 0x200D

		--Outputs
		pc_o							=> pc_o,							-- IFETCH output
		instruction_o			=> instruction_o,			-- IFETCH output
		
		RegWrite_ctrl_o		=> RegWrite_ctrl_o,		-- CONTROL output
		MemWrite_ctrl_o		=> MemWrite_ctrl_o,		-- CONTROL output
		Branch_ctrl_o			=> Branch_ctrl_o,			-- CONTROL output
		
		read_data1_o 			=> read_data1_o,			-- IDECODE output
		read_data2_o 			=> read_data2_o,			-- IDECODE output
		write_data_o			=> write_data_o,			-- IDECODE input(Write-Back) 
		
		alu_res_o 				=> alu_res_o,					-- EXECUTE output															
		brTaken_o					=> brTaken_o,					-- EXECUTE output 
		
		dtcm_addr_o				=> dtcm_addr_o,				-- DMEMORY input
		dtcm_data_wr_o		=> dtcm_data_wr_o,		-- DMEMORY input
		dtcm_data_rd_o		=> dtcm_data_rd_o,		-- DMEMORY output

		smclk_o						=> smclk_o,						-- Basic Timer clock

		mclk_cnt_o				=> mclk_cnt_o					-- TOP output
	);
--------------------------------------------------------------------
	-- 50 MHz, the DE10-Standard board oscillator. This is the PLL reference
	-- clock, so it has to be the real frequency: the three PLLs are generated
	-- for a 50 MHz refclk and would produce the wrong outputs from anything
	-- else. (It used to be 100 ns / 10 MHz, which was harmless only because
	-- the clocks were derived by a toggle flip-flop rather than by a PLL.)
	gen_clk :
	process
  begin
		clk_i <= '1';
		wait for 10 ns;
		clk_i <= not clk_i;
		wait for 10 ns;
  end process;

	-- Long enough for a real PLL to lock when MODELSIM = 0. The cycle counter
	-- is reset-cleared and only starts on release, so a longer reset costs
	-- simulation time but does not affect the reported cycle count.
	gen_rst :
	process
  begin
		rst_i <='1','0' after 2 us;
		wait;
  end process;
--------------------------------------------------------------------		
END struct;

