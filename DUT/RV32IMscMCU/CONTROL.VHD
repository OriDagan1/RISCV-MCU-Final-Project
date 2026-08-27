--============================================================================
-- Copyright 2026 Hananya Ribo 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Control-Unit module
--============================================================================ 
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_SIGNED.ALL;
USE work.const_package.all;


ENTITY control IS
	generic(
		DATA_BUS_WIDTH	: integer	:= 32;
		PC_WIDTH		: integer	:= 10;
		DA_WIDTH		: integer	:= 14
	);
  PORT(
		--Inputs
		instruction_i 		: IN 	STD_LOGIC_VECTOR(31 DOWNTO 0);

		--Inputs, interrupt service protocol (clause 6.v, page 15)
		clk_i				: IN	STD_LOGIC;
		rst_i				: IN	STD_LOGIC;
		intr_i				: IN	STD_LOGIC;										-- from the interrupt controller
		div_busy_i			: IN	STD_LOGIC;										-- entry is blocked while a division is in flight
		gp_i				: IN	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);	-- x3 from IDECODE, bit 0 is GIE
		int_ret_addr_i		: IN	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);			-- from IFETCH, sampled at the start of cycle 1
		bus_rdata_i			: IN	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);	-- TYPE in cycle 1, Mem[TYPE] in cycle 2

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
		DIVRem_ctrl_o		: OUT	STD_LOGIC;	-- rem/remu (write back the residue)

		--Outputs, interrupt service protocol (clause 6.v, page 15)
		inta_n_o			: OUT	STD_LOGIC;								-- ACTIVE LOW, idles at '1'
		int_hold_o			: OUT	STD_LOGIC;								-- freeze the PC and the write-back, cycle 1 and cycle 2
		int_addr_we_o		: OUT	STD_LOGIC;								-- drive int_addr_o onto the data address bus (cycle 2)
		int_addr_o			: OUT	STD_LOGIC_VECTOR(DA_WIDTH-1 DOWNTO 0);	-- TYPE, captured in cycle 1, zero-extended
		int_mem_read_o		: OUT	STD_LOGIC;								-- emulate the load of Mem[TYPE] (cycle 2)
		int_pc_we_o			: OUT	STD_LOGIC;								-- load the PC with int_pc_o (cycle 2)
		int_pc_o			: OUT	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);	-- Mem[TYPE], the ISR entry address
		int_rf_we_o			: OUT	STD_LOGIC;								-- the hardware register-file write port
		int_rf_rd_o			: OUT	STD_LOGIC_VECTOR(4 DOWNTO 0);			-- gp (x3) or tp (x4), by state
		int_rf_data_o		: OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0)
	);
END control;


ARCHITECTURE behavior OF control IS

	SIGNAL	Rtype_w, Itype_w, Stype_w, SBtype_w, Utype_w, UJtype_w 								: STD_LOGIC;
	SIGNAL	lb_w, lh_w, lw_w, lbu_w, lhu_w, lwu_w, ld_w, sb_w, sh_w, sw_w, st_w					: STD_LOGIC;
	SIGNAL	beq_w, bne_w, blt_w, bge_w, bltu_w, bgeu_w, branch_w, jal_w, jalr_w 				: STD_LOGIC;
	SIGNAL	add_w, addi_w, and_w, andi_w, or_w, ori_w, sll_w, slli_w, sra_w, srai_w, mul_w		: STD_LOGIC;  -- New mul_w signal
	SIGNAL	srl_w, srli_w, sub_w, xor_w, xori_w, auipc_w, lui_w, slt_w, slti_w, sltu_w, sltiu_w	: STD_LOGIC;
	SIGNAL	div_w, divu_w, rem_w, remu_w, divop_w												: STD_LOGIC;  -- New division signals
	SIGNAL  opc_w : STD_LOGIC_VECTOR(6 DOWNTO 0);

	--=======================================
	-- Interrupt service protocol (clause 6.v, page 15)
	--=======================================
	-- Three states cover the whole protocol: idle, and the two cycles of
	-- "CPU services an interrupt request (latency of two cycles)". Returning
	-- from an interrupt is not a state - "reti" is an ordinary jalr, decoded
	-- below, and its GIE write rides alongside the jump the rest of the core
	-- already performs for any jalr.
	TYPE INT_STATE_TYPE IS (S_IDLE, S_CYCLE1, S_CYCLE2);
	SIGNAL int_state_q		: INT_STATE_TYPE;

	-- Dedicated registers, page 15's own words: TYPE "capturing it in a
	-- dedicated register" (cycle 1), and the return address "captured...
	-- at the start of cycle 1" so it is not whatever the PC has become once
	-- the hold has taken effect.
	SIGNAL type_reg_q		: STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL ret_addr_reg_q	: STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);

	-- x3 (gp) and x4 (tp), the two hardware write-port destinations this
	-- machine ever uses.
	CONSTANT GP_REG			: STD_LOGIC_VECTOR(4 DOWNTO 0) := "00011";
	CONSTANT TP_REG			: STD_LOGIC_VECTOR(4 DOWNTO 0) := "00100";

	-- "jalr zero, 0(tp)" - rd=x0, rs1=x4, imm=0 - fully specified, so the
	-- mask is all ones, the same convention const_package uses for ecall,
	-- ebreak and eret. Kept local rather than added to const_package: reti
	-- is a hardware side effect of an ordinary instruction, not a new
	-- opcode, and it has exactly one user.
	CONSTANT INST_RETI			: STD_LOGIC_VECTOR(31 DOWNTO 0) := x"00020067";
	CONSTANT INST_RETI_MASK	: STD_LOGIC_VECTOR(31 DOWNTO 0) := x"FFFFFFFF";
	SIGNAL reti_w				: STD_LOGIC;

	SIGNAL gp_clear_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);	-- gp with GIE cleared, cycle 1
	SIGNAL gp_set_w			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);	-- gp with GIE set, reti
	SIGNAL ret_ext_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);	-- ret_addr_reg_q, zero-extended for tp
	SIGNAL type_ext_w		: STD_LOGIC_VECTOR(DA_WIDTH-1 DOWNTO 0);		-- type_reg_q, zero-extended for the address bus

BEGIN
	opc_w 		<=	instruction_i(6 DOWNTO 0);
	-- Code to generate control signals using opcode bits
	Rtype_w		<=  '1'	WHEN	opc_w = RTYPE_OPC  										ELSE 	'0';
	Itype_w		<=  '1'	WHEN	(opc_w = ITYPE_OPC) or (ld_w = '1') or (jalr_w = '1') 	ELSE 	'0';
	Stype_w 	<=  '1'	WHEN	opc_w = STYPE_OPC  										ELSE 	'0';
	SBtype_w 	<=  '1'	WHEN	opc_w = SBTYPE_OPC 										ELSE 	'0';
	Utype_w 	<=  '1'	WHEN	((opc_w and UTYPE_OPC) = UTYPE_OPC)  					ELSE	'0';
	UJtype_w 	<=  '1'	WHEN	opc_w = UJTYPE_OPC 										ELSE 	'0';

	lb_w		<=	'1'	WHEN	(instruction_i and INST_LB_MASK) = INST_LB				ELSE 	'0';	--lb		
	lh_w		<=	'1'	WHEN	(instruction_i and INST_LH_MASK) = INST_LH				ELSE 	'0';	--lh
	lw_w		<=	'1'	WHEN	(instruction_i and INST_LW_MASK) = INST_LW				ELSE 	'0';	--lw
	lbu_w		<=	'1'	WHEN	(instruction_i and INST_LBU_MASK) = INST_LBU			ELSE	'0';	--lbu
	lhu_w		<=	'1'	WHEN	(instruction_i and INST_LHU_MASK) = INST_LHU			ELSE	'0';	--lhu
	lwu_w		<=	'1'	WHEN	(instruction_i and INST_LWU_MASK) = INST_LWU			ELSE	'0';	--lwu
	
	ld_w 		<=	'1' WHEN 	lb_w or lh_w or lw_w or lbu_w or lhu_w or lwu_w			ELSE	'0';	--Load      

	sb_w		<=	'1'	WHEN	(instruction_i and INST_SB_MASK) = INST_SB				ELSE	'0';	--sb
	sh_w		<=	'1'	WHEN	(instruction_i and INST_SH_MASK) = INST_SH				ELSE	'0';	--sh
	sw_w		<=	'1'	WHEN	(instruction_i and INST_SW_MASK) = INST_SW				ELSE	'0';	--sw																																						               
	
	st_w		<=	'1'	WHEN	sb_w or sh_w or sw_w									ELSE	'0';	--Store   	

	beq_w		<=	'1'	WHEN	(instruction_i and INST_BEQ_MASK) = INST_BEQ			ELSE	'0';	--beq												
	bne_w		<=	'1'	WHEN	(instruction_i and INST_BNE_MASK) = INST_BNE			ELSE	'0';	--bne
	blt_w		<=	'1'	WHEN	(instruction_i and INST_BLT_MASK) = INST_BLT			ELSE	'0';	--blt
	bge_w		<=	'1'	WHEN	(instruction_i and INST_BGE_MASK) = INST_BGE			ELSE	'0';	--bge
	bltu_w		<=	'1'	WHEN	(instruction_i and INST_BLTU_MASK) = INST_BLTU			ELSE	'0';	--bltu
	bgeu_w		<=	'1'	WHEN	(instruction_i and INST_BGEU_MASK) = INST_BGEU			ELSE	'0';	--bgeu
	
	branch_w	<=	'1'	WHEN	beq_w or bne_w or blt_w or bge_w or bltu_w or bgeu_w	ELSE	'0';	--Branch     	
	
	jal_w		<=	'1'	WHEN	(instruction_i and INST_JAL_MASK) = INST_JAL			ELSE 	'0';	--jal	

	jalr_w		<=	'1'	WHEN	(instruction_i and INST_JALR_MASK) = INST_JALR			ELSE 	'0';	--jalr
	
	add_w		<=	'1' WHEN	(instruction_i and INST_ADD_MASK) = INST_ADD			ELSE	'0';	--add	
	
	addi_w		<=	'1' WHEN	(instruction_i and INST_ADDI_MASK) = INST_ADDI			ELSE	'0';	--addi
	
	auipc_w		<=	'1' WHEN	(instruction_i and INST_AUIPC_MASK) = INST_AUIPC		ELSE	'0';	--auipc
	
	lui_w		<=	'1' WHEN	(instruction_i and INST_LUI_MASK) = INST_LUI			ELSE	'0';	--lui
	
	and_w		<=	'1' WHEN	(instruction_i and INST_AND_MASK) = INST_AND			ELSE	'0';	--and
	
	andi_w		<=	'1' WHEN	(instruction_i and INST_ANDI_MASK) = INST_ANDI			ELSE	'0';	--andi
	
	or_w		<=	'1' WHEN	(instruction_i and INST_OR_MASK) = INST_OR				ELSE	'0';	--or
	
	ori_w		<=	'1' WHEN	(instruction_i and INST_ORI_MASK) = INST_ORI			ELSE	'0';	--ori
	
	sll_w		<=	'1' WHEN	(instruction_i and INST_SLL_MASK) = INST_SLL			ELSE	'0';	--sll
	
	slli_w 		<=	'1' WHEN	(instruction_i and INST_SLLI_MASK) = INST_SLLI			ELSE	'0';	--slli
	
	sra_w 		<=	'1' WHEN	(instruction_i and INST_SRA_MASK) = INST_SRA			ELSE	'0';	-- sra
	
	srai_w 		<=	'1' WHEN	(instruction_i and INST_SRAI_MASK) = INST_SRAI			ELSE	'0';	-- srai
	
	srl_w 		<=	'1' WHEN	(instruction_i and INST_SRL_MASK) = INST_SRL			ELSE	'0';	-- srl
	
	srli_w 		<=	'1' WHEN	(instruction_i and INST_SRLI_MASK) = INST_SRLI			ELSE	'0';	-- srli
	
	sub_w 		<=	'1' WHEN	(instruction_i and INST_SUB_MASK) = INST_SUB			ELSE	'0';	-- sub
	
	xor_w 		<=	'1' WHEN	(instruction_i and INST_XOR_MASK) = INST_XOR			ELSE	'0';	-- xor
	
	xori_w 		<=	'1' WHEN	(instruction_i and INST_XORI_MASK) = INST_XORI			ELSE	'0';	-- xori
	
	slt_w 		<=	'1' WHEN	(instruction_i and INST_SLT_MASK) = INST_SLT			ELSE	'0';	-- slt
	
	slti_w 		<=	'1' WHEN	(instruction_i and INST_SLTI_MASK) = INST_SLTI			ELSE	'0';	-- slti
	
	sltu_w 		<=	'1' WHEN	(instruction_i and INST_SLTU_MASK) = INST_SLTU			ELSE	'0';	-- sltu
	
	sltiu_w 	<=	'1' WHEN	(instruction_i and INST_SLTIU_MASK) = INST_SLTIU		ELSE	'0';	-- sltiu
	
	mul_w		<=  '1' WHEN 	(instruction_i and INST_MUL_MASK) = INST_MUL			ELSE	'0';	-- mul

	div_w		<=  '1' WHEN 	(instruction_i and INST_DIV_MASK) = INST_DIV			ELSE	'0';	-- div

	divu_w		<=  '1' WHEN 	(instruction_i and INST_DIVU_MASK) = INST_DIVU			ELSE	'0';	-- divu

	rem_w		<=  '1' WHEN 	(instruction_i and INST_REM_MASK) = INST_REM			ELSE	'0';	-- rem

	remu_w		<=  '1' WHEN 	(instruction_i and INST_REMU_MASK) = INST_REMU			ELSE	'0';	-- remu

	-- All four share opcode RTYPE and funct7=0000001, so they are already
	-- covered by Rtype_w for RegWrite/ALUSrc. ALUOp_ctrl_o falls through to
	-- ALU_NONE for them and the accelerator result replaces the ALU result.
	divop_w		<=	div_w or divu_w or rem_w or remu_w;								--Division


	RegWrite_ctrl_o 	<=  Rtype_w or Itype_w or Utype_w or UJtype_w;
	MemtoReg_ctrl_o 	<=  ld_w;
	MemWrite_ctrl_o 	<=  st_w; 
	MemRead_ctrl_o 		<=  ld_w;
	Branch_ctrl_o     	<=	branch_w;
	Jal_ctrl_o			<=	jal_w; 
	Jalr_ctrl_o			<=	jalr_w;  
	RegDst_ctrl_o		<=	jal_w or jalr_w;
	ALUSrc_ctrl_o  		<=  Itype_w or Stype_w or Utype_w or UJtype_w;
	MULOp_ctrl_o		<=  mul_w;
	DIVOp_ctrl_o		<=	divop_w;
	DIVSigned_ctrl_o	<=	div_w or rem_w;
	DIVRem_ctrl_o		<=	rem_w or remu_w;

	UpperIm_ctrl_o		<=	"01" 	WHEN 	auipc_w 	ELSE
							"10" 	WHEN	lui_w		ELSE
							"00";
		  						      		
	ALUOp_ctrl_o	<=  ALU_ADD					WHEN	add_w or addi_w or auipc_w or lui_w or jal_w or jalr_w or ld_w or st_w 	ELSE																																																				
												
						ALU_AND					WHEN	and_w or andi_w															ELSE																			
																			
						ALU_OR					WHEN	or_w or ori_w															ELSE
																										
						ALU_SHIFTL				WHEN	sll_w or slli_w															ELSE																					
																					
						ALU_SHIFTR_ARITH		WHEN	sra_w or srai_w															ELSE 																									
																								
						ALU_SHIFTR				WHEN	srl_w or srli_w															ELSE																					
												
						ALU_SUB					WHEN	sub_w																	ELSE	
			
						ALU_XOR					WHEN	xor_w or xori_w															ELSE 	
																																						
						ALU_LESS_THAN_SIGNED	WHEN	slt_w or slti_w 														ELSE
																																																				
						ALU_LESS_THAN_UNSIGNED	WHEN	sltu_w or sltiu_w														ELSE																						
																						
						ALU_BEQ					WHEN	beq_w																	ELSE
												
						ALU_BNE					WHEN	bne_w																	ELSE
												
						ALU_BLT					WHEN	blt_w																	ELSE
												
						ALU_BGE					WHEN	bge_w																	ELSE
												
						ALU_BLTU				WHEN	bltu_w																	ELSE
												
						ALU_BGEU				WHEN	bgeu_w																	ELSE
												
						ALU_NONE;

	--=======================================
	-- Interrupt service protocol - state machine (clause 6.v, page 15)
	--=======================================
	-- Rising edge, matching every other sequential element already in this
	-- core (pc_q, pc_plus4_q, the register file, mclk_cnt_q). The bus values
	-- this machine samples - TYPE in cycle 1, Mem[TYPE] in cycle 2 - are
	-- combinational results of the CURRENT state and are settled well before
	-- the next rising edge, exactly like an ordinary load's dtcm_data_rd_i.
	--
	-- Entry is a Moore transition out of S_IDLE only: "at the next clock
	-- cycle after INTR is set to '1', INTA is set to '0'" is exactly what a
	-- registered state and a combinational inta_n_o give for free - INTA
	-- cannot fall until the state register itself has moved to S_CYCLE1.
	-- div_busy_i in the entry condition is the divider-in-flight guard: a
	-- service entry started mid-division would lose the pending write-back.
	-- intr_i is a level (INT_CTRL.vhd: intr_o <= gie_i WHEN ifg_w /= 0),
	-- not a pulse, so a rise-then-fall inside one MCLK period is not an
	-- event this synchronous design can observe or needs to: only the value
	-- present at the sampling edge decides entry, same as every other input
	-- this core reads synchronously.
	--
	-- The idle-state decoder outputs above are untouched by any of this -
	-- they depend only on instruction_i, never on int_state_q - which is
	-- what keeps the benchmark at 134 cycles while gie_w is tied to '0' in
	-- MCU.vhd and int_state_q can therefore never leave S_IDLE.
	PROCESS (clk_i, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			int_state_q		<= S_IDLE;
			type_reg_q		<= (OTHERS => '0');
			ret_addr_reg_q	<= (OTHERS => '0');
		ELSIF (clk_i'EVENT AND clk_i = '1') THEN
			CASE int_state_q IS
				WHEN S_IDLE =>
					IF intr_i = '1' AND div_busy_i = '0' THEN
						-- "the next PC address" at the moment the service
						-- process begins - captured now, at the start of
						-- cycle 1, before int_hold_o can freeze IFETCH's
						-- own next_pc_normal_w at some other value.
						ret_addr_reg_q	<= int_ret_addr_i;
						int_state_q		<= S_CYCLE1;
					END IF;

				WHEN S_CYCLE1 =>
					-- "capturing it in a dedicated register" - bus_rdata_i
					-- carries TYPE throughout cycle 1 because inta_n_o is
					-- low, which is what makes INT_CTRL.vhd drive it without
					-- being addressed. Captured on the way out of cycle 1.
					type_reg_q	<= bus_rdata_i(7 DOWNTO 0);
					int_state_q	<= S_CYCLE2;

				WHEN S_CYCLE2 =>
					-- One cycle only - "latency of two cycles" total.
					int_state_q	<= S_IDLE;
			END CASE;
		END IF;
	END PROCESS;

	--=======================================
	-- reti decode - not a state, an ordinary instruction
	--=======================================
	-- "jalr zero, 0(tp)" already executes as a normal jalr through the rest
	-- of the core (Jalr_ctrl_o, RegDst_ctrl_o, ALUOp ADD above); this adds
	-- only the GIE=1 side effect page 15 asks for, gated to S_IDLE so a
	-- coincidentally reti-shaped instruction frozen during the hold can
	-- never be mistaken for a real return.
	reti_w	<= '1' WHEN (instruction_i AND INST_RETI_MASK) = INST_RETI ELSE '0';

	--=======================================
	-- Hardware write port - x3 (gp) in cycle 1 and on reti, x4 (tp) in cycle 2
	--=======================================
	gp_clear_w	<= gp_i(DATA_BUS_WIDTH-1 DOWNTO 1) & '0';	-- GIE := 0, cycle 1
	gp_set_w	<= gp_i(DATA_BUS_WIDTH-1 DOWNTO 1) & '1';	-- GIE := 1, reti

	ret_ext_w(DATA_BUS_WIDTH-1 DOWNTO PC_WIDTH)	<= (OTHERS => '0');
	ret_ext_w(PC_WIDTH-1 DOWNTO 0)					<= ret_addr_reg_q;

	int_rf_we_o		<=	'1'	WHEN	(int_state_q = S_CYCLE1) OR (int_state_q = S_CYCLE2)
								OR (int_state_q = S_IDLE AND reti_w = '1')	ELSE	'0';

	int_rf_rd_o		<=	TP_REG	WHEN	int_state_q = S_CYCLE2	ELSE	GP_REG;	-- cycle 1 and reti both target gp

	int_rf_data_o	<=	ret_ext_w	WHEN	int_state_q = S_CYCLE2	ELSE
						gp_clear_w	WHEN	int_state_q = S_CYCLE1	ELSE
						gp_set_w;	-- idle + reti_w='1'; don't-care otherwise, gated by int_rf_we_o

	--=======================================
	-- Cycle 2 - emulated load of Mem[TYPE], and the PC injection
	--=======================================
	type_ext_w(DA_WIDTH-1 DOWNTO 8)	<= (OTHERS => '0');
	type_ext_w(7 DOWNTO 0)				<= type_reg_q;

	int_addr_we_o	<= '1' WHEN int_state_q = S_CYCLE2 ELSE '0';
	int_addr_o		<= type_ext_w;
	int_mem_read_o	<= '1' WHEN int_state_q = S_CYCLE2 ELSE '0';

	int_pc_we_o		<= '1' WHEN int_state_q = S_CYCLE2 ELSE '0';
	int_pc_o		<= bus_rdata_i(PC_WIDTH-1 DOWNTO 0);	-- Mem[TYPE], valid once int_addr_we_o has settled the DTCM read

	--=======================================
	-- INTA and the hold
	--=======================================
	inta_n_o	<= '0' WHEN int_state_q = S_CYCLE1 ELSE '1';
	int_hold_o	<= '1' WHEN (int_state_q = S_CYCLE1) OR (int_state_q = S_CYCLE2) ELSE '0';

END behavior;


