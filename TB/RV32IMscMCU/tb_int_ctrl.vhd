---------------------------------------------------------------------------------------------
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- tb_int_ctrl - self checking testbench for the Basic Interrupt Controller
--
-- The stimulus process plays three parts at once: the CPU issuing loads and stores, the
-- address decoder asserting cs_i, and the peripherals emitting interrupt pulses. Source
-- pulses are driven the way GPIO_PB_Interface and basic_timer_interface really produce
-- them - one MCLK period wide, rising just after a rising edge - so they span exactly one
-- falling edge, which is where the controller samples.
--
-- Expected values are built from the register maps and the vector table of page 14, not
-- from the DUT, so a wrong constant shows up as a mismatch instead of being mirrored on
-- both sides.
--
-- Checks:
--    1. reset clears IE, IFG and TYPE, and leaves INTR and bus_drive_o low
--    2. IE is read/write, six bits wide, bits 7:4 read as zero
--    3. a source pulse latches even while its IE bit is clear, and stays latched
--    4. IFG reads as irq AND IE - the flag appears only once IE is set
--    5. INTR = GIE AND OR(IFG): low when GIE is low, low when IE is clear
--    6. TYPE encodes the vector table, and is read only
--    7. priority order over every adjacent pair and over all sources together
--    8. write one to clear: a store clears only the bits written as one
--    9. a store of zero to IFG clears nothing
--   10. SET beats CLEAR in the same cycle - an event on the clearing cycle survives
--   11. protocol cycle 1: bus_drive_o rises and TYPE appears with cs_i low
--   12. protocol cycle 2: BTIFG clears automatically, KEYnIFG does not
--   13. the source served is the one captured in cycle 1, not the one pending in cycle 2
--   14. 0x202F reads zero, a load with MemRead low returns zero
--   15. a store with cs_i low, or with cs_i unknown, is ignored
--   16. asynchronous reset mid operation clears everything, and operation resumes
--
-- Run:  vcom INT_CTRL.vhd tb_int_ctrl.vhd
--       vsim -voptargs=+acc work.tb_int_ctrl
--       run -all
---------------------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY tb_int_ctrl IS
END tb_int_ctrl;
---------------------------------------------------------------------------------------------
ARCHITECTURE sim OF tb_int_ctrl IS

	CONSTANT DATA_BUS_WIDTH	: integer := 32;
	CONSTANT NSRC			: integer := 6;

	CONSTANT CLK_PERIOD		: time := 40 ns;	-- 25 MHz MCLK
	CONSTANT CLK_HALF		: time := CLK_PERIOD/2;
	CONSTANT HOLD			: time :=  2 ns;
	CONSTANT SETTLE			: time :=  1 ns;	-- offset after an edge, when stimulus changes

	--Source indices, matching the IFG register map of page 14
	CONSTANT RX				: integer := 0;
	CONSTANT TX				: integer := 1;
	CONSTANT BT				: integer := 2;
	CONSTANT KEY1			: integer := 3;
	CONSTANT KEY2			: integer := 4;
	CONSTANT KEY3			: integer := 5;

	--Register selects inside the 0x202C block
	CONSTANT A_IE			: STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";
	CONSTANT A_IFG			: STD_LOGIC_VECTOR(1 DOWNTO 0) := "01";
	CONSTANT A_TYPE			: STD_LOGIC_VECTOR(1 DOWNTO 0) := "10";
	CONSTANT A_NONE			: STD_LOGIC_VECTOR(1 DOWNTO 0) := "11";	-- 0x202F, unnamed

	--Vector table, page 14
	CONSTANT T_IDLE			: STD_LOGIC_VECTOR(7 DOWNTO 0) := x"00";
	CONSTANT T_RX			: STD_LOGIC_VECTOR(7 DOWNTO 0) := x"08";
	CONSTANT T_TX			: STD_LOGIC_VECTOR(7 DOWNTO 0) := x"0C";
	CONSTANT T_BT			: STD_LOGIC_VECTOR(7 DOWNTO 0) := x"10";
	CONSTANT T_KEY1			: STD_LOGIC_VECTOR(7 DOWNTO 0) := x"14";
	CONSTANT T_KEY2			: STD_LOGIC_VECTOR(7 DOWNTO 0) := x"18";
	CONSTANT T_KEY3			: STD_LOGIC_VECTOR(7 DOWNTO 0) := x"1C";

	CONSTANT ZERO_BUS		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0) := (OTHERS => '0');

	--DUT connections
	SIGNAL clk_w			: STD_LOGIC := '0';
	SIGNAL rst_w			: STD_LOGIC := '1';

	SIGNAL cs_w				: STD_LOGIC := '0';
	SIGNAL addr_w			: STD_LOGIC_VECTOR(1 DOWNTO 0) := A_IE;
	SIGNAL memrd_w			: STD_LOGIC := '0';
	SIGNAL memwr_w			: STD_LOGIC := '0';
	SIGNAL data_wr_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0) := (OTHERS => '0');

	--The six sources as one vector, split out in the port map
	SIGNAL src_w			: STD_LOGIC_VECTOR(NSRC-1 DOWNTO 0) := (OTHERS => '0');

	SIGNAL gie_w			: STD_LOGIC := '0';
	SIGNAL inta_n_w			: STD_LOGIC := '1';	-- ACTIVE LOW, idle high

	SIGNAL data_rd_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL bus_drive_w		: STD_LOGIC;
	SIGNAL intr_w			: STD_LOGIC;

	SIGNAL done_w			: BOOLEAN := FALSE;

	--Zero extend a byte register to the bus
	FUNCTION zext(v : STD_LOGIC_VECTOR(7 DOWNTO 0))
		RETURN STD_LOGIC_VECTOR IS
		VARIABLE r : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0) := (OTHERS => '0');
	BEGIN
		r(7 DOWNTO 0) := v;
		RETURN r;
	END FUNCTION;

	--A byte with a single bit set, for building IE values and clear masks
	FUNCTION bit_of(i : integer) RETURN STD_LOGIC_VECTOR IS
		VARIABLE r : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
	BEGIN
		r(i) := '1';
		RETURN r;
	END FUNCTION;

BEGIN

	--=======================================
	-- DUT
	--=======================================
	DUT: entity work.int_ctrl
	generic map(
		DATA_BUS_WIDTH	=> DATA_BUS_WIDTH
	)
	PORT MAP (
		clk_i			=> clk_w,
		rst_i			=> rst_w,
		cs_i			=> cs_w,
		addr_i			=> addr_w,
		MemRead_ctrl_i	=> memrd_w,
		MemWrite_ctrl_i	=> memwr_w,
		data_wr_i		=> data_wr_w,
		is_rx_i			=> src_w(RX),
		is_tx_i			=> src_w(TX),
		is_bt_i			=> src_w(BT),
		is_key1_i		=> src_w(KEY1),
		is_key2_i		=> src_w(KEY2),
		is_key3_i		=> src_w(KEY3),
		gie_i			=> gie_w,
		inta_n_i		=> inta_n_w,
		data_rd_o		=> data_rd_w,
		bus_drive_o		=> bus_drive_w,
		intr_o			=> intr_w
	);

	--=======================================
	-- Clock
	--=======================================
	CLKGEN:
	process
	begin
		while not done_w loop
			clk_w <= '0';
			wait for CLK_HALF;
			clk_w <= '1';
			wait for CLK_HALF;
		end loop;
		wait;
	end process;

	--=======================================
	-- Stimulus and checking
	--=======================================
	STIM:
	process
		VARIABLE errors_v	: natural := 0;
		VARIABLE checks_v	: natural := 0;

		--- reporting -------------------------------------------------------
		procedure check(cond : boolean; msg : string) is
		begin
			checks_v := checks_v + 1;
			if not cond then
				errors_v := errors_v + 1;
				report "FAIL: " & msg severity error;
			end if;
		end procedure;

		procedure check_vec(got : STD_LOGIC_VECTOR;
							exp : STD_LOGIC_VECTOR;
							msg : string) is
		begin
			checks_v := checks_v + 1;
			if got /= exp then
				errors_v := errors_v + 1;
				report "FAIL: " & msg severity error;
			end if;
		end procedure;

		procedure check_bit(got : STD_LOGIC; exp : STD_LOGIC; msg : string) is
		begin
			checks_v := checks_v + 1;
			if got /= exp then
				errors_v := errors_v + 1;
				report "FAIL: " & msg severity error;
			end if;
		end procedure;

		--- bus plumbing ----------------------------------------------------
		procedure idle is
		begin
			cs_w		<= '0';
			memrd_w		<= '0';
			memwr_w		<= '0';
			data_wr_w	<= (OTHERS => '0');
		end procedure;

		-- One CPU store: set up just after a rising edge, captured on the falling one.
		procedure bus_write(a : STD_LOGIC_VECTOR(1 DOWNTO 0);
							d : STD_LOGIC_VECTOR(7 DOWNTO 0)) is
		begin
			wait until rising_edge(clk_w);
			wait for SETTLE;
			cs_w		<= '1';
			addr_w		<= a;
			memwr_w		<= '1';
			memrd_w		<= '0';
			data_wr_w	<= zext(d);
			wait until falling_edge(clk_w);
			wait for HOLD;
			idle;
		end procedure;

		-- The read path is combinational, so no edge is needed.
		procedure bus_read(a   : STD_LOGIC_VECTOR(1 DOWNTO 0);
						   exp : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
						   msg : string) is
		begin
			cs_w	<= '1';
			addr_w	<= a;
			memrd_w	<= '1';
			memwr_w	<= '0';
			wait for HOLD;
			check_vec(data_rd_w, exp, msg);
			check_bit(bus_drive_w, '1', msg & " - bus_drive_o must be high on a load");
			idle;
			wait for HOLD;
		end procedure;

		--- interrupt sources -----------------------------------------------
		-- One MCLK period wide, rising just after a rising edge, exactly as
		-- GPIO_PB_Interface and basic_timer_interface produce their pulses. It
		-- therefore spans one falling edge, where the controller samples it.
		procedure pulse(i : integer) is
		begin
			wait until rising_edge(clk_w);
			wait for SETTLE;
			src_w(i) <= '1';
			wait until rising_edge(clk_w);
			wait for SETTLE;
			src_w(i) <= '0';
		end procedure;

		-- Two sources firing on the same cycle
		procedure pulse2(i, j : integer) is
		begin
			wait until rising_edge(clk_w);
			wait for SETTLE;
			src_w(i) <= '1';
			src_w(j) <= '1';
			wait until rising_edge(clk_w);
			wait for SETTLE;
			src_w(i) <= '0';
			src_w(j) <= '0';
		end procedure;

		--- the service protocol of page 15 ---------------------------------
		-- Cycle 1 is the cycle in which INTA is low: the controller captures the
		-- source it commits to and puts TYPE on the data bus without being
		-- addressed. Cycle 2 is the cycle after INTA has gone back high, where the
		-- flag of a synchronous source is cleared.
		procedure service(exp_type : STD_LOGIC_VECTOR(7 DOWNTO 0); msg : string) is
		begin
			-- cycle 1
			wait until rising_edge(clk_w);
			wait for SETTLE;
			inta_n_w <= '0';
			idle;						-- no address on the bus, cs_i stays low
			wait for HOLD;
			check_bit(bus_drive_w, '1', msg & " - bus_drive_o must rise in cycle 1");
			check_vec(data_rd_w, zext(exp_type),
					  msg & " - TYPE must be on the data bus in cycle 1 with cs_i low");
			wait until falling_edge(clk_w);
			wait for HOLD;
			-- cycle 2
			wait until rising_edge(clk_w);
			wait for SETTLE;
			inta_n_w <= '1';
			wait until falling_edge(clk_w);
			wait for HOLD;
			check_bit(bus_drive_w, '0', msg & " - bus_drive_o must fall again after cycle 1");
		end procedure;

	begin
		report "=== tb_int_ctrl start ===" severity note;

		--===============================================================
		-- T1  Reset
		--===============================================================
		rst_w	<= '1';
		gie_w	<= '0';
		wait for 2*CLK_PERIOD;

		check_bit(intr_w,      '0', "T1 INTR must be low after reset");
		check_bit(bus_drive_w, '0', "T1 bus_drive_o must be low after reset");
		bus_read(A_IE,   ZERO_BUS, "T1 IE reads zero after reset");
		bus_read(A_IFG,  ZERO_BUS, "T1 IFG reads zero after reset");
		bus_read(A_TYPE, ZERO_BUS, "T1 TYPE reads 00h after reset");

		wait until rising_edge(clk_w);
		rst_w <= '0';
		wait for HOLD;

		--===============================================================
		-- T2  IE is a read/write six bit register
		--===============================================================
		bus_write(A_IE, x"3F");
		bus_read(A_IE, zext(x"3F"), "T2 IE reads back 3F");

		bus_write(A_IE, x"FF");
		bus_read(A_IE, zext(x"3F"), "T2 IE bits 7:6 must read as zero");

		bus_write(A_IE, x"00");
		bus_read(A_IE, ZERO_BUS, "T2 IE cleared");

		--===============================================================
		-- T3/T4  A flag latches with IE clear, and appears when IE is set
		--===============================================================
		-- The event is latched in the irq flip-flop whatever IE says; IE only
		-- decides whether it is visible in IFG. This is the masking reading of
		-- the figure, and it is the behaviour most likely to surprise someone
		-- reading the register, so it is checked directly.
		pulse(KEY1);
		wait for HOLD;
		bus_read(A_IFG,  ZERO_BUS, "T4 IFG hides a flag whose IE bit is clear");
		bus_read(A_TYPE, ZERO_BUS, "T4 TYPE stays 00h while the flag is masked");
		check_bit(intr_w, '0', "T5 INTR must stay low while the flag is masked");

		bus_write(A_IE, bit_of(KEY1));
		wait for HOLD;
		bus_read(A_IFG, zext(bit_of(KEY1)), "T4 the flag appears once IE is set");
		bus_read(A_TYPE, zext(T_KEY1),      "T6 TYPE encodes KEY1 as 14h");

		--===============================================================
		-- T5  INTR is the OR of IFG gated by GIE
		--===============================================================
		check_bit(intr_w, '0', "T5 INTR low while GIE is low");
		gie_w <= '1';
		wait for HOLD;
		check_bit(intr_w, '1', "T5 INTR high with a flag pending and GIE set");
		gie_w <= '0';
		wait for HOLD;
		check_bit(intr_w, '0', "T5 INTR falls again when GIE is cleared");

		--===============================================================
		-- T8/T9  Write one to clear
		--===============================================================
		bus_write(A_IFG, x"00");
		bus_read(A_IFG, zext(bit_of(KEY1)), "T9 a store of zero to IFG clears nothing");

		bus_write(A_IFG, bit_of(KEY2));
		bus_read(A_IFG, zext(bit_of(KEY1)),
				 "T8 clearing a bit that is not set leaves the others alone");

		bus_write(A_IFG, bit_of(KEY1));
		bus_read(A_IFG, ZERO_BUS,  "T8 storing one to a bit clears that flag");
		bus_read(A_TYPE, ZERO_BUS, "T8 TYPE returns to 00h once nothing is pending");

		--===============================================================
		-- T7  Priority, over every source and every adjacent pair
		--===============================================================
		bus_write(A_IE, x"3F");			-- enable all six

		-- each source alone
		pulse(KEY3);  wait for HOLD;
		bus_read(A_TYPE, zext(T_KEY3), "T7 KEY3 alone gives 1Ch");
		bus_write(A_IFG, bit_of(KEY3));

		pulse(KEY2);  wait for HOLD;
		bus_read(A_TYPE, zext(T_KEY2), "T7 KEY2 alone gives 18h");
		bus_write(A_IFG, bit_of(KEY2));

		pulse(KEY1);  wait for HOLD;
		bus_read(A_TYPE, zext(T_KEY1), "T7 KEY1 alone gives 14h");
		bus_write(A_IFG, bit_of(KEY1));

		pulse(BT);    wait for HOLD;
		bus_read(A_TYPE, zext(T_BT),   "T7 BT alone gives 10h");
		bus_write(A_IFG, bit_of(BT));

		pulse(TX);    wait for HOLD;
		bus_read(A_TYPE, zext(T_TX),   "T7 TX alone gives 0Ch");
		bus_write(A_IFG, bit_of(TX));

		pulse(RX);    wait for HOLD;
		bus_read(A_TYPE, zext(T_RX),   "T7 RX alone gives 08h");
		bus_write(A_IFG, bit_of(RX));

		-- adjacent pairs: the lower TYPE always wins
		pulse2(KEY2, KEY3); wait for HOLD;
		bus_read(A_TYPE, zext(T_KEY2), "T7 KEY2 beats KEY3");
		bus_write(A_IFG, x"30");

		pulse2(KEY1, KEY2); wait for HOLD;
		bus_read(A_TYPE, zext(T_KEY1), "T7 KEY1 beats KEY2");
		bus_write(A_IFG, x"18");

		pulse2(BT, KEY1);   wait for HOLD;
		bus_read(A_TYPE, zext(T_BT),   "T7 BT beats KEY1");
		bus_write(A_IFG, x"0C");

		pulse2(TX, BT);     wait for HOLD;
		bus_read(A_TYPE, zext(T_TX),   "T7 TX beats BT");
		bus_write(A_IFG, x"06");

		pulse2(RX, TX);     wait for HOLD;
		bus_read(A_TYPE, zext(T_RX),   "T7 RX beats TX");
		bus_write(A_IFG, x"03");

		-- non adjacent, and everything at once
		pulse2(BT, KEY3);   wait for HOLD;
		bus_read(A_TYPE, zext(T_BT),   "T7 BT beats KEY3");
		bus_write(A_IFG, x"24");

		-- All six at once. Driven inline rather than through pulse/pulse2 because those
		-- take one or two sources; the leading wait is what makes the high window span a
		-- falling edge, which is where the controller samples.
		wait until rising_edge(clk_w);
		wait for SETTLE;
		for i in 0 to NSRC-1 loop
			src_w(i) <= '1';
		end loop;
		wait until rising_edge(clk_w);
		wait for SETTLE;
		for i in 0 to NSRC-1 loop
			src_w(i) <= '0';
		end loop;
		wait for HOLD;
		bus_read(A_IFG,  zext(x"3F"),  "T7 all six flags latched together");
		bus_read(A_TYPE, zext(T_RX),   "T7 with everything pending, RX wins");
		bus_write(A_IFG, x"3F");
		bus_read(A_IFG, ZERO_BUS, "T7 all flags cleared");

		--===============================================================
		-- T6  TYPE is read only
		--===============================================================
		pulse(BT);  wait for HOLD;
		bus_write(A_TYPE, x"FF");
		bus_read(A_TYPE, zext(T_BT), "T6 a store to TYPE must be ignored");
		bus_read(A_IFG,  zext(bit_of(BT)),
				 "T6 a store to TYPE must not disturb IFG");

		--===============================================================
		-- T11/T12  The service protocol
		--===============================================================
		-- BT is pending and enabled. Cycle 1 must present 10h on the data bus
		-- while cs_i is low; cycle 2 must clear BTIFG on its own, because note a
		-- makes it a synchronous source.
		gie_w <= '1';
		wait for HOLD;
		check_bit(intr_w, '1', "T11 INTR high with BTIFG pending");

		service(T_BT, "T11 service of BTIFG");

		bus_read(A_IFG, ZERO_BUS, "T12 BTIFG clears automatically on service");
		check_bit(intr_w, '0', "T12 INTR falls once the flag is cleared");

		-- A key flag must NOT clear itself: note d says software only. This is the
		-- check that catches the infinite interrupt loop if it is ever broken.
		pulse(KEY2);  wait for HOLD;
		service(T_KEY2, "T12 service of KEY2IFG");
		bus_read(A_IFG, zext(bit_of(KEY2)),
				 "T12 KEY2IFG must survive service - software clears it");
		bus_write(A_IFG, bit_of(KEY2));
		bus_read(A_IFG, ZERO_BUS, "T12 KEY2IFG cleared by software");

		--===============================================================
		-- T13  The source served is the one captured in cycle 1
		--===============================================================
		-- BT is pending when the protocol starts. RX, which outranks it, arrives
		-- between cycle 1 and cycle 2. Cycle 2 must clear BT - the source actually
		-- being serviced - and leave RX pending for the next request.
		pulse(BT);  wait for HOLD;

		wait until rising_edge(clk_w);
		wait for SETTLE;
		inta_n_w <= '0';
		idle;
		wait for HOLD;
		check_vec(data_rd_w, zext(T_BT), "T13 cycle 1 commits to BT");
		wait until falling_edge(clk_w);
		wait for HOLD;

		wait until rising_edge(clk_w);
		wait for SETTLE;
		inta_n_w <= '1';
		src_w(RX) <= '1';				-- a higher priority source arrives now
		wait until falling_edge(clk_w);
		wait for HOLD;
		wait until rising_edge(clk_w);
		wait for SETTLE;
		src_w(RX) <= '0';
		wait for HOLD;

		bus_read(A_IFG, zext(bit_of(RX)),
				 "T13 cycle 2 cleared BT and left the newly arrived RX pending");
		bus_write(A_IFG, bit_of(RX));

		--===============================================================
		-- T10  SET beats CLEAR in the same cycle
		--===============================================================
		-- The event and the clearing store land on the same falling edge. Losing
		-- the event here would drop an interrupt under a race that is almost
		-- impossible to reproduce, so the flag must end up set.
		pulse(KEY1);  wait for HOLD;
		bus_read(A_IFG, zext(bit_of(KEY1)), "T10 KEY1IFG set before the race");

		wait until rising_edge(clk_w);
		wait for SETTLE;
		src_w(KEY1)	<= '1';				-- new event
		cs_w		<= '1';				-- and the clearing store, same cycle
		addr_w		<= A_IFG;
		memwr_w		<= '1';
		data_wr_w	<= zext(bit_of(KEY1));
		wait until falling_edge(clk_w);
		wait for HOLD;
		idle;
		wait until rising_edge(clk_w);
		wait for SETTLE;
		src_w(KEY1) <= '0';
		wait for HOLD;

		bus_read(A_IFG, zext(bit_of(KEY1)),
				 "T10 an event on the clearing cycle must survive");
		bus_write(A_IFG, bit_of(KEY1));
		bus_read(A_IFG, ZERO_BUS, "T10 flag cleared afterwards");

		--===============================================================
		-- T14  Unmapped address, and reads without MemRead
		--===============================================================
		pulse(KEY3);  wait for HOLD;
		bus_read(A_NONE, ZERO_BUS, "T14 0x202F reads zero");

		cs_w	<= '1';
		addr_w	<= A_IFG;
		memrd_w	<= '0';
		wait for HOLD;
		check_vec(data_rd_w, ZERO_BUS, "T14 a load with MemRead low returns zero");
		check_bit(bus_drive_w, '0', "T14 bus_drive_o low with MemRead low");
		idle;
		wait for HOLD;

		cs_w	<= '0';
		memrd_w	<= '1';
		wait for HOLD;
		check_vec(data_rd_w, ZERO_BUS, "T14 a load with cs_i low returns zero");
		check_bit(bus_drive_w, '0', "T14 bus_drive_o low with cs_i low");
		idle;
		wait for HOLD;

		--===============================================================
		-- T15  Stores that must be ignored
		--===============================================================
		-- KEY3IFG is still set from T14. None of the following may clear it.
		wait until rising_edge(clk_w);
		wait for SETTLE;
		cs_w		<= '0';				-- no chip select
		addr_w		<= A_IFG;
		memwr_w		<= '1';
		data_wr_w	<= zext(x"3F");
		wait until falling_edge(clk_w);
		wait for HOLD;
		idle;
		wait for HOLD;
		bus_read(A_IFG, zext(bit_of(KEY3)), "T15 a store with cs_i low is ignored");

		wait until rising_edge(clk_w);
		wait for SETTLE;
		cs_w		<= 'X';				-- unknown chip select is not '1'
		addr_w		<= A_IFG;
		memwr_w		<= '1';
		data_wr_w	<= zext(x"3F");
		wait until falling_edge(clk_w);
		wait for HOLD;
		idle;
		wait for HOLD;
		bus_read(A_IFG, zext(bit_of(KEY3)), "T15 a store with cs_i = 'X' is ignored");

		cs_w	<= 'X';
		memrd_w	<= '1';
		wait for HOLD;
		check_vec(data_rd_w, ZERO_BUS, "T15 cs_i = 'X' must not drive the bus");
		idle;
		wait for HOLD;

		--===============================================================
		-- T16  Asynchronous reset, then resume
		--===============================================================
		wait until rising_edge(clk_w);
		wait for CLK_HALF/4;			-- nowhere near an active edge
		rst_w <= '1';
		wait for HOLD;
		check_bit(intr_w, '0', "T16 INTR clears immediately on reset");
		bus_read(A_IE,   ZERO_BUS, "T16 IE clears on reset");
		bus_read(A_IFG,  ZERO_BUS, "T16 IFG clears on reset");
		bus_read(A_TYPE, ZERO_BUS, "T16 TYPE returns to 00h on reset");
		rst_w <= '0';
		wait until rising_edge(clk_w);
		wait for HOLD;

		bus_write(A_IE, bit_of(BT));
		pulse(BT);
		wait for HOLD;
		bus_read(A_IFG,  zext(bit_of(BT)), "T16 flags work again after reset");
		bus_read(A_TYPE, zext(T_BT),       "T16 TYPE works again after reset");
		check_bit(intr_w, '1', "T16 INTR works again after reset");

		--===============================================================
		report "==================================================" severity note;
		report "checks run : " & integer'image(checks_v) severity note;
		report "failures   : " & integer'image(errors_v) severity note;
		if errors_v = 0 then
			report "ALL int_ctrl TESTS PASSED" severity note;
		else
			report "int_ctrl : THERE ARE FAILURES" severity failure;
		end if;
		report "==================================================" severity note;

		done_w <= TRUE;
		wait;
	end process;

END sim;