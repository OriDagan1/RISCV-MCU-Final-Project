---------------------------------------------------------------------------------------------
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- BASIC_TIMER_INTERFACE - the memory-mapped register file of the Basic Timer
--
-- Fig.7 draws the timer as a shaded block with BTCMPR0, BTCMPR1 and BTCAPR sitting
-- OUTSIDE it, and BTCTL1 / BTCTL2 given only as bit tables underneath. What crosses
-- into the shaded block is not a bus but the decoded control fields - BTCLR, BTHOLD,
-- BTSSEL, BTOUTMD, BTOUTEN, BTINT, CAPISEL, CAPMD - and what leaves it is BTCAPR,
-- PWMout and BTIFG. BASIC_TIMER.vhd is exactly that shaded block and says so in its
-- own header: it has no bus interface on purpose.
--
-- This module is the missing outside: the registers drawn touching the block, plus
-- the load/store path that lets the CPU reach them.
--
--   Data BUS  <--->  [ BTCTL1 BTCTL2 BTCMPR0 BTCMPR1 ]  --->  BASIC_TIMER
--                    [             BTCAPR            ]  <---
--
-- Register map, clause 6 of the project definition:
--
--   name      byte addr   resolution   access   width   reset
--   --------  ----------  -----------  -------  ------  -----
--   BTCTL1    0x201C      byte         rw        8      0x00
--   BTCTL2    0x201D      byte         rw        8      0x00
--   BTCMPR0   0x2020      word         rw       32      0
--   BTCMPR1   0x2024      word         rw       32      0
--   BTCAPR    0x2028      word         r        32      0
--
-- Bit layouts, from the tables on page 7:
--
--   BTCTL1   7 BTOUTMD | 6 BTOUTEN | 5 BTHOLD | 4:3 BTSSEL | 2 BTCLR | 1:0 BTINT
--   BTCTL2   7:4 reserved, read as 0        | 3:2 CAPMD   | 1:0 CAPISEL
--
-- NO ADDRESS COMPARISON HAPPENS HERE. PERIPH_AddressDecoder owns the map and hands
-- this module one chip select per register, exactly as GPIO_AddressDecoder does for
-- the GPIO ports. BTCTL1 and BTCTL2 are adjacent byte addresses that differ in bit 0
-- alone, so they share one chip select and sel_i - bit 0 of the byte address - picks
-- between them, which is the same arrangement GPIO_HEX_Pair_Interface uses for a pair
-- of displays. Decoding the address again in here would put a second comparator on
-- the load/store critical path for no gain.
--
-- BTCAPR IS READ ONLY, AND THIS IS A DEVIATION WORTH STATING. The bit table on page 7
-- marks every BTCAPR bit "rw", but Fig.7 draws it purely as the destination of
-- "BTCNT_CAPTURE on event register" and gives it no write path at all, and
-- BT_CAPTURE.vhd accordingly exposes btcapr only as an output. The two statements
-- cannot both be honoured. A store to 0x2028 is therefore accepted and silently
-- ignored here, the same way a store to PORT_SW is ignored: inventing a write path
-- into the capture register would mean overwriting a value the hardware captured,
-- which is the one thing the register exists to preserve.
--
-- BTCNT IS NOT MAPPED. It is absent from the clause 6 table, so it gets no address.
-- BASIC_TIMER still exposes btcnt_o, which MCU.vhd may route to Signal-Tap.
--
-- THE REGISTERS ARE WRITTEN ON THE FALLING EDGE of MCLK, matching PORT_LEDR, the HEX
-- pairs and the DTCM, so that every target on the data bus captures write data at the
-- same instant of the CPU cycle.
--
-- ONE CLOCK DOMAIN, AND THE ASSERT THAT KEEPS IT THAT WAY. These registers are
-- written by the CPU in the MCLK domain and read by BASIC_TIMER in the BTCLK domain,
-- where BTCLK is SMCLK divided by BTSSEL. That is only safe while SMCLK is MCLK: the
-- BTSSEL taps then come off a counter clocked by MCLK, their edges line up with MCLK
-- edges, and every path from here into the timer is an ordinary related-clock path
-- that TimeQuest analyses. Drive the timer from an independent PLL instead and the
-- same paths become true clock domain crossings - the 32-bit compare registers would
-- need a bundled-data handshake rather than bit-wise synchronizers, and BTIFG, which
-- is one BTCLK wide, would need a toggle pulse synchronizer, since a two-flop level
-- synchronizer like cdc_sync can miss a pulse that narrow. None of that machinery is
-- present in this file, so the ASSERT below refuses to elaborate a design in which it
-- would be required. It is a guard rail on retuning the PLLs, in the spirit of the
-- DA_WIDTH assert in GPIO_AddressDecoder.vhd.
--
-- The tri-state buffer of Figure 5 is realised as a read multiplexer: this module
-- drives zeros when it is not selected, so the I/O read paths can be OR-ed together.
-- Cyclone devices have no internal tri-state anyway - Quartus converts every internal
-- 'Z' into exactly this multiplexer.
---------------------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE work.clk_config_package.all;

ENTITY basic_timer_interface IS
	generic(
		DATA_BUS_WIDTH		: integer := 32;
		N					: positive := 32;	-- compare and capture width, as BASIC_TIMER
		CTL_WIDTH			: integer := 8		-- BTCTL1 and BTCTL2 are byte registers
	);
	PORT(
		--Inputs
		clk_i				: IN	STD_LOGIC;	-- MCLK
		rst_i				: IN	STD_LOGIC;

		--Chip selects, one per register, from PERIPH_AddressDecoder
		cs_btctl_i			: IN	STD_LOGIC;	-- BTCTL1 / BTCTL2  0x201C / 0x201D
		cs_btcmpr0_i		: IN	STD_LOGIC;	-- BTCMPR0          0x2020
		cs_btcmpr1_i		: IN	STD_LOGIC;	-- BTCMPR1          0x2024
		cs_btcapr_i			: IN	STD_LOGIC;	-- BTCAPR           0x2028

		sel_i				: IN	STD_LOGIC;	-- bit 0 of the byte address: '0' BTCTL1, '1' BTCTL2

		MemRead_ctrl_i		: IN	STD_LOGIC;
		MemWrite_ctrl_i		: IN	STD_LOGIC;
		data_wr_i			: IN	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

		--From the timer, the captured count
		btcapr_i			: IN	STD_LOGIC_VECTOR(N-1 DOWNTO 0);

		--Outputs
		data_rd_o			: OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

		--To the timer, the registers of Fig.7
		btctl1_o			: OUT	STD_LOGIC_VECTOR(CTL_WIDTH-1 DOWNTO 0);
		btctl2_o			: OUT	STD_LOGIC_VECTOR(CTL_WIDTH-1 DOWNTO 0);
		btcmpr0_o			: OUT	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
		btcmpr1_o			: OUT	STD_LOGIC_VECTOR(N-1 DOWNTO 0)
	);
END basic_timer_interface;
---------------------------------------------------------------------------------------------
ARCHITECTURE rtl OF basic_timer_interface IS

	-- BTCTL2 bits 7:4 are marked r in the bit table, so they are not stored at all:
	-- a store cannot set them and a load returns zeros in their place.
	CONSTANT CTL2_MSB		: integer := 3;		-- highest implemented bit of BTCTL2

	SIGNAL btctl1_q			: STD_LOGIC_VECTOR(CTL_WIDTH-1 DOWNTO 0);
	SIGNAL btctl2_q			: STD_LOGIC_VECTOR(CTL2_MSB DOWNTO 0);
	SIGNAL btcmpr0_q		: STD_LOGIC_VECTOR(N-1 DOWNTO 0);
	SIGNAL btcmpr1_q		: STD_LOGIC_VECTOR(N-1 DOWNTO 0);

	SIGNAL wren_ctl1_w		: STD_LOGIC;
	SIGNAL wren_ctl2_w		: STD_LOGIC;
	SIGNAL wren_cmpr0_w		: STD_LOGIC;
	SIGNAL wren_cmpr1_w		: STD_LOGIC;

	SIGNAL btctl2_w			: STD_LOGIC_VECTOR(CTL_WIDTH-1 DOWNTO 0);
	SIGNAL ctl_rd_w			: STD_LOGIC_VECTOR(CTL_WIDTH-1 DOWNTO 0);

	-- Each register widened to the bus, then one multiplexer over the four
	SIGNAL rd_ctl_w			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL rd_cmpr0_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL rd_cmpr1_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL rd_capr_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL rdata_w			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

BEGIN

	-- See the note on clock domains in the header. Everything in this file assumes
	-- the timer is clocked from MCLK, so that BTCLK is a synchronous derivative of
	-- the bus clock and no crossing hardware is needed.
	ASSERT G_SMCLK_MHZ = G_MCLK_MHZ
		REPORT "basic_timer_interface: the Basic Timer must be clocked from MCLK. "
			 & "G_SMCLK_MHZ differs from G_MCLK_MHZ, so BTCLK is asynchronous to the "
			 & "data bus and these registers would cross clock domains unprotected - "
			 & "BTCMPR0/1 need a bundled-data handshake and BTIFG a toggle pulse "
			 & "synchronizer. Either equalise the clocks in QUARTUS/gen_plls.tcl or "
			 & "add the crossing logic before removing this assert"
		SEVERITY FAILURE;

	--=======================================
	-- Access qualifiers
	--=======================================
	-- A register answers only when its own chip select is asserted and the access is
	-- a store. BTCTL1 and BTCTL2 share a chip select, so sel_i decides which of the
	-- two a store reaches - exactly one register is written per store, never both.
	-- BTCAPR has no write enable at all; see the header.
	wren_ctl1_w		<= cs_btctl_i	AND MemWrite_ctrl_i AND (NOT sel_i);
	wren_ctl2_w		<= cs_btctl_i	AND MemWrite_ctrl_i AND sel_i;
	wren_cmpr0_w	<= cs_btcmpr0_i	AND MemWrite_ctrl_i;
	wren_cmpr1_w	<= cs_btcmpr1_i	AND MemWrite_ctrl_i;

	--=======================================
	-- Write path : CPU -> registers
	--=======================================
	-- All four registers reset to zero, as page 7 requires. That reset value is what
	-- makes the timer safe out of reset: BTCTL1 = 0 means BTHOLD released, BTSSEL on
	-- undivided SMCLK, BTINT on EQU0, and BTCTL2 = 0 means capture disabled.
	WRREG:
	process (clk_i, rst_i)
	begin
		if rst_i = '1' then
			btctl1_q	<= (OTHERS => '0');
			btctl2_q	<= (OTHERS => '0');
			btcmpr0_q	<= (OTHERS => '0');
			btcmpr1_q	<= (OTHERS => '0');
		elsif falling_edge(clk_i) then
			if wren_ctl1_w = '1' then
				btctl1_q	<= data_wr_i(CTL_WIDTH-1 DOWNTO 0);
			end if;
			if wren_ctl2_w = '1' then
				btctl2_q	<= data_wr_i(CTL2_MSB DOWNTO 0);
			end if;
			if wren_cmpr0_w = '1' then
				btcmpr0_q	<= data_wr_i(N-1 DOWNTO 0);
			end if;
			if wren_cmpr1_w = '1' then
				btcmpr1_q	<= data_wr_i(N-1 DOWNTO 0);
			end if;
		end if;
	end process;

	--=======================================
	-- Register outputs : registers -> timer
	--=======================================
	-- BASIC_TIMER decodes the fields itself, so the bytes are handed over whole.
	-- The reserved bits of BTCTL2 are driven as zeros rather than left undriven, so
	-- the value the timer sees and the value a load returns are the same byte.
	btctl2_w(CTL_WIDTH-1 DOWNTO CTL2_MSB+1)	<= (OTHERS => '0');
	btctl2_w(CTL2_MSB DOWNTO 0)				<= btctl2_q;

	btctl1_o	<= btctl1_q;
	btctl2_o	<= btctl2_w;
	btcmpr0_o	<= btcmpr0_q;
	btcmpr1_o	<= btcmpr1_q;

	--=======================================
	-- Read path : registers -> CPU
	--=======================================
	-- The control byte selected by sel_i, zero extended to the bus width, so both lw
	-- and lbu return it unchanged.
	ctl_rd_w	<= btctl2_w WHEN sel_i = '1' ELSE btctl1_q;

	-- Each register widened to the bus. The N-wide slices are null ranges when N
	-- equals the bus width, which is the normal case, and the assignments simply
	-- disappear - the same idiom GPIO_SW_Interface uses for its narrow port.
	rd_ctl_w(DATA_BUS_WIDTH-1 DOWNTO CTL_WIDTH)	<= (OTHERS => '0');
	rd_ctl_w(CTL_WIDTH-1 DOWNTO 0)				<= ctl_rd_w;

	rd_cmpr0_w(DATA_BUS_WIDTH-1 DOWNTO N)		<= (OTHERS => '0');
	rd_cmpr0_w(N-1 DOWNTO 0)					<= btcmpr0_q;

	rd_cmpr1_w(DATA_BUS_WIDTH-1 DOWNTO N)		<= (OTHERS => '0');
	rd_cmpr1_w(N-1 DOWNTO 0)					<= btcmpr1_q;

	-- BTCAPR is read straight from the timer rather than from a copy here, so a load
	-- always returns the most recent captured count.
	rd_capr_w(DATA_BUS_WIDTH-1 DOWNTO N)		<= (OTHERS => '0');
	rd_capr_w(N-1 DOWNTO 0)						<= btcapr_i;

	-- One read multiplexer over the four addressable registers. The chip selects are
	-- one-hot by construction in PERIPH_AddressDecoder, so the priority in this chain
	-- is never exercised; it exists only to give the expression a defined default of
	-- zero, which is what lets MCU.vhd OR the I/O read paths together.
	rdata_w		<=	rd_ctl_w	WHEN cs_btctl_i		= '1' ELSE
					rd_cmpr0_w	WHEN cs_btcmpr0_i	= '1' ELSE
					rd_cmpr1_w	WHEN cs_btcmpr1_i	= '1' ELSE
					rd_capr_w	WHEN cs_btcapr_i	= '1' ELSE
					(OTHERS => '0');

	data_rd_o	<= rdata_w WHEN (MemRead_ctrl_i = '1') ELSE (OTHERS => '0');

END rtl;