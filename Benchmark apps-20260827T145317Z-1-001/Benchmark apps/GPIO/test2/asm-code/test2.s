.include "io_map.s"

.eqv long_delay 	0xB71B00
.eqv short_delay 	4
.eqv SW0_MASK			0x01
.eqv SW1_MASK			0x02
#--------------------------------------------------------------
#							 Data Segment
#--------------------------------------------------------------
.data 
N: .word	short_delay			# delay cycles
 
#--------------------------------------------------------------
#							 Code Segment
#--------------------------------------------------------------
.text
main:
	la   t4,N
	lw   t3,0(t4)
	mv 	 t0,zero  					# t0=0


Loop:	
	lw   t4,PORT_SW 				# read the state of PORT_SW[7-0]
	andi t2,t4,SW0_MASK
	bne  t2,zero,if_l1   		#if SW0='1' jump to if_l1
	j		 elseif
if_l1:
	addi  t0,t0,1
	call print2HEXsArr
	call print2LEDsArr
	call delay
	j    Loop
elseif:	
	andi t2,t4,SW1_MASK
	bne  t2,zero,if_l2   		#if SW1='1' jump to if_l2
	j		 endif
if_l2:
	addi  t0,t0,-1
	call print2HEXsArr
	call print2LEDsArr
	call delay
endif:	
	j    Loop
#============================================================
#												Auxiliary Functions
#============================================================
delay:
	mv	 t1,zero
l:
	addi t1,t1,1  					# t1=t1+1
	blt  t1,t3,l 						# if t1<N then go to Loop label
	ret


print2HEXsArr:
	
	li	 t4,PORT_HEX0
	andi t1,t0,0x0000000F
	sw   t1,0(t4) 					# write to PORT_HEX0
	
	li	 t4,PORT_HEX1
	andi t1,t0,0x000000F0
	srli t1,t1,4
	sw   t1,0(t4) 					# write to PORT_HEX1
	
	li	 t4,PORT_HEX2
	li	 t1,0x00000F00
	and  t1,t0,t1
	srli t1,t1,8
	sw   t1,0(t4) 					# write to PORT_HEX2
	
	li	 t4,PORT_HEX3
	li	 t1,0x0000F000
	and  t1,t0,t1
	srli t1,t1,12
	sw   t1,0(t4) 					# write to PORT_HEX3
	
	li	 t4,PORT_HEX4
	li	 t1,0x000F0000
	and  t1,t0,t1
	srli t1,t1,16
	sw   t1,0(t4) 					# write to PORT_HEX4
	
	li	 t4,PORT_HEX5
	li	 t1,0x00F00000
	and  t1,t0,t1
	srli t1,t1,20
	sw   t1,0(t4) 					# write to PORT_HEX5
	
	ret


print2LEDsArr:

	li	 t4,PORT_LEDR	 
	sw   t0,0(t4) 					# write to PORT_LEDR[7-0]

	ret
	
