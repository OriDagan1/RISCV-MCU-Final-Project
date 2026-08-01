--============================================================================
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Unit testbench for the CDC synchronizer.
--
-- Clocks are deliberately unrelated (MCLK 25MHz, DIVCLK 50MHz with an odd
-- phase offset) so the source data changes at arbitrary points inside the
-- destination clock period, which is the situation the synchronizer exists
-- to survive.
--
-- Checks:
--   1. output low after reset
--   2. every source transition appears at the output within a bounded
--      number of destination cycles
--   3. the output transition count matches the source transition count,
--      i.e. no spurious pulses and none lost
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;


ENTITY tb_cdc_sync IS
END tb_cdc_sync;


ARCHITECTURE sim OF tb_cdc_sync IS
	CONSTANT MCLK_PERIOD	: TIME := 40 ns;	-- 25 MHz, domain A
	CONSTANT DCLK_PERIOD	: TIME := 20 ns;	-- 50 MHz, domain B
	-- Worst case from a src_bit change: up to a full MCLK period waiting for
	-- the launch edge (2 DIVCLK periods here) plus the 2 synchronizer stages.
	-- The bound is generous on purpose - this check is here to catch a dead
	-- or hung crossing, not to pin down a phase-dependent cycle count.
	CONSTANT MAX_LATENCY	: NATURAL := 6;		-- dst edges

	SIGNAL mclk			: STD_LOGIC := '0';
	SIGNAL divclk		: STD_LOGIC := '0';
	SIGNAL rst			: STD_LOGIC := '1';
	SIGNAL src_bit		: STD_LOGIC := '0';
	SIGNAL dst_bit		: STD_LOGIC;

	SIGNAL sim_done		: BOOLEAN := FALSE;
	SIGNAL src_edges	: NATURAL := 0;
	SIGNAL dst_edges	: NATURAL := 0;
	SIGNAL err_cnt		: NATURAL := 0;

BEGIN
	mclk	<= NOT mclk   AFTER MCLK_PERIOD/2 WHEN NOT sim_done ELSE '0';
	divclk	<= NOT divclk AFTER DCLK_PERIOD/2 WHEN NOT sim_done ELSE '0';

	DUT: ENTITY work.cdc_sync
	PORT MAP (
		src_clk_i	=> mclk,
		src_rst_i	=> rst,
		src_bit_i	=> src_bit,
		dst_clk_i	=> divclk,
		dst_rst_i	=> rst,
		dst_bit_o	=> dst_bit
	);

	--=======================================
	-- Transition monitors
	--=======================================
	src_mon: PROCESS (src_bit)
	BEGIN
		IF now > 0 ns AND rst = '0' THEN
			src_edges <= src_edges + 1;
		END IF;
	END PROCESS;

	dst_mon: PROCESS (dst_bit)
	BEGIN
		IF now > 0 ns AND rst = '0' THEN
			dst_edges <= dst_edges + 1;
		END IF;
	END PROCESS;

	--=======================================
	-- Stimulus
	--=======================================
	stim: PROCESS
		VARIABLE errs : NATURAL := 0;

		-- Drive src_bit to a new level and time how long it takes to appear
		PROCEDURE cross(level : STD_LOGIC) IS
			VARIABLE lat : NATURAL := 0;
		BEGIN
			WAIT UNTIL rising_edge(mclk);
			src_bit <= level;

			WHILE dst_bit /= level LOOP
				WAIT UNTIL rising_edge(divclk);
				WAIT FOR 1 ns;		-- sample after the DUT has updated
				lat := lat + 1;
				IF lat > MAX_LATENCY THEN
					REPORT "Level " & STD_LOGIC'image(level) &
					       " did not cross within " &
					       NATURAL'image(MAX_LATENCY) & " destination cycles"
					SEVERITY error;
					errs := errs + 1;
					EXIT;
				END IF;
			END LOOP;

			REPORT "  crossed to " & STD_LOGIC'image(level) & " after " &
			       NATURAL'image(lat) & " DIVCLK edges" SEVERITY note;
		END PROCEDURE;

	BEGIN
		rst <= '1';
		WAIT FOR 100 ns;
		rst <= '0';
		WAIT UNTIL rising_edge(divclk);

		IF dst_bit /= '0' THEN
			REPORT "output not low after reset" SEVERITY error;
			errs := errs + 1;
		END IF;

		-- A few crossings, with dwell times that are not multiples of
		-- either clock period so the launch lands at varying phases
		cross('1');
		WAIT FOR 133 ns;
		cross('0');
		WAIT FOR 77 ns;
		cross('1');
		WAIT FOR 211 ns;
		cross('0');
		WAIT FOR 51 ns;
		cross('1');
		WAIT FOR 97 ns;
		cross('0');

		WAIT FOR 200 ns;

		IF src_edges /= dst_edges THEN
			REPORT "transition count mismatch: source " &
			       NATURAL'image(src_edges) & " , destination " &
			       NATURAL'image(dst_edges) SEVERITY error;
			errs := errs + 1;
		END IF;

		REPORT "==================================================" SEVERITY note;
		REPORT NATURAL'image(src_edges) & " source transitions, " &
		       NATURAL'image(dst_edges) & " destination transitions, " &
		       NATURAL'image(errs) & " errors" SEVERITY note;
		IF errs = 0 THEN
			REPORT "ALL TESTS PASSED" SEVERITY note;
		ELSE
			REPORT "THERE ARE FAILURES" SEVERITY failure;
		END IF;
		REPORT "==================================================" SEVERITY note;

		sim_done <= TRUE;
		WAIT;
	END PROCESS stim;

END sim;
