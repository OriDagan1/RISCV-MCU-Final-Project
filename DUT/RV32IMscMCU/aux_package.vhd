---------------------------------------------------------------------------------------------
-- Copyright 2025 Hananya Ribo 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
---------------------------------------------------------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;
USE work.cond_compilation_package.all;


package aux_package is

	component MCU is
		generic(
			WORD_GRANULARITY 	: boolean 	:= G_WORD_GRANULARITY;
			MODELSIM 					: integer 	:= G_MODELSIM;
			SIGTAP						: integer	:= G_SIGTAP;
			DATA_BUS_WIDTH 		: integer 	:= 32;
			ITCM_ADDR_WIDTH 	: integer 	:= G_ADDRWIDTH;
			DTCM_ADDR_WIDTH 	: integer 	:= G_ADDRWIDTH;
			PC_WIDTH 					: integer 	:= G_PC_WIDTH;
			MA_WIDTH 					: integer 	:= G_MA_WIDTH;
			DATA_WORDS_NUM 		: integer 	:= G_DATA_WORDSNUM;
			DA_WIDTH					: integer 	:= G_DA_WIDTH;
			CLK_CNT_WIDTH 		: integer 	:= 16;
			LEDR_WIDTH				: integer	:= 8;
			SW_WIDTH					: integer	:= 8;
			ITCM_INIT_FILE		: string	:= "C:\Users\oripa\Documents\Benchmark_Apps\test3\RV32IM\bin\M9K-intel\ITCM.hex";
			DTCM_INIT_FILE		: string	:= "C:\Users\oripa\Documents\Benchmark_Apps\test3\RV32IM\bin\M9K-intel\DTCM.hex"
		);
		PORT(
			--Inputs
			rst_i		 					:IN	STD_LOGIC;
			clk_i							:IN	STD_LOGIC;

			SW_i							:IN	STD_LOGIC_VECTOR(SW_WIDTH-1 DOWNTO 0);

			KEY_i							:IN	STD_LOGIC_VECTOR(3 DOWNTO 1);	-- PORT_PB 0x2014

			--Memory-mapped I/O pins (Figure 5)
			LEDR_o						:OUT	STD_LOGIC_VECTOR(LEDR_WIDTH-1 DOWNTO 0);
			HEX0_o						:OUT	STD_LOGIC_VECTOR(6 DOWNTO 0);
			HEX1_o						:OUT	STD_LOGIC_VECTOR(6 DOWNTO 0);
			HEX2_o						:OUT	STD_LOGIC_VECTOR(6 DOWNTO 0);
			HEX3_o						:OUT	STD_LOGIC_VECTOR(6 DOWNTO 0);
			HEX4_o						:OUT	STD_LOGIC_VECTOR(6 DOWNTO 0);
			HEX5_o						:OUT	STD_LOGIC_VECTOR(6 DOWNTO 0);

			--Basic Timer pins (Fig.7), on the clause 4 expansion header
			PWMout_o					:OUT	STD_LOGIC;
			CAPIN1_i					:IN		STD_LOGIC;
			CAPIN2_i					:IN		STD_LOGIC;

			--Outputs for verification and FPGA validation. Null ranges when
			--SIGTAP=0, so they cost no pins - see the note in MCU.vhd.
			pc_o							:OUT	STD_LOGIC_VECTOR(PC_WIDTH*SIGTAP-1 DOWNTO 0);
			instruction_o			:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH*SIGTAP-1 DOWNTO 0);

			RegWrite_ctrl_o		:OUT 	STD_LOGIC;
			MemWrite_ctrl_o		:OUT 	STD_LOGIC;
			Branch_ctrl_o			:OUT 	STD_LOGIC;

			read_data1_o 			:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH*SIGTAP-1 DOWNTO 0);
			read_data2_o 			:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH*SIGTAP-1 DOWNTO 0);
			write_data_o			:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH*SIGTAP-1 DOWNTO 0);

			alu_res_o 				:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH*SIGTAP-1 DOWNTO 0);
			brTaken_o					:OUT 	STD_LOGIC;

			dtcm_addr_o				:OUT 	STD_LOGIC_VECTOR(DA_WIDTH*SIGTAP-1 DOWNTO 0);
			dtcm_data_wr_o		:OUT 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH*SIGTAP-1 DOWNTO 0);
			dtcm_data_rd_o		:OUT 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH*SIGTAP-1 DOWNTO 0);

			smclk_o						:OUT	STD_LOGIC;

			mclk_cnt_o				:OUT	STD_LOGIC_VECTOR(CLK_CNT_WIDTH*SIGTAP-1 DOWNTO 0)
		);
	end component;
---------------------------------------------------------
	component RV32I_CORE is
		generic(
			WORD_GRANULARITY 	: boolean 	:= G_WORD_GRANULARITY;
	    MODELSIM 					: integer 	:= G_MODELSIM;
			DATA_BUS_WIDTH 		: integer 	:= 32;
			ITCM_ADDR_WIDTH 	: integer 	:= G_ADDRWIDTH;
			DTCM_ADDR_WIDTH 	: integer 	:= G_ADDRWIDTH;
			PC_WIDTH 					: integer 	:= 10;
			MA_WIDTH 					: integer 	:= 10;
			DATA_WORDS_NUM 		: integer 	:= G_DATA_WORDSNUM;
			DA_WIDTH					: integer 	:= G_DA_WIDTH;
			CLK_CNT_WIDTH 		: integer 	:= 16;
			ITCM_INIT_FILE		: string	:= "C:\Users\oripa\Documents\Benchmark_Apps\test3\RV32IM\bin\M9K-intel\ITCM.hex"
		);
		PORT(
			--Inputs
			rst_i		 					:IN	STD_LOGIC;
			mclk_i						:IN	STD_LOGIC;
			divclk_i					:IN	STD_LOGIC;

			--Data bus, master side
			dtcm_data_rd_i		:IN 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

			dtcm_addr_o				:OUT 	STD_LOGIC_VECTOR(DA_WIDTH-1 DOWNTO 0);
			dtcm_data_wr_o		:OUT 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			MemRead_ctrl_o		:OUT 	STD_LOGIC;
			MemWrite_ctrl_o		:OUT 	STD_LOGIC;

			--Outputs (used also for Signal-Tap auxiliary pins)
			pc_o							:OUT	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
			instruction_o			:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

			RegWrite_ctrl_o		:OUT 	STD_LOGIC;
			Branch_ctrl_o			:OUT 	STD_LOGIC;

			read_data1_o 			:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			read_data2_o 			:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			write_data_o			:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

			alu_res_o 				:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			brTaken_o					:OUT 	STD_LOGIC;

			mclk_cnt_o				:OUT	STD_LOGIC_VECTOR(CLK_CNT_WIDTH-1 DOWNTO 0)
		);
	end component;
---------------------------------------------------------  
	component control is
		PORT( 
		--Inputs
		instruction_i 		: IN 	STD_LOGIC_VECTOR(31 DOWNTO 0);
		
		--Outputs
		RegDst_ctrl_o 		: OUT 	STD_LOGIC;
		ALUSrc_ctrl_o 		: OUT 	STD_LOGIC;
		MemtoReg_ctrl_o 	: OUT 	STD_LOGIC;
		RegWrite_ctrl_o 	: OUT 	STD_LOGIC;
		MemRead_ctrl_o 		: OUT 	STD_LOGIC;
		MemWrite_ctrl_o	 	: OUT 	STD_LOGIC;
		Branch_ctrl_o 		: OUT 	STD_LOGIC;
		Jal_ctrl_o 			: OUT 	STD_LOGIC;
		Jalr_ctrl_o 		: OUT 	STD_LOGIC;
		UpperIm_ctrl_o		: OUT 	STD_LOGIC_VECTOR(1 DOWNTO 0);
		ALUOp_ctrl_o	 	: OUT 	STD_LOGIC_VECTOR(4 DOWNTO 0);
		MULOp_ctrl_o     	: OUT	STD_LOGIC;  -- New control output

		--Division accelerator control
		DIVOp_ctrl_o		: OUT	STD_LOGIC;	-- any of div/divu/rem/remu
		DIVSigned_ctrl_o	: OUT	STD_LOGIC;	-- div/rem  (signed operands)
		DIVRem_ctrl_o		: OUT	STD_LOGIC	-- rem/remu (write back the residue)
	);
	end component;
---------------------------------------------------------	
	component dmemory is
		generic(
			DATA_BUS_WIDTH 	: integer := 32;
			DTCM_ADDR_WIDTH : integer := 8;
			WORDS_NUM 			: integer := 256;
			DTCM_INIT_FILE	: string  := "C:\Users\oripa\Documents\Benchmark_Apps\test3\RV32IM\bin\M9K-intel\DTCM.hex"
		);
		PORT(	
			--Inputs
			clk_i						: IN 	STD_LOGIC;
			rst_i						: IN 	STD_LOGIC;
			dtcm_addr_i 		: IN 	STD_LOGIC_VECTOR(DTCM_ADDR_WIDTH-1 DOWNTO 0);
			dtcm_data_wr_i 	: IN 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			MemRead_ctrl_i  : IN 	STD_LOGIC;
			MemWrite_ctrl_i : IN 	STD_LOGIC;
			
			--Outputs
			dtcm_data_rd_o 	: OUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0)
		);
	end component;
---------------------------------------------------------		
	component Execute is
		generic(
			DATA_BUS_WIDTH 	: integer := 32;
			PC_WIDTH 				: integer := 10
		);
		PORT(	
			--Inputs
			read_data1_i 		: IN 	STD_LOGIC_VECTOR(31 DOWNTO 0);
			read_data2_i 		: IN 	STD_LOGIC_VECTOR(31 DOWNTO 0);
			sign_extend_i 		: IN 	STD_LOGIC_VECTOR(31 DOWNTO 0);
			UpperIm_ctrl_i		: IN 	STD_LOGIC_VECTOR(1 DOWNTO 0);
			ALUOp_ctrl_i	 	: IN 	STD_LOGIC_VECTOR(4 DOWNTO 0);
			ALUSrc_ctrl_i 		: IN 	STD_LOGIC;
			pc_i				: IN 	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
			MULOp_ctrl_i		: IN  	STD_LOGIC;
			DIVOp_ctrl_i		: IN  	STD_LOGIC;
			div_res_i			: IN 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

			--Outputs
			brTaken_o 			: OUT	STD_LOGIC;
			alu_res_o 			: OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			addr_gen_o 			: OUT	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0)
		);
	end component;
---------------------------------------------------------		
	component Idecode is
		generic(
			PC_WIDTH 				: integer	:= 10;
			DATA_BUS_WIDTH	: integer := 32
		);
		PORT(
			--Inputs
			clk_i						: IN 	STD_LOGIC;
			rst_i						: IN 	STD_LOGIC;
			pc_plus4_i			: IN	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
			instruction_i 	: IN 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			dtcm_data_rd_i 	: IN 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			alu_res_i				: IN 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			RegDst_ctrl_i 	: IN 	STD_LOGIC;
			RegWrite_ctrl_i : IN 	STD_LOGIC;
			MemtoReg_ctrl_i : IN 	STD_LOGIC;
			
			--Outputs
			read_data1_o		: OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			read_data2_o		: OUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			SignExt_o 			: OUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0)		 
		);
	end component;
---------------------------------------------------------		
	component Ifetch is
		generic(
			WORD_GRANULARITY 	: boolean	:= False;
			DATA_BUS_WIDTH 		: integer	:= 32;
			PC_WIDTH 					: integer	:= 10;
			ITCM_ADDR_WIDTH 	: integer	:= 8;
			WORDS_NUM 				: integer	:= 256;
			ITCM_INIT_FILE		: string	:= "C:\Users\oripa\Documents\Benchmark_Apps\test3\RV32IM\bin\M9K-intel\ITCM.hex"
		);
		PORT(
			--Inputs
			clk_i					: IN 	STD_LOGIC;
			rst_i 				: IN 	STD_LOGIC;
			addr_gen_i 		: IN 	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
			Branch_ctrl_i	: IN 	STD_LOGIC;
			brTaken_i 		: IN 	STD_LOGIC;
			Jal_ctrl_i		: IN 	STD_LOGIC;
			Jalr_ctrl_i		: IN 	STD_LOGIC;
			alu_res_i 		: IN 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			stall_i				: IN 	STD_LOGIC;

			--Outputs
			pc_o 					: OUT	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
			pc_plus4_o 		: OUT	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
			instruction_o : OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0)
		);
	end component;
---------------------------------------------------------
-- There is no PLL component here on purpose. The ALTPLL that came with the
-- project was a Cyclone II megafunction, unsupported on the Cyclone V of the
-- DE10-Standard, and PLL.vhd was deleted with it. The three replacements -
-- PLL_MCLK, PLL_DIVCLK and PLL_SMCLK - are altera_pll IP generated by
-- QUARTUS/gen_plls.tcl, and MCU.vhd declares them locally because they are
-- generated artefacts rather than sources of this design.
---------------------------------------------------------
	-- The tri-state buffer of Figure 5, supplied with the project. Drives
	-- IOpin from Dout while en = '1' and releases it to 'Z' otherwise, with
	-- Din always following the bus. MCU.vhd puts one on each GPIO read path.
	COMPONENT BidirPin IS
		generic(
			width	: integer := 16
		);
		PORT(
			Dout	: IN	STD_LOGIC_VECTOR(width-1 DOWNTO 0);
			en		: IN	STD_LOGIC;
			Din		: OUT	STD_LOGIC_VECTOR(width-1 DOWNTO 0);
			IOpin	: INOUT	STD_LOGIC_VECTOR(width-1 DOWNTO 0)
		);
	END COMPONENT;
---------------------------------------------------------
	COMPONENT GPIO_AddressDecoder IS
		generic(
			DA_WIDTH			: integer := 14
		);
		PORT(
			--Inputs
			en_i				: IN	STD_LOGIC;
			addr_i				: IN	STD_LOGIC_VECTOR(DA_WIDTH-1 DOWNTO 0);

			--Outputs, one chip select per device
			cs_ledr_o			: OUT	STD_LOGIC;
			cs_hex0_1_o			: OUT	STD_LOGIC;
			cs_hex2_3_o			: OUT	STD_LOGIC;
			cs_hex4_5_o			: OUT	STD_LOGIC;
			cs_sw_o				: OUT	STD_LOGIC
		);
	END COMPONENT;
---------------------------------------------------------
	COMPONENT PERIPH_AddressDecoder IS
		generic(
			DA_WIDTH			: integer := 14
		);
		PORT(
			--Inputs
			en_i				: IN	STD_LOGIC;
			addr_i				: IN	STD_LOGIC_VECTOR(DA_WIDTH-1 DOWNTO 0);

			--Outputs, one chip select per device
			cs_pb_o				: OUT	STD_LOGIC;
			cs_btctl_o			: OUT	STD_LOGIC;
			cs_btcmpr0_o		: OUT	STD_LOGIC;
			cs_btcmpr1_o		: OUT	STD_LOGIC;
			cs_btcapr_o			: OUT	STD_LOGIC;
			cs_ic_o				: OUT	STD_LOGIC
		);
	END COMPONENT;
---------------------------------------------------------
	COMPONENT GPIO_LEDR_Interface IS
		generic(
			DATA_BUS_WIDTH		: integer := 32;
			LEDR_WIDTH			: integer := 8
		);
		PORT(
			--Inputs
			clk_i				: IN	STD_LOGIC;
			rst_i				: IN	STD_LOGIC;
			cs_i				: IN	STD_LOGIC;
			MemRead_ctrl_i		: IN	STD_LOGIC;
			MemWrite_ctrl_i		: IN	STD_LOGIC;
			data_wr_i			: IN	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

			--Outputs
			data_rd_o			: OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			LEDR_o				: OUT	STD_LOGIC_VECTOR(LEDR_WIDTH-1 DOWNTO 0)
		);
	END COMPONENT;
---------------------------------------------------------
	COMPONENT GPIO_SW_Interface IS
		generic(
			DATA_BUS_WIDTH		: integer := 32;
			SW_WIDTH			: integer := 8
		);
		PORT(
			--Inputs
			cs_i				: IN	STD_LOGIC;
			MemRead_ctrl_i		: IN	STD_LOGIC;
			SW_i				: IN	STD_LOGIC_VECTOR(SW_WIDTH-1 DOWNTO 0);

			--Outputs
			data_rd_o			: OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0)
		);
	END COMPONENT;
---------------------------------------------------------
	COMPONENT GPIO_HEX_Pair_Interface IS
		generic(
			DATA_BUS_WIDTH		: integer := 32;
			PORT_WIDTH			: integer := 8;
			ACTIVE_LOW			: boolean := TRUE
		);
		PORT(
			--Inputs
			clk_i				: IN	STD_LOGIC;
			rst_i				: IN	STD_LOGIC;
			cs_i				: IN	STD_LOGIC;
			sel_i				: IN	STD_LOGIC;
			MemRead_ctrl_i		: IN	STD_LOGIC;
			MemWrite_ctrl_i		: IN	STD_LOGIC;
			data_wr_i			: IN	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

			--Outputs
			data_rd_o			: OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			HEX_lo_o			: OUT	STD_LOGIC_VECTOR(6 DOWNTO 0);
			HEX_hi_o			: OUT	STD_LOGIC_VECTOR(6 DOWNTO 0)
		);
	END COMPONENT;
---------------------------------------------------------
	COMPONENT GPIO_PB_Interface IS
		generic(
			DATA_BUS_WIDTH		: integer := 32
		);
		PORT(
			--Inputs
			clk_i				: IN	STD_LOGIC;
			rst_i				: IN	STD_LOGIC;
			cs_i				: IN	STD_LOGIC;
			MemRead_ctrl_i		: IN	STD_LOGIC;
			KEY_i				: IN	STD_LOGIC_VECTOR(3 DOWNTO 1);

			--Outputs
			data_rd_o			: OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

			--Interrupt requests, one per key. Single cycle pulses.
			key1_irq_o			: OUT	STD_LOGIC;
			key2_irq_o			: OUT	STD_LOGIC;
			key3_irq_o			: OUT	STD_LOGIC
		);
	END COMPONENT;
---------------------------------------------------------
	COMPONENT SevenSegmentEncoder IS
		GENERIC (
			ACTIVE_LOW : BOOLEAN := TRUE
		);
		PORT (
			hex_value_i : IN  STD_LOGIC_VECTOR(3 DOWNTO 0);
			segments_o  : OUT STD_LOGIC_VECTOR(6 DOWNTO 0)
		);
	END COMPONENT;
---------------------------------------------------------
	COMPONENT multiplier IS
		PORT(
			Ain: IN std_logic_vector(15 downto 0);
			Bin: IN std_logic_vector(15 downto 0);
			Res: OUT std_logic_vector(31 downto 0)
		);
	END COMPONENT;
---------------------------------------------------------
	COMPONENT div_accel IS
		generic(
			N : positive := 32
		);
		PORT(
			--CPU side, MCLK domain only
			mclk_i			: IN 	STD_LOGIC;
			rst_i				: IN 	STD_LOGIC;
			Ain_i				: IN 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
			Bin_i				: IN 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
			div_op_i		: IN 	STD_LOGIC;

			Quotient_o	: OUT	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
			Residue_o		: OUT	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
			div_busy_o	: OUT	STD_LOGIC;

			--Accelerator clock
			divclk_i		: IN 	STD_LOGIC
		);
	END COMPONENT;
---------------------------------------------------------
-- Basic Timer (Fig.7). The timer itself has no bus interface on purpose, see
-- the header of BASIC_TIMER.vhd - basic_timer_interface below is the
-- memory-mapped wrapper MCU.vhd instantiates alongside it.
	COMPONENT basic_timer IS
		generic(
			N : positive := 32
		);
		PORT(
			--Clock and reset
			smclk_i		: IN 	STD_LOGIC;
			rst_i		: IN 	STD_LOGIC;

			--Control registers
			btctl1_i	: IN 	STD_LOGIC_VECTOR(7 DOWNTO 0);
			btctl2_i	: IN 	STD_LOGIC_VECTOR(7 DOWNTO 0);

			--Compare registers
			btcmpr0_i	: IN 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
			btcmpr1_i	: IN 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);

			--Capture inputs
			capin1_i	: IN 	STD_LOGIC;
			capin2_i	: IN 	STD_LOGIC;

			--Outputs
			pwmout_o	: OUT	STD_LOGIC;
			btifg_o		: OUT	STD_LOGIC;
			btcapr_o	: OUT	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
			btcnt_o		: OUT	STD_LOGIC_VECTOR(N-1 DOWNTO 0)
		);
	END COMPONENT;
---------------------------------------------------------
	COMPONENT basic_timer_interface IS
		generic(
			DATA_BUS_WIDTH		: integer := 32;
			N					: positive := 32;
			CTL_WIDTH			: integer := 8
		);
		PORT(
			--Inputs
			clk_i				: IN	STD_LOGIC;
			rst_i				: IN	STD_LOGIC;

			cs_btctl_i			: IN	STD_LOGIC;
			cs_btcmpr0_i		: IN	STD_LOGIC;
			cs_btcmpr1_i		: IN	STD_LOGIC;
			cs_btcapr_i			: IN	STD_LOGIC;

			sel_i				: IN	STD_LOGIC;

			MemRead_ctrl_i		: IN	STD_LOGIC;
			MemWrite_ctrl_i		: IN	STD_LOGIC;
			data_wr_i			: IN	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

			btcapr_i			: IN	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
			btifg_i				: IN	STD_LOGIC;

			--Outputs
			data_rd_o			: OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			bt_irq_o			: OUT	STD_LOGIC;

			btctl1_o			: OUT	STD_LOGIC_VECTOR(CTL_WIDTH-1 DOWNTO 0);
			btctl2_o			: OUT	STD_LOGIC_VECTOR(CTL_WIDTH-1 DOWNTO 0);
			btcmpr0_o			: OUT	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
			btcmpr1_o			: OUT	STD_LOGIC_VECTOR(N-1 DOWNTO 0)
		);
	END COMPONENT;

end aux_package;


