#=============================================================================
# Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
# Run the Basic Timer testbenches (Fig.7).
#
#   do compile.do
#   do run_timer.do                 <- the whole timer, tb_basic_timer
#   do run_timer.do tb_btcnt        <- just the counter and the BTSSEL divider
#
# Both are self-checking: every check prints its own OK line and the run ends
# with either ALL TESTS PASSED or a failure count. Nothing has to be read off
# the waveform, but the waves are set up anyway because the PWM output is
# worth looking at.
#=============================================================================

# "quietly" throughout: a bare "set" echoes its value and buries the results.
if {[info exists 1]} {
	quietly set TB $1
} else {
	quietly set TB tb_basic_timer
}

if {$TB ne "tb_basic_timer" && $TB ne "tb_btcnt"} {
	echo "Unknown testbench '$TB'. Use tb_basic_timer or tb_btcnt."
	return
}

vsim -quiet -t 1ps work.$TB

# Everything is 'U' until reset propagates and numeric_std warns on every
# comparison it sees one in. Silenced over the reset window only, so a genuine
# U/X during the run is still reported. Must be set AFTER vsim: loading a
# design resets them.
quietly set StdArithNoWarnings 1
quietly set NumericStdNoWarnings 1
run 0

if {$TB eq "tb_basic_timer"} {
	add wave -divider {Clock and reset}
	add wave             /tb_basic_timer/smclk
	add wave             /tb_basic_timer/rst
	add wave             /tb_basic_timer/DUT/btclk_w
	add wave -divider {Control registers}
	add wave -radix bin  /tb_basic_timer/btctl1
	add wave -radix bin  /tb_basic_timer/btctl2
	add wave -divider {Compare, and the latched shadows}
	add wave -radix dec  /tb_basic_timer/btcmpr0
	add wave -radix dec  /tb_basic_timer/btcmpr1
	add wave -radix dec  /tb_basic_timer/DUT/btcl0_q
	add wave -radix dec  /tb_basic_timer/DUT/btcl1_q
	add wave -divider {Counter}
	add wave -radix dec  /tb_basic_timer/cnt_int
	add wave             /tb_basic_timer/DUT/equ0_w
	add wave             /tb_basic_timer/DUT/equ1_w
	add wave -divider {Outputs}
	add wave             /tb_basic_timer/pwmout
	add wave             /tb_basic_timer/btifg
	add wave -radix dec  /tb_basic_timer/capr_int
	add wave -divider {Capture}
	add wave             /tb_basic_timer/capin1
	add wave             /tb_basic_timer/DUT/capevt_w
} else {
	add wave -divider {Clock and reset}
	add wave             /tb_btcnt/smclk
	add wave             /tb_btcnt/rst
	add wave -radix bin  /tb_btcnt/sel
	add wave             /tb_btcnt/btclk
	add wave -divider {Controls}
	add wave             /tb_btcnt/clr
	add wave             /tb_btcnt/hold
	add wave -radix dec  /tb_btcnt/btcl0
	add wave -divider {Counter}
	add wave -radix dec  /tb_btcnt/cnt_int
	add wave             /tb_btcnt/equ0
}

# Past reset, so real U/X problems should be reported again
quietly set StdArithNoWarnings 0
quietly set NumericStdNoWarnings 0

run -all

echo "================================================="
echo " $TB finished - see ALL TESTS PASSED above"
echo "================================================="
