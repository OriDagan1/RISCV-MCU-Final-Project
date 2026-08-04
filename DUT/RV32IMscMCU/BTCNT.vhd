--============================================================================
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- BTCNT - the 32-bit up-counter of the Basic Timer (the "BTCNT 32-bit Timer
-- (Up-Mode)" block in the middle of Fig.7)
--
-- This is the timer and nothing else: no comparator, no PWM logic, no capture
-- logic. Fig.7 puts both comparators inside the Output Unit and routes EQU0
-- back into this block, so the wrap arrives here as an input rather than
-- being decided here. Keeping the counter standalone is what makes it
-- reusable and each block independently testable.
--
-- The four pins of the block in Fig.7 map straight onto the ports:
--
--        BTCLR ------->|                                |
--        BTHOLD ------>|EN   BTCNT 32-bit Timer         |----> cnt_o
--        BTCLK ------->|CLK           (Up-Mode)    EQU0 |<---- equ0_i
--
-- Up-mode, as Fig.8 draws it: the count ramps 0,1,2.. and the Output Unit
-- raises EQU0 when it reaches BTCL0, which sends it back to 0 on the next
-- BTCLK edge. One period is therefore BTCL0+1 clocks.
--
--   cnt |      /|      /|      /|
--       |    /  |    /  |    /  |        top of the ramp = BTCL0
--       |  /    |  /    |  /    |
--     0 |/______|/______|/______|
--         equ0_i is high here ^ , for one BTCLK
--
-- Priority of the controls, highest first:
--   rst_i    asynchronous, the board reset. "The register value is zero on
--            RESET" (task definition, page 8)
--   clr_i    BTCLR. Synchronous, and outranks BTHOLD, so a frozen counter can
--            still be cleared
--   hold_i   BTHOLD. Freezes the count. Fig.7 draws this as the active-low EN
--            pin, so the polarity is inverted at the port: the name matches
--            the control BIT, and hold_i = '1' means frozen. While frozen the
--            counter ignores equ0_i as well - it is stopped, not paused
--            mid-wrap
--   equ0_i   the wrap from the Output Unit
--
-- NOTE ON THE CLOCK: btclk_i is a generated, run-time selectable clock coming
-- out of the BTSSEL mux in BT_CLKDIV.vhd. See that file for the .sdc
-- constraints it needs and for the rule about when BTSSEL may be written.
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;


ENTITY btcnt IS
	GENERIC(
		N : positive := 32
	);
	PORT(
		btclk_i		: IN 	STD_LOGIC;						-- CLK, from the BTSSEL mux
		rst_i		: IN 	STD_LOGIC;						-- asynchronous reset
		clr_i		: IN 	STD_LOGIC;						-- BTCLR
		hold_i		: IN 	STD_LOGIC;						-- BTHOLD, '1' = freeze
		equ0_i		: IN 	STD_LOGIC;						-- wrap, from the Output Unit

		cnt_o		: OUT	STD_LOGIC_VECTOR(N-1 DOWNTO 0)	-- BTCNT
	);
END btcnt;


ARCHITECTURE behavioral OF btcnt IS
	SIGNAL cnt_q	: unsigned(N-1 DOWNTO 0);

BEGIN
	--=======================================
	-- The counter
	--=======================================
	PROCESS (btclk_i, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			cnt_q	<= (OTHERS => '0');

		ELSIF rising_edge(btclk_i) THEN
			IF clr_i = '1' THEN
				cnt_q	<= (OTHERS => '0');

			ELSIF hold_i = '0' THEN
				IF equ0_i = '1' THEN
					cnt_q	<= (OTHERS => '0');
				ELSE
					cnt_q	<= cnt_q + 1;
				END IF;
			END IF;
		END IF;
	END PROCESS;

	--=======================================
	cnt_o	<= STD_LOGIC_VECTOR(cnt_q);

END behavioral;
