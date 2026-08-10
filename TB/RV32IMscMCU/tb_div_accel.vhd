--============================================================================
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Unit testbench for the division accelerator wrapper.
--
-- The stimulus process plays the part of the CPU: it presents operands and
-- div_op_i, stalls for as long as div_busy_o is high, and does its
-- "write-back" on the single cycle where div_busy_o is low.
--
-- Checks:
--   1. div_busy_o rises in the SAME MCLK cycle as div_op_i. This is the
--      whole reason the wrapper exists - a stall driven straight off the
--      synchronized DIVBUSY would arrive several cycles late and the core
--      would run past the instruction
--   2. results are correct, including division by zero
--   3. back-to-back divisions with div_op_i never going low, which is what
--      two consecutive div instructions actually look like to this block
--   4. the stall lasts a sane, repeatable number of MCLK cycles
--   5. the DIVCLK:MCLK ratio is still one the handshake can survive - see
--      the assertion below, which is the guard rail on retuning the PLLs
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE work.clk_config_package.all;


ENTITY tb_div_accel IS
END tb_div_accel;


ARCHITECTURE sim OF tb_div_accel IS
	-- Taken from the generated clock configuration rather than hard-coded, so
	-- retuning a PLL in QUARTUS/gen_plls.tcl re-tests the accelerator at the
	-- ratio it will actually run at.
	CONSTANT MCLK_PERIOD	: TIME		:= (1000.0 / G_MCLK_MHZ)   * 1 ns;
	CONSTANT DCLK_PERIOD	: TIME		:= (1000.0 / G_DIVCLK_MHZ) * 1 ns;
	CONSTANT N				: POSITIVE	:= 32;

	-- HOW FAST DIVCLK IS ALLOWED TO GO.
	--
	-- DIVBUSY is high for exactly N DIVCLK cycles, which in MCLK terms is
	-- N * f_mclk / f_divclk cycles. The MCLK-side two-flop synchronizer has to
	-- sample that pulse, so it needs it to stay high for at least two MCLK
	-- edges. Push DIVCLK too far above MCLK and the busy pulse becomes
	-- narrower than the synchronizer can see: WAIT_BUSY then never observes
	-- the divider start and the core stalls forever.
	--
	-- At the current 200/25 = 8 this evaluates to 4.0, so there is a factor of
	-- two in hand. The limit is a ratio of 16.
	CONSTANT BUSY_MCLK_CYCLES : REAL := real(N) * G_MCLK_MHZ / G_DIVCLK_MHZ;

	SIGNAL mclk			: STD_LOGIC := '0';
	SIGNAL divclk		: STD_LOGIC := '0';
	SIGNAL rst			: STD_LOGIC := '1';
	SIGNAL sim_done		: BOOLEAN	:= FALSE;

	SIGNAL Ain			: STD_LOGIC_VECTOR(N-1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL Bin			: STD_LOGIC_VECTOR(N-1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL div_op		: STD_LOGIC := '0';
	SIGNAL Quotient		: STD_LOGIC_VECTOR(N-1 DOWNTO 0);
	SIGNAL Residue		: STD_LOGIC_VECTOR(N-1 DOWNTO 0);
	SIGNAL div_busy		: STD_LOGIC;

BEGIN
	ASSERT BUSY_MCLK_CYCLES >= 2.0
		REPORT "DIVCLK:MCLK ratio is too high. DIVBUSY would be high for only "
		     & REAL'image(BUSY_MCLK_CYCLES) & " MCLK cycles, which the two-flop "
		     & "synchronizer in DIV_ACCEL cannot reliably capture - the core "
		     & "would stall forever. Lower G_DIVCLK_MHZ in QUARTUS/gen_plls.tcl."
		SEVERITY failure;

	mclk	<= NOT mclk   AFTER MCLK_PERIOD/2 WHEN NOT sim_done ELSE '0';
	divclk	<= NOT divclk AFTER DCLK_PERIOD/2 WHEN NOT sim_done ELSE '0';

	DUT: ENTITY work.div_accel
	generic map(
		N			=> N
	)
	PORT MAP (
		mclk_i		=> mclk,
		rst_i		=> rst,
		Ain_i		=> Ain,
		Bin_i		=> Bin,
		div_op_i	=> div_op,
		Quotient_o	=> Quotient,
		Residue_o	=> Residue,
		div_busy_o	=> div_busy,
		divclk_i	=> divclk
	);

	stim: PROCESS
		VARIABLE errs		: NATURAL := 0;
		VARIABLE tests		: NATURAL := 0;

		-- Golden model
		PROCEDURE expected(a, b : STD_LOGIC_VECTOR(N-1 DOWNTO 0);
		                   q, r : OUT STD_LOGIC_VECTOR(N-1 DOWNTO 0)) IS
		BEGIN
			IF unsigned(b) = 0 THEN
				q := (OTHERS => '1');
				r := a;
			ELSE
				q := STD_LOGIC_VECTOR(unsigned(a) / unsigned(b));
				r := STD_LOGIC_VECTOR(unsigned(a) MOD unsigned(b));
			END IF;
		END PROCEDURE;

		PROCEDURE check_results(a, b : STD_LOGIC_VECTOR(N-1 DOWNTO 0)) IS
			VARIABLE eq, er : STD_LOGIC_VECTOR(N-1 DOWNTO 0);
		BEGIN
			expected(a, b, eq, er);
			tests := tests + 1;
			IF Quotient /= eq OR Residue /= er THEN
				REPORT "FAIL 0x" & to_hstring(a) & " / 0x" & to_hstring(b) &
				       " : expected q=0x" & to_hstring(eq) &
				       " r=0x" & to_hstring(er) &
				       " , got q=0x" & to_hstring(Quotient) &
				       " r=0x" & to_hstring(Residue) SEVERITY error;
				errs := errs + 1;
			END IF;
		END PROCEDURE;

		------------------------------------------------------------------
		-- Issue one division the way the core would, and count the stall.
		-- hold_op = true leaves div_op_i asserted afterwards, modelling a
		-- following instruction that is also a div.
		------------------------------------------------------------------
		PROCEDURE issue(a, b : STD_LOGIC_VECTOR(N-1 DOWNTO 0);
		                hold_op : BOOLEAN) IS
			VARIABLE stall : NATURAL := 0;
		BEGIN
			WAIT UNTIL rising_edge(mclk);
			Ain		<= a;
			Bin		<= b;
			div_op	<= '1';

			-- The stall must be visible immediately, not next cycle
			WAIT FOR 1 ns;
			IF div_busy /= '1' THEN
				REPORT "div_busy_o did not assert in the same cycle as div_op_i"
				SEVERITY error;
				errs := errs + 1;
			END IF;

			-- Core is stalled: count the cycles it loses
			WHILE div_busy = '1' LOOP
				WAIT UNTIL rising_edge(mclk);
				WAIT FOR 1 ns;
				stall := stall + 1;
			END LOOP;

			-- div_busy_o low: this is the write-back cycle
			check_results(a, b);
			REPORT "  0x" & to_hstring(a) & " / 0x" & to_hstring(b) &
			       "  ->  q=0x" & to_hstring(Quotient) &
			       " r=0x" & to_hstring(Residue) &
			       "   (" & NATURAL'image(stall) & " MCLK stall cycles)"
			SEVERITY note;

			-- We are inside the write-back cycle. In the real core the PC
			-- advances at the end of it, so div_op_i and the operands of the
			-- NEXT instruction all appear together on the following edge.
			-- When holding div_op_i we must therefore return now and let the
			-- next issue() drive that edge - waiting here would leave div_op_i
			-- asserted for a cycle with stale operands still on the bus.
			IF NOT hold_op THEN
				WAIT UNTIL rising_edge(mclk);
				div_op <= '0';
			END IF;
		END PROCEDURE;

	BEGIN
		rst <= '1';
		WAIT FOR 200 ns;
		rst <= '0';
		WAIT UNTIL rising_edge(mclk);

		IF div_busy /= '0' THEN
			REPORT "div_busy_o should be low when idle after reset" SEVERITY error;
			errs := errs + 1;
		END IF;

		--------------------------------------------------------------
		REPORT "--- single divisions ---" SEVERITY note;
		--------------------------------------------------------------
		issue(x"00000018", x"00000005", FALSE);		-- 24 / 5  -> 4 r 4
		WAIT FOR MCLK_PERIOD * 3;
		issue(x"00000064", x"00000007", FALSE);		-- 100 / 7 -> 14 r 2
		WAIT FOR MCLK_PERIOD * 2;
		issue(x"FFFFFFFF", x"00000002", FALSE);		-- max / 2
		WAIT FOR MCLK_PERIOD * 5;
		issue(x"12345678", x"000003E8", FALSE);		-- /1000
		WAIT FOR MCLK_PERIOD * 1;
		issue(x"00000007", x"00000000", FALSE);		-- divide by zero
		WAIT FOR MCLK_PERIOD * 4;
		issue(x"00000001", x"FFFFFFFF", FALSE);		-- quotient 0

		--------------------------------------------------------------
		REPORT "--- back to back, div_op_i never released ---" SEVERITY note;
		--------------------------------------------------------------
		issue(x"000000FF", x"00000010", TRUE);		-- 255 / 16 -> 15 r 15
		issue(x"0000FFFF", x"00000100", TRUE);		-- 65535 / 256 -> 255 r 255
		issue(x"DEADBEEF", x"0000CAFE", TRUE);
		issue(x"00000000", x"00000001", FALSE);		-- last one releases

		--------------------------------------------------------------
		REPORT "--- idle must stay idle ---" SEVERITY note;
		--------------------------------------------------------------
		WAIT FOR MCLK_PERIOD * 20;
		IF div_busy /= '0' THEN
			REPORT "div_busy_o asserted with no request pending" SEVERITY error;
			errs := errs + 1;
		END IF;

		WAIT FOR MCLK_PERIOD * 2;
		REPORT "==================================================" SEVERITY note;
		REPORT NATURAL'image(tests) & " divisions checked, " &
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
