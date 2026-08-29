=======================================================================================
					Description of the application test1:
=======================================================================================
Input:  KEY3, KEY2, KEY1, SW0
Output: PORT_HEX0,PORT_HEX1,PORT_HEX2,PORT_HEX3,PORT_HEX4,PORT_HEX5,PORT_LEDR
RESET:  KEY0
----------------------------------------------------------------------------------------
On RESET:
--------
*)clear (turn off) the six HEXs and red LEDRs[7-0]
*)set the value of delay cycles of the delay routine (SW0=0: short delay, SW0=1: long delay)   

On KEY1 pushing:
---------------
The FSM's state1 is chosen:
*)print onto HEX5,HEX4 the value of arr1[i]
*)goto idle state 

On KEY2 pushing:
---------------
The FSM's state2 is chosen:
*)print onto HEX3,HEX2 the value of arr2[i]
*)goto idle state 

On KEY3 pushing:
---------------
The FSM's state3 is chosen(periodic of SIZE):
*)print onto HEX5,HEX4 the value of arr1[i]
*)print onto HEX3,HEX2 the value of arr2[i]
*)print onto HEX1,HEX0 the qoutient value of arr1[i]/arr2[i]
*)print onto LEDRs[7-0] the reminder value of arr1[i]%arr2[i]
*)i=(i<SIZE)?i+1 :0
*)delay
*)if(i==SIZE) goto idle state  
========================================================================================
					Description of the source code test2:
========================================================================================
Input:  KEY3, KEY2, KEY1
Output: PORT_HEX0,PORT_HEX1,PORT_HEX2,PORT_HEX3,PORT_HEX4,PORT_HEX5,PORT_LEDR
RESET:  KEY0
----------------------------------------------------------------------------------------
On RESET:
--------
The FSM's state0 is chosen

On KEY1 pushing:
---------------
The FSM's state1 is chosen:
*)print onto HEX1,HEX0 the value of a0
*)goto idle state 

On KEY2 pushing:
---------------
The FSM's state2 is chosen:
*)print onto HEX3,HEX2 the value of a0
*)goto idle state   

On KEY3 pushing:
---------------
The FSM's state3 is chosen:
*)print onto HEX5,HEX4 the value of a0
*)goto idle state 

On every BT interrupt-interval of 1sec (value of 0x002625A0 is for SMCLK=20MHz):
-------------------------------------------------------------------------------
a0=a0+1

Notes:
*)the BT timer source clock is SMCLK/8
*)SMCLK=20MHz is only an example:
	Your SMCLK should be MCLK=SMCLK or MCLK=k*SMCLK (k is an integer) depends the design critical-path constraint,
	when the application behavior accordingly 
========================================================================================
					Description of the source code test3:
========================================================================================
Input:  KEY3, KEY2, KEY1
Output: PORT_HEX0,PORT_HEX1,PORT_HEX2,PORT_HEX3,PORT_HEX4,PORT_HEX5,PORT_LEDR
RESET:  KEY0
----------------------------------------------------------------------------------------
On RESET:
--------
*)Set the interrupt-interval to 1sec(BTCMPR0=0x002625A0, timer_source = SMCLK/8, SMCLK=20MHz)
*)The FSM's state0 is chosen 
	

On KEY1 pushing:
---------------
*)Set the interrupt-interval to 0.5sec(BTCMPR0=0x002625A0/2, timer_source = SMCLK/8, SMCLK=20MHz)
*)The FSM's state1 is chosen:
	print onto HEX1,HEX0 the value of a0
	print onto LEDRs[7-0] the value of a0
*)goto idle state 

On KEY2 pushing:
---------------
*)Set the interrupt-interval to 0.25sec(BTCMPR0=0x002625A0/4, timer_source = SMCLK/8, SMCLK=20MHz)
*)The FSM's state2 is chosen:
	print onto HEX3,HEX2 the value of a0
	print onto LEDRs[7-0] the value of a0
*)goto idle state 

On KEY3 pushing:
---------------
*)Set the interrupt-interval to 0.125sec(BTCMPR0=0x002625A0/8, timer_source = SMCLK/8, SMCLK=20MHz)
*)The FSM's state3 is chosen:
	print onto HEX5,HEX4 the value of a0
	print onto LEDRs[7-0] the value of a0
*)goto idle state 

On every BT interrupt-interval:
------------------------------
a0=a0+1

Note:
*)SMCLK=20MHz is only an example:
	Your SMCLK should be MCLK=SMCLK or MCLK=k*SMCLK (k is an integer) depends the design critical-path constraint,
	when the application behavior accordingly
=====================================================================================
										Description of the source code test4:
=====================================================================================
Input:  KEY3, KEY2, KEY1
Output: PORT_HEX0,PORT_HEX1,PORT_HEX2,PORT_HEX3,PORT_HEX4,PORT_HEX5,PORT_LEDR,PWM_PIN
RESET:  KEY0
--------------------------------------------------------------------------------------
On RESET:
--------
clear all HEXs

On KEY1 pushing:
---------------
*)The BT timer is configured to compare mode
*)The interrupt interval is updated in a row for each KEY1 pushing from values 1sec,0.5sec,0.25sec,0.125sec  
*)For every interval value: a0=a0+1; print onto HEXsArr the value of a0
*)goto idle state 

On KEY2 pushing:
---------------
*)The BT timer is configured to output compare mode, PWM output signal=5kHZ
*)The PWM output signal duty-cycle is updated in a row for each KEY2 pushing from values 50%,75%,87.5%,93.75%
*)goto idle state 


On KEY3 pushing:
---------------
*)The BT timer is configured to input capture mode
*)Time measurement of a function:
	- On even KEY3 pushing:
		The application measures the runtime of two arrays division element by element
	-	On odd KEY3 pushing:
		The application measures the runtime of two arrays modulu element by element
*)goto idle state

Note:
*)SMCLK=20MHz is only an example:
	Your SMCLK should be MCLK=SMCLK or MCLK=k*SMCLK (k is an integer) depends the design critical-path constraint,
	when the application behavior accordingly									
