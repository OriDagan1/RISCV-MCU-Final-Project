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

set APPROOT "../../Benchmark apps-20260827T145317Z-1-001/Benchmark apps/GPIO"
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
# Colours come from wave_style.do - see its header for the scheme.
#-----------------------------------------------------------------------------
do wave_style.do
wave_mcu_io app
wave_look

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
if {$TEST == 0} {
	# Measured landmarks. Reset releases at 2 us; the first store lands at
	# 2.26 us; one loop iteration is exactly 1.28 us (32 MCLK cycles), of
	# which the seven stores occupy the first 720 ns, 120 ns apart, and the
	# delay loop the remaining 560 ns.
	echo " Iteration k stores the value k at  2.26 + 1.28*k  us."
	echo " Within an iteration starting at T:"
	echo "   T+0.00us 0x2000 LEDR   T+0.12 0x2004 HEX0   T+0.24 0x2005 HEX1"
	echo "   T+0.36us 0x2008 HEX2   T+0.48 0x2009 HEX3   T+0.60 0x200C HEX4"
	echo "   T+0.72us 0x200D HEX5   then 560ns of delay loop"
	echo ""
	echo " Zoom somewhere useful - zoom full is 158 iterations and unreadable:"
	echo "   wave zoom range 1.9us 23us      ;# 16 iterations, digit runs 0-F"
	echo "   wave zoom range 3.4us 4.9us     ;# one whole iteration"
	echo "   wave zoom range 3.50us 4.30us   ;# just the seven stores"
	echo "   wave zoom range 3.72us 3.86us   ;# the HEX1 store at 0x2005"
	echo "   wave zoom range 4.25us 4.85us   ;# the idle gap, BUF_NONE parks"
} else {
	echo " Keep going with:  force -freeze /tb_RV32I/SW_i 00000010 ; run 200 us"
	echo " Zoom before screenshotting - zoom full is far too coarse to read."
}
echo "----------------------------------------------------------------"
wave zoom range 1.9us 23us
