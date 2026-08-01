--============================================================================
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- CDC_SYNC module - single-bit clock domain crossing synchronizer (Fig.10)
--
-- Three flip-flops in two clock domains:
--
--        domain A (src_clk)      |       domain B (dst_clk)
--   src_bit_i --[ din_q ]--------|--[ ds_q ]--[ dout_q ]--> dst_bit_o
--                launch          |   may be     stable
--                                |  metastable
--
-- din_q gives the crossing a clean register-to-register launch point, so a
-- combinational source in domain A cannot present a glitching value to the
-- destination. ds_q is the flop that is allowed to go metastable; dout_q
-- samples it one destination cycle later, by which time it has settled.
--
-- SINGLE BIT ONLY. Never widen this to a bus: two bits sampled at the same
-- moment can resolve on different destination cycles, so the destination
-- would briefly see a value that never existed in the source. Multi-bit
-- data is crossed by holding it stable and synchronizing one control bit
-- (which is exactly how Dividend/Divisor and Quotient/Residue are handled
-- around the division accelerator).
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;


ENTITY cdc_sync IS
	PORT(
		--Source domain (domain A)
		src_clk_i	: IN 	STD_LOGIC;
		src_rst_i	: IN 	STD_LOGIC;
		src_bit_i	: IN 	STD_LOGIC;

		--Destination domain (domain B)
		dst_clk_i	: IN 	STD_LOGIC;
		dst_rst_i	: IN 	STD_LOGIC;
		dst_bit_o	: OUT	STD_LOGIC
	);
END cdc_sync;


ARCHITECTURE sync OF cdc_sync IS
	SIGNAL din_q	: STD_LOGIC;	-- domain A launch register
	SIGNAL ds_q		: STD_LOGIC;	-- domain B stage 1, may go metastable
	SIGNAL dout_q	: STD_LOGIC;	-- domain B stage 2, stable

	-- Quartus must not merge, duplicate or retime the chain, and it must
	-- recognise it as a synchronizer so the src->dst path is excluded from
	-- static timing analysis instead of reported as a failing path.
	ATTRIBUTE preserve : BOOLEAN;
	ATTRIBUTE preserve OF ds_q		: SIGNAL IS TRUE;
	ATTRIBUTE preserve OF dout_q	: SIGNAL IS TRUE;

	ATTRIBUTE altera_attribute : STRING;
	ATTRIBUTE altera_attribute OF ds_q : SIGNAL IS
		"-name SYNCHRONIZER_IDENTIFICATION ""FORCED IF ASYNCHRONOUS""";

BEGIN
	--=======================================
	-- Domain A : launch register
	--=======================================
	PROCESS (src_clk_i, src_rst_i)
	BEGIN
		IF src_rst_i = '1' THEN
			din_q	<= '0';
		ELSIF rising_edge(src_clk_i) THEN
			din_q	<= src_bit_i;
		END IF;
	END PROCESS;

	--=======================================
	-- Domain B : two-stage synchronizer
	--=======================================
	PROCESS (dst_clk_i, dst_rst_i)
	BEGIN
		IF dst_rst_i = '1' THEN
			ds_q	<= '0';
			dout_q	<= '0';
		ELSIF rising_edge(dst_clk_i) THEN
			ds_q	<= din_q;
			dout_q	<= ds_q;
		END IF;
	END PROCESS;

	--=======================================
	dst_bit_o <= dout_q;

END sync;
