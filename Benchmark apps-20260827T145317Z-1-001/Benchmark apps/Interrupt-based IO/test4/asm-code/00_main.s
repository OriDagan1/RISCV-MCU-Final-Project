.include "io_map.s"
.eqv	SIZE 10
#--------------------------------------------------------------
#							 						Data Segment
#--------------------------------------------------------------
.data 
IV:		# Start of Interrupt Vector Table
	.word main            
	.word UartRX_ISR
	.word UartRX_ISR
	.word UartTX_ISR
	.word BT_ISR
	.word KEY1_ISR
	.word KEY2_ISR
	.word KEY3_ISR


state:	.word 	0							# state-based FSM kernel
  
arr1: .word  81,82,83,84,85,86,87,88,89,90
arr2: .word  11,12,13,14,15,16,17,18,19,20

divarr: .space 40  					# SIZE*4=10*4=40 - DIV result array
remarr: .space 40  					# SIZE*4=10*4=40 - REM result array
runtime_div:	.word	0
runtime_rem:	.word	0
#--------------------------------------------------------------
#							 						Code Segment
#--------------------------------------------------------------	
.text
main:
	call intr_config
	
	la	t3,state
	sw  zero,0(t3)								# state=STATE0
	mv	fp,zero										# sync of fp and state
	
	la 	a1, arr1									# a1 is a pointer to array arr1
	la 	a2, arr2									# a2 is a pointer to array arr2
	li 	a3, SIZE									# a3=SIZE (arrays size)
	la 	a4, divarr								# a4 is a pointer to array divarr
	la 	a5, remarr								# a5 is a pointer to array remarr
					
	li  a0,0
	call print2HEXsArr						# clear the HEXs array {HEX5,HEX4,HEX3,HEX2,HEX1,HEX0}
	
	ori  gp,gp,0x01    						# EINT, GIE=gp[0]=1


STATE0:													# STATE0 is an idle state
	li	t0,0
	bne fp,t0,STATE1
	nop														

			
STATE1:
	li	t0,1
	bne fp,t0,STATE2
	
	andi t4,a7,3								# t4=a7&3 is used as a global value	
	li 	 t6,BTCMPR0

if_l:	
	li	 t2,0
	bne  t4,t2,elif1_l
	li 	 t0,SEC_PERIOD
	sw   t0,0(t6)									# if(t4 == 0) bt_interrupt_period=1sec
elif1_l:
	li	 t2,1
	bne  t4,t2,elif2_l
	li 	 t0,SEC_PERIOD						
	srli t0,t0,1
	sw   t0,0(t6)									# elseif(t4 == 1) bt_interrupt_period=0.5sec
elif2_l:
	li	 t2,2
	bne  t4,t2,elif3_l
	li 	 t0,SEC_PERIOD						
	srli t0,t0,2
	sw   t0,0(t6)									# elseif(t4 == 2) bt_interrupt_period=0.25sec
elif3_l:
	li	 t2,3
	bne  t4,t2,endif_l
	li 	 t0,SEC_PERIOD						
	srli t0,t0,3
	sw   t0,0(t6)									# elseif(t4 == 3) bt_interrupt_period=0.125sec
endif_l:
	mv   fp,zero									# goto idle state
	
		
STATE2: 
	li	t0,2
	bne fp,t0,STATE3
	mv  fp,zero									  # goto idle state


STATE3: 
	li	t0,3
	bne fp,t0,END
	
	andi t4,a7,1									# t4=a7&1 is used as a global value
if_l4:	
	bne  t4,zero,elif_l4
	la 	 a6, runtime_div					# if(t4 == 0) mesure runtime_div
	call capture_init
	call div_arrays
	call capture
	mv   fp,zero									# goto idle state
	j		 END
elif_l4:	
	la 	 a6, runtime_rem					# if(t4 == 1) mesure runtime_rem
	call capture_init
	call rem_arrays
	call capture
	mv   fp,zero									# goto idle state

END:	
	j	STATE0		    							# infinite loop
#==============================================================
#							 						ISRs section
#==============================================================	
KEY1_ISR:
	# set state=STATE1 (three instructions)
	li		t2,1
	la		t3,state
	sw  	t2,0(t3)								# state=1
	mv		fp,t2										# sync of fp and state
	
	call bt_cmp_config
	addi a7,a7,1									# a7++ (used as a global value)
	
	# clr KEY1IFG bit (five instructions)
	li		t2,IFG		
	lw  	t3,0(t2) 								# read the IFG register
	li		t5,KEY1IFG_MASK
	and 	t3,t3,t5 								# update the IFG register
	sw   	t3,0(t2) 								# clr KEY1IFG
	reti 													# return from interrupt 

	
KEY2_ISR:
	# set state=STATE2 (three instructions)
	li		t2,2
	la		t3,state
	sw  	t2,0(t3)								# state=2
	mv		fp,t2										# sync of fp and state
	
	call bt_outcmp_config
	addi a7,a7,1									# a7++ (used as a global value)
	
	# clr KEY2IFG bit (five instructions)	
	li		t2,IFG		
	lw  	t3,0(t2) 								# read the IFG register
	li		t5,KEY2IFG_MASK
	and 	t3,t3,t5								# update the IFG register
	sw   	t3,0(t2) 								# clr KEY2IFG
	reti 													# return from interrupt 


KEY3_ISR:
	# set state=STATE3 (three instructions)
	li		t2,3
	la		t3,state
	sw  	t2,0(t3)								# state=3
	mv		fp,t2										# sync of fp and state
	
	call bt_capture_config
	addi a7,a7,1									# a7++ (used as a global value)
	
	# clr KEY3IFG bit (five instructions)	
	li		t2,IFG		
	lw  	t3,0(t2) 								# read the IFG register
	li		t5,KEY3IFG_MASK
	and 	t3,t3,t5								# update the IFG register 
	sw   	t3,0(t2) 								# clr KEY3IFG
	reti 													# return from interrupt 
	
	
BT_ISR:
	la		t3,state
	lw  	t2,0(t3)								# restore the current state
	
if_l2:	
	li	  t3,1								  
	bne   t2,t3,elif1_l2
	addi  a0,a0,1  								# if(state == STATE1) a0=a0+1
	call  print2HEXsArr						# print the value of a0 onto the HEXs array {HEX5,HEX4,HEX3,HEX2,HEX1,HEX0}
elif1_l2:
	li	  t3,3
	bne   t2,t3,endif_l2
	li	  t2,BTCAPR		
	lw    t1,0(t2) 								 
	sw    t1,0(a6)									# if(state == STATE3) MEM[a6]=BTCAPR									
endif_l2:		
	reti 													# return from interrupt 
 	
	    
UartRX_ISR:	
	reti 													# return from interrupt 


UartTX_ISR:	
	reti 													# return from interrupt        
         
