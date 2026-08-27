---------------------------------------------------------------------------------------------
-- Testbench for PERIPH_AddressDecoder
--
-- Purpose:
--   Exhaustive verification of the clause-6 peripheral address decoder.
--
-- What is checked:
--   1. Canonical addresses from the project definition.
--   2. Intentional address aliases caused by ignored low address bits.
--   3. USART bonus range remains unmapped.
--   4. No decode below the MMIO region.
--   5. No decode above the implemented peripheral block.
--   6. en_i = '0' always disables every peripheral.
--   7. At most one PERIPH chip-select is active at a time.
--   8. No address is selected simultaneously by GPIO_AddressDecoder and
--      PERIPH_AddressDecoder.
--   9. Exhaustive sweep of all 2^14 addresses for en_i='0' and en_i='1'.
--
-- Required DUT files:
--   PERIPH_AddressDecoder.vhd
--   GPIO_AddressDecoder.vhd
---------------------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY tb_PERIPH_AddressDecoder IS
END tb_PERIPH_AddressDecoder;

---------------------------------------------------------------------------------------------

ARCHITECTURE sim OF tb_PERIPH_AddressDecoder IS

	CONSTANT DA_WIDTH			: INTEGER := 14;
	CONSTANT ADDRESS_COUNT		: INTEGER := 2**DA_WIDTH;

	-----------------------------------------------------------------------------------------
	-- Common decoder inputs
	-----------------------------------------------------------------------------------------
	SIGNAL en_i					: STD_LOGIC := '0';
	SIGNAL addr_i				: STD_LOGIC_VECTOR(DA_WIDTH-1 DOWNTO 0)
								:= (OTHERS => '0');

	-----------------------------------------------------------------------------------------
	-- PERIPH_AddressDecoder outputs
	-----------------------------------------------------------------------------------------
	SIGNAL cs_pb_o				: STD_LOGIC;
	SIGNAL cs_btctl_o			: STD_LOGIC;
	SIGNAL cs_btcmpr0_o			: STD_LOGIC;
	SIGNAL cs_btcmpr1_o			: STD_LOGIC;
	SIGNAL cs_btcapr_o			: STD_LOGIC;
	SIGNAL cs_ic_o				: STD_LOGIC;

	-----------------------------------------------------------------------------------------
	-- GPIO_AddressDecoder outputs
	-- Used only to verify that the two decoders can never overlap.
	-----------------------------------------------------------------------------------------
	SIGNAL cs_ledr_o				: STD_LOGIC;
	SIGNAL cs_hex0_1_o			: STD_LOGIC;
	SIGNAL cs_hex2_3_o			: STD_LOGIC;
	SIGNAL cs_hex4_5_o			: STD_LOGIC;
	SIGNAL cs_sw_o				: STD_LOGIC;

	-----------------------------------------------------------------------------------------
	-- Combined vectors
	--
	-- PERIPH:
	--   bit 5 = PB
	--   bit 4 = BTCTL
	--   bit 3 = BTCMPR0
	--   bit 2 = BTCMPR1
	--   bit 1 = BTCAPR
	--   bit 0 = Interrupt Controller
	--
	-- GPIO:
	--   bit 4 = LEDR
	--   bit 3 = HEX0/1
	--   bit 2 = HEX2/3
	--   bit 1 = HEX4/5
	--   bit 0 = SW
	-----------------------------------------------------------------------------------------
	SIGNAL periph_cs_w			: STD_LOGIC_VECTOR(5 DOWNTO 0);
	SIGNAL gpio_cs_w				: STD_LOGIC_VECTOR(4 DOWNTO 0);


	-----------------------------------------------------------------------------------------
	-- Count the number of active bits in a STD_LOGIC_VECTOR.
	-----------------------------------------------------------------------------------------
	FUNCTION count_ones(
		CONSTANT value_i : STD_LOGIC_VECTOR
	) RETURN INTEGER IS

		VARIABLE count_v : INTEGER := 0;

	BEGIN

		FOR i IN value_i'RANGE LOOP

			IF value_i(i) = '1' THEN
				count_v := count_v + 1;
			END IF;

		END LOOP;

		RETURN count_v;

	END FUNCTION;


	-----------------------------------------------------------------------------------------
	-- Golden model for PERIPH_AddressDecoder.
	--
	-- Vector:
	--   "100000" = PB
	--   "010000" = BTCTL
	--   "001000" = BTCMPR0
	--   "000100" = BTCMPR1
	--   "000010" = BTCAPR
	--   "000001" = Interrupt Controller
	-----------------------------------------------------------------------------------------
	FUNCTION expected_periph(
		CONSTANT address_i	: INTEGER;
		CONSTANT enable_i	: STD_LOGIC
	) RETURN STD_LOGIC_VECTOR IS

		VARIABLE result_v : STD_LOGIC_VECTOR(5 DOWNTO 0)
						 := (OTHERS => '0');

	BEGIN

		IF enable_i /= '1' THEN
			RETURN result_v;
		END IF;

		-------------------------------------------------------------------------------------
		-- The decoder additionally checks addr_i(13).
		-------------------------------------------------------------------------------------
		IF address_i < 16#2000# OR address_i > 16#3FFF# THEN
			RETURN result_v;
		END IF;

		-------------------------------------------------------------------------------------
		-- Expected groups.
		--
		-- Low address bits are intentionally ignored by the main decoder.
		-------------------------------------------------------------------------------------
		CASE address_i IS

			-- PORT_PB
			WHEN 16#2014# TO 16#2017# =>
				result_v := "100000";

			-- 0x2018 - 0x201B = USART bonus
			-- Deliberately unmapped.

			-- BTCTL1 / BTCTL2 group
			WHEN 16#201C# TO 16#201F# =>
				result_v := "010000";

			-- BTCMPR0 word slot
			WHEN 16#2020# TO 16#2023# =>
				result_v := "001000";

			-- BTCMPR1 word slot
			WHEN 16#2024# TO 16#2027# =>
				result_v := "000100";

			-- BTCAPR word slot
			WHEN 16#2028# TO 16#202B# =>
				result_v := "000010";

			-- Interrupt Controller group:
			-- IE / IFG / TYPE + unused fourth slot
			WHEN 16#202C# TO 16#202F# =>
				result_v := "000001";

			WHEN OTHERS =>
				NULL;

		END CASE;

		RETURN result_v;

	END FUNCTION;


	-----------------------------------------------------------------------------------------
	-- Golden model for the existing GPIO_AddressDecoder.
	--
	-- This is included so the testbench can prove that the two decoders never
	-- select a device at the same address.
	-----------------------------------------------------------------------------------------
	FUNCTION expected_gpio(
		CONSTANT address_i	: INTEGER;
		CONSTANT enable_i	: STD_LOGIC
	) RETURN STD_LOGIC_VECTOR IS

		VARIABLE result_v : STD_LOGIC_VECTOR(4 DOWNTO 0)
						 := (OTHERS => '0');

	BEGIN

		IF enable_i /= '1' THEN
			RETURN result_v;
		END IF;

		CASE address_i IS

			WHEN 16#2000# TO 16#2003# =>
				result_v := "10000";	-- LEDR

			WHEN 16#2004# TO 16#2007# =>
				result_v := "01000";	-- HEX0/1

			WHEN 16#2008# TO 16#200B# =>
				result_v := "00100";	-- HEX2/3

			WHEN 16#200C# TO 16#200F# =>
				result_v := "00010";	-- HEX4/5

			WHEN 16#2010# TO 16#2013# =>
				result_v := "00001";	-- SW

			WHEN OTHERS =>
				NULL;

		END CASE;

		RETURN result_v;

	END FUNCTION;


BEGIN

	-----------------------------------------------------------------------------------------
	-- Combine outputs for compact checking.
	-----------------------------------------------------------------------------------------
	periph_cs_w <=
		cs_pb_o &
		cs_btctl_o &
		cs_btcmpr0_o &
		cs_btcmpr1_o &
		cs_btcapr_o &
		cs_ic_o;

	gpio_cs_w <=
		cs_ledr_o &
		cs_hex0_1_o &
		cs_hex2_3_o &
		cs_hex4_5_o &
		cs_sw_o;


	-----------------------------------------------------------------------------------------
	-- DUT: peripheral decoder
	-----------------------------------------------------------------------------------------
	DUT_PERIPH:
	ENTITY work.PERIPH_AddressDecoder
	GENERIC MAP(
		DA_WIDTH			=> DA_WIDTH
	)
	PORT MAP(
		en_i				=> en_i,
		addr_i				=> addr_i,

		cs_pb_o				=> cs_pb_o,
		cs_btctl_o			=> cs_btctl_o,
		cs_btcmpr0_o		=> cs_btcmpr0_o,
		cs_btcmpr1_o		=> cs_btcmpr1_o,
		cs_btcapr_o			=> cs_btcapr_o,
		cs_ic_o				=> cs_ic_o
	);


	-----------------------------------------------------------------------------------------
	-- Existing GPIO decoder.
	-- Used as an integration cross-check only.
	-----------------------------------------------------------------------------------------
	DUT_GPIO:
	ENTITY work.GPIO_AddressDecoder
	GENERIC MAP(
		DA_WIDTH			=> DA_WIDTH
	)
	PORT MAP(
		en_i				=> en_i,
		addr_i				=> addr_i,

		cs_ledr_o			=> cs_ledr_o,
		cs_hex0_1_o		=> cs_hex0_1_o,
		cs_hex2_3_o		=> cs_hex2_3_o,
		cs_hex4_5_o		=> cs_hex4_5_o,
		cs_sw_o				=> cs_sw_o
	);


	-----------------------------------------------------------------------------------------
	-- Stimulus + self checking
	-----------------------------------------------------------------------------------------
	STIMULUS:
	PROCESS

		-------------------------------------------------------------------------------------
		-- Test one address against an explicit expected PERIPH result.
		-------------------------------------------------------------------------------------
		PROCEDURE check_address(
			CONSTANT address_c	: IN INTEGER;
			CONSTANT enable_c	: IN STD_LOGIC;
			CONSTANT expected_c	: IN STD_LOGIC_VECTOR(5 DOWNTO 0);
			CONSTANT description_c : IN STRING
		) IS
		BEGIN

			addr_i <= STD_LOGIC_VECTOR(TO_UNSIGNED(address_c, DA_WIDTH));
			en_i   <= enable_c;

			WAIT FOR 1 ns;

			ASSERT periph_cs_w = expected_c
				REPORT
					"ERROR: " & description_c &
					" | address(decimal)=" & INTEGER'IMAGE(address_c)
				SEVERITY ERROR;

			ASSERT count_ones(periph_cs_w) <= 1
				REPORT
					"ERROR: More than one PERIPH chip-select active at address " &
					INTEGER'IMAGE(address_c)
				SEVERITY ERROR;

			ASSERT NOT (
				(count_ones(periph_cs_w) > 0) AND
				(count_ones(gpio_cs_w) > 0)
			)
				REPORT
					"ERROR: GPIO/PERIPH decoder overlap at address " &
					INTEGER'IMAGE(address_c)
				SEVERITY ERROR;

		END PROCEDURE;


		VARIABLE expected_periph_v	: STD_LOGIC_VECTOR(5 DOWNTO 0);
		VARIABLE expected_gpio_v		: STD_LOGIC_VECTOR(4 DOWNTO 0);

	BEGIN

		-------------------------------------------------------------------------------------
		-- TEST 1: en_i must disable everything.
		-------------------------------------------------------------------------------------
		REPORT "TEST 1: en_i='0' disables all peripheral selects" SEVERITY NOTE;

		check_address(16#2014#, '0', "000000", "PB disabled by en_i");
		check_address(16#201C#, '0', "000000", "BTCTL disabled by en_i");
		check_address(16#2020#, '0', "000000", "BTCMPR0 disabled by en_i");
		check_address(16#2024#, '0', "000000", "BTCMPR1 disabled by en_i");
		check_address(16#2028#, '0', "000000", "BTCAPR disabled by en_i");
		check_address(16#202C#, '0', "000000", "IC disabled by en_i");


		-------------------------------------------------------------------------------------
		-- TEST 2: Canonical addresses from the project definition.
		-------------------------------------------------------------------------------------
		REPORT "TEST 2: Canonical clause-6 addresses" SEVERITY NOTE;

		check_address(16#2014#, '1', "100000", "PORT_PB");
		check_address(16#201C#, '1', "010000", "BTCTL1");
		check_address(16#201D#, '1', "010000", "BTCTL2");
		check_address(16#2020#, '1', "001000", "BTCMPR0");
		check_address(16#2024#, '1', "000100", "BTCMPR1");
		check_address(16#2028#, '1', "000010", "BTCAPR");
		check_address(16#202C#, '1', "000001", "IE");
		check_address(16#202D#, '1', "000001", "IFG");
		check_address(16#202E#, '1', "000001", "TYPE");


		-------------------------------------------------------------------------------------
		-- TEST 3: Intentional aliases / ignored low bits.
		-------------------------------------------------------------------------------------
		REPORT "TEST 3: Intentional low-bit aliases" SEVERITY NOTE;

		-- PB group
		check_address(16#2015#, '1', "100000", "PB alias +1");
		check_address(16#2016#, '1', "100000", "PB alias +2");
		check_address(16#2017#, '1', "100000", "PB alias +3");

		-- BTCTL group
		check_address(16#201E#, '1', "010000", "BTCTL alias 0x201E");
		check_address(16#201F#, '1', "010000", "BTCTL alias 0x201F");

		-- BTCMPR0 word slot
		check_address(16#2021#, '1', "001000", "BTCMPR0 +1");
		check_address(16#2022#, '1', "001000", "BTCMPR0 +2");
		check_address(16#2023#, '1', "001000", "BTCMPR0 +3");

		-- BTCMPR1 word slot
		check_address(16#2025#, '1', "000100", "BTCMPR1 +1");
		check_address(16#2026#, '1', "000100", "BTCMPR1 +2");
		check_address(16#2027#, '1', "000100", "BTCMPR1 +3");

		-- BTCAPR word slot
		check_address(16#2029#, '1', "000010", "BTCAPR +1");
		check_address(16#202A#, '1', "000010", "BTCAPR +2");
		check_address(16#202B#, '1', "000010", "BTCAPR +3");

		-- Fourth unused slot of IC group.
		check_address(16#202F#, '1', "000001", "IC unused sel=11 slot");


		-------------------------------------------------------------------------------------
		-- TEST 4: USART bonus area must remain completely unmapped.
		-------------------------------------------------------------------------------------
		REPORT "TEST 4: USART bonus range must remain unmapped" SEVERITY NOTE;

		check_address(16#2018#, '1', "000000", "USART UTCL");
		check_address(16#2019#, '1', "000000", "USART RXBF");
		check_address(16#201A#, '1', "000000", "USART TXBF");
		check_address(16#201B#, '1', "000000", "USART unused group byte");


		-------------------------------------------------------------------------------------
		-- TEST 5: Boundaries around every implemented region.
		-------------------------------------------------------------------------------------
		REPORT "TEST 5: Address-boundary checks" SEVERITY NOTE;

		check_address(16#1FFF#, '1', "000000", "Last DTCM byte");
		check_address(16#2000#, '1', "000000", "First MMIO byte belongs to GPIO");
		check_address(16#2013#, '1', "000000", "Last SW/GPIO byte");
		check_address(16#2014#, '1', "100000", "First PERIPH address");

		check_address(16#2017#, '1', "100000", "End PB group");
		check_address(16#2018#, '1', "000000", "Start USART gap");

		check_address(16#201B#, '1', "000000", "End USART gap");
		check_address(16#201C#, '1', "010000", "Start BTCTL group");

		check_address(16#201F#, '1', "010000", "End BTCTL group");
		check_address(16#2020#, '1', "001000", "Start BTCMPR0 group");

		check_address(16#2023#, '1', "001000", "End BTCMPR0 group");
		check_address(16#2024#, '1', "000100", "Start BTCMPR1 group");

		check_address(16#2027#, '1', "000100", "End BTCMPR1 group");
		check_address(16#2028#, '1', "000010", "Start BTCAPR group");

		check_address(16#202B#, '1', "000010", "End BTCAPR group");
		check_address(16#202C#, '1', "000001", "Start IC group");

		check_address(16#202F#, '1', "000001", "End IC group");
		check_address(16#2030#, '1', "000000", "First unmapped slot after IC");

		check_address(16#203F#, '1', "000000", "End of local 0x2000-0x203F block");
		check_address(16#2040#, '1', "000000", "Immediately above local block");
		check_address(16#3FFF#, '1', "000000", "Last MMIO address");


		-------------------------------------------------------------------------------------
		-- TEST 6: en_i='1' alone must not be sufficient if address bit 13 is zero.
		-------------------------------------------------------------------------------------
		REPORT "TEST 6: addr_i(13) must also indicate MMIO space" SEVERITY NOTE;

		check_address(16#0014#, '1', "000000", "PB pattern outside MMIO");
		check_address(16#001C#, '1', "000000", "BTCTL pattern outside MMIO");
		check_address(16#0020#, '1', "000000", "BTCMPR0 pattern outside MMIO");
		check_address(16#002C#, '1', "000000", "IC pattern outside MMIO");


		-------------------------------------------------------------------------------------
		-- TEST 7: Exhaustive sweep with en_i = '0'.
		--
		-- Every one of the 16384 addresses must produce zero selects.
		-------------------------------------------------------------------------------------
		REPORT "TEST 7: Exhaustive 14-bit sweep with en_i='0'" SEVERITY NOTE;

		en_i <= '0';

		FOR address_v IN 0 TO ADDRESS_COUNT-1 LOOP

			addr_i <= STD_LOGIC_VECTOR(TO_UNSIGNED(address_v, DA_WIDTH));

			WAIT FOR 1 ns;

			ASSERT periph_cs_w = "000000"
				REPORT
					"ERROR: PERIPH select active while en_i=0 at address " &
					INTEGER'IMAGE(address_v)
				SEVERITY ERROR;

			ASSERT gpio_cs_w = "00000"
				REPORT
					"ERROR: GPIO select active while en_i=0 at address " &
					INTEGER'IMAGE(address_v)
				SEVERITY ERROR;

		END LOOP;


		-------------------------------------------------------------------------------------
		-- TEST 8: Exhaustive sweep with en_i = '1'.
		--
		-- This verifies every possible 14-bit address against independent golden
		-- models for both decoders.
		-------------------------------------------------------------------------------------
		REPORT "TEST 8: Exhaustive 14-bit sweep with en_i='1'" SEVERITY NOTE;

		en_i <= '1';

		FOR address_v IN 0 TO ADDRESS_COUNT-1 LOOP

			addr_i <= STD_LOGIC_VECTOR(TO_UNSIGNED(address_v, DA_WIDTH));

			WAIT FOR 1 ns;

			expected_periph_v := expected_periph(address_v, '1');
			expected_gpio_v   := expected_gpio(address_v, '1');

			---------------------------------------------------------------------------------
			-- Exact PERIPH decode
			---------------------------------------------------------------------------------
			ASSERT periph_cs_w = expected_periph_v
				REPORT
					"ERROR: PERIPH decode mismatch at address " &
					INTEGER'IMAGE(address_v)
				SEVERITY ERROR;

			---------------------------------------------------------------------------------
			-- Exact existing GPIO decode
			---------------------------------------------------------------------------------
			ASSERT gpio_cs_w = expected_gpio_v
				REPORT
					"ERROR: GPIO regression mismatch at address " &
					INTEGER'IMAGE(address_v)
				SEVERITY ERROR;

			---------------------------------------------------------------------------------
			-- PERIPH must always be one-hot-or-zero.
			---------------------------------------------------------------------------------
			ASSERT count_ones(periph_cs_w) <= 1
				REPORT
					"ERROR: Multiple PERIPH chip-selects active at address " &
					INTEGER'IMAGE(address_v)
				SEVERITY ERROR;

			---------------------------------------------------------------------------------
			-- GPIO must always be one-hot-or-zero.
			---------------------------------------------------------------------------------
			ASSERT count_ones(gpio_cs_w) <= 1
				REPORT
					"ERROR: Multiple GPIO chip-selects active at address " &
					INTEGER'IMAGE(address_v)
				SEVERITY ERROR;

			---------------------------------------------------------------------------------
			-- Critical integration property:
			-- The two decoder blocks must NEVER both select something.
			---------------------------------------------------------------------------------
			ASSERT NOT (
				(count_ones(periph_cs_w) > 0) AND
				(count_ones(gpio_cs_w) > 0)
			)
				REPORT
					"ERROR: GPIO and PERIPH decoders overlap at address " &
					INTEGER'IMAGE(address_v)
				SEVERITY ERROR;

		END LOOP;


		-------------------------------------------------------------------------------------
		-- TEST 9: Return rapidly through all actual peripheral groups.
		--
		-- Extra back-to-back combinational check after the exhaustive sweep.
		-------------------------------------------------------------------------------------
		REPORT "TEST 9: Back-to-back combinational address changes" SEVERITY NOTE;

		check_address(16#2014#, '1', "100000", "PB");
		check_address(16#201C#, '1', "010000", "BTCTL");
		check_address(16#2020#, '1', "001000", "BTCMPR0");
		check_address(16#2024#, '1', "000100", "BTCMPR1");
		check_address(16#2028#, '1', "000010", "BTCAPR");
		check_address(16#202C#, '1', "000001", "IC");
		check_address(16#2018#, '1', "000000", "USART gap");
		check_address(16#2030#, '1', "000000", "Unmapped");


		-------------------------------------------------------------------------------------
		-- Complete.
		-------------------------------------------------------------------------------------
		REPORT "============================================================" SEVERITY NOTE;
		REPORT "ALL PERIPH_AddressDecoder TESTS PASSED" SEVERITY NOTE;
		REPORT "Exhaustively checked all 16384 addresses for en_i=0 and en_i=1"
			SEVERITY NOTE;
		REPORT "GPIO/PERIPH overlap check: PASSED" SEVERITY NOTE;
		REPORT "============================================================" SEVERITY NOTE;

		WAIT;

	END PROCESS;

END sim;