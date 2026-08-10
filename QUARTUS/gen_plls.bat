@echo off
REM ===========================================================================
REM Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
REM Regenerate the three clock PLLs and the matching VHDL constants.
REM
REM Run from this directory:   gen_plls.bat
REM
REM Change the frequencies in gen_plls.tcl first - that file is the single
REM source of truth, and this script propagates it to both the IP and
REM DUT/RV32IMscMCU/clk_config_package.vhd.
REM ===========================================================================
setlocal
set QSYS=C:\intelFPGA_lite\21.1\quartus\sopc_builder\bin

echo.
echo [1/2] building the .qsys files and clk_config_package.vhd
call "%QSYS%\qsys-script.exe" --script=gen_plls.tcl
if errorlevel 1 goto :fail

echo.
echo [2/2] generating IP  (this takes a minute or two per PLL)
for %%P in (PLL_MCLK PLL_DIVCLK PLL_SMCLK) do (
    echo    %%P
    call "%QSYS%\qsys-generate.exe" %%P.qsys --synthesis=VHDL --simulation=VHDL --part=5CSXFC6D6F31C6
    if errorlevel 1 goto :fail
)

echo.
echo done. Recompile in ModelSim with:  do compile.do
goto :eof

:fail
echo.
echo GENERATION FAILED - see the messages above.
exit /b 1
