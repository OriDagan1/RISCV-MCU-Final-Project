#=============================================================================
# Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
# Pin assignments for MCU.vhd on the DE10-Standard (5CSXFC6D6F31C6).
#
# Run from the Quartus Tcl Console (View > Utility Windows > Tcl Console),
# with the project open. The console starts in the project directory, so if
# the .qpf sits in QUARTUS/ alongside this file:
#
#     source pins.tcl
#
# and otherwise give the path to it relative to the project directory.
#
# Run Analysis & Elaboration FIRST. set_location_assignment does not check
# that a port exists, so a typo here is accepted silently; elaborating first
# means the Pin Planner can show you all 71 rows bound to real ports.
#
# Pin numbers are from DE10-Standard_User_manual.pdf in the repository root:
#   Table 3-5  clock inputs        Table 3-8  LEDs
#   Table 3-6  slide switches      Table 3-9  seven-segment displays
#   Table 3-7  push-buttons        Table 3-11 expansion header
#
# The eight expansion-header pins at the bottom are a choice, not the board's:
# any GPIO pin works. Move them if the header is wired for something else.
#=============================================================================

#-----------------------------------------------------------------------------
# Clock and reset
#-----------------------------------------------------------------------------
set_location_assignment PIN_AF14 -to clk_i          ;# CLOCK_50
set_location_assignment PIN_AJ4  -to rst_i          ;# KEY[0], system reset

#-----------------------------------------------------------------------------
# Slide switches - PORT_SW 0x2010. Clause 5 maps SW7..SW0 only.
#-----------------------------------------------------------------------------
set_location_assignment PIN_AB30 -to SW_i[0]
set_location_assignment PIN_Y27  -to SW_i[1]
set_location_assignment PIN_AB28 -to SW_i[2]
set_location_assignment PIN_AC30 -to SW_i[3]
set_location_assignment PIN_W25  -to SW_i[4]
set_location_assignment PIN_V25  -to SW_i[5]
set_location_assignment PIN_AC28 -to SW_i[6]
set_location_assignment PIN_AD30 -to SW_i[7]

#-----------------------------------------------------------------------------
# Push-buttons - PORT_PB 0x2014. KEY3..KEY1 only; KEY0 is rst_i above.
# Active low, hardware debounced on the board.
#-----------------------------------------------------------------------------
set_location_assignment PIN_AK4  -to KEY_i[1]
set_location_assignment PIN_AA14 -to KEY_i[2]
set_location_assignment PIN_AA15 -to KEY_i[3]

#-----------------------------------------------------------------------------
# Red LEDs - PORT_LEDR 0x2000. Clause 5 maps LEDR7..LEDR0 only.
#-----------------------------------------------------------------------------
set_location_assignment PIN_AA24 -to LEDR_o[0]
set_location_assignment PIN_AB23 -to LEDR_o[1]
set_location_assignment PIN_AC23 -to LEDR_o[2]
set_location_assignment PIN_AD24 -to LEDR_o[3]
set_location_assignment PIN_AG25 -to LEDR_o[4]
set_location_assignment PIN_AF25 -to LEDR_o[5]
set_location_assignment PIN_AE24 -to LEDR_o[6]
set_location_assignment PIN_AF24 -to LEDR_o[7]

#-----------------------------------------------------------------------------
# Seven-segment displays. Vectors are g f e d c b a, active low.
# HEX0 0x2004  HEX1 0x2005  HEX2 0x2008  HEX3 0x2009  HEX4 0x200C  HEX5 0x200D
#-----------------------------------------------------------------------------
set_location_assignment PIN_W17  -to HEX0_o[0]
set_location_assignment PIN_V18  -to HEX0_o[1]
set_location_assignment PIN_AG17 -to HEX0_o[2]
set_location_assignment PIN_AG16 -to HEX0_o[3]
set_location_assignment PIN_AH17 -to HEX0_o[4]
set_location_assignment PIN_AG18 -to HEX0_o[5]
set_location_assignment PIN_AH18 -to HEX0_o[6]

set_location_assignment PIN_AF16 -to HEX1_o[0]
set_location_assignment PIN_V16  -to HEX1_o[1]
set_location_assignment PIN_AE16 -to HEX1_o[2]
set_location_assignment PIN_AD17 -to HEX1_o[3]
set_location_assignment PIN_AE18 -to HEX1_o[4]
set_location_assignment PIN_AE17 -to HEX1_o[5]
set_location_assignment PIN_V17  -to HEX1_o[6]

set_location_assignment PIN_AA21 -to HEX2_o[0]
set_location_assignment PIN_AB17 -to HEX2_o[1]
set_location_assignment PIN_AA18 -to HEX2_o[2]
set_location_assignment PIN_Y17  -to HEX2_o[3]
set_location_assignment PIN_Y18  -to HEX2_o[4]
set_location_assignment PIN_AF18 -to HEX2_o[5]
set_location_assignment PIN_W16  -to HEX2_o[6]

set_location_assignment PIN_Y19  -to HEX3_o[0]
set_location_assignment PIN_W19  -to HEX3_o[1]
set_location_assignment PIN_AD19 -to HEX3_o[2]
set_location_assignment PIN_AA20 -to HEX3_o[3]
set_location_assignment PIN_AC20 -to HEX3_o[4]
set_location_assignment PIN_AA19 -to HEX3_o[5]
set_location_assignment PIN_AD20 -to HEX3_o[6]

set_location_assignment PIN_AD21 -to HEX4_o[0]
set_location_assignment PIN_AG22 -to HEX4_o[1]
set_location_assignment PIN_AE22 -to HEX4_o[2]
set_location_assignment PIN_AE23 -to HEX4_o[3]
set_location_assignment PIN_AG23 -to HEX4_o[4]
set_location_assignment PIN_AF23 -to HEX4_o[5]
set_location_assignment PIN_AH22 -to HEX4_o[6]

set_location_assignment PIN_AF21 -to HEX5_o[0]
set_location_assignment PIN_AG21 -to HEX5_o[1]
set_location_assignment PIN_AF20 -to HEX5_o[2]
set_location_assignment PIN_AG20 -to HEX5_o[3]
set_location_assignment PIN_AE19 -to HEX5_o[4]
set_location_assignment PIN_AF19 -to HEX5_o[5]
set_location_assignment PIN_AB21 -to HEX5_o[6]

#-----------------------------------------------------------------------------
# Basic Timer (Fig.7) - the board has no dedicated pins for these, so they
# go on the 2x20 expansion header of clause 4.
#-----------------------------------------------------------------------------
set_location_assignment PIN_W15  -to PWMout_o       ;# GPIO[0], header pin 1
set_location_assignment PIN_AK2  -to CAPIN1_i       ;# GPIO[1], header pin 2
set_location_assignment PIN_Y16  -to CAPIN2_i       ;# GPIO[2], header pin 3

#-----------------------------------------------------------------------------
# The five std_logic observation outputs. These survive G_SIGTAP=0 because
# std_logic has no null form, so they need pins whatever SIGTAP says.
# smclk_o especially must keep one: it is the only load on PLL_SMCLK, and
# without it Quartus trims that PLL out of the design and the PPA report.
#-----------------------------------------------------------------------------
set_location_assignment PIN_AK3  -to smclk_o           ;# GPIO[3], scope point
set_location_assignment PIN_AJ1  -to RegWrite_ctrl_o   ;# GPIO[4]
set_location_assignment PIN_AJ2  -to MemWrite_ctrl_o   ;# GPIO[5]
set_location_assignment PIN_AH2  -to Branch_ctrl_o     ;# GPIO[6]
set_location_assignment PIN_AH3  -to brTaken_o         ;# GPIO[7]

#-----------------------------------------------------------------------------
# I/O standard. 3.3-V LVTTL everywhere. Note the slide switches are listed
# in the manual as "Depend on JP3"; the default jumper position is 3.3 V,
# which is what this assumes.
#-----------------------------------------------------------------------------
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to *

#-----------------------------------------------------------------------------
# Protect the board: the Cyclone V default drives unused pins to ground, and
# on this board the expansion header, HPS DDR3, audio and video codecs are
# all physically wired to something.
#-----------------------------------------------------------------------------
set_global_assignment -name RESERVE_ALL_UNUSED_PINS "AS INPUT TRI-STATED"

# Write everything into the .qsf now rather than at the next save.
export_assignments

post_message "pins.tcl: 71 pin assignments applied, unused pins tri-stated."
