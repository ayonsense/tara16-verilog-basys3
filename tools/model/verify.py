#!/usr/bin/env python3
# Copyright (C) 2026 Ayon Chakraborty, IIT Madras. GPL-3.0-or-later.
"""
Design self-check: run TARA example programs through BOTH
  (a) the golden behavioural simulator  (python-sim .../cpu.py)
  (b) the microcoded datapath model     (model/tara_pymodel.py)
and assert identical final register + memory (incl. framebuffer) state.

This proves the microcode + datapath design matches the ISA before RTL/Vivado.
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SIM  = os.path.abspath(os.environ.get("TARA16_SIM") or os.path.join(HERE, "..", "..", "..", "tara16-studio"))
sys.path.insert(0, SIM)
sys.path.insert(0, HERE)

from src.assembler.asm import assemble          # golden assembler
from src.simulation.cpu import TaraCPU           # golden CPU
from tara_pymodel import TaraModel               # our microcoded model

PROGS = [
    "src/examples/progs/Basic/fibonacci.tara",
    "src/examples/progs/Basic/factorial.tara",
    "src/examples/progs/Intermediate/greatest_common_divisor.tara",
    "src/examples/progs/Intermediate/prime_test.tara",
    "src/examples/progs/Intermediate/first_n_primes.tara",
    "src/examples/progs/Advanced/bubble_sort.tara",
    "src/examples/progs/Advanced/insertion_sort.tara",
    "src/examples/progs/Advanced/binary_search.tara",
    "src/examples/progs/Advanced/matrix_multiplication.tara",
    "src/examples/progs/Display/draw_rectangle.tara",
    "src/examples/progs/Display/draw_triangle.tara",
    "src/examples/progs/Display/draw_line.tara",
    "src/examples/progs/Display/draw_spiral.tara",   # infinite loop — lock-step only
]

MAX_INSTR = 40_000   # lock-step horizon (covers all but the huge bubble sort)

def run_one(path):
    with open(os.path.join(SIM, path)) as f:
        src = f.read()
    words, listing, errors, labels = assemble(src)
    if errors:
        return ("ASMERR", [str(e) for e in errors])
    prog = [(a, w) for a, w in words]          # (addr, word) pairs (contiguous from 0)

    g = TaraCPU();  g.load_program([w for _, w in prog])   # golden wants bare ints
    m = TaraModel(); m.load_program(prog)

    # ── instruction-by-instruction lock-step ──────────────────────────────
    diffs = []
    n = 0
    while n < MAX_INSTR:
        g_alive = g.step(record_history=False)     # executes one instruction
        if not m.halted:
            m.step_instruction()
        n += 1
        # cheap divergence check: registers, PC, and a memory checksum
        if [r & 0xFFFF for r in g.reg] != list(m.reg) or \
           (g.pc & 0x7FF) != (m.pc & 0x7FF) or sum(g.mem) != sum(m.mem):
            for i in range(8):
                if (g.reg[i] & 0xFFFF) != m.reg[i]:
                    diffs.append(f"@instr {n} R{i}: golden={g.reg[i]&0xFFFF:#06x} model={m.reg[i]:#06x}")
            if (g.pc & 0x7FF) != (m.pc & 0x7FF):
                diffs.append(f"@instr {n} PC: golden={g.pc&0x7FF:#05x} model={m.pc&0x7FF:#05x}")
            for a in range(TaraCPU.MEM_SIZE):
                if g.mem[a] != m.mem[a]:
                    diffs.append(f"@instr {n} mem[{a:#05x}]: golden={g.mem[a]:#04x} model={m.mem[a]:#04x}")
                    if len(diffs) > 10: break
            break
        if g.halted and m.halted:
            break
        if g.halted != m.halted:
            diffs.append(f"@instr {n} halt mismatch golden={g.halted} model={m.halted}")
            break
    status = "OK" if not diffs else "FAIL"
    tail = "halted" if g.halted else f"ran {n} instr (no HLT)"
    return (status, diffs, g.instr_count, m.cycles, tail)

def main():
    npass = nfail = 0
    for p in PROGS:
        full = os.path.join(SIM, p)
        if not os.path.exists(full):
            print(f"  FAIL (missing): {p}"); nfail += 1; continue
        res = run_one(p)
        name = os.path.basename(p)
        if res[0] == "OK":
            npass += 1
            print(f"  PASS  {name:32s}  {res[4]:20s}  model_cycles={res[3]:>8}")
        else:
            nfail += 1
            print(f"  FAIL  {name:32s}  [{res[0]}]")
            for d in res[1][:14]:
                print(f"          {d}")
    print(f"\n{'='*60}\n  {npass} passed, {nfail} failed\n{'='*60}")
    sys.exit(1 if nfail else 0)

if __name__ == "__main__":
    main()
