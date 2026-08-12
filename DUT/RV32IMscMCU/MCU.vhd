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
USE work.clk_config_package.all;
USE work.aux_package.all;


ENTITY MCU IS
	generic(
		WORD_GRANULARITY 	: boolean 	:= G_WORD_GRANULARITY;
		MODELSIM 			: integer 	:= G_MODELSIM;
		-- 1 exposes the observation outputs below, 0 removes them. See the
		-- note on their declaration; the testbench passes 1, Quartus takes
		-- the default 0 so the design presents only the board I/O of clause 5.
		SIGTAP				: integer	:= G_SIGTAP;
		DATA_BUS_WIDTH 		: integer 	:= 32;
		ITCM_ADDR_WIDTH 	: integer 	:= G_ADDRWIDTH;
		DTCM_ADDR_WIDTH 	: integer 	:= G_ADDRWIDTH;
		PC_WIDTH 			: integer 	:= G_PC_WIDTH;
		MA_WIDTH 			: integer 	:= G_MA_WIDTH;
		DATA_WORDS_NUM 		: integer 	:= G_DATA_WORDSNUM;
		DA_WIDTH			: integer 	:= G_DA_WIDTH;
		CLK_CNT_WIDTH 		: integer 	:= 16;
		-- Clause 5 maps only LEDR7..LEDR0 and SW7..SW0, although the board
		-- carries ten of each. LEDR9, LEDR8, SW9 and SW8 stay unconnected.
		LEDR_WIDTH			: integer	:= 8;
		SW_WIDTH			: integer	:= 8;
		ITCM_INIT_FILE		: string	:= "C:\Users\oripa\Documents\Benchmark_Apps\Final Project Tests\GPIO\test0\bin\M9K-intel\ITCM.hex";
		DTCM_INIT_FILE		: string	:= "C:\Users\oripa\Documents\Benchmark_Apps\Final Project Tests\GPIO\test0\bin\M9K-intel\DTCM.hex"
	);
	PORT(
		--Inputs
		rst_i		 		:IN	STD_LOGIC;
		clk_i				:IN	STD_LOGIC;	-- 50 MHz board clock

		SW_i				:IN	STD_LOGIC_VECTOR(SW_WIDTH-1 DOWNTO 0);	-- PORT_SW   0x2010

		--=====================================================================
		-- Memory-mapped I/O pins (Figure 5, clause 5)
		--   PORT_LEDR  0x2000    PORT_SW  0x2010
		--   HEX0 0x2004  HEX1 0x2005  HEX2 0x2008
		--   HEX3 0x2009  HEX4 0x200C  HEX5 0x200D
		-- Segment vectors are g f e d c b a, active low.
		--=====================================================================
		LEDR_o				:OUT	STD_LOGIC_VECTOR(LEDR_WIDTH-1 DOWNTO 0);
		HEX0_o				:OUT	STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX1_o				:OUT	STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX2_o				:OUT	STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX3_o				:OUT	STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX4_o				:OUT	STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX5_o				:OUT	STD_LOGIC_VECTOR(6 DOWNTO 0);

		--=====================================================================
		-- Observation outputs, for verification and for FPGA validation.
		--
		-- Multiplying each width by SIGTAP is what clause 7 asks for: with
		-- SIGTAP=0 every range below becomes (-1 DOWNTO 0), a null array, so
		-- the port carries no bits and Quartus creates no pins for it. With
		-- SIGTAP=1 the ranges are the full widths the testbench expects.
		-- 267 of the 272 observation bits disappear this way.
		--=====================================================================
		pc_o				:OUT	STD_LOGIC_VECTOR(PC_WIDTH*SIGTAP-1 DOWNTO 0);
		instruction_o		:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH*SIGTAP-1 DOWNTO 0);

		-- These five are std_logic, which has no null form, so they stay.
		-- Five pins is a price worth paying; smclk_o in particular must stay,
		-- because it is the only load on PLL_SMCLK and removing it would let
		-- Quartus strip that PLL out of the design and out of the PPA report.
		RegWrite_ctrl_o		:OUT 	STD_LOGIC;
		MemWrite_ctrl_o		:OUT 	STD_LOGIC;
		Branch_ctrl_o		:OUT 	STD_LOGIC;

		read_data1_o 		:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH*SIGTAP-1 DOWNTO 0);
		read_data2_o 		:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH*SIGTAP-1 DOWNTO 0);
		write_data_o		:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH*SIGTAP-1 DOWNTO 0);

		alu_res_o 			:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH*SIGTAP-1 DOWNTO 0);
		brTaken_o			:OUT 	STD_LOGIC;

		dtcm_addr_o			:OUT 	STD_LOGIC_VECTOR(DA_WIDTH*SIGTAP-1 DOWNTO 0);
		dtcm_data_wr_o		:OUT 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH*SIGTAP-1 DOWNTO 0);
		dtcm_data_rd_o		:OUT 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH*SIGTAP-1 DOWNTO 0);

		-- SMCLK is generated here for the Basic Timer, which is not
		-- instantiated yet. Brought out so the clock is observable and so its
		-- PLL is not optimised away as dead logic before the timer arrives.
		smclk_o				:OUT	STD_LOGIC;

		mclk_cnt_o			:OUT	STD_LOGIC_VECTOR(CLK_CNT_WIDTH*SIGTAP-1 DOWNTO 0)
	);
END MCU;
--============================================================================
ARCHITECTURE structure OF MCU IS
	-- The reset every module actually sees.
	--
	-- KEY0 is the system reset (see the task note), and the DE10-Standard
	-- pushbuttons are active low - the manual is explicit: "The push-button
	-- generates a low logic level when it is pressed". Everything downstream
	-- is active high, the three PLL rst_reset inputs included, so on the FPGA
	-- the pin has to be inverted here. Without this the board sits in
	-- permanent reset with no clocks whenever KEY0 is not held down.
	--
	-- In simulation the testbench drives rst_i active high directly, so the
	-- inversion is skipped and every existing .do script keeps working.
	SIGNAL rst_w			: STD_LOGIC;

	-- Observation taps. The CPU drives these; whether they reach a pin is
	-- decided by SIGTAP_GEN at the bottom of the file.
	SIGNAL pc_w				: STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
	SIGNAL instruction_w	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL read_data1_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL read_data2_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL write_data_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL alu_res_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL mclk_cnt_w		: STD_LOGIC_VECTOR(CLK_CNT_WIDTH-1 DOWNTO 0);

	-- Clocks. Initialised because the MODELSIM=1 clock generators below are
	-- self-triggering assignments, which never start from 'U'.
	SIGNAL mclk_w			: STD_LOGIC := '0';
	SIGNAL divclk_w			: STD_LOGIC := '0';
	SIGNAL smclk_w			: STD_LOGIC := '0';

	--=======================================
	-- One PLL per clock, as required. All three are generated by
	-- QUARTUS/gen_plls.tcl from a 50 MHz board reference and all three have
	-- the same interface, differing only in the output frequency baked into
	-- the IP. locked is left unused, matching the PLL supplied with LAB4.
	--=======================================
	COMPONENT PLL_MCLK IS
		PORT (
			outclk_0_clk	: OUT	STD_LOGIC;
			refclk_clk		: IN	STD_LOGIC := '0';
			rst_reset		: IN	STD_LOGIC := '0'
		);
	END COMPONENT;

	COMPONENT PLL_DIVCLK IS
		PORT (
			outclk_0_clk	: OUT	STD_LOGIC;
			refclk_clk		: IN	STD_LOGIC := '0';
			rst_reset		: IN	STD_LOGIC := '0'
		);
	END COMPONENT;

	COMPONENT PLL_SMCLK IS
		PORT (
			outclk_0_clk	: OUT	STD_LOGIC;
			refclk_clk		: IN	STD_LOGIC := '0';
			rst_reset		: IN	STD_LOGIC := '0'
		);
	END COMPONENT;

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

	-- Memory-mapped I/O. One chip select per device out of the GPIO decoder,
	-- one read path back from each; exactly one cs is ever asserted, so the
	-- read paths are OR-ed rather than multiplexed (see the read mux below).
	SIGNAL cs_ledr_w		: STD_LOGIC;
	SIGNAL cs_hex0_1_w		: STD_LOGIC;
	SIGNAL cs_hex2_3_w		: STD_LOGIC;
	SIGNAL cs_hex4_5_w		: STD_LOGIC;
	SIGNAL cs_sw_w			: STD_LOGIC;

	SIGNAL rd_ledr_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL rd_hex0_1_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL rd_hex2_3_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL rd_hex4_5_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL rd_sw_w			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

	-- The shared I/O read bus of Figure 5. Every port reaches it through a
	-- BidirPin, so this signal genuinely has six drivers and relies on
	-- std_logic resolution; it must not be assigned anywhere else.
	SIGNAL io_bus_w			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

	-- Output enables, one per tri-state buffer. Exactly one is '1' at any
	-- instant: the chip selects are one-hot, and oe_none_w is their NOR.
	SIGNAL oe_ledr_w		: STD_LOGIC;
	SIGNAL oe_hex0_1_w		: STD_LOGIC;
	SIGNAL oe_hex2_3_w		: STD_LOGIC;
	SIGNAL oe_hex4_5_w		: STD_LOGIC;
	SIGNAL oe_sw_w			: STD_LOGIC;
	SIGNAL oe_none_w		: STD_LOGIC;

	-- What BUF_NONE parks the bus at. A plain signal rather than an aggregate
	-- in the port map: BidirPin's Dout is an IN port, and only VHDL-2008
	-- accepts an expression there.
	SIGNAL io_park_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

BEGIN

	--=======================================
	-- Reset polarity
	--=======================================
	rst_w	<= rst_i WHEN MODELSIM = 1 ELSE NOT rst_i;

	--=======================================
	-- Clock generation
	--
	-- Three clocks, one PLL each, all from the 50 MHz board oscillator:
	--
	--   MCLK     25 MHz    CPU
	--   DIVCLK  200 MHz    division accelerator
	--   SMCLK    25 MHz    Basic Timer
	--
	-- The frequencies live in clk_config_package.vhd, which is GENERATED by
	-- QUARTUS/gen_plls.tcl from the same numbers it builds the IP with. To
	-- retune a clock, edit that script and run QUARTUS\gen_plls.bat; the two
	-- branches below then track each other automatically.
	--
	-- MODELSIM = 0 (FPGA)  instantiate the PLL IP
	-- MODELSIM = 1 (sim)   generate the clocks behaviourally
	--
	-- The simulation branch exists so a ModelSim run needs neither the Intel
	-- simulation libraries nor a PLL lock delay. It is not a different clock
	-- plan - both branches run at exactly the frequencies above, because both
	-- read them from the same generated package. Simulating the real IP is
	-- still possible: leave MODELSIM at 0 and the PLL models are compiled in.
	--
	-- Quartus note: each PLL output is a generated clock, so the .sdc needs a
	-- create_clock on clk_i and derive_pll_clocks to pick up all three.
	--=======================================
	CLK_FPGA: if MODELSIM = 0 generate
		U_PLL_MCLK: PLL_MCLK
		PORT MAP (
			refclk_clk		=> clk_i,
			rst_reset		=> rst_w,
			outclk_0_clk	=> mclk_w
		);

		U_PLL_DIVCLK: PLL_DIVCLK
		PORT MAP (
			refclk_clk		=> clk_i,
			rst_reset		=> rst_w,
			outclk_0_clk	=> divclk_w
		);

		U_PLL_SMCLK: PLL_SMCLK
		PORT MAP (
			refclk_clk		=> clk_i,
			rst_reset		=> rst_w,
			outclk_0_clk	=> smclk_w
		);
	end generate;

	CLK_SIM: if MODELSIM = 1 generate
		-- Half period in ns: 1000/f gives the period in ns for f in MHz.
		-- Deliberately not synthesizable - this branch must never reach
		-- Quartus, and if MODELSIM is left at 1 by mistake it will fail loudly
		-- there rather than quietly building the wrong hardware.
		CONSTANT MCLK_HALF		: TIME := (500.0 / G_MCLK_MHZ)   * 1 ns;
		CONSTANT DIVCLK_HALF	: TIME := (500.0 / G_DIVCLK_MHZ) * 1 ns;
		CONSTANT SMCLK_HALF		: TIME := (500.0 / G_SMCLK_MHZ)  * 1 ns;
	begin
		mclk_w		<= NOT mclk_w	AFTER MCLK_HALF;
		divclk_w	<= NOT divclk_w	AFTER DIVCLK_HALF;
		smclk_w		<= NOT smclk_w	AFTER SMCLK_HALF;
	end generate;

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
		rst_i				=> rst_w,
		mclk_i				=> mclk_w,
		divclk_i			=> divclk_w,
		dtcm_data_rd_i		=> bus_rdata_w,

		--Data bus, master side
		dtcm_addr_o			=> bus_addr_w,
		dtcm_data_wr_o		=> bus_wdata_w,
		MemRead_ctrl_o		=> bus_read_w,
		MemWrite_ctrl_o		=> bus_write_w,

		--Observation. Into signals, not straight out to the ports: the ports
		--are null when SIGTAP=0, so SIGTAP_GEN decides whether they are
		--driven at all. The signals stay full width either way, which is what
		--Signal-Tap taps.
		pc_o				=> pc_w,
		instruction_o		=> instruction_w,
		RegWrite_ctrl_o		=> RegWrite_ctrl_o,
		Branch_ctrl_o		=> Branch_ctrl_o,
		read_data1_o		=> read_data1_w,
		read_data2_o		=> read_data2_w,
		write_data_o		=> write_data_w,
		alu_res_o			=> alu_res_w,
		brTaken_o			=> brTaken_o,
		mclk_cnt_o			=> mclk_cnt_w
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
		rst_i 				=> rst_w,
		dtcm_addr_i 		=> dtcm_addr_w,
		dtcm_data_wr_i 		=> bus_wdata_w,
		MemRead_ctrl_i 		=> dtcm_rd_w,
		MemWrite_ctrl_i 	=> dtcm_we_w,

		--Outputs
		dtcm_data_rd_o 		=> dtcm_q_w
	);

	--=======================================
	-- Memory-mapped I/O (Figure 5)
	--=======================================
	-- The GPIO decoder turns the byte address into one chip select per device;
	-- no port module inspects the address bus itself. MemRead / MemWrite are
	-- passed through unqualified because every port already gates them with
	-- its own cs_i, and cs_i is only asserted inside the I/O region.
	--
	-- All GPIO registers are clocked by MCLK. They capture on its FALLING
	-- edge, as does the DTCM (dmemory inverts the clock into altsyncram), so
	-- every target on the data bus latches write data at the same instant.
	IODEC: GPIO_AddressDecoder
	generic map(
		DA_WIDTH			=> DA_WIDTH
	)
	PORT MAP (
		--Inputs
		en_i				=> io_sel_w,
		addr_i				=> bus_addr_w,

		--Outputs
		cs_ledr_o			=> cs_ledr_w,
		cs_hex0_1_o			=> cs_hex0_1_w,
		cs_hex2_3_o			=> cs_hex2_3_w,
		cs_hex4_5_o			=> cs_hex4_5_w,
		cs_sw_o				=> cs_sw_w
	);

	IOLEDR: GPIO_LEDR_Interface
	generic map(
		DATA_BUS_WIDTH		=> DATA_BUS_WIDTH,
		LEDR_WIDTH			=> LEDR_WIDTH
	)
	PORT MAP (
		--Inputs
		clk_i				=> mclk_w,
		rst_i				=> rst_w,
		cs_i				=> cs_ledr_w,
		MemRead_ctrl_i		=> bus_read_w,
		MemWrite_ctrl_i		=> bus_write_w,
		data_wr_i			=> bus_wdata_w,

		--Outputs
		data_rd_o			=> rd_ledr_w,
		LEDR_o				=> LEDR_o
	);

	IOSW: GPIO_SW_Interface
	generic map(
		DATA_BUS_WIDTH		=> DATA_BUS_WIDTH,
		SW_WIDTH			=> SW_WIDTH
	)
	PORT MAP (
		--Inputs
		cs_i				=> cs_sw_w,
		MemRead_ctrl_i		=> bus_read_w,
		SW_i				=> SW_i,

		--Outputs
		data_rd_o			=> rd_sw_w
	);

	-- One instance per pair of displays. Inside a pair the two addresses
	-- differ in bit 0 only, so the decoder selects the pair and bit 0 of the
	-- byte address picks the digit: even address -> lo, odd address -> hi.
	IOHEX01: GPIO_HEX_Pair_Interface
	generic map(
		DATA_BUS_WIDTH		=> DATA_BUS_WIDTH
	)
	PORT MAP (
		--Inputs
		clk_i				=> mclk_w,
		rst_i				=> rst_w,
		cs_i				=> cs_hex0_1_w,
		sel_i				=> bus_addr_w(0),
		MemRead_ctrl_i		=> bus_read_w,
		MemWrite_ctrl_i		=> bus_write_w,
		data_wr_i			=> bus_wdata_w,

		--Outputs
		data_rd_o			=> rd_hex0_1_w,
		HEX_lo_o			=> HEX0_o,			-- 0x2004
		HEX_hi_o			=> HEX1_o			-- 0x2005
	);

	IOHEX23: GPIO_HEX_Pair_Interface
	generic map(
		DATA_BUS_WIDTH		=> DATA_BUS_WIDTH
	)
	PORT MAP (
		--Inputs
		clk_i				=> mclk_w,
		rst_i				=> rst_w,
		cs_i				=> cs_hex2_3_w,
		sel_i				=> bus_addr_w(0),
		MemRead_ctrl_i		=> bus_read_w,
		MemWrite_ctrl_i		=> bus_write_w,
		data_wr_i			=> bus_wdata_w,

		--Outputs
		data_rd_o			=> rd_hex2_3_w,
		HEX_lo_o			=> HEX2_o,			-- 0x2008
		HEX_hi_o			=> HEX3_o			-- 0x2009
	);

	IOHEX45: GPIO_HEX_Pair_Interface
	generic map(
		DATA_BUS_WIDTH		=> DATA_BUS_WIDTH
	)
	PORT MAP (
		--Inputs
		clk_i				=> mclk_w,
		rst_i				=> rst_w,
		cs_i				=> cs_hex4_5_w,
		sel_i				=> bus_addr_w(0),
		MemRead_ctrl_i		=> bus_read_w,
		MemWrite_ctrl_i		=> bus_write_w,
		data_wr_i			=> bus_wdata_w,

		--Outputs
		data_rd_o			=> rd_hex4_5_w,
		HEX_lo_o			=> HEX4_o,			-- 0x200C
		HEX_hi_o			=> HEX5_o			-- 0x200D
	);

	--=======================================
	-- The shared I/O bus - the tri-state buffers of Figure 5
	--=======================================
	-- Figure 5 draws each peripheral reaching the data bus through a
	-- tri-state buffer, and BidirPin.vhd is that buffer: it drives IOpin with
	-- Dout while en = '1' and releases it to 'Z' otherwise. One instance per
	-- device, all sharing io_bus_w, is the figure drawn literally.
	--
	-- Only the port -> CPU direction is built here. BidirPin also brings the
	-- bus back out on Din, which is what a truly bidirectional data bus would
	-- use to deliver store data, but this core has separate write and read
	-- buses (bus_wdata_w and bus_rdata_w out of RV32I_CORE), so store data
	-- reaches the ports on bus_wdata_w and every Din is left open.
	--
	-- Cyclone V has no internal tri-state. Quartus resolves these buffers
	-- into a multiplexer during synthesis, which is why the ports also drive
	-- zeros when deselected: the behaviour is identical either way.
	oe_ledr_w	<= cs_ledr_w	AND bus_read_w;
	oe_hex0_1_w	<= cs_hex0_1_w	AND bus_read_w;
	oe_hex2_3_w	<= cs_hex2_3_w	AND bus_read_w;
	oe_hex4_5_w	<= cs_hex4_5_w	AND bus_read_w;
	oe_sw_w		<= cs_sw_w		AND bus_read_w;

	-- A bus with every buffer released floats at 'Z', and 'Z' propagated into
	-- the register file would show up as red in the wave window and as
	-- metavalue warnings rather than as data. BUF_NONE parks the bus at zero
	-- whenever no device is driving it, which also gives the reads-as-zero
	-- behaviour that unmapped I/O addresses need - 0x2014, 0x2018, 0x201C and
	-- everything from 0x2020 up, all reserved for the peripherals of clause 6.
	oe_none_w	<= NOT (oe_ledr_w OR oe_hex0_1_w OR oe_hex2_3_w OR oe_hex4_5_w OR oe_sw_w);

	BUF_LEDR: BidirPin
	generic map(width => DATA_BUS_WIDTH)
	PORT MAP (Dout => rd_ledr_w,	en => oe_ledr_w,	Din => OPEN, IOpin => io_bus_w);

	BUF_HEX01: BidirPin
	generic map(width => DATA_BUS_WIDTH)
	PORT MAP (Dout => rd_hex0_1_w,	en => oe_hex0_1_w,	Din => OPEN, IOpin => io_bus_w);

	BUF_HEX23: BidirPin
	generic map(width => DATA_BUS_WIDTH)
	PORT MAP (Dout => rd_hex2_3_w,	en => oe_hex2_3_w,	Din => OPEN, IOpin => io_bus_w);

	BUF_HEX45: BidirPin
	generic map(width => DATA_BUS_WIDTH)
	PORT MAP (Dout => rd_hex4_5_w,	en => oe_hex4_5_w,	Din => OPEN, IOpin => io_bus_w);

	BUF_SW: BidirPin
	generic map(width => DATA_BUS_WIDTH)
	PORT MAP (Dout => rd_sw_w,		en => oe_sw_w,		Din => OPEN, IOpin => io_bus_w);

	io_park_w	<= (OTHERS => '0');

	BUF_NONE: BidirPin
	generic map(width => DATA_BUS_WIDTH)
	PORT MAP (Dout => io_park_w,	en => oe_none_w,	Din => OPEN, IOpin => io_bus_w);

	--=======================================
	-- Read data multiplexer
	--=======================================
	-- The last hop: bit 13 of the address picks between the I/O bus and the
	-- DTCM. This one is a real multiplexer, not a shared bus - the DTCM
	-- output is an altsyncram q port and never goes high impedance.
	bus_rdata_w	<= io_bus_w WHEN io_sel_w = '1' ELSE dtcm_q_w;

---------------------------------------------------------------------------------------
-- Copying out important signals only for Verification and FPGA Velidation(Signal-TAP)
---------------------------------------------------------------------------------------
	-- std_logic ports, no null form, so these are always driven. Five pins.
	MemWrite_ctrl_o		<=	bus_write_w;							-- CORE output, stall applied
	smclk_o				<=	smclk_w;								-- Basic Timer clock

	-- Everything with a width is driven only when SIGTAP=1. With SIGTAP=0 the
	-- ports are null arrays and this whole block disappears, which is how
	-- clause 7's "removed in the final step using a suitable parameter in the
	-- generate VHDL statement" is satisfied. Signal-Tap is unaffected: it taps
	-- the internal signals over JTAG and needs no pins.
	SIGTAP_GEN: if SIGTAP = 1 generate
		pc_o			<=	pc_w;									-- IFETCH output
		instruction_o	<=	instruction_w;							-- IFETCH output

		read_data1_o	<=	read_data1_w;							-- IDECODE output
		read_data2_o	<=	read_data2_w;							-- IDECODE output
		write_data_o	<=	write_data_w;							-- IDECODE write-back

		alu_res_o		<=	alu_res_w;								-- EXECUTE output

		dtcm_addr_o 	<= 	bus_addr_w;								-- data bus, byte address
		dtcm_data_wr_o 	<= 	bus_wdata_w;							-- data bus, write data
		dtcm_data_rd_o	<=	bus_rdata_w;							-- data bus, read data

		mclk_cnt_o		<=	mclk_cnt_w;								-- MCLK cycle counter
	end generate;
---------------------------------------------------------------------------------------

END structure;
