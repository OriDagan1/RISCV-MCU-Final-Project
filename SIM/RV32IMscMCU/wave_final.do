#=============================================================================
# Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
# Final verification wave setup for tb_RV32IMscMCU (test1..test4), with
# especially good coverage of test4's Compare, PWM and Capture sections.
#
# Usage, from SIM/RV32IMscMCU after "do compile.do" and vcom'ing
# TB/RV32IMscMCU/tb_RV32IMscMCU.vhd (not yet in compile.do's own list):
#
#   vsim -gTEST_NUM=4 -gTEST4_SUBTEST=3 work.tb_RV32IMscMCU
#   do wave_final.do
#   run -all
#
# All hierarchical paths below were checked against the actual current
# source (DUT/RV32IMscMCU/*.vhd) before this file was written - see the
# per-group notes for the two names that needed a real path rather than the
# literal one asked for.
#
# Sourced rather than duplicated: wave_style.do's three generic helpers -
#   w color path {radix}   one signal, coloured, optionally with a radix
#   wdiv color label       a section divider tinted to match its group
#   wave_look              window geometry (leaf names, column widths, us)
# None of those are specific to tb_RV32I/CORE; only wave_mcu_io/wave_cpu in
# that file are, and neither is called or touched here.
#=============================================================================
do wave_style.do

proc wave_final {} {
	catch {delete wave *}

	set TB   /tb_rv32imscmcu
	set DUT  /tb_rv32imscmcu/DUT
	set CPU  /tb_rv32imscmcu/DUT/CPU
	set BT   /tb_rv32imscmcu/DUT/BT
	set CAPT /tb_rv32imscmcu/DUT/BT/CAPT
	set BTIF /tb_rv32imscmcu/DUT/BTIF

	#-------------------------------------------------------------------
	# -- TOP LEVEL --
	#-------------------------------------------------------------------
	# Board-side I/O plus PC/instruction. PWMout_o lives here only - the
	# task's own signal list named it again under Basic Timer, but it is
	# the same net with no logic in between (basic_timer's pwmout_o wires
	# straight to this top-level port), so a second trace would be a pure
	# duplicate and the Cleanup section asks not to do that.
	wdiv Red {TOP LEVEL}
	w Red          $TB/rst_i
	w #7F8C99      $TB/clk_i
	w Cyan         $TB/SW_i          hex
	w DodgerBlue   $TB/KEY_i         binary
	w SpringGreen  $TB/LEDR_o        binary
	w Gold         $TB/HEX0_o        binary
	w #FFE066      $TB/HEX1_o        binary
	w Orange       $TB/HEX2_o        binary
	w #FFBB70      $TB/HEX3_o        binary
	w Coral        $TB/HEX4_o        binary
	w #FFA694      $TB/HEX5_o        binary
	w MediumOrchid $TB/PWMout_o
	w SkyBlue      $TB/pc_o          hex
	w #A8D8FF      $TB/instruction_o hex

	#-------------------------------------------------------------------
	# -- CPU / BUS --
	#-------------------------------------------------------------------
	# MemRead_ctrl_o is not an MCU-level port (only RegWrite_ctrl_o,
	# MemWrite_ctrl_o and Branch_ctrl_o are re-exposed there) - it exists
	# as RV32I_CORE's own output port, so it is read at $CPU instead of $TB.
	wdiv White {CPU / BUS}
	w GreenYellow  $CPU/MemRead_ctrl_o
	w Magenta      $TB/MemWrite_ctrl_o
	w GreenYellow  $TB/RegWrite_ctrl_o
	w SkyBlue      $TB/Branch_ctrl_o
	w White        $TB/dtcm_addr_o     hex
	w Magenta      $TB/dtcm_data_wr_o  hex
	w GreenYellow  $TB/dtcm_data_rd_o  hex

	#-------------------------------------------------------------------
	# -- BASIC TIMER --
	#-------------------------------------------------------------------
	# capevt_w (raw, drives btifg_o/the interrupt request - unchanged by
	# the capture fix) and capevt_q (the delayed/aligned signal the fix
	# added, feeding capevt_o -> BTIF) are shown side by side so the one
	# BTCLK-cycle alignment the fix introduced is visible directly.
	wdiv MediumOrchid {BASIC TIMER}
	w MediumOrchid $BT/btctl1_i  hex
	w MediumOrchid $BT/btctl2_i  hex
	w MediumOrchid $BT/btcmpr0_i hex
	w MediumOrchid $BT/btcmpr1_i hex
	w Violet       $BT/btclk_w
	w MediumOrchid $BT/cnt_w     hex
	w MediumOrchid $BT/btcl0_q   hex
	w MediumOrchid $BT/btcl1_q   hex
	w MediumOrchid $BT/equ0_w
	w MediumOrchid $BT/equ1_w
	w MediumOrchid $BT/btifg_o
	w Tomato       $BT/capevt_w
	w OrangeRed    $BT/capevt_q
	w MediumOrchid $BT/btcapr_o  hex

	#-------------------------------------------------------------------
	# -- CAPTURE INTERNAL --
	#-------------------------------------------------------------------
	# Focused set only, per the task: the synchronizer chain and the two
	# outputs, not every internal net of BT_CAPTURE.
	wdiv Tomato {CAPTURE INTERNAL}
	w Tomato $CAPT/cnt_i      hex
	w Tomato $CAPT/capisel_i  binary
	w Tomato $CAPT/capmd_i    binary
	w Tomato $CAPT/cap_src_w
	w Tomato $CAPT/sync_q     binary
	w Tomato $CAPT/rise_w
	w Tomato $CAPT/capevt_w
	w Tomato $CAPT/btcapr_q   hex

	#-------------------------------------------------------------------
	# -- TIMER INTERFACE --
	#-------------------------------------------------------------------
	# btcapr_q here is the CPU-visible BTCAPR register itself - what a
	# software "lw BTCAPR" actually reads. Together with the Basic Timer
	# and Capture Internal groups above, the full chain is on screen:
	# BT.cnt_w -> CAPT.capevt_w/rise_w -> CAPT.btcapr_q (true value) ->
	# BT.capevt_q (aligned) -> BTIF.capevt_i/btcapr_i -> BTIF.btcapr_q
	# (CPU-visible) -> dtcm_data_rd_o on the lw, dtcm_data_wr_o on the sw.
	wdiv SteelBlue {TIMER INTERFACE}
	w SteelBlue $BTIF/btcapr_i hex
	w SteelBlue $BTIF/capevt_i
	w SteelBlue $BTIF/btcapr_q hex

	#-------------------------------------------------------------------
	# -- TB CHECKERS --
	#-------------------------------------------------------------------
	# The testbench's own monitors, exact names, so test4 can be read off
	# these counters/values instead of decoding every store by hand.
	wdiv Khaki {TB CHECKERS}
	w Khaki $TB/state_store_count_s   unsigned
	w Khaki $TB/last_state_store_s    hex
	w Khaki $TB/btcmpr0_store_count_s unsigned
	w Khaki $TB/last_btcmpr0_store_s  hex
	w Khaki $TB/btcmpr1_store_count_s unsigned
	w Khaki $TB/last_btcmpr1_store_s  hex
	w Khaki $TB/pwm_edge_count_s      unsigned
	w Khaki $TB/divarr_store_count_s  unsigned
	w Khaki $TB/remarr_store_count_s  unsigned
	w Khaki $TB/runtime_div_store_s   unsigned
	w Khaki $TB/runtime_rem_store_s   unsigned
	w Khaki $TB/last_runtime_div_s    hex
	w Khaki $TB/last_runtime_rem_s    hex

	wave_look
}

wave_final
