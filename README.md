# TARA CPU — Verilog (Basys 3)

A synthesizable, **microprogrammed** implementation of the TARA teaching CPU for
the Digilent Basys 3 (Artix-7 `xc7a35tcpg236-1`), with the 64×64 framebuffer
scaled to 640×480 VGA. The ISA is transcribed exactly from the reference Python
simulator (`../tara16-studio`), which is used as the golden model for verification.

## Setup

Clone `tara16-verilog-basys3` and `tara16-studio` alongside each other. Python 3,
Icarus Verilog (`iverilog` and `vvp`), and Make are needed for verification.
Set `TARA16_SIM` to the Studio repository root if it is elsewhere.
Vivado is needed only for synthesis; openFPGALoader is used by the optional
board-programming commands. No board is required to run the tests.

The required ROM initialization files in `tools/assets/` are supplied ready to
use by the standard build.

## Directory layout

The tree is split into two top-level source areas: the **hardware** (everything
that becomes the chip) and the **tools** used by the supported build and
verification flow. FPGA program loading is done through TARA Studio.

```
tara16-verilog-basys3/
├─ hardware/                 the CPU itself — everything that is synthesized
│  ├─ rtl/
│  │  ├─ alu/      full_adder, rca16, cla4, cla16, mult16, shifter, logic_unit, alu
│  │  ├─ core/     regfile, pc, ir, mar, mdr, status_reg
│  │  ├─ mem/      memory  (2 KB, async read, VGA port, $readmemh init)
│  │  ├─ control/  ring_counter, control_rom, control_unit
│  │  ├─ cpu/      tara_cpu   (datapath + control + memory)
│  │  └─ board/    clock_step, vga_sync, vga_scaler, ps2_*, uart_*, mem_monitor,
│  │               prog_loader, seg7, tara_top
│  ├─ constraints/ tara_basys3.xdc
│  ├─ sim/         iverilog testbenches + Makefile
│  └─ build.tcl    one-command Vivado build (synthesize → bitstream → program)
├─ tools/                    supported build and verification utilities
│  ├─ microcode/  control-store support files
│  ├─ programs/   boot-program support files
│  └─ model/      tara_pymodel.py, verify.py  (design co-simulation vs golden)
└─ build/                    generated products (bitstream, reports, Vivado proj)
```

## Build in Vivado

From this repository root:

```sh
make test              # RTL tests; does not alter the release boot image
make verify            # compare with the Studio CPU model
make bitstream         # build only; does not program a board
make program           # explicitly program FPGA SRAM
make flash             # explicitly program persistent SPI flash
```

Builds use `vivado` on PATH; override with `make bitstream VIVADO=/path/to/vivado`.

The one-command flow (Basys 3 plugged in over USB):

```
vivado -mode batch -source hardware/build.tcl              # build + program
vivado -mode batch -source hardware/build.tcl -tclargs noprogram   # build only
```

`build.tcl` reads all of `hardware/rtl/**/*.v` and `hardware/constraints/
tara_basys3.xdc`, supplies the required memory initialization resources, and
writes the bitstream and reports into `build/`.

To do it from the Vivado GUI instead: new project for `xc7a35tcpg236-1`, add
`hardware/rtl/**/*.v` (top module **`tara_top`**), and add
`hardware/constraints/tara_basys3.xdc`.

To run a different program, load it live over USB with TARA Studio; no hardware
rebuild is needed for normal program changes.

## Board controls

| Control | Function |
|---------|----------|
| `sw[0]` | run (1) / single-step (0) |
| `sw[1]` | auto-clock speed: full 100 MHz (1) / 5 kHz slow (0) |
| `sw[2]` | loader enable (ESP32) — leave 0 for normal use |
| `sw[4]` | game QUIT key (bit4 at 0x5FF) |
| `sw[15:14]` | 7-seg source: 0=PC, 1=IR, 2=register, 3=raw switches |
| `sw[13:11]` | register select (R0..R7) when 7-seg source = 2 |
| `btnC` | reset |
| `btnU` | single-step (one T-state) **and** game UP |
| `btnD` / `btnL` / `btnR` | game DOWN / LEFT / RIGHT |

LEDs (16-bit): `{halted, loading, Z,N,C,V, 0,0, Tstate[2:0], R0[4:0]}`.

**Game inputs** are memory-mapped, one-hot, at **`0x05FF`** (read with `LDB`):
`bit0=UP bit1=DOWN bit2=LEFT bit3=RIGHT bit4=QUIT`. Two sources drive these
controls:
- **Buttons**: btnU/D/L/R + sw[4]=QUIT.
- **PS/2 keyboard** via the Basys3 USB-HID port (`PS2Clk`=C17, `PS2Data`=B17):
  arrow keys or **WASD** for movement. **Q** resets/restarts like `btnC`.

Load a game from TARA Studio, run at full speed, and steer with either the
buttons or a USB keyboard.

VGA shows the `0x600–0x7FF` framebuffer (amber on black). The top and bottom
borders are reserved for the lab display frame.

## TARA Studio FPGA Tool

Use the **TARA FPGA Tool** tab in the TARA Studio desktop application to read and
write the board's 2 KB memory over the same micro-USB programming cable. Select
**FPGA USB**, choose the Basys 3 UART serial port, and press **Connect**. The
memory view lets you read ranges, enable auto-refresh, inspect the framebuffer,
fill memory, and poke individual bytes while working with the real FPGA.

**Assemble & run a program — no re-synthesis.** Pick a `.tara` file with
**Browse** and press **Load && Run**: TARA Studio assembles it, holds the CPU
while streaming the machine code to `0x000`, then releases it so it runs from
PC=0. You only rebuild the bitstream to change *hardware*; new programs are
loaded over USB. Set `sw[0]=1`, `sw[1]=1` for normal full-speed runs.

Tip: pause the CPU (`sw[0]=0`) before manual pokes so the running program does
not overwrite them.

## Verification

The CPU **design** (microcode + datapath) is verified by cycle-accurate
co-simulation against the golden simulator:

```
python3 tools/model/verify.py   # compare 13 example programs instruction-by-instruction
```

This lock-steps `tools/model/tara_pymodel.py` (which decodes the *same* control
words the RTL uses) against `../tara16-studio/src/simulation/cpu.py` across Fibonacci,
factorial, GCD, primes, bubble/insertion sort, binary search, matrix multiply,
and the framebuffer draw demos — registers, PC and memory match every
instruction.

`hardware/sim/` contains Icarus Verilog testbenches (`make` runs them) for the
adders, ALU, regfile, and a whole-CPU program run that checks registers against
the golden state — run these locally where `iverilog`/Vivado xsim is available.

Model comparisons and RTL testbenches cover the supplied scenarios; they are
not exhaustive hardware verification. FPGA synthesis and board operation require
the corresponding tools and physical board.
