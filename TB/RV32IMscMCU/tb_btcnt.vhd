--============================================================================
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Unit testbench for the Basic Timer counter and its BTSSEL clock select.
--
-- The two are tested together because BT_CLKDIV exists only to clock BTCNT,
-- so what matters is the rate the count actually advances at, not the shape
-- of BTCLK on its own.
--
-- Fig.7 puts the BTCNT-vs-BTCL0 comparator inside the Output Unit and feeds
-- EQU0 back into the counter. That module is not written yet, so the one line
-- marked GOLDEN below stands in for it. When BT_OUTPUT_UNIT.vhd lands it must
-- produce exactly this, and the numbers checked here must not move.
--
-- BTSSEL is only ever changed here while the timer is stopped, which is the
-- rule stated in BT_CLKDIV.vhd: a combinational mux between two running
-- clocks can emit a runt pulse on the cycle the selection changes.
--
-- Checks:
--   1. BTCNT is zero after reset
--   2. up-mode counts 0..BTCL0 inclusive, so a period is BTCL0+1 BTCLK edges
--   3. BTSSEL = 00/01/10/11 give BTCLK periods of 1x, 2x, 4x and 8x SMCLK
--   4. BTHOLD freezes the count, and releasing it resumes from where it left
--   5. BTCLR zeroes the count, and still does so while BTHOLD is asserted
--   6. shortening BTCL0 under a running counter restarts it instead of
--      letting it run away to 0xFFFFFFFF
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;


ENTITY tb_btcnt IS
END tb_btcnt;


ARCHITECTURE sim OF tb_btcnt IS
	CONSTANT N				: positive	:= 32;
	CONSTANT SMCLK_PERIOD	: TIME		:= 20 ns;	-- 50 MHz

	SIGNAL smclk		: STD_LOGIC := '0';
	SIGNAL rst			: STD_LOGIC := '1';
	SIGNAL sel			: STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";
	SIGNAL btclk		: STD_LOGIC;
	SIGNAL clr			: STD_LOGIC := '0';
	SIGNAL hold			: STD_LOGIC := '0';
	SIGNAL btcl0		: STD_LOGIC_VECTOR(N-1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL cnt			: STD_LOGIC_VECTOR(N-1 DOWNTO 0);
	SIGNAL equ0			: STD_LOGIC;

	SIGNAL sim_done		: BOOLEAN := FALSE;

	-- Readable in the wave window and in report strings
	SIGNAL cnt_int		: NATURAL := 0;

BEGIN
	smclk	<= NOT smclk AFTER SMCLK_PERIOD/2 WHEN NOT sim_done ELSE '0';

	cnt_int	<= to_integer(unsigned(cnt));

	--=======================================
	-- GOLDEN: stands in for the Output Unit comparator.
	--
	-- ">=" and not "=" on purpose, and BT_OUTPUT_UNIT must do the same. BTCL0
	-- is reloaded from BTCMPR0 while the timer runs, so if software shortens
	-- the period the count can already be past the new limit. With "=" the
	-- comparison would miss and the timer would run all the way to
	-- 0xFFFFFFFF before wrapping; with ">=" it restarts on the next edge. In
	-- steady state the count never exceeds BTCL0, so the two are identical -
	-- this only covers the reload case, which is check 6.
	--=======================================
	equ0	<= '1' WHEN unsigned(cnt) >= unsigned(btcl0) ELSE '0';

	--=======================================
	CLKDIV: ENTITY work.bt_clkdiv
	PORT MAP (
		smclk_i	=> smclk,
		rst_i	=> rst,
		sel_i	=> sel,
		btclk_o	=> btclk
	);

	CNTR: ENTITY work.btcnt
	GENERIC MAP (
		N		=> N
	)
	PORT MAP (
		btclk_i	=> btclk,
		rst_i	=> rst,
		clr_i	=> clr,
		hold_i	=> hold,
		equ0_i	=> equ0,
		cnt_o	=> cnt
	);

	--=======================================
	-- Stimulus
	--=======================================
	stim: PROCESS
		VARIABLE errs : NATURAL := 0;

		-- One BTCNT clock, whatever BTSSEL currently selects
		PROCEDURE step(n : NATURAL) IS
		BEGIN
			FOR i IN 1 TO n LOOP
				WAIT UNTIL rising_edge(btclk);
			END LOOP;
			WAIT FOR 1 ns;			-- sample after the DUT has updated
		END PROCEDURE;

		PROCEDURE check(tag : STRING; got : NATURAL; want : NATURAL) IS
		BEGIN
			IF got /= want THEN
				REPORT tag & ": expected " & NATURAL'image(want) &
				       " , got " & NATURAL'image(got) SEVERITY error;
				errs := errs + 1;
			ELSE
				REPORT "  " & tag & " = " & NATURAL'image(got) & " OK"
				SEVERITY note;
			END IF;
		END PROCEDURE;

		-- Time between two consecutive BTCLK rising edges
		PROCEDURE measure_btclk(tag : STRING; want : TIME) IS
			VARIABLE t0 : TIME;
			VARIABLE t1 : TIME;
		BEGIN
			WAIT UNTIL rising_edge(btclk);	t0 := now;
			WAIT UNTIL rising_edge(btclk);	t1 := now;
			IF (t1 - t0) /= want THEN
				REPORT tag & ": expected " & TIME'image(want) &
				       " , got " & TIME'image(t1 - t0) SEVERITY error;
				errs := errs + 1;
			ELSE
				REPORT "  " & tag & " = " & TIME'image(t1 - t0) & " OK"
				SEVERITY note;
			END IF;
		END PROCEDURE;

		-- Park the timer so BTSSEL can be changed safely, then restart it
		PROCEDURE set_btssel(v : STD_LOGIC_VECTOR(1 DOWNTO 0)) IS
		BEGIN
			hold	<= '1';
			WAIT FOR 4 * SMCLK_PERIOD;
			sel		<= v;
			WAIT FOR 4 * SMCLK_PERIOD;
			hold	<= '0';
		END PROCEDURE;

	BEGIN
		--------------------------------------------------
		-- 1. reset
		--------------------------------------------------
		REPORT "--- reset ---" SEVERITY note;
		btcl0	<= STD_LOGIC_VECTOR(to_unsigned(4, N));
		rst		<= '1';
		WAIT FOR 4 * SMCLK_PERIOD;
		check("count after reset", cnt_int, 0);
		-- No wait after releasing reset: the very next BTCLK edge is already
		-- the 0 -> 1 step, so step(1) below must land on it.
		rst		<= '0';

		--------------------------------------------------
		-- 2. up-mode ramp: 0,1,2,3,4,0,...
		--------------------------------------------------
		REPORT "--- up-mode ramp, BTCL0 = 4 ---" SEVERITY note;
		step(1);	check("cnt", cnt_int, 1);
		step(1);	check("cnt", cnt_int, 2);
		step(1);	check("cnt", cnt_int, 3);
		step(1);	check("cnt", cnt_int, 4);
		IF equ0 /= '1' THEN
			REPORT "equ0 not asserted at the top of the ramp" SEVERITY error;
			errs := errs + 1;
		END IF;
		step(1);	check("cnt wraps to", cnt_int, 0);
		IF equ0 /= '0' THEN
			REPORT "equ0 still asserted after the wrap" SEVERITY error;
			errs := errs + 1;
		END IF;

		--------------------------------------------------
		-- 3. BTSSEL selects the BTCLK rate
		--------------------------------------------------
		REPORT "--- BTSSEL clock select ---" SEVERITY note;
		set_btssel("00");	measure_btclk("BTSSEL=00 SMCLK   BTCLK period", 1 * SMCLK_PERIOD);
		set_btssel("01");	measure_btclk("BTSSEL=01 SMCLK:2 BTCLK period", 2 * SMCLK_PERIOD);
		set_btssel("10");	measure_btclk("BTSSEL=10 SMCLK:4 BTCLK period", 4 * SMCLK_PERIOD);
		set_btssel("11");	measure_btclk("BTSSEL=11 SMCLK:8 BTCLK period", 8 * SMCLK_PERIOD);

		-- and the count still advances one step per BTCLK at the slowest rate
		clr		<= '1';
		step(1);
		clr		<= '0';
		step(1);	check("cnt at SMCLK:8", cnt_int, 1);
		step(1);	check("cnt at SMCLK:8", cnt_int, 2);

		--------------------------------------------------
		-- 4. BTHOLD
		--------------------------------------------------
		REPORT "--- BTHOLD ---" SEVERITY note;
		set_btssel("00");
		btcl0	<= STD_LOGIC_VECTOR(to_unsigned(1000, N));
		clr		<= '1';
		step(2);
		clr		<= '0';
		step(7);					-- 0 -> 7
		check("cnt before hold", cnt_int, 7);
		hold	<= '1';
		WAIT FOR 20 * SMCLK_PERIOD;
		check("cnt after 20 held clocks", cnt_int, 7);
		hold	<= '0';
		step(3);
		check("cnt after release", cnt_int, 10);

		--------------------------------------------------
		-- 5. BTCLR, including while held
		--------------------------------------------------
		REPORT "--- BTCLR ---" SEVERITY note;
		clr		<= '1';
		step(1);
		clr		<= '0';
		check("cnt after BTCLR", cnt_int, 0);

		step(5);
		check("cnt before held clear", cnt_int, 5);
		hold	<= '1';
		clr		<= '1';
		step(1);
		check("cnt after BTCLR while BTHOLD", cnt_int, 0);
		clr		<= '0';
		hold	<= '0';

		--------------------------------------------------
		-- 6. shortening BTCL0 under a running counter
		--------------------------------------------------
		REPORT "--- BTCL0 shortened mid-period ---" SEVERITY note;
		step(50);
		check("cnt before the reload", cnt_int, 50);
		btcl0	<= STD_LOGIC_VECTOR(to_unsigned(10, N));
		step(1);
		-- cnt was 50, well past the new BTCL0 of 10, so the next edge must
		-- restart it rather than carry on to 0xFFFFFFFF
		check("cnt after shortening BTCL0 to 10", cnt_int, 0);
		step(11);
		check("cnt one full short period later", cnt_int, 0);

		--------------------------------------------------
		REPORT "==================================================" SEVERITY note;
		IF errs = 0 THEN
			REPORT "ALL TESTS PASSED" SEVERITY note;
		ELSE
			REPORT NATURAL'image(errs) & " FAILURES" SEVERITY failure;
		END IF;
		REPORT "==================================================" SEVERITY note;

		sim_done <= TRUE;
		WAIT;
	END PROCESS stim;

END sim;
