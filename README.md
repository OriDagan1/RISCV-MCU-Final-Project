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
 cycles to finish = 484
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
vsim work.tb_divider   ; run -all      # the divider, 4618 divisions
vsim work.tb_cdc_sync  ; run -all      # the clock domain crossing
vsim work.tb_div_accel ; run -all      # the accelerator handshake
```

Each ends with `ALL TESTS PASSED`.

---

## Where the GPIO goes

`MCU.vhd` is the top level and owns everything outside the CPU: clocks, the
DTCM, and the address decode. The CPU is a bus master — it drives a byte
address and takes read data back, and has no idea which device answers. So
**all of the GPIO work is in `MCU.vhd` plus whatever new files you add**; you
should not need to touch the core.

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

### The three hook points

They are already marked `TODO(feature/gpio)` in `MCU.vhd`:

**1. Port list** — add the board pins:

```vhdl
LEDR_o : OUT STD_LOGIC_VECTOR(9 DOWNTO 0);
SW_i   : IN  STD_LOGIC_VECTOR(9 DOWNTO 0);
HEX0_o : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
...
```

**2. Write path** — `io_sel_w` already exists and the DTCM write enable is
already qualified with it, so a write to `0x2000+` cannot reach the DTCM:

```vhdl
io_sel_w  <= bus_addr_w(DA_WIDTH-1);
dtcm_we_w <= bus_write_w AND NOT io_sel_w;    -- already there
io_we_w   <= bus_write_w AND     io_sel_w;    -- yours
```

**3. Read path** — currently a one-line stub. Replace it with the mux:

```vhdl
-- now:
bus_rdata_w <= dtcm_q_w;
-- becomes:
bus_rdata_w <= io_rdata_w WHEN io_sel_w = '1' ELSE dtcm_q_w;
```

Useful signals already in scope: `bus_addr_w`, `bus_wdata_w`, `bus_rdata_w`,
`bus_read_w`, `bus_write_w`, `io_sel_w`, `mclk_w`.

### Checking you didn't break anything

Run `do run_benchmark.do` on any benchmark. It must still say
`*** DTCM MATCHES THE GOLDEN MODEL ***`. None of the supplied benchmarks touch
I/O, so adding the GPIO must leave every one of them unchanged.

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
| DIVCLK | 200 MHz | the division accelerator |
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
from the same numbers it builds the IP with. Verified: the benchmark gives 276
cycles and 1024/1024 either way.

**To retune a clock**, edit the `CLOCKS` list in `QUARTUS/gen_plls.tcl` and run
`QUARTUS\gen_plls.bat`. That regenerates the IP *and* rewrites the VHDL
constants, so the two can never drift apart. Then `do compile.do`.

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
└── CORE : MCU                 <- top level, clocks + DTCM + decode
    ├── MEM : dmemory          /tb_RV32I/CORE/MEM/data_memory/MEMORY/m_mem_data_a
    └── CPU : RV32I_CORE       /tb_RV32I/CORE/CPU/...
        ├── IFE  (ITCM)
        └── DIVA (divider accelerator)
```

---

## Layout

```
DUT/RV32IMscMCU/    design sources
  MCU.vhd             top level: clocks, DTCM, address decode  <- GPIO goes here
  clk_config_package.vhd   GENERATED clock frequencies - do not edit
  RV32I_CORE.vhd      the CPU, a bus master
  DIV_ACCEL.vhd       division accelerator (CDC + handshake)
  DIV.vhd             restoring divider
  CDC_SYNC.vhd        clock domain crossing synchronizer
  SUBTRACTOR.vhd
  IFETCH / IDECODE / CONTROL / EXECUTE / DMEMORY / MULT
  BASIC_TIMER.vhd     Basic Timer top (Fig.7) - built, not yet memory-mapped
  BTCNT / BT_CLKDIV / BT_OUTPUT_UNIT / BT_CAPTURE
  aux_package.vhd     component declarations - update when you change a port list
  const_package.vhd   instruction encodings, ALU opcodes
  cond_compilation_package.vhd   TCM size and widths
TB/RV32IMscMCU/     testbenches
SIM/RV32IMscMCU/    compile.do, run_benchmark.do, run_timer.do
QUARTUS/            gen_plls.tcl + .bat, the three PLL .qsys files
  PLL_MCLK/ PLL_DIVCLK/ PLL_SMCLK/   generated IP: synthesis/ and simulation/
```

The Basic Timer of Figure 7 is on this branch only — built and tested, but not
yet memory-mapped, so it waits for the GPIO work to land before it gets a bus
interface. It is deliberately not on `main` for that reason.

If you change any entity's ports, update its component declaration in
`aux_package.vhd` too, or you get a confusing elaboration error rather than a
compile error.
