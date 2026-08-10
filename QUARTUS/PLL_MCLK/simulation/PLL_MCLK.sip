set_global_assignment -entity "PLL_MCLK" -library "lib_PLL_MCLK" -name IP_TOOL_NAME "Qsys"
set_global_assignment -entity "PLL_MCLK" -library "lib_PLL_MCLK" -name IP_TOOL_VERSION "21.1"
set_global_assignment -entity "PLL_MCLK" -library "lib_PLL_MCLK" -name IP_TOOL_ENV "Qsys"
set_global_assignment -library "lib_PLL_MCLK" -name SPD_FILE [file join $::quartus(sip_path) "../PLL_MCLK.spd"]
set_global_assignment -library "lib_PLL_MCLK" -name MISC_FILE [file join $::quartus(sip_path) "../../PLL_MCLK.qsys"]

set_global_assignment -library "lib_PLL_MCLK" -name MISC_FILE [file join $::quartus(sip_path) "PLL_MCLK.vhd"]
set_global_assignment -library "lib_PLL_MCLK" -name MISC_FILE [file join $::quartus(sip_path) "submodules/PLL_MCLK_pll_0.vho"]
