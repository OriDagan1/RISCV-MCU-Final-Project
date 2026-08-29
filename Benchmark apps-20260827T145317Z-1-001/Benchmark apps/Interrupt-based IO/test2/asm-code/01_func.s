.include "io_map.s"
.global print2HEX10Arr
.global print2HEX32Arr
.global print2HEX54Arr
.global print2LEDsArr
.global sys_init
#============================================================
#												Auxiliary Functions
#============================================================
.text

print2HEX10Arr:						# a0 is the function argument
	li	 s2,PORT_HEX0
	andi s1,a0,0x0000000F
	sw   s1,0(s2) 					# write to PORT_HEX0
	
	li	 s2,PORT_HEX1
	andi s1,a0,0x000000F0
	srli s1,s1,4
	sw   s1,0(s2) 					# write to PORT_HEX1
	ret

print2HEX32Arr:						# a0 is the function argument
	li	 s2,PORT_HEX2
	andi s1,a0,0x0000000F
	sw   s1,0(s2) 					# write to PORT_HEX2
	
	li	 s2,PORT_HEX3
	andi s1,a0,0x000000F0
	srli s1,s1,4
	sw   s1,0(s2) 					# write to PORT_HEX3
	ret

	
print2HEX54Arr:						# a0 is the function argument
	li	 s2,PORT_HEX4
	andi s1,a0,0x0000000F
	sw   s1,0(s2) 					# write to PORT_HEX4
	
	li	 s2,PORT_HEX5
	andi s1,a0,0x000000F0
	srli s1,s1,4
	sw   s1,0(s2) 					# write to PORT_HEX5
	ret


print2LEDsArr:						# a0 is the function argument
	li	 s2,PORT_LEDR	 
	sw   a0,0(s2) 					# write to PORT_LEDR[7-0]

	ret
	
sys_init:
	li 	 t0,BTHOLD_BTSSEL3_BTCLR
  li   t6,BTCTL1
	sw   t0,0(t6)       					# BTCTL1=(BTHOLD=1,BTSSEL=3,BTCLR=1)
	
	li   t6,IE
	sw   zero,0(t6)        				# IE=0
	
	li   t6,IFG	
	sw   zero,0(t6)        				# IFG=0
	
	li 	 t0,SEC_PERIOD						# interrupt period of 1sec
	li 	 t6,BTCMPR0
	sw   t0,0(t6)
	
	li 	 t0,KEY3IE_KEY2IE_KEY1IE_BTIE  					
	li   t6,IE 
	sw   t0,0(t6)									# KEY3IE,KEY2IE,KEY1IE,BTIE are enabled   
	
	li 	 t0,BTSSEL3
	li   t6,BTCTL1  
	sw   t0,0(t6)       					# BTCTL1=(BTHOLD=0, BTSSEL=3), start the timer
	
	ret

	