---------------------------------------------------------------------------------------------
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- PORT_HEX pair - memory mapped General Purpose Output (GPO), two hex digits
--
-- One instance serves two adjacent byte addresses, i.e. one pair of displays:
--     instance 0 : 0x2004 -> HEX0 , 0x2005 -> HEX1
--     instance 1 : 0x2008 -> HEX2 , 0x2009 -> HEX3
--     instance 2 : 0x200C -> HEX4 , 0x200D -> HEX5
-- Inside a pair the two addresses differ in bit 0 only, so the decoder gives
-- this module one chip select for the pair and lets bit 0 of the byte address
-- choose the digit: sel_i = '0' is the low (even) address, sel_i = '1' is the
-- high (odd) one. Bit 1 is always '0' in the map above, which is why the pair
-- select in the decoder comes from address bits [3:2].
--
-- Ref : Figure 5 - "Basic GPIO peripheral connection using Memory Mapped I/O"
--
-- store (cs_i='1' & MemWrite_ctrl_i='1') : data_wr_i[PORT_WIDTH-1:0] is captured
--                                          into the register selected by sel_i
-- load  (cs_i='1' & MemRead_ctrl_i ='1') : that register is zero extended onto
--                                          data_rd_o
--
-- The port register is a full byte, like the D-latch of Figure 5 and like the
-- LEDR port: a store keeps data_wr_i[7:0] and a load returns it unchanged. The
-- display itself can only show one hexadecimal digit, so only the low nibble
-- reaches the encoder - but nothing the CPU wrote is thrown away, and a load
-- returns exactly the byte that was stored.
--
-- The registers are written on the FALLING edge of the clock, matching the DTCM
-- (dmemory drives the altsyncram clock0 with NOT clk_i), so that every target
-- on the data bus captures write data at the same instant of the CPU cycle.
--
-- Figure 5 draws the port as a D-latch whose enable is (CS AND MemWrite), i.e.
-- level sensitive and with no clock at all. This design uses an edge triggered
-- register instead. The two behave identically as seen from the CPU, because in
-- a single-cycle core the address, the data and MemWrite are all stable for the
-- whole cycle, so the value latched when the enable falls is the value captured
-- on the falling edge. The register is preferred because an inferred latch is
-- not analysed by TimeQuest, cannot be sampled reliably by Signal-Tap, and would
-- pass any glitch on cs_i or MemWrite_ctrl_i straight through to the displays -
-- and because PORT_LEDR and the DTCM already write on this same edge, so all
-- targets on the data bus stay consistent with one another.
--
-- The tri-state buffer of Figure 5 is realised as a read multiplexer: this
-- module drives zeros when it is not selected, so the I/O read paths can be
-- OR-ed together. Cyclone devices have no internal tri-state anyway - Quartus
-- converts every internal 'Z' into exactly this multiplexer.
--
-- The binary to seven-segment translation is done by two SevenSegmentEncoder
-- instances, one per digit, so the register file here stays purely a bus
-- peripheral and the encoding stays in one place for all six displays.
---------------------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY GPIO_HEX_Pair_Interface IS
	generic(
		DATA_BUS_WIDTH		: integer := 32;
		PORT_WIDTH			: integer := 8;		-- width of the port register, Figure 5 (must be >= 4)
		ACTIVE_LOW			: boolean := TRUE	-- board displays are active low
	);
	PORT(
		--Inputs
		clk_i				: IN	STD_LOGIC;
		rst_i				: IN	STD_LOGIC;
		cs_i				: IN	STD_LOGIC;	-- chip select of the pair, from the GPIO address decoder
		sel_i				: IN	STD_LOGIC;	-- bit 0 of the byte address: '0' low digit, '1' high digit
		MemRead_ctrl_i		: IN	STD_LOGIC;
		MemWrite_ctrl_i		: IN	STD_LOGIC;
		data_wr_i			: IN	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

		--Outputs
		data_rd_o			: OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
		HEX_lo_o			: OUT	STD_LOGIC_VECTOR(6 DOWNTO 0);	-- display at the even address, g f e d c b a
		HEX_hi_o			: OUT	STD_LOGIC_VECTOR(6 DOWNTO 0)	-- display at the odd address,  g f e d c b a
	);
END GPIO_HEX_Pair_Interface;
---------------------------------------------------------------------------------------------
ARCHITECTURE rtl OF GPIO_HEX_Pair_Interface IS

	-- Not a generic: the SevenSegmentEncoder input is four bits wide, so this
	-- is a property of the encoder and changing it here would only break the
	-- port map below.
	CONSTANT DIGIT_WIDTH	: integer := 4;

	SIGNAL hex_lo_q		: STD_LOGIC_VECTOR(PORT_WIDTH-1 DOWNTO 0);		-- the SFR of the even address
	SIGNAL hex_hi_q		: STD_LOGIC_VECTOR(PORT_WIDTH-1 DOWNTO 0);		-- the SFR of the odd address
	SIGNAL wren_lo_w	: STD_LOGIC;
	SIGNAL wren_hi_w	: STD_LOGIC;
	SIGNAL hex_rd_w		: STD_LOGIC_VECTOR(PORT_WIDTH-1 DOWNTO 0);
	SIGNAL rdata_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

BEGIN

	--=======================================
	-- Access qualifier
	--=======================================
	-- The pair answers only when the address on the bus is one of its own two,
	-- and inside the pair exactly one register is written per store.
	wren_lo_w	<= cs_i AND MemWrite_ctrl_i AND (NOT sel_i);
	wren_hi_w	<= cs_i AND MemWrite_ctrl_i AND sel_i;

	--=======================================
	-- Write path : CPU -> device
	--=======================================
	WRPORT:
	process (clk_i, rst_i)
	begin
		if rst_i = '1' then
			hex_lo_q	<= (OTHERS => '0');
			hex_hi_q	<= (OTHERS => '0');
		elsif falling_edge(clk_i) then
			if wren_lo_w = '1' then
				hex_lo_q	<= data_wr_i(PORT_WIDTH-1 DOWNTO 0);
			end if;
			if wren_hi_w = '1' then
				hex_hi_q	<= data_wr_i(PORT_WIDTH-1 DOWNTO 0);
			end if;
		end if;
	end process;

	--=======================================
	-- Display path : device -> pins
	--=======================================
	-- Both digits are driven continuously; the displays are static, there is no
	-- multiplexing on the board. Only the low nibble of each port register is
	-- displayable - the upper bits are stored but have nowhere to go.
	SEG_LO: entity work.SevenSegmentEncoder
	generic map(
		ACTIVE_LOW		=> ACTIVE_LOW
	)
	PORT MAP (
		hex_value_i		=> hex_lo_q(DIGIT_WIDTH-1 DOWNTO 0),
		segments_o		=> HEX_lo_o
	);

	SEG_HI: entity work.SevenSegmentEncoder
	generic map(
		ACTIVE_LOW		=> ACTIVE_LOW
	)
	PORT MAP (
		hex_value_i		=> hex_hi_q(DIGIT_WIDTH-1 DOWNTO 0),
		segments_o		=> HEX_hi_o
	);

	--=======================================
	-- Read path : device -> CPU
	--=======================================
	-- A load returns the byte that was stored, not the segment pattern: the
	-- port register is what the programmer wrote and what it reads back.
	hex_rd_w	<= hex_hi_q WHEN sel_i = '1' ELSE hex_lo_q;

	rdata_w(DATA_BUS_WIDTH-1 DOWNTO PORT_WIDTH)	<= (OTHERS => '0');
	rdata_w(PORT_WIDTH-1 DOWNTO 0)				<= hex_rd_w;

	data_rd_o	<= rdata_w WHEN (cs_i = '1' AND MemRead_ctrl_i = '1') ELSE (OTHERS => '0');

END rtl;