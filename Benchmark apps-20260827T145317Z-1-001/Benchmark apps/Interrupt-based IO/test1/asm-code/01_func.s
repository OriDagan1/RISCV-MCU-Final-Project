.include "io_map.s"
.global print2HEX10Arr
.global print2HEX32Arr
.global print2HEX54Arr
.global print2LEDsArr
.global delay
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
	
delay:
	mv	 t1,zero
l:
	addi t1,t1,1  					# t1=t1+1
	blt  t1,a3,l 						# if t1<a3 then go to Loop label
	ret
	
