---------------------------------------------------------------------------------------------
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- PORT_SW - memory mapped General Purpose Input (GPI), 8-bit
--
-- Mapping : byte address 0x2010, reads SW7..SW0
-- Ref     : Figure 5 - "Basic GPIO peripheral connection using Memory Mapped I/O"
--
-- load  (cs_i='1' & MemRead_ctrl_i='1') : the switch value is zero extended onto data_rd_o
-- store                                 : has no effect. This is an input port, there is no
--                                         register the CPU can write, so MemWrite_ctrl_i and
--                                         data_wr_i are not brought into this module at all.
--
-- Figure 5 draws PORT_SW with no storage element at all: the switches reach the data bus
-- straight through the tri-state buffer, gated by CS and MemRead. This module is that path
-- exactly - purely combinational, no clock, no reset, no register. It is the one GPIO port
-- in the design that has no state of its own: PORT_LEDR and the HEX pairs hold what the CPU
-- wrote, PORT_SW only reports what the pins are doing right now.
--
-- No input synchronizer is placed here, although SW is asynchronous to MCLK. The only
-- element that samples this path is the register file write port, one flop per bit, so a
-- switch moved exactly on the sampling edge resolves to either its old or its new value -
-- both of which are legitimate answers for a switch that is being moved at that instant.
-- There is no second sampler that could resolve the same bit differently and no control
-- decision taken from the value in the same cycle, so the classic multi-sampler failure
-- cannot occur. The CDC discussion of the project definition (Figure 10) is about the
-- MCLK / DIVCLK crossing of the division accelerator, where a control bit really does
-- cross clock domains, and it is handled there by CDC_SYNC.
--
-- The tri-state buffer of Figure 5 is realised as a read multiplexer: this module drives
-- zeros when it is not selected, so the I/O read paths can be OR-ed together. Cyclone
-- devices have no internal tri-state anyway - Quartus converts every internal 'Z' into
-- exactly this multiplexer.
---------------------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY GPIO_SW_Interface IS
	generic(
		DATA_BUS_WIDTH		: integer := 32;
		SW_WIDTH			: integer := 8		-- SW7 .. SW0
	);
	PORT(
		--Inputs
		cs_i				: IN	STD_LOGIC;	-- chip select, from the GPIO address decoder
		MemRead_ctrl_i		: IN	STD_LOGIC;
		SW_i				: IN	STD_LOGIC_VECTOR(SW_WIDTH-1 DOWNTO 0);

		--Outputs
		data_rd_o			: OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0)
	);
END GPIO_SW_Interface;
---------------------------------------------------------------------------------------------
ARCHITECTURE rtl OF GPIO_SW_Interface IS

	SIGNAL rdata_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

BEGIN

	--=======================================
	-- Read path : device -> CPU
	--=======================================
	-- SW7..SW0 occupy the low byte of the data bus, the rest reads as zero, so
	-- both lw and lbu return the switch value unchanged.
	rdata_w(DATA_BUS_WIDTH-1 DOWNTO SW_WIDTH)	<= (OTHERS => '0');
	rdata_w(SW_WIDTH-1 DOWNTO 0)				<= SW_i;

	-- The device answers only when the address on the bus is its own and the
	-- access is a load; a store to 0x2010 is silently ignored.
	data_rd_o	<= rdata_w WHEN (cs_i = '1' AND MemRead_ctrl_i = '1') ELSE (OTHERS => '0');

END rtl;