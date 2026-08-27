#=============================================================================
# Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
# Shared wave-window styling for the MCU simulations.
#
# Sourced by run_gpio.do, check_io_bus.do and run_benchmark.do:
#
#   do wave_style.do
#   wave_look
#   wave_mcu_io app          ;# or:  wave_mcu_io bus
#
# The colours are not decoration. Each peripheral has one signature colour
# carried all the way through - chip select, output enable, and the pin
# itself - so a single glance follows a transaction from the address decode
# to the board. Writes are magenta, reads are green-yellow, the address is
# white, and the shared I/O bus is yellow because it is the thing the whole
# GPIO design exists to arbitrate.
#
#   Red            reset
#   Violet family  the three clock domains
#   Sky blue       CPU program counter and instruction
#   White          address bus
#   Magenta        write strobe and write data
#   Green-yellow   read strobe and read data
#   Spring green   PORT_LEDR      decode -> enable -> pin
#   Gold           PORT_HEX0 / HEX1
#   Orange         PORT_HEX2 / HEX3
#   Coral          PORT_HEX4 / HEX5
#   Cyan           PORT_SW        the only clause-5 input device
#   DodgerBlue     PORT_PB        the first clause-6 device, KEY3..KEY1
#   MediumOrchid   Basic Timer    BTIF chip selects, oe_bt_w, its four bus
#                  registers, btcnt_w and btifg_w, and PWMout_o
#   Tomato family  the three PORT_PB interrupt request pulses
#   MediumPurple   bt_irq_w, the Basic Timer's edge-detected pulse
#   SteelBlue      the interrupt controller: cs_ic_w, oe_ic_w, intr_w,
#                  gie_w, inta_n_w and INTC's internal IE/IFG/TYPE state
#   Salmon         BUF_NONE, the buffer that parks the bus when idle
#   Yellow         io_bus_w, the shared tri-state bus of Figure 5
#
# Within a display pair the low digit is the saturated shade and the high
# digit the lighter one, so HEX0 and HEX1 stay apart even though they share
# one chip select and one interface instance.
#=============================================================================

# Plain "set" inside procs: "quietly set" does not reliably create a readable
# local in this ModelSim, and the variable then cannot be read back.

#-----------------------------------------------------------------------------
# One signal. Colours the trace and the name in the pathname pane together.
#-----------------------------------------------------------------------------
proc w {color path {radix ""}} {
	if {$radix eq ""} {
		add wave -color $color -itemcolor $color $path
	} else {
		add wave -color $color -itemcolor $color -radix $radix $path
	}
}

#-----------------------------------------------------------------------------
# A section heading in the wave window, tinted to match the group below it.
#-----------------------------------------------------------------------------
proc wdiv {color label} {
	add wave -divider -color $color -height 24 $label
}

#-----------------------------------------------------------------------------
# Window geometry and spacing. Kept apart from the signal list so it can be
# reapplied after a re-run without rebuilding the waves.
#
# signalnamewidth 1 shows the leaf name only - "cs_ledr_w" rather than
# "/tb_RV32I/CORE/cs_ledr_w". Set it to 0 if a screenshot needs to prove
# which level of hierarchy a signal lives at.
#-----------------------------------------------------------------------------
proc wave_look {} {
	configure wave -signalnamewidth 1
	configure wave -namecolwidth 210
	configure wave -valuecolwidth 110
	configure wave -justifyvalue left
	configure wave -rowmargin 6
	configure wave -childrowmargin 3
	configure wave -timelineunits us
}

#-----------------------------------------------------------------------------
# The standard memory-mapped I/O wave set.
#
#   mode "app"   running a real program: include the CPU and the counter
#   mode "bus"   check_io_bus.do forces the bus by hand, so the CPU is idle
#                and its traces would only be noise
#-----------------------------------------------------------------------------
proc wave_mcu_io {mode} {
	catch {delete wave *}

	set C_LEDR  SpringGreen
	set C_HEX01 Gold
	set C_HEX23 Orange
	set C_HEX45 Coral
	set C_SW    Cyan
	set C_PB    DodgerBlue
	set C_BT    MediumOrchid
	set C_IC    SteelBlue
	set C_NONE  Salmon
	set C_BUS   Yellow

	wdiv Red {RESET AND CLOCKS}
	w Red      /tb_RV32I/rst_i
	w #7F8C99  /tb_RV32I/clk_i
	w Violet   /tb_RV32I/CORE/mclk_w
	w Orchid   /tb_RV32I/CORE/divclk_w
	w #B39DDB  /tb_RV32I/CORE/smclk_w

	if {$mode eq "app"} {
		wdiv SkyBlue {CPU}
		w SkyBlue   /tb_RV32I/pc_o          hex
		w #A8D8FF   /tb_RV32I/instruction_o hex
		w Turquoise /tb_RV32I/CORE/CPU/ID/RF_q(5) unsigned
	}

	wdiv White {DATA BUS - MASTER SIDE}
	w White       /tb_RV32I/CORE/bus_addr_w  hex
	w Magenta     /tb_RV32I/CORE/bus_write_w
	w Magenta     /tb_RV32I/CORE/bus_wdata_w hex
	w GreenYellow /tb_RV32I/CORE/bus_read_w
	w GreenYellow /tb_RV32I/CORE/bus_rdata_w hex
	w Khaki       /tb_RV32I/CORE/io_sel_w

	wdiv Turquoise {ADDRESS DECODE - ONE HOT}
	w $C_LEDR  /tb_RV32I/CORE/cs_ledr_w
	w $C_HEX01 /tb_RV32I/CORE/cs_hex0_1_w
	w $C_HEX23 /tb_RV32I/CORE/cs_hex2_3_w
	w $C_HEX45 /tb_RV32I/CORE/cs_hex4_5_w
	w $C_SW    /tb_RV32I/CORE/cs_sw_w
	w $C_PB    /tb_RV32I/CORE/cs_pb_w
	w $C_BT    /tb_RV32I/CORE/cs_btctl_w
	w $C_BT    /tb_RV32I/CORE/cs_btcmpr0_w
	w $C_BT    /tb_RV32I/CORE/cs_btcmpr1_w
	w $C_BT    /tb_RV32I/CORE/cs_btcapr_w
	w $C_IC    /tb_RV32I/CORE/cs_ic_w

	wdiv $C_BUS {BIDIRPIN ENABLES AND THE SHARED BUS}
	w $C_LEDR  /tb_RV32I/CORE/oe_ledr_w
	w $C_HEX01 /tb_RV32I/CORE/oe_hex0_1_w
	w $C_HEX23 /tb_RV32I/CORE/oe_hex2_3_w
	w $C_HEX45 /tb_RV32I/CORE/oe_hex4_5_w
	w $C_SW    /tb_RV32I/CORE/oe_sw_w
	w $C_PB    /tb_RV32I/CORE/oe_pb_w
	w $C_BT    /tb_RV32I/CORE/oe_bt_w
	w $C_IC    /tb_RV32I/CORE/oe_ic_w
	w $C_NONE  /tb_RV32I/CORE/oe_none_w
	w $C_BUS   /tb_RV32I/CORE/io_bus_w hex

	# The four registers BTIF exposes to the bus, plus btcnt_w (not bus
	# addressable, but the running count that makes the others meaningful).
	wdiv $C_BT {BASIC TIMER REGISTERS}
	w $C_BT    /tb_RV32I/CORE/btctl1_w  hex
	w $C_BT    /tb_RV32I/CORE/btctl2_w  hex
	w $C_BT    /tb_RV32I/CORE/btcmpr0_w hex
	w $C_BT    /tb_RV32I/CORE/btcmpr1_w hex
	w $C_BT    /tb_RV32I/CORE/btcapr_w  hex
	w $C_BT    /tb_RV32I/CORE/btcnt_w   hex

	wdiv $C_SW {PINS}
	w $C_SW    /tb_RV32I/SW_i     hex
	w $C_PB    /tb_RV32I/KEY_i    binary
	w $C_BT    /tb_RV32I/PWMout_o
	w $C_LEDR  /tb_RV32I/LEDR_o binary
	# Low digit saturated, high digit lighter, so the two halves of a pair
	# stay apart even though one instance and one chip select drive both.
	w Gold     /tb_RV32I/HEX0_o binary
	w #FFE066  /tb_RV32I/HEX1_o binary
	w Orange   /tb_RV32I/HEX2_o binary
	w #FFBB70  /tb_RV32I/HEX3_o binary
	w Coral    /tb_RV32I/HEX4_o binary
	w #FFA694  /tb_RV32I/HEX5_o binary

	# No consumer yet - see the notes at IOPB and BTIF in MCU.vhd - but
	# observable here so a key release or a timer event is visible the
	# instant its port drives it.
	wdiv Tomato {INTERRUPT SOURCES}
	w Tomato    /tb_RV32I/CORE/key1_irq_w
	w OrangeRed /tb_RV32I/CORE/key2_irq_w
	w Crimson   /tb_RV32I/CORE/key3_irq_w
	w $C_BT     /tb_RV32I/CORE/btifg_w
	w MediumPurple /tb_RV32I/CORE/bt_irq_w

	# gie_w and inta_n_w are the real loop as of step 4 of the CPU protocol -
	# CORE's gie_o and inta_n_o, wired into INTC's gie_i and inta_n_i in
	# MCU.vhd - so intr_w can now genuinely rise once software sets gp[0].
	# int_state_q is CONTROL's own three-state machine (S_IDLE, S_CYCLE1,
	# S_CYCLE2): grouped here rather than under CPU above because it only
	# means anything alongside intr_w, gie_w and inta_n_w.
	wdiv $C_IC {INTERRUPT CONTROLLER}
	w $C_IC    /tb_RV32I/CORE/intr_w
	w $C_IC    /tb_RV32I/CORE/gie_w
	w $C_IC    /tb_RV32I/CORE/inta_n_w
	w $C_IC    /tb_RV32I/CORE/CPU/CTL/int_state_q
	w $C_IC    /tb_RV32I/CORE/INTC/ie_q   binary
	w $C_IC    /tb_RV32I/CORE/INTC/irq_q  binary
	w $C_IC    /tb_RV32I/CORE/INTC/ifg_w  binary
	w $C_IC    /tb_RV32I/CORE/INTC/type_w hex
}

#-----------------------------------------------------------------------------
# The CPU-centric set for the RV32IM benchmark, where there is no I/O at all
# and the division accelerator is the interesting part.
#-----------------------------------------------------------------------------
proc wave_cpu {} {
	catch {delete wave *}
	set CPU /tb_RV32I/CORE/CPU

	wdiv Red {RESET AND CLOCKS}
	w Red      /tb_RV32I/rst_i
	w #7F8C99  /tb_RV32I/clk_i
	w Violet   /tb_RV32I/CORE/mclk_w
	w Orchid   /tb_RV32I/CORE/divclk_w
	w #B39DDB  /tb_RV32I/CORE/smclk_w

	wdiv SkyBlue {CPU}
	w SkyBlue   /tb_RV32I/pc_o          hex
	w #A8D8FF   /tb_RV32I/instruction_o hex
	w Turquoise /tb_RV32I/mclk_cnt_o    unsigned

	wdiv GreenYellow {WRITE-BACK}
	w GreenYellow /tb_RV32I/RegWrite_ctrl_o
	w GreenYellow /tb_RV32I/write_data_o hex

	wdiv Gold {DIVISION ACCELERATOR}
	w Gold      $CPU/div_op_w
	w Coral     $CPU/div_busy_w
	w #FFE066   $CPU/div_ain_w  unsigned
	w #FFBB70   $CPU/div_bin_w  unsigned
	w SpringGreen $CPU/div_quot_w unsigned
	w Cyan      $CPU/div_rsdu_w unsigned
	w Turquoise $CPU/div_res_w  unsigned

	wdiv White {DTCM}
	w Magenta /tb_RV32I/MemWrite_ctrl_o
	w White   /tb_RV32I/dtcm_addr_o    hex
	w Magenta /tb_RV32I/dtcm_data_wr_o hex
}
