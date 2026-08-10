--------------------------------------------------------------------------------
-- Testbench for GPIO_LEDR_Interface
--------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Self checking testbench for GPIO_LEDR_Interface (PORT_LEDR, 0x2000)
--
-- What is verified:
--   T1  asynchronous reset clears the port register and LEDR_o
--   T2  a selected store captures data_wr_i[7:0] on the FALLING edge, and only there
--   T3  the upper bus bits are ignored (an 8-bit port on a 32-bit bus)
--   T4  a store with cs_i='0' is ignored (device not addressed)
--   T5  a store with MemWrite_ctrl_i='0' is ignored (wrong bus cycle)
--   T6  a selected load returns the port value zero extended to the full bus width
--   T7  data_rd_o is all zeros whenever the device is not selected, so the I/O
--       read paths of the eight peripherals may be OR-ed together
--   T8  the read path is combinational - no clock edge is needed to see the value
--   T9  asynchronous reset asserted in mid cycle takes effect immediately
--   T10 back to back stores on consecutive cycles, as the CPU issues them
--
-- Run:  vsim -c work.tb_GPIO_LEDR_Interface -do "run -all; quit"
--       The simulation ends by itself and reports PASS or the failure count.
---------------------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
 
ENTITY tb_GPIO_LEDR_Interface IS
END tb_GPIO_LEDR_Interface;
---------------------------------------------------------------------------------------------
ARCHITECTURE sim OF tb_GPIO_LEDR_Interface IS
 
	constant DATA_BUS_WIDTH	: integer := 32;
	constant LEDR_WIDTH		: integer := 8;
 
	constant CLK_PERIOD		: time := 20 ns;	-- 50 MHz, as the board clock
	constant HOLD			: time :=  2 ns;	-- settle time after an active edge
 
	--DUT connections
	SIGNAL clk_w			: STD_LOGIC := '0';
	SIGNAL rst_w			: STD_LOGIC := '1';
	SIGNAL cs_w				: STD_LOGIC := '0';
	SIGNAL MemRead_w		: STD_LOGIC := '0';
	SIGNAL MemWrite_w		: STD_LOGIC := '0';
	SIGNAL data_wr_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL data_rd_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL LEDR_w			: STD_LOGIC_VECTOR(LEDR_WIDTH-1 DOWNTO 0);
 
	SIGNAL sim_done_w		: BOOLEAN := FALSE;
 
	--Convenience: an all zero bus value
	constant ZERO_BUS		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0) := (OTHERS => '0');
 
BEGIN
 
	--=======================================
	-- DUT
	--=======================================
	DUT: entity work.GPIO_LEDR_Interface
	generic map(
		DATA_BUS_WIDTH		=> DATA_BUS_WIDTH,
		LEDR_WIDTH			=> LEDR_WIDTH
	)
	PORT MAP(
		clk_i				=> clk_w,
		rst_i				=> rst_w,
		cs_i				=> cs_w,
		MemRead_ctrl_i		=> MemRead_w,
		MemWrite_ctrl_i		=> MemWrite_w,
		data_wr_i			=> data_wr_w,
		data_rd_o			=> data_rd_w,
		LEDR_o				=> LEDR_w
	);
 
	--=======================================
	-- Clock
	--=======================================
	CLKGEN:
	process
	begin
		while not sim_done_w loop
			clk_w <= '0';
			wait for CLK_PERIOD/2;
			clk_w <= '1';
			wait for CLK_PERIOD/2;
		end loop;
		wait;
	end process;
 
	--=======================================
	-- Stimulus and checking
	--=======================================
	STIM:
	process
		variable errors_v	: integer := 0;
		variable checks_v	: integer := 0;
 
		--Report a mismatch on the LED port
		procedure check_leds(constant expected : in STD_LOGIC_VECTOR(LEDR_WIDTH-1 DOWNTO 0);
							 constant tag      : in string) is
		begin
			checks_v := checks_v + 1;
			if LEDR_w /= expected then
				errors_v := errors_v + 1;
				report tag & " : LEDR_o mismatch" severity error;
			end if;
		end procedure;
 
		--Report a mismatch on the read bus
		procedure check_rd(constant expected : in STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
						   constant tag      : in string) is
		begin
			checks_v := checks_v + 1;
			if data_rd_w /= expected then
				errors_v := errors_v + 1;
				report tag & " : data_rd_o mismatch" severity error;
			end if;
		end procedure;
 
		--One CPU store cycle. Control and data are set up just after the rising
		--edge, exactly as the single cycle core presents them, and are held
		--across the falling edge where the device captures.
		procedure bus_store(constant value : in STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
							constant sel   : in STD_LOGIC;
							constant wr    : in STD_LOGIC) is
		begin
			wait until rising_edge(clk_w);
			cs_w		<= sel;
			MemWrite_w	<= wr;
			MemRead_w	<= '0';
			data_wr_w	<= value;
			wait until falling_edge(clk_w);
			wait for HOLD;
		end procedure;
 
		--Release the bus after a cycle
		procedure bus_idle is
		begin
			wait until rising_edge(clk_w);
			cs_w		<= '0';
			MemWrite_w	<= '0';
			MemRead_w	<= '0';
			data_wr_w	<= (OTHERS => '0');
			wait for HOLD;
		end procedure;
 
		--Zero extend an 8-bit port value to the bus width
		function zext(constant v : STD_LOGIC_VECTOR(LEDR_WIDTH-1 DOWNTO 0))
			return STD_LOGIC_VECTOR is
			variable r : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0) := (OTHERS => '0');
		begin
			r(LEDR_WIDTH-1 DOWNTO 0) := v;
			return r;
		end function;
 
	begin
		---------------------------------------------------------------
		-- T1 : reset
		---------------------------------------------------------------
		rst_w <= '1';
		wait for 2*CLK_PERIOD;
		check_leds(x"00", "T1 reset");
		wait until rising_edge(clk_w);
		rst_w <= '0';
		wait for HOLD;
 
		---------------------------------------------------------------
		-- T2 : a selected store is captured, and only on the falling edge
		---------------------------------------------------------------
		wait until rising_edge(clk_w);
		cs_w		<= '1';
		MemWrite_w	<= '1';
		MemRead_w	<= '0';
		data_wr_w	<= x"000000A5";
		wait for HOLD;
		--still before the capture edge, the port must hold its old value
		check_leds(x"00", "T2 no early capture");
		wait until falling_edge(clk_w);
		wait for HOLD;
		check_leds(x"A5", "T2 capture on falling edge");
		bus_idle;
		check_leds(x"A5", "T2 value retained after the cycle");
 
		---------------------------------------------------------------
		-- T3 : the upper 24 bus bits are ignored
		---------------------------------------------------------------
		bus_store(x"FFFFFF3C", '1', '1');
		check_leds(x"3C", "T3 upper bus bits ignored");
		bus_idle;
 
		---------------------------------------------------------------
		-- T4 : not addressed, the store must be ignored
		---------------------------------------------------------------
		bus_store(x"0000005A", '0', '1');
		check_leds(x"3C", "T4 store ignored when cs_i=0");
		bus_idle;
 
		---------------------------------------------------------------
		-- T5 : addressed but not a store cycle
		---------------------------------------------------------------
		bus_store(x"00000077", '1', '0');
		check_leds(x"3C", "T5 store ignored when MemWrite_ctrl_i=0");
		bus_idle;
 
		---------------------------------------------------------------
		-- T6 : a selected load returns the port value, zero extended
		---------------------------------------------------------------
		wait until rising_edge(clk_w);
		cs_w		<= '1';
		MemRead_w	<= '1';
		MemWrite_w	<= '0';
		wait for HOLD;
		check_rd(zext(x"3C"), "T6 load returns the port value");
		--and the load must not disturb the port itself
		wait until falling_edge(clk_w);
		wait for HOLD;
		check_leds(x"3C", "T6 load does not modify the port");
		bus_idle;
 
		---------------------------------------------------------------
		-- T7 : not selected, the read path must drive zeros
		---------------------------------------------------------------
		wait until rising_edge(clk_w);
		cs_w		<= '0';
		MemRead_w	<= '1';
		wait for HOLD;
		check_rd(ZERO_BUS, "T7 zeros when cs_i=0");
 
		--selected, but not a load cycle
		wait until rising_edge(clk_w);
		cs_w		<= '1';
		MemRead_w	<= '0';
		wait for HOLD;
		check_rd(ZERO_BUS, "T7 zeros when MemRead_ctrl_i=0");
		bus_idle;
 
		---------------------------------------------------------------
		-- T8 : the read path is combinational, no clock edge involved
		---------------------------------------------------------------
		cs_w		<= '1';
		MemRead_w	<= '1';
		wait for HOLD;
		check_rd(zext(x"3C"), "T8 combinational read");
		cs_w		<= '0';
		MemRead_w	<= '0';
		wait for HOLD;
		check_rd(ZERO_BUS, "T8 combinational deselect");
 
		---------------------------------------------------------------
		-- T9 : asynchronous reset in mid cycle
		---------------------------------------------------------------
		bus_store(x"000000FF", '1', '1');
		check_leds(x"FF", "T9 preload");
		bus_idle;
		wait for CLK_PERIOD/4;			-- deliberately off any clock edge
		rst_w <= '1';
		wait for HOLD;
		check_leds(x"00", "T9 async reset is immediate");
		wait until rising_edge(clk_w);
		rst_w <= '0';
		wait for HOLD;
 
		---------------------------------------------------------------
		-- T10 : back to back stores on consecutive cycles
		---------------------------------------------------------------
		bus_store(x"00000011", '1', '1');
		check_leds(x"11", "T10 first store");
		bus_store(x"00000022", '1', '1');
		check_leds(x"22", "T10 second store");
		bus_store(x"00000044", '1', '1');
		check_leds(x"44", "T10 third store");
		bus_idle;
 
		---------------------------------------------------------------
		-- Summary
		---------------------------------------------------------------
		wait for 2*CLK_PERIOD;
		report "checks executed : " & integer'image(checks_v) severity note;
		if errors_v = 0 then
			report "GPIO_LEDR_Interface : PASS" severity note;
		else
			report "GPIO_LEDR_Interface : FAIL, mismatches = "
				 & integer'image(errors_v) severity failure;
		end if;
 
		sim_done_w <= TRUE;
		wait;
	end process;
 
END sim;
 