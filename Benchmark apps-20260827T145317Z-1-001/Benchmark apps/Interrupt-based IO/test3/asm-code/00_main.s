.include "io_map.s"
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


	state: 	.word 	0							# state-based FSM kernel    
	N:			.word 	0xB71B00

#--------------------------------------------------------------
#							 						Code Segment
#--------------------------------------------------------------	
.text
main:
	call sys_init

	la	t3,state
	sw  zero,0(t3)								# state=STATE0
	mv	fp,zero										# sync of fp and state
	
	ori  gp,gp,0x01    						# EINT, GIE=gp[0]=1 

		
STATE0:													# idle state
	li	 t0,0
	bne  fp,t0,STATE1
	nop

			
STATE1:
	li	 t0,1
	bne  fp,t0,STATE2
	call print2HEX10Arr
	call print2LEDsArr
	mv   fp,zero									  # goto idle state

	
STATE2: 
	li	 t0,2
	bne  fp,t0,STATE3
	call print2HEX32Arr
	call print2LEDsArr
	mv   fp,zero									  # goto idle state

	
STATE3: 
	li	 t0,3
	bne  fp,t0,END
	call print2HEX54Arr
	call print2LEDsArr
	mv   fp,zero									  # goto idle state


END:	
	j	STATE0		    								# infinite loop
#==============================================================
#							 						ISRs section
#==============================================================	
KEY1_ISR:
	li		t2,1
	la		t3,state
	sw  	t2,0(t3)								# state=1
	mv		fp,t2										# sync of fp and state
	
	li 	 t0,SEC_PERIOD						
	srli t0,t0,1
	li 	 t6,BTCMPR0
	sw   t0,0(t6)									# interrupt period of 0.5sec
		
	li		t2,IFG		
	lw  	t3,0(t2) 								# read the IFG register
	li		t5,KEY1IFG_MASK
	and 	t3,t3,t5 								# update the IFG register
	sw   	t3,0(t2) 								# clr KEY1IFG
	reti 													# return from interrupt 

	
KEY2_ISR:
	li		t2,2
	la		t3,state
	sw  	t2,0(t3)								# state=2
	mv		fp,t2										# sync of fp and state
	
	li 	 t0,SEC_PERIOD						
	srli t0,t0,2
	li 	 t6,BTCMPR0
	sw   t0,0(t6)									# interrupt period of 0.25sec
		
	li		t2,IFG		
	lw  	t3,0(t2) 								# read the IFG register
	li		t5,KEY2IFG_MASK
	and 	t3,t3,t5								# update the IFG register
	sw   	t3,0(t2) 								# clr KEY2IFG	
	reti 													# return from interrupt 


KEY3_ISR:
	li		t2,3
	la		t3,state
	sw  	t2,0(t3)								# state=3
	mv		fp,t2										# sync of fp and state
	
	li 	 t0,SEC_PERIOD						
	srli t0,t0,3
	li 	 t6,BTCMPR0
	sw   t0,0(t6)									# interrupt period of 0.125sec
		
	li		t2,IFG		
	lw  	t3,0(t2) 								# read the IFG register
	li		t5,KEY3IFG_MASK
	and 	t3,t3,t5								# update the IFG register 
	sw   	t3,0(t2) 								# clr KEY3IFG
	reti 													# return from interrupt 
	
	
BT_ISR:	
	addi  a0,a0,1  								# a0=a0+1
	
	la		t3,state
	lw  	t2,0(t3)								# restore the current state
	mv		fp,t2										# sync of fp and the current state
	reti 													# return from interrupt 

	    
UartRX_ISR:	
	reti 													# return from interrupt 

UartTX_ISR:	
	reti 													# return from interrupt        
         
