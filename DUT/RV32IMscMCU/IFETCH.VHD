--============================================================================
-- Copyright 2026 Hananya Ribo 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Top Level Structural Model for Single-Cycle RISC-V Core
-- IFETCH module provides the PC and the ITCM of the RISC-V core)
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;
LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;


ENTITY Ifetch IS
	generic(
		WORD_GRANULARITY 	: boolean	:= False;
		DATA_BUS_WIDTH 		: integer	:= 32;
		PC_WIDTH 			: integer	:= 10;
		ITCM_ADDR_WIDTH 	: integer	:= 8;
		WORDS_NUM 			: integer	:= 256;
		-- Benchmark image. Override from the testbench (or with vsim -g) so
		-- switching application does not mean editing this file.
		ITCM_INIT_FILE		: string	:= "C:\Users\oripa\Documents\Benchmark_Apps\test3\RV32IM\bin\M9K-intel\ITCM.hex"
	);
	PORT(
		--Inputs
		clk_i			: IN 	STD_LOGIC;
		rst_i 			: IN 	STD_LOGIC;
		addr_gen_i 		: IN 	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
		Branch_ctrl_i	: IN 	STD_LOGIC;
		brTaken_i 		: IN 	STD_LOGIC;
		Jal_ctrl_i		: IN 	STD_LOGIC;
		Jalr_ctrl_i		: IN 	STD_LOGIC;
		alu_res_i 		: IN 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
		stall_i			: IN 	STD_LOGIC;	-- hold the current instruction (multicycle accelerator busy)

		--Outputs
		pc_o 			: OUT	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
		pc_plus4_o 		: OUT	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
		instruction_o 	: OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0)
	);
END Ifetch;


ARCHITECTURE behavior OF Ifetch IS
	SIGNAL pc_q				: STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
	SIGNAL pc_plus4_q		: STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
	SIGNAL pc_plus4_r 		: STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
	SIGNAL itcm_addr_w		: STD_LOGIC_VECTOR(ITCM_ADDR_WIDTH-1 DOWNTO 0);
	SIGNAL next_pc_w  		: STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
	SIGNAL brTaken_w  		: STD_LOGIC;
	SIGNAL rst_q  			: STD_LOGIC;
	
BEGIN
	--=======================================
	-- ITCM (ROM) connection
	--=======================================
	inst_memory: altsyncram
	GENERIC MAP (
		operation_mode					=> "ROM",
		width_a 						=> DATA_BUS_WIDTH,
		widthad_a 						=> ITCM_ADDR_WIDTH,
		numwords_a 						=> WORDS_NUM,
		lpm_hint 						=> "ENABLE_RUNTIME_MOD = YES,INSTANCE_NAME = ITCM",
		lpm_type 						=> "altsyncram",
		outdata_reg_a 					=> "UNREGISTERED",
		init_file 						=> ITCM_INIT_FILE,
		intended_device_family			=> "Cyclone"
	)
	PORT MAP (
		clock0    	=> clk_i,
		address_a	=> itcm_addr_w, 
		q_a 	   	=> instruction_o 
	);
-------------------------------------------------------------------------------------
-- rst_i synchronization
-------------------------------------------------------------------------------------
PROCESS (clk_i, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			rst_q <= '1';	-- preset
		ELSIF(clk_i'EVENT  AND clk_i='1') THEN
			rst_q <= rst_i;
		END IF;
END PROCESS;

-----------------------------------------------------------------------------------		
	-- Adder to execute PC+4
  pc_plus4_r(PC_WIDTH-1 DOWNTO 0)	<= next_pc_w(PC_WIDTH-1 DOWNTO 0) + 4;
	
-----------------------------------------------------------------------------------
	-- Decision MUX for the next PC value
	brTaken_w <= 	Branch_ctrl_i AND brTaken_i;
	
	-- Stalling re-drives the address of the instruction that is already being
	-- executed, so the ITCM re-reads it and pc_q keeps its value. pc_plus4_q
	-- follows automatically, since it is loaded with next_pc_w+4 every cycle.
	next_pc_w	<=				(others => '0') 					WHEN	rst_q 								ELSE
								pc_q(PC_WIDTH-1 DOWNTO 0)			WHEN	stall_i = '1'						ELSE	-- case of accelerator stall
								alu_res_i(PC_WIDTH-1 DOWNTO 0)		WHEN	Jalr_ctrl_i							ELSE	-- case of jalr
								addr_gen_i(PC_WIDTH-1 DOWNTO 0)		WHEN	brTaken_w or Jal_ctrl_i 			ELSE	-- case of Branch Taken or jal
								pc_plus4_q(PC_WIDTH-1 DOWNTO 0);														-- case of Branch Not-Taken
-----------------------------------------------------------------------------------
-- pc_plus4 register
-------------------------------------------------------------------------------------
PROCESS (clk_i, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			pc_plus4_q(PC_WIDTH-1 DOWNTO 0) <= (OTHERS => '0') ; 
		ELSIF(clk_i'EVENT  AND clk_i='1') THEN
			pc_plus4_q(PC_WIDTH-1 DOWNTO 0) <= pc_plus4_r;	
		END IF;
END PROCESS;

-----------------------------------------------------------------------------------
-- pc register
-------------------------------------------------------------------------------------
PROCESS (clk_i, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			pc_q(PC_WIDTH-1 DOWNTO 0) <= (OTHERS => '0') ; 
		ELSIF(clk_i'EVENT  AND clk_i='1') THEN
			pc_q(PC_WIDTH-1 DOWNTO 0) <= next_pc_w;	
		END IF;
END PROCESS;
-----------------------------------------------------------------------------------	
	-- send address to inst. memory address register
	G1: 
	if (WORD_GRANULARITY = True) generate 			-- i.e. each WORD has unike address
		itcm_addr_w <= next_pc_w(PC_WIDTH-1 DOWNTO 2);
	elsif (WORD_GRANULARITY = False) generate 	-- i.e. each BYTE has unike address
		itcm_addr_w <= next_pc_w;
	end generate;
---------------------------------------------------------------------------------------
	pc_o 		<= 	pc_q;
	pc_plus4_o	<= 	pc_plus4_q;	
---------------------------------------------------------------------------------------
	
END behavior;


