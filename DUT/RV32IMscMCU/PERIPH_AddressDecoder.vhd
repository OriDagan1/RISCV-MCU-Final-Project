---------------------------------------------------------------------------------------------
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- PERIPH_AddressDecoder - the "Optimized Address Decoder" of Figure 5, clause 6 block
--
-- One chip select per peripheral with interrupt capability, decoded from the byte
-- address the core drives onto the data bus. This is the companion of
-- GPIO_AddressDecoder: that one owns 0x2000-0x201F and answers for the eight GPIO
-- ports of clause 5, this one owns the peripherals of clause 6 above it. Between
-- them they cover the whole mapped part of the I/O region, and neither ever
-- asserts a select the other could also assert - see "one-hot across both
-- decoders" below.
--
-- Two decoders rather than one wider decoder, deliberately. GPIO_AddressDecoder
-- is anchored by an ASSERT and by an exhaustive testbench that sweeps all 2*16384
-- input combinations and requires 0x2014, 0x201C, 0x2020, 0x2024, 0x2028, 0x202C,
-- 0x202D and 0x202E to select nothing. Those checks are correct and must keep
-- passing: they are what proves the GPIO block does not alias onto clause 6.
-- Widening that module would have to delete its own regression tests.
--
-- The decode is purely combinational, exactly as drawn in Figure 5: the address is
-- stable for the whole cycle of the single-cycle core, and the chip selects are
-- qualified inside each peripheral by MemRead_ctrl / MemWrite_ctrl, so no storage
-- element is needed here.
--
--   Data address space (Figure 2), 14-bit byte address:
--     0x0000 - 0x1FFF   DTCM
--     0x2000 - 0x3FFF   memory-mapped I/O          <- bit 13, decoded in MCU.vhd
--
--   Peripherals with interrupt capability (clause 6 of the project definition):
--
--     byte addr | 13 | 12..6 | 5  4  3  2 | 1  0 |  register  | device
--     ----------+----+-------+------------+------+------------+-------------------
--      0x2014   |  1 |   0   | 0  1  0  1 | x  x | PORT_PB    | KEY[3-1]
--      0x2018   |  1 |   0   | 0  1  1  0 | x  x | UTCL/RXBF/TXBF | USART - BONUS
--      0x201C   |  1 |   0   | 0  1  1  1 | x  0 | BTCTL1     | Basic Timer
--      0x201D   |  1 |   0   | 0  1  1  1 | x  1 | BTCTL2     | Basic Timer
--      0x2020   |  1 |   0   | 1  0  0  0 | 0  0 | BTCMPR0    | Basic Timer
--      0x2024   |  1 |   0   | 1  0  0  1 | 0  0 | BTCMPR1    | Basic Timer
--      0x2028   |  1 |   0   | 1  0  1  0 | 0  0 | BTCAPR     | Basic Timer
--      0x202C   |  1 |   0   | 1  0  1  1 | 0  0 | IE         | Interrupt Controller
--      0x202D   |  1 |   0   | 1  0  1  1 | 0  1 | IFG        | Interrupt Controller
--      0x202E   |  1 |   0   | 1  0  1  1 | 1  0 | TYPE       | Interrupt Controller
--
-- WHY THE DEVICE SELECT IS [5:2] AND NOT [4:2]. The GPIO block spans one aligned
-- group of eight four-byte slots, so three bits are enough there. Clause 6 reaches
-- up to 0x202E, which needs bit 5 as well: BTCMPR0 (0x2020) differs from PORT_LEDR
-- (0x2000) in bit 5 alone, and IE (0x202C) differs from the HEX4/HEX5 pair
-- (0x200C) in bit 5 alone. Four bits of device select and bits [12:6] forced to
-- zero put this block at exactly 0x2000-0x203F, of which it decodes only the seven
-- patterns above.
--
-- ONE-HOT ACROSS BOTH DECODERS. The GPIO decoder answers for [5:2] in 0000..0100
-- (it forces bit 5 to zero and decodes [4:2]); this one answers for 0101, 0111,
-- 1000, 1001, 1010 and 1011. The two sets are disjoint by construction, so at most
-- one chip select in the whole design is ever asserted and the read paths of all
-- devices can be OR-ed together in MCU.vhd exactly as they are today.
--
-- PAIRS AND TRIPLES ARE NOT SPLIT HERE. BTCTL1 and BTCTL2 differ in bit 0 only, and
-- IE, IFG and TYPE differ in bits [1:0] only. Following the treatment of the HEX
-- pairs in GPIO_AddressDecoder, those bits are NOT decoded in this module: the
-- device gets one chip select for the whole group and MCU.vhd wires the low
-- address bits straight to the sel input of the peripheral, which picks the
-- register inside the group. Keeping the split inside the device is what lets one
-- BidirPin and one oe term serve the whole group.
--
-- ALIASES, intentional and documented, exactly as in the GPIO block:
--   PORT_PB  also answers at 0x2015-0x2017      (bits [1:0] not decoded)
--   BTCTL    also answers at 0x201E-0x201F      (bit 1 not decoded, so 0x201E is a
--                                                second name for BTCTL1 and 0x201F
--                                                for BTCTL2)
--   BTCMPR0/1 and BTCAPR are word addresses, so their three trailing byte
--            addresses are aliases of the word and no benchmark uses them
--   The interrupt controller group has a fourth slot, 0x202F, which clause 6 does
--            not name. cs_ic_o is asserted there too; the interrupt controller
--            itself must ignore sel = "11" rather than this module suppressing it,
--            which would cost a comparator on the load/store critical path.
--
-- The USART slot 0110 (0x2018-0x201B) is deliberately left undecoded: the USART is
-- the 20% bonus of clause 6.iv and is not part of this design. A load from it
-- returns zero, because every peripheral drives zeros when it is not selected and
-- MCU.vhd parks the shared bus at zero when no output enable is active. Adding the
-- bonus later means one more SEL constant and one more chip select, nothing else.
--
-- DA_WIDTH is checked to be 14 below, for the same reason as in the GPIO decoder:
-- the addresses of clause 6 are absolute, and the I/O region begins at
-- 2**(DA_WIDTH-1).
---------------------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY PERIPH_AddressDecoder IS
	generic(
		DA_WIDTH			: integer := 14		-- width of the byte address on the data bus
	);
	PORT(
		--Inputs
		en_i				: IN	STD_LOGIC;	-- I/O space select, bit 13 of the byte address (from MCU)
		addr_i				: IN	STD_LOGIC_VECTOR(DA_WIDTH-1 DOWNTO 0);	-- byte address on the bus

		--Outputs, one chip select per device
		cs_pb_o				: OUT	STD_LOGIC;	-- PORT_PB                  0x2014
		cs_btctl_o			: OUT	STD_LOGIC;	-- BTCTL1 / BTCTL2          0x201C / 0x201D
		cs_btcmpr0_o		: OUT	STD_LOGIC;	-- BTCMPR0                  0x2020
		cs_btcmpr1_o		: OUT	STD_LOGIC;	-- BTCMPR1                  0x2024
		cs_btcapr_o			: OUT	STD_LOGIC;	-- BTCAPR                   0x2028
		cs_ic_o				: OUT	STD_LOGIC	-- IE / IFG / TYPE          0x202C / 0x202D / 0x202E
	);
END PERIPH_AddressDecoder;
---------------------------------------------------------------------------------------------
ARCHITECTURE rtl OF PERIPH_AddressDecoder IS

	-- Device select field, address bits [5:2]
	CONSTANT SEL_MSB		: integer := 5;
	CONSTANT SEL_LSB		: integer := 2;

	CONSTANT SEL_PB			: STD_LOGIC_VECTOR(SEL_MSB-SEL_LSB DOWNTO 0) := "0101";	-- 0x2014
	-- "0110" is the USART group 0x2018-0x201B, clause 6.iv, bonus - not decoded
	CONSTANT SEL_BTCTL		: STD_LOGIC_VECTOR(SEL_MSB-SEL_LSB DOWNTO 0) := "0111";	-- 0x201C, 0x201D
	CONSTANT SEL_BTCMPR0	: STD_LOGIC_VECTOR(SEL_MSB-SEL_LSB DOWNTO 0) := "1000";	-- 0x2020
	CONSTANT SEL_BTCMPR1	: STD_LOGIC_VECTOR(SEL_MSB-SEL_LSB DOWNTO 0) := "1001";	-- 0x2024
	CONSTANT SEL_BTCAPR		: STD_LOGIC_VECTOR(SEL_MSB-SEL_LSB DOWNTO 0) := "1010";	-- 0x2028
	CONSTANT SEL_IC			: STD_LOGIC_VECTOR(SEL_MSB-SEL_LSB DOWNTO 0) := "1011";	-- 0x202C, 0x202D, 0x202E

	-- Address bits above the device select field, all zero inside this block
	CONSTANT ZEROS_UPPER	: STD_LOGIC_VECTOR(DA_WIDTH-2 DOWNTO SEL_MSB+1) := (OTHERS => '0');

	-- Byte address width the map of clause 6 was written for: the I/O region starts
	-- at 0x2000, which is bit 13, i.e. 14 address bits on the data bus.
	CONSTANT MAP_DA_WIDTH	: integer := 14;

	SIGNAL dev_sel_w		: STD_LOGIC_VECTOR(SEL_MSB-SEL_LSB DOWNTO 0);
	SIGNAL periph_en_w		: STD_LOGIC;

BEGIN

	-- The addresses of clause 6 are absolute, so the width of the byte address is
	-- not free. en_i is bit DA_WIDTH-1 of the address (MCU.vhd), so the I/O region
	-- starts at 2**(DA_WIDTH-1) and clause 6 places PORT_PB at 0x2014 inside it,
	-- hence 14 bits. The assembly applications and the mapping header load these
	-- addresses as constants, so a different width would silently move the whole
	-- block out from under them.
	ASSERT DA_WIDTH = MAP_DA_WIDTH
		REPORT "PERIPH_AddressDecoder: DA_WIDTH must be 14 - the clause 6 block is "
			 & "anchored at absolute byte addresses inside the I/O region, which "
			 & "begins at 2**(DA_WIDTH-1) = 0x2000"
		SEVERITY FAILURE;

	--=======================================
	-- Block select
	--=======================================
	-- This block answers only for 0x2000-0x203F: the I/O space enable from MCU.vhd,
	-- the I/O region bit of the address itself, and all address bits between the
	-- device select field and bit 13 at zero. Everything above stays unmapped.
	--
	-- Bit DA_WIDTH-1 is tested here as well as arriving as en_i, which is the Ak
	-- input the decoder of Figure 5 is drawn with. MCU.vhd derives en_i from that
	-- very bit, so synthesis folds the two together and the AND costs nothing - but
	-- no bit of addr_i is then left undecoded, and the module still selects only
	-- inside the I/O region if it is ever enabled from somewhere else.
	periph_en_w	<= en_i AND addr_i(DA_WIDTH-1)
					WHEN (addr_i(DA_WIDTH-2 DOWNTO SEL_MSB+1) = ZEROS_UPPER)
					ELSE '0';

	--=======================================
	-- Device select
	--=======================================
	dev_sel_w	<= addr_i(SEL_MSB DOWNTO SEL_LSB);

	-- One-hot by construction: the patterns are mutually exclusive within this
	-- module, and disjoint from the patterns of GPIO_AddressDecoder, so at most one
	-- device in the whole design ever sees its chip select asserted and the read
	-- paths can be OR-ed together in MCU.vhd.
	cs_pb_o			<= periph_en_w WHEN (dev_sel_w = SEL_PB)		ELSE '0';
	cs_btctl_o		<= periph_en_w WHEN (dev_sel_w = SEL_BTCTL)		ELSE '0';
	cs_btcmpr0_o	<= periph_en_w WHEN (dev_sel_w = SEL_BTCMPR0)	ELSE '0';
	cs_btcmpr1_o	<= periph_en_w WHEN (dev_sel_w = SEL_BTCMPR1)	ELSE '0';
	cs_btcapr_o		<= periph_en_w WHEN (dev_sel_w = SEL_BTCAPR)	ELSE '0';
	cs_ic_o			<= periph_en_w WHEN (dev_sel_w = SEL_IC)		ELSE '0';

END rtl;