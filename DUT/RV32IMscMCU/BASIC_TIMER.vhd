--============================================================================
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- BASIC_TIMER - the Basic Timer with output comparing capabilities, Fig.7
--
-- This is the whole shaded block of Fig.7 plus the registers drawn touching
-- it. It is pure structure: five components, the two BTCL latches, the BTCTL
-- bit decode and the BTIFG mux. No arithmetic happens in this file.
--
--                         BTCMPR0        BTCMPR1
--                            |              |
--                     [Latch BTCL0]  [Latch BTCL1]   <- both enabled by EQU0
--                            |              |
--   SMCLK -> [BT_CLKDIV] -> BTCLK           |
--                            |              |
--                        [BTCNT] --BTCNT--> [BT_OUTPUT_UNIT] -> PWMout
--                            ^                  |     |
--                            +----- EQU0 -------+     +-- EQU1
--                                                 |
--   CAPIN1/2 -> [BT_CAPTURE] -> BTCAPR, capture event
--                                                 |
--                              BTINT -> [ 4:1 mux ] -> BTIFG
--
-- THE INTERFACE IS THE FIGURE, NOT A BUS. BTCTL1, BTCTL2, BTCMPR0 and
-- BTCMPR1 arrive as plain vectors and BTCAPR, BTCNT, PWMout and BTIFG leave
-- as plain vectors, exactly as Fig.7 draws them. The memory-mapped wrapper
-- that decodes I/O addresses onto these ports is deliberately NOT here: that
-- belongs in MCU.vhd, which is being changed on feature/gpio at the moment.
-- Keeping the split here means the two branches cannot collide.
--
-- WHY THE LATCHES ARE SELF-STARTING. BTCL0 resets to 0 and EQU0 is
-- "BTCNT >= BTCL0", so straight after reset EQU0 is already true. The first
-- BTCLK edge therefore loads BTCMPR0 into BTCL0 and BTCMPR1 into BTCL1, and
-- from the edge after that the timer runs with the programmed period. No
-- start-up state machine is needed - the reset value does the work.
--
-- WHY THE COMPARE VALUES ARE DOUBLE BUFFERED. Software writes BTCMPR0 and
-- BTCMPR1 at any moment, but the latches only copy them into BTCL0/BTCL1 when
-- EQU0 marks the end of a period ("HEU0='1'" in Fig.7, which is EQU0 - the
-- figure also writes the counter output as "EUQ0"). Changing the duty cycle
-- mid-period therefore cannot produce a short or a stretched pulse; the new
-- value takes effect cleanly at the next period boundary.
--
-- REGISTER MAP, from the bit tables on page 7 of the task definition:
--
--   BTCTL1   7 BTOUTMD | 6 BTOUTEN | 5 BTHOLD | 4:3 BTSSEL | 2 BTCLR | 1:0 BTINT
--   BTCTL2   7:4 reserved, read as 0         | 3:2 CAPMD  | 1:0 CAPISEL
--
--   BTINT   {0: EQU0, 1: EQU1, 2 and 3: capture event}   -- "three options"
--   BTSSEL  {0: SMCLK, 1: SMCLK:2, 2: SMCLK:4, 3: SMCLK:8}
--   CAPISEL {0: CAPIN1, 1: CAPIN2, 2: VCC, 3: GND}
--   CAPMD   {0,3: disabled, 1: rising edge, 2: falling edge}
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;


ENTITY basic_timer IS
	GENERIC(
		N : positive := 32
	);
	PORT(
		--Clock and reset
		smclk_i		: IN 	STD_LOGIC;
		rst_i		: IN 	STD_LOGIC;

		--Control registers
		btctl1_i	: IN 	STD_LOGIC_VECTOR(7 DOWNTO 0);
		btctl2_i	: IN 	STD_LOGIC_VECTOR(7 DOWNTO 0);

		--Compare registers
		btcmpr0_i	: IN 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
		btcmpr1_i	: IN 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);

		--Capture inputs
		capin1_i	: IN 	STD_LOGIC;
		capin2_i	: IN 	STD_LOGIC;

		--Outputs
		pwmout_o	: OUT	STD_LOGIC;
		btifg_o		: OUT	STD_LOGIC;
		btcapr_o	: OUT	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
		btcnt_o		: OUT	STD_LOGIC_VECTOR(N-1 DOWNTO 0);	-- readback

		-- The capture event, one BTCLK wide, straight out of BT_CAPTURE's
		-- CAPMD trigger select. It was already computed and already used
		-- inside this block - it is the "10"/"11" input of the BTINT mux
		-- below - and this port only exposes it. No logic changed.
		--
		-- It exists because forum row 25 makes BTCAPR read/write: "All of the
		-- timer's interface registers are readable and writable, except the
		-- four high bits of BTCTL2". A writable BTCAPR has to live in
		-- BASIC_TIMER_INTERFACE as a register loadable from two sources - the
		-- bus on a store, and the timer on a capture - and the second source
		-- needs to know WHEN a capture happened. Watching btcapr_o for a
		-- change cannot substitute: a periodic capture that records the same
		-- count every period never changes it, which is exactly what test4's
		-- input-capture mode does.
		capevt_o	: OUT	STD_LOGIC
	);
END basic_timer;


ARCHITECTURE struct OF basic_timer IS
	--BTCTL1 fields
	SIGNAL btoutmd_w	: STD_LOGIC;
	SIGNAL btouten_w	: STD_LOGIC;
	SIGNAL bthold_w		: STD_LOGIC;
	SIGNAL btssel_w		: STD_LOGIC_VECTOR(1 DOWNTO 0);
	SIGNAL btclr_w		: STD_LOGIC;
	SIGNAL btint_w		: STD_LOGIC_VECTOR(1 DOWNTO 0);

	--BTCTL2 fields
	SIGNAL capmd_w		: STD_LOGIC_VECTOR(1 DOWNTO 0);
	SIGNAL capisel_w	: STD_LOGIC_VECTOR(1 DOWNTO 0);

	--Internal nets
	SIGNAL btclk_w		: STD_LOGIC;
	SIGNAL cnt_w		: STD_LOGIC_VECTOR(N-1 DOWNTO 0);
	SIGNAL btcl0_q		: STD_LOGIC_VECTOR(N-1 DOWNTO 0);
	SIGNAL btcl1_q		: STD_LOGIC_VECTOR(N-1 DOWNTO 0);
	SIGNAL equ0_w		: STD_LOGIC;
	SIGNAL equ1_w		: STD_LOGIC;
	SIGNAL capevt_w		: STD_LOGIC;

BEGIN
	--=======================================
	-- Control register decode
	--=======================================
	btoutmd_w	<= btctl1_i(7);
	btouten_w	<= btctl1_i(6);
	bthold_w	<= btctl1_i(5);
	btssel_w	<= btctl1_i(4 DOWNTO 3);
	btclr_w		<= btctl1_i(2);
	btint_w		<= btctl1_i(1 DOWNTO 0);

	capmd_w		<= btctl2_i(3 DOWNTO 2);
	capisel_w	<= btctl2_i(1 DOWNTO 0);

	--=======================================
	-- BTSSEL clock select
	--=======================================
	CLKDIV: ENTITY work.bt_clkdiv
	PORT MAP (
		smclk_i		=> smclk_i,
		rst_i		=> rst_i,
		sel_i		=> btssel_w,
		btclk_o		=> btclk_w
	);

	--=======================================
	-- Latch BTCL0 / Latch BTCL1
	--
	-- One process for both because Fig.7 gives them the same enable, EQU0.
	--=======================================
	LATCH: PROCESS (btclk_w, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			btcl0_q	<= (OTHERS => '0');
			btcl1_q	<= (OTHERS => '0');
		ELSIF rising_edge(btclk_w) THEN
			IF equ0_w = '1' THEN
				btcl0_q	<= btcmpr0_i;
				btcl1_q	<= btcmpr1_i;
			END IF;
		END IF;
	END PROCESS;

	--=======================================
	-- BTCNT 32-bit timer
	--=======================================
	CNTR: ENTITY work.btcnt
	GENERIC MAP (
		N			=> N
	)
	PORT MAP (
		btclk_i		=> btclk_w,
		rst_i		=> rst_i,
		clr_i		=> btclr_w,
		hold_i		=> bthold_w,
		equ0_i		=> equ0_w,
		cnt_o		=> cnt_w
	);

	--=======================================
	-- Output unit: both comparators and the PWM waveform
	--=======================================
	OUTU: ENTITY work.bt_output_unit
	GENERIC MAP (
		N			=> N
	)
	PORT MAP (
		btclk_i		=> btclk_w,
		rst_i		=> rst_i,
		cnt_i		=> cnt_w,
		btcl0_i		=> btcl0_q,
		btcl1_i		=> btcl1_q,
		btoutmd_i	=> btoutmd_w,
		btouten_i	=> btouten_w,
		equ0_o		=> equ0_w,
		equ1_o		=> equ1_w,
		pwmout_o	=> pwmout_o
	);

	--=======================================
	-- Input capture
	--=======================================
	CAPT: ENTITY work.bt_capture
	GENERIC MAP (
		N			=> N
	)
	PORT MAP (
		btclk_i		=> btclk_w,
		rst_i		=> rst_i,
		capin1_i	=> capin1_i,
		capin2_i	=> capin2_i,
		capisel_i	=> capisel_w,
		capmd_i		=> capmd_w,
		cnt_i		=> cnt_w,
		btcapr_o	=> btcapr_o,
		capevt_o	=> capevt_w
	);

	--=======================================
	-- BTINT interrupt source mux.
	-- Fig.7 ties inputs 10 and 11 to the same capture event line, which is
	-- what makes BTINT "three options" rather than four.
	--=======================================
	WITH btint_w SELECT
		btifg_o	<=	equ0_w		WHEN "00",
					equ1_w		WHEN "01",
					capevt_w	WHEN "10",
					capevt_w	WHEN "11",
					'0'			WHEN OTHERS;

	--=======================================
	btcnt_o	<= cnt_w;

	-- See the note at the port declaration: an extra consumer of a signal the
	-- BTINT mux above already uses, nothing more.
	capevt_o	<= capevt_w;

END struct;
