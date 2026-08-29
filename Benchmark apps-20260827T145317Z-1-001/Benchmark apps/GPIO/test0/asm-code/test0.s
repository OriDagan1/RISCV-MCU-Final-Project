.include "io_map.s"

.eqv long_delay 	0xB71B00
.eqv short_delay 	4
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
	li	 t4,PORT_LEDR	 
	sw   t0,0(t4) 					# write to PORT_LEDR[7-0]
	
	li	 t4,PORT_HEX0
	sw   t0,0(t4) 					# write to PORT_HEX0
	
	li	 t4,PORT_HEX1
	sw   t0,0(t4) 					# write to PORT_HEX1
	
	li	 t4,PORT_HEX2
	sw   t0,0(t4) 					# write to PORT_HEX2
	
	li	 t4,PORT_HEX3
	sw   t0,0(t4) 					# write to PORT_HEX3
	
	li	 t4,PORT_HEX4
	sw   t0,0(t4) 					# write to PORT_HEX4
	
	li	 t4,PORT_HEX5
	sw   t0,0(t4) 					# write to PORT_HEX5
		
	addi t0,t0,1 						# t0=t0+1
	mv   t1,zero  					# t1=0
	
delay:	
	addi t1,t1,1  					# t1=t1+1
	blt  t1,t3,delay 				# if t1<N then go to Loop label
	j   Loop
	

