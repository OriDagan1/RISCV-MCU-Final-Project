--============================================================================
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- MCU - top level (Figure 1)
--
-- Everything outside the CPU lives here: clock generation, the data memory,
-- and the address decode that will shortly also route memory-mapped I/O.
-- The core is a bus master that drives a byte address across the whole data
-- address space of Figure 2 and takes back read data; which device answers
-- is decided here and nowhere else.
--
--   Data address space (Figure 2), 14-bit byte address:
--     0x0000 - 0x1FFF   DTCM, 8 KiB
--     0x2000 - 0x3FFF   memory-mapped I/O
--   so bit 13 of the byte address is the DTCM / I/O select.
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
use ieee.std_logic_unsigned.all;
USE work.cond_compilation_package.all;
USE work.aux_package.all;


ENTITY MCU IS
	generic(
		WORD_GRANULARITY 	: boolean 	:= G_WORD_GRANULARITY;
		MODELSIM 			: integer 	:= G_MODELSIM;
		DATA_BUS_WIDTH 		: integer 	:= 32;
		ITCM_ADDR_WIDTH 	: integer 	:= G_ADDRWIDTH;
		DTCM_ADDR_WIDTH 	: integer 	:= G_ADDRWIDTH;
		PC_WIDTH 			: integer 	:= G_PC_WIDTH;
		MA_WIDTH 			: integer 	:= G_MA_WIDTH;
		DATA_WORDS_NUM 		: integer 	:= G_DATA_WORDSNUM;
		DA_WIDTH			: integer 	:= G_DA_WIDTH;
		CLK_CNT_WIDTH 		: integer 	:= 16;
		ITCM_INIT_FILE		: string	:= "C:\Users\oripa\Documents\Benchmark_Apps\test3\RV32IM\bin\M9K-intel\ITCM.hex";
		DTCM_INIT_FILE		: string	:= "C:\Users\oripa\Documents\Benchmark_Apps\test3\RV32IM\bin\M9K-intel\DTCM.hex"
	);
	PORT(
		--Inputs
		rst_i		 		:IN	STD_LOGIC;
		clk_i				:IN	STD_LOGIC;	-- 50 MHz board clock

		--=====================================================================
		-- TODO(feature/gpio): the I/O pins land here.
		--   PORT_LEDR  0x2000    PORT_SW  0x2010
		--   HEX0 0x2004  HEX1 0x2005  HEX2 0x2008
		--   HEX3 0x2009  HEX4 0x200C  HEX5 0x200D
		--=====================================================================

		--Outputs (used also for Signal-Tap auxiliary pins)
		pc_o				:OUT	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
		instruction_o		:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

		RegWrite_ctrl_o		:OUT 	STD_LOGIC;
		MemWrite_ctrl_o		:OUT 	STD_LOGIC;
		Branch_ctrl_o		:OUT 	STD_LOGIC;

		read_data1_o 		:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
		read_data2_o 		:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
		write_data_o		:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

		alu_res_o 			:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
		brTaken_o			:OUT 	STD_LOGIC;

		dtcm_addr_o			:OUT 	STD_LOGIC_VECTOR(DA_WIDTH-1 DOWNTO 0);
		dtcm_data_wr_o		:OUT 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
		dtcm_data_rd_o		:OUT 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

		mclk_cnt_o			:OUT	STD_LOGIC_VECTOR(CLK_CNT_WIDTH-1 DOWNTO 0)
	);
END MCU;
--============================================================================
ARCHITECTURE structure OF MCU IS
	-- Clocks
	SIGNAL mclk_w			: STD_LOGIC;
	SIGNAL divclk_w			: STD_LOGIC;
	SIGNAL mclk_q			: STD_LOGIC;

	-- Data bus
	SIGNAL bus_addr_w		: STD_LOGIC_VECTOR(DA_WIDTH-1 DOWNTO 0);
	SIGNAL bus_wdata_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL bus_rdata_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL bus_read_w		: STD_LOGIC;
	SIGNAL bus_write_w		: STD_LOGIC;
	SIGNAL io_sel_w			: STD_LOGIC;

	-- DTCM
	SIGNAL dtcm_addr_w		: STD_LOGIC_VECTOR(DTCM_ADDR_WIDTH-1 DOWNTO 0);
	SIGNAL dtcm_we_w		: STD_LOGIC;
	SIGNAL dtcm_rd_w		: STD_LOGIC;
	SIGNAL dtcm_q_w			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

BEGIN

	--=======================================
	-- Clock generation
	--
	-- DIVCLK is the incoming board clock; MCLK is derived from it by a single
	-- toggle flip-flop, so the accelerator runs at twice the CPU rate. This
	-- replaces the supplied ALTPLL, which is a Cyclone II megafunction and is
	-- not supported on the Cyclone V of the DE10-Standard. The 2:1 ratio is
	-- the one the PLL was configured for (G_PLL_DIV=2, G_PLL_MUL=1), so the
	-- CPU sees the same clock it always saw.
	--
	-- MCLK is a derived clock, so the .sdc needs a create_generated_clock on
	-- mclk_q for Quartus to time it properly.
	--=======================================
	divclk_w <= clk_i;

	CLKDIV:
	process (clk_i, rst_i)
	begin
		if rst_i = '1' then
			mclk_q	<= '0';
		elsif rising_edge(clk_i) then
			mclk_q	<= NOT mclk_q;
		end if;
	end process;

	mclk_w <= mclk_q;

	--=======================================
	-- CPU core
	--=======================================
	CPU: RV32I_CORE
	generic map(
		WORD_GRANULARITY	=>	WORD_GRANULARITY,
		MODELSIM			=>	MODELSIM,
		DATA_BUS_WIDTH		=>	DATA_BUS_WIDTH,
		ITCM_ADDR_WIDTH		=>	ITCM_ADDR_WIDTH,
		DTCM_ADDR_WIDTH		=>	DTCM_ADDR_WIDTH,
		PC_WIDTH			=>	PC_WIDTH,
		MA_WIDTH			=>	MA_WIDTH,
		DATA_WORDS_NUM		=>	DATA_WORDS_NUM,
		DA_WIDTH			=>	DA_WIDTH,
		CLK_CNT_WIDTH		=>	CLK_CNT_WIDTH,
		ITCM_INIT_FILE		=>	ITCM_INIT_FILE
	)
	PORT MAP (
		--Inputs
		rst_i				=> rst_i,
		mclk_i				=> mclk_w,
		divclk_i			=> divclk_w,
		dtcm_data_rd_i		=> bus_rdata_w,

		--Data bus, master side
		dtcm_addr_o			=> bus_addr_w,
		dtcm_data_wr_o		=> bus_wdata_w,
		MemRead_ctrl_o		=> bus_read_w,
		MemWrite_ctrl_o		=> bus_write_w,

		--Observation
		pc_o				=> pc_o,
		instruction_o		=> instruction_o,
		RegWrite_ctrl_o		=> RegWrite_ctrl_o,
		Branch_ctrl_o		=> Branch_ctrl_o,
		read_data1_o		=> read_data1_o,
		read_data2_o		=> read_data2_o,
		write_data_o		=> write_data_o,
		alu_res_o			=> alu_res_o,
		brTaken_o			=> brTaken_o,
		mclk_cnt_o			=> mclk_cnt_o
	);

	--=======================================
	-- Address decode
	--=======================================
	-- Bit 13 of the byte address splits the 16 KiB data address space in two:
	-- low half DTCM, high half memory-mapped I/O.
	io_sel_w	<= bus_addr_w(DA_WIDTH-1);

	dtcm_we_w	<= bus_write_w	AND NOT io_sel_w;
	dtcm_rd_w	<= bus_read_w	AND NOT io_sel_w;

	-- The DTCM is word addressed, so drop the two byte-offset bits. MA_WIDTH
	-- spans the DTCM only (13 bits = 8 KiB), which is exactly one bit less
	-- than the bus, so bit 13 is excluded here by construction.
	G1:
	if (WORD_GRANULARITY = True) generate	-- i.e. each WORD has a unike address
		dtcm_addr_w	<= bus_addr_w(MA_WIDTH-1 DOWNTO 2);
	elsif (WORD_GRANULARITY = False) generate	-- i.e. each BYTE has a unike address
		dtcm_addr_w	<= bus_addr_w(DTCM_ADDR_WIDTH-1 DOWNTO 0);
	end generate;

	--=======================================
	-- DTCM module connection
	--=======================================
	MEM: dmemory
	generic map(
		DATA_BUS_WIDTH		=> 	DATA_BUS_WIDTH,
		DTCM_ADDR_WIDTH		=> 	DTCM_ADDR_WIDTH,
		WORDS_NUM			=>	DATA_WORDS_NUM,
		DTCM_INIT_FILE		=>	DTCM_INIT_FILE
	)
	PORT MAP (
		--Inputs
		clk_i 				=> mclk_w,
		rst_i 				=> rst_i,
		dtcm_addr_i 		=> dtcm_addr_w,
		dtcm_data_wr_i 		=> bus_wdata_w,
		MemRead_ctrl_i 		=> dtcm_rd_w,
		MemWrite_ctrl_i 	=> dtcm_we_w,

		--Outputs
		dtcm_data_rd_o 		=> dtcm_q_w
	);

	--=======================================
	-- Read data multiplexer
	--=======================================
	-- TODO(feature/gpio): becomes
	--     bus_rdata_w <= io_rdata_w WHEN io_sel_w = '1' ELSE dtcm_q_w;
	-- once the I/O block exists. Until then every read is answered by the
	-- DTCM, which is exactly the behaviour before this file was split out.
	bus_rdata_w	<= dtcm_q_w;

---------------------------------------------------------------------------------------
-- Copying out important signals only for Verification and FPGA Velidation(Signal-TAP)
---------------------------------------------------------------------------------------
	MemWrite_ctrl_o		<=	bus_write_w;							-- CORE output, stall applied

	dtcm_addr_o 		<= 	bus_addr_w;								-- data bus, byte address
	dtcm_data_wr_o 		<= 	bus_wdata_w;							-- data bus, write data
	dtcm_data_rd_o		<=	bus_rdata_w;							-- data bus, read data
---------------------------------------------------------------------------------------

END structure;
