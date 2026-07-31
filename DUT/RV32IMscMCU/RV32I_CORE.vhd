--============================================================================
-- Copyright 2026 Hananya Ribo 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Top Level Structural Model for Single-Cycle RISC-V Core
--============================================================================ 
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
use ieee.std_logic_unsigned.all;
USE work.cond_compilation_package.all;
USE work.aux_package.all;


ENTITY RV32I_CORE IS
	generic( 
		WORD_GRANULARITY 	: boolean 	:= G_WORD_GRANULARITY;
	    MODELSIM 			: integer 	:= G_MODELSIM;
		DATA_BUS_WIDTH 		: integer 	:= 32;
		ITCM_ADDR_WIDTH 	: integer 	:= G_ADDRWIDTH;
		DTCM_ADDR_WIDTH 	: integer 	:= G_ADDRWIDTH;
		PC_WIDTH 			: integer 	:= G_PC_WIDTH;
		MA_WIDTH 			: integer 	:= G_MA_WIDTH;
		DATA_WORDS_NUM 		: integer 	:= G_DATA_WORDSNUM;
		CLK_CNT_WIDTH 		: integer 	:= 16
	);
	PORT(	
		--Inputs
		rst_i		 		:IN	STD_LOGIC;
		clk_i				:IN	STD_LOGIC;
		
		--Outputs (used also for Signal-Tap auxiliary pins)
		pc_o				:OUT	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
		instruction_o		:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
		
		RegWrite_ctrl_o		:OUT 	STD_LOGIC;
		MemWrite_ctrl_o		:OUT 	STD_LOGIC;
		Branch_ctrl_o		:OUT 	STD_LOGIC;
		
		read_data1_o 		:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
		read_data2_o 		:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
		write_data_o		:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
		
		alu_res_o 			:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);															
		brTaken_o			:OUT 	STD_LOGIC; 
		
		dtcm_addr_o			:OUT 	STD_LOGIC_VECTOR(DTCM_ADDR_WIDTH-1 DOWNTO 0);
		dtcm_data_wr_o		:OUT 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
		dtcm_data_rd_o		:OUT 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
		
		mclk_cnt_o			:OUT	STD_LOGIC_VECTOR(CLK_CNT_WIDTH-1 DOWNTO 0)
	);		
END RV32I_CORE;
--============================================================================
ARCHITECTURE structure OF RV32I_CORE IS
	-- declare signals used to connect VHDL components
	SIGNAL pc_w 			: STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
	SIGNAL pc_plus4_w 		: STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
	SIGNAL read_data1_w 	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL read_data2_w 	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL sign_extend_w 	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL addr_gen_w 		: STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
	SIGNAL alu_res_w 		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL dtcm_data_rd_w 	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL dtcm_addr_w 		: STD_LOGIC_VECTOR(DTCM_ADDR_WIDTH-1 DOWNTO 0);
	SIGNAL alu_src_w 		: STD_LOGIC;
	SIGNAL branch_w 		: STD_LOGIC;
	SIGNAL Jal_ctrl_w 		: STD_LOGIC;
	SIGNAL Jalr_ctrl_w 		: STD_LOGIC;
	SIGNAL reg_write_w 		: STD_LOGIC;
	SIGNAL reg_dst_w 		: STD_LOGIC;
	SIGNAL brTaken_w 		: STD_LOGIC;
	SIGNAL mem_write_w 		: STD_LOGIC;
	SIGNAL MemtoReg_w 		: STD_LOGIC;
	SIGNAL mem_read_w 		: STD_LOGIC;
	SIGNAL upper_im_w		: STD_LOGIC_VECTOR(1 DOWNTO 0);
	SIGNAL alu_op_w 		: STD_LOGIC_VECTOR(4 DOWNTO 0);
	SIGNAL instruction_w	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL mclk_w 			: STD_LOGIC;
	SIGNAL mclk_cnt_q		: STD_LOGIC_VECTOR(CLK_CNT_WIDTH-1 DOWNTO 0);
	
	SIGNAL mul_op_w			: STD_LOGIC;

BEGIN
	
	--=======================================
	-- PLL module connection
	--=======================================
	G0:
	if (MODELSIM = 0) generate
	  MCLK: PLL
		PORT MAP (
			inclk0 	=> clk_i,
			c0 		=> mclk_w
		);
	else generate
		mclk_w <= clk_i;
	end generate;
	--===========================================
	-- IFETCH (including ITCM) module connection
	--===========================================
	IFE : Ifetch
	generic map(
		WORD_GRANULARITY	=> 	WORD_GRANULARITY,
		DATA_BUS_WIDTH		=> 	DATA_BUS_WIDTH, 
		PC_WIDTH					=>	PC_WIDTH,
		ITCM_ADDR_WIDTH		=>	ITCM_ADDR_WIDTH,
		WORDS_NUM					=>	DATA_WORDS_NUM
	)
	PORT MAP (
		--Inputs
		clk_i 					=> mclk_w,  
		rst_i 					=> rst_i, 
		addr_gen_i 			=> addr_gen_w,
		Branch_ctrl_i 	=> branch_w,
		brTaken_i				=> brTaken_w,
		Jal_ctrl_i 			=> Jal_ctrl_w,
		Jalr_ctrl_i			=> Jalr_ctrl_w,
		alu_res_i				=> alu_res_w,
		
		--Outputs
		pc_o 						=> pc_w,
		pc_plus4_o	 		=> pc_plus4_w,
		instruction_o 	=> instruction_w    
	);
	--=======================================
	-- IDECODE module connection
	--=======================================
	ID : Idecode
	generic map(
		PC_WIDTH		=>	PC_WIDTH,
		DATA_BUS_WIDTH	=>  DATA_BUS_WIDTH
	)
	PORT MAP (	
		--Inputs
		clk_i 				=> mclk_w,  
		rst_i 				=> rst_i,
		pc_plus4_i	 		=> pc_plus4_w,
		instruction_i 		=> instruction_w,
		dtcm_data_rd_i 		=> dtcm_data_rd_w,
		alu_res_i 			=> alu_res_w,
		RegDst_ctrl_i		=> reg_dst_w,
		RegWrite_ctrl_i 	=> reg_write_w,
		MemtoReg_ctrl_i 	=> MemtoReg_w,
		
		--Outputs
		read_data1_o 		=> read_data1_w,
		read_data2_o 		=> read_data2_w,
		SignExt_o 			=> sign_extend_w	 
	);
	--=======================================
	-- CONTROL module connection
	--=======================================
	CTL:   control
	PORT MAP ( 	
		--Inputs
		instruction_i 		=> instruction_w,
		
		--Outputs
		RegDst_ctrl_o		=> reg_dst_w,
		ALUSrc_ctrl_o 		=> alu_src_w,
		MemtoReg_ctrl_o 	=> MemtoReg_w,
		RegWrite_ctrl_o 	=> reg_write_w,
		MemRead_ctrl_o 		=> mem_read_w,
		MemWrite_ctrl_o 	=> mem_write_w,
		Branch_ctrl_o 		=> branch_w,
		Jal_ctrl_o 			=> Jal_ctrl_w,
		Jalr_ctrl_o			=> Jalr_ctrl_w,
		UpperIm_ctrl_o 		=> upper_im_w,
		ALUOp_ctrl_o 		=> alu_op_w,
		MULOp_ctrl_o		=> mul_op_w
	);
	--=======================================
	-- EXECUTE module connection
	--=======================================
	EXE:  Execute
  generic map(
		DATA_BUS_WIDTH 	=> 	DATA_BUS_WIDTH,
		PC_WIDTH 		=>	PC_WIDTH
	)
	PORT MAP (	
		--Inputs
		read_data1_i 		=> read_data1_w,
		read_data2_i 		=> read_data2_w,
		sign_extend_i 		=> sign_extend_w,
		UpperIm_ctrl_i 		=> upper_im_w,
		ALUOp_ctrl_i 		=> alu_op_w,
		ALUSrc_ctrl_i 		=> alu_src_w,
		pc_i				=> pc_w,
		MULOp_ctrl_i		=> mul_op_w,
		
		--Outputs
		brTaken_o 			=> brTaken_w,
		alu_res_o			=> alu_res_w,
		addr_gen_o 			=> addr_gen_w			
	);
	--=======================================
	-- DTCM module connection
	--=======================================
	G1: 
	if (WORD_GRANULARITY = True) generate -- i.e. each WORD has a unike address
		dtcm_addr_w	<= alu_res_w(MA_WIDTH-1 DOWNTO 2); -- increment memory address by 4;
	elsif (WORD_GRANULARITY = False) generate -- i.e. each BYTE has a unike address
		dtcm_addr_w	<= alu_res_w(MA_WIDTH-1 DOWNTO 0);
	end generate;
	
	MEM:  dmemory
	generic map(
		DATA_BUS_WIDTH		=> 	DATA_BUS_WIDTH, 
		DTCM_ADDR_WIDTH		=> 	DTCM_ADDR_WIDTH,
		WORDS_NUM					=>	DATA_WORDS_NUM
	)
	PORT MAP (	
		--Inputs
		clk_i 				=> mclk_w,  
		rst_i 				=> rst_i,
		dtcm_addr_i 		=> dtcm_addr_w,
		dtcm_data_wr_i 		=> read_data2_w,
		MemRead_ctrl_i 		=> mem_read_w, 
		MemWrite_ctrl_i 	=> mem_write_w,
				
		--Outputs
		dtcm_data_rd_o 		=> dtcm_data_rd_w 
	);	
	
	--=======================================
	-- MCLK counter register connection
	--=======================================									
	process (mclk_w , rst_i)
	begin
		if rst_i = '1' then
			mclk_cnt_q	<=	(others	=> '0');
		elsif rising_edge(mclk_w) then
			mclk_cnt_q	<=	mclk_cnt_q + '1';
		end if;
	end process;
---------------------------------------------------------------------------------------
-- Copying out important signals only for Verification and FPGA Velidation(Signal-TAP)
---------------------------------------------------------------------------------------
	pc_o				<=	pc_w;									-- IFETCH output								
	instruction_o 		<= 	instruction_w;							-- IFETCH output
	
	RegWrite_ctrl_o 	<= 	reg_write_w;							-- CONTROL output
	MemWrite_ctrl_o 	<= 	mem_write_w;							-- CONTROL output
	Branch_ctrl_o 		<= 	branch_w;								-- CONTROL output
	  
	read_data1_o 		<= 	read_data1_w;							-- IDECODE output
	read_data2_o 		<= 	read_data2_w;							-- IDECODE output
	write_data_o  		<= 	dtcm_data_rd_w WHEN MemtoReg_w = '1' 
													ELSE alu_res_w; -- IDECODE input(Write-Back) 
	
	alu_res_o 			<= 	alu_res_w;								-- EXECUTE output			
	brTaken_o 			<= 	brTaken_w;								-- EXECUTE output
  
	dtcm_addr_o 		<= 	dtcm_addr_w;							-- DMEMORY input
	dtcm_data_wr_o 		<= 	read_data2_w;							-- DMEMORY input
	dtcm_data_rd_o		<=	dtcm_data_rd_w;							-- DMEMORY output
	
	mclk_cnt_o			<=	mclk_cnt_q;								-- TOP output
	
---------------------------------------------------------------------------------------

END structure;

