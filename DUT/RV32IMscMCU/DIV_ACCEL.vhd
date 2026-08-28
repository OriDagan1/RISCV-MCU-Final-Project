--============================================================================
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- DIV_ACCEL - division accelerator wrapper (the "Accelerator" block of Fig.1)
--
-- Wraps the DIVCLK-domain divider behind an interface that is entirely in
-- the MCLK domain, so the CPU core never has to reason about the second
-- clock. Everything clock-domain-crossing related in the design lives here.
--
--   MCLK domain                          | DIVCLK domain
--   ------------------------------------ | -------------------------------
--   Ain_i,Bin_i -> [ ain_q,bin_q ]--------|------> Dividend, Divisor
--                   (Fig.3 "Sync")        |
--   handshake FSM -> div_ena_q -> [cdc_sync] ----> DIVENA
--   div_busy_o <-------------------[cdc_sync] <--- DIVBUSY
--   Quotient_o,Residue_o <- [quot_q,res_q] <------ Quotient, Residue
--
-- Why the operand buses are registered and not synchronized:
-- a two-flop synchronizer is only ever correct on a single bit, because
-- separate bits can resolve on different destination cycles. Buses are made
-- safe by holding them still instead. ain_q/bin_q are loaded when the
-- request is issued and held for the whole division, and the request itself
-- takes ~4 DIVCLK edges to cross, so the data has been stable for several
-- destination cycles before the divider latches it. The control path being
-- slower than the data path is what makes the crossing safe.
--
-- Handshake protocol (all in MCLK):
--   IDLE       div_busy_o follows div_op_i combinationally, so the stall is
--              asserted in the same cycle the instruction is decoded - not
--              when DIVBUSY eventually arrives, which is 4-5 cycles too late
--   WAIT_BUSY  stalled, waiting for confirmation that the divider started
--   WAIT_DONE  stalled, waiting for the divider to finish. div_ena_q is
--              dropped on entry to this state: the divider is provably
--              running by then, so the request line is free to return low
--              with the whole division time as margin before the next one
--   DONE       one cycle with div_busy_o low, during which the core does
--              its write-back and advances the PC
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;


ENTITY div_accel IS
	generic(
		N : positive := 32
	);
	PORT(
		--CPU side, MCLK domain only
		mclk_i		: IN 	STD_LOGIC;
		rst_i		: IN 	STD_LOGIC;
		Ain_i		: IN 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
		Bin_i		: IN 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
		div_op_i	: IN 	STD_LOGIC;

		Quotient_o	: OUT	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
		Residue_o	: OUT	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
		div_busy_o	: OUT	STD_LOGIC;

		--Accelerator clock
		divclk_i	: IN 	STD_LOGIC
	);
END div_accel;


ARCHITECTURE struct OF div_accel IS
	TYPE state_t IS (IDLE, WAIT_BUSY, WAIT_DONE, DONE);

	-- MCLK domain
	SIGNAL state_q		: state_t;
	SIGNAL ain_q		: STD_LOGIC_VECTOR(N-1 DOWNTO 0);
	SIGNAL bin_q		: STD_LOGIC_VECTOR(N-1 DOWNTO 0);
	SIGNAL quot_q		: STD_LOGIC_VECTOR(N-1 DOWNTO 0);
	SIGNAL res_q		: STD_LOGIC_VECTOR(N-1 DOWNTO 0);
	SIGNAL div_ena_q	: STD_LOGIC;
	SIGNAL busy_sync_w	: STD_LOGIC;

	-- DIVCLK domain
	SIGNAL div_ena_w	: STD_LOGIC;
	SIGNAL div_busy_w	: STD_LOGIC;
	SIGNAL quot_w		: STD_LOGIC_VECTOR(N-1 DOWNTO 0);
	SIGNAL res_w		: STD_LOGIC_VECTOR(N-1 DOWNTO 0);

	COMPONENT cdc_sync IS
		PORT(
			src_clk_i	: IN 	STD_LOGIC;
			src_rst_i	: IN 	STD_LOGIC;
			src_bit_i	: IN 	STD_LOGIC;
			dst_clk_i	: IN 	STD_LOGIC;
			dst_rst_i	: IN 	STD_LOGIC;
			dst_bit_o	: OUT	STD_LOGIC
		);
	END COMPONENT;

	COMPONENT divider IS
		generic(
			N : positive := 32
		);
		PORT(
			Dividend 	: IN 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
			Divisor 	: IN 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
			DIVCLK		: IN 	STD_LOGIC;
			DIVRST		: IN 	STD_LOGIC;
			DIVENA		: IN 	STD_LOGIC;
			Quotient	: OUT 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
			Residue		: OUT 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
			DIVBUSY		: OUT 	STD_LOGIC
		);
	END COMPONENT;

BEGIN
	--=======================================
	-- Request crossing : MCLK -> DIVCLK
	--=======================================
	ENA_SYNC: cdc_sync
	PORT MAP (
		src_clk_i	=> mclk_i,
		src_rst_i	=> rst_i,
		src_bit_i	=> div_ena_q,
		dst_clk_i	=> divclk_i,
		dst_rst_i	=> rst_i,
		dst_bit_o	=> div_ena_w
	);

	--=======================================
	-- Divider core
	--=======================================
	-- DIVRST is the system reset here, deliberately, and is NOT the per-division
	-- initialisation that Fig.9 gives that name to. The forum defines DIVRST as
	-- the line that loads the divider's Quotient register and {Residue,Dividend}
	-- shift register at the start of every div/divu/rem/remu; inside DIV.vhd that
	-- is the start_w load branch, driven off the DIVENA edge this wrapper raises
	-- once per division. See DIV.vhd's header for why the load and the clear
	-- cannot share one line.
	DIV: divider
	generic map(
		N			=> N
	)
	PORT MAP (
		Dividend	=> ain_q,
		Divisor		=> bin_q,
		DIVCLK		=> divclk_i,
		DIVRST		=> rst_i,
		DIVENA		=> div_ena_w,
		Quotient	=> quot_w,
		Residue		=> res_w,
		DIVBUSY		=> div_busy_w
	);

	--=======================================
	-- Status crossing : DIVCLK -> MCLK
	--=======================================
	BUSY_SYNC: cdc_sync
	PORT MAP (
		src_clk_i	=> divclk_i,
		src_rst_i	=> rst_i,
		src_bit_i	=> div_busy_w,
		dst_clk_i	=> mclk_i,
		dst_rst_i	=> rst_i,
		dst_bit_o	=> busy_sync_w
	);

	--=======================================
	-- MCLK handshake FSM, operand and result registers
	--=======================================
	PROCESS (mclk_i, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			state_q		<= IDLE;
			ain_q		<= (OTHERS => '0');
			bin_q		<= (OTHERS => '0');
			quot_q		<= (OTHERS => '0');
			res_q		<= (OTHERS => '0');
			div_ena_q	<= '0';

		ELSIF rising_edge(mclk_i) THEN
			CASE state_q IS

				WHEN IDLE =>
					IF div_op_i = '1' THEN
						-- Fig.3 "Sync": launch registers for the operands
						ain_q		<= Ain_i;
						bin_q		<= Bin_i;
						div_ena_q	<= '1';
						state_q		<= WAIT_BUSY;
					END IF;

				WHEN WAIT_BUSY =>
					-- DIVBUSY high proves the divider saw the request, so the
					-- request line can be released with the rest of the
					-- division as margin before it is raised again
					IF busy_sync_w = '1' THEN
						div_ena_q	<= '0';
						state_q		<= WAIT_DONE;
					END IF;

				WHEN WAIT_DONE =>
					IF busy_sync_w = '0' THEN
						-- Results have been stable since DIVBUSY fell, which
						-- is two MCLK edges ago, so they are safe to capture
						quot_q		<= quot_w;
						res_q		<= res_w;
						state_q		<= DONE;
					END IF;

				WHEN DONE =>
					state_q		<= IDLE;

			END CASE;
		END IF;
	END PROCESS;

	--=======================================
	-- Stall output. Combinational in IDLE so the core is held on the very
	-- cycle the instruction is decoded, before DIVBUSY could possibly have
	-- made the round trip.
	--=======================================
	WITH state_q SELECT
		div_busy_o	<=	div_op_i	WHEN IDLE,
						'1'			WHEN WAIT_BUSY,
						'1'			WHEN WAIT_DONE,
						'0'			WHEN DONE;

	Quotient_o	<= quot_q;
	Residue_o	<= res_q;

END struct;
