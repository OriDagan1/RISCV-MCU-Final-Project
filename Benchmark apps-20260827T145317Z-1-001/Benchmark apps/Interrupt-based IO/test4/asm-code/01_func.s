.include "io_map.s"
.global print2HEXsArr
.global print2LEDsArr
.global intr_config
.global bt_cmp_config
.global bt_outcmp_config
.global bt_capture_config
.global capture_init
.global capture
.global div_arrays
.global rem_arrays
#============================================================
#												Auxiliary Functions
#============================================================
.text

#-----------------------------------------------------------------
#	Function: print the value of a0 onto LEDR[7-0]
# arguments: a0
# return value: none
#-----------------------------------------------------------------
print2LEDsArr:						# a0 is the function argument
	li	 s2,PORT_LEDR	 
	sw   a0,0(s2) 					# write to PORT_LEDR[7-0]

	ret
#-----------------------------------------------------------------
#	Function: print the value of a0 onto HEX5,HEX4,HEX3,HEX2,HEX1,HEX0
# arguments: a0
# return value: none
#-----------------------------------------------------------------	
print2HEXsArr:
	li	 s2,PORT_HEX0
	andi s1,a0,0x0000000F
	sw   s1,0(s2) 					# write to PORT_HEX0
	
	li	 s2,PORT_HEX1
	andi s1,a0,0x000000F0
	srli s1,s1,4
	sw   s1,0(s2) 					# write to PORT_HEX1
	
	li	 s2,PORT_HEX2
	li	 s1,0x00000F00
	and  s1,a0,s1
	srli s1,s1,8
	sw   s1,0(s2) 					# write to PORT_HEX2
	
	li	 s2,PORT_HEX3
	li	 s1,0x0000F000
	and  s1,a0,s1
	srli s1,s1,12
	sw   s1,0(s2) 					# write to PORT_HEX3
	
	li	 s2,PORT_HEX4
	li	 s1,0x000F0000
	and  s1,a0,s1
	srli s1,s1,16
	sw   s1,0(s2) 					# write to PORT_HEX4
	
	li	 s2,PORT_HEX5
	li	 s1,0x00F00000
	and  s1,a0,s1
	srli s1,s1,20
	sw   s1,0(s2) 					# write to PORT_HEX5
	
	ret
#-----------------------------------------------------------------
#	Function: System static configuration
# arguments: none
# return value: none
#-----------------------------------------------------------------	
intr_config:
	# BT hold and clear
	li 	 t0,BTHOLD_BTCLR
  li   t6,BTCTL1
	sw   t0,0(t6)       					# BTCTL1=(BTHOLD=1,BTCLR=1)

	li   t6,IE
	sw   zero,0(t6)        				# IE=0
	
	li   t6,IFG	
	sw   zero,0(t6)        				# IFG=0
	
	li 	 t0,KEY3IE_KEY2IE_KEY1IE  					
	li   t6,IE 
	sw   t0,0(t6)									# KEY3IE,KEY2IE,KEY1IE are enabled   	
	
	ret
#-----------------------------------------------------------------
#	Function: Basic Timer compare mode configuration
# arguments: none
# return value: none
#-----------------------------------------------------------------
bt_cmp_config:	
	li 	 t0,SEC_PERIOD						# interrupt period of 1sec
	li 	 t6,BTCMPR0
	sw   t0,0(t6)

	# start the timer 
	li   t6,BTCTL1  
	sw   zero,0(t6)       					# BTCTL1=(BTHOLD=0,BTCLR=0,BTSSEL=SMCLK,BTINT=0)
	
	# set BTIE
	li 	 t0,KEY3IE_KEY2IE_KEY1IE_BTIE		  					
	li   t6,IE 
	sw   t0,0(t6)									# KEY3IE,KEY2IE,KEY1IE,BTIE are enabled

	ret
#-----------------------------------------------------------------
#	Function: Basic Timer output compare mode configuration
# arguments: none
# return value: none
#-----------------------------------------------------------------
bt_outcmp_config:
	# clear BTIE 
	li 	 t0,KEY3IE_KEY2IE_KEY1IE	# output compare mode doesn't need interrupt request					
	li   t6,IE 
	sw   t0,0(t6)									# KEY3IE,KEY2IE,KEY1IE are only enabled  

	li 	 t0,FREQ_5K								# PWM frequency=5KHz (for SMCLK=20MHz)
	li 	 t6,BTCMPR0
	sw   t0,0(t6)
		
	andi t4,a7,3								# t4=a7&3 is used as a global value	
if_l1:	
	li	 t2,0
	bne  t4,t2,elif1_l1
	srli t0,t0,1									# if(t4 == 0) duty_cycle=0.5								
elif1_l1:
	li	 t2,1
	bne  t4,t2,elif2_l1
	srli t0,t0,2									# if(t4 == 0) duty_cycle=0.25
elif2_l1:
	li	 t2,2
	bne  t4,t2,elif3_l1
	srli t0,t0,3									# if(t4 == 0) duty_cycle=0.125
elif3_l1:
	li	 t2,3
	bne  t4,t2,endif_l1
	srli t0,t0,4									# if(t4 == 0) duty_cycle=0.0625
endif_l1:	
	li 	 t6,BTCMPR1								
	sw   t0,0(t6)									# set the PWM duty_cycle

	# start the timer
	li 	 t0,BTOUTEN
	li   t6,BTCTL1  
	sw   t0,0(t6)       					# BTCTL1=(BTOUTEN=1,BTHOLD=0,BTCLR=0,BTSSEL=SMCLK)

	ret
#-----------------------------------------------------------------
#	Function: Basic Timer output compare mode configuration
# arguments: none
# return value: none
#-----------------------------------------------------------------
bt_capture_config:
	li 	 t0,BTHOLD_BTCLR_BTINT2
	li   t6,BTCTL1  
	sw   t0,0(t6)       					# BTCTL1=(BTHOLD=1,BTCLR=1,BTSSEL=SMCLK,BTINT=2)
			
	li 	 t0,0xFFFFFFFF						# full scale counting of 32-bit BTCNT
	li 	 t6,BTCMPR0
	sw   t0,0(t6)
	
	li 	 t0,CAPMD1_CAPISEL3				# capture on rising-edge event, set the input signal to GND 
	li 	 t6,BTCTL2
	sw   t0,0(t6)
	
	# set BTIE (case STATE2 was the previous state) 
	li 	 t0,KEY3IE_KEY2IE_KEY1IE_BTIE		  					
	li   t6,IE 
	sw   t0,0(t6)									# KEY3IE,KEY2IE,KEY1IE,BTIE are enabled
		
	ret
#-----------------------------------------------------------------
#	Function: BT-based capture initialization
# arguments: none
# return value: none 
#-----------------------------------------------------------------
capture_init:
	# BTCNT clear and hold
	li 	 t0,BTHOLD_BTCLR_BTINT2		# BTCTL1=(BTHOLD=1,BTCLR=1,BTSSEL=SMCLK,BTINT=2)
  li   t6,BTCTL1
	sw   t0,0(t6)       					# BTCTL1=(BTHOLD=1,BTCLR=1)
	
	# Release the timer
	li 	 t0,BTINT2
  li   t6,BTCTL1
	sw   t0,0(t6)       					# BTCTL1=(BTSSEL=SMCLK,BTINT=2)
			
	ret
#-----------------------------------------------------------------
#	Function: BT-based capture
# arguments: none
# return value: none 
#-----------------------------------------------------------------
capture:
	li 	 t0,CAPMD1_CAPISEL2				# set the input signal to VCC 
	li 	 t6,BTCTL2
	sw   t0,0(t6)

	ret
#-----------------------------------------------------------------
# Function: Division of two arrays element by element
# arguments:
# 	a1: pointer to first the input array
# 	a2: pointer to second the input array
# 	a3: arrays size
# 	a4: pointer to the output array
# return value: none
#-----------------------------------------------------------------
div_arrays:
	mv  t4, zero									# initialization of the array iterator t4
	mv 	s8,a1											# s8 is the arr1_ptr
	mv 	s9,a2											# s9 is the arr2_ptr
	mv  s10,a4										# s10 is the divarr_ptr							

for_l:
	bge	t4,a3,endfor_l
	lw	t1,0(s8)
	lw	t2,0(s9)
	div t3,t1,t2
	sw  t3,0(s10)
	
	addi s8,s8,4								  # arr1_ptr++
	addi s9,s9,4								  # arr2_ptr++
	addi s10,s10,4								# divarr_ptr++
	addi t4,t4,1									# iterator incrementation
	j for_l
endfor_l:
	ret
#-----------------------------------------------------------------
# Function: Reminder of two arrays element by element
# arguments:
# 	a1: pointer to first the input array
# 	a2: pointer to second the input array
# 	a3: arrays size
# 	a5: pointer to the output array
# return value: none
#-----------------------------------------------------------------
rem_arrays:
	mv  t4, zero									# initialization of the array iterator t4
	mv 	s8,a1											# s8 is the arr1_ptr
	mv 	s9,a2											# s9 is the arr2_ptr
	mv  s10,a5										# s10 is the remarr_ptr							

for_l1:
	bge	t4,a3,endfor_l1
	lw	t1,0(s8)
	lw	t2,0(s9)
	rem t3,t1,t2
	sw  t3,0(s10)
	
	addi s8,s8,4								  # arr1_ptr++
	addi s9,s9,4								  # arr2_ptr++
	addi s10,s10,4								# divarr_ptr++
	addi t4,t4,1									# iterator incrementation
	j for_l1
endfor_l1:
	ret

