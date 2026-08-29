----------------------------------------------------------------------------------
				Description of the source code test0.s:
----------------------------------------------------------------------------------
Output: PORT_LEDR[7-0], PORT_HEX0, PORT_HEX1, PORT_HEX2, PORT_HEX3, PORT_HEX4, PORT_HEX5
RESET:  Pushbutton KEY0

The program execution:
counting up by 1, shown separately onto all output devices
----------------------------------------------------------------------------------
				Description of the source code test1.s:
----------------------------------------------------------------------------------
Input:  PORT_SW[7-0] 
Output: PORT_LEDR[7-0], PORT_HEX0, PORT_HEX1, PORT_HEX2, PORT_HEX3, PORT_HEX4, PORT_HEX5
RESET:  Pushbutton KEY0

The program execution:
if SW=0x01 (other SW1-SW7 don't matter): counting up by 1,
	shown separately onto all output devices
	
if SW=0x02 (other SW2-SW7 don't matter): counting down by 1,
	shown separately onto all output devices
	
else, doing nothing (output state saved)
----------------------------------------------------------------------------------
				Description of the source code test2.s:
----------------------------------------------------------------------------------
Input:  PORT_SW[7-0] 
Output: PORT_LEDR[7-0], PORT_HEX0, PORT_HEX1, PORT_HEX2, PORT_HEX3, PORT_HEX4, PORT_HEX5
RESET:  Pushbutton KEY0

The program execution:
if SW=0x01 (other SW1-SW7 don't matter): counting up by 1,
	shown onto HEXs Array(HEX5-HEX0 as number of six digits)
	shown onto PORT_LEDR[7-0]
	
if SW=0x02 (other SW2-SW7 don't matter): counting down by 1,
	shown onto HEXs Array(HEX5-HEX0 as number of six digits)
	shown onto PORT_LEDR[7-0]
	
else, doing nothing (output state saved)
----------------------------------------------------------------------------------
