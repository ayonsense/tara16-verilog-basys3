#!/usr/bin/env python3
# Copyright (C) 2026 Ayon Chakraborty, IIT Madras. GPL-3.0-or-later.
"""
TARA microcode generator — the SINGLE SOURCE OF TRUTH for the control store.

Emits, all in lockstep:
  microcode.mem        : 256 x 40-bit horizontal control words ($readmemh)
  ctrl_defs.vh         : Verilog localparams for every control-word field
  microcode_listing.txt: human-readable per-(opcode,Tstate) listing

It is also importable: `build_rom()` returns the 256-entry integer ROM, and
`FIELDS` the bit layout, so the Python co-simulation model (model/) and the
Verilog (via the .vh) decode identical control words.

Control word = FETCH (T0..T2, identical for every opcode) + EXECUTE (T3..).
The `done` bit returns the ring counter to T0.
"""
import os

# ───────────────────────── control-word field layout ─────────────────────────
# (name, width)   packed from bit 0 upward; total padded to CW_WIDTH.
FIELDS = [
    ("done",      1),
    ("halt",      1),
    ("pc_inc",    1),
    ("pc_load",   1),
    ("pc_src",    1),   # 0=ALU result, 1=regfile port A (RET)
    ("pc_cond",   2),   # 0=always, 1=if-zero, 2=if-neg
    ("ir_load",   1),
    ("mar_load",  1),
    ("mar_src",   1),   # 0=PC, 1=ALU result
    ("mdr_load",  1),
    ("mdr_src",   1),   # 0=memory, 1=regfile port B
    ("mem_we",    1),
    ("mem_byte",  1),   # 1=byte, 0=word
    ("rf_we",     1),
    ("rfw_sel",   2),   # 0=rd, 1=R6, 2=R7
    ("rfw_src",   3),   # 0=ALU,1=MDR,2=LIL{0,imm8},3=LIH{imm8,Rd[7:0]},4=PC_link
    ("rfa_sel",   2),   # portA: 0=rsA,1=rd,2=R6,3=R7
    ("rfb_sel",   2),   # portB: 0=rsB,1=rd,2=R7,3=R6
    ("alu_op",    4),
    ("alu_a",     1),   # 0=portA, 1=PC
    ("alu_b",     3),   # 0=portB,1=sext5(off5),2=sext8(imm8),3=const2,4=branch_rel<<1,5=shamt
    ("status_we", 1),
]
CW_WIDTH   = 40
CW_HEXDIG  = CW_WIDTH // 4
NUM_TSTATE = 8                 # ring counter 0..7
NUM_OPCODE = 32                # 5-bit opcode space

# field bit offsets
_OFF, _b = {}, 0
for _n, _w in FIELDS:
    _OFF[_n] = (_b, _w)
    _b += _w
assert _b <= CW_WIDTH, f"control word {_b} > {CW_WIDTH}"

# ───────────────────────── symbolic constants ───────────────────────────────
# ALU ops
ADD,SUB,MUL,AND,OR,XOR,NOT,SHL,SHR,SLT,PASSA,PASSB = range(12)
# alu_b mux
B_RFB,B_OFF5,B_IMM8,B_CONST2,B_REL,B_SHAMT = range(6)
# rfw_src
W_ALU,W_MDR,W_LIL,W_LIH,W_PCLINK = range(5)
# rfa_sel / rfb_sel
A_RSA,A_RD,A_R6,A_R7 = range(4)
B_RSB,Bp_RD,Bp_R7,Bp_R6 = range(4)
# rfw_sel
WR_RD,WR_R6,WR_R7 = range(3)
# pc_cond
C_ALWAYS,C_IFZ,C_IFN = range(3)

OP = {  # mnemonic -> opcode (transcribed from the golden simulator cpu.py)
    'NOP':0,'HLT':1,'MOV':2,'LIL':3,'LIH':4,'LDW':5,'STW':6,'LDB':7,'STB':8,
    'ADD':9,'SUB':10,'ADDI':11,'MUL':12,'AND':13,'OR':14,'XOR':15,'NOT':16,
    'SHL':17,'SHR':18,'SLT':19,'BZ':20,'BN':21,'JMP':22,'CALL':23,'RET':24,
    'PUSH':25,'POP':26,
}

def cw(**kw):
    """Assemble a control word integer from field=value kwargs (others 0)."""
    val = 0
    for name, v in kw.items():
        lsb, w = _OFF[name]
        assert 0 <= v < (1 << w), f"{name}={v} exceeds {w} bits"
        val |= (v & ((1 << w) - 1)) << lsb
    return val

# ───────────────────────── FETCH (common T0..T2) ────────────────────────────
FETCH = [
    cw(mar_load=1, mar_src=0),                       # T0: MAR <- PC
    cw(mdr_load=1, mdr_src=0, pc_inc=1),             # T1: MDR <- M[MAR]; PC += 2
    cw(ir_load=1),                                   # T2: IR  <- MDR
]

# ───────────────────────── EXECUTE micro-sequences ──────────────────────────
def alu_rrr(op):   # F1: Rd <- RsA op RsB
    return [cw(rfa_sel=A_RSA, rfb_sel=B_RSB, alu_a=0, alu_b=B_RFB, alu_op=op,
              rf_we=1, rfw_sel=WR_RD, rfw_src=W_ALU, status_we=1, done=1)]

EXEC = {
    'NOP':  [cw(done=1)],
    'HLT':  [cw(halt=1)],                            # halt latches; never 'done'

    'MOV':  [cw(rfa_sel=A_RSA, alu_a=0, alu_op=PASSA,
                rf_we=1, rfw_sel=WR_RD, rfw_src=W_ALU, done=1)],
    'NOT':  [cw(rfa_sel=A_RSA, alu_a=0, alu_op=NOT,
                rf_we=1, rfw_sel=WR_RD, rfw_src=W_ALU, status_we=1, done=1)],

    'LIL':  [cw(rf_we=1, rfw_sel=WR_RD, rfw_src=W_LIL, done=1)],
    'LIH':  [cw(rfa_sel=A_RD, rf_we=1, rfw_sel=WR_RD, rfw_src=W_LIH, done=1)],
    'ADDI': [cw(rfa_sel=A_RD, alu_a=0, alu_b=B_IMM8, alu_op=ADD,
                rf_we=1, rfw_sel=WR_RD, rfw_src=W_ALU, status_we=1, done=1)],
    'SHL':  [cw(rfa_sel=A_RD, alu_a=0, alu_b=B_SHAMT, alu_op=SHL,
                rf_we=1, rfw_sel=WR_RD, rfw_src=W_ALU, status_we=1, done=1)],
    'SHR':  [cw(rfa_sel=A_RD, alu_a=0, alu_b=B_SHAMT, alu_op=SHR,
                rf_we=1, rfw_sel=WR_RD, rfw_src=W_ALU, status_we=1, done=1)],

    'ADD':  alu_rrr(ADD), 'SUB': alu_rrr(SUB), 'MUL': alu_rrr(MUL),
    'AND':  alu_rrr(AND), 'OR':  alu_rrr(OR),  'XOR': alu_rrr(XOR),
    'SLT':  alu_rrr(SLT),

    # ── loads/stores ── ea = Rbase(rsA) + sext5(off5)
    'LDW':  [cw(rfa_sel=A_RSA, alu_a=0, alu_b=B_OFF5, alu_op=ADD,
                mar_load=1, mar_src=1),
             cw(mdr_load=1, mdr_src=0, mem_byte=0),
             cw(rf_we=1, rfw_sel=WR_RD, rfw_src=W_MDR, done=1)],
    'LDB':  [cw(rfa_sel=A_RSA, alu_a=0, alu_b=B_OFF5, alu_op=ADD,
                mar_load=1, mar_src=1),
             cw(mdr_load=1, mdr_src=0, mem_byte=1),
             cw(rf_we=1, rfw_sel=WR_RD, rfw_src=W_MDR, done=1)],
    'STW':  [cw(rfa_sel=A_RSA, alu_a=0, alu_b=B_OFF5, alu_op=ADD,
                mar_load=1, mar_src=1, rfb_sel=Bp_RD, mdr_load=1, mdr_src=1),
             cw(mem_we=1, mem_byte=0, done=1)],
    'STB':  [cw(rfa_sel=A_RSA, alu_a=0, alu_b=B_OFF5, alu_op=ADD,
                mar_load=1, mar_src=1, rfb_sel=Bp_RD, mdr_load=1, mdr_src=1),
             cw(mem_we=1, mem_byte=1, done=1)],

    # ── control transfer ── target = PC_after + branch_rel<<1
    'BZ':   [cw(rfa_sel=A_RD, pc_cond=C_IFZ, alu_a=1, alu_b=B_REL, alu_op=ADD,
                pc_load=1, pc_src=0, done=1)],
    'BN':   [cw(rfa_sel=A_RD, pc_cond=C_IFN, alu_a=1, alu_b=B_REL, alu_op=ADD,
                pc_load=1, pc_src=0, done=1)],
    'JMP':  [cw(alu_a=1, alu_b=B_REL, alu_op=ADD,
                pc_load=1, pc_cond=C_ALWAYS, pc_src=0, done=1)],
    'CALL': [cw(alu_a=1, alu_b=B_REL, alu_op=ADD,
                pc_load=1, pc_cond=C_ALWAYS, pc_src=0,
                rf_we=1, rfw_sel=WR_R6, rfw_src=W_PCLINK, done=1)],
    'RET':  [cw(rfa_sel=A_R6, pc_load=1, pc_src=1, pc_cond=C_ALWAYS, done=1)],

    # ── stack ── full-descending, word, R7=SP
    'PUSH': [cw(rfa_sel=A_R7, alu_a=0, alu_b=B_CONST2, alu_op=SUB,   # SP-2
                rf_we=1, rfw_sel=WR_R7, rfw_src=W_ALU,               # SP <- SP-2
                mar_load=1, mar_src=1,                               # MAR <- SP-2
                rfb_sel=Bp_RD, mdr_load=1, mdr_src=1),               # MDR <- Rstk
             cw(mem_we=1, mem_byte=0, done=1)],
    'POP':  [cw(rfa_sel=A_R7, alu_a=0, alu_op=PASSA, mar_load=1, mar_src=1),
             cw(mdr_load=1, mdr_src=0, mem_byte=0),
             cw(rf_we=1, rfw_sel=WR_RD, rfw_src=W_MDR),              # Rstk <- M[SP]
             cw(rfa_sel=A_R7, alu_a=0, alu_b=B_CONST2, alu_op=ADD,   # SP+2
                rf_we=1, rfw_sel=WR_R7, rfw_src=W_ALU, done=1)],
}

# ───────────────────────── build the 256-entry ROM ──────────────────────────
def build_rom():
    rom = [0] * (NUM_OPCODE * NUM_TSTATE)
    name_by_op = {v: k for k, v in OP.items()}
    for op in range(NUM_OPCODE):
        seq = FETCH + EXEC.get(name_by_op.get(op, ''), [cw(done=1)])  # undefined → NOP
        for t in range(NUM_TSTATE):
            rom[op * NUM_TSTATE + t] = seq[t] if t < len(seq) else 0
    return rom

# ───────────────────────── emitters ─────────────────────────────────────────
def emit(outdir):
    rom = build_rom()
    name_by_op = {v: k for k, v in OP.items()}

    with open(os.path.join(outdir, "microcode.mem"), "w") as f:
        for word in rom:
            f.write(f"{word:0{CW_HEXDIG}x}\n")

    with open(os.path.join(outdir, "ctrl_defs.vh"), "w") as f:
        f.write("// AUTO-GENERATED by gen_microcode.py — do not edit by hand.\n")
        f.write("// TARA microcoded control-word field definitions.\n")
        f.write("// All preprocessor `defines so this header is legal to `include\n")
        f.write("// at file scope (above the module), unlike localparams.\n")
        f.write("`ifndef TARA_CTRL_DEFS_VH\n`define TARA_CTRL_DEFS_VH\n\n")
        f.write(f"`define CW_WIDTH   {CW_WIDTH}\n")
        f.write(f"`define NUM_TSTATE {NUM_TSTATE}\n")
        f.write(f"`define ROM_DEPTH  {NUM_OPCODE*NUM_TSTATE}\n\n")
        for name, (lsb, w) in _OFF.items():
            U = name.upper()
            f.write(f"`define CW_{U}_LSB {lsb}\n")
            f.write(f"`define CW_{U}_W   {w}\n")
        f.write("\n// field-extract macros — pass a bare net identifier (e.g. `CW_DONE(cw)).\n")
        f.write("// No parens around the operand: a part-select must apply to an identifier.\n")
        for name, (lsb, w) in _OFF.items():
            U = name.upper()
            f.write(f"`define CW_{U}(cw) cw[`CW_{U}_LSB +: `CW_{U}_W]\n")
        # symbolic ALU-op constants (for reference; alu.v defines its own)
        f.write("\n// ALU ops\n")
        for i, nm in enumerate(["ADD","SUB","MUL","AND","OR","XOR","NOT",
                                "SHL","SHR","SLT","PASSA","PASSB"]):
            f.write(f"`define ALU_{nm} {i}\n")
        f.write("\n`endif\n")

    with open(os.path.join(outdir, "microcode_listing.txt"), "w") as f:
        f.write("TARA microcode listing — addr = opcode*8 + Tstate\n")
        f.write("="*72 + "\n")
        for op in range(NUM_OPCODE):
            nm = name_by_op.get(op)
            if nm is None:
                continue
            f.write(f"\n[{op:2d}] {nm}\n")
            for t in range(NUM_TSTATE):
                word = rom[op*NUM_TSTATE + t]
                if word == 0 and t >= 3:
                    continue
                active = [n for n,(l,w) in _OFF.items() if (word>>l)&((1<<w)-1)]
                vals = ", ".join(f"{n}={ (word>>_OFF[n][0])&((1<<_OFF[n][1])-1) }"
                                 for n in active)
                tag = "FETCH" if t < 3 else "EXEC "
                f.write(f"   T{t} {tag} {word:0{CW_HEXDIG}x}  {vals}\n")
    return rom

if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    rom = emit(here)
    print(f"wrote microcode.mem ({len(rom)} words), ctrl_defs.vh, microcode_listing.txt")
