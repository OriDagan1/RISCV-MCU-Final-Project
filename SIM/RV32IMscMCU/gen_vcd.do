#=============================================================================
# Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
# Dump switching activity as a .vcd for the Quartus Power Analyzer.
#
#   do compile.do
#   do gen_vcd.do                 ;# RV32IM benchmark  -> mcu_rv32im.vcd
#   set VCDAPP GPIO0 ; do gen_vcd.do   ;# GPIO test0   -> mcu_gpio0.vcd
#
# Clause 6 wants a Power table. Without a .vcd the Power Analyzer falls back
# to an assumed default toggle rate, which is a guess; feeding it real
# activity from the benchmark makes the dynamic figure defensible. Say in the
# report which of the two you used - they are different workloads and they
# will not give the same number.
#
# Only the reset-released, program-running window is recorded. Activity
# during reset is not representative, and the finish self-loop at the end of
# the benchmark would dilute the toggle rates if it ran on for long.
#
# Note: this is an RTL simulation with MODELSIM=1, so the three PLLs are
# behavioural and do not appear in the dump. The Power Analyzer reports what
# fraction of netlist nodes it matched; anything unmatched falls back to the
# default toggle rate. Check that figure before quoting the result.
#=============================================================================
if {![info exists VCDAPP]} { set VCDAPP RV32IM }

quietly set APPROOT "C:/Users/oripa/Documents/Benchmark_Apps/Final Project Tests"

switch -- $VCDAPP {
	RV32IM {
		quietly set IMG  "$APPROOT/RV32IM/test1/man_compiled/bin/M9K-intel"
		quietly set OUT  "mcu_rv32im.vcd"
		# 276 MCLK cycles at 25 MHz = 11.04 us, starting when reset releases
		# at 2 us. 11.5 us covers the whole program and little else.
		quietly set WIN  "11.5 us"
		quietly set NOTE "RV32IM benchmark, 276 cycles - exercises the CPU, the multiplier, the divider and the DTCM"
	}
	GPIO0 {
		quietly set IMG  "$APPROOT/GPIO/test0/bin/M9K-intel"
		quietly set OUT  "mcu_gpio0.vcd"
		# Infinite display loop, 1.28 us per iteration. 20 us is about
		# sixteen iterations, plenty for a stable toggle rate.
		quietly set WIN  "20 us"
		quietly set NOTE "GPIO test0 - exercises the memory-mapped I/O writes, but barely touches the divider"
	}
	default {
		echo "VCDAPP must be RV32IM or GPIO0"
		return
	}
}

if {![file exists $IMG/ITCM.hex]} {
	echo "NOT FOUND: $IMG/ITCM.hex"
	return
}

catch {quit -sim}
vsim -quiet -t 1ps -GMODELSIM=1 \
	"-GITCM_INIT_FILE=\"$IMG/ITCM.hex\"" \
	"-GDTCM_INIT_FILE=\"$IMG/DTCM.hex\"" work.tb_RV32I
quietly set StdArithNoWarnings 1
quietly set NumericStdNoWarnings 1
run 0

# Reset releases at 2 us. Step past it before opening the dump so the reset
# transient is not counted as program activity.
run 2 us
quietly set StdArithNoWarnings 0
quietly set NumericStdNoWarnings 0

# Dump the MCU, not the testbench: the Quartus top level is MCU, and the
# testbench's own signals have no counterpart in the netlist.
vcd file $OUT
vcd add -r /tb_RV32I/CORE/*

run $WIN

vcd flush
echo "----------------------------------------------------------------"
echo " wrote SIM/RV32IMscMCU/$OUT"
echo " workload : $NOTE"
echo " window   : reset release (2 us) + $WIN"
echo ""
echo " In Quartus: Assignments -> Settings -> Power Analyzer Settings"
echo "   'Use input files to initialize toggle rates...'  -> add the .vcd"
echo " Then Processing -> Start -> Start Power Analyzer."
echo " Check the reported percentage of matched nodes before quoting it."
echo "----------------------------------------------------------------"
