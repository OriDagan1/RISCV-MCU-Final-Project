.data
arr1:
        .word   1
        .word   2
        .word   3
        .word   4
        .word   5
        .word   6
        .word   7
        .word   8
arr2:
        .word   8
        .word   7
        .word   6
        .word   5
        .word   4
        .word   3
        .word   2
        .word   1
res1:
        .space   32
res2:
        .space   32
res3:
        .space   32

.globl main
.text
main:
        addi    sp,sp,-32
        sw      ra,28(sp)
        sw      s0,24(sp)
        addi    s0,sp,32
        sw      zero,-20(s0)
        j       .L2
.L3:
        la     a4,arr1
        lw      a5,-20(s0)
        slli    a5,a5,2
        add     a5,a4,a5
        lw      a4,0(a5)
        la     a3,arr2
        lw      a5,-20(s0)
        slli    a5,a5,2
        add     a5,a3,a5
        lw      a5,0(a5)
        div     a4,a4,a5
        la     a3,res1
        lw      a5,-20(s0)
        slli    a5,a5,2
        add     a5,a3,a5
        sw      a4,0(a5)
        la     a4,arr1
        lw      a5,-20(s0)
        slli    a5,a5,2
        add     a5,a4,a5
        lw      a4,0(a5)
        la     a3,arr2
        lw      a5,-20(s0)
        slli    a5,a5,2
        add     a5,a3,a5
        lw      a5,0(a5)
        mul     a4,a4,a5
        la     a3,res2
        lw      a5,-20(s0)
        slli    a5,a5,2
        add     a5,a3,a5
        sw      a4,0(a5)
        la     a4,arr1
        lw      a5,-20(s0)
        slli    a5,a5,2
        add     a5,a4,a5
        lw      a4,0(a5)
        la     a3,arr2
        lw      a5,-20(s0)
        slli    a5,a5,2
        add     a5,a3,a5
        lw      a5,0(a5)
        rem     a4,a4,a5
        la     a3,res3
        lw      a5,-20(s0)
        slli    a5,a5,2
        add     a5,a3,a5
        sw      a4,0(a5)
        lw      a5,-20(s0)
        addi    a5,a5,1
        sw      a5,-20(s0)
.L2:
        lw      a4,-20(s0)
        li      a5,7
        ble     a4,a5,.L3
.L4:
        j       .L4