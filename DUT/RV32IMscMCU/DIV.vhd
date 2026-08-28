--============================================================================
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- DIVIDER module - unsigned binary multicycle division accelerator (Fig.9)
--
-- Restoring division. A single 2N-bit left-shift register holds
-- {Residue, Dividend}: the dividend is loaded into the low half and the
-- partial residue accumulates in the high half. Each DIVCLK cycle the
-- register shifts left by one and the subtractor tests the high half
-- against the divisor; the Non_neg result is both the decision to keep the
-- subtraction and the quotient bit shifted in from the right.
--
-- Timing: DIVBUSY rises on the DIVCLK edge that loads the operands and
-- falls N DIVCLK cycles later. Quotient/Residue are valid from that point
-- until the next load.
--
-- Division by zero needs no special case: the algorithm naturally yields
-- Quotient = all ones and Residue = Dividend, which is exactly what the
-- RISC-V spec requires of divu/remu. Measured, not assumed - with
-- divisor_q = 0 the subtractor never borrows, so Non_neg is '1' on all N
-- steps and a '1' shifts into the quotient on each of them.
--
-- WHERE FIGURE 9'S DIVRST FUNCTION ACTUALLY LIVES. The forum defines DIVRST
-- as the line that initialises this core's internal registers - the Quotient
-- register and the {Residue,Dividend} shift register holding the Dividend and
-- Divisor - at the start of each division, once per div/divu/rem/remu. That
-- initialisation is the start_w load branch below, NOT the DIVRST port: the
-- port is the ordinary asynchronous system reset, and DIV_ACCEL.vhd ties it
-- to rst_i.
--
-- The two cannot be merged. DIVRST arrives here as an asynchronous CLEAR, so
-- pulsing it once per division would zero shreg_q - including the dividend
-- that the same pulse is supposed to load into it - and would race the load
-- branch. Loading and clearing are opposite operations on the same registers;
-- start_w is the load, DIVRST is the clear, and the divider needs both.
--
-- CDC note: Dividend, Divisor and DIVENA cross from the MCLK domain. Only
-- DIVENA needs synchronizing (Fig.10) - the operand buses are captured by
-- the load edge, which the synchronizer delays until well after the CPU
-- has driven them.
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;


ENTITY divider IS
	generic(
		N : positive := 32
	);
	PORT(
		--Inputs
		Dividend 	: IN 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
		Divisor 	: IN 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);

		DIVCLK		: IN 	STD_LOGIC;
		DIVRST		: IN 	STD_LOGIC;
		DIVENA		: IN 	STD_LOGIC;

		--Outputs
		Quotient	: OUT 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
		Residue		: OUT 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);

		DIVBUSY		: OUT 	STD_LOGIC
	);
END divider;


ARCHITECTURE div OF divider IS
	CONSTANT ZEROS_N	: STD_LOGIC_VECTOR(N-1 DOWNTO 0) := (OTHERS => '0');

	-- Registers
	SIGNAL shreg_q		: STD_LOGIC_VECTOR(2*N-1 DOWNTO 0);	-- {Residue,Dividend}
	SIGNAL divisor_q	: STD_LOGIC_VECTOR(N-1 DOWNTO 0);
	SIGNAL quotient_q	: STD_LOGIC_VECTOR(N-1 DOWNTO 0);
	SIGNAL step_cnt_q	: INTEGER RANGE 0 TO N;
	SIGNAL busy_q		: STD_LOGIC;
	SIGNAL divena_q		: STD_LOGIC;						-- DIVENA edge detect

	-- Combinational
	SIGNAL start_w		: STD_LOGIC;
	SIGNAL shifted_w	: STD_LOGIC_VECTOR(2*N-1 DOWNTO 0);
	SIGNAL sub_res_w	: STD_LOGIC_VECTOR(N-1 DOWNTO 0);
	SIGNAL non_neg_w	: STD_LOGIC;

	COMPONENT subtractor IS
		generic(
			N : positive := 32
		);
		PORT(
			X 		: IN 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
			Y		: IN 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
			Res 	: OUT 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
			Non_neg	: OUT 	STD_LOGIC
		);
	END COMPONENT;

BEGIN
	--=======================================
	-- Start pulse - this is Fig.9's DIVRST, see the header
	--=======================================
	-- DIVENA arrives from the slow MCLK domain and stays high for several
	-- DIVCLK cycles, so it is edge-detected. Without this the divider would
	-- restart on every cycle that DIVENA is held.
	start_w		<= DIVENA AND (NOT divena_q) AND (NOT busy_q);

	--=======================================
	-- Dividend left shift-register (combinational shift)
	--=======================================
	shifted_w	<= shreg_q(2*N-2 DOWNTO 0) & '0';

	--=======================================
	-- SUBTRACTOR module connection
	--=======================================
	SUB: subtractor
	generic map(
		N		=> N
	)
	PORT MAP (
		--Inputs
		X		=> divisor_q,
		Y		=> shifted_w(2*N-1 DOWNTO N),

		--Outputs
		Res		=> sub_res_w,
		Non_neg	=> non_neg_w
	);

	--=======================================
	-- Multicycle control and datapath registers
	--=======================================
	PROCESS (DIVCLK, DIVRST)
	BEGIN
		IF DIVRST = '1' THEN
			shreg_q		<= (OTHERS => '0');
			divisor_q	<= (OTHERS => '0');
			quotient_q	<= (OTHERS => '0');
			step_cnt_q	<= 0;
			busy_q		<= '0';
			divena_q	<= '0';

		ELSIF rising_edge(DIVCLK) THEN
			divena_q <= DIVENA;

			IF start_w = '1' THEN
				-- Load: dividend into the low half, residue cleared
				shreg_q		<= ZEROS_N & Dividend;
				divisor_q	<= Divisor;
				quotient_q	<= (OTHERS => '0');
				step_cnt_q	<= N;
				busy_q		<= '1';

			ELSIF busy_q = '1' THEN
				-- One restoring step: keep the subtraction only if it did
				-- not borrow, otherwise leave the shifted value in place
				IF non_neg_w = '1' THEN
					shreg_q	<= sub_res_w & shifted_w(N-1 DOWNTO 0);
				ELSE
					shreg_q	<= shifted_w;
				END IF;

				quotient_q	<= quotient_q(N-2 DOWNTO 0) & non_neg_w;
				step_cnt_q	<= step_cnt_q - 1;

				IF step_cnt_q = 1 THEN
					busy_q	<= '0';
				END IF;
			END IF;
		END IF;
	END PROCESS;

	--=======================================
	Quotient	<= quotient_q;
	Residue		<= shreg_q(2*N-1 DOWNTO N);
	DIVBUSY		<= busy_q;

END div;
