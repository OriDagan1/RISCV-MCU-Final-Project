---------------------------------------------------------------------------------------------
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Testbench for GPIO_HEX_Pair_Interface
--
-- Self checking: every check bumps an error counter and the final report tells
-- whether the device passed. Nothing has to be read off the waveform, although
-- the waveform is still the fastest way to see WHY something failed.
--
-- What is covered
--   1  reset clears both registers, both displays show '0'
--   2  store to the even address (A0='0') and to the odd one (A0='1')
--   3  the other digit of the pair is never disturbed by a store
--   4  all 16 digit values on both digits, segments compared to the truth table
--   5  load returns the stored digit, zero extended over the whole bus
--   6  a store with cs_i='0' is ignored
--   7  a store with MemWrite_ctrl_i='0' is ignored
--   8  the port register keeps the whole byte, the display shows the low nibble
--   9  data_rd_o is all zeros unless (cs_i='1' AND MemRead_ctrl_i='1')
--  10  the register captures on the FALLING edge, not the rising one
--  11  reset is asynchronous: it clears mid cycle, not at the next edge
--  12  the ACTIVE_LOW generic really inverts the segment vector
--
-- Two instances are driven by the same stimulus, one active low (as on the
-- board) and one active high, so the generate branches of the encoder are both
-- exercised and can be compared against each other.
--
-- Scope: this is a unit test of one peripheral. It does not replace the
-- verification flow of clause 8 of the assignment, where the whole MCU runs the
-- benchmark applications and the ModelSim DTCM.mem is compared against the RARS
-- DTCM.h golden model. It exists so that a failure there can be blamed on the
-- system and not on this device.
--
-- Run:  vcom SevenSegmentEncoder.vhd GPIO_HEX_Pair_Interface.vhd tb_GPIO_HEX_Pair_Interface.vhd
--       vsim -voptargs=+acc work.tb_GPIO_HEX_Pair_Interface
--       run -all
---------------------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY tb_GPIO_HEX_Pair_Interface IS
END tb_GPIO_HEX_Pair_Interface;
---------------------------------------------------------------------------------------------
ARCHITECTURE sim OF tb_GPIO_HEX_Pair_Interface IS

	CONSTANT DATA_BUS_WIDTH	: integer := 32;
	CONSTANT PORT_WIDTH		: integer := 8;		-- the D-latch of Figure 5
	CONSTANT DIGIT_WIDTH	: integer := 4;		-- what the display can actually show
	CONSTANT SEG_WIDTH		: integer := 7;		-- local only, the DUT ports are fixed at 7

	CONSTANT CLK_PERIOD		: time := 20 ns;	-- 50 MHz board clock
	CONSTANT CLK_HALF		: time := CLK_PERIOD/2;

	-- Bus
	SIGNAL clk_w			: STD_LOGIC := '0';
	SIGNAL rst_w			: STD_LOGIC := '1';
	SIGNAL cs_w				: STD_LOGIC := '0';
	SIGNAL sel_w			: STD_LOGIC := '0';
	SIGNAL memrd_w			: STD_LOGIC := '0';
	SIGNAL memwr_w			: STD_LOGIC := '0';
	SIGNAL data_wr_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0) := (OTHERS => '0');

	-- DUT, active low displays (the board)
	SIGNAL data_rd_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL hex_lo_w			: STD_LOGIC_VECTOR(SEG_WIDTH-1 DOWNTO 0);
	SIGNAL hex_hi_w			: STD_LOGIC_VECTOR(SEG_WIDTH-1 DOWNTO 0);

	-- DUT, active high displays (generic coverage only)
	SIGNAL data_rd_ah_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL hex_lo_ah_w		: STD_LOGIC_VECTOR(SEG_WIDTH-1 DOWNTO 0);
	SIGNAL hex_hi_ah_w		: STD_LOGIC_VECTOR(SEG_WIDTH-1 DOWNTO 0);

	SIGNAL done_w			: BOOLEAN := FALSE;

	--=======================================
	-- Expected segment pattern, active high : g f e d c b a
	--=======================================
	-- Written out independently of the DUT so that a typo in the encoder table
	-- is caught here rather than being copied into the check.
	FUNCTION seg_of(digit : STD_LOGIC_VECTOR(3 DOWNTO 0)) RETURN STD_LOGIC_VECTOR IS
	BEGIN
		CASE digit IS
			WHEN "0000" => RETURN "0111111";	-- 0
			WHEN "0001" => RETURN "0000110";	-- 1
			WHEN "0010" => RETURN "1011011";	-- 2
			WHEN "0011" => RETURN "1001111";	-- 3
			WHEN "0100" => RETURN "1100110";	-- 4
			WHEN "0101" => RETURN "1101101";	-- 5
			WHEN "0110" => RETURN "1111101";	-- 6
			WHEN "0111" => RETURN "0000111";	-- 7
			WHEN "1000" => RETURN "1111111";	-- 8
			WHEN "1001" => RETURN "1101111";	-- 9
			WHEN "1010" => RETURN "1110111";	-- A
			WHEN "1011" => RETURN "1111100";	-- b
			WHEN "1100" => RETURN "0111001";	-- C
			WHEN "1101" => RETURN "1011110";	-- d
			WHEN "1110" => RETURN "1111001";	-- E
			WHEN OTHERS => RETURN "1110001";	-- F
		END CASE;
	END FUNCTION;

	-- What the board should see for a given stored digit.
	FUNCTION seg_low(digit : STD_LOGIC_VECTOR(3 DOWNTO 0)) RETURN STD_LOGIC_VECTOR IS
	BEGIN
		RETURN NOT seg_of(digit);
	END FUNCTION;

	FUNCTION nibble(v : integer) RETURN STD_LOGIC_VECTOR IS
	BEGIN
		RETURN STD_LOGIC_VECTOR(TO_UNSIGNED(v, DIGIT_WIDTH));
	END FUNCTION;

	FUNCTION zext(v : integer) RETURN STD_LOGIC_VECTOR IS
	BEGIN
		RETURN STD_LOGIC_VECTOR(TO_UNSIGNED(v, DATA_BUS_WIDTH));
	END FUNCTION;

	FUNCTION img(v : STD_LOGIC_VECTOR) RETURN STRING IS
		VARIABLE s : STRING(1 TO v'LENGTH);
		VARIABLE i : integer := 1;
	BEGIN
		FOR k IN v'RANGE LOOP
			CASE v(k) IS
				WHEN '0'	=> s(i) := '0';
				WHEN '1'	=> s(i) := '1';
				WHEN 'U'	=> s(i) := 'U';
				WHEN 'X'	=> s(i) := 'X';
				WHEN 'Z'	=> s(i) := 'Z';
				WHEN OTHERS	=> s(i) := '?';
			END CASE;
			i := i + 1;
		END LOOP;
		RETURN s;
	END FUNCTION;

BEGIN

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
	-- DUT, as instantiated on the board
	--=======================================
	DUT: entity work.GPIO_HEX_Pair_Interface
	generic map(
		DATA_BUS_WIDTH	=> DATA_BUS_WIDTH,
		PORT_WIDTH		=> PORT_WIDTH,
		ACTIVE_LOW		=> TRUE
	)
	PORT MAP (
		clk_i			=> clk_w,
		rst_i			=> rst_w,
		cs_i			=> cs_w,
		sel_i			=> sel_w,
		MemRead_ctrl_i	=> memrd_w,
		MemWrite_ctrl_i	=> memwr_w,
		data_wr_i		=> data_wr_w,
		data_rd_o		=> data_rd_w,
		HEX_lo_o		=> hex_lo_w,
		HEX_hi_o		=> hex_hi_w
	);

	--=======================================
	-- Same stimulus, active high displays
	--=======================================
	DUT_AH: entity work.GPIO_HEX_Pair_Interface
	generic map(
		DATA_BUS_WIDTH	=> DATA_BUS_WIDTH,
		PORT_WIDTH		=> PORT_WIDTH,
		ACTIVE_LOW		=> FALSE
	)
	PORT MAP (
		clk_i			=> clk_w,
		rst_i			=> rst_w,
		cs_i			=> cs_w,
		sel_i			=> sel_w,
		MemRead_ctrl_i	=> memrd_w,
		MemWrite_ctrl_i	=> memwr_w,
		data_wr_i		=> data_wr_w,
		data_rd_o		=> data_rd_ah_w,
		HEX_lo_o		=> hex_lo_ah_w,
		HEX_hi_o		=> hex_hi_ah_w
	);

	--=======================================
	-- Stimulus and checks
	--=======================================
	STIM:
	process
		VARIABLE errors : natural := 0;

		--- reporting -------------------------------------------------------
		procedure check(cond : boolean; msg : string) is
		begin
			if not cond then
				errors := errors + 1;
				report "FAIL: " & msg severity error;
			end if;
		end procedure;

		--- bus transactions ------------------------------------------------
		-- A store is presented after the rising edge and captured by the
		-- device on the following falling edge, exactly like a DTCM write.
		procedure bus_write(sel : STD_LOGIC; data : STD_LOGIC_VECTOR) is
		begin
			wait until rising_edge(clk_w);
			cs_w		<= '1';
			memwr_w		<= '1';
			memrd_w		<= '0';
			sel_w		<= sel;
			data_wr_w	<= data;
			wait until falling_edge(clk_w);
			wait for 1 ns;
			cs_w		<= '0';
			memwr_w		<= '0';
		end procedure;

		-- A store that must be ignored: same waveform, but one of the two
		-- qualifiers is missing.
		procedure bus_write_blocked(sel : STD_LOGIC; data : STD_LOGIC_VECTOR;
									cs : STD_LOGIC; wr : STD_LOGIC) is
		begin
			wait until rising_edge(clk_w);
			cs_w		<= cs;
			memwr_w		<= wr;
			memrd_w		<= '0';
			sel_w		<= sel;
			data_wr_w	<= data;
			wait until falling_edge(clk_w);
			wait for 1 ns;
			cs_w		<= '0';
			memwr_w		<= '0';
		end procedure;

		-- The read path is combinational, so no edge is needed.
		procedure bus_read(sel : STD_LOGIC; expected : STD_LOGIC_VECTOR; msg : string) is
		begin
			wait until rising_edge(clk_w);
			cs_w		<= '1';
			memrd_w		<= '1';
			memwr_w		<= '0';
			sel_w		<= sel;
			wait for 2 ns;
			check(data_rd_w = expected,
				  msg & " : data_rd_o = " & img(data_rd_w) & ", expected " & img(expected));
			cs_w		<= '0';
			memrd_w		<= '0';
			wait for 1 ns;
		end procedure;

		--- display checks ---------------------------------------------------
		procedure check_digits(lo : STD_LOGIC_VECTOR(3 DOWNTO 0);
							   hi : STD_LOGIC_VECTOR(3 DOWNTO 0);
							   msg : string) is
		begin
			check(hex_lo_w = seg_low(lo),
				  msg & " : HEX_lo_o = " & img(hex_lo_w) & ", expected " & img(seg_low(lo)));
			check(hex_hi_w = seg_low(hi),
				  msg & " : HEX_hi_o = " & img(hex_hi_w) & ", expected " & img(seg_low(hi)));
			-- 12: the active high build must be the exact complement
			check(hex_lo_ah_w = NOT hex_lo_w, msg & " : ACTIVE_LOW generic not honoured on the low digit");
			check(hex_hi_ah_w = NOT hex_hi_w, msg & " : ACTIVE_LOW generic not honoured on the high digit");
		end procedure;

	begin
		report "=== GPIO_HEX_Pair_Interface testbench start ===" severity note;

		--===============================================================
		-- 1  Reset
		--===============================================================
		rst_w <= '1';
		wait for 2*CLK_PERIOD;
		wait until falling_edge(clk_w);
		wait for 1 ns;

		check_digits("0000", "0000", "T1 reset, both displays show 0");
		rst_w <= '0';
		wait until rising_edge(clk_w);

		bus_read('0', zext(0), "T1 reset, low register reads 0");
		bus_read('1', zext(0), "T1 reset, high register reads 0");

		--===============================================================
		-- 2/3  A store hits exactly one digit of the pair
		--===============================================================
		bus_write('0', zext(5));
		check_digits("0101", "0000", "T2 store 5 to the low digit");
		bus_read('0', zext(5), "T2 low digit reads back 5");
		bus_read('1', zext(0), "T3 high digit untouched by the low store");

		bus_write('1', zext(10));
		check_digits("0101", "1010", "T2 store A to the high digit");
		bus_read('1', zext(10), "T2 high digit reads back A");
		bus_read('0', zext(5), "T3 low digit untouched by the high store");

		--===============================================================
		-- 4/5  Every digit value, on both halves of the pair
		--===============================================================
		for v in 0 to 15 loop
			bus_write('0', zext(v));
			check_digits(nibble(v), "1010", "T4 low digit value " & integer'image(v));
			bus_read('0', zext(v), "T5 low digit read back, value " & integer'image(v));
			bus_read('1', zext(10), "T3 high digit stable during the low sweep");
		end loop;

		for v in 0 to 15 loop
			bus_write('1', zext(v));
			check_digits("1111", nibble(v), "T4 high digit value " & integer'image(v));
			bus_read('1', zext(v), "T5 high digit read back, value " & integer'image(v));
			bus_read('0', zext(15), "T3 low digit stable during the high sweep");
		end loop;

		-- both digits now hold F
		bus_write('0', zext(15));
		bus_write('1', zext(15));
		check_digits("1111", "1111", "T4 both digits hold F");

		--===============================================================
		-- 6  A store without chip select is ignored
		--===============================================================
		bus_write_blocked('0', zext(3), '0', '1');
		check_digits("1111", "1111", "T6 store with cs_i='0' must not change the displays");
		bus_read('0', zext(15), "T6 store with cs_i='0' must not change the register");

		--===============================================================
		-- 7  A store without MemWrite is ignored
		--===============================================================
		bus_write_blocked('1', zext(3), '1', '0');
		check_digits("1111", "1111", "T7 store with MemWrite_ctrl_i='0' must not change the displays");
		bus_read('1', zext(15), "T7 store with MemWrite_ctrl_i='0' must not change the register");

		--===============================================================
		-- 8  The port register is a byte : stored whole, displayed by nibble
		--===============================================================
		-- Only bits above the port width may be dropped; the byte itself must
		-- survive a store and come back on a load, even though the display can
		-- show no more than its low nibble.
		bus_write('0', x"DEADBEE3");
		check_digits("0011", "1111", "T8 the display shows the low nibble of the stored byte");
		bus_read('0', zext(16#E3#), "T8 the whole byte must read back, upper bus bits dropped");

		bus_write('1', zext(16#AB#));
		check_digits("0011", "1011", "T8 high digit shows B out of the stored AB");
		bus_read('1', zext(16#AB#), "T8 high port register must return AB, not 0B");

		-- back to a known state for the timing test
		bus_write('0', zext(3));
		bus_write('1', zext(15));
		check_digits("0011", "1111", "T8 state restored before the timing test");

		--===============================================================
		-- 9  The read bus is released when the device is not addressed
		--===============================================================
		wait until rising_edge(clk_w);
		cs_w	<= '0';
		memrd_w	<= '1';
		sel_w	<= '0';
		wait for 2 ns;
		check(data_rd_w = zext(0), "T9 data_rd_o must be all zeros when cs_i='0'");

		cs_w	<= '1';
		memrd_w	<= '0';
		wait for 2 ns;
		check(data_rd_w = zext(0), "T9 data_rd_o must be all zeros when MemRead_ctrl_i='0'");
		cs_w	<= '0';

		--===============================================================
		-- 10  The capture edge is the falling one
		--===============================================================
		-- Present a new value right after a rising edge. Until the falling
		-- edge arrives the display must still show the previous digit; only
		-- after it may it change.
		wait until rising_edge(clk_w);
		cs_w		<= '1';
		memwr_w		<= '1';
		sel_w		<= '0';
		data_wr_w	<= zext(9);
		wait for CLK_HALF/2;		-- still inside the high phase
		check_digits("0011", "1111", "T10 no capture before the falling edge");
		wait until falling_edge(clk_w);
		wait for 1 ns;
		check_digits("1001", "1111", "T10 capture on the falling edge");
		cs_w		<= '0';
		memwr_w		<= '0';

		--===============================================================
		-- 11  Reset is asynchronous
		--===============================================================
		bus_write('1', zext(12));
		check_digits("1001", "1100", "T11 setup before the asynchronous reset");

		wait until rising_edge(clk_w);
		wait for CLK_HALF/4;		-- nowhere near a clock edge
		rst_w <= '1';
		wait for 1 ns;
		check_digits("0000", "0000", "T11 reset must clear both registers immediately");
		rst_w <= '0';
		wait until rising_edge(clk_w);
		bus_read('0', zext(0), "T11 low register cleared by reset");
		bus_read('1', zext(0), "T11 high register cleared by reset");

		-- and the device still works afterwards
		bus_write('0', zext(7));
		bus_write('1', zext(1));
		check_digits("0111", "0001", "T11 normal operation resumes after reset");

		--===============================================================
		report "=== GPIO_HEX_Pair_Interface testbench done ===" severity note;
		if errors = 0 then
			report "PASS: all checks passed" severity note;
		else
			report "FAILED: " & integer'image(errors) & " check(s) failed" severity error;
		end if;

		done_w <= TRUE;
		wait;
	end process;

END sim;