--============================================================================
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- BT_CAPTURE - the input capture chain along the bottom of Fig.7: the CAPISEL
-- source mux, the "Capture Mode" block, the edge detector and the
-- "BTCNT_CAPTURE on event register" that drives BTCAPR.
--
--   CAPIN1 ->| 00 |
--   CAPIN2 ->| 01 |      +---------+   ___
--   VCC    ->| 10 |----->| Capture |--/   |--> [ BTCNT_CAPTURE ] --> BTCAPR
--   GND    ->| 11 |      |  Mode   |      |          ^
--               ^        +---------+                 |
--            CAPISEL          ^                    BTCNT
--                           CAPMD
--
-- CAPISEL {0: CAPIN1, 1: CAPIN2, 2: VCC('1'), 3: GND('0')}
-- CAPMD   {0,3: capture disabled, 1: rising edge, 2: falling edge}
--
-- The constant VCC and GND sources look pointless but are the standard way to
-- test the path from software: select GND then VCC with CAPMD set to rising
-- and you have forced a capture event without any external stimulus.
--
-- SYNCHRONIZING THE INPUT. CAPIN1 and CAPIN2 are external pins with no clock
-- of their own, so they can change at any point inside a BTCLK period and
-- would otherwise drive a flip-flop into metastability. sync_q(0) and
-- sync_q(1) are an ordinary two-flop synchronizer; sync_q(2) is one more copy
-- so an edge can be spotted by comparing two adjacent samples.
--
-- This is why the project's cdc_sync component is NOT used here: that one
-- crosses between two known clocks and needs a source clock to launch from.
-- A free-running pin has none, so the two flops live entirely in the BTCLK
-- domain.
--
--   sync_q(1)  sync_q(2)   meaning
--   ---------  ---------   --------------
--       1          0       rising edge
--       0          1       falling edge
--
-- CAPTURE RESOLUTION. Everything here runs on BTCLK, not SMCLK, because the
-- value being captured is BTCNT and a capture register has to be in the same
-- clock domain as the counter it samples. The consequence is that at
-- BTSSEL = 11 the input is only sampled every eighth SMCLK, so a pulse
-- narrower than two BTCLK periods can be missed. That is inherent to the
-- figure - use a faster BTSSEL when capturing narrow pulses.
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;


ENTITY bt_capture IS
	GENERIC(
		N : positive := 32
	);
	PORT(
		btclk_i		: IN 	STD_LOGIC;						-- from the BTSSEL mux
		rst_i		: IN 	STD_LOGIC;						-- asynchronous reset
		capin1_i	: IN 	STD_LOGIC;						-- external pin
		capin2_i	: IN 	STD_LOGIC;						-- external pin
		capisel_i	: IN 	STD_LOGIC_VECTOR(1 DOWNTO 0);	-- CAPISEL
		capmd_i		: IN 	STD_LOGIC_VECTOR(1 DOWNTO 0);	-- CAPMD
		cnt_i		: IN 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);	-- BTCNT

		btcapr_o	: OUT	STD_LOGIC_VECTOR(N-1 DOWNTO 0);	-- BTCAPR
		capevt_o	: OUT	STD_LOGIC						-- to the BTIFG mux
	);
END bt_capture;


ARCHITECTURE behavioral OF bt_capture IS
	SIGNAL cap_src_w	: STD_LOGIC;
	SIGNAL sync_q		: STD_LOGIC_VECTOR(2 DOWNTO 0);
	SIGNAL rise_w		: STD_LOGIC;
	SIGNAL fall_w		: STD_LOGIC;
	SIGNAL capevt_w		: STD_LOGIC;
	SIGNAL btcapr_q		: STD_LOGIC_VECTOR(N-1 DOWNTO 0);

	-- Quartus must not optimise the synchronizer away or retime through it
	ATTRIBUTE preserve : BOOLEAN;
	ATTRIBUTE preserve OF sync_q : SIGNAL IS TRUE;

BEGIN
	--=======================================
	-- CAPISEL source mux
	--=======================================
	WITH capisel_i SELECT
		cap_src_w	<=	capin1_i	WHEN "00",
						capin2_i	WHEN "01",
						'1'			WHEN "10",		-- VCC
						'0'			WHEN "11",		-- GND
						'0'			WHEN OTHERS;

	--=======================================
	-- Two-flop synchronizer plus one delayed copy for edge detection
	--=======================================
	PROCESS (btclk_i, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			sync_q	<= (OTHERS => '0');
		ELSIF rising_edge(btclk_i) THEN
			sync_q	<= sync_q(1 DOWNTO 0) & cap_src_w;
		END IF;
	END PROCESS;

	rise_w	<=      sync_q(1) AND NOT sync_q(2);
	fall_w	<= NOT  sync_q(1) AND     sync_q(2);

	--=======================================
	-- CAPMD trigger select
	--=======================================
	WITH capmd_i SELECT
		capevt_w	<=	'0'			WHEN "00",		-- disabled
						rise_w		WHEN "01",		-- rising edge
						fall_w		WHEN "10",		-- falling edge
						'0'			WHEN "11",		-- disabled
						'0'			WHEN OTHERS;

	--=======================================
	-- BTCNT_CAPTURE on event register
	--=======================================
	PROCESS (btclk_i, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			btcapr_q	<= (OTHERS => '0');
		ELSIF rising_edge(btclk_i) THEN
			IF capevt_w = '1' THEN
				btcapr_q	<= cnt_i;
			END IF;
		END IF;
	END PROCESS;

	--=======================================
	btcapr_o	<= btcapr_q;
	capevt_o	<= capevt_w;

END behavioral;
