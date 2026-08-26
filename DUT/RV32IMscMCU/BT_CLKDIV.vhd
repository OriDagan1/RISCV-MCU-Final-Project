--============================================================================
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- BT_CLKDIV - the BTSSEL clock source select of the Basic Timer: the divider
-- chain and the 4-way mux drawn on the left of Fig.7, feeding the CLK pin of
-- BTCNT.
--
--   SMCLK     ->| 00 |
--   SMCLK : 2 ->| 01 |
--   SMCLK : 4 ->| 10 |--> BTCLK   (the clock BTCNT actually runs on)
--   SMCLK : 8 ->| 11 |
--                  ^
--                BTSSEL
--
-- The divided clocks are taps of one SYNCHRONOUS binary counter, not a ripple
-- chain of flip-flops each clocking the next. Both give /2, /4 and /8 at 50%
-- duty, but in a ripple chain every stage adds another clock-to-output delay,
-- so SMCLK:8 would lag SMCLK by three delays and the four mux inputs would be
-- skewed relative to each other. Taps of one counter all change on the same
-- SMCLK edge.
--
--   div_q     : 000 001 010 011 100 101 110 111 000 ...
--   div_q(0)  :  0   1   0   1   0   1   0   1   0     SMCLK : 2
--   div_q(1)  :  0   0   1   1   0   0   1   1   0     SMCLK : 4
--   div_q(2)  :  0   0   0   0   1   1   1   1   0     SMCLK : 8
--
-- TWO THINGS THIS COSTS, both inherent to the figure rather than to this code:
--
-- 1. BTCLK is a generated clock, so Quartus needs to be told about it. The
--    .sdc must carry, alongside the create_generated_clock for MCLK:
--        create_generated_clock -name BTCLK_DIV2 -source [SMCLK] -divide_by 2 ...
--        create_generated_clock -name BTCLK_DIV4 -source [SMCLK] -divide_by 4 ...
--        create_generated_clock -name BTCLK_DIV8 -source [SMCLK] -divide_by 8 ...
--    and set_clock_groups -exclusive on them, since only one reaches BTCNT at
--    a time and TimeQuest would otherwise time paths between them.
--
-- 2. A combinational mux between two running clocks can emit a runt pulse on
--    the cycle BTSSEL changes, which would clock BTCNT with a pulse shorter
--    than its setup time. SOFTWARE RULE: program BTSSEL while the timer is
--    stopped - either with BTHOLD = '1' or with BTCLR = '1' - and only then
--    release it. Writing BTSSEL on a running timer risks one corrupt count.
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;


ENTITY bt_clkdiv IS
	PORT(
		smclk_i		: IN 	STD_LOGIC;						-- SMCLK, the source
		rst_i		: IN 	STD_LOGIC;						-- asynchronous reset
		sel_i		: IN 	STD_LOGIC_VECTOR(1 DOWNTO 0);	-- BTSSEL

		btclk_o		: OUT	STD_LOGIC						-- to the CLK pin of BTCNT
	);
END bt_clkdiv;


ARCHITECTURE behavioral OF bt_clkdiv IS
	SIGNAL div_q	: unsigned(2 DOWNTO 0);		-- /8 is the deepest division

BEGIN
	--=======================================
	-- Divider chain
	--=======================================
	PROCESS (smclk_i, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			div_q	<= (OTHERS => '0');
		ELSIF rising_edge(smclk_i) THEN
			div_q	<= div_q + 1;
		END IF;
	END PROCESS;

	--=======================================
	-- The BTSSEL mux
	--=======================================
	WITH sel_i SELECT
		btclk_o	<=	smclk_i		WHEN "00",		-- SMCLK
					div_q(0)	WHEN "01",		-- SMCLK : 2
					div_q(1)	WHEN "10",		-- SMCLK : 4
					div_q(2)	WHEN "11",		-- SMCLK : 8
					smclk_i		WHEN OTHERS;

END behavioral;
