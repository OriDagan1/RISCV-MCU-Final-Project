--============================================================================
-- Copyright 2026 Hananya Ribo 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Top Level Structural Model for Single-Cycle RISC-V Core
-- Idecode module (implements the register file for the MIPS computer
--============================================================================ 
LIBRARY IEEE; 		
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;
USE work.const_package.all;


ENTITY Idecode IS
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
END Idecode;


ARCHITECTURE behavior OF Idecode IS
TYPE register_file IS ARRAY (0 TO 31) OF STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

	SIGNAL RF_q							: register_file;
	SIGNAL write_data_w			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	
	SIGNAL opc_w						: STD_LOGIC_VECTOR(6 DOWNTO 0);
	SIGNAL rs1_w						: STD_LOGIC_VECTOR(4 DOWNTO 0);
	SIGNAL rs2_w						: STD_LOGIC_VECTOR(4 DOWNTO 0);
	SIGNAL rd_w							: STD_LOGIC_VECTOR(4 DOWNTO 0);
	
	SIGNAL Iimm_w						: STD_LOGIC_VECTOR(11 DOWNTO 0);
	SIGNAL Simm_w						: STD_LOGIC_VECTOR(11 DOWNTO 0);
	SIGNAL SBimm_w					: STD_LOGIC_VECTOR(11 DOWNTO 0);
	SIGNAL Uimm_w						: STD_LOGIC_VECTOR(19 DOWNTO 0);
	SIGNAL UJimm_w					: STD_LOGIC_VECTOR(19 DOWNTO 0);
	
	SIGNAL SignExt_Iimm_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL SignExt_Simm_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL SignExt_SBimm_w	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL SignExt_Uimm_w		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL SignExt_UJimm_w	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

BEGIN
	opc_w		<= instruction_i(6 DOWNTO 0); 
	
	rs1_w		<= instruction_i(19 DOWNTO 15);
  rs2_w		<= instruction_i(24 DOWNTO 20);
  rd_w		<= instruction_i(11 DOWNTO 7);
	
  Iimm_w 	<= instruction_i(31 DOWNTO 20);
	Simm_w 	<= instruction_i(31 DOWNTO 25) & instruction_i(11 DOWNTO 7);
	SBimm_w <= instruction_i(31) & instruction_i(7) & instruction_i(30 DOWNTO 25) & instruction_i(11 DOWNTO 8);
	Uimm_w 	<= instruction_i(31 DOWNTO 12);
	UJimm_w <= instruction_i(31) & instruction_i(19 DOWNTO 12) & instruction_i(20) & instruction_i(30 DOWNTO 21);
	
	-- Read the Register 1 output of the Register-File
	read_data1_o <= RF_q(CONV_INTEGER(rs1_w));
	
	-- Read the Register 2 output of the Register-File		 
	read_data2_o <= RF_q(CONV_INTEGER(rs2_w));
	
	-- Mux to bypass data memory for Rformat instructions
	write_data_w <= ZEROS_DBUS2PCADDR & pc_plus4_i				WHEN	RegDst_ctrl_i				ELSE
									alu_res_i(DATA_BUS_WIDTH-1 DOWNTO 0) 	WHEN	not MemtoReg_ctrl_i ELSE 
									dtcm_data_rd_i;
	
	-- Sign Extend 16-bits to 32-bits
  SignExt_Iimm_w 	<=	ZEROS_IMM20 & Iimm_w 	WHEN	not Iimm_w(11) 	ELSE ONES_IMM20 & Iimm_w;
	SignExt_Simm_w 	<=	ZEROS_IMM20	& Simm_w 	WHEN 	not Simm_w(11)	ELSE ONES_IMM20 & Simm_w;
	SignExt_SBimm_w <=	ZEROS_IMM20	& SBimm_w WHEN 	not SBimm_w(11)	ELSE ONES_IMM20 & SBimm_w;
	SignExt_Uimm_w 	<=	ZEROS_IMM12 & Uimm_w 	WHEN 	not Uimm_w(19) 	ELSE ONES_IMM12 & Uimm_w;
	SignExt_UJimm_w	<=	ZEROS_IMM12 & UJimm_w WHEN 	not UJimm_w(19) ELSE ONES_IMM12 & UJimm_w;

	
	-- UTYPE_OPC is "0010111" and "0110111" = "0010111", which is the opcode of
	-- auipc alone. lui is "0110111" and needs its own choice here, otherwise it
	-- falls through to the others branch and every lui yields zero.
	with	opc_w select
		SignExt_o <=	SignExt_Iimm_w														when ITYPE_OPC,
									SignExt_Iimm_w														when INST_JALR(6 DOWNTO 0),
									SignExt_Simm_w														when STYPE_OPC,
									SignExt_SBimm_w 													when SBTYPE_OPC,
									SignExt_Uimm_w(19 DOWNTO 0) & ZEROS_IMM12	when UTYPE_OPC,
									SignExt_Uimm_w(19 DOWNTO 0) & ZEROS_IMM12	when INST_LUI(6 DOWNTO 0),
									SignExt_UJimm_w														when UJTYPE_OPC,
									(others => '0')														when others;
	--==============================================================================
	--	Register-File(RF) structure
	--==============================================================================
	process(clk_i,rst_i)
	begin
		if (rst_i='1') then
			FOR i IN 0 TO 31 LOOP
				RF_q(i) <= CONV_STD_LOGIC_VECTOR(0,32);
			END LOOP;
		elsif (clk_i'event and clk_i='1') then
			if (RegWrite_ctrl_i = '1' AND rd_w /= 0) then	-- RF(0) hard-wired of value zero
				RF_q(CONV_INTEGER(rd_w)) <= write_data_w;
				-- index type is integer so we must use conv_integer for type casting
			end if;
		end if;
	end process;

END behavior;





