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
		ITCM_INIT_FILE		: string	:= G_ITCM_INIT_FILE;
		DTCM_INIT_FILE		: string	:= G_DTCM_INIT_FILE
	);
	PORT(
		--Inputs
		rst_i		 		:IN	STD_LOGIC;
		clk_i				:IN	STD_LOGIC;	-- 50 MHz board clock

		SW_i				:IN	STD_LOGIC_VECTOR(SW_WIDTH-1 DOWNTO 0);	-- PORT_SW   0x2010

		-- KEY3..KEY1, active low and already debounced in hardware (Figure 6),
		-- so this port carries the raw pin levels: no inversion and no
		-- debouncer belongs here - GPIO_PB_Interface expects exactly this.
		-- KEY0 is the system reset (clause 3) and arrives as rst_i instead;
		-- it is never part of this vector.
		KEY_i				:IN	STD_LOGIC_VECTOR(3 DOWNTO 1);	-- PORT_PB   0x2014

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
		-- Basic Timer pins (Fig.7, clause 6). The board has no dedicated
		-- pushbutton-style pins for these, so they go on the 2x20 expansion
		-- header of clause 4 - the same header CAPISEL's internal VCC/GND
		-- test sources exist to let a design skip until wired up.
		--=====================================================================
		PWMout_o			:OUT	STD_LOGIC;	-- Basic Timer PWM output
		CAPIN1_i			:IN		STD_LOGIC;	-- Basic Timer capture input 1
		CAPIN2_i			:IN		STD_LOGIC;	-- Basic Timer capture input 2

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

		-- SMCLK is PLL_SMCLK's output (forum rows 8 and 13: three PLL
		-- instances, one per clock branch of Figure 1). This port is the only
		-- load on that PLL outside the Basic Timer, so it keeps Quartus from
		-- trimming the PLL out of the design and out of the PPA report. It is
		-- also the only pin from which SMCLK - and BTCLK once BT_CLKDIV taps
		-- it - can be observed directly, on a scope or by Signal-Tap, without
		-- instrumenting the Basic Timer itself.
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
	-- is active high, so on the FPGA the pin has to be inverted here. Without
	-- this the board sits in permanent reset whenever KEY0 is not held down.
	-- It does not reach the PLLs - see the note at CLK_FPGA below.
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
	-- One PLL per clock, three in all, as forum row 13 requires ("No - from
	-- three different instances of the PLL module"). All three are generated
	-- by QUARTUS/gen_plls.tcl from the same 50 MHz board reference and share
	-- one IP interface, differing only in the output frequency baked into
	-- each. locked is left unused, matching the PLL supplied with LAB4.
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

	-- Clause 6 chip selects, from PERIPH_AddressDecoder. All six now have a
	-- consumer: cs_pb_w, the four Basic Timer selects, and now cs_ic_w too.
	SIGNAL cs_pb_w			: STD_LOGIC;
	SIGNAL cs_btctl_w		: STD_LOGIC;
	SIGNAL cs_btcmpr0_w		: STD_LOGIC;
	SIGNAL cs_btcmpr1_w		: STD_LOGIC;
	SIGNAL cs_btcapr_w		: STD_LOGIC;
	SIGNAL cs_ic_w			: STD_LOGIC;

	-- PORT_PB read path and interrupt requests. The three IRQ pulses have no
	-- consumer until the interrupt controller lands; see the note there.
	SIGNAL rd_pb_w			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL oe_pb_w			: STD_LOGIC;
	SIGNAL key1_irq_w		: STD_LOGIC;
	SIGNAL key2_irq_w		: STD_LOGIC;
	SIGNAL key3_irq_w		: STD_LOGIC;

	-- Basic Timer registers (BTIF) and the timer core (BT) they front.
	-- btcnt_w and bt_irq_w have no consumer yet, exactly like key1_irq_w..
	-- key3_irq_w above: btcnt_w until something needs to read the raw count,
	-- bt_irq_w until the interrupt controller lands.
	SIGNAL btctl1_w			: STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL btctl2_w			: STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL btcmpr0_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL btcmpr1_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL btcapr_w			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	-- The capture event out of BT, into BTIF's BTCAPR register. Forum row 25
	-- makes BTCAPR read/write, so it is a register in BTIF with two load
	-- sources and this is the one that tells it the timer has a new value.
	SIGNAL capevt_w			: STD_LOGIC;
	SIGNAL btcnt_w			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL btifg_w			: STD_LOGIC;
	SIGNAL bt_irq_w			: STD_LOGIC;
	SIGNAL rd_bt_w			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL oe_bt_w			: STD_LOGIC;

	-- The Basic Interrupt Controller (clause 6.v). rd_ic_w/oe_ic_w follow the
	-- read-path pattern of every other device, but oe_ic_w is NOT cs AND
	-- MemRead here - int_ctrl computes its own bus_drive_o and this signal is
	-- simply that port, because protocol cycle 1 has to put TYPE on the bus
	-- without cs_i ever going high. See the read-path section below.
	--
	-- intr_w has no consumer yet, like bt_irq_w and the key IRQs before it:
	-- the CPU side of the protocol is the next task. gie_w and inta_n_w come
	-- from the CPU in that same task; tied off below in the meantime.
	SIGNAL rd_ic_w			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL oe_ic_w			: STD_LOGIC;
	SIGNAL intr_w			: STD_LOGIC;
	SIGNAL gie_w			: STD_LOGIC;
	SIGNAL inta_n_w			: STD_LOGIC;

	-- The shared I/O read bus of Figure 5. Every port reaches it through a
	-- BidirPin, so this signal genuinely has nine drivers (LEDR, the three
	-- HEX pairs, SW, PB, the Basic Timer group, the interrupt controller and
	-- BUF_NONE) and relies on std_logic resolution; it must not be assigned
	-- anywhere else.
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
	-- Three clocks, one PLL instance each, all fed from the same 50 MHz board
	-- oscillator - one per clock branch of Figure 1:
	--
	--   MCLK     25 MHz    CPU
	--   DIVCLK  200 MHz    division accelerator
	--   SMCLK    25 MHz    Basic Timer
	--
	-- THIS IS THE COURSE FORUM'S ARCHITECTURE, NOT A FREE CHOICE. Row 13 asks
	-- whether the three clocks come from one PLL instance and answers "No -
	-- from three different instances of the PLL module". Row 8 adds that
	-- "DIVCLK is connected to the output of a separate PLL. The input clock of
	-- each of the three PLLs is the 50MHz base clock". Row 16 explains why the
	-- separation is wanted even when two of the frequencies match: it exists
	-- for timing closure, for maximum performance, and to keep the CPU, the
	-- peripherals and the accelerator independent of one another - "in the
	-- basic case of a single-cycle CPU running at a low frequency, the
	-- separation is required and necessary, but their value may be identical,
	-- i.e. MCLK=SMCLK".
	--
	-- SO MCLK AND SMCLK ARE DELIBERATELY THE SAME FREQUENCY, ON SEPARATE PLLs.
	-- That is not a contradiction and it does not reintroduce a clock domain
	-- crossing into the Basic Timer. Row 15 settles it: "Since the CPU clock
	-- MCLK and the peripheral clock SMCLK are fed from the same 50MHz physical
	-- source, it only remains to ensure that MCLK is an integer multiple of
	-- SMCLK, which guarantees full synchronisation with no need for edge
	-- synchronisation." Here the ratio is 1, which is an integer, so no CDC
	-- hardware is added anywhere on the CPU-to-timer path and none is needed.
	-- BASIC_TIMER_INTERFACE.vhd's concurrent ASSERT is what holds that
	-- condition: it refuses to elaborate if G_SMCLK_MHZ and G_MCLK_MHZ ever
	-- differ. Read its header for exactly what that assert does and does not
	-- enforce - it checks the frequencies, not how they are generated, which
	-- is all row 15 requires.
	--
	-- DIVCLK IS THE ONE REAL CROSSING. It is deliberately much faster than
	-- MCLK (row 16: "DIVCLK must be as high as the critical path of the
	-- divider structure allows"), so the ratio is not 1 and row 15's argument
	-- does not apply to it. That crossing is handled properly, by CDC_SYNC
	-- inside DIV_ACCEL - it is the crossing Figure 10 of the task definition
	-- teaches, and nothing here touches it.
	--
	-- The frequencies live in clk_config_package.vhd, which is GENERATED by
	-- QUARTUS/gen_plls.tcl from the same numbers it builds the IP with. To
	-- retune a clock, edit that script and run QUARTUS\gen_plls.bat; the three
	-- branches below then track each other automatically. Retuning MCLK
	-- without retuning SMCLK to match will trip the ASSERT rather than build
	-- an unsynchronised design.
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
	-- create_clock on clk_i and derive_pll_clocks to pick up all three. BTCLK
	-- (SMCLK through BT_CLKDIV's /2, /4, /8 taps) is a further clock generated
	-- in fabric and still needs its own create_generated_clock and
	-- set_clock_groups -exclusive, exactly as BT_CLKDIV.vhd's header says.
	-- That requirement is untouched by this change and is not yet in the .sdc.
	--
	-- rst_reset is tied low deliberately: KEY0 must NOT reset the PLLs. It is
	-- the system reset, and if it also stopped the clocks then every press
	-- would kill MCLK, DIVCLK and SMCLK together, and the logic would then run
	-- on an unlocked, off-frequency clock for the whole relock time after the
	-- release - because rst_w drops the instant the key comes up, well before
	-- the PLLs are stable again. Invisible on the LEDs, but it corrupts a
	-- Signal-Tap capture and freezes acquisition while the key is down.
	-- The PLLs lock once after configuration and stay locked; KEY0 resets the
	-- CPU, the memory and the peripherals, which is all a system reset means.
	--=======================================
	CLK_FPGA: if MODELSIM = 0 generate
		U_PLL_MCLK: PLL_MCLK
		PORT MAP (
			refclk_clk		=> clk_i,
			rst_reset		=> '0',
			outclk_0_clk	=> mclk_w
		);

		U_PLL_DIVCLK: PLL_DIVCLK
		PORT MAP (
			refclk_clk		=> clk_i,
			rst_reset		=> '0',
			outclk_0_clk	=> divclk_w
		);

		U_PLL_SMCLK: PLL_SMCLK
		PORT MAP (
			refclk_clk		=> clk_i,
			rst_reset		=> '0',
			outclk_0_clk	=> smclk_w
		);
	end generate;

	CLK_SIM: if MODELSIM = 1 generate
		-- Half period in ns: 1000/f gives the period in ns for f in MHz.
		-- Deliberately not synthesizable - this branch must never reach
		-- Quartus, and if MODELSIM is left at 1 by mistake it will fail loudly
		-- there rather than quietly building the wrong hardware.
		--
		-- SMCLK gets its own generator here, matching its own PLL in the FPGA
		-- branch above. With G_SMCLK_MHZ = G_MCLK_MHZ the two waveforms come
		-- out identical - same initial value, same half period - which is the
		-- ratio-1 case row 15 calls fully synchronised. The generator is kept
		-- separate rather than collapsed into "smclk_w <= mclk_w" so that
		-- retuning SMCLK in gen_plls.tcl changes the simulation as well as the
		-- hardware, instead of silently changing only the hardware.
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

		-- The interrupt service protocol (clause 6.v, page 15), closing the
		-- loop through INTC below: intr_w is INTC's own intr_o, and gie_w /
		-- inta_n_w are no longer tied off - they are simply this port's
		-- outputs, read back into INTC's gie_i / inta_n_i further down.
		intr_i				=> intr_w,

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
		mclk_cnt_o			=> mclk_cnt_w,

		--Interrupt service protocol (clause 6.v, page 15)
		inta_n_o			=> inta_n_w,
		gie_o				=> gie_w
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

	-- The two decoders partition the I/O region between them. GPIO_AddressDecoder
	-- owns 0x2000-0x201F (device select on address bits [4:2], with [12:5]
	-- forced to zero); PERIPH_AddressDecoder owns the clause-6 block above it,
	-- 0x2000-0x203F of device-select space on bits [5:2] with [12:6] forced to
	-- zero. The two sets of device-select patterns are disjoint by construction
	-- (see the header of PERIPH_AddressDecoder.vhd), so the chip selects across
	-- both decoders stay one-hot together and the read paths can keep being
	-- OR-ed onto io_bus_w exactly as they are today.
	IODEC6: PERIPH_AddressDecoder
	generic map(
		DA_WIDTH			=> DA_WIDTH
	)
	PORT MAP (
		--Inputs
		en_i				=> io_sel_w,
		addr_i				=> bus_addr_w,

		--Outputs
		cs_pb_o				=> cs_pb_w,
		cs_btctl_o			=> cs_btctl_w,
		cs_btcmpr0_o		=> cs_btcmpr0_w,
		cs_btcmpr1_o		=> cs_btcmpr1_w,
		cs_btcapr_o			=> cs_btcapr_w,
		cs_ic_o				=> cs_ic_w
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

	-- PORT_PB, the first clause-6 device. Read-only like PORT_SW - no
	-- MemWrite_ctrl_i, no data_wr_i - but unlike PORT_SW it is clocked: it
	-- contains the two-flop KEY synchronizer and the release edge detector,
	-- so it needs clk_i and rst_i where GPIO_SW_Interface needs neither.
	--
	-- rst_i is wired to rst_w, the internal resolved reset, and must never be
	-- the raw rst_i port. GPIO_PB_Interface resets its key-history registers
	-- to the idle level "111"; feeding it the wrongly-polarised reset would
	-- make the first sample after reset look like three simultaneous key
	-- releases and fire three spurious interrupts.
	IOPB: GPIO_PB_Interface
	generic map(
		DATA_BUS_WIDTH		=> DATA_BUS_WIDTH
	)
	PORT MAP (
		--Inputs
		clk_i				=> mclk_w,
		rst_i				=> rst_w,
		cs_i				=> cs_pb_w,
		MemRead_ctrl_i		=> bus_read_w,
		KEY_i				=> KEY_i,

		--Outputs
		data_rd_o			=> rd_pb_w,
		key1_irq_o			=> key1_irq_w,
		key2_irq_o			=> key2_irq_w,
		key3_irq_o			=> key3_irq_w
	);

	-- The Basic Timer's memory-mapped register file. One chip select per
	-- register out of IODEC6 above, already declared and already wired to
	-- the decoder - they simply had no consumer until now. sel_i is bit 0 of
	-- the byte address, exactly as the HEX pairs use it, because BTCTL1 and
	-- BTCTL2 are the same kind of adjacent-byte-address pair.
	--
	-- rst_i is rst_w, the internal resolved reset, never the raw rst_i port -
	-- same reason as every other clocked port in this file.
	BTIF: basic_timer_interface
	generic map(
		DATA_BUS_WIDTH		=> DATA_BUS_WIDTH
	)
	PORT MAP (
		--Inputs
		clk_i				=> mclk_w,
		rst_i				=> rst_w,
		cs_btctl_i			=> cs_btctl_w,
		cs_btcmpr0_i		=> cs_btcmpr0_w,
		cs_btcmpr1_i		=> cs_btcmpr1_w,
		cs_btcapr_i			=> cs_btcapr_w,
		sel_i				=> bus_addr_w(0),
		MemRead_ctrl_i		=> bus_read_w,
		MemWrite_ctrl_i		=> bus_write_w,
		data_wr_i			=> bus_wdata_w,
		btcapr_i			=> btcapr_w,
		capevt_i			=> capevt_w,
		btifg_i				=> btifg_w,

		--Outputs
		data_rd_o			=> rd_bt_w,
		bt_irq_o			=> bt_irq_w,
		btctl1_o			=> btctl1_w,
		btctl2_o			=> btctl2_w,
		btcmpr0_o			=> btcmpr0_w,
		btcmpr1_o			=> btcmpr1_w
	);

	-- The Basic Timer itself (Fig.7). Runs on smclk_w, PLL_SMCLK's output. It
	-- and BTIF's mclk_w are separate PLL outputs at the same frequency, from
	-- the same 50 MHz source - the ratio-1 case forum row 15 states is fully
	-- synchronised with no need for edge synchronisation, which is why the
	-- register writes and the btifg_i edge detector above carry no crossing
	-- hardware. See the clock generation note at the top of this file.
	BT: basic_timer
	generic map(
		N					=> DATA_BUS_WIDTH
	)
	PORT MAP (
		--Inputs
		smclk_i				=> smclk_w,
		rst_i				=> rst_w,
		btctl1_i			=> btctl1_w,
		btctl2_i			=> btctl2_w,
		btcmpr0_i			=> btcmpr0_w,
		btcmpr1_i			=> btcmpr1_w,
		capin1_i			=> CAPIN1_i,
		capin2_i			=> CAPIN2_i,

		--Outputs
		pwmout_o			=> PWMout_o,
		btifg_o				=> btifg_w,
		btcapr_o			=> btcapr_w,
		btcnt_o				=> btcnt_w,
		capevt_o			=> capevt_w
	);

	-- The Basic Interrupt Controller (clause 6.v): IE, IFG and TYPE at
	-- 0x202C-0x202E, fed by the four sources this file already has pulses
	-- for. cs_ic_w is IODEC6's sixth output, declared since the PERIPH
	-- integration and unused until now; addr_i only needs the low two bits,
	-- since PERIPH_AddressDecoder has already narrowed the access down to
	-- this one device before cs_ic_w asserts. The decoder also asserts
	-- cs_ic_w for 0x202F ("11") on purpose - int_ctrl's own header explains
	-- why suppressing it there would cost a comparator for no gain, and the
	-- module already returns zero for that address itself.
	--
	-- rst_i is rst_w, never the raw rst_i port, for the same reason as every
	-- other clocked device here.
	--
	-- is_rx_i and is_tx_i are tied to '0': the USART is the 20% bonus and out
	-- of scope, but its IE/IFG bits still exist because the register map
	-- defines them - they will just never set themselves.
	INTC: int_ctrl
	generic map(
		DATA_BUS_WIDTH		=> DATA_BUS_WIDTH
	)
	PORT MAP (
		--Inputs
		clk_i				=> mclk_w,
		rst_i				=> rst_w,
		cs_i				=> cs_ic_w,
		addr_i				=> bus_addr_w(1 DOWNTO 0),
		MemRead_ctrl_i		=> bus_read_w,
		MemWrite_ctrl_i		=> bus_write_w,
		data_wr_i			=> bus_wdata_w,
		is_rx_i				=> '0',
		is_tx_i				=> '0',
		is_bt_i				=> bt_irq_w,
		is_key1_i			=> key1_irq_w,
		is_key2_i			=> key2_irq_w,
		is_key3_i			=> key3_irq_w,
		gie_i				=> gie_w,
		inta_n_i			=> inta_n_w,

		--Outputs
		data_rd_o			=> rd_ic_w,
		bus_drive_o			=> oe_ic_w,
		intr_o				=> intr_w
	);

	-- gie_i and inta_n_i are CPU-side handshake signals, and as of step 4 the
	-- loop through the CPU is real: gie_w and inta_n_w are driven by CORE's
	-- gie_o and inta_n_o above (see the CPU instantiation), not tied off.
	-- INTR can genuinely rise now, and the service machine in CONTROL.VHD can
	-- genuinely be entered.
	--
	-- What still holds every interrupt off by default is the register file,
	-- not this wiring: RF_q resets to all zero (IDECODE.VHD), so gp[0] - GIE
	-- - is '0' out of reset, and intr_o <= gie_i WHEN ifg_w /= 0 ELSE '0' in
	-- int_ctrl means INTR cannot rise until software explicitly stores a '1'
	-- into gp[0]. No existing benchmark or GPIO application does that, so
	-- every one of them keeps running exactly as before - not because the
	-- protocol is inert, but because nothing has asked for it yet.

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
	oe_pb_w		<= cs_pb_w		AND bus_read_w;

	-- One output enable for the whole Basic Timer register group: the four
	-- chip selects are already mutually exclusive out of PERIPH_AddressDecoder,
	-- so ORing them here and driving one BidirPin is exactly the shared
	-- chip-select grouping that decoder was designed to allow, matching how
	-- one instance already serves both BTCTL1 and BTCTL2 inside BTIF.
	oe_bt_w		<= (cs_btctl_w OR cs_btcmpr0_w OR cs_btcmpr1_w OR cs_btcapr_w) AND bus_read_w;

	-- oe_ic_w is NOT assigned here. Unlike every other device, int_ctrl
	-- computes its own output enable (bus_drive_o) and this signal is simply
	-- that port from the INTC instance above - see the note there for why an
	-- ordinary cs AND MemRead term cannot do protocol cycle 1's job.

	-- A bus with every buffer released floats at 'Z', and 'Z' propagated into
	-- the register file would show up as red in the wave window and as
	-- metavalue warnings rather than as data. BUF_NONE parks the bus at zero
	-- whenever no device is driving it, which also gives the reads-as-zero
	-- behaviour that unmapped I/O addresses need. 0x2014 through 0x202E are
	-- now all mapped (PORT_PB, the Basic Timer register group, then the
	-- interrupt controller); only 0x2018-0x201B (USART, bonus, not part of
	-- this design) remains unmapped.
	--
	-- oe_pb_w, oe_bt_w and oe_ic_w all have to appear in this NOR: leaving
	-- any one out would let BUF_NONE and that port's buffer both drive
	-- io_bus_w during a load from its address range, resolving to 'X'.
	oe_none_w	<= NOT (oe_ledr_w OR oe_hex0_1_w OR oe_hex2_3_w OR oe_hex4_5_w OR oe_sw_w OR oe_pb_w OR oe_bt_w OR oe_ic_w);

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

	BUF_PB: BidirPin
	generic map(width => DATA_BUS_WIDTH)
	PORT MAP (Dout => rd_pb_w,		en => oe_pb_w,		Din => OPEN, IOpin => io_bus_w);

	BUF_BT: BidirPin
	generic map(width => DATA_BUS_WIDTH)
	PORT MAP (Dout => rd_bt_w,		en => oe_bt_w,		Din => OPEN, IOpin => io_bus_w);

	BUF_IC: BidirPin
	generic map(width => DATA_BUS_WIDTH)
	PORT MAP (Dout => rd_ic_w,		en => oe_ic_w,		Din => OPEN, IOpin => io_bus_w);

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
	--
	-- io_sel_w alone is not enough any more. Page 15 requires that in
	-- protocol cycle 1 the interrupt controller puts TYPE on the data bus
	-- while the CPU has not driven 0x202E onto the address bus at all -
	-- io_sel_w would then be whatever bit 13 of a stale or unrelated address
	-- happens to be, and could select dtcm_q_w instead of io_bus_w, losing
	-- TYPE. Adding oe_ic_w = '1' to the condition covers that case: it is
	-- true throughout cycle 1 regardless of what the address bus is doing.
	-- The two terms cannot conflict - an ordinary load from 0x202C-0x202E
	-- has io_sel_w = '1' and oe_ic_w = '1' together, selecting the same
	-- io_bus_w either way, and a DTCM access has oe_ic_w = '0' because
	-- int_ctrl is not selected. While inta_n_w is tied high (see INTC above)
	-- this is inert: oe_ic_w can only be cs_ic_w AND bus_read_w, which
	-- already implies io_sel_w = '1'. It is written now so the CPU-protocol
	-- task does not have to touch this multiplexer again.
	bus_rdata_w	<= io_bus_w WHEN (io_sel_w = '1' OR oe_ic_w = '1') ELSE dtcm_q_w;

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
