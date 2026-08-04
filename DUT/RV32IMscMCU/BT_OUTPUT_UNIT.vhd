--============================================================================
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- BT_OUTPUT_UNIT - the "Output Unit" block of Fig.7
--
-- Holds BOTH comparators. Fig.7 draws EQU0 and EQU1 leaving this block and
-- fanning out: EQU0 goes back to BTCNT to wrap the count and up to the BTCL0
-- and BTCL1 latch enables, EQU1 goes to the BTIFG mux, and both are used here
-- to build the PWM waveform.
--
--   BTCNT ---->|              |
--   BTCL0 ---->| Output Unit  |----> PWMout
--   BTCL1 ---->|              |----> EQU0, EQU1
--   BTCLK ---->|              |
--   BTOUTMD -->|              |
--   BTOUTEN -->|              |
--
-- THE TWO PWM MODES (Fig.8). BTCL0 is the top of the ramp, BTCL1 the
-- threshold part-way up it, and the output changes at each crossing:
--
--   event   Mode 0 "Set/Reset"   Mode 1 "Reset/Set"   so the output takes
--   -----   ------------------   ------------------   ------------------
--   EQU1    set   -> '1'         reset -> '0'         NOT BTOUTMD
--   EQU0    reset -> '0'         set   -> '1'             BTOUTMD
--
-- which is why the two assignments below are simply BTOUTMD and its inverse
-- rather than a four-way case: mode 1 is the mirror image of mode 0, so the
-- mode bit IS the level the output takes at the end of a period.
--
-- EQU0 IS TESTED FIRST, AND MUST BE. Both comparators are ">=", so at the top
-- of the ramp EQU1 and EQU0 are true together. If EQU1 were tested first the
-- output would set and never reset, and the PWM would stick high after one
-- period.
--
-- WHY ">=" AND NOT "=". BTCL0 and BTCL1 are reloaded from BTCMPR0/BTCMPR1
-- while the timer runs, so if software shortens the period the count can
-- already be past the new value. With "=" the comparison would miss and the
-- timer would run to 0xFFFFFFFF before wrapping; with ">=" it restarts on the
-- next edge. In steady state the count never exceeds BTCL0, so the two are
-- identical - this only covers the reload case. Same guard as the LAB4 PWM.
--
-- DEGENERATE SETTINGS, both harmless and both left to behave predictably
-- rather than being special-cased:
--   BTCL1 >= BTCL0   EQU0 wins every time, so Mode 0 stays low (0% duty) and
--                    Mode 1 stays high (100% duty)
--   BTCL1 = 0        EQU1 is true from the first count, so the output flips
--                    one clock into the period (nearly 100% / 0% duty)
--
-- PWMout IS REGISTERED. Fig.8 draws the edges exactly on the crossings; here
-- they land one BTCLK later. That is deliberate: a combinational output would
-- glitch on every comparator transition, which on a real pin is a spike.
-- The one-clock skew is constant and does not affect the duty cycle.
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;


ENTITY bt_output_unit IS
	GENERIC(
		N : positive := 32
	);
	PORT(
		btclk_i		: IN 	STD_LOGIC;						-- from the BTSSEL mux
		rst_i		: IN 	STD_LOGIC;						-- asynchronous reset
		cnt_i		: IN 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);	-- BTCNT
		btcl0_i		: IN 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);	-- top of the ramp
		btcl1_i		: IN 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);	-- threshold
		btoutmd_i	: IN 	STD_LOGIC;						-- 0: Set/Reset, 1: Reset/Set
		btouten_i	: IN 	STD_LOGIC;						-- '0' freezes PWMout

		equ0_o		: OUT	STD_LOGIC;						-- count reached BTCL0
		equ1_o		: OUT	STD_LOGIC;						-- count reached BTCL1
		pwmout_o	: OUT	STD_LOGIC
	);
END bt_output_unit;


ARCHITECTURE behavioral OF bt_output_unit IS
	SIGNAL equ0_w	: STD_LOGIC;
	SIGNAL equ1_w	: STD_LOGIC;
	SIGNAL pwm_q	: STD_LOGIC;

BEGIN
	--=======================================
	-- The two comparators
	--=======================================
	equ0_w	<= '1' WHEN unsigned(cnt_i) >= unsigned(btcl0_i) ELSE '0';
	equ1_w	<= '1' WHEN unsigned(cnt_i) >= unsigned(btcl1_i) ELSE '0';

	--=======================================
	-- PWM output
	--
	-- BTOUTEN = '0' holds the last value, which is also the reset state, so a
	-- pin driven by PWMout stays parked until software enables the timer.
	--
	-- NOTE FOR THE REVIEW: the task definition describes this bit only as
	-- "BTOUTEN: hold the PWMout signal value" without giving its active
	-- level. Read as an output ENable, as the name says: '1' lets the output
	-- update, '0' freezes it. If the intended sense turns out to be the
	-- opposite, invert the test on the next line and nothing else changes.
	--=======================================
	PROCESS (btclk_i, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			pwm_q	<= '0';

		ELSIF rising_edge(btclk_i) THEN
			IF btouten_i = '1' THEN
				IF equ0_w = '1' THEN
					pwm_q	<= btoutmd_i;		-- end of period
				ELSIF equ1_w = '1' THEN
					pwm_q	<= NOT btoutmd_i;	-- threshold crossing
				END IF;
			END IF;
		END IF;
	END PROCESS;

	--=======================================
	equ0_o		<= equ0_w;
	equ1_o		<= equ1_w;
	pwmout_o	<= pwm_q;

END behavioral;
