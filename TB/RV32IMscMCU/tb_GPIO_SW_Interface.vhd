---------------------------------------------------------------------------------------------
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Self checking testbench for GPIO_SW_Interface (PORT_SW, byte address 0x2010)
--
-- The DUT is purely combinational, so this testbench has no clock at all: it drives the
-- inputs, waits for the delta cycles to settle, and compares data_rd_o against the value
-- the specification requires. Every mismatch is reported and counted; the run ends with a
-- summary and a failure assertion if anything went wrong, so it can be used as a pass/fail
-- gate and not only watched as a waveform.
--
-- What is covered
--   1. Bus arbitration : the port drives zeros for every combination of cs_i and
--      MemRead_ctrl_i except (1,1) - this is what lets the I/O read paths be OR-ed together.
--   2. Store is ignored : the module has no write path, so a store cycle to its address
--      (cs_i='1', MemRead_ctrl_i='0') must not put anything on the bus.
--   3. Data integrity : exhaustive sweep of all 256 switch patterns, checked against the
--      zero extended expected word, in all four control combinations (1024 checks).
--   4. Zero extension : bits 31..8 are never anything but zero.
--   5. No stored state : the value follows the pins immediately while selected, and a
--      pattern changed while the port is deselected is visible on the next read - this is
--      what distinguishes the GPI of Figure 5 from a latched GPO port.
--   6. Unknown controls : cs_i or MemRead_ctrl_i at 'X'/'U'/'Z' must not open the port.
--   7. Unknown data : an undriven switch pin must reach the bus as is when the port is
--      selected, i.e. the module must not silently mask it into a clean value.
--   8. Generic boundaries : a narrow instance (SW_WIDTH=4) and the degenerate instance
--      SW_WIDTH = DATA_BUS_WIDTH, where the zero extension slice becomes a null range.
--
-- Compiles under VHDL-93 and later; no VHDL-2008 constructs are used here.
---------------------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY tb_GPIO_SW_Interface IS
END tb_GPIO_SW_Interface;
---------------------------------------------------------------------------------------------
ARCHITECTURE test OF tb_GPIO_SW_Interface IS

	CONSTANT DATA_BUS_WIDTH	: integer := 32;
	CONSTANT SW_WIDTH		: integer := 8;
	CONSTANT NARROW_WIDTH	: integer := 4;		-- narrow instance
	CONSTANT FULL_WIDTH		: integer := 32;	-- degenerate instance, null zero extension slice

	CONSTANT SETTLE			: time := 1 ns;		-- combinational settling allowance
	CONSTANT STEP			: time := 10 ns;	-- one "bus cycle" of the testbench

	CONSTANT ZERO_WORD		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0) := (OTHERS => '0');

	--Main instance, the one the MCU uses : SW7..SW0 at 0x2010
	SIGNAL cs_w				: STD_LOGIC := '0';
	SIGNAL rd_w				: STD_LOGIC := '0';
	SIGNAL sw_w				: STD_LOGIC_VECTOR(SW_WIDTH-1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL data_w			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

	--Narrow instance
	SIGNAL cs_n_w			: STD_LOGIC := '0';
	SIGNAL rd_n_w			: STD_LOGIC := '0';
	SIGNAL sw_n_w			: STD_LOGIC_VECTOR(NARROW_WIDTH-1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL data_n_w			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

	--Degenerate instance, port as wide as the data bus
	SIGNAL cs_f_w			: STD_LOGIC := '0';
	SIGNAL rd_f_w			: STD_LOGIC := '0';
	SIGNAL sw_f_w			: STD_LOGIC_VECTOR(FULL_WIDTH-1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL data_f_w			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

	--=======================================
	-- Helpers
	--=======================================
	-- Printable form of a vector. std_logic_vector'image and to_string are VHDL-2008,
	-- and this testbench deliberately stays VHDL-93 clean.
	function slv_image(v : STD_LOGIC_VECTOR) return STRING is
		variable s_v	: STRING(1 TO v'length);
		variable i_v	: natural := 1;
	begin
		for k in v'range loop
			case v(k) is
				when '0' 	=> s_v(i_v) := '0';
				when '1' 	=> s_v(i_v) := '1';
				when 'X' 	=> s_v(i_v) := 'X';
				when 'U' 	=> s_v(i_v) := 'U';
				when 'Z' 	=> s_v(i_v) := 'Z';
				when 'W' 	=> s_v(i_v) := 'W';
				when 'L' 	=> s_v(i_v) := 'L';
				when 'H' 	=> s_v(i_v) := 'H';
				when others => s_v(i_v) := '-';
			end case;
			i_v := i_v + 1;
		end loop;
		return s_v;
	end function;

	-- The word the specification requires on a successful read: the port value in the
	-- low bits, zeros everywhere above it.
	function expected_word(v : STD_LOGIC_VECTOR) return STD_LOGIC_VECTOR is
		variable r_v	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0) := (OTHERS => '0');
	begin
		r_v(v'length-1 DOWNTO 0) := v;
		return r_v;
	end function;

BEGIN

	--=======================================
	-- Devices under test
	--=======================================
	DUT: entity work.GPIO_SW_Interface
	generic map(
		DATA_BUS_WIDTH	=> DATA_BUS_WIDTH,
		SW_WIDTH		=> SW_WIDTH
	)
	PORT MAP (
		cs_i			=> cs_w,
		MemRead_ctrl_i	=> rd_w,
		SW_i			=> sw_w,
		data_rd_o		=> data_w
	);

	DUT_NARROW: entity work.GPIO_SW_Interface
	generic map(
		DATA_BUS_WIDTH	=> DATA_BUS_WIDTH,
		SW_WIDTH		=> NARROW_WIDTH
	)
	PORT MAP (
		cs_i			=> cs_n_w,
		MemRead_ctrl_i	=> rd_n_w,
		SW_i			=> sw_n_w,
		data_rd_o		=> data_n_w
	);

	DUT_FULL: entity work.GPIO_SW_Interface
	generic map(
		DATA_BUS_WIDTH	=> DATA_BUS_WIDTH,
		SW_WIDTH		=> FULL_WIDTH
	)
	PORT MAP (
		cs_i			=> cs_f_w,
		MemRead_ctrl_i	=> rd_f_w,
		SW_i			=> sw_f_w,
		data_rd_o		=> data_f_w
	);

	--=======================================
	-- Stimulus and checking
	--=======================================
	STIM:
	process
		variable errors_v	: natural := 0;
		variable checks_v	: natural := 0;

		procedure check(constant tag_c    : in STRING;
						constant actual_c : in STD_LOGIC_VECTOR;
						constant expect_c : in STD_LOGIC_VECTOR) is
		begin
			checks_v := checks_v + 1;
			if actual_c /= expect_c then
				errors_v := errors_v + 1;
				report "FAIL [" & tag_c & "] expected " & slv_image(expect_c) &
					   " , got " & slv_image(actual_c)
					severity error;
			end if;
		end procedure;

		-- One full read cycle on the main instance: drive, settle, compare.
		procedure access_and_check(constant tag_c	: in STRING;
								   constant cs_c	: in STD_LOGIC;
								   constant rd_c	: in STD_LOGIC;
								   constant sw_c	: in STD_LOGIC_VECTOR(SW_WIDTH-1 DOWNTO 0)) is
		begin
			cs_w <= cs_c;
			rd_w <= rd_c;
			sw_w <= sw_c;
			wait for SETTLE;
			if (cs_c = '1' AND rd_c = '1') then
				check(tag_c, data_w, expected_word(sw_c));
			else
				check(tag_c, data_w, ZERO_WORD);
			end if;
		end procedure;

		variable sw_v		: STD_LOGIC_VECTOR(SW_WIDTH-1 DOWNTO 0);
		variable exp_v		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	begin
		report "tb_GPIO_SW_Interface : start" severity note;

		--------------------------------------------------------------------------------
		-- 1. Idle bus. Nothing is selected, the switches are held at a non-zero pattern
		--    so that a leaking read path shows up as a mismatch and not as a lucky zero.
		--------------------------------------------------------------------------------
		access_and_check("idle, cs=0 rd=0, SW=A5", '0', '0', x"A5");
		wait for STEP;

		--------------------------------------------------------------------------------
		-- 2. Another device is being read. cs_i is low, so this port must stay silent
		--    even though a load is in progress - otherwise the OR of the I/O read paths
		--    would corrupt every DTCM and every other peripheral read in the system.
		--------------------------------------------------------------------------------
		access_and_check("other device read, cs=0 rd=1, SW=A5", '0', '1', x"A5");
		wait for STEP;

		--------------------------------------------------------------------------------
		-- 3. Store to this address. PORT_SW is a GPI, a store must have no visible
		--    effect at all - and in particular must not drive the read path.
		--------------------------------------------------------------------------------
		access_and_check("store to 0x2010, cs=1 rd=0, SW=A5", '1', '0', x"A5");
		wait for STEP;

		--------------------------------------------------------------------------------
		-- 4. The one legal access: selected and reading.
		--------------------------------------------------------------------------------
		access_and_check("load 0x2010, cs=1 rd=1, SW=A5", '1', '1', x"A5");
		wait for STEP;

		--------------------------------------------------------------------------------
		-- 5. Walking ones and walking zeros: each switch reaches its own bus bit, no
		--    swaps, no shorts between adjacent bits.
		--------------------------------------------------------------------------------
		for i in 0 to SW_WIDTH-1 loop
			sw_v := (OTHERS => '0');
			sw_v(i) := '1';
			access_and_check("walking one", '1', '1', sw_v);
			wait for SETTLE;

			sw_v := (OTHERS => '1');
			sw_v(i) := '0';
			access_and_check("walking zero", '1', '1', sw_v);
			wait for SETTLE;
		end loop;
		wait for STEP;

		--------------------------------------------------------------------------------
		-- 6. Exhaustive sweep. All 256 patterns against all four control combinations.
		--    This is where the zero extension of bits 31..8 is proved for every value:
		--    expected_word builds the upper bits as zeros independently of the DUT.
		--------------------------------------------------------------------------------
		for value in 0 to 2**SW_WIDTH - 1 loop
			sw_v := STD_LOGIC_VECTOR(to_unsigned(value, SW_WIDTH));
			access_and_check("sweep cs=0 rd=0", '0', '0', sw_v);
			access_and_check("sweep cs=0 rd=1", '0', '1', sw_v);
			access_and_check("sweep cs=1 rd=0", '1', '0', sw_v);
			access_and_check("sweep cs=1 rd=1", '1', '1', sw_v);
		end loop;
		wait for STEP;

		--------------------------------------------------------------------------------
		-- 7. Transparency. While the port is selected the bus must follow the pins with
		--    no clock and no enable pulse, exactly as the tri-state buffer of Figure 5.
		--------------------------------------------------------------------------------
		cs_w <= '1';
		rd_w <= '1';
		sw_w <= x"0F";
		wait for SETTLE;
		check("transparent, first value", data_w, expected_word(STD_LOGIC_VECTOR'(x"0F")));

		sw_w <= x"F0";			-- change the pins without touching the controls
		wait for SETTLE;
		check("transparent, follows pins", data_w, expected_word(STD_LOGIC_VECTOR'(x"F0")));
		wait for STEP;

		--------------------------------------------------------------------------------
		-- 8. No stored state. Deselect, move the switches while nobody is looking, then
		--    read again: a GPI must report the pins as they are now. If a latch or a
		--    register had crept into this module, the old value would come back here.
		--------------------------------------------------------------------------------
		cs_w <= '0';
		rd_w <= '0';
		wait for SETTLE;
		check("deselected after read", data_w, ZERO_WORD);

		sw_w <= x"3C";			-- moved while the port is not selected
		wait for STEP;

		cs_w <= '1';
		rd_w <= '1';
		wait for SETTLE;
		check("no stored state", data_w, expected_word(STD_LOGIC_VECTOR'(x"3C")));
		wait for STEP;

		--------------------------------------------------------------------------------
		-- 9. Unknown or floating control lines. Before the address decoder is reset, or
		--    on an unconnected chip select, cs_i can be 'U', 'X' or 'Z'. None of these
		--    is '1', so the port must stay off the bus rather than half open it.
		--------------------------------------------------------------------------------
		sw_w <= x"FF";
		access_and_check("cs=X", 'X', '1', x"FF");
		access_and_check("cs=U", 'U', '1', x"FF");
		access_and_check("cs=Z", 'Z', '1', x"FF");
		access_and_check("rd=X", '1', 'X', x"FF");
		access_and_check("rd=U", '1', 'U', x"FF");
		access_and_check("rd=Z", '1', 'Z', x"FF");
		wait for STEP;

		-- 'H' and 'L' are the weak forms of '1' and '0'. The RTL compares against '1',
		-- so a weak high does NOT open the port. That is the behaviour of the code as
		-- written and it is the safe direction: nothing is driven onto the shared bus.
		access_and_check("cs=H, weak high does not select", 'H', '1', x"FF");
		access_and_check("cs=L", 'L', '1', x"FF");
		wait for STEP;

		--------------------------------------------------------------------------------
		-- 10. Unknown data pins. An unconnected switch input must arrive at the bus as
		--     it is, so that a wiring mistake in the top level is visible in simulation
		--     instead of being hidden behind a clean looking zero.
		--------------------------------------------------------------------------------
		sw_v := "XXXX0101";
		access_and_check("SW half unknown, selected", '1', '1', sw_v);
		access_and_check("SW half unknown, not selected", '0', '1', sw_v);
		wait for STEP;

		--------------------------------------------------------------------------------
		-- 11. Narrow instance, SW_WIDTH = 4. Same rules, and bits 31..4 are the zeros.
		--------------------------------------------------------------------------------
		cs_n_w <= '1';
		rd_n_w <= '1';
		for value in 0 to 2**NARROW_WIDTH - 1 loop
			sw_n_w <= STD_LOGIC_VECTOR(to_unsigned(value, NARROW_WIDTH));
			wait for SETTLE;
			exp_v := (OTHERS => '0');
			exp_v(NARROW_WIDTH-1 DOWNTO 0) := STD_LOGIC_VECTOR(to_unsigned(value, NARROW_WIDTH));
			check("narrow instance read", data_n_w, exp_v);
		end loop;

		cs_n_w <= '0';
		wait for SETTLE;
		check("narrow instance deselected", data_n_w, ZERO_WORD);
		wait for STEP;

		--------------------------------------------------------------------------------
		-- 12. Degenerate instance, SW_WIDTH = DATA_BUS_WIDTH. Here the zero extension
		--     slice rdata_w(31 DOWNTO 32) is a null range. It is legal VHDL and must
		--     elaborate and behave, which is what this case proves. If a simulator ever
		--     refuses the null range aggregate, remove DUT_FULL and this block - the
		--     MCU never instantiates the port wider than one byte anyway.
		--------------------------------------------------------------------------------
		cs_f_w <= '1';
		rd_f_w <= '1';
		sw_f_w <= x"DEADBEEF";
		wait for SETTLE;
		check("full width instance, DEADBEEF", data_f_w, STD_LOGIC_VECTOR'(x"DEADBEEF"));

		sw_f_w <= (OTHERS => '1');
		wait for SETTLE;
		check("full width instance, all ones", data_f_w, STD_LOGIC_VECTOR'(x"FFFFFFFF"));

		cs_f_w <= '0';
		wait for SETTLE;
		check("full width instance deselected", data_f_w, ZERO_WORD);
		wait for STEP;

		--------------------------------------------------------------------------------
		-- 13. Isolation between instances. Reading one port must not disturb another,
		--     which is the property the MCU relies on when it ORs the I/O read paths.
		--------------------------------------------------------------------------------
		cs_w   <= '1';	rd_w   <= '1';	sw_w   <= x"55";
		cs_n_w <= '0';	rd_n_w <= '1';	sw_n_w <= "1111";
		cs_f_w <= '0';	rd_f_w <= '1';	sw_f_w <= (OTHERS => '1');
		wait for SETTLE;
		check("isolation, selected port",	data_w,   expected_word(STD_LOGIC_VECTOR'(x"55")));
		check("isolation, narrow silent",	data_n_w, ZERO_WORD);
		check("isolation, full silent",		data_f_w, ZERO_WORD);
		wait for STEP;

		--------------------------------------------------------------------------------
		-- Summary
		--------------------------------------------------------------------------------
		report "tb_GPIO_SW_Interface : " & integer'image(checks_v) & " checks, " &
			   integer'image(errors_v) & " errors" severity note;

		assert errors_v = 0
			report "tb_GPIO_SW_Interface : FAILED"
			severity failure;

		report "tb_GPIO_SW_Interface : PASSED" severity note;
		wait;
	end process;

END test;