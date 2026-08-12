#=============================================================================
# Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
# Run one benchmark application on the RV32IM MCU.
#
#   do compile.do
#   do run_benchmark.do
#
# The application data must end up at DTCM word 0, with arr1, arr2 and the
# result arrays contiguous from there, exactly as in Figure 2 of the task
# definition. Which image set achieves that depends on the TCM size selected
# in cond_compilation_package.vhd, because the two sets were linked for
# different memory maps:
#
#   TCM size            image set                     how it is loaded
#   ------------------  ----------------------------  --------------------
#   8 KiB (TCM8KiB)     bin/M9K-intel/*.hex           init_file generic
#   4 KiB (TCM4KiB)     bin/Hexadecimal-Text/*.h      mem load
#
# Pairing them the other way puts the data segment at word 1024 instead of
# word 0, so this script checks the combination and refuses to run a
# mismatched one.
#
# ----------------------------------------------------------------------------
# EDIT THESE
# ----------------------------------------------------------------------------
# Folder containing bin/. Forward slashes.
quietly set APP "C:/Users/oripa/Documents/Benchmark_Apps/Final Project Tests/RV32IM/test1/man_compiled"

# auto | M9K | HEX      "auto" picks from the compiled TCM size.
quietly set IMAGE auto

quietly set RUN_TIME   900us
quietly set SHOW_WORDS 40
# Golden reference to diff against. "" disables the check.
quietly set GOLDEN "$APP/output/RARS/DTCM.h"
#=============================================================================

# "quietly" throughout: a bare "set" echoes its value and buries the results.
# Hierarchy since Sprint 0: tb -> MCU (instance CORE) -> RV32I_CORE (CPU).
# The MCU instance keeps the label CORE so the DTCM path is unchanged from
# the dumps produced before the split.
quietly set CPU  "/tb_RV32I/CORE/CPU"
quietly set ITCM "$CPU/IFE/inst_memory/MEMORY/m_mem_data_a"
quietly set DTCM "/tb_RV32I/CORE/MEM/data_memory/MEMORY/m_mem_data_a"

#-----------------------------------------------------------------------------
# Work out the TCM size, which decides the image set. DATA_WORDS_NUM is a
# generic on the testbench, so it needs an elaborated design to read; load
# once plainly, check, then reload with the right images.
#-----------------------------------------------------------------------------
# MODELSIM=1 picks the behavioural clock generators in MCU.vhd over the three
# PLL IP cores. Identical frequencies either way - both branches read
# clk_config_package.vhd, which QUARTUS/gen_plls.tcl writes alongside the IP -
# but the behavioural path needs no PLL lock time. To simulate the real IP
# instead, set this to 0; compile.do reports whether the models are loaded.
quietly set SIMGEN "-GMODELSIM=1"

vsim -quiet -t 1ps $SIMGEN work.tb_RV32I
# Everything is 'U' until reset propagates and std_logic_arith warns on every
# operation it sees one in - hundreds of harmless messages. Silenced over the
# reset window only, so a genuine U/X during the program is still reported.
# These must be set AFTER vsim: loading a design resets them.
quietly set StdArithNoWarnings 1
quietly set NumericStdNoWarnings 1
run 0
quietly set WORDS [examine -radix unsigned /tb_RV32I/DATA_WORDS_NUM]

if {$IMAGE eq "auto"} {
	if {$WORDS >= 2048} { quietly set IMAGE M9K } else { quietly set IMAGE HEX }
}

if {$IMAGE eq "M9K" && $WORDS < 2048} {
	echo "MISMATCH: M9K-intel images need the 8 KiB TCM, but DATA_WORDS_NUM=$WORDS."
	echo "          Set G_ADDRWIDTH/G_DATA_WORDSNUM/G_PC_WIDTH/G_MA_WIDTH to the"
	echo "          *_TCM8KiB constants in cond_compilation_package.vhd, or use IMAGE HEX."
	return
}
if {$IMAGE eq "HEX" && $WORDS >= 2048} {
	echo "MISMATCH: Hexadecimal-Text images need the 4 KiB TCM, but DATA_WORDS_NUM=$WORDS."
	echo "          Set G_ADDRWIDTH/G_DATA_WORDSNUM/G_PC_WIDTH/G_MA_WIDTH to the"
	echo "          *_TCM4KiB constants in cond_compilation_package.vhd, or use IMAGE M9K."
	echo "          Running anyway would place the data segment at word 1024, not word 0."
	return
}

#-----------------------------------------------------------------------------
# Load the application
#-----------------------------------------------------------------------------
if {$IMAGE eq "M9K"} {
	quietly set IMG "$APP/bin/M9K-intel"
	if {![file exists $IMG/ITCM.hex]} { echo "NOT FOUND: $IMG/ITCM.hex" ; return }
	# Intel HEX goes in through the init_file generic; altsyncram applies it
	# at time 0, so it has to be set before elaboration.
	quit -sim
	vsim -quiet -t 1ps $SIMGEN "-GITCM_INIT_FILE=\"$IMG/ITCM.hex\"" "-GDTCM_INIT_FILE=\"$IMG/DTCM.hex\"" work.tb_RV32I
	# quit -sim cleared these, so re-arm them for the new simulation
	quietly set StdArithNoWarnings 1
	quietly set NumericStdNoWarnings 1
	run 0
} else {
	quietly set IMG "$APP/bin/Hexadecimal-Text"
	if {![file exists $IMG/ITCM.h]} { echo "NOT FOUND: $IMG/ITCM.h" ; return }
	# Plain word lists, which init_file cannot read, so they go in with
	# mem load - and only after "run 0", because altsyncram applies its
	# init_file generic at time 0 and would overwrite them.
	mem load -infile $IMG/ITCM.h -format hex $ITCM
	mem load -infile $IMG/DTCM.h -format hex $DTCM
}
echo "TCM = [expr {$WORDS*4/1024}] KiB, image set = $IMAGE"
echo "loaded $IMG"

# Clocks, CPU, write-back, the division accelerator and the DTCM. Colours
# come from wave_style.do - see its header for the scheme. Zoom right into
# the clocks to see the 8:1 ratio: DIVCLK ticks eight times per MCLK, which
# is what cut the division stall to 9 cycles. The Timing Analyzer measured the
# DIVCLK domain at 238.61 MHz, so 200 MHz closes with 19% margin.
do wave_style.do
wave_cpu
wave_look

# Past reset, so real U/X problems should be reported again.
run 200 ns
quietly set StdArithNoWarnings 0
quietly set NumericStdNoWarnings 0

# Catch the "finish: beq x0,x0,finish" self-loop, so the reported figure is
# the program's cycle count and not however long the clock was left running.
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

# Data segment starts at word 0 (Figure 2), so dump from there.
mem save -o DTCM_out.mem -f mti -data hex -noaddress -wordsperline 1 \
	-startaddress 0 -endaddress [expr {$WORDS - 1}] $DTCM

#-----------------------------------------------------------------------------
# Diff against the golden model
#-----------------------------------------------------------------------------
if {$GOLDEN ne "" && [file exists $GOLDEN]} {
	quietly set fg [open $GOLDEN r]
	quietly set gold [split [string trim [read $fg]] "\n"]
	close $fg
	quietly set fs [open DTCM_out.mem r]
	quietly set mine {}
	foreach ln [split [read $fs] "\n"] {
		quietly set ln [string trim $ln]
		if {$ln ne "" && [string index $ln 0] ne "/"} { lappend mine $ln }
	}
	close $fs

	quietly set n [llength $gold]
	if {[llength $mine] < $n} { quietly set n [llength $mine] }
	quietly set bad 0
	quietly set firsts {}
	for {quietly set i 0} {$i < $n} {incr i} {
		if {[string toupper [string trim [lindex $gold $i]]] ne
		    [string toupper [lindex $mine $i]]} {
			incr bad
			if {[llength $firsts] < 8} {
				lappend firsts "   word $i: golden [lindex $gold $i]  sim [lindex $mine $i]"
			}
		}
	}
	echo "================================================="
	echo " golden : $GOLDEN"
	echo " compared $n words, $bad mismatches"
	foreach l $firsts { echo $l }
	if {$bad == 0} { echo " *** DTCM MATCHES THE GOLDEN MODEL ***" }
} else {
	echo " (no golden reference at $GOLDEN - skipped the diff)"
}

if {$SHOW_WORDS > 0} {
	echo "================================================="
	echo " data segment, words 0 - [expr {$SHOW_WORDS - 1}]"
	echo "================================================="
	# "mem display" returns its text rather than printing it: at the top level
	# of a do file the transcript echoes the return value, but inside this
	# if-block it would be discarded, so echo it explicitly.
	echo [mem display -addressradix d -dataradix d -wordsperline 8 \
		-startaddress 0 -endaddress [expr {$SHOW_WORDS - 1}] $DTCM]
}
echo "================================================="
echo " full dump -> SIM/RV32IMscMCU/DTCM_out.mem"
