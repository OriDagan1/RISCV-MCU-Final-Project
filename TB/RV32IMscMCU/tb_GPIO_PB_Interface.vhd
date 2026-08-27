---------------------------------------------------------------------------------------------
-- Testbench for GPIO_PB_Interface
--
-- Tests:
--  1. Reset / no spurious interrupts
--  2. Memory-mapped read path
--  3. cs_i / MemRead_ctrl_i qualification
--  4. KEY1, KEY2, KEY3 independently
--  5. No interrupt on press   (1 -> 0)
--  6. Interrupt on release    (0 -> 1)
--  7. IRQ pulse is exactly one MCLK cycle
--  8. Interrupt generation is independent of bus access
--  9. Simultaneous key events
-- 10. Held-key behavior
-- 11. Repeated events
-- 12. Reset during operation
--
-- KEY inputs are assumed to already be debounced, as required by the project hardware.
---------------------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY tb_GPIO_PB_Interface IS
END tb_GPIO_PB_Interface;

---------------------------------------------------------------------------------------------

ARCHITECTURE sim OF tb_GPIO_PB_Interface IS

	CONSTANT DATA_BUS_WIDTH	: INTEGER := 32;
	CONSTANT CLK_PERIOD		: TIME := 40 ns;		-- 25 MHz MCLK

	SIGNAL clk_i			: STD_LOGIC := '0';
	SIGNAL rst_i			: STD_LOGIC := '0';

	SIGNAL cs_i				: STD_LOGIC := '0';
	SIGNAL MemRead_ctrl_i	: STD_LOGIC := '0';

	-- KEY3..KEY1
	-- Active-low:
	--   '1' = released
	--   '0' = pressed
	SIGNAL KEY_i			: STD_LOGIC_VECTOR(3 DOWNTO 1) := "111";

	SIGNAL data_rd_o		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

	SIGNAL key1_irq_o		: STD_LOGIC;
	SIGNAL key2_irq_o		: STD_LOGIC;
	SIGNAL key3_irq_o		: STD_LOGIC;

	SIGNAL sim_done			: BOOLEAN := FALSE;


	-----------------------------------------------------------------------------------------
	-- Expected PORT_PB read value
	--
	-- data[3] = KEY3
	-- data[2] = KEY2
	-- data[1] = KEY1
	-- data[0] = 0
	-----------------------------------------------------------------------------------------
	FUNCTION expected_pb(
		keys : STD_LOGIC_VECTOR(3 DOWNTO 1)
	) RETURN STD_LOGIC_VECTOR IS

		VARIABLE result_v : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

	BEGIN

		result_v := (OTHERS => '0');

		result_v(3 DOWNTO 1) := keys;

		RETURN result_v;

	END FUNCTION;


	-----------------------------------------------------------------------------------------
	-- Wait for N rising clock edges.
	--
	-- The extra 1 ns lets registered signals and combinational outputs settle after
	-- the rising edge before assertions are evaluated.
	-----------------------------------------------------------------------------------------
	PROCEDURE wait_rising_edges(
		CONSTANT number_of_edges : IN POSITIVE
	) IS
	BEGIN

		FOR i IN 1 TO number_of_edges LOOP

			WAIT UNTIL rising_edge(clk_i);
			WAIT FOR 1 ns;

		END LOOP;

	END PROCEDURE;


BEGIN

	-----------------------------------------------------------------------------------------
	-- DUT
	-----------------------------------------------------------------------------------------
	DUT:
	ENTITY work.GPIO_PB_Interface
	GENERIC MAP(
		DATA_BUS_WIDTH		=> DATA_BUS_WIDTH
	)
	PORT MAP(
		clk_i				=> clk_i,
		rst_i				=> rst_i,

		cs_i				=> cs_i,
		MemRead_ctrl_i		=> MemRead_ctrl_i,

		KEY_i				=> KEY_i,

		data_rd_o			=> data_rd_o,

		key1_irq_o			=> key1_irq_o,
		key2_irq_o			=> key2_irq_o,
		key3_irq_o			=> key3_irq_o
	);


	-----------------------------------------------------------------------------------------
	-- Clock generation
	-----------------------------------------------------------------------------------------
	clk_i <= NOT clk_i AFTER CLK_PERIOD/2 WHEN NOT sim_done ELSE '0';


	-----------------------------------------------------------------------------------------
	-- Stimulus and self-checking assertions
	-----------------------------------------------------------------------------------------
	STIMULUS:
	PROCESS
	BEGIN

		-------------------------------------------------------------------------------------
		-- Initial state
		-------------------------------------------------------------------------------------
		REPORT "TEST 1: Reset and idle state" SEVERITY NOTE;

		KEY_i			<= "111";	-- all released
		cs_i			<= '0';
		MemRead_ctrl_i	<= '0';

		rst_i <= '1';

		WAIT FOR CLK_PERIOD / 2;

		ASSERT key1_irq_o = '0'
			REPORT "ERROR: KEY1 IRQ active during reset"
			SEVERITY ERROR;

		ASSERT key2_irq_o = '0'
			REPORT "ERROR: KEY2 IRQ active during reset"
			SEVERITY ERROR;

		ASSERT key3_irq_o = '0'
			REPORT "ERROR: KEY3 IRQ active during reset"
			SEVERITY ERROR;

		ASSERT data_rd_o = x"00000000"
			REPORT "ERROR: data_rd_o must be zero when device is not selected"
			SEVERITY ERROR;


		-------------------------------------------------------------------------------------
		-- Read while reset is active.
		-- Internal synchronized key state should be KEY_IDLE = "111".
		-------------------------------------------------------------------------------------
		cs_i			<= '1';
		MemRead_ctrl_i	<= '1';

		WAIT FOR 1 ns;

		ASSERT data_rd_o = x"0000000E"
			REPORT "ERROR: PORT_PB reset/idle read should be 0x0000000E"
			SEVERITY ERROR;


		-------------------------------------------------------------------------------------
		-- Release reset.
		-- Check that resetting registers to "111" prevents false interrupts.
		-------------------------------------------------------------------------------------
		rst_i <= '0';

		wait_rising_edges(4);

		ASSERT key1_irq_o = '0' AND
			   key2_irq_o = '0' AND
			   key3_irq_o = '0'
			REPORT "ERROR: Spurious IRQ generated after reset"
			SEVERITY ERROR;


		-------------------------------------------------------------------------------------
		-- TEST 2: Bus qualification
		-------------------------------------------------------------------------------------
		REPORT "TEST 2: Memory-mapped read qualification" SEVERITY NOTE;

		cs_i			<= '0';
		MemRead_ctrl_i	<= '1';

		WAIT FOR 1 ns;

		ASSERT data_rd_o = x"00000000"
			REPORT "ERROR: data_rd_o active while cs_i = 0"
			SEVERITY ERROR;


		cs_i			<= '1';
		MemRead_ctrl_i	<= '0';

		WAIT FOR 1 ns;

		ASSERT data_rd_o = x"00000000"
			REPORT "ERROR: data_rd_o active while MemRead_ctrl_i = 0"
			SEVERITY ERROR;


		cs_i			<= '1';
		MemRead_ctrl_i	<= '1';

		WAIT FOR 1 ns;

		ASSERT data_rd_o = x"0000000E"
			REPORT "ERROR: Idle KEY value read incorrectly"
			SEVERITY ERROR;


		-------------------------------------------------------------------------------------
		-- TEST 3: KEY1 press
		--
		-- Press = 1 -> 0.
		-- Must NOT produce an interrupt.
		-------------------------------------------------------------------------------------
		REPORT "TEST 3: KEY1 press - no interrupt expected" SEVERITY NOTE;

		-- Change asynchronously, away from a clock edge.
		WAIT FOR 7 ns;

		KEY_i(1) <= '0';

		-- First rising edge: key_meta_q sees 0.
		wait_rising_edges(1);

		ASSERT key1_irq_o = '0'
			REPORT "ERROR: KEY1 IRQ generated at synchronizer stage 1"
			SEVERITY ERROR;


		-- Second rising edge: key_sync_q sees 0.
		wait_rising_edges(1);

		ASSERT key1_irq_o = '0'
			REPORT "ERROR: KEY1 press (1->0) incorrectly generated IRQ"
			SEVERITY ERROR;


		-- Third edge updates previous state.
		wait_rising_edges(1);

		ASSERT key1_irq_o = '0'
			REPORT "ERROR: KEY1 IRQ generated while key remains pressed"
			SEVERITY ERROR;


		ASSERT data_rd_o = x"0000000C"
			REPORT "ERROR: KEY1 pressed read value should be 0x0000000C"
			SEVERITY ERROR;


		-------------------------------------------------------------------------------------
		-- TEST 4: Hold KEY1 down
		-------------------------------------------------------------------------------------
		REPORT "TEST 4: Hold KEY1 pressed" SEVERITY NOTE;

		FOR i IN 1 TO 5 LOOP

			wait_rising_edges(1);

			ASSERT key1_irq_o = '0'
				REPORT "ERROR: Repeated KEY1 IRQ while key is held down"
				SEVERITY ERROR;

		END LOOP;


		-------------------------------------------------------------------------------------
		-- TEST 5: KEY1 release
		--
		-- Release = 0 -> 1.
		-- After synchronization, one MCLK-wide IRQ pulse is expected.
		-------------------------------------------------------------------------------------
		REPORT "TEST 5: KEY1 release - one IRQ pulse expected" SEVERITY NOTE;

		WAIT FOR 9 ns;

		KEY_i(1) <= '1';

		-- Stage 1
		wait_rising_edges(1);

		ASSERT key1_irq_o = '0'
			REPORT "ERROR: KEY1 IRQ appeared too early"
			SEVERITY ERROR;


		-- Stage 2: synchronized signal becomes 1.
		-- Previous synchronized value is still 0.
		-- IRQ must now be high.
		wait_rising_edges(1);

		ASSERT key1_irq_o = '1'
			REPORT "ERROR: KEY1 release did not generate IRQ"
			SEVERITY ERROR;

		ASSERT key2_irq_o = '0' AND key3_irq_o = '0'
			REPORT "ERROR: KEY1 release affected another IRQ output"
			SEVERITY ERROR;

		ASSERT data_rd_o = x"0000000E"
			REPORT "ERROR: PORT_PB did not update after KEY1 release"
			SEVERITY ERROR;


		-- One clock later previous catches up.
		wait_rising_edges(1);

		ASSERT key1_irq_o = '0'
			REPORT "ERROR: KEY1 IRQ pulse lasted longer than one MCLK cycle"
			SEVERITY ERROR;


		-------------------------------------------------------------------------------------
		-- TEST 6: IRQ independent of bus read
		-------------------------------------------------------------------------------------
		REPORT "TEST 6: Interrupt generation independent of cs/read" SEVERITY NOTE;

		cs_i			<= '0';
		MemRead_ctrl_i	<= '0';

		-- Press KEY2.
		WAIT FOR 5 ns;
		KEY_i(2) <= '0';

		wait_rising_edges(3);

		ASSERT key2_irq_o = '0'
			REPORT "ERROR: KEY2 press generated IRQ"
			SEVERITY ERROR;


		-- Release KEY2 while CPU is not reading PORT_PB.
		WAIT FOR 6 ns;
		KEY_i(2) <= '1';

		wait_rising_edges(1);

		ASSERT key2_irq_o = '0'
			REPORT "ERROR: KEY2 IRQ appeared too early"
			SEVERITY ERROR;

		wait_rising_edges(1);

		ASSERT key2_irq_o = '1'
			REPORT "ERROR: KEY2 release did not generate IRQ while cs_i/read were disabled"
			SEVERITY ERROR;

		ASSERT data_rd_o = x"00000000"
			REPORT "ERROR: data_rd_o active even though PB port was not selected"
			SEVERITY ERROR;

		wait_rising_edges(1);

		ASSERT key2_irq_o = '0'
			REPORT "ERROR: KEY2 IRQ lasted longer than one cycle"
			SEVERITY ERROR;


		-------------------------------------------------------------------------------------
		-- TEST 7: KEY3 independently
		-------------------------------------------------------------------------------------
		REPORT "TEST 7: KEY3 independent operation" SEVERITY NOTE;

		KEY_i(3) <= '0';

		wait_rising_edges(3);

		ASSERT key3_irq_o = '0'
			REPORT "ERROR: KEY3 press generated IRQ"
			SEVERITY ERROR;

		KEY_i(3) <= '1';

		wait_rising_edges(1);

		ASSERT key3_irq_o = '0'
			REPORT "ERROR: KEY3 IRQ appeared too early"
			SEVERITY ERROR;

		wait_rising_edges(1);

		ASSERT key3_irq_o = '1'
			REPORT "ERROR: KEY3 release did not generate IRQ"
			SEVERITY ERROR;

		ASSERT key1_irq_o = '0' AND key2_irq_o = '0'
			REPORT "ERROR: KEY3 release affected KEY1/KEY2 IRQ"
			SEVERITY ERROR;

		wait_rising_edges(1);

		ASSERT key3_irq_o = '0'
			REPORT "ERROR: KEY3 IRQ lasted longer than one clock"
			SEVERITY ERROR;


		-------------------------------------------------------------------------------------
		-- TEST 8: Simultaneous KEY1 + KEY2 release
		-------------------------------------------------------------------------------------
		REPORT "TEST 8: Simultaneous KEY1 and KEY2 events" SEVERITY NOTE;

		-- Press both.
		KEY_i(1) <= '0';
		KEY_i(2) <= '0';

		wait_rising_edges(3);

		ASSERT key1_irq_o = '0' AND key2_irq_o = '0'
			REPORT "ERROR: Simultaneous press generated IRQ"
			SEVERITY ERROR;


		-- Release both together.
		KEY_i(1) <= '1';
		KEY_i(2) <= '1';

		wait_rising_edges(1);

		ASSERT key1_irq_o = '0' AND key2_irq_o = '0'
			REPORT "ERROR: Simultaneous IRQ appeared before synchronization completed"
			SEVERITY ERROR;

		wait_rising_edges(1);

		ASSERT key1_irq_o = '1' AND key2_irq_o = '1'
			REPORT "ERROR: Simultaneous KEY1+KEY2 release did not generate both IRQ pulses"
			SEVERITY ERROR;

		ASSERT key3_irq_o = '0'
			REPORT "ERROR: KEY3 IRQ unexpectedly active"
			SEVERITY ERROR;

		wait_rising_edges(1);

		ASSERT key1_irq_o = '0' AND
			   key2_irq_o = '0' AND
			   key3_irq_o = '0'
			REPORT "ERROR: Simultaneous IRQ pulse lasted longer than one clock"
			SEVERITY ERROR;


		-------------------------------------------------------------------------------------
		-- TEST 9: Verify all read combinations
		-------------------------------------------------------------------------------------
		REPORT "TEST 9: PORT_PB read combinations" SEVERITY NOTE;

		cs_i			<= '1';
		MemRead_ctrl_i	<= '1';

		-- 000 = all three pressed.
		KEY_i <= "000";

		wait_rising_edges(3);

		ASSERT data_rd_o = x"00000000"
			REPORT "ERROR: KEY=000 read incorrectly"
			SEVERITY ERROR;


		-- 001 -> bit1 only.
		KEY_i <= "001";

		wait_rising_edges(2);

		ASSERT data_rd_o = x"00000002"
			REPORT "ERROR: KEY=001 should read as 0x00000002"
			SEVERITY ERROR;

		wait_rising_edges(1);


		-- 010 -> bit2 only.
		KEY_i <= "010";

		wait_rising_edges(2);

		ASSERT data_rd_o = x"00000004"
			REPORT "ERROR: KEY=010 should read as 0x00000004"
			SEVERITY ERROR;

		wait_rising_edges(1);


		-- 100 -> bit3 only.
		KEY_i <= "100";

		wait_rising_edges(2);

		ASSERT data_rd_o = x"00000008"
			REPORT "ERROR: KEY=100 should read as 0x00000008"
			SEVERITY ERROR;

		wait_rising_edges(1);


		-- 111 = all released.
		KEY_i <= "111";

		wait_rising_edges(2);

		ASSERT data_rd_o = x"0000000E"
			REPORT "ERROR: KEY=111 should read as 0x0000000E"
			SEVERITY ERROR;

		wait_rising_edges(1);


		-------------------------------------------------------------------------------------
		-- TEST 10: Repeated KEY1 events
		--
		-- Verify that two separate press/release operations generate two separate pulses.
		-------------------------------------------------------------------------------------
		REPORT "TEST 10: Repeated KEY1 interrupts" SEVERITY NOTE;

		KEY_i(1) <= '0';

		wait_rising_edges(3);

		KEY_i(1) <= '1';

		wait_rising_edges(2);

		ASSERT key1_irq_o = '1'
			REPORT "ERROR: First repeated KEY1 release did not generate IRQ"
			SEVERITY ERROR;

		wait_rising_edges(1);

		ASSERT key1_irq_o = '0'
			REPORT "ERROR: First repeated KEY1 IRQ did not clear"
			SEVERITY ERROR;


		KEY_i(1) <= '0';

		wait_rising_edges(3);

		KEY_i(1) <= '1';

		wait_rising_edges(2);

		ASSERT key1_irq_o = '1'
			REPORT "ERROR: Second repeated KEY1 release did not generate IRQ"
			SEVERITY ERROR;

		wait_rising_edges(1);

		ASSERT key1_irq_o = '0'
			REPORT "ERROR: Second repeated KEY1 IRQ did not clear"
			SEVERITY ERROR;


		-------------------------------------------------------------------------------------
		-- TEST 11: Reset during operation
		-------------------------------------------------------------------------------------
		REPORT "TEST 11: Reset during operation" SEVERITY NOTE;

		-- Put KEY1 in pressed state and allow it into the synchronizer.
		KEY_i <= "110";

		wait_rising_edges(3);

		ASSERT data_rd_o = x"0000000C"
			REPORT "ERROR: Pre-reset KEY state incorrect"
			SEVERITY ERROR;


		-- Assert asynchronous reset between clock edges.
		WAIT FOR 7 ns;

		rst_i <= '1';

		WAIT FOR 2 ns;

		ASSERT key1_irq_o = '0' AND
			   key2_irq_o = '0' AND
			   key3_irq_o = '0'
			REPORT "ERROR: IRQ active during asynchronous reset"
			SEVERITY ERROR;

		-- Because internal state resets to KEY_IDLE.
		ASSERT data_rd_o = x"0000000E"
			REPORT "ERROR: Internal PB state not reset to KEY_IDLE"
			SEVERITY ERROR;


		-- Return external keys to their real idle state before releasing reset.
		KEY_i <= "111";

		WAIT FOR CLK_PERIOD;

		rst_i <= '0';

		wait_rising_edges(4);

		ASSERT key1_irq_o = '0' AND
			   key2_irq_o = '0' AND
			   key3_irq_o = '0'
			REPORT "ERROR: Spurious interrupt after second reset"
			SEVERITY ERROR;

		ASSERT data_rd_o = x"0000000E"
			REPORT "ERROR: PORT_PB incorrect after reset recovery"
			SEVERITY ERROR;


		-------------------------------------------------------------------------------------
		-- TEST 12: Read controls must not affect interrupt path
		--
		-- Toggle bus controls while an event propagates through synchronization.
		-------------------------------------------------------------------------------------
		REPORT "TEST 12: Bus-control changes during interrupt event" SEVERITY NOTE;

		KEY_i(3) <= '0';

		wait_rising_edges(3);

		cs_i			<= '0';
		MemRead_ctrl_i	<= '0';

		KEY_i(3) <= '1';

		wait_rising_edges(1);

		cs_i			<= '1';
		MemRead_ctrl_i	<= '0';

		wait_rising_edges(1);

		ASSERT key3_irq_o = '1'
			REPORT "ERROR: Bus-control transition interfered with KEY3 IRQ"
			SEVERITY ERROR;

		ASSERT data_rd_o = x"00000000"
			REPORT "ERROR: Read data active with MemRead_ctrl_i = 0"
			SEVERITY ERROR;

		wait_rising_edges(1);

		ASSERT key3_irq_o = '0'
			REPORT "ERROR: KEY3 IRQ did not return low"
			SEVERITY ERROR;


		-------------------------------------------------------------------------------------
		-- End
		-------------------------------------------------------------------------------------
		REPORT "============================================================" SEVERITY NOTE;
		REPORT "ALL GPIO_PB_Interface TESTS PASSED" SEVERITY NOTE;
		REPORT "============================================================" SEVERITY NOTE;

		sim_done <= TRUE;

		WAIT;

	END PROCESS;

END sim;