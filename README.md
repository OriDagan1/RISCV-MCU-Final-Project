# RV32IM MCU — running the simulation

BGU 361-1-4693, final project. This is the short version: how to run a
benchmark in ModelSim, and where the GPIO block plugs in.

---

## One-time setup

**ModelSim cannot open a path containing Hebrew characters.** The project lives
under `Documents\לימודים\מעבדת ארכיטקטורה\`, so ModelSim has to reach it
through an ASCII directory junction. Make one once (no admin rights, nothing is
copied — it is the same folder under a second name):

```
mklink /J C:\Users\<you>\rv32im "C:\Users\<you>\Documents\לימודים\מעבדת ארכיטקטורה\RISC-V MCU Project"
```

Keep editing and committing in the real folder. Only ModelSim uses the junction.
Remove it later with `rmdir C:\Users\<you>\rv32im` — that deletes just the link.

---

## Run a benchmark

In the ModelSim transcript:

```tcl
cd C:/Users/<you>/rv32im/SIM/RV32IMscMCU
do compile.do
do run_benchmark.do
```

That's it. `compile.do` builds everything into `work`; `run_benchmark.do` loads
the program, runs it, checks the result against the golden model, and prints
the data memory.

### What success looks like

```
 compile OK
 TCM = 8 KiB, image set = M9K
 PC               = 0068
 instruction      = 00000063
 cycles to finish = 340
 compared 1024 words, 0 mismatches
 *** DTCM MATCHES THE GOLDEN MODEL ***

  0:   1   2   3   4   5   6   7   8      arr1
  8:   8   7   6   5   4   3   2   1      arr2
 16:   0   0   0   0   1   2   3   8      div
 24:   8  14  18  20  20  18  14   8      mul
 32:   1   2   3   4   1   0   1   0      rem
```

`instruction = 00000063` with a frozen PC means the program reached its
`finish: beq x0,x0,finish` self-loop. If `cycles to finish` says `NOT REACHED`,
raise `RUN_TIME` at the top of the script.

### Switching benchmark

Edit line 27 of `run_benchmark.do` — forward slashes, point at the folder that
*contains* `bin/`:

```tcl
quietly set APP "C:/Users/<you>/Documents/Benchmark_Apps/test3/RV32IM"
```

Then `do run_benchmark.do` again. No need to recompile.

### Unit testbenches

```tcl
vsim work.tb_divider                ; run -all   # the divider, 4618 divisions
vsim work.tb_cdc_sync               ; run -all   # the clock domain crossing
vsim work.tb_div_accel              ; run -all   # the accelerator handshake
vsim work.tb_SevenSegmentEncoder    ; run -all   # the hex to segment table
vsim work.tb_GPIO_AddressDecoder    ; run -all   # all 32768 input combinations
vsim work.tb_GPIO_LEDR_Interface    ; run -all   # PORT_LEDR
vsim work.tb_GPIO_SW_Interface      ; run -all   # PORT_SW
vsim work.tb_GPIO_HEX_Pair_Interface; run -all   # one pair of displays
```

Each ends with `ALL TESTS PASSED` or an equivalent `PASSED` line.

---

## Memory-mapped I/O

`MCU.vhd` is the top level and owns everything outside the CPU: clocks, the
DTCM, the address decode and the GPIO. The CPU is a bus master — it drives a
byte address and takes read data back, and has no idea which device answers.
Nothing in the core knows that the GPIO exists.

### Address map (Figure 2)

14-bit byte address. Bit 13 is the DTCM / I/O select:

```
0x0000 - 0x1FFF   DTCM, 8 KiB
0x2000 - 0x3FFF   memory-mapped I/O
```

```
PORT_LEDR  0x2000        PORT_SW  0x2010
HEX0 0x2004   HEX1 0x2005   HEX2 0x2008
HEX3 0x2009   HEX4 0x200C   HEX5 0x200D
```

Clause 5 maps `LEDR7..LEDR0` and `SW7..SW0` only — eight bits each, although
the board carries ten of each. `LEDR9`, `LEDR8`, `SW9` and `SW8` are unused.

### How it is wired

```
bus_addr_w ──> GPIO_AddressDecoder ──> five one-hot chip selects
                                        │                    (each AND bus_read_w
                                        │                     = one output enable)
                                        v
   IOLEDR   GPIO_LEDR_Interface  ──> BUF_LEDR  ──┐   LEDR_o
   IOSW     GPIO_SW_Interface    ──> BUF_SW    ──┤   SW_i
   IOHEX01  GPIO_HEX_Pair_Interface > BUF_HEX01 ─┤   HEX0_o HEX1_o
   IOHEX23  GPIO_HEX_Pair_Interface > BUF_HEX23 ─┤   HEX2_o HEX3_o
   IOHEX45  GPIO_HEX_Pair_Interface > BUF_HEX45 ─┤   HEX4_o HEX5_o
                     zeros ───────> BUF_NONE   ──┤
                                                 │
                                             io_bus_w   <── the shared I/O bus
                    bus_rdata_w <── io_bus_w when io_sel_w else dtcm_q_w
```

Every `BUF_*` is an instance of the supplied `BidirPin.vhd`, the tri-state
buffer Figure 5 draws between each port and the data bus.

Four things worth knowing:

- **One instance serves two displays.** Inside a pair the two addresses differ
  in bit 0 only, so the decoder gives the pair one chip select and
  `bus_addr_w(0)` picks the digit.
- **`io_bus_w` genuinely has six drivers** and relies on `std_logic`
  resolution — it must never be assigned anywhere else. The enables are
  one-hot: the five chip selects are one-hot by construction, and
  `oe_none_w` is their NOR, so exactly one buffer drives at any instant and
  the rest sit at `'Z'`. Cyclone V has no internal tri-state, so Quartus
  resolves the six buffers back into a multiplexer during synthesis; the `'Z'`
  only exists in simulation and in the figure.
- **`BUF_NONE` parks the bus at zero** whenever no port is selected. Without
  it an unmapped I/O address would leave `io_bus_w` floating at `'Z'` and
  propagate X into the register file. With it, unmapped I/O reads as zero.
- **GPIO registers capture on the FALLING edge of MCLK**, as does the DTCM
  (`dmemory` inverts the clock into `altsyncram`), so every target on the data
  bus latches write data at the same instant of the CPU cycle.

The decoder also decodes address bits [12:5], which Figure 5 omits, so the
block occupies exactly `0x2000-0x201F`. Without them the decode would alias,
and the aliases are not harmless: `BTCMPR0` at `0x2020` has the same [4:2]
pattern as `PORT_LEDR`, and `IE` at `0x202C` the same as the HEX4/HEX5 pair.

### Checking you didn't break anything

Run `do run_benchmark.do` on any benchmark. It must still say
`*** DTCM MATCHES THE GOLDEN MODEL ***` at 276 cycles. None of the supplied
benchmarks touch I/O, so the GPIO must leave every one of them unchanged — if
a cycle count moves, that is a bug and not an improvement.

---

## Things that will waste your time if you don't know them

**The image set has to match the TCM size.** The two sets were linked for
different memory maps, and the data segment must land at DTCM word 0:

| TCM size in `cond_compilation_package.vhd` | image set | loaded via |
|---|---|---|
| 8 KiB (`*_TCM8KiB`, current) | `bin/M9K-intel/*.hex` | `init_file` generic |
| 4 KiB (`*_TCM4KiB`) | `bin/Hexadecimal-Text/*.h` | `mem load` |

Pair them the other way and the data quietly lands at word 1024 instead of 0.
`run_benchmark.do` detects the TCM size and refuses to run a mismatched pair,
so you should never hit this — but that is why the check is there.

**Compare against `DTCM.h`, not `DTCM.hex`.** For
`Final Project Tests/RV32IM/test1`, the shipped `output/RARS/DTCM.hex` is stale:
it holds add/mul/xor results from an older version of that program. The `.h`
dump is correct. Generally: `.h` is the simulation format, `.hex` is Quartus.

**There are three PLLs, and simulation bypasses them.** Per the professor's
forum post, each clock gets its own PLL, all from the 50 MHz board oscillator:

| Clock | Frequency | Drives |
|---|---|---|
| MCLK | 25 MHz | the CPU |
| DIVCLK | 100 MHz | the division accelerator |
| SMCLK | 25 MHz | the Basic Timer |

These are `altera_pll` (PLL Intel FPGA IP), *not* the ALTPLL that came with the
project — ALTPLL is a Cyclone II megafunction the Cyclone V does not support.

`MCU.vhd` picks between two clock sources with the `MODELSIM` generic, which
the professor left declared and unused for exactly this:

- `MODELSIM = 0` — instantiate the three PLL IP cores. This is the FPGA build.
- `MODELSIM = 1` — generate the clocks behaviourally. No Intel libraries, no
  PLL lock delay. `run_benchmark.do` passes this.

**Both branches run at the same frequencies by construction**, because both
read `clk_config_package.vhd`, which is *generated* by `QUARTUS/gen_plls.tcl`
from the same numbers it builds the IP with. Verified: the benchmark gives 340
cycles and 1024/1024 either way.

**To retune a clock**, edit the `CLOCKS` list in `QUARTUS/gen_plls.tcl` and run
`QUARTUS\gen_plls.bat`. That regenerates the IP *and* rewrites the VHDL
constants, so the two can never drift apart. Then `do compile.do`.

**DIVCLK is deliberately conservative.** It was 200 MHz, which is above what
the divider is likely to close timing at — around 130 MHz has been reported for
this datapath. It is now 100 MHz so the first FPGA validation run has margin.
The frequency changes the cycle count and nothing else; the golden model
matches at every setting:

| DIVCLK | ratio to MCLK | benchmark cycles |
|---|---|---|
| 200 MHz | 8:1 | 276 |
| 150 MHz | 6:1 | 292 |
| 100 MHz | 4:1 | **340** |
| 50 MHz | 2:1 | 484 |

The benchmark performs 16 divisions, so each halving of DIVCLK costs about
four MCLK cycles per division. Once the Timing Analyzer gives the real fmax of
the DIVCLK domain, raise it and re-verify.

There is a ceiling on DIVCLK: `DIVBUSY` is high for 32 DIVCLK cycles, and the
MCLK-side synchronizer in `DIV_ACCEL` needs it high for at least 2 MCLK cycles,
so the DIVCLK:MCLK ratio must stay at or below 16. `tb_div_accel` asserts this
and fails with an explanatory message if you exceed it — it is not a silent
failure, but it is worth knowing before you try 800 MHz.

For Quartus the `.sdc` needs a `create_clock` on `clk_i` plus
`derive_pll_clocks`, which picks up all three PLL outputs.

**Design hierarchy**, for the wave window:

```
tb_RV32I
└── CORE : MCU                 <- top level, clocks + DTCM + decode + GPIO
    ├── MEM : dmemory          /tb_RV32I/CORE/MEM/data_memory/MEMORY/m_mem_data_a
    ├── IODEC   : GPIO_AddressDecoder
    ├── IOLEDR  : GPIO_LEDR_Interface
    ├── IOSW    : GPIO_SW_Interface
    ├── IOHEX01 / IOHEX23 / IOHEX45 : GPIO_HEX_Pair_Interface
    ├── BUF_LEDR / BUF_SW / BUF_HEX01 / BUF_HEX23 / BUF_HEX45 / BUF_NONE
    │                          : BidirPin, all six driving /tb_RV32I/CORE/io_bus_w
    └── CPU : RV32I_CORE       /tb_RV32I/CORE/CPU/...
        ├── IFE  (ITCM)
        └── DIVA (divider accelerator)
```

---

## Layout

```
DUT/RV32IMscMCU/    design sources
  MCU.vhd             top level: clocks, DTCM, address decode, GPIO
  clk_config_package.vhd   GENERATED clock frequencies - do not edit
  RV32I_CORE.vhd      the CPU, a bus master
  DIV_ACCEL.vhd       division accelerator (CDC + handshake)
  DIV.vhd             restoring divider
  CDC_SYNC.vhd        clock domain crossing synchronizer
  SUBTRACTOR.vhd
  IFETCH / IDECODE / CONTROL / EXECUTE / DMEMORY / MULT
  GPIO_AddressDecoder.vhd      one chip select per device (Fig.5)
  GPIO_LEDR_Interface.vhd      PORT_LEDR, GPO
  GPIO_SW_Interface.vhd        PORT_SW, GPI, combinational
  GPIO_HEX_Pair_Interface.vhd  two displays per instance
  SevenSegmentEncoder.vhd      hex nibble to g f e d c b a, active low
  BidirPin.vhd                 SUPPLIED tri-state buffer, one per port (Fig.5)
  aux_package.vhd     component declarations - update when you change a port list
  const_package.vhd   instruction encodings, ALU opcodes
  cond_compilation_package.vhd   TCM size and widths
TB/RV32IMscMCU/     testbenches
SIM/RV32IMscMCU/    compile.do, run_benchmark.do
QUARTUS/            gen_plls.tcl + .bat, the three PLL .qsys files
  PLL_MCLK/ PLL_DIVCLK/ PLL_SMCLK/   generated IP: synthesis/ and simulation/
```

The Basic Timer of Figure 7 lives on `feature/timer`, not here — it is built
and tested but not yet memory-mapped, so it waits for the GPIO work to land
before it gets a bus interface.

If you change any entity's ports, update its component declaration in
`aux_package.vhd` too, or you get a confusing elaboration error rather than a
compile error.
