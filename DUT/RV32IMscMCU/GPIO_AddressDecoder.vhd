---------------------------------------------------------------------------------------------
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- GPIO_AddressDecoder - the "Optimized Address Decoder" of Figure 5
--
-- One chip select per GPIO device, decoded from the byte address the core drives
-- onto the data bus. This is the only place in the design that knows which
-- address belongs to which device: every GPIO port module receives a single cs_i
-- and answers only when it is asserted, so a port never inspects the address bus
-- itself.
--
-- The decode is purely combinational, exactly as drawn in Figure 5: the address
-- is stable for the whole cycle of the single-cycle core, and the chip selects
-- are qualified inside each port by MemRead_ctrl / MemWrite_ctrl, so no storage
-- element is needed here.
--
--   Data address space (Figure 2), 14-bit byte address:
--     0x0000 - 0x1FFF   DTCM
--     0x2000 - 0x3FFF   memory-mapped I/O          <- bit 13, decoded in MCU.vhd
--
--   GPIO map (clause 5 of the project definition):
--
--     byte addr | 13 | 12..5 | 4  3  2 | 1 | 0 |  device            | direction
--     ----------+----+-------+---------+---+---+--------------------+----------
--      0x2000   |  1 |   0   | 0  0  0 | x | x | PORT_LEDR          | GPO
--      0x2004   |  1 |   0   | 0  0  1 | 0 | 0 | PORT_HEX0          | GPO
--      0x2005   |  1 |   0   | 0  0  1 | 0 | 1 | PORT_HEX1          | GPO
--      0x2008   |  1 |   0   | 0  1  0 | 0 | 0 | PORT_HEX2          | GPO
--      0x2009   |  1 |   0   | 0  1  0 | 0 | 1 | PORT_HEX3          | GPO
--      0x200C   |  1 |   0   | 0  1  1 | 0 | 0 | PORT_HEX4          | GPO
--      0x200D   |  1 |   0   | 0  1  1 | 0 | 1 | PORT_HEX5          | GPO
--      0x2010   |  1 |   0   | 1  0  0 | x | x | PORT_SW            | GPI
--
-- Address bits [4:2] are therefore the device select, which is what Figure 5
-- feeds into the decoder as <Ak,A4,A3,A2>. Bit 0 is NOT decoded here: the two
-- displays of a pair differ in bit 0 only, so the pair gets one chip select and
-- bit 0 of the address is wired straight to sel_i of GPIO_HEX_Pair_Interface,
-- which picks the digit inside the pair.
--
-- Bits [12:5] ARE decoded, although Figure 5 does not show them, so that this
-- block occupies exactly 0x2000-0x201F. Leaving them out would make the decode
-- alias, and the aliases are not harmless: the peripherals with interrupt
-- capability of clause 6 live just above this block, and BTCMPR0 (0x2020) has
-- the same [4:2] pattern as PORT_LEDR while IE (0x202C) has the same pattern as
-- the HEX4/HEX5 pair. Decoding bit 5 upwards costs one 8-input gate and keeps
-- those addresses free for the timer, the pushbuttons, the USART and the
-- interrupt controller.
--
-- Inside the block the decode is still the optimized one of Figure 5: bit 1 and,
-- for the single-byte ports, bit 0 are ignored, so PORT_LEDR also answers at
-- 0x2001..0x2003 and PORT_SW at 0x2011..0x2013. Those addresses are unmapped, no
-- benchmark application uses them, and decoding them would only add logic to the
-- critical path of the load/store cycle.
--
-- The three [4:2] combinations 101, 110 and 111 (0x2014, 0x2018, 0x201C) are left
-- undecoded on purpose: they are PORT_PB, the USART registers and the Basic Timer
-- control registers of clause 6. A load from them returns zero for now, because
-- every port drives zeros when it is not selected and MCU.vhd ORs the read paths.
--
-- DA_WIDTH is checked to be 14 below. The decode itself is written relative to the
-- top address bit and would work for any width - it is the map that is not: the I/O
-- region begins at 2**(DA_WIDTH-1), and clause 5 puts PORT_LEDR at 0x2000, which
-- fixes the byte address at 14 bits.
---------------------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY GPIO_AddressDecoder IS
	generic(
		DA_WIDTH			: integer := 14		-- width of the byte address on the data bus
	);
	PORT(
		--Inputs
		en_i				: IN	STD_LOGIC;	-- I/O space select, bit 13 of the byte address (from MCU)
		addr_i				: IN	STD_LOGIC_VECTOR(DA_WIDTH-1 DOWNTO 0);	-- byte address on the bus

		--Outputs, one chip select per device
		cs_ledr_o			: OUT	STD_LOGIC;	-- PORT_LEDR                0x2000
		cs_hex0_1_o			: OUT	STD_LOGIC;	-- PORT_HEX0 / PORT_HEX1    0x2004 / 0x2005
		cs_hex2_3_o			: OUT	STD_LOGIC;	-- PORT_HEX2 / PORT_HEX3    0x2008 / 0x2009
		cs_hex4_5_o			: OUT	STD_LOGIC;	-- PORT_HEX4 / PORT_HEX5    0x200C / 0x200D
		cs_sw_o				: OUT	STD_LOGIC	-- PORT_SW                  0x2010
	);
END GPIO_AddressDecoder;
---------------------------------------------------------------------------------------------
ARCHITECTURE rtl OF GPIO_AddressDecoder IS

	-- Device select field, address bits [4:2]
	CONSTANT SEL_MSB		: integer := 4;
	CONSTANT SEL_LSB		: integer := 2;

	CONSTANT SEL_LEDR		: STD_LOGIC_VECTOR(SEL_MSB-SEL_LSB DOWNTO 0) := "000";	-- 0x2000
	CONSTANT SEL_HEX0_1		: STD_LOGIC_VECTOR(SEL_MSB-SEL_LSB DOWNTO 0) := "001";	-- 0x2004, 0x2005
	CONSTANT SEL_HEX2_3		: STD_LOGIC_VECTOR(SEL_MSB-SEL_LSB DOWNTO 0) := "010";	-- 0x2008, 0x2009
	CONSTANT SEL_HEX4_5		: STD_LOGIC_VECTOR(SEL_MSB-SEL_LSB DOWNTO 0) := "011";	-- 0x200C, 0x200D
	CONSTANT SEL_SW			: STD_LOGIC_VECTOR(SEL_MSB-SEL_LSB DOWNTO 0) := "100";	-- 0x2010

	-- Address bits above the device select field, all zero inside the GPIO block
	CONSTANT ZEROS_UPPER	: STD_LOGIC_VECTOR(DA_WIDTH-2 DOWNTO SEL_MSB+1) := (OTHERS => '0');

	-- Byte address width the map of clause 5 was written for: PORT_LEDR at 0x2000
	-- means the I/O select bit is bit 13, i.e. 14 address bits on the data bus.
	CONSTANT MAP_DA_WIDTH	: integer := 14;

	SIGNAL dev_sel_w		: STD_LOGIC_VECTOR(SEL_MSB-SEL_LSB DOWNTO 0);
	SIGNAL gpio_en_w		: STD_LOGIC;

BEGIN

	-- The addresses of clause 5 are absolute, so the width of the byte address is
	-- not free. en_i is bit DA_WIDTH-1 of the address (MCU.vhd), so the I/O region
	-- starts at 2**(DA_WIDTH-1); PORT_LEDR sits at the bottom of it and clause 5
	-- puts it at 0x2000, hence 14 bits. The assembly applications and the mapping
	-- header load these addresses as constants, so a different width would silently
	-- move the whole block out from under them.
	ASSERT DA_WIDTH = MAP_DA_WIDTH
		REPORT "GPIO_AddressDecoder: DA_WIDTH must be 14 - the GPIO block is anchored "
			 & "at the absolute byte address 0x2000 (clause 5), which is 2**(DA_WIDTH-1)"
		SEVERITY FAILURE;

	--=======================================
	-- Block select
	--=======================================
	-- The GPIO block answers only for 0x2000-0x201F: the I/O space enable from
	-- MCU.vhd, the I/O region bit of the address itself, and all address bits
	-- between the device select field and bit 13 at zero. Everything above stays
	-- free for the peripherals with interrupt capability.
	--
	-- Bit DA_WIDTH-1 is tested here as well as arriving as en_i, which is the Ak
	-- input the decoder of Figure 5 is drawn with. MCU.vhd derives en_i from that
	-- very bit, so synthesis folds the two together and the AND costs nothing -
	-- but no bit of addr_i is then left undecoded, and the module still selects
	-- only inside the I/O region if it is ever enabled from somewhere else.
	gpio_en_w	<= en_i AND addr_i(DA_WIDTH-1)
					WHEN (addr_i(DA_WIDTH-2 DOWNTO SEL_MSB+1) = ZEROS_UPPER)
					ELSE '0';

	--=======================================
	-- Device select
	--=======================================
	dev_sel_w	<= addr_i(SEL_MSB DOWNTO SEL_LSB);

	-- One-hot by construction: the patterns are mutually exclusive, so at most
	-- one device ever sees its chip select asserted and the read paths of the
	-- ports can be OR-ed together in MCU.vhd.
	cs_ledr_o	<= gpio_en_w WHEN (dev_sel_w = SEL_LEDR)	ELSE '0';
	cs_hex0_1_o	<= gpio_en_w WHEN (dev_sel_w = SEL_HEX0_1)	ELSE '0';
	cs_hex2_3_o	<= gpio_en_w WHEN (dev_sel_w = SEL_HEX2_3)	ELSE '0';
	cs_hex4_5_o	<= gpio_en_w WHEN (dev_sel_w = SEL_HEX4_5)	ELSE '0';
	cs_sw_o		<= gpio_en_w WHEN (dev_sel_w = SEL_SW)		ELSE '0';

END rtl;