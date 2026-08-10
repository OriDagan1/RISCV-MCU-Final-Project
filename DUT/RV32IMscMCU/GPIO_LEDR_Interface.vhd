---------------------------------------------------------------------------------------------
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- PORT_LEDR - memory mapped General Purpose Output (GPO), 8-bit
--
-- Mapping : byte address 0x2000, drives LEDR7..LEDR0
-- Ref     : Figure 5 - "Basic GPIO peripheral connection using Memory Mapped I/O"
--
-- store (cs_i='1' & MemWrite_ctrl_i='1') : data_wr_i[7:0] is captured into the port register
-- load  (cs_i='1' & MemRead_ctrl_i ='1') : the port register is zero extended onto data_rd_o
--
-- The register is written on the FALLING edge of the clock, matching the DTCM
-- (dmemory drives the altsyncram clock0 with NOT clk_i), so that every target
-- on the data bus captures write data at the same instant of the CPU cycle.
--
-- The tri-state buffer of Figure 5 is realised as a read multiplexer: this
-- module drives zeros when it is not selected, so the I/O read paths can be
-- OR-ed together. Cyclone devices have no internal tri-state anyway - Quartus
-- converts every internal 'Z' into exactly this multiplexer.
---------------------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY GPIO_LEDR_Interface IS
	generic(
		DATA_BUS_WIDTH		: integer := 32;
		LEDR_WIDTH			: integer := 8		-- LEDR7 .. LEDR0
	);
	PORT(
		--Inputs
		clk_i				: IN	STD_LOGIC;
		rst_i				: IN	STD_LOGIC;
		cs_i				: IN	STD_LOGIC;	-- chip select, from the GPIO address decoder
		MemRead_ctrl_i		: IN	STD_LOGIC;
		MemWrite_ctrl_i		: IN	STD_LOGIC;
		data_wr_i			: IN	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

		--Outputs
		data_rd_o			: OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
		LEDR_o				: OUT	STD_LOGIC_VECTOR(LEDR_WIDTH-1 DOWNTO 0)
	);
END GPIO_LEDR_Interface;
---------------------------------------------------------------------------------------------
ARCHITECTURE rtl OF GPIO_LEDR_Interface IS

	SIGNAL ledr_q		: STD_LOGIC_VECTOR(LEDR_WIDTH-1 DOWNTO 0);		-- the SFR of this device
	SIGNAL wren_w		: STD_LOGIC;
	SIGNAL rdata_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

BEGIN

	--=======================================
	-- Access qualifier
	--=======================================
	-- The device answers only when the address on the bus is its own.
	wren_w	<= cs_i AND MemWrite_ctrl_i;

	--=======================================
	-- Write path : CPU -> device
	--=======================================
	WRPORT:
	process (clk_i, rst_i)
	begin
		if rst_i = '1' then
			ledr_q	<= (OTHERS => '0');
		elsif falling_edge(clk_i) then
			if wren_w = '1' then
				ledr_q	<= data_wr_i(LEDR_WIDTH-1 DOWNTO 0);
			end if;
		end if;
	end process;

	LEDR_o	<= ledr_q;

	--=======================================
	-- Read path : device -> CPU
	--=======================================
	rdata_w(DATA_BUS_WIDTH-1 DOWNTO LEDR_WIDTH)	<= (OTHERS => '0');
	rdata_w(LEDR_WIDTH-1 DOWNTO 0)				<= ledr_q;

	data_rd_o	<= rdata_w WHEN (cs_i = '1' AND MemRead_ctrl_i = '1') ELSE (OTHERS => '0');

END rtl;