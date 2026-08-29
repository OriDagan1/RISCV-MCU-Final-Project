.eqv	SIZE 8

.globl main
.data
arr1: .word  1,2,3,4,5,6,7,8
arr2: .word  8,7,6,5,4,3,2,1
res1: .space 32  # SIZE*4=32 - ADD result array
res2: .space 32  # SIZE*4=32 - MUL result array
res3: .space 32  # SIZE*4=32 - XOR result array

.text
main:	
	li s0, SIZE
	la t0, arr1
	la t1, arr2
	la t2, res1
	la s1, res2
	la s2, res3
	
loop:	lw t3, 0(t0)
	lw t4, 0(t1)
	
	div t5,t3,t4
	sw t5,0(t2)
	
	mul t5,t3,t4
	sw t5,0(s1)
	
	rem t5,t3,t4
	sw t5,0(s2)
	
	addi t0,t0,4
	addi t1,t1,4
	addi t2,t2,4
	addi s1,s1,4
	addi s2,s2,4
	addi s0,s0,-1
	
	bne  s0,x0,loop
finish:	beq x0,x0,finish
	
