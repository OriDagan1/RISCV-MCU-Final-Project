---------------------------------------------------------------------------------------------
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- tb_basic_timer_interface - self checking testbench for the Basic Timer register file
--
-- The stimulus process plays the part of the CPU and of PERIPH_AddressDecoder: it asserts
-- one chip select at a time and presents a store or a load exactly as the single-cycle core
-- does - control and data set up just after the rising edge and held across the falling
-- edge, where the device captures.
--
-- Expected values are built independently of the DUT, from the register map of clause 6 and
-- the bit tables of page 7, so a typo in the DUT shows up as a mismatch rather than being
-- reproduced identically on both sides.
--
-- Scope: this is a unit test of one peripheral. It does not replace the verification flow of
-- clause 8, where the whole MCU runs the benchmark applications. It exists so that a failure
-- there can be blamed on the system and not on this device.
--
-- Checks:
--    1. reset clears every register, and a load returns zero
--    2. every register written and read back
--    3. BTCTL1 and BTCTL2 share a chip select and are separated by sel_i alone
--    4. a store to one register leaves the other three untouched
--    5. BTCTL2 bits 7:4 are read only zero, on the bus and on btctl2_o
--    6. the register outputs to the timer track the stored values
--    7. only the low byte of the bus reaches a control register
--    8. a store with cs_i low is ignored
--    9. a store with MemWrite_ctrl_i low is ignored
--   10. a load with cs_i low or MemRead_ctrl_i low returns zeros
--   11. capture happens on the FALLING edge, not before
--   12. BTCAPR is READ/WRITE (forum row 25): a store is accepted, reads back,
--       and does not disturb any other register; it also resets to zero
--       (row 21). 12b: a store and a capture on the same falling edge - the
--       capture wins, see BASIC_TIMER_INTERFACE.vhd's header for why
--   13. BTCAPR is a register with two load sources, not a live window on the
--       timer: btcapr_i alone does not change it, a capture event loads it,
--       and a capture after a store overwrites the stored value
--   14. asynchronous reset in mid operation clears everything immediately
--   15. exhaustive walking one and walking zero over all 32 bits of BTCMPR0
--   16. all ones and all zeros patterns on both compare registers
--   17. an unknown chip select ('X', 'U', 'Z') must not open the port
--   18. normal operation resumes after a reset
--   19. bt_irq_o - the BTIFG edge detector: low while btifg_i is low, one
--       MCLK-cycle pulse per rising edge of btifg_i (including when held
--       high for a full 8 MCLK periods, the BTSSEL=11 case), no pulse on a
--       falling edge, two events give two pulses, low during and across a
--       reset, and undisturbed by a concurrent bus access
--
-- Run:  vcom clk_config_package.vhd BASIC_TIMER_INTERFACE.vhd tb_basic_timer_interface.vhd
--       vsim -voptargs=+acc work.tb_basic_timer_interface
--       run -all
---------------------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY tb_basic_timer_interface IS
END tb_basic_timer_interface;
---------------------------------------------------------------------------------------------
ARCHITECTURE sim OF tb_basic_timer_interface IS

	CONSTANT DATA_BUS_WIDTH	: integer	:= 32;
	CONSTANT N				: positive	:= 32;
	CONSTANT CTL_WIDTH		: integer	:= 8;

	CONSTANT CLK_PERIOD		: time := 40 ns;	-- 25 MHz MCLK
	CONSTANT CLK_HALF		: time := CLK_PERIOD/2;
	CONSTANT HOLD			: time :=  2 ns;	-- settle allowance after an active edge

	--DUT connections
	SIGNAL clk_w			: STD_LOGIC := '0';
	SIGNAL rst_w			: STD_LOGIC := '1';

	SIGNAL cs_btctl_w		: STD_LOGIC := '0';
	SIGNAL cs_btcmpr0_w		: STD_LOGIC := '0';
	SIGNAL cs_btcmpr1_w		: STD_LOGIC := '0';
	SIGNAL cs_btcapr_w		: STD_LOGIC := '0';
	SIGNAL sel_w			: STD_LOGIC := '0';

	SIGNAL memrd_w			: STD_LOGIC := '0';
	SIGNAL memwr_w			: STD_LOGIC := '0';
	SIGNAL data_wr_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL btcapr_w			: STD_LOGIC_VECTOR(N-1 DOWNTO 0) := (OTHERS => '0');
	-- The capture event out of basic_timer, which loads BTCAPR from btcapr_w.
	-- Forum row 25 made BTCAPR read/write, so it is a register in the DUT with
	-- two load sources and this is the timer-side one.
	SIGNAL capevt_w			: STD_LOGIC := '0';
	SIGNAL btifg_w			: STD_LOGIC := '0';

	SIGNAL data_rd_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL btctl1_w			: STD_LOGIC_VECTOR(CTL_WIDTH-1 DOWNTO 0);
	SIGNAL btctl2_w			: STD_LOGIC_VECTOR(CTL_WIDTH-1 DOWNTO 0);
	SIGNAL btcmpr0_w		: STD_LOGIC_VECTOR(N-1 DOWNTO 0);
	SIGNAL btcmpr1_w		: STD_LOGIC_VECTOR(N-1 DOWNTO 0);
	SIGNAL bt_irq_w			: STD_LOGIC;

	SIGNAL done_w			: BOOLEAN := FALSE;

	--Which register a bus cycle is aimed at
	TYPE reg_t IS (R_BTCTL1, R_BTCTL2, R_BTCMPR0, R_BTCMPR1, R_BTCAPR, R_NONE);

	CONSTANT ZERO_BUS		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0) := (OTHERS => '0');

	--=======================================
	-- Expected read value, built from the register map and not from the DUT
	--=======================================
	FUNCTION zext_ctl(v : STD_LOGIC_VECTOR(CTL_WIDTH-1 DOWNTO 0))
		RETURN STD_LOGIC_VECTOR IS
		VARIABLE r : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0) := (OTHERS => '0');
	BEGIN
		r(CTL_WIDTH-1 DOWNTO 0) := v;
		RETURN r;
	END FUNCTION;

	FUNCTION zext_word(v : STD_LOGIC_VECTOR(N-1 DOWNTO 0))
		RETURN STD_LOGIC_VECTOR IS
		VARIABLE r : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0) := (OTHERS => '0');
	BEGIN
		r(N-1 DOWNTO 0) := v;
		RETURN r;
	END FUNCTION;

	--BTCTL2 keeps only bits 3:0; 7:4 are read only zero (page 7)
	FUNCTION ctl2_masked(v : STD_LOGIC_VECTOR(CTL_WIDTH-1 DOWNTO 0))
		RETURN STD_LOGIC_VECTOR IS
		VARIABLE r : STD_LOGIC_VECTOR(CTL_WIDTH-1 DOWNTO 0) := (OTHERS => '0');
	BEGIN
		r(3 DOWNTO 0) := v(3 DOWNTO 0);
		RETURN r;
	END FUNCTION;

	FUNCTION word(v : natural) RETURN STD_LOGIC_VECTOR IS
	BEGIN
		RETURN STD_LOGIC_VECTOR(to_unsigned(v, N));
	END FUNCTION;

BEGIN

	--=======================================
	-- DUT
	--=======================================
	DUT: entity work.basic_timer_interface
	generic map(
		DATA_BUS_WIDTH	=> DATA_BUS_WIDTH,
		N				=> N,
		CTL_WIDTH		=> CTL_WIDTH
	)
	PORT MAP (
		clk_i			=> clk_w,
		rst_i			=> rst_w,
		cs_btctl_i		=> cs_btctl_w,
		cs_btcmpr0_i	=> cs_btcmpr0_w,
		cs_btcmpr1_i	=> cs_btcmpr1_w,
		cs_btcapr_i		=> cs_btcapr_w,
		sel_i			=> sel_w,
		MemRead_ctrl_i	=> memrd_w,
		MemWrite_ctrl_i	=> memwr_w,
		data_wr_i		=> data_wr_w,
		btcapr_i		=> btcapr_w,
		capevt_i		=> capevt_w,
		btifg_i			=> btifg_w,
		data_rd_o		=> data_rd_w,
		bt_irq_o		=> bt_irq_w,
		btctl1_o		=> btctl1_w,
		btctl2_o		=> btctl2_w,
		btcmpr0_o		=> btcmpr0_w,
		btcmpr1_o		=> btcmpr1_w
	);

	--=======================================
	-- Clock
	--=======================================
	CLKGEN:
	process
	begin
		while not done_w loop
			clk_w <= '0';
			wait for CLK_HALF;
			clk_w <= '1';
			wait for CLK_HALF;
		end loop;
		wait;
	end process;

	--=======================================
	-- Stimulus and checking
	--=======================================
	STIM:
	process
		VARIABLE errors_v	: natural := 0;
		VARIABLE checks_v	: natural := 0;

		--- reporting -------------------------------------------------------
		procedure check(cond : boolean; msg : string) is
		begin
			checks_v := checks_v + 1;
			if not cond then
				errors_v := errors_v + 1;
				report "FAIL: " & msg severity error;
			end if;
		end procedure;

		procedure check_vec(got : STD_LOGIC_VECTOR;
							exp : STD_LOGIC_VECTOR;
							msg : string) is
		begin
			checks_v := checks_v + 1;
			if got /= exp then
				errors_v := errors_v + 1;
				report "FAIL: " & msg severity error;
			end if;
		end procedure;

		--- bus plumbing ----------------------------------------------------
		-- Assert exactly one chip select, the way PERIPH_AddressDecoder does.
		procedure aim(r : reg_t) is
		begin
			cs_btctl_w		<= '0';
			cs_btcmpr0_w	<= '0';
			cs_btcmpr1_w	<= '0';
			cs_btcapr_w		<= '0';
			case r is
				when R_BTCTL1	=> cs_btctl_w   <= '1'; sel_w <= '0';
				when R_BTCTL2	=> cs_btctl_w   <= '1'; sel_w <= '1';
				when R_BTCMPR0	=> cs_btcmpr0_w <= '1';
				when R_BTCMPR1	=> cs_btcmpr1_w <= '1';
				when R_BTCAPR	=> cs_btcapr_w  <= '1';
				when R_NONE		=> null;
			end case;
		end procedure;

		procedure idle is
		begin
			aim(R_NONE);
			memrd_w		<= '0';
			memwr_w		<= '0';
			data_wr_w	<= (OTHERS => '0');
		end procedure;

		-- One CPU store cycle: set up after the rising edge, capture on the falling one.
		procedure bus_write(r : reg_t; data : STD_LOGIC_VECTOR) is
		begin
			wait until rising_edge(clk_w);
			aim(r);
			memwr_w		<= '1';
			memrd_w		<= '0';
			data_wr_w	<= data;
			wait until falling_edge(clk_w);
			wait for HOLD;
			idle;
		end procedure;

		-- A store that must be ignored: same waveform, one qualifier missing.
		procedure bus_write_blocked(r : reg_t; data : STD_LOGIC_VECTOR;
									force_cs : STD_LOGIC; wr : STD_LOGIC) is
		begin
			wait until rising_edge(clk_w);
			aim(r);
			if force_cs = '0' then
				aim(R_NONE);
			end if;
			memwr_w		<= wr;
			memrd_w		<= '0';
			data_wr_w	<= data;
			wait until falling_edge(clk_w);
			wait for HOLD;
			idle;
		end procedure;

		-- One capture event: present a count on btcapr_i and pulse capevt_i
		-- across the falling edge, which is where the DUT's register samples.
		-- Same waveform shape as bus_write, so a capture and a store can be
		-- made to collide simply by issuing both around one falling edge.
		procedure capture(v : STD_LOGIC_VECTOR) is
		begin
			wait until rising_edge(clk_w);
			btcapr_w	<= v;
			capevt_w	<= '1';
			wait until falling_edge(clk_w);
			wait for HOLD;
			capevt_w	<= '0';
		end procedure;

		-- The read path is combinational, so no edge is needed.
		procedure bus_read(r : reg_t; exp : STD_LOGIC_VECTOR; msg : string) is
		begin
			aim(r);
			memrd_w	<= '1';
			memwr_w	<= '0';
			wait for HOLD;
			check_vec(data_rd_w, exp, msg);
			idle;
			wait for HOLD;
		end procedure;

		-- Advance N MCLK rising edges, then settle by HOLD - for the BTIFG
		-- edge detector checks, which are not tied to a register write/read.
		procedure step_mclk(n : POSITIVE) is
		begin
			for i in 1 to n loop
				wait until rising_edge(clk_w);
			end loop;
			wait for HOLD;
		end procedure;

	begin
		report "=== tb_basic_timer_interface start ===" severity note;

		--===============================================================
		-- 1  Reset clears everything
		--===============================================================
		rst_w <= '1';
		wait for 2*CLK_PERIOD;

		check_vec(btctl1_w,  x"00",   "T1 BTCTL1 must be zero after reset");
		check_vec(btctl2_w,  x"00",   "T1 BTCTL2 must be zero after reset");
		check_vec(btcmpr0_w, word(0), "T1 BTCMPR0 must be zero after reset");
		check_vec(btcmpr1_w, word(0), "T1 BTCMPR1 must be zero after reset");

		bus_read(R_BTCTL1,  ZERO_BUS, "T1 BTCTL1 reads zero after reset");
		bus_read(R_BTCTL2,  ZERO_BUS, "T1 BTCTL2 reads zero after reset");
		bus_read(R_BTCMPR0, ZERO_BUS, "T1 BTCMPR0 reads zero after reset");
		bus_read(R_BTCMPR1, ZERO_BUS, "T1 BTCMPR1 reads zero after reset");

		-- BTCAPR is a register now, so it has a reset value of its own. Forum
		-- row 21 names it in the list that resets: "Only the timer module's
		-- interface registers reset on RESET: BTCTL1, BTCTL2, BTCAPR,
		-- BTCMPR0, BTCMPR1". btcapr_w is non-zero here on purpose - the read
		-- must return the reset register, not the timer's input.
		btcapr_w <= word(48879);
		wait for HOLD;
		bus_read(R_BTCAPR,  ZERO_BUS, "T1 BTCAPR reads zero after reset");
		btcapr_w <= (OTHERS => '0');
		wait for HOLD;

		wait until rising_edge(clk_w);
		rst_w <= '0';
		wait for HOLD;

		--===============================================================
		-- 2/3  Write and read back, and sel_i separates the control pair
		--===============================================================
		bus_write(R_BTCTL1, zext_ctl(x"A5"));
		check_vec(btctl1_w, x"A5", "T2 BTCTL1 output follows the store");
		bus_read(R_BTCTL1, zext_ctl(x"A5"), "T2 BTCTL1 reads back A5");
		bus_read(R_BTCTL2, ZERO_BUS,        "T3 BTCTL2 untouched by the BTCTL1 store");

		bus_write(R_BTCTL2, zext_ctl(x"09"));
		check_vec(btctl2_w, x"09", "T2 BTCTL2 output follows the store");
		bus_read(R_BTCTL2, zext_ctl(x"09"),  "T2 BTCTL2 reads back 09");
		bus_read(R_BTCTL1, zext_ctl(x"A5"),  "T3 BTCTL1 untouched by the BTCTL2 store");

		bus_write(R_BTCMPR0, zext_word(word(1000)));
		check_vec(btcmpr0_w, word(1000), "T2 BTCMPR0 output follows the store");
		bus_read(R_BTCMPR0, zext_word(word(1000)), "T2 BTCMPR0 reads back 1000");

		bus_write(R_BTCMPR1, zext_word(word(500)));
		check_vec(btcmpr1_w, word(500), "T2 BTCMPR1 output follows the store");
		bus_read(R_BTCMPR1, zext_word(word(500)), "T2 BTCMPR1 reads back 500");

		--===============================================================
		-- 4  A store hits exactly one register
		--===============================================================
		bus_read(R_BTCTL1,  zext_ctl(x"A5"),         "T4 BTCTL1 stable");
		bus_read(R_BTCTL2,  zext_ctl(x"09"),         "T4 BTCTL2 stable");
		bus_read(R_BTCMPR0, zext_word(word(1000)),   "T4 BTCMPR0 stable");
		bus_read(R_BTCMPR1, zext_word(word(500)),    "T4 BTCMPR1 stable");

		bus_write(R_BTCMPR0, zext_word(word(77)));
		bus_read(R_BTCMPR1, zext_word(word(500)),    "T4 BTCMPR1 survives a BTCMPR0 store");
		bus_read(R_BTCTL1,  zext_ctl(x"A5"),         "T4 BTCTL1 survives a BTCMPR0 store");
		bus_write(R_BTCMPR0, zext_word(word(1000))); -- restore

		--===============================================================
		-- 5  BTCTL2 bits 7:4 are read only zero
		--===============================================================
		-- Page 7 marks them r. A store must not set them, on the bus or on the
		-- port that feeds the timer.
		bus_write(R_BTCTL2, zext_ctl(x"FF"));
		check_vec(btctl2_w, ctl2_masked(x"FF"), "T5 btctl2_o reserved bits must stay zero");
		bus_read(R_BTCTL2, zext_ctl(ctl2_masked(x"FF")),
				 "T5 BTCTL2 must read 0F after storing FF");

		bus_write(R_BTCTL2, zext_ctl(x"F0"));
		check_vec(btctl2_w, x"00", "T5 storing F0 to BTCTL2 leaves it zero");
		bus_read(R_BTCTL2, ZERO_BUS, "T5 BTCTL2 reads zero after storing F0");

		-- BTCTL1 has no reserved bits: all eight must survive
		bus_write(R_BTCTL1, zext_ctl(x"FF"));
		check_vec(btctl1_w, x"FF", "T5 BTCTL1 keeps all eight bits");
		bus_read(R_BTCTL1, zext_ctl(x"FF"), "T5 BTCTL1 reads back FF");

		--===============================================================
		-- 7  Only the low byte of the bus reaches a control register
		--===============================================================
		bus_write(R_BTCTL1, x"DEADBEEF");
		check_vec(btctl1_w, x"EF", "T7 BTCTL1 keeps only the low byte");
		bus_read(R_BTCTL1, zext_ctl(x"EF"), "T7 BTCTL1 reads EF, upper bus bits dropped");

		bus_write(R_BTCTL2, x"DEADBEEF");
		check_vec(btctl2_w, ctl2_masked(x"EF"), "T7 BTCTL2 keeps only the low nibble of EF");

		-- back to a known state
		bus_write(R_BTCTL1, zext_ctl(x"A5"));
		bus_write(R_BTCTL2, zext_ctl(x"09"));

		--===============================================================
		-- 8  A store without chip select is ignored
		--===============================================================
		bus_write_blocked(R_BTCTL1, zext_ctl(x"3C"), '0', '1');
		bus_read(R_BTCTL1, zext_ctl(x"A5"), "T8 store with no chip select must be ignored");

		bus_write_blocked(R_BTCMPR0, zext_word(word(4242)), '0', '1');
		bus_read(R_BTCMPR0, zext_word(word(1000)),
				 "T8 BTCMPR0 store with no chip select must be ignored");

		--===============================================================
		-- 9  A store without MemWrite is ignored
		--===============================================================
		bus_write_blocked(R_BTCTL1, zext_ctl(x"3C"), '1', '0');
		bus_read(R_BTCTL1, zext_ctl(x"A5"), "T9 store with MemWrite low must be ignored");

		bus_write_blocked(R_BTCMPR1, zext_word(word(4242)), '1', '0');
		bus_read(R_BTCMPR1, zext_word(word(500)),
				 "T9 BTCMPR1 store with MemWrite low must be ignored");

		--===============================================================
		-- 10  The read bus is released when the device is not addressed
		--===============================================================
		aim(R_NONE);
		memrd_w	<= '1';
		wait for HOLD;
		check_vec(data_rd_w, ZERO_BUS, "T10 data_rd_o must be zero with no chip select");

		aim(R_BTCTL1);
		memrd_w	<= '0';
		wait for HOLD;
		check_vec(data_rd_w, ZERO_BUS, "T10 data_rd_o must be zero with MemRead low");
		idle;
		wait for HOLD;

		--===============================================================
		-- 11  Capture is on the FALLING edge, not before
		--===============================================================
		-- Until the falling edge arrives the register must still hold its old
		-- value; only after it may it change.
		wait until rising_edge(clk_w);
		aim(R_BTCMPR0);
		memwr_w		<= '1';
		data_wr_w	<= zext_word(word(31337));
		wait for CLK_HALF/2;					-- still inside the high phase
		check_vec(btcmpr0_w, word(1000), "T11 no capture before the falling edge");
		wait until falling_edge(clk_w);
		wait for HOLD;
		check_vec(btcmpr0_w, word(31337), "T11 capture on the falling edge");
		idle;
		wait for HOLD;
		bus_write(R_BTCMPR0, zext_word(word(1000)));	-- restore

		--===============================================================
		-- 12/13  BTCAPR is READ/WRITE, with two load sources
		--===============================================================
		-- These two checks previously asserted the opposite: "a store to
		-- BTCAPR must be ignored" and "BTCAPR follows the timer, it is not a
		-- stored copy". Forum row 25 overturns both - "All of the timer's
		-- interface registers are readable and writable, except the four high
		-- bits of BTCTL2, which are read-only" - so BTCAPR is now a register
		-- in the DUT loaded from the bus on a store and from btcapr_i on a
		-- capture event. Rewritten, not deleted, because the register still
		-- has to track the timer; what changed is that a store also reaches it.

		-- It no longer follows btcapr_i by itself. Moving the timer's value
		-- with no capture event must NOT change what a load returns - that is
		-- the difference between a register and the old pass-through.
		btcapr_w <= word(12345);
		wait for HOLD;
		bus_read(R_BTCAPR, ZERO_BUS,
				 "T13 BTCAPR ignores btcapr_i without a capture event");

		-- A capture event loads it.
		capture(word(12345));
		bus_read(R_BTCAPR, zext_word(word(12345)),
				 "T13 a capture event loads BTCAPR from the timer");

		-- A store is accepted and reads back - the row 25 requirement itself.
		bus_write(R_BTCAPR, zext_word(word(999)));
		bus_read(R_BTCAPR, zext_word(word(999)),
				 "T12 a store to BTCAPR is accepted and reads back");

		-- And it must not have leaked into any other register
		bus_read(R_BTCMPR0, zext_word(word(1000)), "T12 BTCAPR store did not touch BTCMPR0");
		bus_read(R_BTCTL1,  zext_ctl(x"A5"),       "T12 BTCAPR store did not touch BTCTL1");
		bus_read(R_BTCMPR1, zext_word(word(500)),  "T12 BTCAPR store did not touch BTCMPR1");

		-- A later capture overwrites what software stored: the hardware
		-- measurement is still the register's primary job.
		capture(word(6789));
		bus_read(R_BTCAPR, zext_word(word(6789)),
				 "T13 a capture after a store overwrites the stored value");

		-- Full-width patterns through both paths.
		capture((btcapr_w'range => '1'));
		bus_read(R_BTCAPR, zext_word((btcapr_w'range => '1')),
				 "T13 BTCAPR captures all ones unchanged");
		bus_write(R_BTCAPR, ZERO_BUS);
		bus_read(R_BTCAPR, ZERO_BUS, "T12 BTCAPR stores all zeros unchanged");

		--===============================================================
		-- 12b  Store and capture on the SAME falling edge: capture wins
		--===============================================================
		-- Documented in BASIC_TIMER_INTERFACE.vhd's header: the two sources
		-- are asymmetric in what losing costs. A store is software and can be
		-- retried - the ISR still holds the value. A capture is a measurement
		-- of a counter that has already moved on, and once dropped it exists
		-- nowhere. So the irrecoverable source takes priority.
		bus_write(R_BTCAPR, zext_word(word(4444)));
		bus_read(R_BTCAPR, zext_word(word(4444)), "T12b a known value before the collision");

		wait until rising_edge(clk_w);
		btcapr_w	<= word(31337);		-- the timer's captured count
		capevt_w	<= '1';				-- and the capture event
		aim(R_BTCAPR);					-- and a store to the same register
		memwr_w		<= '1';
		memrd_w		<= '0';
		data_wr_w	<= zext_word(word(555));
		wait until falling_edge(clk_w);
		wait for HOLD;
		capevt_w	<= '0';
		idle;
		wait for HOLD;

		bus_read(R_BTCAPR, zext_word(word(31337)),
				 "T12b capture beats a store on the same edge");

		btcapr_w <= (OTHERS => '0');
		wait for HOLD;

		--===============================================================
		-- 15  Walking one and walking zero over BTCMPR0
		--===============================================================
		for i in 0 to N-1 loop
			bus_write(R_BTCMPR0, zext_word(STD_LOGIC_VECTOR(shift_left(to_unsigned(1, N), i))));
			bus_read(R_BTCMPR0,
					 zext_word(STD_LOGIC_VECTOR(shift_left(to_unsigned(1, N), i))),
					 "T15 walking one, bit " & integer'image(i));
		end loop;

		for i in 0 to N-1 loop
			bus_write(R_BTCMPR1,
					  zext_word(NOT STD_LOGIC_VECTOR(shift_left(to_unsigned(1, N), i))));
			bus_read(R_BTCMPR1,
					 zext_word(NOT STD_LOGIC_VECTOR(shift_left(to_unsigned(1, N), i))),
					 "T15 walking zero, bit " & integer'image(i));
		end loop;

		--===============================================================
		-- 16  All ones and all zeros
		--===============================================================
		bus_write(R_BTCMPR0, x"FFFFFFFF");
		bus_read(R_BTCMPR0, x"FFFFFFFF", "T16 BTCMPR0 all ones");
		bus_write(R_BTCMPR0, x"00000000");
		bus_read(R_BTCMPR0, ZERO_BUS,    "T16 BTCMPR0 all zeros");

		bus_write(R_BTCMPR1, x"FFFFFFFF");
		bus_read(R_BTCMPR1, x"FFFFFFFF", "T16 BTCMPR1 all ones");
		bus_write(R_BTCMPR1, x"00000000");
		bus_read(R_BTCMPR1, ZERO_BUS,    "T16 BTCMPR1 all zeros");

		--===============================================================
		-- 17  An unknown chip select must not open the port
		--===============================================================
		-- Before the decoder is reset, or on an unconnected select, cs can be
		-- 'U', 'X' or 'Z'. None of these is '1', so the port must stay off the
		-- bus rather than half open it.
		bus_write(R_BTCTL1, zext_ctl(x"A5"));

		idle;
		cs_btctl_w	<= 'X';
		memrd_w		<= '1';
		wait for HOLD;
		check_vec(data_rd_w, ZERO_BUS, "T17 cs_btctl_i = 'X' must not drive the bus");

		cs_btctl_w	<= 'U';
		wait for HOLD;
		check_vec(data_rd_w, ZERO_BUS, "T17 cs_btctl_i = 'U' must not drive the bus");

		cs_btctl_w	<= 'Z';
		wait for HOLD;
		check_vec(data_rd_w, ZERO_BUS, "T17 cs_btctl_i = 'Z' must not drive the bus");

		-- and an unknown select must not let a store through either
		cs_btctl_w	<= 'X';
		memrd_w		<= '0';
		memwr_w		<= '1';
		data_wr_w	<= zext_ctl(x"5A");
		wait until falling_edge(clk_w);
		wait for HOLD;
		check_vec(btctl1_w, x"A5", "T17 a store with cs_i = 'X' must be ignored");
		idle;
		wait for HOLD;

		--===============================================================
		-- 14/18  Asynchronous reset in mid operation, then resume
		--===============================================================
		bus_write(R_BTCTL1,  zext_ctl(x"5A"));
		bus_write(R_BTCTL2,  zext_ctl(x"06"));
		bus_write(R_BTCMPR0, zext_word(word(2024)));
		bus_write(R_BTCMPR1, zext_word(word(1012)));

		wait until rising_edge(clk_w);
		wait for CLK_HALF/4;					-- nowhere near a clock edge
		rst_w <= '1';
		wait for HOLD;
		check_vec(btctl1_w,  x"00",   "T14 reset clears BTCTL1 immediately");
		check_vec(btctl2_w,  x"00",   "T14 reset clears BTCTL2 immediately");
		check_vec(btcmpr0_w, word(0), "T14 reset clears BTCMPR0 immediately");
		check_vec(btcmpr1_w, word(0), "T14 reset clears BTCMPR1 immediately");
		rst_w <= '0';
		wait until rising_edge(clk_w);

		bus_read(R_BTCTL1,  ZERO_BUS, "T14 BTCTL1 reads zero after reset");
		bus_read(R_BTCMPR0, ZERO_BUS, "T14 BTCMPR0 reads zero after reset");

		bus_write(R_BTCTL1,  zext_ctl(x"3C"));
		bus_write(R_BTCMPR0, zext_word(word(88)));
		bus_read(R_BTCTL1,  zext_ctl(x"3C"),      "T18 normal operation resumes after reset");
		bus_read(R_BTCMPR0, zext_word(word(88)),  "T18 BTCMPR0 works again after reset");

		--===============================================================
		-- 19  BTIFG edge detector : bt_irq_o, one MCLK pulse per event
		--
		-- btifg_w starts at '0' and nothing before this point has touched it,
		-- so bt_irq_w is already settled low here.
		--===============================================================
		REPORT "--- BTIFG edge detector (bt_irq_o) ---" SEVERITY note;

		check(bt_irq_w = '0', "T19 bt_irq_o low while btifg_i is low");

		-- A rising edge on btifg_i produces a pulse exactly one MCLK period
		-- long, and holding btifg_i high for the remaining 7 of 8 MCLK
		-- periods (the BTSSEL=11 case) produces no further pulses - this is
		-- the whole point of the edge detector.
		wait until rising_edge(clk_w);
		btifg_w <= '1';
		wait for HOLD;
		check(bt_irq_w = '1', "T19 bt_irq_o pulses on the rising edge of btifg_i");

		for i in 2 to 8 loop
			wait until rising_edge(clk_w);
			wait for HOLD;
			check(bt_irq_w = '0',
			      "T19 no repeated pulse while btifg_i held high, edge " & integer'image(i));
		end loop;

		-- A falling edge on btifg_i produces no pulse.
		wait until rising_edge(clk_w);
		btifg_w <= '0';
		wait for HOLD;
		check(bt_irq_w = '0', "T19 bt_irq_o does not pulse on the falling edge of btifg_i");
		wait until rising_edge(clk_w);
		wait for HOLD;
		check(bt_irq_w = '0', "T19 bt_irq_o still low one cycle after the falling edge");

		-- Two separate events produce two separate pulses.
		wait until rising_edge(clk_w);
		btifg_w <= '1';
		wait for HOLD;
		check(bt_irq_w = '1', "T19 first of two separate events pulses");

		wait until rising_edge(clk_w);
		btifg_w <= '0';
		wait for HOLD;
		check(bt_irq_w = '0', "T19 first pulse cleared after one cycle");

		wait until rising_edge(clk_w);
		wait for HOLD;
		check(bt_irq_w = '0', "T19 idle between the two events");

		wait until rising_edge(clk_w);
		btifg_w <= '1';
		wait for HOLD;
		check(bt_irq_w = '1', "T19 second of two separate events pulses");

		wait until rising_edge(clk_w);
		btifg_w <= '0';
		wait for HOLD;
		check(bt_irq_w = '0', "T19 second pulse cleared after one cycle");

		-- bt_irq_o must be '0' during reset and while reset is held, with
		-- btifg_i idle - the same idle-input idiom TEST 1 uses for the
		-- pushbutton port. This module has no independent reset gate on
		-- bt_irq_o itself (it is bt_irq_o <= btifg_i AND NOT <register>, per
		-- design), but in the integrated MCU basic_timer_interface and
		-- basic_timer share the same rst_w, so btifg_i is forced low by the
		-- same reset event that clears this module - an isolated unit
		-- testbench forcing btifg_i high across a reset it does not also
		-- apply to a (nonexistent, here) upstream timer would not reflect
		-- any reachable system state.
		step_mclk(1);
		check(bt_irq_w = '0', "T19 bt_irq_o idle before reset");

		rst_w <= '1';
		WAIT FOR HOLD;
		check(bt_irq_w = '0', "T19 bt_irq_o stays low the instant reset asserts");

		step_mclk(3);
		check(bt_irq_w = '0', "T19 bt_irq_o stays low while reset is held");

		rst_w <= '0';
		step_mclk(1);
		check(bt_irq_w = '0', "T19 bt_irq_o stays low immediately after reset releases");

		-- Driving btifg_i and a bus access at the same time disturbs neither.
		bus_write(R_BTCTL1, zext_ctl(x"5A"));

		wait until rising_edge(clk_w);
		btifg_w <= '1';
		aim(R_BTCTL1);
		memrd_w	<= '1';
		memwr_w	<= '0';
		wait for HOLD;
		check_vec(data_rd_w, zext_ctl(x"5A"),
		          "T19 bus read unaffected by a concurrent btifg_i rising edge");
		check(bt_irq_w = '1', "T19 bt_irq_o pulses correctly during a concurrent bus read");
		idle;
		wait for HOLD;

		wait until rising_edge(clk_w);
		btifg_w <= '0';
		wait for HOLD;
		check(bt_irq_w = '0',
		      "T19 bt_irq_o pulse still exactly one cycle with bus traffic present");

		bus_read(R_BTCTL1, zext_ctl(x"5A"), "T19 BTCTL1 unaffected by the concurrent btifg_i event");

		--===============================================================
		report "==================================================" severity note;
		report "checks run : " & integer'image(checks_v) severity note;
		report "failures   : " & integer'image(errors_v) severity note;
		if errors_v = 0 then
			report "ALL basic_timer_interface TESTS PASSED" severity note;
		else
			report "basic_timer_interface : THERE ARE FAILURES" severity failure;
		end if;
		report "==================================================" severity note;

		done_w <= TRUE;
		wait;
	end process;

END sim;