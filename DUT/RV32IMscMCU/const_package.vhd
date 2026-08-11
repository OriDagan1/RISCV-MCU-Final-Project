---------------------------------------------------------------------------------------------
-- Copyright 2025 Hananya Ribo 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
---------------------------------------------------------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;
USE work.cond_compilation_package.all;

package const_package is
--------------------------------------------------------------------
--	VECTOR EXTENTIONS constants
--------------------------------------------------------------------
	constant ZEROS_IMM12	:	STD_LOGIC_VECTOR(11 DOWNTO 0) := 12x"000";
	constant ZEROS_IMM20	:	STD_LOGIC_VECTOR(19 DOWNTO 0) := 20x"00000";
	constant ONES_IMM12	:	STD_LOGIC_VECTOR(11 DOWNTO 0) := 12x"FFF";
	constant ONES_IMM20	:	STD_LOGIC_VECTOR(19 DOWNTO 0) := 20x"FFFFF";
	
	constant ZEROS_DBUS2PCADDR	:	STD_LOGIC_VECTOR(DBUS_WIDTH-G_PC_WIDTH-1 DOWNTO 0) := (OTHERS => '0');
	
--------------------------------------------------------------------
--	IDECODE constants
--------------------------------------------------------------------
	constant RTYPE_OPC	:	STD_LOGIC_VECTOR(6 DOWNTO 0) := "0110011";
	constant ITYPE_OPC	:	STD_LOGIC_VECTOR(6 DOWNTO 0) := "0010011";
	-- Loads are I-type too, but they carry their own opcode. ITYPE_OPC above
	-- is OP-IMM (addi, andi, slti...) and does NOT match them.
	constant LTYPE_OPC	:	STD_LOGIC_VECTOR(6 DOWNTO 0) := "0000011";
	constant STYPE_OPC	:	STD_LOGIC_VECTOR(6 DOWNTO 0) := "0100011";
	constant SBTYPE_OPC	:	STD_LOGIC_VECTOR(6 DOWNTO 0) := "1100011";
	constant UTYPE_OPC	:	STD_LOGIC_VECTOR(6 DOWNTO 0) := "0010111" and "0110111";	--Upper immediate 
	constant UJTYPE_OPC	:	STD_LOGIC_VECTOR(6 DOWNTO 0) := "1101111";
--------------------------------------------------------------------
-- ALU Operations
--------------------------------------------------------------------
	constant ALU_NONE								:	STD_LOGIC_VECTOR(4 DOWNTO 0) :=	"00000";
	constant ALU_SHIFTL							:	STD_LOGIC_VECTOR(4 DOWNTO 0) :=	"00001";
	constant ALU_SHIFTR							:	STD_LOGIC_VECTOR(4 DOWNTO 0) :=	"00010";
	constant ALU_SHIFTR_ARITH				:	STD_LOGIC_VECTOR(4 DOWNTO 0) :=	"00011";
	constant ALU_ADD								:	STD_LOGIC_VECTOR(4 DOWNTO 0) :=	"00100";
	constant ALU_SUB								:	STD_LOGIC_VECTOR(4 DOWNTO 0) :=	"00110";
	constant ALU_AND								:	STD_LOGIC_VECTOR(4 DOWNTO 0) :=	"00111";
	constant ALU_OR									:	STD_LOGIC_VECTOR(4 DOWNTO 0) :=	"01000";
	constant ALU_XOR								:	STD_LOGIC_VECTOR(4 DOWNTO 0) :=	"01001";
	constant ALU_LESS_THAN_UNSIGNED	:	STD_LOGIC_VECTOR(4 DOWNTO 0) :=	"01010";
	constant ALU_LESS_THAN_SIGNED		:	STD_LOGIC_VECTOR(4 DOWNTO 0) :=	"01011";
	
	constant ALU_BEQ								:	STD_LOGIC_VECTOR(4 DOWNTO 0) :=	"10001";
	constant ALU_BNE								:	STD_LOGIC_VECTOR(4 DOWNTO 0) :=	"10010";
	constant ALU_BLT								:	STD_LOGIC_VECTOR(4 DOWNTO 0) :=	"10011";
	constant ALU_BGE								:	STD_LOGIC_VECTOR(4 DOWNTO 0) :=	"10100";
	constant ALU_BLTU								:	STD_LOGIC_VECTOR(4 DOWNTO 0) :=	"10101";
	constant ALU_BGEU								:	STD_LOGIC_VECTOR(4 DOWNTO 0) :=	"10110";

--------------------------------------------------------------------
-- Instructions Masks
--------------------------------------------------------------------	
-- andi
 constant INST_ANDI						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"7013";
 constant INST_ANDI_MASK			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- addi
 constant INST_ADDI						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"13";
 constant INST_ADDI_MASK			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- slti
 constant INST_SLTI 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"2013";
 constant INST_SLTI_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- sltiu
 constant INST_SLTIU 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"3013";
 constant INST_SLTIU_MASK 		:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- ori
 constant INST_ORI 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"6013";
 constant INST_ORI_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- xori
 constant INST_XORI 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"4013";
 constant INST_XORI_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- slli
 constant INST_SLLI 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"1013";
 constant INST_SLLI_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fc00707f";

-- srli
 constant INST_SRLI 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"5013";
 constant INST_SRLI_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fc00707f";

-- srai
 constant INST_SRAI 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"40005013";
 constant INST_SRAI_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fc00707f";

-- lui
 constant INST_LUI 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"37";
 constant INST_LUI_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"7f";

-- auipc
 constant INST_AUIPC 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"17";
 constant INST_AUIPC_MASK 		:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"7f";

-- add
 constant INST_ADD 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"33";
 constant INST_ADD_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fe00707f";

-- sub
 constant INST_SUB 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"40000033";
 constant INST_SUB_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fe00707f";

-- slt
 constant INST_SLT 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"2033";
 constant INST_SLT_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fe00707f";

-- sltu
 constant INST_SLTU 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"3033";
 constant INST_SLTU_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fe00707f";

-- xor
 constant INST_XOR 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"4033";
 constant INST_XOR_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fe00707f";

-- or
 constant INST_OR 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"6033";
 constant INST_OR_MASK 				:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fe00707f";

-- and
 constant INST_AND 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"7033";
 constant INST_AND_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fe00707f";

-- sll
 constant INST_SLL 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"1033";
 constant INST_SLL_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fe00707f";

-- srl
 constant INST_SRL 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"5033";
 constant INST_SRL_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fe00707f";

-- sra
 constant INST_SRA 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"40005033";
 constant INST_SRA_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fe00707f";

-- jal
 constant INST_JAL 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"6f";
 constant INST_JAL_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"7f";

-- jalr
 constant INST_JALR 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"67";
 constant INST_JALR_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- beq
 constant INST_BEQ 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"63";
 constant INST_BEQ_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- bne
 constant INST_BNE 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"1063";
 constant INST_BNE_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- blt
 constant INST_BLT 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"4063";
 constant INST_BLT_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- bge
 constant INST_BGE 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"5063";
 constant INST_BGE_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- bltu
 constant INST_BLTU 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"6063";
 constant INST_BLTU_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- bgeu
 constant INST_BGEU 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"7063";
 constant INST_BGEU_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- lb
 constant INST_LB 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"3";
 constant INST_LB_MASK 				:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- lh
 constant INST_LH 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"1003";
 constant INST_LH_MASK 				:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- lw
 constant INST_LW 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"2003";
 constant INST_LW_MASK 				:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- lbu
 constant INST_LBU 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"4003";
 constant INST_LBU_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- lhu
 constant INST_LHU 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"5003";
 constant INST_LHU_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- lwu
 constant INST_LWU 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"6003";
 constant INST_LWU_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- sb
 constant INST_SB 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"23";
 constant INST_SB_MASK 				:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- sh
 constant INST_SH 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"1023";
 constant INST_SH_MASK 				:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- sw
 constant INST_SW 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"2023";
 constant INST_SW_MASK 				:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- ecall
 constant INST_ECALL 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"73";
 constant INST_ECALL_MASK 		:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"ffffffff";

-- ebreak
 constant INST_EBREAK 				:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"100073";
 constant INST_EBREAK_MASK 		:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"ffffffff";

-- eret
 constant INST_ERET 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"200073";
 constant INST_ERET_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"cfffffff";

-- csrrw
 constant INST_CSRRW 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"1073";
 constant INST_CSRRW_MASK 		:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- csrrs
 constant INST_CSRRS 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"2073";
 constant INST_CSRRS_MASK 		:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- csrrc
 constant INST_CSRRC 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"3073";
 constant INST_CSRRC_MASK 		:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- csrrwi
 constant INST_CSRRWI 				:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"5073";
 constant INST_CSRRWI_MASK 		:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- csrrsi
 constant INST_CSRRSI 				:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"6073";
 constant INST_CSRRSI_MASK 		:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- csrrci
 constant INST_CSRRCI 				:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"7073";
 constant INST_CSRRCI_MASK 		:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- mul
 constant INST_MUL 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"2000033";
 constant INST_MUL_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fe00707f";

-- mulh
 constant INST_MULH 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"2001033";
 constant INST_MULH_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fe00707f";

-- mulhsu
 constant INST_MULHSU 				:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"2002033";
 constant INST_MULHSU_MASK 		:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fe00707f";

-- mulhu
 constant INST_MULHU 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"2003033";
 constant INST_MULHU_MASK 		:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fe00707f";

-- div
 constant INST_DIV 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"2004033";
 constant INST_DIV_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fe00707f";

-- divu
 constant INST_DIVU 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"2005033";
 constant INST_DIVU_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fe00707f";

-- rem
 constant INST_REM 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"2006033";
 constant INST_REM_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fe00707f";

-- remu
 constant INST_REMU 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"2007033";
 constant INST_REMU_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fe00707f";

-- wfi
 constant INST_WFI 						:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"10500073";
 constant INST_WFI_MASK 			:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"ffff8fff";

-- fence
 constant INST_FENCE 					:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"f";
 constant INST_FENCE_MASK 		:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

-- sfence
 constant INST_SFENCE 				:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"12000073";
 constant INST_SFENCE_MASK 		:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"fe007fff";

-- fence.i
 constant INST_IFENCE 				:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"100f";
 constant INST_IFENCE_MASK 		:	STD_LOGIC_VECTOR(31 DOWNTO 0) := 32x"707f";

----------------------------------------------------------------------------------	
end const_package;

