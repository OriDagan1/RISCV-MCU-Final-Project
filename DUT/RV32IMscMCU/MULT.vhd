LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;

entity multiplier is
	port(
		Ain : in std_logic_vector(15 downto 0);
		Bin : in std_logic_vector(15 downto 0);
		
		Res : out std_logic_vector(31 downto 0)
	);
end multiplier;

architecture mult of multiplier is

	signal A_low, A_high 	: std_logic_vector(7 downto 0);
	signal B_low, B_high 	: std_logic_vector(7 downto 0);
	
	signal P0, P1, P2, P3 	: std_logic_vector(15 downto 0);
	signal M 				: std_logic_vector(16 downto 0);
	
	signal P0_ext			: std_logic_vector(31 downto 0);
	signal M_shifted		: std_logic_vector(31 downto 0);
	signal P3_shifted		: std_logic_vector(31 downto 0);
	
begin
	
	-- Extract the high and low 8-bit chunks from the 16-bit inputs
    A_low  <= Ain(7 downto 0);
    A_high <= Ain(15 downto 8);
    B_low  <= Bin(7 downto 0);
    B_high <= Bin(15 downto 8);
	
	-- Stage 1
	P0 <= A_low * B_low;
    P1 <= A_low * B_high;
    P2 <= A_high * B_low;
    P3 <= A_high * B_high;
	
	-- Stage 2
	M <= ("0" & P1) + ("0" & P2);
	
	P0_ext 		<= x"0000" & P0; 						-- P0 zero extended to 32 bits
	M_shifted 	<= "0000000" & M & x"00";		-- M shifted left by 8
	P3_shifted 	<= P3 & x"0000";						-- P3 shifted left by 16
	
	Res <= P0_ext + M_shifted + P3_shifted;

end mult;

