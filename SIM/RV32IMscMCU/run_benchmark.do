#=============================================================================
# Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
# Run one benchmark application on the RV32IM MCU.
#
#   do compile.do
#   do run_benchmark.do
#
# ----------------------------------------------------------------------------
# EDIT THIS to pick the application. It must be the folder that contains
# bin/Hexadecimal-Text/{ITCM.h,DTCM.h}. Use FORWARD slashes.
# ----------------------------------------------------------------------------
quietly set APP "C:/Users/oripa/Documents/Benchmark_Apps/Final Project Tests/RV32IM/test1/man_compiled"

quietly set RUN_TIME  900us
# The Hexadecimal-Text images keep the real linker addresses, so the data
# segment lands in the upper half of the 8 KiB DTCM: byte 0x1000 = word 1024.
quietly set DATA_BASE 1024
# How many words of the data segment to print at the end (0 disables).
quietly set SHOW_WORDS 40
#=============================================================================

# "quietly" everywhere below: a bare "set" echoes its value into the
# transcript, which buries the actual results in noise.
quietly set IMG  "$APP/bin/Hexadecimal-Text"
quietly set ITCM "/tb_RV32I/CORE/IFE/inst_memory/MEMORY/m_mem_data_a"
quietly set DTCM "/tb_RV32I/CORE/MEM/data_memory/MEMORY/m_mem_data_a"

if {![file exists $IMG/ITCM.h]} { echo "NOT FOUND: $IMG/ITCM.h" ; return }
if {![file exists $IMG/DTCM.h]} { echo "NOT FOUND: $IMG/DTCM.h" ; return }

vsim -quiet -t 1ps work.tb_RV32I

# Everything is 'U' until reset propagates, and std_logic_arith warns on every
# arithmetic operation it sees one in. That is hundreds of harmless messages
# at time 0, so silence them over the reset window and switch them back on
# afterwards - a U/X warning during the actual program is worth seeing.
quietly set StdArithNoWarnings 1
quietly set NumericStdNoWarnings 1

# run 0 first: altsyncram applies its init_file generic at time 0, so loading
# the images before that would simply be overwritten.
run 0
mem load -infile $IMG/ITCM.h -format hex $ITCM
mem load -infile $IMG/DTCM.h -format hex -startaddress $DATA_BASE $DTCM
echo "loaded $IMG"

add wave -divider {CPU}
add wave -radix hex  /tb_RV32I/pc_o
add wave -radix hex  /tb_RV32I/instruction_o
add wave -radix dec  /tb_RV32I/mclk_cnt_o
add wave -divider {Write-back}
add wave             /tb_RV32I/RegWrite_ctrl_o
add wave -radix hex  /tb_RV32I/write_data_o
add wave -divider {Divider accelerator}
add wave             /tb_RV32I/CORE/div_op_w
add wave             /tb_RV32I/CORE/div_busy_w
add wave -radix dec  /tb_RV32I/CORE/div_ain_w
add wave -radix dec  /tb_RV32I/CORE/div_bin_w
add wave -radix dec  /tb_RV32I/CORE/div_quot_w
add wave -radix dec  /tb_RV32I/CORE/div_rsdu_w
add wave -radix dec  /tb_RV32I/CORE/div_res_w
add wave -divider {Memory}
add wave             /tb_RV32I/MemWrite_ctrl_o
add wave -radix hex  /tb_RV32I/dtcm_addr_o
add wave -radix hex  /tb_RV32I/dtcm_data_wr_o

# Past reset, so real U/X problems should be reported again.
run 200 ns
quietly set StdArithNoWarnings 0
quietly set NumericStdNoWarnings 0

# Catch the "finish: beq x0,x0,finish" self-loop so the cycle count is the
# program's, not however long we happened to keep the clock running. The
# counter starts at reset, so this is cycles-to-completion.
quietly set ::FINISH_CYCLES "NOT REACHED"
when {/tb_RV32I/instruction_o == 16#63#} {
	if {$::FINISH_CYCLES eq "NOT REACHED"} {
		quietly set ::FINISH_CYCLES [examine -radix unsigned /tb_RV32I/mclk_cnt_o]
	}
}

run $RUN_TIME

echo "================================================="
echo " PC               = [examine -radix hex /tb_RV32I/pc_o]"
echo " instruction      = [examine -radix hex /tb_RV32I/instruction_o]"
echo " cycles to finish = $::FINISH_CYCLES"
echo "================================================="
if {$::FINISH_CYCLES eq "NOT REACHED"} {
	echo " The program never hit its finish self-loop."
	echo " Increase RUN_TIME at the top of this script."
} else {
	echo " instruction 00000063 with a frozen PC = program done."
}
echo "================================================="

# Dump the data segment so it can be diffed against the RARS reference.
mem save -o DTCM_out.mem -f mti -data hex -noaddress -wordsperline 1 \
	-startaddress $DATA_BASE -endaddress [expr {$DATA_BASE + 1023}] $DTCM
echo " full data segment -> SIM/RV32IMscMCU/DTCM_out.mem"

if {$SHOW_WORDS > 0} {
	echo "-------------------------------------------------"
	echo " data segment, first $SHOW_WORDS words"
	echo " (word 0 below = DTCM word $DATA_BASE = byte 0x1000)"
	echo "-------------------------------------------------"
	# "mem display" returns its text rather than printing it. At the top level
	# of a do file the transcript echoes that return value, but inside this
	# if-block it would be discarded, so echo it explicitly.
	quietly set LAST [expr {$DATA_BASE + $SHOW_WORDS - 1}]
	echo [mem display -addressradix d -dataradix d -wordsperline 8 -startaddress $DATA_BASE -endaddress $LAST $DTCM]
	echo "-------------------------------------------------"
}
