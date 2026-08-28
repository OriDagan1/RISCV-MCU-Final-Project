set_global_assignment -entity "PLL_SMCLK" -library "lib_PLL_SMCLK" -name IP_TOOL_NAME "Qsys"
set_global_assignment -entity "PLL_SMCLK" -library "lib_PLL_SMCLK" -name IP_TOOL_VERSION "21.1"
set_global_assignment -entity "PLL_SMCLK" -library "lib_PLL_SMCLK" -name IP_TOOL_ENV "Qsys"
set_global_assignment -library "lib_PLL_SMCLK" -name SPD_FILE [file join $::quartus(sip_path) "../PLL_SMCLK.spd"]
set_global_assignment -library "lib_PLL_SMCLK" -name MISC_FILE [file join $::quartus(sip_path) "../../PLL_SMCLK.qsys"]

set_global_assignment -library "lib_PLL_SMCLK" -name MISC_FILE [file join $::quartus(sip_path) "PLL_SMCLK.vhd"]
set_global_assignment -library "lib_PLL_SMCLK" -name MISC_FILE [file join $::quartus(sip_path) "submodules/PLL_SMCLK_pll_0.vho"]
