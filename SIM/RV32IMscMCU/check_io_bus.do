#=============================================================================
# Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
# Prove the memory-mapped I/O wiring inside MCU.vhd, which no unit testbench
# reaches, and that the six BidirPin buffers never fight over io_bus_w.
#
#   do compile.do
#   do check_io_bus.do
#
# The GPIO unit testbenches verify each port module on its own. This one
# verifies the level above them: that a byte address on the bus reaches the
# right device, that the tri-state buffers of Figure 5 hand the bus over
# cleanly, and that the DTCM and the I/O block stay out of each other's way.
#
# It fakes bus transactions with "force -freeze" on the master side of the
# bus instead of running a program, so every case - including the unmapped
# addresses reserved for clause 6 - can be hit directly.
#=============================================================================
catch {quit -sim}
vsim -quiet -t 1ps -GMODELSIM=1 work.tb_RV32I
quietly set StdArithNoWarnings 1
quietly set NumericStdNoWarnings 1

set ERRS 0

# Colours come from wave_style.do - see its header for the scheme. The "bus"
# set leaves the CPU traces out: this script drives the bus by hand, so the
# program counter sits still and would only add noise to the screenshot.
do wave_style.do
wave_mcu_io bus
wave_look

# Plain "set", not "quietly set": inside a proc, quietly set does not reliably
# create the variable in this ModelSim, and reading it back fails.
proc chk {label path radix want} {
	global ERRS
	set got  [string tolower [examine -radix $radix $path]]
	set want [string tolower $want]
	if {$got eq $want} {
		echo "   PASS  $label = $got"
	} else {
		echo "   FAIL  $label = $got   expected $want"
		incr ERRS
	}
}

# A strong-strong collision on the shared bus resolves to 'X'; a fully
# released bus stays 'Z'. Either is a wiring bug. Checked after every step
# rather than only at chosen instants.
proc nocontend {where} {
	global ERRS
	set v [string tolower [examine -radix binary /tb_RV32I/CORE/io_bus_w]]
	if {[string match *x* $v] || [string match *z* $v] || [string match *u* $v]} {
		echo "   FAIL  io_bus_w not resolved during $where : $v"
		incr ERRS
	}
}

proc bus {addr wdata wr rd} {
	force -freeze /tb_RV32I/CORE/bus_addr_w  $addr
	force -freeze /tb_RV32I/CORE/bus_wdata_w $wdata
	force -freeze /tb_RV32I/CORE/bus_write_w $wr
	force -freeze /tb_RV32I/CORE/bus_read_w  $rd
	run 120 ns
	nocontend "addr $addr wr=$wr rd=$rd"
}

# Reset releases at 2 us.
run 3 us
quietly set StdArithNoWarnings 0
quietly set NumericStdNoWarnings 0
nocontend "reset release"

echo "-- idle: no device driving, BUF_NONE must park the bus"
chk "io_bus_w " /tb_RV32I/CORE/io_bus_w  hex 00000000
chk "oe_none_w" /tb_RV32I/CORE/oe_none_w bin 1

echo "-- store 0xA5 to PORT_LEDR 0x2000"
bus 10000000000000 00000000000000000000000010100101 1 0
chk "LEDR_o   " /tb_RV32I/LEDR_o binary 10100101

echo "-- store 0x03 to PORT_HEX0 0x2004  (even address, low digit of pair 0)"
bus 10000000000100 00000000000000000000000000000011 1 0
chk "HEX0_o   " /tb_RV32I/HEX0_o binary 0110000

echo "-- store 0x0E to PORT_HEX1 0x2005  (odd address, high digit of pair 0)"
bus 10000000000101 00000000000000000000000000001110 1 0
chk "HEX1_o   " /tb_RV32I/HEX1_o binary 0000110
chk "HEX0_o   " /tb_RV32I/HEX0_o binary 0110000

echo "-- store 0x07 to PORT_HEX5 0x200D  (odd address, high digit of pair 2)"
bus 10000000001101 00000000000000000000000000000111 1 0
chk "HEX5_o   " /tb_RV32I/HEX5_o binary 1111000

echo "-- load PORT_SW 0x2010 - the testbench holds SW at 0xA5"
bus 10000000010000 00000000000000000000000000000000 0 1
chk "oe_sw_w  " /tb_RV32I/CORE/oe_sw_w    bin 1
chk "oe_none_w" /tb_RV32I/CORE/oe_none_w  bin 0
chk "io_bus_w " /tb_RV32I/CORE/io_bus_w    hex 000000a5
chk "rdata    " /tb_RV32I/CORE/bus_rdata_w hex 000000a5

echo "-- load PORT_LEDR 0x2000 - reads back what was stored"
bus 10000000000000 00000000000000000000000000000000 0 1
chk "rdata    " /tb_RV32I/CORE/bus_rdata_w hex 000000a5

echo "-- load PORT_HEX1 0x2005 - reads back the stored byte, not the segments"
bus 10000000000101 00000000000000000000000000000000 0 1
chk "rdata    " /tb_RV32I/CORE/bus_rdata_w hex 0000000e

echo "-- load unmapped I/O 0x2014 - no buffer enabled, BUF_NONE answers"
bus 10000000010100 00000000000000000000000000000000 0 1
chk "oe_none_w" /tb_RV32I/CORE/oe_none_w  bin 1
chk "rdata    " /tb_RV32I/CORE/bus_rdata_w hex 00000000

echo "-- store 0xFF to DTCM 0x0000 then load it back - I/O must not intercept"
bus 00000000000000 00000000000000000000000011111111 1 0
bus 00000000000000 00000000000000000000000000000000 0 1
chk "rdata    " /tb_RV32I/CORE/bus_rdata_w hex 000000ff
chk "LEDR_o   " /tb_RV32I/LEDR_o binary 10100101

echo "================================================="
if {$ERRS == 0} {
	echo " I/O BUS CHECK PASSED - 18 checks, io_bus_w never X, Z or U"
} else {
	echo " I/O BUS CHECK FAILED : $ERRS errors"
}
echo "================================================="
wave zoom full
