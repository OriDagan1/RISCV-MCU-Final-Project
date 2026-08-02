#=============================================================================
# Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
# Compile every source of the RV32IM MCU into the "work" library.
#
# Run from this directory:    do compile.do
#=============================================================================
# Run this from SIM/RV32IMscMCU - the paths below are relative to it.
#
# Deliberately NOT [file normalize]d: if you reach the project through an
# ASCII directory junction (see the note at the bottom of this file),
# normalizing would resolve it back to the real path and ModelSim cannot
# open a path containing non-ASCII characters.
set DUT  ../../DUT/RV32IMscMCU
set TB   ../../TB/RV32IMscMCU

if {[file exists work]} { vdel -all }
vlib work
vmap work work

# Order matters: packages first, then leaf modules, then the core, then the TBs
foreach f [list \
	$DUT/cond_compilation_package.vhd \
	$DUT/const_package.vhd            \
	$DUT/aux_package.vhd              \
	$DUT/MULT.vhd                     \
	$DUT/SUBTRACTOR.vhd               \
	$DUT/DIV.vhd                      \
	$DUT/CDC_SYNC.vhd                 \
	$DUT/DIV_ACCEL.vhd                \
	$DUT/CONTROL.VHD                  \
	$DUT/IDECODE.VHD                  \
	$DUT/IFETCH.VHD                   \
	$DUT/EXECUTE.VHD                  \
	$DUT/DMEMORY.VHD                  \
	$DUT/RV32I_CORE.vhd               \
	$TB/tb_RV32I.vhd                  \
	$TB/tb_divider.vhd                \
	$TB/tb_cdc_sync.vhd               \
	$TB/tb_div_accel.vhd              ] {
	echo "vcom $f"
	if {[catch {vcom -2008 -quiet $f} msg]} {
		echo "COMPILE FAILED: $f"
		echo $msg
		return
	}
}
echo "-------------------------------------------------"
echo " compile OK"
echo "-------------------------------------------------"

# NOTE: PLL.vhd is deliberately NOT compiled. The ALTPLL it wraps is a
# Cyclone II megafunction and is not supported on the Cyclone V of the
# DE10-Standard; RV32I_CORE derives MCLK from clk_i with a toggle flip-flop
# instead. The file is kept in DUT/ only for reference.
#
# NOTE: ModelSim 20.1 cannot open a path containing non-ASCII characters,
# and the project lives under a Hebrew directory name. Reach it through an
# ASCII directory junction instead (one-off, no admin rights, no copying):
#
#   mklink /J C:\Users\oripa\rv32im "C:\Users\oripa\Documents\<hebrew>\RISC-V MCU Project"
#
# then work from C:\Users\oripa\rv32im\SIM\RV32IMscMCU. Remove it later with
# "rmdir C:\Users\oripa\rv32im", which deletes only the link.
