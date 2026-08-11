#=============================================================================
# Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
# Run one of the three supplied GPIO applications, with a wave window set up
# for the memory-mapped I/O path.
#
#   do compile.do
#   set TEST 1 ; do run_gpio.do
#
# TEST 0, 1 or 2. Defaults to 0 if you do not set it.
#
#   test0   counts up on its own, writes the counter to LEDR and to every
#           display. SW is not read.
#   test1   reads PORT_SW. SW=0x01 counts up, SW=0x02 counts down, anything
#           else holds. Every display shows the low nibble.
#   test2   same SW behaviour, but the six displays are the six nibbles of
#           the counter, so each one shows something different.
#
# These programs are infinite display loops. They never reach a finish
# self-loop and they have no golden DTCM, so run_benchmark.do's cycle count
# and memory diff do not apply - watch the wave window instead.
#
# Drive the switches from the transcript while it runs:
#
#   force -freeze /tb_RV32I/SW_i 00000001 ; run 200 us     ;# count up
#   force -freeze /tb_RV32I/SW_i 00000010 ; run 200 us     ;# count down
#   force -freeze /tb_RV32I/SW_i 00000000 ; run 200 us     ;# hold
#=============================================================================
if {![info exists TEST]} { set TEST 0 }

set APPROOT "C:/Users/oripa/Documents/Benchmark_Apps/Final Project Tests/GPIO"
set IMG     "$APPROOT/test$TEST/bin/M9K-intel"

if {![file exists $IMG/ITCM.hex]} {
	echo "NOT FOUND: $IMG/ITCM.hex"
	echo "Edit APPROOT at the top of run_gpio.do if the apps live elsewhere."
	return
}

# The GPIO images are linked for the 8 KiB TCM, same as the M9K-intel set of
# the RV32IM benchmark. altsyncram applies init_file at time 0, so the images
# go in through generics and have to be set before elaboration.
catch {quit -sim}
vsim -quiet -t 1ps -GMODELSIM=1 \
	"-GITCM_INIT_FILE=\"$IMG/ITCM.hex\"" \
	"-GDTCM_INIT_FILE=\"$IMG/DTCM.hex\"" work.tb_RV32I

# Everything is 'U' until reset propagates and std_arith warns on every
# operation that sees one. Silenced over the reset window only. Must be set
# AFTER vsim - loading a design resets them.
quietly set StdArithNoWarnings 1
quietly set NumericStdNoWarnings 1

#-----------------------------------------------------------------------------
# Wave window, grouped the way the report reads: clocks, then what the CPU
# puts on the bus, then the decode, then the tri-state buffers, then the pins.
#-----------------------------------------------------------------------------
catch {delete wave *}

add wave -divider {Clocks and reset}
add wave              /tb_RV32I/rst_i
add wave              /tb_RV32I/clk_i
add wave              /tb_RV32I/CORE/mclk_w
add wave              /tb_RV32I/CORE/divclk_w
add wave              /tb_RV32I/CORE/smclk_w

add wave -divider {CPU}
add wave -radix hex   /tb_RV32I/pc_o
add wave -radix hex   /tb_RV32I/instruction_o
add wave -radix unsigned /tb_RV32I/CORE/CPU/ID/RF_q(5)

add wave -divider {Data bus, master side}
add wave -radix hex   /tb_RV32I/CORE/bus_addr_w
add wave              /tb_RV32I/CORE/bus_read_w
add wave              /tb_RV32I/CORE/bus_write_w
add wave -radix hex   /tb_RV32I/CORE/bus_wdata_w
add wave -radix hex   /tb_RV32I/CORE/bus_rdata_w
add wave              /tb_RV32I/CORE/io_sel_w

add wave -divider {Address decode - one hot}
add wave              /tb_RV32I/CORE/cs_ledr_w
add wave              /tb_RV32I/CORE/cs_hex0_1_w
add wave              /tb_RV32I/CORE/cs_hex2_3_w
add wave              /tb_RV32I/CORE/cs_hex4_5_w
add wave              /tb_RV32I/CORE/cs_sw_w

add wave -divider {BidirPin output enables}
add wave              /tb_RV32I/CORE/oe_ledr_w
add wave              /tb_RV32I/CORE/oe_hex0_1_w
add wave              /tb_RV32I/CORE/oe_hex2_3_w
add wave              /tb_RV32I/CORE/oe_hex4_5_w
add wave              /tb_RV32I/CORE/oe_sw_w
add wave              /tb_RV32I/CORE/oe_none_w
add wave -radix hex   /tb_RV32I/CORE/io_bus_w

add wave -divider {Pins}
add wave -radix hex      /tb_RV32I/SW_i
add wave -radix binary   /tb_RV32I/LEDR_o
add wave -radix binary   /tb_RV32I/HEX0_o
add wave -radix binary   /tb_RV32I/HEX1_o
add wave -radix binary   /tb_RV32I/HEX2_o
add wave -radix binary   /tb_RV32I/HEX3_o
add wave -radix binary   /tb_RV32I/HEX4_o
add wave -radix binary   /tb_RV32I/HEX5_o

configure wave -namecolwidth 260
configure wave -valuecolwidth 90
configure wave -timelineunits us

# Reset releases at 2 us. Step past it before re-arming the warnings, so a
# genuine U or X during the program is still reported.
run 3 us
quietly set StdArithNoWarnings 0
quietly set NumericStdNoWarnings 0

if {$TEST == 0} {
	# test0 ignores SW. Just let it count.
	run 200 us
	echo "----------------------------------------------------------------"
	echo " GPIO test0 - free-running counter, SW not read"
} else {
	# Exercise all four SW cases in one shot so a single screenshot of the
	# wave window shows up, hold, down and hold again.
	force -freeze /tb_RV32I/SW_i 00000001
	run 150 us
	force -freeze /tb_RV32I/SW_i 00000000
	run 80 us
	force -freeze /tb_RV32I/SW_i 00000010
	run 150 us
	force -freeze /tb_RV32I/SW_i 00000100
	run 80 us
	echo "----------------------------------------------------------------"
	echo " GPIO test$TEST - SW driven: up (0x01), hold (0x00),"
	echo "                  down (0x02), hold (0x04)"
}

echo " counter t0    = [examine -radix unsigned /tb_RV32I/CORE/CPU/ID/RF_q(5)]"
echo " LEDR_o        = [examine -radix binary /tb_RV32I/LEDR_o]"
echo " HEX5..HEX0    = [examine -radix binary /tb_RV32I/HEX5_o]\
 [examine -radix binary /tb_RV32I/HEX4_o]\
 [examine -radix binary /tb_RV32I/HEX3_o]\
 [examine -radix binary /tb_RV32I/HEX2_o]\
 [examine -radix binary /tb_RV32I/HEX1_o]\
 [examine -radix binary /tb_RV32I/HEX0_o]"
echo " io_bus_w      = [examine -radix hex /tb_RV32I/CORE/io_bus_w]"
echo "----------------------------------------------------------------"
echo " Keep going with:  force -freeze /tb_RV32I/SW_i 00000010 ; run 200 us"
echo "----------------------------------------------------------------"
wave zoom full
