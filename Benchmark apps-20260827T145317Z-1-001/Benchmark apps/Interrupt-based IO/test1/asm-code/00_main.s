.include "io_map.s"
.eqv	SIZE 8
.eqv	short_delay	4						# used for ModelSim based verification
.eqv	long_delay 	0xB71B00		# used for FPGA based validation
.eqv 	SW0_MASK		0x01
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


state: .word 	0							# state-based FSM kernel    
	
arr1: .word  100,98,97,96,95,94,93,92
arr2: .word  8,7,6,5,4,3,2,1

#--------------------------------------------------------------
#							 						Code Segment
#--------------------------------------------------------------	
.text
main:
	la	t3,state
	sw  zero,0(t3)								# state=STATE0
	mv	fp,zero										# sync of fp and state

	li 	s9, SIZE
	la 	a1, arr1									
	mv  s10, a1										# s10 is the arr1_ptr
	la 	a2, arr2									
	mv  s11, a2										# s11 is the arr2_ptr
	mv  t4, zero									# t4 is the loop iterator
	
	li 	 t0,BTHOLD_BTSSEL3_BTCLR
  li   t6,BTCTL1
	sw   t0,0(t6)       					# BTCTL1=(BTHOLD=1,BTSSEL=3,BTCLR=1)
	
	li   t6,IE
	sw   zero,0(t6)        				# IE=0
	
	li   t6,IFG	
	sw   zero,0(t6)        				# IFG=0
	
	li 	 t0,BTSSEL3
	li   t6,BTCTL1  
	sw   t0,0(t6)       					# BTCTL1=(BTHOLD=0, BTSSEL=3)
			
	li   t6,PORT_SW
	lw   t0,0(t6)       					# read the state of PORT_SW
	
	li 	 t0,KEY3IE_KEY2IE_KEY1IE  					
	li   t6,IE 
	sw   t0,0(t6)									# KEY3IE_KEY2IE_KEY1IE are enabled       		
						
	li  a0,0
	call print2HEX10Arr						# clear HEX1,HEX0
	call print2HEX32Arr						# clear HEX3,HEX2
	call print2HEX54Arr						# clear HEX5,HEX4
	call print2LEDsArr						# clear LEDR[7-0]
	
	lw   t1,PORT_SW 							# read the state of PORT_SW[7-0]
	andi t1,t1,SW0_MASK
	bne  t1,zero,if_l   					# if SW0='1' jump to if_l
	li	 a3, short_delay					# a3 is the cycles delay argument
	j		 STATE1
if_l:
	li 	 a3, long_delay						# a3 is the cycles delay argument
	
	ori  gp,gp,0x01    						# EINT, GIE=gp[0]=1 


STATE0:													# idle state
	li	t0,0
	bne fp,t0,STATE1
	nop

											
STATE1:
	li	t0,1
	bne fp,t0,STATE2
	lw	a0,0(s10)
	call print2HEX54Arr
	mv  fp,zero									  # goto idle state

	
STATE2: 
	li	t0,2
	bne fp,t0,STATE3
	lw	a0,0(s11)
	call print2HEX32Arr
	mv  fp,zero									  # goto idle state
	
		
STATE3: 
	li	t0,3
	bne fp,t0,END
	lw	t6,0(s10)
	mv  a0,t6
	call print2HEX54Arr						# print arr1[i]
	lw	t2,0(s11)
	mv  a0,t2
	call print2HEX32Arr						# print arr2[i]
	div a0,t6,t2
	call print2HEX10Arr
	rem  a0,t6,t2
	call print2LEDsArr
	
	blt	 t4,s9,if1
	mv   t4,zero									# initialization of the array iterator 
	mv   s10,a1										# initialization of arr1_ptr
	mv   s11,a2										# initialization of arr2_ptr
	mv   fp,zero									# goto idle state
	j    END	
if1:	
	addi s10,s10,4								# arr1_ptr++
	addi s11,s11,4								# arr2_ptr++
	addi t4,t4,1									# iterator incrementation
	call delay
		
END:	
	j	STATE0		    						# infinite loop
#==============================================================
#							 						ISRs section
#==============================================================	
KEY1_ISR:
	li		t2,1
	la		t3,state
	sw  	t2,0(t3)								# state=1
	mv		fp,t2										# sync of fp and state
		
	li		t2,IFG		
	lw  	t3,0(t2) 								# read IFG
	li		t5,KEY1IFG_MASK
	and 	t3,t3,t5 
	sw   	t3,0(t2) 								# clr KEY1IFG	
	reti 													# return from interrupt

	
KEY2_ISR:
	li		t2,2
	la		t3,state
	sw  	t2,0(t3)								# state=2
	mv		fp,t2										# sync of fp and state
		
	li		t2,IFG		
	lw  	t3,0(t2) 								# read IFG
	li		t5,KEY2IFG_MASK
	and 	t3,t3,t5 
	sw   	t3,0(t2) 								# clr KEY2IFG	
	reti 													# return from interrupt


KEY3_ISR:
	li		t2,3
	la		t3,state
	sw  	t2,0(t3)								# state=3
	mv		fp,t2										# sync of fp and state
		
	li		t2,IFG		
	lw  	t3,0(t2) 								# read IFG
	li		t5,KEY3IFG_MASK
	and 	t3,t3,t5 
	sw   	t3,0(t2) 								# clr KEY3IFG	
	reti 													# return from interrupt  
	
	
BT_ISR:	
	reti 													# return from interrupt  
	    
UartRX_ISR:	
	reti 													# return from interrupt  

UartTX_ISR:	
	reti 													# return from interrupt     
         
