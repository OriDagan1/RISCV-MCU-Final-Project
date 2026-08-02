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
set APP "C:/Users/oripa/Documents/Benchmark_Apps/Final Project Tests/RV32IM/test1/man_compiled"

set RUN_TIME  900us
# The Hexadecimal-Text images keep the real linker addresses, so the data
# segment lands in the upper half of the 8 KiB DTCM: byte 0x1000 = word 1024.
set DATA_BASE 1024
#=============================================================================

set IMG "$APP/bin/Hexadecimal-Text"
set ITCM "/tb_RV32I/CORE/IFE/inst_memory/MEMORY/m_mem_data_a"
set DTCM "/tb_RV32I/CORE/MEM/data_memory/MEMORY/m_mem_data_a"

if {![file exists $IMG/ITCM.h]} { echo "NOT FOUND: $IMG/ITCM.h" ; return }
if {![file exists $IMG/DTCM.h]} { echo "NOT FOUND: $IMG/DTCM.h" ; return }

vsim -quiet -t 1ps work.tb_RV32I

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
add wave              /tb_RV32I/RegWrite_ctrl_o
add wave -radix hex  /tb_RV32I/write_data_o
add wave -divider {Divider accelerator}
add wave              /tb_RV32I/CORE/div_op_w
add wave              /tb_RV32I/CORE/div_busy_w
add wave -radix dec  /tb_RV32I/CORE/div_ain_w
add wave -radix dec  /tb_RV32I/CORE/div_bin_w
add wave -radix dec  /tb_RV32I/CORE/div_quot_w
add wave -radix dec  /tb_RV32I/CORE/div_rsdu_w
add wave -radix dec  /tb_RV32I/CORE/div_res_w
add wave -divider {Memory}
add wave              /tb_RV32I/MemWrite_ctrl_o
add wave -radix hex  /tb_RV32I/dtcm_addr_o
add wave -radix hex  /tb_RV32I/dtcm_data_wr_o

run $RUN_TIME

echo "-------------------------------------------------"
echo " PC          = [examine -radix hex /tb_RV32I/pc_o]"
echo " instruction = [examine -radix hex /tb_RV32I/instruction_o]"
echo " MCLK cycles = [examine -radix unsigned /tb_RV32I/mclk_cnt_o]"
echo "-------------------------------------------------"
echo " If PC has stopped changing and instruction = 00000063,"
echo " the program has reached its 'finish' self-loop."
echo "-------------------------------------------------"

# Dump the data segment so it can be diffed against the RARS reference.
mem save -o DTCM_out.mem -f mti -data hex -noaddress -wordsperline 1 \
	-startaddress $DATA_BASE -endaddress [expr {$DATA_BASE + 1023}] $DTCM
echo " data segment written to SIM/RV32IMscMCU/DTCM_out.mem"
