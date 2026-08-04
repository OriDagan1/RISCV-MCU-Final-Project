--============================================================================
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Testbench for the complete Basic Timer of Fig.7.
--
-- Black-box: everything is driven through the BTCTL1 / BTCTL2 / BTCMPRx ports
-- and observed on PWMout, BTIFG, BTCAPR and BTCNT, so the wiring inside
-- BASIC_TIMER.vhd is under test as well as the individual blocks.
--
-- BTSSEL is left at 00 for most of the run so that BTCLK = SMCLK and every
-- count can be reasoned about in SMCLK edges. The divider ratios themselves
-- are covered in tb_btcnt; check 8 here only confirms the top level routes
-- BTSSEL through to the counter.
--
-- Reference settings used throughout: BTCMPR0 = 9, BTCMPR1 = 5, so the ramp
-- is 0..9 (a period of 10) and the threshold sits at 5.
--
--   cnt      0 1 2 3 4 5 6 7 8 9 | 0 1 ...
--   EQU1     . . . . . 1 1 1 1 1 |
--   EQU0     . . . . . . . . . 1 |
--   Mode 0   0 0 0 0 0 0 1 1 1 1 | 0        4 high out of 10
--   Mode 1   1 1 1 1 1 1 0 0 0 0 | 1        6 high out of 10
--
-- The output is registered, so each level appears one BTCLK after the
-- crossing that caused it - hence Mode 0 rising at cnt=6 and not cnt=5.
--
-- Checks:
--   1. reset state of every output
--   2. the BTCL latches self-start from BTCMPR without a start-up sequence
--   3. up-mode period is BTCMPR0+1
--   4. Mode 0 "Set/Reset" duty, and the waveform edge by edge
--   5. Mode 1 "Reset/Set" is the exact mirror
--   6. BTOUTEN = '0' freezes PWMout
--   7. BTCMPR1 is double buffered: a mid-period write only takes effect at
--      the next period boundary
--   8. BTSSEL reaches the counter
--   9. BTHOLD and BTCLR reach the counter through BTCTL1
--  10. input capture: rising edge, falling edge, disabled, and the CAPIN1 pin
--  11. the BTINT mux selects EQU0 / EQU1 / capture event
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;


ENTITY tb_basic_timer IS
END tb_basic_timer;


ARCHITECTURE sim OF tb_basic_timer IS
	CONSTANT N				: positive	:= 32;
	CONSTANT SMCLK_PERIOD	: TIME		:= 20 ns;	-- 50 MHz

	--BTSSEL encodings
	CONSTANT SS_1			: STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";
	CONSTANT SS_2			: STD_LOGIC_VECTOR(1 DOWNTO 0) := "01";
	--CAPISEL encodings
	CONSTANT CS_IN1			: STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";
	CONSTANT CS_VCC			: STD_LOGIC_VECTOR(1 DOWNTO 0) := "10";
	CONSTANT CS_GND			: STD_LOGIC_VECTOR(1 DOWNTO 0) := "11";
	--CAPMD encodings
	CONSTANT CM_OFF			: STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";
	CONSTANT CM_RISE		: STD_LOGIC_VECTOR(1 DOWNTO 0) := "01";
	CONSTANT CM_FALL		: STD_LOGIC_VECTOR(1 DOWNTO 0) := "10";
	--BTINT encodings
	CONSTANT BI_EQU0		: STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";
	CONSTANT BI_EQU1		: STD_LOGIC_VECTOR(1 DOWNTO 0) := "01";
	CONSTANT BI_CAP			: STD_LOGIC_VECTOR(1 DOWNTO 0) := "10";

	SIGNAL smclk		: STD_LOGIC := '0';
	SIGNAL rst			: STD_LOGIC := '1';
	SIGNAL btctl1		: STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
	SIGNAL btctl2		: STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
	SIGNAL btcmpr0		: STD_LOGIC_VECTOR(N-1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL btcmpr1		: STD_LOGIC_VECTOR(N-1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL capin1		: STD_LOGIC := '0';
	SIGNAL capin2		: STD_LOGIC := '0';
	SIGNAL pwmout		: STD_LOGIC;
	SIGNAL btifg		: STD_LOGIC;
	SIGNAL btcapr		: STD_LOGIC_VECTOR(N-1 DOWNTO 0);
	SIGNAL btcnt		: STD_LOGIC_VECTOR(N-1 DOWNTO 0);

	SIGNAL sim_done		: BOOLEAN := FALSE;

	-- Readable in the wave window
	SIGNAL cnt_int		: NATURAL := 0;
	SIGNAL capr_int		: NATURAL := 0;

	--=======================================
	-- BTCTL1 assembled from its fields, so the tests read like the register
	-- map instead of like bit patterns:
	--   7 BTOUTMD | 6 BTOUTEN | 5 BTHOLD | 4:3 BTSSEL | 2 BTCLR | 1:0 BTINT
	--=======================================
	FUNCTION ctl1(outmd	: STD_LOGIC;
	              outen	: STD_LOGIC;
	              hold	: STD_LOGIC;
	              ssel	: STD_LOGIC_VECTOR(1 DOWNTO 0);
	              clr	: STD_LOGIC;
	              intr	: STD_LOGIC_VECTOR(1 DOWNTO 0))
	RETURN STD_LOGIC_VECTOR IS
	BEGIN
		RETURN outmd & outen & hold & ssel & clr & intr;
	END FUNCTION;

	--   7:4 reserved | 3:2 CAPMD | 1:0 CAPISEL
	FUNCTION ctl2(capmd		: STD_LOGIC_VECTOR(1 DOWNTO 0);
	              capisel	: STD_LOGIC_VECTOR(1 DOWNTO 0))
	RETURN STD_LOGIC_VECTOR IS
	BEGIN
		RETURN "0000" & capmd & capisel;
	END FUNCTION;

BEGIN
	smclk	<= NOT smclk AFTER SMCLK_PERIOD/2 WHEN NOT sim_done ELSE '0';

	cnt_int		<= to_integer(unsigned(btcnt));
	capr_int	<= to_integer(unsigned(btcapr));

	--=======================================
	DUT: ENTITY work.basic_timer
	GENERIC MAP (
		N			=> N
	)
	PORT MAP (
		smclk_i		=> smclk,
		rst_i		=> rst,
		btctl1_i	=> btctl1,
		btctl2_i	=> btctl2,
		btcmpr0_i	=> btcmpr0,
		btcmpr1_i	=> btcmpr1,
		capin1_i	=> capin1,
		capin2_i	=> capin2,
		pwmout_o	=> pwmout,
		btifg_o		=> btifg,
		btcapr_o	=> btcapr,
		btcnt_o		=> btcnt
	);

	--=======================================
	-- Stimulus
	--=======================================
	stim: PROCESS
		VARIABLE errs	: NATURAL := 0;
		VARIABLE c		: NATURAL;		-- count noted at a capture trigger
		VARIABLE prev	: NATURAL;		-- BTCAPR before a non-event

		PROCEDURE step(n : NATURAL) IS
		BEGIN
			FOR i IN 1 TO n LOOP
				WAIT UNTIL rising_edge(smclk);
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

		PROCEDURE checkb(tag : STRING; got : STD_LOGIC; want : STD_LOGIC) IS
		BEGIN
			IF got /= want THEN
				REPORT tag & ": expected " & STD_LOGIC'image(want) &
				       " , got " & STD_LOGIC'image(got) SEVERITY error;
				errs := errs + 1;
			ELSE
				REPORT "  " & tag & " = " & STD_LOGIC'image(got) & " OK"
				SEVERITY note;
			END IF;
		END PROCEDURE;

		-- Advance to the start of the NEXT period. Always crosses a period
		-- boundary, even when called with the count already at 0, so any
		-- pending BTCMPR value is guaranteed to have been latched into BTCL.
		PROCEDURE align IS
		BEGIN
			step(1);
			FOR i IN 0 TO 2000 LOOP
				EXIT WHEN cnt_int = 0;
				step(1);
			END LOOP;
		END PROCEDURE;

		-- Sample PWMout once per count over one whole period
		PROCEDURE duty(tag : STRING; period : NATURAL; want : NATURAL) IS
			VARIABLE h : NATURAL := 0;
		BEGIN
			align;
			FOR i IN 1 TO period LOOP
				IF pwmout = '1' THEN
					h := h + 1;
				END IF;
				step(1);
			END LOOP;
			check(tag, h, want);
		END PROCEDURE;

	BEGIN
		--------------------------------------------------
		-- 1. reset
		--------------------------------------------------
		REPORT "--- reset ---" SEVERITY note;
		btcmpr0	<= STD_LOGIC_VECTOR(to_unsigned(9, N));
		btcmpr1	<= STD_LOGIC_VECTOR(to_unsigned(5, N));
		btctl1	<= ctl1('0','0','0', SS_1, '0', BI_EQU0);
		btctl2	<= ctl2(CM_OFF, CS_GND);
		rst		<= '1';
		WAIT FOR 4 * SMCLK_PERIOD;
		check ("BTCNT  after reset", cnt_int,  0);
		check ("BTCAPR after reset", capr_int, 0);
		checkb("PWMout after reset", pwmout, '0');
		rst		<= '0';

		--------------------------------------------------
		-- 2. the BTCL latches load themselves
		--
		-- BTCL0 resets to 0 and EQU0 is "BTCNT >= BTCL0", so EQU0 is already
		-- true out of reset and the first edge copies BTCMPR0 into BTCL0. If
		-- that did not happen the counter would be stuck at 0 forever, so
		-- seeing it count at all proves the self-start.
		--------------------------------------------------
		REPORT "--- BTCL latches self-start ---" SEVERITY note;
		step(1);	check("BTCNT after the loading edge", cnt_int, 0);
		step(1);	check("BTCNT then advances to",       cnt_int, 1);

		--------------------------------------------------
		-- 3. period is BTCMPR0 + 1
		--------------------------------------------------
		REPORT "--- period, BTCMPR0 = 9 ---" SEVERITY note;
		align;
		step(9);	check("BTCNT at the top of the ramp", cnt_int, 9);
		step(1);	check("BTCNT wraps to",               cnt_int, 0);

		--------------------------------------------------
		-- 4. Output Mode 0, Set/Reset
		--------------------------------------------------
		REPORT "--- Mode 0 Set/Reset ---" SEVERITY note;
		btctl1	<= ctl1('0','1','0', SS_1, '0', BI_EQU0);	-- BTOUTMD=0, BTOUTEN=1
		duty("Mode 0 high count", 10, 4);

		align;
		checkb("Mode 0 at cnt=0", pwmout, '0');
		step(5);	checkb("Mode 0 at cnt=5", pwmout, '0');
		step(1);	checkb("Mode 0 at cnt=6", pwmout, '1');
		step(3);	checkb("Mode 0 at cnt=9", pwmout, '1');
		step(1);	checkb("Mode 0 back at cnt=0", pwmout, '0');

		--------------------------------------------------
		-- 5. Output Mode 1, Reset/Set - the mirror image
		--------------------------------------------------
		REPORT "--- Mode 1 Reset/Set ---" SEVERITY note;
		btctl1	<= ctl1('1','1','0', SS_1, '0', BI_EQU0);	-- BTOUTMD=1
		duty("Mode 1 high count", 10, 6);

		align;
		checkb("Mode 1 at cnt=0", pwmout, '1');
		step(5);	checkb("Mode 1 at cnt=5", pwmout, '1');
		step(1);	checkb("Mode 1 at cnt=6", pwmout, '0');
		step(3);	checkb("Mode 1 at cnt=9", pwmout, '0');
		step(1);	checkb("Mode 1 back at cnt=0", pwmout, '1');

		--------------------------------------------------
		-- 6. BTOUTEN freezes the output
		--------------------------------------------------
		REPORT "--- BTOUTEN ---" SEVERITY note;
		btctl1	<= ctl1('0','1','0', SS_1, '0', BI_EQU0);	-- Mode 0, enabled
		align;
		step(7);	checkb("PWMout high before freezing", pwmout, '1');
		btctl1	<= ctl1('0','0','0', SS_1, '0', BI_EQU0);	-- BTOUTEN=0
		step(20);	checkb("PWMout after 20 frozen clocks", pwmout, '1');
		btctl1	<= ctl1('0','1','0', SS_1, '0', BI_EQU0);	-- re-enable
		duty("Mode 0 high count after re-enable", 10, 4);

		--------------------------------------------------
		-- 7. BTCMPR1 is double buffered
		--
		-- Rewrite BTCMPR1 from 5 to 2 at cnt=2. Without the BTCL1 latch the
		-- new threshold would be met immediately and PWMout would rise at
		-- cnt=3; with it, this period must still use 5 and rise at cnt=6.
		--------------------------------------------------
		REPORT "--- BTCMPR1 double buffering ---" SEVERITY note;
		align;
		step(2);	check("at cnt", cnt_int, 2);
		btcmpr1	<= STD_LOGIC_VECTOR(to_unsigned(2, N));
		step(1);	checkb("PWMout at cnt=3, still the old threshold", pwmout, '0');
		step(1);	checkb("PWMout at cnt=4, still the old threshold", pwmout, '0');
		step(1);	checkb("PWMout at cnt=5, still the old threshold", pwmout, '0');
		step(1);	checkb("PWMout at cnt=6, old threshold applied",   pwmout, '1');
		-- the next period runs on the new value: high from cnt=3 to cnt=9
		duty("high count with BTCMPR1 = 2", 10, 7);
		btcmpr1	<= STD_LOGIC_VECTOR(to_unsigned(5, N));
		duty("high count back at BTCMPR1 = 5", 10, 4);

		--------------------------------------------------
		-- 8. BTSSEL reaches the counter
		--
		-- Park the timer before changing BTSSEL, as BT_CLKDIV.vhd requires.
		-- At SMCLK:2 exactly 10 BTCLK edges fall in 20 SMCLK edges, so the
		-- count must advance by 10 whatever the divider phase.
		--
		-- BTCMPR0 is raised to 1000 first and a period allowed to elapse, so
		-- that the BTCL0 latch has actually taken the new value before the
		-- timer is parked - otherwise the count would still wrap at 9.
		--------------------------------------------------
		REPORT "--- BTSSEL reaches the counter ---" SEVERITY note;
		btcmpr0	<= STD_LOGIC_VECTOR(to_unsigned(1000, N));
		step(12);											-- let BTCL0 reload
		btctl1	<= ctl1('0','1','1', SS_1, '1', BI_EQU0);	-- park: BTHOLD + BTCLR
		step(4);
		btctl1	<= ctl1('0','1','1', SS_2, '1', BI_EQU0);	-- now change BTSSEL
		step(4);
		btctl1	<= ctl1('0','1','0', SS_2, '0', BI_EQU0);	-- release
		step(20);
		check("BTCNT after 20 SMCLK at SMCLK:2", cnt_int, 10);

		--------------------------------------------------
		-- 9. BTHOLD and BTCLR through BTCTL1
		--------------------------------------------------
		REPORT "--- BTHOLD and BTCLR ---" SEVERITY note;
		btctl1	<= ctl1('0','1','1', SS_2, '1', BI_EQU0);	-- park
		step(4);
		btctl1	<= ctl1('0','1','0', SS_1, '0', BI_EQU0);	-- back to SMCLK
		step(7);	check("BTCNT before hold", cnt_int, 7);
		btctl1	<= ctl1('0','1','1', SS_1, '0', BI_EQU0);	-- BTHOLD
		step(20);	check("BTCNT after 20 held clocks", cnt_int, 7);
		btctl1	<= ctl1('0','1','0', SS_1, '1', BI_EQU0);	-- BTCLR
		step(2);	check("BTCNT after BTCLR", cnt_int, 0);
		btctl1	<= ctl1('0','1','0', SS_1, '0', BI_EQU0);

		--------------------------------------------------
		-- 10. input capture
		--
		-- BTCMPR0 is still 1000 so the count cannot wrap during this test.
		-- The capture input passes through a two-flop synchronizer plus one
		-- delayed copy, so the event is recognised two edges after the source
		-- changes and the register samples the count on the third. Hence
		-- BTCAPR = c+2, where c is the count when the source was switched.
		--------------------------------------------------
		REPORT "--- input capture ---" SEVERITY note;
		btctl2	<= ctl2(CM_RISE, CS_GND);		-- source parked low
		step(5);
		c := cnt_int;
		btctl2	<= ctl2(CM_RISE, CS_VCC);		-- GND -> VCC, a rising edge
		step(3);
		check("BTCAPR after a rising-edge capture", capr_int, c + 2);

		c := cnt_int;
		btctl2	<= ctl2(CM_FALL, CS_GND);		-- VCC -> GND, a falling edge
		step(3);
		check("BTCAPR after a falling-edge capture", capr_int, c + 2);

		prev := capr_int;
		btctl2	<= ctl2(CM_OFF, CS_VCC);		-- an edge, but CAPMD disabled
		step(5);
		check("BTCAPR unchanged with CAPMD = 00", capr_int, prev);

		-- and through the real CAPIN1 pin rather than the constant sources
		capin1	<= '0';
		btctl2	<= ctl2(CM_RISE, CS_IN1);
		step(5);
		c := cnt_int;
		capin1	<= '1';
		step(3);
		check("BTCAPR after a CAPIN1 rising edge", capr_int, c + 2);

		--------------------------------------------------
		-- 11. the BTINT interrupt source mux
		--
		-- Reset first: it zeroes BTCL0, which makes EQU0 true again and so
		-- reloads the latches from BTCMPR on the next edge. That is the
		-- quickest way back to a 10-count period from BTCMPR0 = 1000.
		--------------------------------------------------
		REPORT "--- BTINT mux ---" SEVERITY note;
		btcmpr0	<= STD_LOGIC_VECTOR(to_unsigned(9, N));
		rst		<= '1';
		step(2);
		rst		<= '0';
		btctl1	<= ctl1('0','1','0', SS_1, '0', BI_EQU0);
		btctl2	<= ctl2(CM_OFF, CS_GND);
		step(2);

		align;
		checkb("BTINT=EQU0, BTIFG at cnt=0", btifg, '0');
		step(9);	checkb("BTINT=EQU0, BTIFG at cnt=9", btifg, '1');
		step(1);	checkb("BTINT=EQU0, BTIFG at cnt=0", btifg, '0');

		btctl1	<= ctl1('0','1','0', SS_1, '0', BI_EQU1);
		align;
		checkb("BTINT=EQU1, BTIFG at cnt=0", btifg, '0');
		step(4);	checkb("BTINT=EQU1, BTIFG at cnt=4", btifg, '0');
		step(1);	checkb("BTINT=EQU1, BTIFG at cnt=5", btifg, '1');
		step(4);	checkb("BTINT=EQU1, BTIFG at cnt=9", btifg, '1');
		step(1);	checkb("BTINT=EQU1, BTIFG at cnt=0", btifg, '0');

		btctl1	<= ctl1('0','1','0', SS_1, '0', BI_CAP);
		btctl2	<= ctl2(CM_RISE, CS_GND);
		step(5);
		checkb("BTINT=capture, BTIFG idle", btifg, '0');
		btctl2	<= ctl2(CM_RISE, CS_VCC);
		step(2);	checkb("BTINT=capture, BTIFG on the event", btifg, '1');
		step(1);	checkb("BTINT=capture, BTIFG after the event", btifg, '0');

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
