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
			DATA_BUS_WIDTH 		: integer 	:= 32;
			ITCM_ADDR_WIDTH 	: integer 	:= G_ADDRWIDTH;
			DTCM_ADDR_WIDTH 	: integer 	:= G_ADDRWIDTH;
			PC_WIDTH 					: integer 	:= G_PC_WIDTH;
			MA_WIDTH 					: integer 	:= G_MA_WIDTH;
			DATA_WORDS_NUM 		: integer 	:= G_DATA_WORDSNUM;
			DA_WIDTH					: integer 	:= G_DA_WIDTH;
			CLK_CNT_WIDTH 		: integer 	:= 16;
			ITCM_INIT_FILE		: string	:= "C:\Users\oripa\Documents\Benchmark_Apps\test3\RV32IM\bin\M9K-intel\ITCM.hex";
			DTCM_INIT_FILE		: string	:= "C:\Users\oripa\Documents\Benchmark_Apps\test3\RV32IM\bin\M9K-intel\DTCM.hex"
		);
		PORT(
			--Inputs
			rst_i		 					:IN	STD_LOGIC;
			clk_i							:IN	STD_LOGIC;

			--Outputs (used also for Signal-Tap auxiliary pins)
			pc_o							:OUT	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
			instruction_o			:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

			RegWrite_ctrl_o		:OUT 	STD_LOGIC;
			MemWrite_ctrl_o		:OUT 	STD_LOGIC;
			Branch_ctrl_o			:OUT 	STD_LOGIC;

			read_data1_o 			:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			read_data2_o 			:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			write_data_o			:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

			alu_res_o 				:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			brTaken_o					:OUT 	STD_LOGIC;

			dtcm_addr_o				:OUT 	STD_LOGIC_VECTOR(DA_WIDTH-1 DOWNTO 0);
			dtcm_data_wr_o		:OUT 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			dtcm_data_rd_o		:OUT 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

			smclk_o						:OUT	STD_LOGIC;

			mclk_cnt_o				:OUT	STD_LOGIC_VECTOR(CLK_CNT_WIDTH-1 DOWNTO 0)
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
-- The PLL component declaration was removed with the ALTPLL it wrapped:
-- that is a Cyclone II megafunction and is unsupported on the Cyclone V of
-- the DE10-Standard. MCU.vhd derives MCLK from clk_i with a toggle
-- flip-flop instead. PLL.vhd has been deleted; it is in git history if
-- it is ever needed again.
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

end aux_package;


