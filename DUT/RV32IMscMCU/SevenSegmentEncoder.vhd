---------------------------------------------------------------------------------------------
-- Seven-segment hexadecimal encoder
--
-- Converts a 4-bit hexadecimal value (0...F) to seven segment control signals.
-- Segment vector order: segments_o(6 downto 0) = g f e d c b a
-- ACTIVE_LOW = true matches the active-low seven-segment displays used on the FPGA boards.
---------------------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY SevenSegmentEncoder IS
    GENERIC (
        ACTIVE_LOW : BOOLEAN := TRUE
    );
    PORT (
        hex_value_i : IN  STD_LOGIC_VECTOR(3 DOWNTO 0);
        segments_o  : OUT STD_LOGIC_VECTOR(6 DOWNTO 0)
    );
END SevenSegmentEncoder;

ARCHITECTURE dataflow OF SevenSegmentEncoder IS

    -- Active-high internal representation:
    -- '1' means that the corresponding segment is illuminated.
    SIGNAL segment_on_w : STD_LOGIC_VECTOR(6 DOWNTO 0);

BEGIN

    --                         gfedcba
    WITH hex_value_i SELECT
        segment_on_w <= "0111111" WHEN "0000", -- 0
                        "0000110" WHEN "0001", -- 1
                        "1011011" WHEN "0010", -- 2
                        "1001111" WHEN "0011", -- 3
                        "1100110" WHEN "0100", -- 4
                        "1101101" WHEN "0101", -- 5
                        "1111101" WHEN "0110", -- 6
                        "0000111" WHEN "0111", -- 7
                        "1111111" WHEN "1000", -- 8
                        "1101111" WHEN "1001", -- 9
                        "1110111" WHEN "1010", -- A
                        "1111100" WHEN "1011", -- b
                        "0111001" WHEN "1100", -- C
                        "1011110" WHEN "1101", -- d
                        "1111001" WHEN "1110", -- E
                        "1110001" WHEN "1111", -- F
                        "0000000" WHEN OTHERS;

    ACTIVE_LOW_GEN : IF ACTIVE_LOW GENERATE
        segments_o <= NOT segment_on_w;
    END GENERATE ACTIVE_LOW_GEN;

    ACTIVE_HIGH_GEN : IF NOT ACTIVE_LOW GENERATE
        segments_o <= segment_on_w;
    END GENERATE ACTIVE_HIGH_GEN;

END dataflow;