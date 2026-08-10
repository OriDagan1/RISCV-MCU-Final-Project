---------------------------------------------------------------------------------------------
-- Testbench for SevenSegmentEncoder
--
-- Tests all hexadecimal input values 0...F.
-- Verifies both Active-High and Active-Low configurations.
---------------------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY tb_SevenSegmentEncoder IS
END tb_SevenSegmentEncoder;

ARCHITECTURE simulation OF tb_SevenSegmentEncoder IS

    SIGNAL hex_value_s            : STD_LOGIC_VECTOR(3 DOWNTO 0);
    SIGNAL segments_active_high_s : STD_LOGIC_VECTOR(6 DOWNTO 0);
    SIGNAL segments_active_low_s  : STD_LOGIC_VECTOR(6 DOWNTO 0);

    TYPE segment_array_t IS ARRAY (0 TO 15) OF STD_LOGIC_VECTOR(6 DOWNTO 0);

    -- Expected Active-High patterns.
    -- Segment order: g f e d c b a
    CONSTANT EXPECTED_SEGMENTS_C : segment_array_t := (
        0  => "0111111", -- 0
        1  => "0000110", -- 1
        2  => "1011011", -- 2
        3  => "1001111", -- 3
        4  => "1100110", -- 4
        5  => "1101101", -- 5
        6  => "1111101", -- 6
        7  => "0000111", -- 7
        8  => "1111111", -- 8
        9  => "1101111", -- 9
        10 => "1110111", -- A
        11 => "1111100", -- b
        12 => "0111001", -- C
        13 => "1011110", -- d
        14 => "1111001", -- E
        15 => "1110001"  -- F
    );

BEGIN

    -- Active-High encoder instance
    DUT_ACTIVE_HIGH : ENTITY WORK.SevenSegmentEncoder
        GENERIC MAP (
            ACTIVE_LOW => FALSE
        )
        PORT MAP (
            hex_value_i => hex_value_s,
            segments_o  => segments_active_high_s
        );

    -- Active-Low encoder instance
    DUT_ACTIVE_LOW : ENTITY WORK.SevenSegmentEncoder
        GENERIC MAP (
            ACTIVE_LOW => TRUE
        )
        PORT MAP (
            hex_value_i => hex_value_s,
            segments_o  => segments_active_low_s
        );

    STIMULUS_PROCESS : PROCESS
    BEGIN

        FOR i IN 0 TO 15 LOOP

            hex_value_s <= STD_LOGIC_VECTOR(TO_UNSIGNED(i, 4));

            WAIT FOR 10 ns;

            ASSERT segments_active_high_s = EXPECTED_SEGMENTS_C(i)
                REPORT "Active-High error for hexadecimal value " &
                       INTEGER'IMAGE(i)
                SEVERITY ERROR;

            ASSERT segments_active_low_s = NOT EXPECTED_SEGMENTS_C(i)
                REPORT "Active-Low error for hexadecimal value " &
                       INTEGER'IMAGE(i)
                SEVERITY ERROR;

        END LOOP;

        REPORT "SevenSegmentEncoder: all tests passed successfully."
            SEVERITY NOTE;

        WAIT;

    END PROCESS;

END simulation;