---------------------------------------------------------------------------------------------
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- tb_int_service - self checking testbench for CONTROL's interrupt service state machine
-- (clause 6.v, page 15)
--
-- CONTROL is instantiated alone. gp_i, int_ret_addr_i and bus_rdata_i are driven by hand to
-- stand in for IDECODE, IFETCH and the data bus respectively - the closed loop through
-- INT_CTRL.vhd and MCU.vhd does not exist until step 4, so this is the last point at which
-- the state machine can be exercised in isolation. Once MCU.vhd connects gie_w, it is only
-- observable through a full-system run.
--
-- The generic map (PC_WIDTH=13, DA_WIDTH=14, DATA_BUS_WIDTH=32) matches the project's real
-- 8 KiB TCM configuration (cond_compilation_package.vhd), not the component defaults, so the
-- widths this test exercises are the ones the benchmark actually uses.
--
-- Checks:
--    1. idle: inta_n_o high, int_hold_o/int_pc_we_o/int_rf_we_o/int_addr_we_o/int_mem_read_o
--       all low, and the ordinary decoder outputs are unaffected by any interrupt input
--    2. intr_i rising: inta_n_o goes low on the NEXT cycle, not the same one
--    3. cycle 1: inta_n_o low, int_hold_o high, the hardware write clears bit 0 of gp while
--       preserving the other bits, and bus_rdata_i (TYPE) is captured into a dedicated
--       register rather than passed through combinationally
--    4. cycle 1 to cycle 2: inta_n_o returns high
--    5. cycle 2: int_addr_we_o high with int_addr_o equal to the captured TYPE, zero
--       extended; int_mem_read_o high; int_pc_we_o high with int_pc_o equal to bus_rdata_i
--       (Mem[TYPE]); the hardware write puts the return address captured at the start of
--       cycle 1 into x4 (tp)
--    6. after cycle 2: back to idle, everything released
--    7. intr_i high while div_busy_i is high produces no entry at all, and entry happens
--       normally on the cycle after div_busy_i falls
--    8. intr_i rising and falling again before the next sampling edge produces no entry -
--       this is a synchronous design and only the value at the edge decides entry
--    9. reti (jalr zero, 0(tp)) decoded at idle: GIE set through the hardware write, and
--       Jalr_ctrl_o still asserted - the jump itself is not suppressed
--   10. an ordinary jalr with different operands (rd, rs1 both different from reti's):
--       no GIE write, Jalr_ctrl_o still asserted
--   11. asynchronous reset mid-protocol returns to idle immediately, without waiting for a
--       clock edge
--
-- Run:  vcom CONTROL.VHD tb_int_service.vhd
--       vsim -voptargs=+acc work.tb_int_service
--       run -all
---------------------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY tb_int_service IS
END tb_int_service;
---------------------------------------------------------------------------------------------
ARCHITECTURE sim OF tb_int_service IS

	CONSTANT DATA_BUS_WIDTH	: integer := 32;
	CONSTANT PC_WIDTH		: integer := 13;	-- matches G_PC_WIDTH, the project's 8 KiB TCM configuration
	CONSTANT DA_WIDTH		: integer := 14;	-- matches G_DA_WIDTH

	CONSTANT CLK_PERIOD	: time := 40 ns;	-- 25 MHz MCLK
	CONSTANT CLK_HALF		: time := CLK_PERIOD/2;
	CONSTANT HOLD			: time :=  2 ns;
	CONSTANT SETTLE			: time :=  1 ns;	-- offset after an edge, when stimulus changes

	-- x3 (gp) and x4 (tp), the two hardware write-port destinations, from the ISA side -
	-- deliberately not copied from CONTROL's own internal constants, so a wrong constant on
	-- either side shows up as a mismatch instead of being mirrored on both.
	CONSTANT GP_REG			: STD_LOGIC_VECTOR(4 DOWNTO 0) := "00011";
	CONSTANT TP_REG			: STD_LOGIC_VECTOR(4 DOWNTO 0) := "00100";

	-- add x1, x2, x3 - an ordinary R-type instruction with no interrupt-related side effect,
	-- used as the "background" instruction throughout so idle behaviour and reti/jalr
	-- decoding can each be checked against a known-benign default.
	CONSTANT INST_ADD		: STD_LOGIC_VECTOR(31 DOWNTO 0) := x"003100B3";

	-- jalr zero, 0(tp): rd=x0, rs1=x4, imm=0 - the exact bit pattern CONTROL.VHD decodes as
	-- reti. Computed from the ISA fields, not copied from the DUT.
	CONSTANT INST_RETI		: STD_LOGIC_VECTOR(31 DOWNTO 0) := x"00020067";

	-- jalr ra, 0(x5): an ordinary jalr whose rd and rs1 both differ from reti's. Must jump
	-- like any jalr, and must NOT be mistaken for a return.
	CONSTANT INST_JALR_OTHER	: STD_LOGIC_VECTOR(31 DOWNTO 0) := x"000280E7";

	CONSTANT ZERO_BUS		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0) := (OTHERS => '0');

	-- An arbitrary, recognisable Mem[TYPE] value for T6 - PC_WIDTH bits wide, zero extended
	-- onto the bus by hand at the point of use, so the same 13 bit pattern can also be
	-- compared directly against int_pc_o without repeating the literal.
	CONSTANT MEM_TYPE_LOW	: STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0) := "1" & x"55" & "1010";

	-- A downto range choice inside an inline aggregate concatenation leaves the index
	-- direction ambiguous and vcom warns (1514, matching the note in INT_CTRL.vhd) - a
	-- named constant with its own declared range sidesteps that instead of suppressing it.
	CONSTANT PAD_PC_TO_BUS	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO PC_WIDTH) := (OTHERS => '0');

	-- An arbitrary, recognisable "next PC" value for T3/T6 - the return address CONTROL
	-- must capture at the start of cycle 1 and still be holding when it writes tp in cycle 2.
	CONSTANT RET_ADDR		: STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0) := "1" & x"23" & "0011";

	--DUT connections
	SIGNAL clk_w			: STD_LOGIC := '0';
	SIGNAL rst_w			: STD_LOGIC := '1';
	SIGNAL instruction_w	: STD_LOGIC_VECTOR(31 DOWNTO 0) := INST_ADD;
	SIGNAL intr_w			: STD_LOGIC := '0';
	SIGNAL div_busy_w		: STD_LOGIC := '0';
	SIGNAL gp_w				: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL int_ret_addr_w	: STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL bus_rdata_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0) := (OTHERS => '0');

	SIGNAL RegWrite_ctrl_w	: STD_LOGIC;
	SIGNAL Jalr_ctrl_w		: STD_LOGIC;

	SIGNAL inta_n_w			: STD_LOGIC;
	SIGNAL int_hold_w		: STD_LOGIC;
	SIGNAL int_addr_we_w	: STD_LOGIC;
	SIGNAL int_addr_w		: STD_LOGIC_VECTOR(DA_WIDTH-1 DOWNTO 0);
	SIGNAL int_mem_read_w	: STD_LOGIC;
	SIGNAL int_pc_we_w		: STD_LOGIC;
	SIGNAL int_pc_w			: STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
	SIGNAL int_rf_we_w		: STD_LOGIC;
	SIGNAL int_rf_rd_w		: STD_LOGIC_VECTOR(4 DOWNTO 0);
	SIGNAL int_rf_data_w	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

	SIGNAL done_w			: BOOLEAN := FALSE;

	--Zero extend a TYPE byte to the address bus width
	FUNCTION zext_addr(v : STD_LOGIC_VECTOR(7 DOWNTO 0)) RETURN STD_LOGIC_VECTOR IS
		VARIABLE r : STD_LOGIC_VECTOR(DA_WIDTH-1 DOWNTO 0) := (OTHERS => '0');
	BEGIN
		r(7 DOWNTO 0) := v;
		RETURN r;
	END FUNCTION;

	--Zero extend a captured return address to the data bus width
	FUNCTION zext_data(v : STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0)) RETURN STD_LOGIC_VECTOR IS
		VARIABLE r : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0) := (OTHERS => '0');
	BEGIN
		r(PC_WIDTH-1 DOWNTO 0) := v;
		RETURN r;
	END FUNCTION;

BEGIN

	--=======================================
	-- DUT
	--=======================================
	DUT: entity work.control
	generic map(
		DATA_BUS_WIDTH	=> DATA_BUS_WIDTH,
		PC_WIDTH		=> PC_WIDTH,
		DA_WIDTH		=> DA_WIDTH
	)
	PORT MAP (
		instruction_i		=> instruction_w,
		clk_i				=> clk_w,
		rst_i				=> rst_w,
		intr_i				=> intr_w,
		div_busy_i			=> div_busy_w,
		gp_i				=> gp_w,
		int_ret_addr_i		=> int_ret_addr_w,
		bus_rdata_i			=> bus_rdata_w,

		RegDst_ctrl_o		=> OPEN,
		ALUSrc_ctrl_o		=> OPEN,
		MemtoReg_ctrl_o		=> OPEN,
		RegWrite_ctrl_o		=> RegWrite_ctrl_w,
		MemRead_ctrl_o		=> OPEN,
		MemWrite_ctrl_o		=> OPEN,
		Branch_ctrl_o		=> OPEN,
		Jal_ctrl_o			=> OPEN,
		Jalr_ctrl_o			=> Jalr_ctrl_w,
		UpperIm_ctrl_o		=> OPEN,
		ALUOp_ctrl_o		=> OPEN,
		MULOp_ctrl_o		=> OPEN,
		DIVOp_ctrl_o		=> OPEN,
		DIVSigned_ctrl_o	=> OPEN,
		DIVRem_ctrl_o		=> OPEN,

		inta_n_o			=> inta_n_w,
		int_hold_o			=> int_hold_w,
		int_addr_we_o		=> int_addr_we_w,
		int_addr_o			=> int_addr_w,
		int_mem_read_o		=> int_mem_read_w,
		int_pc_we_o			=> int_pc_we_w,
		int_pc_o			=> int_pc_w,
		int_rf_we_o			=> int_rf_we_w,
		int_rf_rd_o			=> int_rf_rd_w,
		int_rf_data_o		=> int_rf_data_w
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

		procedure check_bit(got : STD_LOGIC; exp : STD_LOGIC; msg : string) is
		begin
			checks_v := checks_v + 1;
			if got /= exp then
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

		-- The four "protocol is running" outputs, checked together often enough that a
		-- helper avoids repeating all four at every call site.
		procedure check_released(msg : string) is
		begin
			check_bit(inta_n_w,       '1', msg & " - inta_n_o must be idle high");
			check_bit(int_hold_w,     '0', msg & " - int_hold_o must be low");
			check_bit(int_addr_we_w,  '0', msg & " - int_addr_we_o must be low");
			check_bit(int_mem_read_w, '0', msg & " - int_mem_read_o must be low");
			check_bit(int_pc_we_w,    '0', msg & " - int_pc_we_o must be low");
		end procedure;

	begin
		report "=== tb_int_service start ===" severity note;

		--===============================================================
		-- T1  Reset
		--===============================================================
		rst_w			<= '1';
		instruction_w	<= INST_ADD;
		intr_w			<= '0';
		div_busy_w		<= '0';
		gp_w			<= (OTHERS => '0');
		int_ret_addr_w	<= (OTHERS => '0');
		bus_rdata_w		<= (OTHERS => '0');
		wait for 2*CLK_PERIOD;

		check_released("T1 reset");
		check_bit(int_rf_we_w, '0', "T1 int_rf_we_o must be low after reset");

		wait until rising_edge(clk_w);
		rst_w <= '0';
		wait for HOLD;

		--===============================================================
		-- T2  Idle: released, and the ordinary decoder is unaffected
		--===============================================================
		wait for SETTLE;
		check_released("T2 idle");
		check_bit(int_rf_we_w, '0', "T2 idle - no hardware write for an ordinary add");
		check_bit(RegWrite_ctrl_w, '1', "T2 idle - RegWrite_ctrl_o still reflects add's own decode");
		check_bit(Jalr_ctrl_w, '0', "T2 idle - Jalr_ctrl_o low for an ordinary add");

		--===============================================================
		-- T3  intr_i rising: inta_n_o falls on the NEXT cycle, not this one
		--===============================================================
		gp_w			<= x"000000C5";			-- bit 0 = 1 (GIE set), other bits distinct
		int_ret_addr_w	<= RET_ADDR;
		wait until rising_edge(clk_w);
		wait for SETTLE;
		intr_w <= '1';
		wait for HOLD;
		check_bit(inta_n_w, '1', "T3 inta_n_o must not fall the same cycle intr_i rises");

		wait until rising_edge(clk_w);		-- the "next clock cycle" page 15 refers to
		wait for SETTLE;
		check_bit(inta_n_w, '0', "T3 inta_n_o falls exactly one cycle after intr_i rose");

		--===============================================================
		-- T4  Cycle 1: hold, the hardware clear of GIE, TYPE captured not passed through
		--===============================================================
		check_bit(int_hold_w, '1', "T4 cycle 1 - int_hold_o must be high");
		check_bit(int_rf_we_w, '1', "T4 cycle 1 - hardware write must be asserted");
		check_vec(int_rf_rd_w, GP_REG, "T4 cycle 1 - hardware write targets gp (x3)");
		check_vec(int_rf_data_w, x"000000C4",
				  "T4 cycle 1 - GIE cleared, the other bits of gp preserved");

		-- TYPE appears on the bus now, exactly as INT_CTRL.vhd would drive it while
		-- inta_n_o is low. Held only for this cycle - changed again before cycle 2 so a
		-- capture-vs-passthrough bug shows up as the wrong byte in cycle 2, not the right
		-- one by coincidence.
		bus_rdata_w <= x"00000014";	-- TYPE = 14h (arbitrary, matches no real vector on purpose)

		wait until rising_edge(clk_w);		-- cycle 1 -> cycle 2; type_reg_q captures now
		wait for SETTLE;

		--===============================================================
		-- T5  Cycle 1 to cycle 2: inta_n_o returns high
		--===============================================================
		check_bit(inta_n_w, '1', "T5 inta_n_o returns high in cycle 2");
		check_bit(int_hold_w, '1', "T5 int_hold_o stays high in cycle 2");

		--===============================================================
		-- T6  Cycle 2: the emulated load of Mem[TYPE], the PC injection, tp written
		--===============================================================
		-- Mem[TYPE] appears on the bus now that CONTROL is driving int_addr_o - a
		-- different value from cycle 1's, so int_pc_o being right proves it is reading
		-- THIS cycle's bus_rdata_i, not the byte captured for TYPE.
		bus_rdata_w <= PAD_PC_TO_BUS & MEM_TYPE_LOW;
		wait for HOLD;

		check_bit(int_addr_we_w, '1', "T6 cycle 2 - int_addr_we_o must be high");
		check_vec(int_addr_w, zext_addr(x"14"), "T6 cycle 2 - int_addr_o is the captured TYPE");
		check_bit(int_mem_read_w, '1', "T6 cycle 2 - int_mem_read_o must be high");
		check_bit(int_pc_we_w, '1', "T6 cycle 2 - int_pc_we_o must be high");
		check_vec(int_pc_w, MEM_TYPE_LOW,
				  "T6 cycle 2 - int_pc_o is this cycle's Mem[TYPE], not cycle 1's TYPE");

		check_bit(int_rf_we_w, '1', "T6 cycle 2 - hardware write must be asserted");
		check_vec(int_rf_rd_w, TP_REG, "T6 cycle 2 - hardware write targets tp (x4)");
		check_vec(int_rf_data_w, zext_data(RET_ADDR),
				  "T6 cycle 2 - tp gets the return address captured at the start of cycle 1");

		--===============================================================
		-- T7  After cycle 2: back to idle, everything released
		--===============================================================
		intr_w		<= '0';				-- do not re-enter on the very next cycle
		bus_rdata_w	<= (OTHERS => '0');

		wait until rising_edge(clk_w);		-- cycle 2 -> idle
		wait for SETTLE;
		check_released("T7 after cycle 2");
		check_bit(int_rf_we_w, '0', "T7 after cycle 2 - hardware write released");

		--===============================================================
		-- T8  Entry is blocked while div_busy_i is high
		--===============================================================
		div_busy_w	<= '1';
		intr_w		<= '1';
		for i in 1 to 3 loop
			wait until rising_edge(clk_w);
			wait for SETTLE;
			check_released("T8 blocked by div_busy_i, cycle " & integer'image(i));
		end loop;

		-- div_busy_i falls mid cycle; entry commits on the very next rising edge, exactly
		-- one cycle after the fall, same as an ordinary entry.
		wait for SETTLE;
		div_busy_w <= '0';
		wait until rising_edge(clk_w);
		wait for SETTLE;
		check_bit(inta_n_w, '0',
				  "T8 entry proceeds on the cycle after div_busy_i falls");

		-- Drain this service back to idle before the next test, using the same two-cycle
		-- shape as T4-T7, without re-checking every field again.
		wait until rising_edge(clk_w);		-- cycle 1 -> cycle 2
		wait for SETTLE;
		wait until rising_edge(clk_w);		-- cycle 2 -> idle
		wait for SETTLE;
		intr_w <= '0';
		check_released("T8 drained back to idle");

		--===============================================================
		-- T9  intr_i rising and falling again before the sampling edge: no entry
		--===============================================================
		-- INTR is a level (INT_CTRL.vhd: intr_o <= gie_i WHEN ifg_w /= 0), not a pulse.
		-- This design samples it synchronously, like every other input CONTROL reads, so a
		-- rise-and-fall entirely between two rising edges is simply never observed - the
		-- same behaviour any synchronous input would have. Documented here, not treated
		-- as a special case in CONTROL.VHD.
		wait until rising_edge(clk_w);
		wait for SETTLE;
		intr_w <= '1';
		wait for CLK_HALF/4;			-- comfortably clear of the next rising edge
		intr_w <= '0';
		for i in 1 to 2 loop
			wait until rising_edge(clk_w);
			wait for SETTLE;
			check_released("T9 glitch before the sampling edge, cycle " & integer'image(i));
		end loop;

		--===============================================================
		-- T10  reti: GIE set through the hardware write, jump not suppressed
		--===============================================================
		instruction_w	<= INST_RETI;
		gp_w			<= x"00000032";		-- bit 0 = 0 (GIE clear) beforehand
		wait for SETTLE;
		check_bit(int_rf_we_w, '1', "T10 reti - hardware write must be asserted");
		check_vec(int_rf_rd_w, GP_REG, "T10 reti - hardware write targets gp (x3)");
		check_vec(int_rf_data_w, x"00000033", "T10 reti - GIE set, the other bits preserved");
		check_bit(Jalr_ctrl_w, '1', "T10 reti - Jalr_ctrl_o still asserted, the jump is not suppressed");

		--===============================================================
		-- T11  An ordinary jalr with different operands: no GIE write
		--===============================================================
		instruction_w <= INST_JALR_OTHER;
		wait for SETTLE;
		check_bit(int_rf_we_w, '0', "T11 ordinary jalr - no hardware write");
		check_bit(Jalr_ctrl_w, '1', "T11 ordinary jalr - Jalr_ctrl_o still asserted");

		instruction_w <= INST_ADD;
		wait for SETTLE;

		--===============================================================
		-- T12  Asynchronous reset mid protocol
		--===============================================================
		div_busy_w	<= '0';
		intr_w		<= '1';
		wait until rising_edge(clk_w);
		wait for SETTLE;
		check_bit(inta_n_w, '0', "T12 entered cycle 1 before the reset");

		wait for CLK_HALF/4;			-- nowhere near an active edge
		rst_w <= '1';
		wait for HOLD;
		check_released("T12 asynchronous reset mid cycle 1, before any clock edge");
		check_bit(int_rf_we_w, '0', "T12 asynchronous reset - hardware write released too");

		rst_w	<= '0';
		intr_w	<= '0';
		wait until rising_edge(clk_w);
		wait for HOLD;
		check_released("T12 idle again after the reset is released");

		--===============================================================
		report "==================================================" severity note;
		report "checks run : " & integer'image(checks_v) severity note;
		report "failures   : " & integer'image(errors_v) severity note;
		if errors_v = 0 then
			report "ALL int_service TESTS PASSED" severity note;
		else
			report "int_service : THERE ARE FAILURES" severity failure;
		end if;
		report "==================================================" severity note;

		done_w <= TRUE;
		wait;
	end process;

END sim;
