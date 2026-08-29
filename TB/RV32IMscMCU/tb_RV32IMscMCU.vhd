---------------------------------------------------------------------------------------------
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Final Project 2026
--
-- Testbench : tb_RV32IMscMCU
-- Purpose   : One top-level ModelSim testbench for the four supplied
--             "Interrupt-based IO" benchmark applications (test1..test4).
--
-- Important source-derived points used here:
--   * KEY1..KEY3 are active low. The project uses the 0->1 release event as IRQ.
--   * The complete MCU is the DUT; the benchmark runs from ITCM/DTCM images.
--   * test2/test3 use SEC_PERIOD=0x002625A0 with BTCLK=SMCLK/8.
--     With the current SMCLK=25 MHz this gives about 0.8 s for the initial period.
--   * test3 changes BTCMPR0 while the timer is already running. The current RTL
--     double-buffers BTCMPR0 into BTCL0 only on EQU0, so the FIRST interrupt after
--     the key sequence still belongs to the old period; only subsequent periods
--     use the final KEY3 value.
--   * test4 compare mode has the same double-buffering effect. Its first compare
--     period is SEC_PERIOD=0x01312D00 on direct SMCLK, about 0.8 s at 25 MHz;
--     after the third KEY1, the following period is SEC_PERIOD/8, about 0.1 s.
--   * test4 input-capture benchmark uses the timer's INTERNAL GND/VCC CAPISEL
--     sources, so CAPIN1_i/CAPIN2_i need no external pulse for the supplied code.
--
-- One TB, four applications:
--   vsim -gTEST_NUM=1 work.tb_RV32IMscMCU
--   vsim -gTEST_NUM=2 work.tb_RV32IMscMCU
--   vsim -gTEST_NUM=3 work.tb_RV32IMscMCU
--   vsim -gTEST_NUM=4 work.tb_RV32IMscMCU
--
-- RUN_TIMER_CHECKS defaults to TRUE because the formal benchmark verification must
-- exercise the Basic Timer. Set FALSE only for a quick debug run; such a run is
-- explicitly reported as PARTIAL and never as a full PASS.
--
-- test4 subtests:
--   TEST4_SUBTEST = 0 : compare + PWM + capture (reset between sections)
--   TEST4_SUBTEST = 1 : compare only
--   TEST4_SUBTEST = 2 : PWM only
--   TEST4_SUBTEST = 3 : input capture/runtime only
--
-- test1 note:
-- The supplied application selects short_delay when SW0=0, but that branch jumps
-- over the EINT instruction. The unmodified binary therefore needs SW0=1 to test
-- interrupts. That selects long_delay, so this TB verifies KEY1, KEY2 and the FIRST
-- visible KEY3 DIV/REM iteration; it does not wait for the complete SIZE loop.
--
-- BENCH_ROOT:
-- The path is relative to SIM/RV32IMscMCU. The user's current local tree has used
-- the spelling "Intrrupt-based IO". If your actual directory is instead spelled
-- "Interrupt-based IO", change only BENCH_ROOT (or override ITCM_INIT_FILE and
-- DTCM_INIT_FILE from ModelSim).
---------------------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

LIBRARY STD;
USE STD.ENV.ALL;

USE work.cond_compilation_package.all;

ENTITY tb_RV32IMscMCU IS
    GENERIC (
        -------------------------------------------------------------------------
        -- Same structural generics as the older tb_RV32I, so existing scripts
        -- can be adapted with minimal changes.
        -------------------------------------------------------------------------
        WORD_GRANULARITY : BOOLEAN := G_WORD_GRANULARITY;
        MODELSIM         : INTEGER := 1;
        DATA_BUS_WIDTH   : INTEGER := 32;
        ITCM_ADDR_WIDTH  : INTEGER := G_ADDRWIDTH;
        DTCM_ADDR_WIDTH  : INTEGER := G_ADDRWIDTH;
        PC_WIDTH         : INTEGER := G_PC_WIDTH;
        MA_WIDTH         : INTEGER := G_MA_WIDTH;
        DATA_WORDS_NUM   : INTEGER := G_DATA_WORDSNUM;
        DA_WIDTH         : INTEGER := G_DA_WIDTH;
        CLK_CNT_WIDTH    : INTEGER := 16;

        -------------------------------------------------------------------------
        -- Benchmark selection
        -------------------------------------------------------------------------
        TEST_NUM          : INTEGER RANGE 1 TO 4 := 4;
        TEST4_SUBTEST     : INTEGER RANGE 0 TO 3 := 0;
        RUN_TIMER_CHECKS  : BOOLEAN := TRUE;

        BENCH_ROOT : STRING := "C:\Users\mayja\labs architecture hanan\RISCV-MCU-Final-Project\Benchmark apps-20260827T145317Z-1-001\Benchmark apps\Interrupt-based IO";

        -- Optional explicit image overrides. "AUTO" means: derive the
        -- image path automatically from BENCH_ROOT and TEST_NUM.
        ITCM_INIT_FILE : STRING := "AUTO";
        DTCM_INIT_FILE : STRING := "AUTO";

        -------------------------------------------------------------------------
        -- Testbench timing only; these are NOT DUT timer periods.
        -------------------------------------------------------------------------
        RESET_TIME          : TIME := 2 us;
        INIT_WAIT           : TIME := 50 us;
        KEY_LOW_TIME        : TIME := 1 us;
        SERVICE_WAIT        : TIME := 50 us;

        -- Timeouts, not assumed exact event times. The TB waits for the expected
        -- visible event and fails if it has not appeared before the timeout.
        FIRST_TIMER_TIMEOUT : TIME := 900 ms;
        FAST_TIMER_TIMEOUT  : TIME := 150 ms;
        PWM_OBSERVE_TIME    : TIME := 500 us;
        CAPTURE_WAIT        : TIME := 200 us
    );
END tb_RV32IMscMCU;


ARCHITECTURE sim OF tb_RV32IMscMCU IS

    -----------------------------------------------------------------------------
    -- Helpers
    -----------------------------------------------------------------------------
    FUNCTION test_folder(n : INTEGER) RETURN STRING IS
    BEGIN
        CASE n IS
            WHEN 1      => RETURN "test1";
            WHEN 2      => RETURN "test2";
            WHEN 3      => RETURN "test3";
            WHEN 4      => RETURN "test4";
            WHEN OTHERS => RETURN "test1";
        END CASE;
    END FUNCTION;

    FUNCTION choose_file(custom_file : STRING; default_file : STRING) RETURN STRING IS
    BEGIN
        IF custom_file = "AUTO" THEN
            RETURN default_file;
        ELSE
            RETURN custom_file;
        END IF;
    END FUNCTION;

    SUBTYPE seg7_t IS STD_LOGIC_VECTOR(6 DOWNTO 0);

    -- Same gfedcba truth table and active-low polarity as SevenSegmentEncoder.vhd.
    FUNCTION seg7(hex_value : NATURAL) RETURN seg7_t IS
        VARIABLE segment_on_v : seg7_t;
    BEGIN
        CASE hex_value IS
            WHEN 0      => segment_on_v := "0111111";
            WHEN 1      => segment_on_v := "0000110";
            WHEN 2      => segment_on_v := "1011011";
            WHEN 3      => segment_on_v := "1001111";
            WHEN 4      => segment_on_v := "1100110";
            WHEN 5      => segment_on_v := "1101101";
            WHEN 6      => segment_on_v := "1111101";
            WHEN 7      => segment_on_v := "0000111";
            WHEN 8      => segment_on_v := "1111111";
            WHEN 9      => segment_on_v := "1101111";
            WHEN 10     => segment_on_v := "1110111";
            WHEN 11     => segment_on_v := "1111100";
            WHEN 12     => segment_on_v := "0111001";
            WHEN 13     => segment_on_v := "1011110";
            WHEN 14     => segment_on_v := "1111001";
            WHEN 15     => segment_on_v := "1110001";
            WHEN OTHERS => segment_on_v := "0000000";
        END CASE;
        RETURN NOT segment_on_v;
    END FUNCTION;

    -- Expected test4 array results derived from the supplied assembly data:
    -- arr1 = 81..90, arr2 = 11..20.
    FUNCTION expected_div(index_v : INTEGER) RETURN NATURAL IS
    BEGIN
        CASE index_v IS
            WHEN 0 => RETURN 7;
            WHEN 1 => RETURN 6;
            WHEN 2 => RETURN 6;
            WHEN 3 => RETURN 6;
            WHEN 4 => RETURN 5;
            WHEN 5 => RETURN 5;
            WHEN 6 => RETURN 5;
            WHEN 7 => RETURN 4;
            WHEN 8 => RETURN 4;
            WHEN 9 => RETURN 4;
            WHEN OTHERS => RETURN 0;
        END CASE;
    END FUNCTION;

    FUNCTION expected_rem(index_v : INTEGER) RETURN NATURAL IS
    BEGIN
        CASE index_v IS
            WHEN 0 => RETURN 4;
            WHEN 1 => RETURN 10;
            WHEN 2 => RETURN 5;
            WHEN 3 => RETURN 0;
            WHEN 4 => RETURN 10;
            WHEN 5 => RETURN 6;
            WHEN 6 => RETURN 2;
            WHEN 7 => RETURN 16;
            WHEN 8 => RETURN 13;
            WHEN 9 => RETURN 10;
            WHEN OTHERS => RETURN 0;
        END CASE;
    END FUNCTION;

    CONSTANT AUTO_ITCM_FILE_C : STRING :=
        BENCH_ROOT & "/" & test_folder(TEST_NUM) & "/bin/M9K-intel/ITCM.hex";
    CONSTANT AUTO_DTCM_FILE_C : STRING :=
        BENCH_ROOT & "/" & test_folder(TEST_NUM) & "/bin/M9K-intel/DTCM.hex";

    CONSTANT ITCM_FILE_C : STRING := choose_file(ITCM_INIT_FILE, AUTO_ITCM_FILE_C);
    CONSTANT DTCM_FILE_C : STRING := choose_file(DTCM_INIT_FILE, AUTO_DTCM_FILE_C);

    -----------------------------------------------------------------------------
    -- Addresses used only by monitors
    -----------------------------------------------------------------------------
    CONSTANT STATE_ADDR_C       : INTEGER := 16#0020#;
    CONSTANT BTCMPR0_ADDR_C     : INTEGER := 16#2020#;
    CONSTANT BTCMPR1_ADDR_C     : INTEGER := 16#2024#;

    CONSTANT DIVARR_BASE_C      : INTEGER := 16#0074#;
    CONSTANT DIVARR_LAST_C      : INTEGER := 16#0098#;
    CONSTANT REMARR_BASE_C      : INTEGER := 16#009C#;
    CONSTANT REMARR_LAST_C      : INTEGER := 16#00C0#;
    CONSTANT RUNTIME_DIV_ADDR_C : INTEGER := 16#00C4#;
    CONSTANT RUNTIME_REM_ADDR_C : INTEGER := 16#00C8#;

    -----------------------------------------------------------------------------
    -- Board-side inputs
    -----------------------------------------------------------------------------
    SIGNAL rst_i       : STD_LOGIC := '1';
    SIGNAL clk_i       : STD_LOGIC := '0';
    SIGNAL SW_i        : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL KEY_i       : STD_LOGIC_VECTOR(3 DOWNTO 1) := "111";
    SIGNAL CAPIN1_i    : STD_LOGIC := '0';
    SIGNAL CAPIN2_i    : STD_LOGIC := '0';

    -----------------------------------------------------------------------------
    -- Board-side outputs
    -----------------------------------------------------------------------------
    SIGNAL LEDR_o      : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL HEX0_o      : STD_LOGIC_VECTOR(6 DOWNTO 0);
    SIGNAL HEX1_o      : STD_LOGIC_VECTOR(6 DOWNTO 0);
    SIGNAL HEX2_o      : STD_LOGIC_VECTOR(6 DOWNTO 0);
    SIGNAL HEX3_o      : STD_LOGIC_VECTOR(6 DOWNTO 0);
    SIGNAL HEX4_o      : STD_LOGIC_VECTOR(6 DOWNTO 0);
    SIGNAL HEX5_o      : STD_LOGIC_VECTOR(6 DOWNTO 0);
    SIGNAL PWMout_o    : STD_LOGIC;

    -----------------------------------------------------------------------------
    -- Observation outputs exposed by MCU with SIGTAP=1
    -----------------------------------------------------------------------------
    SIGNAL pc_o                : STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
    SIGNAL instruction_o       : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
    SIGNAL RegWrite_ctrl_o     : STD_LOGIC;
    SIGNAL MemWrite_ctrl_o     : STD_LOGIC;
    SIGNAL Branch_ctrl_o       : STD_LOGIC;
    SIGNAL read_data1_o        : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
    SIGNAL read_data2_o        : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
    SIGNAL write_data_o        : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
    SIGNAL alu_res_o           : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
    SIGNAL brTaken_o           : STD_LOGIC;
    SIGNAL dtcm_addr_o         : STD_LOGIC_VECTOR(DA_WIDTH-1 DOWNTO 0);
    SIGNAL dtcm_data_wr_o      : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
    SIGNAL dtcm_data_rd_o      : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
    SIGNAL smclk_o             : STD_LOGIC;
    SIGNAL mclk_cnt_o          : STD_LOGIC_VECTOR(CLK_CNT_WIDTH-1 DOWNTO 0);

    -----------------------------------------------------------------------------
    -- Monitors
    -----------------------------------------------------------------------------
    SIGNAL pwm_edge_count_s        : NATURAL := 0;

    SIGNAL state_store_count_s     : NATURAL := 0;
    SIGNAL last_state_store_s      : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');

    SIGNAL btcmpr0_store_count_s   : NATURAL := 0;
    SIGNAL last_btcmpr0_store_s    : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL btcmpr1_store_count_s   : NATURAL := 0;
    SIGNAL last_btcmpr1_store_s    : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');

    SIGNAL divarr_store_count_s    : NATURAL := 0;
    SIGNAL remarr_store_count_s    : NATURAL := 0;
    SIGNAL runtime_div_store_s     : NATURAL := 0;
    SIGNAL runtime_rem_store_s     : NATURAL := 0;
    SIGNAL last_runtime_div_s      : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL last_runtime_rem_s      : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');

BEGIN

    ASSERT MODELSIM = 1
        REPORT "tb_RV32IMscMCU is intended for ModelSim with MODELSIM=1"
        SEVERITY FAILURE;

    -----------------------------------------------------------------------------
    -- Complete MCU under test
    -----------------------------------------------------------------------------
    DUT : ENTITY work.MCU
        GENERIC MAP (
            WORD_GRANULARITY => WORD_GRANULARITY,
            MODELSIM         => MODELSIM,
            SIGTAP           => 1,
            DATA_BUS_WIDTH   => DATA_BUS_WIDTH,
            ITCM_ADDR_WIDTH  => ITCM_ADDR_WIDTH,
            DTCM_ADDR_WIDTH  => DTCM_ADDR_WIDTH,
            PC_WIDTH         => PC_WIDTH,
            MA_WIDTH         => MA_WIDTH,
            DATA_WORDS_NUM   => DATA_WORDS_NUM,
            DA_WIDTH         => DA_WIDTH,
            CLK_CNT_WIDTH    => CLK_CNT_WIDTH,
            ITCM_INIT_FILE   => ITCM_FILE_C,
            DTCM_INIT_FILE   => DTCM_FILE_C
        )
        PORT MAP (
            rst_i               => rst_i,
            clk_i               => clk_i,
            SW_i                => SW_i,
            KEY_i               => KEY_i,

            LEDR_o              => LEDR_o,
            HEX0_o              => HEX0_o,
            HEX1_o              => HEX1_o,
            HEX2_o              => HEX2_o,
            HEX3_o              => HEX3_o,
            HEX4_o              => HEX4_o,
            HEX5_o              => HEX5_o,

            PWMout_o            => PWMout_o,
            CAPIN1_i            => CAPIN1_i,
            CAPIN2_i            => CAPIN2_i,

            pc_o                => pc_o,
            instruction_o       => instruction_o,
            RegWrite_ctrl_o     => RegWrite_ctrl_o,
            MemWrite_ctrl_o     => MemWrite_ctrl_o,
            Branch_ctrl_o       => Branch_ctrl_o,
            read_data1_o        => read_data1_o,
            read_data2_o        => read_data2_o,
            write_data_o        => write_data_o,
            alu_res_o           => alu_res_o,
            brTaken_o           => brTaken_o,
            dtcm_addr_o         => dtcm_addr_o,
            dtcm_data_wr_o      => dtcm_data_wr_o,
            dtcm_data_rd_o      => dtcm_data_rd_o,
            smclk_o             => smclk_o,
            mclk_cnt_o          => mclk_cnt_o
        );

    -----------------------------------------------------------------------------
    -- 50 MHz board reference clock.
    -----------------------------------------------------------------------------
    CLK_GEN : PROCESS
    BEGIN
        clk_i <= '0';
        WAIT FOR 10 ns;
        clk_i <= '1';
        WAIT FOR 10 ns;
    END PROCESS;

    -----------------------------------------------------------------------------
    -- Count PWM transitions.
    -----------------------------------------------------------------------------
    PWM_MON : PROCESS(PWMout_o)
    BEGIN
        IF PWMout_o'EVENT THEN
            pwm_edge_count_s <= pwm_edge_count_s + 1;
        END IF;
    END PROCESS;

    -----------------------------------------------------------------------------
    -- Observe CPU stores on the unified data address bus.
    --
    -- Do not trigger from rising_edge(MemWrite_ctrl_o): MemWrite may stay high
    -- across consecutive STORE instructions, and address/data/control can settle
    -- in neighbouring delta cycles.
    --
    -- mclk_cnt_o changes once per CPU MCLK rising edge.  We use that as the
    -- sampling event, wait 1 ps for the combinational bus signals to settle, and
    -- then inspect the store for the current CPU cycle.
    -----------------------------------------------------------------------------
    BUS_WRITE_MON : PROCESS
        VARIABLE addr_v  : INTEGER;
        VARIABLE index_v : INTEGER;
    BEGIN
        WAIT ON mclk_cnt_o;
        WAIT FOR 1 ps;

        IF rst_i = '0' AND MemWrite_ctrl_o = '1' THEN
            addr_v := to_integer(unsigned(dtcm_addr_o));

            IF addr_v = STATE_ADDR_C THEN
                state_store_count_s <= state_store_count_s + 1;
                last_state_store_s  <= dtcm_data_wr_o;

            ELSIF addr_v = BTCMPR0_ADDR_C THEN
                btcmpr0_store_count_s <= btcmpr0_store_count_s + 1;
                last_btcmpr0_store_s  <= dtcm_data_wr_o;

            ELSIF addr_v = BTCMPR1_ADDR_C THEN
                btcmpr1_store_count_s <= btcmpr1_store_count_s + 1;
                last_btcmpr1_store_s  <= dtcm_data_wr_o;

            ELSIF TEST_NUM = 4 AND
                  addr_v >= DIVARR_BASE_C AND addr_v <= DIVARR_LAST_C AND
                  ((addr_v - DIVARR_BASE_C) MOD 4 = 0) THEN

                index_v := (addr_v - DIVARR_BASE_C) / 4;

                divarr_store_count_s <= divarr_store_count_s + 1;

                ASSERT dtcm_data_wr_o =
                       STD_LOGIC_VECTOR(to_unsigned(expected_div(index_v), 32))
                    REPORT "test4 DIV array wrong value at index " &
                           INTEGER'IMAGE(index_v)
                    SEVERITY ERROR;

            ELSIF TEST_NUM = 4 AND
                  addr_v >= REMARR_BASE_C AND addr_v <= REMARR_LAST_C AND
                  ((addr_v - REMARR_BASE_C) MOD 4 = 0) THEN

                index_v := (addr_v - REMARR_BASE_C) / 4;

                remarr_store_count_s <= remarr_store_count_s + 1;

                ASSERT dtcm_data_wr_o =
                       STD_LOGIC_VECTOR(to_unsigned(expected_rem(index_v), 32))
                    REPORT "test4 REM array wrong value at index " &
                           INTEGER'IMAGE(index_v)
                    SEVERITY ERROR;

            ELSIF TEST_NUM = 4 AND addr_v = RUNTIME_DIV_ADDR_C THEN
                runtime_div_store_s <= runtime_div_store_s + 1;
                last_runtime_div_s  <= dtcm_data_wr_o;

            ELSIF TEST_NUM = 4 AND addr_v = RUNTIME_REM_ADDR_C THEN
                runtime_rem_store_s <= runtime_rem_store_s + 1;
                last_runtime_rem_s  <= dtcm_data_wr_o;
            END IF;
        END IF;
    END PROCESS;

    -----------------------------------------------------------------------------
    -- Stimulus for test1..test4
    -----------------------------------------------------------------------------
    STIMULUS : PROCESS

        VARIABLE pwm_before_v        : NATURAL;
        VARIABLE state_before_v      : NATURAL;
        VARIABLE cmp0_before_v       : NATURAL;
        VARIABLE cmp1_before_v       : NATURAL;
        VARIABLE div_before_v        : NATURAL;
        VARIABLE rem_before_v        : NATURAL;
        VARIABLE rt_div_before_v     : NATURAL;
        VARIABLE rt_rem_before_v     : NATURAL;

        PROCEDURE do_reset IS
        BEGIN
            KEY_i <= "111";
            rst_i <= '1';

            WAIT FOR RESET_TIME;

            rst_i <= '0';

            WAIT FOR INIT_WAIT;
        END PROCEDURE;

        PROCEDURE key_release_event(CONSTANT key_num : IN INTEGER) IS
        BEGIN
            -- Active-low:
            -- 1->0 = press
            -- 0->1 = release = interrupt event
            KEY_i(key_num) <= '0';

            WAIT FOR KEY_LOW_TIME;

            KEY_i(key_num) <= '1';

            WAIT FOR SERVICE_WAIT;
        END PROCEDURE;

        PROCEDURE key_event_expect_state(
            CONSTANT key_num        : IN INTEGER;
            CONSTANT expected_state : IN NATURAL
        ) IS
        BEGIN
            state_before_v := state_store_count_s;

            key_release_event(key_num);

            ASSERT state_store_count_s > state_before_v
                REPORT "KEY" & INTEGER'IMAGE(key_num) &
                       " did not cause the ISR to store the FSM state"
                SEVERITY ERROR;

            ASSERT last_state_store_s =
                   STD_LOGIC_VECTOR(to_unsigned(expected_state, 32))
                REPORT "KEY" & INTEGER'IMAGE(key_num) &
                       " ISR stored the wrong FSM state"
                SEVERITY ERROR;
        END PROCEDURE;

        PROCEDURE expect_digit(
            SIGNAL actual      : IN seg7_t;
            CONSTANT expected  : IN NATURAL;
            CONSTANT where_s   : IN STRING
        ) IS
        BEGIN
            ASSERT actual = seg7(expected)
                REPORT "HEX mismatch at " & where_s
                SEVERITY ERROR;
        END PROCEDURE;

        PROCEDURE expect_zeroed_hexes IS
        BEGIN
            expect_digit(HEX0_o, 0, "HEX0");
            expect_digit(HEX1_o, 0, "HEX1");
            expect_digit(HEX2_o, 0, "HEX2");
            expect_digit(HEX3_o, 0, "HEX3");
            expect_digit(HEX4_o, 0, "HEX4");
            expect_digit(HEX5_o, 0, "HEX5");
        END PROCEDURE;

        PROCEDURE expect_six_hex_value_1(
            CONSTANT where_s : IN STRING
        ) IS
        BEGIN
            expect_digit(HEX5_o, 0, where_s & " HEX5");
            expect_digit(HEX4_o, 0, where_s & " HEX4");
            expect_digit(HEX3_o, 0, where_s & " HEX3");
            expect_digit(HEX2_o, 0, where_s & " HEX2");
            expect_digit(HEX1_o, 0, where_s & " HEX1");
            expect_digit(HEX0_o, 1, where_s & " HEX0");
        END PROCEDURE;

        PROCEDURE expect_six_hex_value_2(
            CONSTANT where_s : IN STRING
        ) IS
        BEGIN
            expect_digit(HEX5_o, 0, where_s & " HEX5");
            expect_digit(HEX4_o, 0, where_s & " HEX4");
            expect_digit(HEX3_o, 0, where_s & " HEX3");
            expect_digit(HEX2_o, 0, where_s & " HEX2");
            expect_digit(HEX1_o, 0, where_s & " HEX1");
            expect_digit(HEX0_o, 2, where_s & " HEX0");
        END PROCEDURE;

    BEGIN

        -------------------------------------------------------------------------
        -- Common initial conditions
        -------------------------------------------------------------------------
        SW_i     <= (OTHERS => '0');
        KEY_i    <= "111";
        CAPIN1_i <= '0';
        CAPIN2_i <= '0';

        -- Supplied test1 application issue:
        -- SW0=0 selects short_delay but jumps over EINT.
        IF TEST_NUM = 1 THEN
            SW_i(0) <= '1';
        END IF;

        REPORT "============================================================"
            SEVERITY NOTE;
        REPORT "tb_RV32IMscMCU: Interrupt-based IO test" &
               INTEGER'IMAGE(TEST_NUM)
            SEVERITY NOTE;
        REPORT "ITCM = " & ITCM_FILE_C
            SEVERITY NOTE;
        REPORT "DTCM = " & DTCM_FILE_C
            SEVERITY NOTE;
        REPORT "============================================================"
            SEVERITY NOTE;

        do_reset;

        expect_zeroed_hexes;

        ASSERT LEDR_o = x"00"
            REPORT "LEDR was not zero after reset/software initialization"
            SEVERITY ERROR;

        -------------------------------------------------------------------------
        -- TEST 1 : KEY interrupts + GPIO + DIV/REM
        -------------------------------------------------------------------------
        CASE TEST_NUM IS

            WHEN 1 =>

                REPORT "TEST1: KEY1 -> HEX5:HEX4 = arr1[0] = 0x64"
                    SEVERITY NOTE;

                key_event_expect_state(1, 1);

                expect_digit(HEX5_o, 6, "test1 KEY1 HEX5");
                expect_digit(HEX4_o, 4, "test1 KEY1 HEX4");


                REPORT "TEST1: KEY2 -> HEX3:HEX2 = arr2[0] = 0x08"
                    SEVERITY NOTE;

                key_event_expect_state(2, 2);

                expect_digit(HEX3_o, 0, "test1 KEY2 HEX3");
                expect_digit(HEX2_o, 8, "test1 KEY2 HEX2");


                REPORT "TEST1: KEY3 -> verify first array/DIV/REM iteration"
                    SEVERITY NOTE;

                key_event_expect_state(3, 3);

                -- arr1[0] = 100 = 0x64
                -- arr2[0] =   8 = 0x08
                -- DIV     =  12 = 0x0C
                -- REM     =   4 = 0x04
                expect_digit(HEX5_o, 6,  "test1 KEY3 HEX5");
                expect_digit(HEX4_o, 4,  "test1 KEY3 HEX4");
                expect_digit(HEX3_o, 0,  "test1 KEY3 HEX3");
                expect_digit(HEX2_o, 8,  "test1 KEY3 HEX2");
                expect_digit(HEX1_o, 0,  "test1 KEY3 HEX1");
                expect_digit(HEX0_o, 12, "test1 KEY3 HEX0");

                ASSERT LEDR_o = x"04"
                    REPORT "test1 KEY3: LEDR should contain remainder 0x04"
                    SEVERITY ERROR;

                REPORT
                    "TEST1 PASS for KEY1, KEY2 and the first visible KEY3 iteration."
                    SEVERITY NOTE;

                REPORT
                    "TEST1 note: full SIZE loop is not awaited because SW0=1 selects long_delay."
                    SEVERITY NOTE;


            ---------------------------------------------------------------------
            -- TEST 2 : Basic Timer increments a0; keys choose display pair
            ---------------------------------------------------------------------
            WHEN 2 =>

                REPORT
                    "TEST2: verify all three key ISR paths while a0 is still 0."
                    SEVERITY NOTE;

                key_event_expect_state(1, 1);
                expect_digit(HEX1_o, 0, "test2 KEY1 HEX1");
                expect_digit(HEX0_o, 0, "test2 KEY1 HEX0");

                key_event_expect_state(2, 2);
                expect_digit(HEX3_o, 0, "test2 KEY2 HEX3");
                expect_digit(HEX2_o, 0, "test2 KEY2 HEX2");

                key_event_expect_state(3, 3);
                expect_digit(HEX5_o, 0, "test2 KEY3 HEX5");
                expect_digit(HEX4_o, 0, "test2 KEY3 HEX4");


                IF RUN_TIMER_CHECKS THEN

                    REPORT
                        "TEST2: waiting for first BT interrupt (~0.8 s at current clocks)."
                        SEVERITY NOTE;

                    -- state memory still contains STATE3.
                    -- BT_ISR increments a0 and restores fp=3.
                    -- STATE3 then displays 0x01 on HEX5:HEX4.
                    WAIT UNTIL
                        (HEX5_o = seg7(0) AND HEX4_o = seg7(1))
                        FOR FIRST_TIMER_TIMEOUT;

                    ASSERT
                        (HEX5_o = seg7(0) AND HEX4_o = seg7(1))
                        REPORT
                            "test2: first Basic-Timer interrupt was not observed before timeout"
                        SEVERITY ERROR;


                    -- a0 is now 1.
                    -- Check all three display-selection paths.
                    key_event_expect_state(1, 1);

                    expect_digit(HEX1_o, 0, "test2 a0=1 KEY1 HEX1");
                    expect_digit(HEX0_o, 1, "test2 a0=1 KEY1 HEX0");


                    key_event_expect_state(2, 2);

                    expect_digit(HEX3_o, 0, "test2 a0=1 KEY2 HEX3");
                    expect_digit(HEX2_o, 1, "test2 a0=1 KEY2 HEX2");


                    key_event_expect_state(3, 3);

                    expect_digit(HEX5_o, 0, "test2 a0=1 KEY3 HEX5");
                    expect_digit(HEX4_o, 1, "test2 a0=1 KEY3 HEX4");


                    REPORT
                        "TEST2 PASS: KEY1/2/3 paths and first Basic-Timer interrupt verified."
                        SEVERITY NOTE;

                ELSE

                    REPORT
                        "TEST2 PARTIAL: key ISR paths verified; Basic-Timer interval not awaited."
                        SEVERITY NOTE;

                END IF;


            ---------------------------------------------------------------------
            -- TEST 3 : keys reprogram periodic interrupt interval
            ---------------------------------------------------------------------
            WHEN 3 =>

                REPORT "TEST3: KEY1 programs SEC_PERIOD/2."
                    SEVERITY NOTE;

                cmp0_before_v := btcmpr0_store_count_s;

                key_event_expect_state(1, 1);

                ASSERT btcmpr0_store_count_s > cmp0_before_v
                    REPORT "test3 KEY1: no BTCMPR0 write observed"
                    SEVERITY ERROR;

                ASSERT last_btcmpr0_store_s = x"001312D0"
                    REPORT
                        "test3 KEY1: BTCMPR0 should be SEC_PERIOD/2 = 0x001312D0"
                    SEVERITY ERROR;


                REPORT "TEST3: KEY2 programs SEC_PERIOD/4."
                    SEVERITY NOTE;

                cmp0_before_v := btcmpr0_store_count_s;

                key_event_expect_state(2, 2);

                ASSERT btcmpr0_store_count_s > cmp0_before_v
                    REPORT "test3 KEY2: no BTCMPR0 write observed"
                    SEVERITY ERROR;

                ASSERT last_btcmpr0_store_s = x"00098968"
                    REPORT
                        "test3 KEY2: BTCMPR0 should be SEC_PERIOD/4 = 0x00098968"
                    SEVERITY ERROR;


                REPORT "TEST3: KEY3 programs SEC_PERIOD/8."
                    SEVERITY NOTE;

                cmp0_before_v := btcmpr0_store_count_s;

                key_event_expect_state(3, 3);

                ASSERT btcmpr0_store_count_s > cmp0_before_v
                    REPORT "test3 KEY3: no BTCMPR0 write observed"
                    SEVERITY ERROR;

                ASSERT last_btcmpr0_store_s = x"0004C4B4"
                    REPORT
                        "test3 KEY3: BTCMPR0 should be SEC_PERIOD/8 = 0x0004C4B4"
                    SEVERITY ERROR;


                IF RUN_TIMER_CHECKS THEN

                    -----------------------------------------------------------------
                    -- Double-buffering correction:
                    --
                    -- The new BTCMPR0 value is NOT immediately the active BTCL0.
                    -- The first interrupt still comes from the old initial period.
                    -----------------------------------------------------------------
                    REPORT
                        "TEST3: waiting for first interrupt at OLD buffered period."
                        SEVERITY NOTE;

                    WAIT UNTIL LEDR_o = x"01"
                        FOR FIRST_TIMER_TIMEOUT;

                    ASSERT LEDR_o = x"01"
                        REPORT
                            "test3: first timer interrupt was not observed before timeout"
                        SEVERITY ERROR;

                    expect_digit(HEX5_o, 0, "test3 first BT HEX5");
                    expect_digit(HEX4_o, 1, "test3 first BT HEX4");


                    -----------------------------------------------------------------
                    -- The first EQU0 edge has now loaded SEC_PERIOD/8 into BTCL0.
                    -- Next interrupt should therefore be ~0.1 s later.
                    -----------------------------------------------------------------
                    REPORT
                        "TEST3: waiting for next interrupt at new KEY3 interval."
                        SEVERITY NOTE;

                    WAIT UNTIL LEDR_o = x"02"
                        FOR FAST_TIMER_TIMEOUT;

                    ASSERT LEDR_o = x"02"
                        REPORT
                            "test3: updated SEC_PERIOD/8 interval was not observed before timeout"
                        SEVERITY ERROR;

                    expect_digit(HEX5_o, 0, "test3 second BT HEX5");
                    expect_digit(HEX4_o, 2, "test3 second BT HEX4");


                    REPORT
                        "TEST3 PASS: reprogramming and double-buffered timer behavior verified."
                        SEVERITY NOTE;

                ELSE

                    REPORT
                        "TEST3 PARTIAL: KEY ISR and BTCMPR0 programming verified; timer intervals not awaited."
                        SEVERITY NOTE;

                END IF;


            ---------------------------------------------------------------------
            -- TEST 4 : compare, PWM, input capture
            ---------------------------------------------------------------------
            WHEN 4 =>

                -----------------------------------------------------------------
                -- TEST4 SUBTEST 1 : Compare mode
                -----------------------------------------------------------------
                IF TEST4_SUBTEST = 0 OR TEST4_SUBTEST = 1 THEN

                    REPORT
                        "TEST4/COMPARE: first KEY1 -> final BTCMPR0=SEC_PERIOD/2."
                        SEVERITY NOTE;

                    cmp0_before_v := btcmpr0_store_count_s;

                    key_event_expect_state(1, 1);

                    ASSERT btcmpr0_store_count_s >= cmp0_before_v + 2
                        REPORT
                            "test4 compare KEY1: expected bt_cmp_config + STATE1 BTCMPR0 writes"
                        SEVERITY ERROR;

                    ASSERT last_btcmpr0_store_s = x"00989680"
                        REPORT
                            "test4 compare KEY1: final BTCMPR0 should be SEC_PERIOD/2"
                        SEVERITY ERROR;


                    REPORT
                        "TEST4/COMPARE: second KEY1 -> final BTCMPR0=SEC_PERIOD/4."
                        SEVERITY NOTE;

                    cmp0_before_v := btcmpr0_store_count_s;

                    key_event_expect_state(1, 1);

                    ASSERT btcmpr0_store_count_s >= cmp0_before_v + 2
                        REPORT
                            "test4 compare second KEY1: expected two BTCMPR0 writes"
                        SEVERITY ERROR;

                    ASSERT last_btcmpr0_store_s = x"004C4B40"
                        REPORT
                            "test4 compare second KEY1: final BTCMPR0 should be SEC_PERIOD/4"
                        SEVERITY ERROR;


                    REPORT
                        "TEST4/COMPARE: third KEY1 -> final BTCMPR0=SEC_PERIOD/8."
                        SEVERITY NOTE;

                    cmp0_before_v := btcmpr0_store_count_s;

                    key_event_expect_state(1, 1);

                    ASSERT btcmpr0_store_count_s >= cmp0_before_v + 2
                        REPORT
                            "test4 compare third KEY1: expected two BTCMPR0 writes"
                        SEVERITY ERROR;

                    ASSERT last_btcmpr0_store_s = x"002625A0"
                        REPORT
                            "test4 compare third KEY1: final BTCMPR0 should be SEC_PERIOD/8"
                        SEVERITY ERROR;


                    IF RUN_TIMER_CHECKS THEN

                        -----------------------------------------------------------------
                        -- The timer began with SEC_PERIOD active in BTCL0.
                        -- The three newer values are only candidates until EQU0.
                        -----------------------------------------------------------------
                        REPORT
                            "TEST4/COMPARE: waiting for first interrupt at old buffered period."
                            SEVERITY NOTE;

                        WAIT UNTIL HEX0_o = seg7(1)
                            FOR FIRST_TIMER_TIMEOUT;

                        ASSERT HEX0_o = seg7(1)
                            REPORT
                                "test4 compare: first timer interrupt was not observed before timeout"
                            SEVERITY ERROR;

                        expect_six_hex_value_1(
                            "test4 compare first BT"
                        );


                        -----------------------------------------------------------------
                        -- At first EQU0 the latest value, SEC_PERIOD/8, entered BTCL0.
                        -----------------------------------------------------------------
                        REPORT
                            "TEST4/COMPARE: waiting for second interrupt at SEC_PERIOD/8."
                            SEVERITY NOTE;

                        WAIT UNTIL HEX0_o = seg7(2)
                            FOR FAST_TIMER_TIMEOUT;

                        ASSERT HEX0_o = seg7(2)
                            REPORT
                                "test4 compare: updated SEC_PERIOD/8 interval was not observed before timeout"
                            SEVERITY ERROR;

                        expect_six_hex_value_2(
                            "test4 compare second BT"
                        );


                        REPORT "TEST4/COMPARE PASS."
                            SEVERITY NOTE;

                    ELSE

                        REPORT
                            "TEST4/COMPARE PARTIAL: register programming verified; timer intervals not awaited."
                            SEVERITY NOTE;

                    END IF;

                END IF;


                -----------------------------------------------------------------
                -- Start each test4 operating mode from a clean application state.
                -----------------------------------------------------------------
                IF TEST4_SUBTEST = 0 THEN

                    REPORT
                        "TEST4: reset before PWM subtest."
                        SEVERITY NOTE;

                    do_reset;

                END IF;


                -----------------------------------------------------------------
                -- TEST4 SUBTEST 2 : Output Compare / PWM
                -----------------------------------------------------------------
                IF TEST4_SUBTEST = 0 OR TEST4_SUBTEST = 2 THEN

                    -----------------------------------------------------------------
                    -- KEY2 #1 : 50%
                    -----------------------------------------------------------------
                    REPORT
                        "TEST4/PWM: KEY2 #1 -> 50% duty."
                        SEVERITY NOTE;

                    cmp0_before_v := btcmpr0_store_count_s;
                    cmp1_before_v := btcmpr1_store_count_s;

                    key_event_expect_state(2, 2);

                    ASSERT btcmpr0_store_count_s > cmp0_before_v
                        REPORT
                            "test4 PWM: no BTCMPR0 write on first KEY2"
                        SEVERITY ERROR;

                    ASSERT btcmpr1_store_count_s > cmp1_before_v
                        REPORT
                            "test4 PWM: no BTCMPR1 write on first KEY2"
                        SEVERITY ERROR;

                    ASSERT last_btcmpr0_store_s = x"00000FA0"
                        REPORT
                            "test4 PWM: BTCMPR0 should be FREQ_5K = 0x00000FA0"
                        SEVERITY ERROR;

                    ASSERT last_btcmpr1_store_s = x"000007D0"
                        REPORT
                            "test4 PWM first KEY2: BTCMPR1 should be 2000"
                        SEVERITY ERROR;


                    pwm_before_v := pwm_edge_count_s;

                    WAIT FOR PWM_OBSERVE_TIME;

                    ASSERT pwm_edge_count_s >= pwm_before_v + 2
                        REPORT
                            "test4 PWM: PWMout_o did not toggle at least twice"
                        SEVERITY ERROR;


                    -----------------------------------------------------------------
                    -- KEY2 #2 : 75%
                    -----------------------------------------------------------------
                    REPORT
                        "TEST4/PWM: KEY2 #2 -> 75% duty."
                        SEVERITY NOTE;

                    key_event_expect_state(2, 2);

                    ASSERT last_btcmpr1_store_s = x"000003E8"
                        REPORT
                            "test4 PWM second KEY2: BTCMPR1 should be 1000"
                        SEVERITY ERROR;


                    -----------------------------------------------------------------
                    -- KEY2 #3 : 87.5%
                    -----------------------------------------------------------------
                    REPORT
                        "TEST4/PWM: KEY2 #3 -> 87.5% duty."
                        SEVERITY NOTE;

                    key_event_expect_state(2, 2);

                    ASSERT last_btcmpr1_store_s = x"000001F4"
                        REPORT
                            "test4 PWM third KEY2: BTCMPR1 should be 500"
                        SEVERITY ERROR;


                    -----------------------------------------------------------------
                    -- KEY2 #4 : 93.75%
                    -----------------------------------------------------------------
                    REPORT
                        "TEST4/PWM: KEY2 #4 -> 93.75% duty."
                        SEVERITY NOTE;

                    key_event_expect_state(2, 2);

                    ASSERT last_btcmpr1_store_s = x"000000FA"
                        REPORT
                            "test4 PWM fourth KEY2: BTCMPR1 should be 250"
                        SEVERITY ERROR;


                    pwm_before_v := pwm_edge_count_s;

                    WAIT FOR PWM_OBSERVE_TIME;

                    ASSERT pwm_edge_count_s >= pwm_before_v + 2
                        REPORT
                            "test4 PWM: PWMout_o stopped toggling after duty-cycle updates"
                        SEVERITY ERROR;


                    REPORT
                        "TEST4/PWM PASS: all four duty thresholds and PWM activity verified."
                        SEVERITY NOTE;

                END IF;


                IF TEST4_SUBTEST = 0 THEN

                    REPORT
                        "TEST4: reset before input-capture subtest."
                        SEVERITY NOTE;

                    do_reset;

                END IF;


                -----------------------------------------------------------------
                -- TEST4 SUBTEST 3 : Input capture + runtime measurement
                -----------------------------------------------------------------
                IF TEST4_SUBTEST = 0 OR TEST4_SUBTEST = 3 THEN

                    -----------------------------------------------------------------
                    -- After reset a7=0.
                    -- KEY3 ISR increments a7 before STATE3 tests its parity.
                    -- First KEY3 -> a7=1 -> REM path.
                    -----------------------------------------------------------------
                    REPORT
                        "TEST4/CAPTURE: first KEY3 measures REM runtime."
                        SEVERITY NOTE;

                    rem_before_v    := remarr_store_count_s;
                    rt_rem_before_v := runtime_rem_store_s;

                    key_event_expect_state(3, 3);

                    WAIT FOR CAPTURE_WAIT;

                    ASSERT remarr_store_count_s >= rem_before_v + 10
                        REPORT
                            "test4 capture: first KEY3 did not store all 10 REM results"
                        SEVERITY ERROR;

                    ASSERT runtime_rem_store_s >= rt_rem_before_v + 1
                        REPORT
                            "test4 capture: first KEY3 did not store runtime_rem from BTCAPR"
                        SEVERITY ERROR;

                    ASSERT last_runtime_rem_s /= x"00000000"
                        REPORT
                            "test4 capture: runtime_rem was stored as zero"
                        SEVERITY ERROR;


                    -----------------------------------------------------------------
                    -- Second KEY3 -> a7=2 -> DIV path.
                    -----------------------------------------------------------------
                    REPORT
                        "TEST4/CAPTURE: second KEY3 measures DIV runtime."
                        SEVERITY NOTE;

                    div_before_v    := divarr_store_count_s;
                    rt_div_before_v := runtime_div_store_s;

                    key_event_expect_state(3, 3);

                    WAIT FOR CAPTURE_WAIT;

                    ASSERT divarr_store_count_s >= div_before_v + 10
                        REPORT
                            "test4 capture: second KEY3 did not store all 10 DIV results"
                        SEVERITY ERROR;

                    ASSERT runtime_div_store_s >= rt_div_before_v + 1
                        REPORT
                            "test4 capture: second KEY3 did not store runtime_div from BTCAPR"
                        SEVERITY ERROR;

                    ASSERT last_runtime_div_s /= x"00000000"
                        REPORT
                            "test4 capture: runtime_div was stored as zero"
                        SEVERITY ERROR;


                    REPORT
                        "TEST4/CAPTURE PASS: correct REM/DIV arrays and non-zero captured runtimes verified."
                        SEVERITY NOTE;

                END IF;


                IF RUN_TIMER_CHECKS OR
                   (TEST4_SUBTEST = 2) OR
                   (TEST4_SUBTEST = 3) THEN

                    REPORT
                        "TEST4 selected checks complete."
                        SEVERITY NOTE;

                ELSE

                    REPORT
                        "TEST4 selected checks complete, with compare timer interval skipped."
                        SEVERITY NOTE;

                END IF;


            WHEN OTHERS =>
                NULL;

        END CASE;


        REPORT "============================================================"
            SEVERITY NOTE;

        REPORT
            "tb_RV32IMscMCU finished test" &
            INTEGER'IMAGE(TEST_NUM) & "."
            SEVERITY NOTE;

        REPORT
            "Also inspect/save the interrupt waveforms; the project report requires benchmark timing waveforms."
            SEVERITY NOTE;

        REPORT "============================================================"
            SEVERITY NOTE;


        STOP;

        WAIT;

    END PROCESS;

END sim;