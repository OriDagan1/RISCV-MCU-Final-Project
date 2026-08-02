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
		CLK_CNT_WIDTH 		: integer 	:= 16;
		-- Benchmark images, overridable so switching application does not
		-- mean editing IFETCH/DMEMORY.
		ITCM_INIT_FILE		: string	:= "C:\Users\oripa\Documents\Benchmark_Apps\test3\RV32IM\bin\M9K-intel\ITCM.hex";
		DTCM_INIT_FILE		: string	:= "C:\Users\oripa\Documents\Benchmark_Apps\test3\RV32IM\bin\M9K-intel\DTCM.hex"
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
	SIGNAL divclk_w			: STD_LOGIC;
	SIGNAL mclk_q			: STD_LOGIC;
	SIGNAL mclk_cnt_q		: STD_LOGIC_VECTOR(CLK_CNT_WIDTH-1 DOWNTO 0);

	SIGNAL mul_op_w			: STD_LOGIC;

	-- Division accelerator
	CONSTANT ONES_DBUS		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0) := (OTHERS => '1');
	SIGNAL div_op_w			: STD_LOGIC;
	SIGNAL div_signed_w		: STD_LOGIC;
	SIGNAL div_rem_w		: STD_LOGIC;
	SIGNAL div_busy_w		: STD_LOGIC;
	SIGNAL div_a_neg_w		: STD_LOGIC;
	SIGNAL div_b_neg_w		: STD_LOGIC;
	SIGNAL div_by_zero_w	: STD_LOGIC;
	SIGNAL div_ain_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL div_bin_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL div_quot_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL div_rsdu_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL div_quot_fix_w	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL div_rsdu_fix_w	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL div_res_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

	-- Write enables after the multicycle stall has been applied
	SIGNAL reg_write_gated_w	: STD_LOGIC;
	SIGNAL mem_write_gated_w	: STD_LOGIC;

BEGIN

	--=======================================
	-- Clock generation
	--
	-- DIVCLK is the incoming board clock; MCLK is derived from it by a single
	-- toggle flip-flop, so the accelerator runs at twice the CPU rate. This
	-- replaces the supplied ALTPLL, which is a Cyclone II megafunction and is
	-- not supported on the Cyclone V of the DE10-Standard. The 2:1 ratio is
	-- the one the PLL was configured for (G_PLL_DIV=2, G_PLL_MUL=1), so the
	-- CPU sees the same clock it saw before.
	--
	-- TODO(Sprint 0): this block moves to MCU.vhd along with the DTCM, and
	-- the core then takes mclk and divclk as ports instead of deriving them.
	--=======================================
	divclk_w <= clk_i;

	CLKDIV:
	process (clk_i, rst_i)
	begin
		if rst_i = '1' then
			mclk_q	<= '0';
		elsif rising_edge(clk_i) then
			mclk_q	<= NOT mclk_q;
		end if;
	end process;

	mclk_w <= mclk_q;
	--===========================================
	-- IFETCH (including ITCM) module connection
	--===========================================
	IFE : Ifetch
	generic map(
		WORD_GRANULARITY	=> 	WORD_GRANULARITY,
		DATA_BUS_WIDTH		=> 	DATA_BUS_WIDTH, 
		PC_WIDTH					=>	PC_WIDTH,
		ITCM_ADDR_WIDTH		=>	ITCM_ADDR_WIDTH,
		WORDS_NUM					=>	DATA_WORDS_NUM,
		ITCM_INIT_FILE		=>	ITCM_INIT_FILE
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
		stall_i					=> div_busy_w,

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
		RegWrite_ctrl_i 	=> reg_write_gated_w,
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
		MULOp_ctrl_o		=> mul_op_w,
		DIVOp_ctrl_o		=> div_op_w,
		DIVSigned_ctrl_o	=> div_signed_w,
		DIVRem_ctrl_o		=> div_rem_w
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
		DIVOp_ctrl_i		=> div_op_w,
		div_res_i			=> div_res_w,

		--Outputs
		brTaken_o 			=> brTaken_w,
		alu_res_o			=> alu_res_w,
		addr_gen_o 			=> addr_gen_w			
	);
	--=======================================
	-- Division accelerator connection (Fig.1 "Accelerator", Fig.3)
	--=======================================
	-- RV32IM has four division instructions but the accelerator of Fig.9 is
	-- an unsigned machine, so the ISA-level sign handling lives here: the
	-- operands are reduced to magnitudes on the way in and the results are
	-- given their signs back on the way out. divu/remu bypass all of it.
	div_a_neg_w		<= div_signed_w AND read_data1_w(DATA_BUS_WIDTH-1);
	div_b_neg_w		<= div_signed_w AND read_data2_w(DATA_BUS_WIDTH-1);

	div_ain_w		<= (NOT read_data1_w) + 1	WHEN	div_a_neg_w = '1'	ELSE	read_data1_w;
	div_bin_w		<= (NOT read_data2_w) + 1	WHEN	div_b_neg_w = '1'	ELSE	read_data2_w;

	DIVA: div_accel
	generic map(
		N					=> DATA_BUS_WIDTH
	)
	PORT MAP (
		--Inputs
		mclk_i				=> mclk_w,
		rst_i				=> rst_i,
		Ain_i				=> div_ain_w,
		Bin_i				=> div_bin_w,
		div_op_i			=> div_op_w,
		divclk_i			=> divclk_w,

		--Outputs
		Quotient_o			=> div_quot_w,
		Residue_o			=> div_rsdu_w,
		div_busy_o			=> div_busy_w
	);

	-- Sign restore. The quotient is negative when exactly one operand was,
	-- and the remainder always takes the sign of the dividend. Division by
	-- zero is the one case the sign rule must not be applied to: RISC-V asks
	-- for a quotient of -1 whatever the dividend was, and all-ones is already
	-- what the unsigned accelerator produces. The remainder of a division by
	-- zero is the dividend, which the sign rule does restore correctly.
	div_by_zero_w	<= '1' WHEN read_data2_w = 0 ELSE '0';

	div_quot_fix_w	<=	ONES_DBUS					WHEN	div_by_zero_w = '1'					ELSE
						(NOT div_quot_w) + 1		WHEN	(div_a_neg_w XOR div_b_neg_w) = '1'	ELSE
						div_quot_w;

	div_rsdu_fix_w	<=	(NOT div_rsdu_w) + 1		WHEN	div_a_neg_w = '1'					ELSE
						div_rsdu_w;

	div_res_w		<=	div_rsdu_fix_w	WHEN	div_rem_w = '1'	ELSE	div_quot_fix_w;

	--=======================================
	-- Multicycle stall
	--=======================================
	-- The core is single-cycle, so a multicycle instruction is handled by
	-- freezing it in place: IFETCH stops advancing the PC, so the ITCM keeps
	-- re-presenting the same instruction and the register file keeps sourcing
	-- the same operands, while both write enables are held off so nothing is
	-- committed. div_busy_w is low again for the one cycle in which the
	-- write-back happens and the PC moves on.
	reg_write_gated_w	<= reg_write_w AND NOT div_busy_w;
	mem_write_gated_w	<= mem_write_w AND NOT div_busy_w;

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
		WORDS_NUM					=>	DATA_WORDS_NUM,
		DTCM_INIT_FILE		=>	DTCM_INIT_FILE
	)
	PORT MAP (	
		--Inputs
		clk_i 				=> mclk_w,  
		rst_i 				=> rst_i,
		dtcm_addr_i 		=> dtcm_addr_w,
		dtcm_data_wr_i 		=> read_data2_w,
		MemRead_ctrl_i 		=> mem_read_w,
		MemWrite_ctrl_i 	=> mem_write_gated_w,
				
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
	
	RegWrite_ctrl_o 	<= 	reg_write_gated_w;						-- CONTROL output, stall applied
	MemWrite_ctrl_o 	<= 	mem_write_gated_w;						-- CONTROL output, stall applied
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

