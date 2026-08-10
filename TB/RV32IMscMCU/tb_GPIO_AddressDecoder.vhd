---------------------------------------------------------------------------------------------
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- tb_GPIO_AddressDecoder - self checking testbench for the GPIO address decoder
--
-- The decoder is purely combinational, so there is no clock here and no reset: the
-- testbench drives an address, waits, and compares the chip selects against a golden
-- model.
--
-- The golden model is deliberately NOT written the way the DUT is written. The DUT
-- slices address bits ([4:2] for the device, [12:5] for the block); the golden model
-- works on the absolute byte address as an integer, exactly as clause 5 of the project
-- definition states it (PORT_LEDR at 0x2000, the HEX pairs at 0x2004/8/C, PORT_SW at
-- 0x2010). An error in the slicing therefore shows up as a mismatch instead of being
-- reproduced identically on both sides.
--
-- Two phases:
--   Phase 1 - directed cases, one report line each, so the transcript reads as a
--             checklist against the table of clause 5 and against the addresses that
--             clause 6 will later take.
--   Phase 2 - exhaustive sweep of the whole 14-bit data address space for both values
--             of en_i, i.e. all 2 * 16384 = 32768 input combinations. For a decoder
--             this is cheap and it is the only way to be sure no address anywhere in
--             the map accidentally selects a device.
--
-- Every case checks two independent properties:
--   a) at most one chip select is asserted  (one-hot or none - the read paths of the
--      GPIO ports are OR-ed together in MCU.vhd, so two selects at once would put two
--      port registers on the data bus at the same time)
--   b) the selected device is the one the map of clause 5 prescribes
--
-- Cases that deserve to be called out, all covered below:
--   - 0x2020, 0x2024, 0x2028, 0x202C : BTCMPR0/1, BTCAPR and IE of clause 6. These have
--     the SAME [4:2] pattern as PORT_LEDR and as the HEX pairs, so a decoder that looks
--     only at bits [4:2] - which is all Figure 5 draws - answers on them. Nothing may
--     be selected here.
--   - en_i and bit 13 driven inconsistently. The decoder tests both, so neither alone
--     can select a device.
--   - the documented aliases 0x2001-0x2003, 0x2006-0x2007, 0x2011-0x2013. Bit 1, and
--     bit 0 outside the HEX pairs, are intentionally not decoded (Figure 5), so these
--     addresses do select their device. The golden model expects that: the test pins
--     the intended behaviour instead of pretending it does not exist.
---------------------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY tb_GPIO_AddressDecoder IS
	generic(
		DA_WIDTH			: integer := 14
	);
END tb_GPIO_AddressDecoder;
---------------------------------------------------------------------------------------------
ARCHITECTURE sim OF tb_GPIO_AddressDecoder IS

	CONSTANT TP				: time := 10 ns;	-- directed cases, readable in the waveform
	CONSTANT TP_FAST		: time := 1 ns;		-- exhaustive sweep

	CONSTANT ADDR_SPACE		: integer := 2**DA_WIDTH;

	-- The map of clause 5, as absolute byte addresses
	CONSTANT ADDR_LEDR		: integer := 16#2000#;
	CONSTANT ADDR_HEX0		: integer := 16#2004#;
	CONSTANT ADDR_HEX1		: integer := 16#2005#;
	CONSTANT ADDR_HEX2		: integer := 16#2008#;
	CONSTANT ADDR_HEX3		: integer := 16#2009#;
	CONSTANT ADDR_HEX4		: integer := 16#200C#;
	CONSTANT ADDR_HEX5		: integer := 16#200D#;
	CONSTANT ADDR_SW		: integer := 16#2010#;

	-- Extent of the GPIO block: bits [12:5] zero inside the I/O region
	CONSTANT BLOCK_LO		: integer := 16#2000#;
	CONSTANT BLOCK_HI		: integer := 16#201F#;

	--DUT interface
	SIGNAL en_s				: STD_LOGIC := '0';
	SIGNAL addr_s			: STD_LOGIC_VECTOR(DA_WIDTH-1 DOWNTO 0) := (OTHERS => '0');

	SIGNAL cs_ledr_s		: STD_LOGIC;
	SIGNAL cs_hex0_1_s		: STD_LOGIC;
	SIGNAL cs_hex2_3_s		: STD_LOGIC;
	SIGNAL cs_hex4_5_s		: STD_LOGIC;
	SIGNAL cs_sw_s			: STD_LOGIC;

	-- Aggregated for the waveform only, nothing reads it
	SIGNAL cs_bus_s			: STD_LOGIC_VECTOR(4 DOWNTO 0);

	TYPE device_t IS (DEV_NONE, DEV_LEDR, DEV_HEX0_1, DEV_HEX2_3, DEV_HEX4_5, DEV_SW);

	--=======================================
	-- Golden model
	--=======================================
	-- Written from the absolute addresses of clause 5, not from bit slices.
	FUNCTION golden_device(addr : integer; en : STD_LOGIC) RETURN device_t IS
		VARIABLE offset	: integer;
	BEGIN
		-- The block is enabled by the I/O region select of MCU.vhd AND lives in the
		-- I/O region of Figure 2, which is what bit 13 of the address says.
		IF en /= '1' THEN
			RETURN DEV_NONE;
		END IF;

		-- Outside 0x2000-0x201F nothing here answers: below is the DTCM, above are the
		-- peripherals with interrupt capability of clause 6.
		IF (addr < BLOCK_LO) OR (addr > BLOCK_HI) THEN
			RETURN DEV_NONE;
		END IF;

		-- Inside the block a device owns one aligned group of four byte addresses.
		-- Bit 1, and bit 0 outside the HEX pairs, are not decoded (Figure 5).
		offset := (addr - BLOCK_LO) / 4;

		CASE offset IS
			WHEN 0		=> RETURN DEV_LEDR;		-- 0x2000 .. 0x2003
			WHEN 1		=> RETURN DEV_HEX0_1;	-- 0x2004 .. 0x2007
			WHEN 2		=> RETURN DEV_HEX2_3;	-- 0x2008 .. 0x200B
			WHEN 3		=> RETURN DEV_HEX4_5;	-- 0x200C .. 0x200F
			WHEN 4		=> RETURN DEV_SW;		-- 0x2010 .. 0x2013
			WHEN OTHERS	=> RETURN DEV_NONE;		-- 0x2014 .. 0x201F, reserved for clause 6
		END CASE;
	END FUNCTION;

	--=======================================
	-- Reporting helper
	--=======================================
	FUNCTION to_hex4(v : integer) RETURN string IS
		CONSTANT DIGITS	: string(1 TO 16) := "0123456789ABCDEF";
		VARIABLE r		: string(1 TO 4);
		VARIABLE t		: integer := v;
	BEGIN
		FOR i IN 4 DOWNTO 1 LOOP
			r(i)	:= DIGITS((t MOD 16) + 1);
			t		:= t / 16;
		END LOOP;
		RETURN r;
	END FUNCTION;

BEGIN

	--=======================================
	-- DUT
	--=======================================
	DUT: entity work.GPIO_AddressDecoder
	generic map(
		DA_WIDTH		=> DA_WIDTH
	)
	PORT MAP (
		en_i			=> en_s,
		addr_i			=> addr_s,
		cs_ledr_o		=> cs_ledr_s,
		cs_hex0_1_o		=> cs_hex0_1_s,
		cs_hex2_3_o		=> cs_hex2_3_s,
		cs_hex4_5_o		=> cs_hex4_5_s,
		cs_sw_o			=> cs_sw_s
	);

	cs_bus_s	<= cs_sw_s & cs_hex4_5_s & cs_hex2_3_s & cs_hex0_1_s & cs_ledr_s;

	--=======================================
	-- Stimulus and checking
	--=======================================
	STIMULUS:
	process

		VARIABLE err_cnt	: integer := 0;
		VARIABLE chk_cnt	: integer := 0;

		-- Applies one vector and checks both properties. Declared after err_cnt and
		-- chk_cnt so that it may update them.
		procedure apply_and_check(addr : in integer; en : in STD_LOGIC;
								  hold : in time; verbose : in boolean) is
			VARIABLE expected	: device_t;
			VARIABLE observed	: device_t;
			VARIABLE hits		: integer;
		begin
			addr_s	<= STD_LOGIC_VECTOR(TO_UNSIGNED(addr, DA_WIDTH));
			en_s	<= en;
			wait for hold;

			hits		:= 0;
			observed	:= DEV_NONE;

			if cs_ledr_s = '1' then
				hits := hits + 1;	observed := DEV_LEDR;
			end if;
			if cs_hex0_1_s = '1' then
				hits := hits + 1;	observed := DEV_HEX0_1;
			end if;
			if cs_hex2_3_s = '1' then
				hits := hits + 1;	observed := DEV_HEX2_3;
			end if;
			if cs_hex4_5_s = '1' then
				hits := hits + 1;	observed := DEV_HEX4_5;
			end if;
			if cs_sw_s = '1' then
				hits := hits + 1;	observed := DEV_SW;
			end if;

			expected	:= golden_device(addr, en);
			chk_cnt		:= chk_cnt + 1;

			-- (a) never more than one device on the bus at a time
			if hits > 1 then
				err_cnt := err_cnt + 1;
				report "FAIL (not one-hot) : addr 0x" & to_hex4(addr)
					 & "  en=" & STD_LOGIC'image(en)
					 & "  cs=" & integer'image(hits) & " asserted"
					severity error;

			-- (b) the right device, per clause 5
			elsif observed /= expected then
				err_cnt := err_cnt + 1;
				report "FAIL (wrong select) : addr 0x" & to_hex4(addr)
					 & "  en=" & STD_LOGIC'image(en)
					 & "  expected " & device_t'image(expected)
					 & "  observed " & device_t'image(observed)
					severity error;

			elsif verbose then
				report "pass : addr 0x" & to_hex4(addr)
					 & "  en=" & STD_LOGIC'image(en)
					 & "  -> " & device_t'image(observed)
					severity note;
			end if;
		end procedure;

	begin
		report "=== tb_GPIO_AddressDecoder : phase 1, directed cases ===" severity note;

		--------------------------------------------------------------------------
		-- 1. The eight mapped ports of clause 5
		--------------------------------------------------------------------------
		apply_and_check(ADDR_LEDR, '1', TP, TRUE);	-- PORT_LEDR
		apply_and_check(ADDR_HEX0, '1', TP, TRUE);	-- PORT_HEX0, low digit of pair 0
		apply_and_check(ADDR_HEX1, '1', TP, TRUE);	-- PORT_HEX1, high digit of pair 0
		apply_and_check(ADDR_HEX2, '1', TP, TRUE);	-- PORT_HEX2
		apply_and_check(ADDR_HEX3, '1', TP, TRUE);	-- PORT_HEX3
		apply_and_check(ADDR_HEX4, '1', TP, TRUE);	-- PORT_HEX4
		apply_and_check(ADDR_HEX5, '1', TP, TRUE);	-- PORT_HEX5
		apply_and_check(ADDR_SW,   '1', TP, TRUE);	-- PORT_SW

		--------------------------------------------------------------------------
		-- 2. Boundaries of the block
		--------------------------------------------------------------------------
		-- One below the block is the top of the DTCM, one above the last decoded
		-- group is reserved space. Neither may select anything.
		apply_and_check(16#1FFC#, '0', TP, TRUE);	-- last DTCM word
		apply_and_check(16#1FFF#, '0', TP, TRUE);	-- last DTCM byte
		apply_and_check(16#2014#, '1', TP, TRUE);	-- PORT_PB      (clause 6)
		apply_and_check(16#2018#, '1', TP, TRUE);	-- UTCL         (clause 6)
		apply_and_check(16#2019#, '1', TP, TRUE);	-- RXBF         (clause 6)
		apply_and_check(16#201A#, '1', TP, TRUE);	-- TXBF         (clause 6)
		apply_and_check(16#201C#, '1', TP, TRUE);	-- BTCTL1       (clause 6)
		apply_and_check(16#201D#, '1', TP, TRUE);	-- BTCTL2       (clause 6)
		apply_and_check(16#201F#, '1', TP, TRUE);	-- last address of the block

		--------------------------------------------------------------------------
		-- 3. Regression: the clause 6 addresses that share [4:2] with a GPIO port
		--------------------------------------------------------------------------
		-- These are the ones a Figure 5 decoder (bits [4:2] only) gets wrong.
		apply_and_check(16#2020#, '1', TP, TRUE);	-- BTCMPR0, [4:2]=000 like PORT_LEDR
		apply_and_check(16#2024#, '1', TP, TRUE);	-- BTCMPR1, [4:2]=001 like HEX0/HEX1
		apply_and_check(16#2028#, '1', TP, TRUE);	-- BTCAPR,  [4:2]=010 like HEX2/HEX3
		apply_and_check(16#202C#, '1', TP, TRUE);	-- IE,      [4:2]=011 like HEX4/HEX5
		apply_and_check(16#202D#, '1', TP, TRUE);	-- IFG
		apply_and_check(16#202E#, '1', TP, TRUE);	-- TYPE
		apply_and_check(16#2030#, '1', TP, TRUE);	-- free I/O space
		apply_and_check(16#3FFC#, '1', TP, TRUE);	-- top of the I/O region

		--------------------------------------------------------------------------
		-- 4. Regression: DTCM addresses with the same low bits as a GPIO port
		--------------------------------------------------------------------------
		-- Same [4:2] as every port, but bit 13 is low, so a store here must reach the
		-- DTCM alone. This is the check that bit 13 is really part of the decode.
		apply_and_check(16#0000#, '0', TP, TRUE);
		apply_and_check(16#0004#, '0', TP, TRUE);
		apply_and_check(16#0008#, '0', TP, TRUE);
		apply_and_check(16#000C#, '0', TP, TRUE);
		apply_and_check(16#0010#, '0', TP, TRUE);

		--------------------------------------------------------------------------
		-- 5. Inconsistent enable and address bit 13
		--------------------------------------------------------------------------
		-- Neither input alone may select a device: en_i is the region enable of
		-- MCU.vhd, bit 13 is the region bit of Figure 2, and the decoder needs both.
		apply_and_check(16#0000#, '1', TP, TRUE);	-- enabled, but a DTCM address
		apply_and_check(16#0004#, '1', TP, TRUE);
		apply_and_check(16#2000#, '0', TP, TRUE);	-- I/O address, but not enabled
		apply_and_check(16#2010#, '0', TP, TRUE);

		--------------------------------------------------------------------------
		-- 6. The documented aliases - intended behaviour, pinned down here
		--------------------------------------------------------------------------
		-- Bit 1, and bit 0 outside the HEX pairs, are not decoded, exactly as in
		-- Figure 5. These addresses are unmapped and unused by the benchmarks.
		apply_and_check(16#2001#, '1', TP, TRUE);	-- alias of PORT_LEDR
		apply_and_check(16#2002#, '1', TP, TRUE);
		apply_and_check(16#2003#, '1', TP, TRUE);
		apply_and_check(16#2006#, '1', TP, TRUE);	-- alias inside pair HEX0/HEX1
		apply_and_check(16#2007#, '1', TP, TRUE);
		apply_and_check(16#200A#, '1', TP, TRUE);	-- alias inside pair HEX2/HEX3
		apply_and_check(16#200E#, '1', TP, TRUE);	-- alias inside pair HEX4/HEX5
		apply_and_check(16#2011#, '1', TP, TRUE);	-- alias of PORT_SW
		apply_and_check(16#2013#, '1', TP, TRUE);

		report "=== phase 1 done, " & integer'image(chk_cnt) & " checks, "
			 & integer'image(err_cnt) & " errors ===" severity note;

		--------------------------------------------------------------------------
		-- Phase 2 : exhaustive sweep of the whole data address space
		--------------------------------------------------------------------------
		report "=== phase 2, exhaustive sweep of all "
			 & integer'image(2*ADDR_SPACE) & " input combinations ===" severity note;

		for a in 0 TO ADDR_SPACE-1 loop
			apply_and_check(a, '0', TP_FAST, FALSE);
			apply_and_check(a, '1', TP_FAST, FALSE);
		end loop;

		--------------------------------------------------------------------------
		-- Verdict
		--------------------------------------------------------------------------
		report "=== tb_GPIO_AddressDecoder finished : "
			 & integer'image(chk_cnt) & " checks, "
			 & integer'image(err_cnt) & " errors ===" severity note;

		assert err_cnt = 0
			report "tb_GPIO_AddressDecoder : FAILED"
			severity failure;

		report "tb_GPIO_AddressDecoder : PASSED" severity note;

		wait;
	end process;

END sim;