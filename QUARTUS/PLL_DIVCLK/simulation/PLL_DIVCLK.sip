set_global_assignment -entity "PLL_DIVCLK" -library "lib_PLL_DIVCLK" -name IP_TOOL_NAME "Qsys"
set_global_assignment -entity "PLL_DIVCLK" -library "lib_PLL_DIVCLK" -name IP_TOOL_VERSION "21.1"
set_global_assignment -entity "PLL_DIVCLK" -library "lib_PLL_DIVCLK" -name IP_TOOL_ENV "Qsys"
set_global_assignment -library "lib_PLL_DIVCLK" -name SPD_FILE [file join $::quartus(sip_path) "../PLL_DIVCLK.spd"]
set_global_assignment -library "lib_PLL_DIVCLK" -name MISC_FILE [file join $::quartus(sip_path) "../../PLL_DIVCLK.qsys"]

set_global_assignment -library "lib_PLL_DIVCLK" -name MISC_FILE [file join $::quartus(sip_path) "PLL_DIVCLK.vhd"]
set_global_assignment -library "lib_PLL_DIVCLK" -name MISC_FILE [file join $::quartus(sip_path) "submodules/PLL_DIVCLK_pll_0.vho"]
