--============================================================================
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Unit testbench for the unsigned multicycle division accelerator.
--
-- Two DUTs are driven from one stimulus process:
--   DUT_S : N=6  - exhaustively checked over all 64x64 operand pairs,
--                  including every division by zero
--   DUT_F : N=32 - directed corner cases plus pseudo-random pairs
--
-- Self-checking: every result is compared against a golden model and the
-- run ends with a pass/fail report. Nothing to inspect by eye.
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;


ENTITY tb_divider IS
END tb_divider;


ARCHITECTURE sim OF tb_divider IS
	CONSTANT CLK_PERIOD	: TIME		:= 10 ns;
	CONSTANT N_SMALL			: POSITIVE	:= 6;	-- small width, exhaustive
	CONSTANT N_FULL			: POSITIVE	:= 32;	-- full width, directed + random
	CONSTANT RAND_TESTS	: NATURAL	:= 500;

	SIGNAL divclk		: STD_LOGIC := '0';
	SIGNAL divrst		: STD_LOGIC := '1';
	SIGNAL sim_done		: BOOLEAN	:= FALSE;

	-- Small DUT
	SIGNAL s_dividend	: STD_LOGIC_VECTOR(N_SMALL-1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL s_divisor	: STD_LOGIC_VECTOR(N_SMALL-1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL s_ena		: STD_LOGIC := '0';
	SIGNAL s_quotient	: STD_LOGIC_VECTOR(N_SMALL-1 DOWNTO 0);
	SIGNAL s_residue	: STD_LOGIC_VECTOR(N_SMALL-1 DOWNTO 0);
	SIGNAL s_busy		: STD_LOGIC;

	-- Full DUT
	SIGNAL f_dividend	: STD_LOGIC_VECTOR(N_FULL-1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL f_divisor	: STD_LOGIC_VECTOR(N_FULL-1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL f_ena		: STD_LOGIC := '0';
	SIGNAL f_quotient	: STD_LOGIC_VECTOR(N_FULL-1 DOWNTO 0);
	SIGNAL f_residue	: STD_LOGIC_VECTOR(N_FULL-1 DOWNTO 0);
	SIGNAL f_busy		: STD_LOGIC;

BEGIN
	--=======================================
	-- Clock
	--=======================================
	divclk <= NOT divclk AFTER CLK_PERIOD/2 WHEN NOT sim_done ELSE '0';

	--=======================================
	-- DUTs
	--=======================================
	DUT_S: ENTITY work.divider
	generic map(
		N			=> N_SMALL
	)
	PORT MAP (
		Dividend	=> s_dividend,
		Divisor		=> s_divisor,
		DIVCLK		=> divclk,
		DIVRST		=> divrst,
		DIVENA		=> s_ena,
		Quotient	=> s_quotient,
		Residue		=> s_residue,
		DIVBUSY		=> s_busy
	);

	DUT_F: ENTITY work.divider
	generic map(
		N			=> N_FULL
	)
	PORT MAP (
		Dividend	=> f_dividend,
		Divisor		=> f_divisor,
		DIVCLK		=> divclk,
		DIVRST		=> divrst,
		DIVENA		=> f_ena,
		Quotient	=> f_quotient,
		Residue		=> f_residue,
		DIVBUSY		=> f_busy
	);

	--=======================================
	-- Stimulus and checking
	--=======================================
	stim: PROCESS
		VARIABLE err_cnt	: NATURAL := 0;
		VARIABLE tst_cnt	: NATURAL := 0;
		VARIABLE lfsr		: UNSIGNED(31 DOWNTO 0) := x"ACE12345";
		VARIABLE rand_a		: STD_LOGIC_VECTOR(N_FULL-1 DOWNTO 0);

		-- 32-bit maximal-length LFSR, taps 32,22,2,1
		PROCEDURE next_rand IS
		BEGIN
			lfsr := lfsr(30 DOWNTO 0) &
			        (lfsr(31) XOR lfsr(21) XOR lfsr(1) XOR lfsr(0));
		END PROCEDURE;

		------------------------------------------------------------------
		-- Small DUT: drive one division and compare against the golden model
		------------------------------------------------------------------
		PROCEDURE check_small(a : NATURAL; b : NATURAL) IS
			VARIABLE exp_q : NATURAL;
			VARIABLE exp_r : NATURAL;
			VARIABLE got_q : NATURAL;
			VARIABLE got_r : NATURAL;
		BEGIN
			IF b = 0 THEN				-- RISC-V divu/remu by zero
				exp_q := 2**N_SMALL - 1;
				exp_r := a;
			ELSE
				exp_q := a / b;
				exp_r := a MOD b;
			END IF;

			s_dividend	<= STD_LOGIC_VECTOR(to_unsigned(a, N_SMALL));
			s_divisor	<= STD_LOGIC_VECTOR(to_unsigned(b, N_SMALL));
			WAIT UNTIL rising_edge(divclk);
			s_ena		<= '1';
			WAIT UNTIL rising_edge(divclk);		-- operands loaded here
			s_ena		<= '0';

			WAIT FOR 1 ns;
			IF s_busy /= '1' THEN
				REPORT "DIVBUSY did not assert on load (a=" & NATURAL'image(a) &
				       " b=" & NATURAL'image(b) & ")" SEVERITY error;
				err_cnt := err_cnt + 1;
			END IF;

			WAIT UNTIL s_busy = '0';
			WAIT FOR 1 ns;

			got_q := to_integer(unsigned(s_quotient));
			got_r := to_integer(unsigned(s_residue));
			tst_cnt := tst_cnt + 1;

			IF got_q /= exp_q OR got_r /= exp_r THEN
				REPORT "N=6 FAIL " & NATURAL'image(a) & "/" & NATURAL'image(b) &
				       " : expected q=" & NATURAL'image(exp_q) &
				       " r=" & NATURAL'image(exp_r) &
				       " , got q=" & NATURAL'image(got_q) &
				       " r=" & NATURAL'image(got_r)
				SEVERITY error;
				err_cnt := err_cnt + 1;
			END IF;
		END PROCEDURE;

		------------------------------------------------------------------
		-- Full DUT: same, but the golden model runs on unsigned
		------------------------------------------------------------------
		PROCEDURE check_full(a : STD_LOGIC_VECTOR(N_FULL-1 DOWNTO 0);
		                     b : STD_LOGIC_VECTOR(N_FULL-1 DOWNTO 0)) IS
			VARIABLE exp_q : STD_LOGIC_VECTOR(N_FULL-1 DOWNTO 0);
			VARIABLE exp_r : STD_LOGIC_VECTOR(N_FULL-1 DOWNTO 0);
		BEGIN
			IF unsigned(b) = 0 THEN		-- RISC-V divu/remu by zero
				exp_q := (OTHERS => '1');
				exp_r := a;
			ELSE
				exp_q := STD_LOGIC_VECTOR(unsigned(a) / unsigned(b));
				exp_r := STD_LOGIC_VECTOR(unsigned(a) MOD unsigned(b));
			END IF;

			f_dividend	<= a;
			f_divisor	<= b;
			WAIT UNTIL rising_edge(divclk);
			f_ena		<= '1';
			WAIT UNTIL rising_edge(divclk);
			f_ena		<= '0';

			WAIT FOR 1 ns;
			IF f_busy /= '1' THEN
				REPORT "DIVBUSY did not assert on load (full width)"
				SEVERITY error;
				err_cnt := err_cnt + 1;
			END IF;

			WAIT UNTIL f_busy = '0';
			WAIT FOR 1 ns;

			tst_cnt := tst_cnt + 1;

			IF f_quotient /= exp_q OR f_residue /= exp_r THEN
				REPORT "N=32 FAIL 0x" & to_hstring(a) & " / 0x" & to_hstring(b) &
				       " : expected q=0x" & to_hstring(exp_q) &
				       " r=0x" & to_hstring(exp_r) &
				       " , got q=0x" & to_hstring(f_quotient) &
				       " r=0x" & to_hstring(f_residue)
				SEVERITY error;
				err_cnt := err_cnt + 1;
			END IF;
		END PROCEDURE;

		------------------------------------------------------------------
		-- Same as check_small, but announces where to look in the waveform
		------------------------------------------------------------------
		PROCEDURE showcase(a : NATURAL; b : NATURAL) IS
		BEGIN
			check_small(a, b);
			REPORT "SHOWCASE  " & NATURAL'image(a) & " / " & NATURAL'image(b) &
			       "  =  quotient " &
			       NATURAL'image(to_integer(unsigned(s_quotient))) &
			       " , residue " &
			       NATURAL'image(to_integer(unsigned(s_residue))) &
			       "   <-- DIVBUSY fell at " & TIME'image(now - 1 ns)
			SEVERITY note;
		END PROCEDURE;

	BEGIN
		--------------------------------------------------------------
		-- Reset
		--------------------------------------------------------------
		divrst <= '1';
		WAIT FOR CLK_PERIOD * 5;
		divrst <= '0';
		WAIT UNTIL rising_edge(divclk);

		IF s_busy /= '0' OR f_busy /= '0' THEN
			REPORT "DIVBUSY should be low after reset" SEVERITY error;
			err_cnt := err_cnt + 1;
		END IF;

		--------------------------------------------------------------
		-- Showcase: a few readable divisions at the very start of the
		-- waveform, so there is no need to hunt through the sweep below.
		--------------------------------------------------------------
		REPORT "--- showcase divisions (N=6) ---" SEVERITY note;
		showcase(24,  5);	-- q=4  r=4   the general case
		showcase(13,  3);	-- q=4  r=1
		showcase(63,  1);	-- q=63 r=0   divide by one
		showcase( 5,  9);	-- q=0  r=5   divisor larger than dividend
		showcase( 7,  0);	-- q=63 r=7   divide by zero
		REPORT "--- end of showcase ---" SEVERITY note;

		--------------------------------------------------------------
		-- Exhaustive sweep at N=6
		--------------------------------------------------------------
		REPORT "Exhaustive N=6 sweep (4096 pairs)..." SEVERITY note;
		FOR a IN 0 TO 2**N_SMALL - 1 LOOP
			FOR b IN 0 TO 2**N_SMALL - 1 LOOP
				check_small(a, b);
			END LOOP;
		END LOOP;

		--------------------------------------------------------------
		-- Directed corner cases at N=32
		--------------------------------------------------------------
		REPORT "Directed N=32 corner cases..." SEVERITY note;
		check_full(x"00000000", x"00000001");	-- 0 / 1
		check_full(x"00000001", x"00000001");	-- 1 / 1
		check_full(x"00000001", x"00000002");	-- quotient 0, residue 1
		check_full(x"00000064", x"00000007");	-- 100 / 7
		check_full(x"FFFFFFFF", x"00000001");	-- max / 1
		check_full(x"FFFFFFFF", x"00000002");	-- max / 2
		check_full(x"FFFFFFFF", x"FFFFFFFF");	-- max / max
		check_full(x"FFFFFFFE", x"FFFFFFFF");	-- just below max
		check_full(x"00000001", x"FFFFFFFF");	-- tiny / max
		check_full(x"80000000", x"80000000");	-- MSB set both sides
		check_full(x"80000000", x"00000002");	-- exercises the top bit
		check_full(x"7FFFFFFF", x"00010000");	-- power-of-two divisor
		check_full(x"12345678", x"000003E8");	-- /1000
		check_full(x"00000000", x"00000000");	-- 0 / 0
		check_full(x"00000005", x"00000000");	-- 5 / 0
		check_full(x"FFFFFFFF", x"00000000");	-- max / 0

		--------------------------------------------------------------
		-- Pseudo-random pairs at N=32
		--------------------------------------------------------------
		REPORT "Random N=32 pairs..." SEVERITY note;
		FOR i IN 1 TO RAND_TESTS LOOP
			next_rand;
			rand_a := STD_LOGIC_VECTOR(lfsr);
			next_rand;
			check_full(rand_a, STD_LOGIC_VECTOR(lfsr));
		END LOOP;

		--------------------------------------------------------------
		-- Back-to-back: DIVENA held high must start exactly one division
		--------------------------------------------------------------
		REPORT "DIVENA held-high check..." SEVERITY note;
		f_dividend	<= x"000000FF";
		f_divisor	<= x"00000010";
		WAIT UNTIL rising_edge(divclk);
		f_ena		<= '1';
		WAIT UNTIL f_busy = '0';				-- one division completes
		WAIT FOR CLK_PERIOD * 5;				-- DIVENA still high
		IF f_busy /= '0' THEN
			REPORT "Divider restarted while DIVENA was held high" SEVERITY error;
			err_cnt := err_cnt + 1;
		END IF;
		IF f_quotient /= x"0000000F" OR f_residue /= x"0000000F" THEN
			REPORT "Held-high result wrong: q=0x" & to_hstring(f_quotient) &
			       " r=0x" & to_hstring(f_residue) SEVERITY error;
			err_cnt := err_cnt + 1;
		END IF;
		f_ena <= '0';
		tst_cnt := tst_cnt + 1;

		--------------------------------------------------------------
		-- Report
		--------------------------------------------------------------
		WAIT FOR CLK_PERIOD * 2;
		REPORT "==================================================" SEVERITY note;
		REPORT NATURAL'image(tst_cnt) & " divisions checked, " &
		       NATURAL'image(err_cnt) & " errors" SEVERITY note;
		IF err_cnt = 0 THEN
			REPORT "ALL TESTS PASSED" SEVERITY note;
		ELSE
			REPORT "THERE ARE FAILURES - see the errors above" SEVERITY failure;
		END IF;
		REPORT "==================================================" SEVERITY note;

		sim_done <= TRUE;
		WAIT;
	END PROCESS stim;

END sim;
