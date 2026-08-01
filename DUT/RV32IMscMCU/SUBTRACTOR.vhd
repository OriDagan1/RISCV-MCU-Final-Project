--============================================================================
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- SUBTRACTOR module - unsigned N-bit subtractor with borrow detection.
-- Combinational building block of the multicycle division accelerator (Fig.9)
--
--   Res     = Y - X   (meaningful only when Non_neg = '1')
--   Non_neg = '1' when Y >= X, i.e. the subtraction produced no borrow
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;


ENTITY subtractor IS
	generic(
		N : positive := 32
	);
	PORT(
		--Inputs
		X 		: IN 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
		Y		: IN 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);

		--Outputs
		Res 	: OUT 	STD_LOGIC_VECTOR(N-1 DOWNTO 0);
		Non_neg	: OUT 	STD_LOGIC
	);
END subtractor;


ARCHITECTURE sub OF subtractor IS
	-- One extra bit so the borrow out of the MSB is captured instead of lost
	SIGNAL diff_w : UNSIGNED(N DOWNTO 0);

BEGIN
	diff_w	<= resize(unsigned(Y), N+1) - resize(unsigned(X), N+1);

	Res		<= STD_LOGIC_VECTOR(diff_w(N-1 DOWNTO 0));
	Non_neg	<= NOT diff_w(N);	-- borrow='1' => Y < X => result is negative

END sub;
