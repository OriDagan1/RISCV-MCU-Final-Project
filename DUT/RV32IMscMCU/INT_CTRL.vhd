---------------------------------------------------------------------------------------------
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- INT_CTRL - the Basic Interrupt Controller of clause 6.v
--
-- Holds IE, IFG and TYPE at 0x202C, 0x202D and 0x202E, latches the interrupt sources,
-- decides which of them is served first, and raises INTR for the CPU. It is the block
-- drawn as "Basic Interrupt Controller IE, IFG, TYPE" in the figure of clause 6.v, built
-- the way the two circuits underneath that figure draw it.
--
--   IS_x --> [ irq FF ] --irq_x--+--AND--> IFG(x) --+
--                                |  eint_x = IE(x)  |
--            clr_irq ------------+                  +--OR--+--AND--> INTR
--                                                          |
--                                                    GIE ---+
--
--   IFG --> [ priority encoder ] --> TYPE --> data bus, protocol cycle 1
--
-- THE THREE READINGS OF THE FIGURE THAT SHAPE THIS FILE. Each is a decision; each is
-- written down because none of them is spelled out in words anywhere in the definition.
--
--   1. IFG IS ALREADY MASKED BY IE. In the "several sources" circuit the bracket labelled
--      "This is the IFG Register" points at the outputs of the AND gates, not at the
--      flip-flops feeding them, so IFG(x) = irq(x) AND IE(x). A real MSP430 keeps IFG
--      independent of IE; this design follows the figure instead. The visible consequence
--      is that reading IFG while an IE bit is clear returns zero for that source even
--      though its event was latched, and the flag reappears the moment IE is set. This is
--      deliberate, and it is the reason the flip-flops are called irq here and not IFG.
--
--   2. THE FLIP-FLOP IS CLOCK-ENABLED, NOT CLOCKED BY THE SOURCE. The figure draws IS
--      wired to the clock input of a D flip-flop whose D is tied to "1". Building that
--      literally would turn six interrupt sources into six clock domains that the timing
--      analyser cannot constrain - in a project graded on its PPA and timing report that
--      is a real cost, not a stylistic one. The sources instead arrive as one-MCLK-wide
--      pulses and set an enabled flip-flop in the MCLK domain. GPIO_PB_Interface already
--      made this choice for the pushbuttons and documents it; basic_timer_interface makes
--      it for BTIFG. This file completes the same scheme.
--
--   3. SET BEATS CLEAR IN THE SAME CYCLE. If a source pulses on exactly the cycle its flag
--      is being cleared, the event must survive - the alternative silently loses an
--      interrupt, and only under a race that is almost impossible to reproduce.
--
-- SIX FLAGS, SEVEN VECTORS. The IFG register of page 14 has six usable bits, but the
-- vector table on the same page lists seven maskable entries, because "UART status error"
-- (04h) and "UART RX" (08h) share RXIFG. One flag cannot select between two vectors: that
-- needs a status signal from the USART, which the register map does not carry. Since the
-- USART is the 20% bonus of clause 6.iv and out of scope here, RXIFG is encoded as UART RX
-- (08h) and 04h is unreachable. Adding the bonus means an extra input, not a redesign.
--
-- RESET IS NOT A SOURCE HERE. It is the NMI of the vector table, its flag column holds a
-- dash, and bits 7:6 of IFG read as zero - so it has no IE bit and, being non maskable, no
-- GIE either. KEY0 is the system reset of clause 3 and reaches the design as rst_w. Its
-- vector value 00h is what TYPE reads when nothing is pending.
--
-- THE PROTOCOL, AND WHY THIS MODULE DRIVES THE BUS WITHOUT BEING ADDRESSED. Page 15 puts
-- the service state machine in the CPU's control unit, and in cycle 1 it requires "writing
-- the content of register TYPE on Data BUS and capturing it in a dedicated register", with
-- the note that TYPE "cannot be written on the Address BUS because the CPU is the only BUS
-- master". So during cycle 1 nobody puts 0x202E on the address bus and cs_i is low, yet
-- TYPE must appear on the data bus anyway. That is what bus_drive_o exists for: it is high
-- for an ordinary load from one of the three addresses AND for protocol cycle 1, and
-- MCU.vhd uses it directly as the output enable of this device's bus buffer instead of the
-- usual "cs AND MemRead" term.
--
-- Cycle 1 is identified as the cycle in which INTA is low. Page 15: INTR rises, the CPU
-- pulls INTA low on the next cycle, the falling edge of INTA starts the process, and cycle
-- 1 itself sets INTA back to '1'. Cycle 2 is therefore the cycle after INTA has returned
-- high, which is where the definition asks for "in case of TYPE pending interrupt of a
-- synchronous interrupt source, clear its flag (like the BTIFG)". The source being served
-- is captured at the end of cycle 1 rather than recomputed in cycle 2, because the CPU
-- clears GIE in cycle 1 and a second source arriving in between must not divert the clear.
--
-- WHICH FLAGS CLEAR THEMSELVES, from the notes under the figure:
--   BTIFG   note a   cleared automatically when the interrupt is serviced
--   RXIFG   note b   cleared on service or when RXBUF is read      (bonus, tied off)
--   TXIFG   note c   cleared on service or on a write to TXBUF     (bonus, tied off)
--   KEYiIFG note d   cleared manually by software only
--
-- WRITING TO IFG CLEARS: A STORE WRITES THE VALUE THE REGISTER SHOULD TAKE. A bit stored
-- as '0' clears that flag; a bit stored as '1' leaves it as it is. This is not a free
-- choice - it is what the lecturer's own applications require, and an earlier version of
-- this file got it wrong.
--
-- That earlier version used write-one-to-clear, on the reasoning that because IFG reads
-- back masked by IE, a read-modify-write would read zero for any source whose IE bit is
-- clear and then clear a latched event the programmer never saw. The reasoning is sound;
-- the conclusion contradicted the specification. Every ISR in the supplied applications
-- clears its flag like this (00_main.s of Interrupt-based IO test1, test2 and test3):
--
--     li   t2,IFG
--     lw   t3,0(t2)          # read IFG
--     li   t5,KEY1IFG_MASK   # 0xFFF7, an AND mask - note the polarity
--     and  t3,t3,t5
--     sw   t3,0(t2)          # clr KEY1IFG
--
-- The mask is the COMPLEMENT of the bit. Under write-one-to-clear that store carries a
-- zero in the KEY1 position and therefore clears nothing: the flag survives, reti restores
-- GIE, INTR is still asserted, and the CPU re-enters the same ISR for ever. Each of those
-- applications also opens with "sw zero,0(IFG)" to clear every flag before enabling any
-- interrupt - the step the forum describes as standard practice for exactly the
-- reset-window race in the note below - and write-one-to-clear made that store a no-op too.
--
-- The residual risk the old reasoning identified is real but smaller than it looks: the
-- read-modify-write reads back every flag whose IE bit is set, so a second ENABLED source
-- arriving mid-ISR is preserved. Only a latched event whose IE bit is clear can be lost,
-- and such an event cannot raise INTR anyway while it stays masked.
--
-- WHY A STORED '1' DOES NOT SET A FLAG. IFGx = 1 means "interrupt pending", and what makes
-- a source pending is its hardware event, not software. Holding on a stored '1' rather
-- than loading it keeps the register a faithful record of events and makes the ISR idiom
-- above exact: it stores back the bits it read, and those flags stay set. No supplied
-- application ever stores a one into IFG.
--
-- THE RESET WINDOW THIS ALSO FIXES. BTCTL1 resets to 0, so BTINT = "00" and BTIFG follows
-- EQU0 = (BTCNT >= BTCL0) = (0 >= 0), which is TRUE from the instant reset releases. The
-- edge detector in basic_timer_interface resets its history flop to '0' and therefore sees
-- a rising edge on that level, so depending on which MCLK edge arrives first after reset
-- deasserts, a BTIFG event can be latched here that no timer event caused. Reproduced in
-- simulation: releasing reset at two of four phases inside one MCLK period leaves
-- irq_q = 0x04. The application's opening "sw zero,0(IFG)" is what clears it, which is
-- precisely why that store has to work.
--
-- THE PRIORITY ENCODER IS INTERNAL. Clause 6.v draws one block, and the encoder here is
-- eight lines of chained conditions that exist only to feed the TYPE register in the same
-- file. A separate entity would add a component declaration, a compile.do entry, a second
-- testbench and another file to describe in the report, for logic with no second consumer.
--
-- Everything is clocked on the FALLING edge of MCLK, like every other store target in the
-- design. The one-MCLK source pulses are generated off the rising edge, so they are stable
-- across the falling edge in the middle of their high period and cannot be missed.
---------------------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY int_ctrl IS
	generic(
		DATA_BUS_WIDTH	: integer := 32
	);
	PORT(
		--Inputs
		clk_i			: IN	STD_LOGIC;	-- MCLK
		rst_i			: IN	STD_LOGIC;

		--Bus side. cs_i covers 0x202C to 0x202F, addr_i picks the register
		cs_i			: IN	STD_LOGIC;
		addr_i			: IN	STD_LOGIC_VECTOR(1 DOWNTO 0);	-- 00 IE, 01 IFG, 10 TYPE, 11 unused
		MemRead_ctrl_i	: IN	STD_LOGIC;
		MemWrite_ctrl_i	: IN	STD_LOGIC;
		data_wr_i		: IN	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

		--Interrupt sources, one MCLK cycle wide, active high, highest priority first
		is_rx_i			: IN	STD_LOGIC;	-- RXIFG   08h   USART, bonus - tie to '0'
		is_tx_i			: IN	STD_LOGIC;	-- TXIFG   0Ch   USART, bonus - tie to '0'
		is_bt_i			: IN	STD_LOGIC;	-- BTIFG   10h   basic_timer_interface bt_irq_o
		is_key1_i		: IN	STD_LOGIC;	-- KEY1IFG 14h   GPIO_PB_Interface key1_irq_o
		is_key2_i		: IN	STD_LOGIC;	-- KEY2IFG 18h   GPIO_PB_Interface key2_irq_o
		is_key3_i		: IN	STD_LOGIC;	-- KEY3IFG 1Ch   GPIO_PB_Interface key3_irq_o

		--CPU handshake
		gie_i			: IN	STD_LOGIC;	-- gp[0] of the register file
		inta_n_i		: IN	STD_LOGIC;	-- ACTIVE LOW, low during protocol cycle 1

		--Outputs
		data_rd_o		: OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
		bus_drive_o		: OUT	STD_LOGIC;	-- output enable: ordinary load OR protocol cycle 1
		intr_o			: OUT	STD_LOGIC
	);
END int_ctrl;
---------------------------------------------------------------------------------------------
ARCHITECTURE rtl OF int_ctrl IS

	CONSTANT NSRC			: integer := 6;		-- usable bits of IE and IFG
	CONSTANT REG_WIDTH		: integer := 8;		-- IE, IFG and TYPE are byte registers

	-- Bit positions, from the IE and IFG register maps of page 14
	CONSTANT RXIFG_BIT		: integer := 0;
	CONSTANT TXIFG_BIT		: integer := 1;
	CONSTANT BTIFG_BIT		: integer := 2;
	CONSTANT KEY1IFG_BIT	: integer := 3;
	CONSTANT KEY2IFG_BIT	: integer := 4;
	CONSTANT KEY3IFG_BIT	: integer := 5;

	-- Register selects inside the 0x202C block
	CONSTANT SEL_IE			: STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";	-- 0x202C
	CONSTANT SEL_IFG		: STD_LOGIC_VECTOR(1 DOWNTO 0) := "01";	-- 0x202D
	CONSTANT SEL_TYPE		: STD_LOGIC_VECTOR(1 DOWNTO 0) := "10";	-- 0x202E
	-- "11" is 0x202F. PERIPH_AddressDecoder asserts cs_i there too, on purpose: suppressing
	-- it would have cost a comparator on the load/store path. Ignoring it is this module's
	-- job, and its header says so.

	-- TYPE contents of the interrupt vector table, page 14
	CONSTANT TYPE_IDLE		: STD_LOGIC_VECTOR(REG_WIDTH-1 DOWNTO 0) := x"00";	-- also the RESET vector
	CONSTANT TYPE_RX		: STD_LOGIC_VECTOR(REG_WIDTH-1 DOWNTO 0) := x"08";
	CONSTANT TYPE_TX		: STD_LOGIC_VECTOR(REG_WIDTH-1 DOWNTO 0) := x"0C";
	CONSTANT TYPE_BT		: STD_LOGIC_VECTOR(REG_WIDTH-1 DOWNTO 0) := x"10";
	CONSTANT TYPE_KEY1		: STD_LOGIC_VECTOR(REG_WIDTH-1 DOWNTO 0) := x"14";
	CONSTANT TYPE_KEY2		: STD_LOGIC_VECTOR(REG_WIDTH-1 DOWNTO 0) := x"18";
	CONSTANT TYPE_KEY3		: STD_LOGIC_VECTOR(REG_WIDTH-1 DOWNTO 0) := x"1C";

	-- Which flags clear themselves when their interrupt is serviced, notes a to d.
	-- Bit order matches the IFG register: RX, TX, BT clear on service; the keys do not.
	CONSTANT AUTO_CLEAR		: STD_LOGIC_VECTOR(NSRC-1 DOWNTO 0) := "000111";

	CONSTANT SRC_ZERO		: STD_LOGIC_VECTOR(NSRC-1 DOWNTO 0) := (OTHERS => '0');

	-- Bits 7:6 of IE and IFG read as zero, per the register maps of page 14. A named
	-- constant rather than an inline aggregate: a downto range choice inside a
	-- concatenation leaves the index direction ambiguous and vcom warns (1514).
	CONSTANT PAD_HI			: STD_LOGIC_VECTOR(REG_WIDTH-1 DOWNTO NSRC) := (OTHERS => '0');

	--State
	SIGNAL irq_q			: STD_LOGIC_VECTOR(NSRC-1 DOWNTO 0);	-- the latched events
	SIGNAL ie_q				: STD_LOGIC_VECTOR(NSRC-1 DOWNTO 0);	-- IE register
	SIGNAL served_q			: STD_LOGIC_VECTOR(NSRC-1 DOWNTO 0);	-- one-hot, captured in cycle 1
	SIGNAL svc_q			: STD_LOGIC;							-- '1' between cycle 1 and cycle 2

	--Combinational
	SIGNAL is_w				: STD_LOGIC_VECTOR(NSRC-1 DOWNTO 0);	-- the source pulses, gathered
	SIGNAL ifg_w			: STD_LOGIC_VECTOR(NSRC-1 DOWNTO 0);	-- irq AND IE, reading 1 above
	SIGNAL clr_sw_w			: STD_LOGIC_VECTOR(NSRC-1 DOWNTO 0);	-- write-one-to-clear from the bus
	SIGNAL clr_svc_w		: STD_LOGIC_VECTOR(NSRC-1 DOWNTO 0);	-- automatic clear on service
	SIGNAL sel_w			: STD_LOGIC_VECTOR(NSRC-1 DOWNTO 0);	-- one-hot winner of the priority chain
	SIGNAL type_w			: STD_LOGIC_VECTOR(REG_WIDTH-1 DOWNTO 0);

	SIGNAL cycle1_w			: STD_LOGIC;							-- protocol cycle 1, INTA low
	SIGNAL wr_w				: STD_LOGIC;
	SIGNAL rd_w				: STD_LOGIC;
	SIGNAL drive_w			: STD_LOGIC;

	SIGNAL reg_rd_w			: STD_LOGIC_VECTOR(REG_WIDTH-1 DOWNTO 0);
	SIGNAL rdata_w			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL type_ext_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

BEGIN

	--=======================================
	-- Sources and bus access qualifiers
	--=======================================
	is_w(RXIFG_BIT)		<= is_rx_i;
	is_w(TXIFG_BIT)		<= is_tx_i;
	is_w(BTIFG_BIT)		<= is_bt_i;
	is_w(KEY1IFG_BIT)	<= is_key1_i;
	is_w(KEY2IFG_BIT)	<= is_key2_i;
	is_w(KEY3IFG_BIT)	<= is_key3_i;

	wr_w		<= cs_i AND MemWrite_ctrl_i;
	rd_w		<= cs_i AND MemRead_ctrl_i;
	cycle1_w	<= NOT inta_n_i;

	--=======================================
	-- IFG and INTR - the second circuit of clause 6.v, drawn literally
	--=======================================
	-- A flag is visible only while its own enable is set: IFG(x) = irq(x) AND IE(x). That
	-- is reading 1 in the header, and it is also why nothing here needs to mask irq_q
	-- again further down.
	ifg_w	<= irq_q AND ie_q;

	-- The OR of every flag, gated by the global enable. GIE lives in gp[0] of the register
	-- file and arrives from the CPU rather than being stored here, because the service
	-- protocol clears and restores it in hardware.
	intr_o	<= gie_i WHEN ifg_w /= SRC_ZERO ELSE '0';

	--=======================================
	-- Priority encoder and TYPE
	--=======================================
	-- First match wins, so the order of these branches is the Priority column of the vector
	-- table: RX is 2, TX is 3, the Basic Timer is 4 and the pushbuttons are 5, 6 and 7. Two
	-- flags pending together therefore yield the lower TYPE value, and the loser stays set
	-- and is served on the next request - only the source actually being serviced is
	-- cleared. TYPE is 00h when nothing is pending, which is the RESET vector and never
	-- reaches the CPU, because INTR is low in that case.
	type_w	<=	TYPE_RX		WHEN ifg_w(RXIFG_BIT)	= '1' ELSE
				TYPE_TX		WHEN ifg_w(TXIFG_BIT)	= '1' ELSE
				TYPE_BT		WHEN ifg_w(BTIFG_BIT)	= '1' ELSE
				TYPE_KEY1	WHEN ifg_w(KEY1IFG_BIT)	= '1' ELSE
				TYPE_KEY2	WHEN ifg_w(KEY2IFG_BIT)	= '1' ELSE
				TYPE_KEY3	WHEN ifg_w(KEY3IFG_BIT)	= '1' ELSE
				TYPE_IDLE;

	-- The same chain as a one-hot vector, so cycle 1 can record which source it committed
	-- to without decoding TYPE back again.
	sel_w(RXIFG_BIT)	<=	ifg_w(RXIFG_BIT);
	sel_w(TXIFG_BIT)	<=	ifg_w(TXIFG_BIT)	AND NOT ifg_w(RXIFG_BIT);
	sel_w(BTIFG_BIT)	<=	ifg_w(BTIFG_BIT)	AND NOT (ifg_w(TXIFG_BIT) OR ifg_w(RXIFG_BIT));
	sel_w(KEY1IFG_BIT)	<=	ifg_w(KEY1IFG_BIT)	AND NOT (ifg_w(BTIFG_BIT) OR ifg_w(TXIFG_BIT)
													  OR ifg_w(RXIFG_BIT));
	sel_w(KEY2IFG_BIT)	<=	ifg_w(KEY2IFG_BIT)	AND NOT (ifg_w(KEY1IFG_BIT) OR ifg_w(BTIFG_BIT)
													  OR ifg_w(TXIFG_BIT) OR ifg_w(RXIFG_BIT));
	sel_w(KEY3IFG_BIT)	<=	ifg_w(KEY3IFG_BIT)	AND NOT (ifg_w(KEY2IFG_BIT) OR ifg_w(KEY1IFG_BIT)
													  OR ifg_w(BTIFG_BIT) OR ifg_w(TXIFG_BIT)
													  OR ifg_w(RXIFG_BIT));

	--=======================================
	-- Flag clearing
	--=======================================
	-- A store to 0x202D writes the value the register should take: a bit stored as '0'
	-- clears that flag, a bit stored as '1' leaves it alone. See the header - this is what
	-- the supplied applications' "and t3,t3,MASK ; sw t3,0(IFG)" idiom and their opening
	-- "sw zero,0(IFG)" both require, and it is NOT write-one-to-clear.
	CLRSW: for i in 0 to NSRC-1 generate
		clr_sw_w(i)	<= '1' WHEN (wr_w = '1' AND addr_i = SEL_IFG AND data_wr_i(i) = '0')
						  ELSE '0';
	end generate;

	-- Automatic clear in protocol cycle 2, for the synchronous sources only. svc_q is set
	-- at the end of cycle 1 and cycle1_w has gone low again by cycle 2, so this is true for
	-- exactly one cycle per service.
	clr_svc_w	<= served_q AND AUTO_CLEAR WHEN (svc_q = '1' AND cycle1_w = '0')
											ELSE SRC_ZERO;

	--=======================================
	-- The interrupt request flip-flops, and the service tracker
	--=======================================
	-- One enabled flip-flop per source instead of a flip-flop clocked by the source, and
	-- SET ahead of CLEAR so an event landing on the cycle its flag is cleared survives.
	-- Both are readings 2 and 3 in the header.
	IRQFF:
	process (clk_i, rst_i)
	begin
		if rst_i = '1' then
			irq_q		<= (OTHERS => '0');
			ie_q		<= (OTHERS => '0');
			served_q	<= (OTHERS => '0');
			svc_q		<= '0';
		elsif falling_edge(clk_i) then

			-- IE, a plain read/write byte register. Only six bits exist; 7:6 read as zero.
			if wr_w = '1' and addr_i = SEL_IE then
				ie_q	<= data_wr_i(NSRC-1 DOWNTO 0);
			end if;

			-- Protocol tracking. Capturing the winner in cycle 1 rather than recomputing it
			-- in cycle 2 matters: the CPU clears GIE during cycle 1, and a higher priority
			-- source arriving in between must not redirect the automatic clear onto a flag
			-- that was never served.
			if cycle1_w = '1' then
				served_q	<= sel_w;
				svc_q		<= '1';
			else
				svc_q		<= '0';
			end if;

			-- The flags themselves
			for i in 0 to NSRC-1 loop
				if is_w(i) = '1' then
					irq_q(i)	<= '1';
				elsif clr_sw_w(i) = '1' or clr_svc_w(i) = '1' then
					irq_q(i)	<= '0';
				end if;
			end loop;

		end if;
	end process;

	--=======================================
	-- Read path
	--=======================================
	-- IE and IFG read back their six bits zero extended; TYPE is read only. 0x202F has no
	-- register behind it and reads zero.
	reg_rd_w	<=	PAD_HI & ie_q	WHEN addr_i = SEL_IE	ELSE
					PAD_HI & ifg_w	WHEN addr_i = SEL_IFG	ELSE
					type_w			WHEN addr_i = SEL_TYPE	ELSE
					(OTHERS => '0');

	rdata_w(DATA_BUS_WIDTH-1 DOWNTO REG_WIDTH)		<= (OTHERS => '0');
	rdata_w(REG_WIDTH-1 DOWNTO 0)					<= reg_rd_w;

	type_ext_w(DATA_BUS_WIDTH-1 DOWNTO REG_WIDTH)	<= (OTHERS => '0');
	type_ext_w(REG_WIDTH-1 DOWNTO 0)				<= type_w;

	-- Two ways onto the bus: an ordinary load, and protocol cycle 1, where the CPU is not
	-- addressing this device at all but page 15 still requires TYPE on the data bus. Cycle
	-- 1 wins, which is free of conflict because the CPU is not executing a load then.
	drive_w		<= rd_w OR cycle1_w;
	bus_drive_o	<= drive_w;

	data_rd_o	<=	type_ext_w	WHEN cycle1_w	= '1' ELSE
					rdata_w		WHEN rd_w		= '1' ELSE
					(OTHERS => '0');

END rtl;