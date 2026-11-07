#!/usr/bin/env python3
# Copyright (C) 2026 Ayon Chakraborty, IIT Madras. GPL-3.0-or-later.
"""
Cycle-accurate Python model of the TARA microcoded datapath.

It decodes the SAME 40-bit control words emitted by microcode/gen_microcode.py
and implements the SAME datapath the Verilog implements (PC/IR/MAR/MDR/regfile/
ALU + ring-counter T-states). Running a program here and comparing to the golden
behavioural simulator (python-sim .../cpu.py) validates the microcode + datapath
*design* before it is committed to RTL — this is the pre-silicon check used in
environments without an HDL simulator. The iverilog testbenches reproduce it.

One call to `microstep()` == one CPU clock == one ring-counter T-state.
"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "microcode"))
import gen_microcode as mc

NUM_T = mc.NUM_TSTATE
OFF   = mc._OFF
ROM   = mc.build_rom()

# opcode numbers
OPN = mc.OP
JMP, CALL = OPN['JMP'], OPN['CALL']

def _fld(cwval, name):
    lsb, w = OFF[name]
    return (cwval >> lsb) & ((1 << w) - 1)

def sext(v, bits):
    return v - (1 << bits) if v & (1 << (bits - 1)) else v

def m16(v): return v & 0xFFFF

class TaraModel:
    MEM = 2048
    def __init__(self):
        self.reset()

    def reset(self):
        self.reg = [0]*8
        self.pc  = 0
        self.ir  = 0
        self.mar = 0
        self.mdr = 0
        self.t   = 0
        # word-organized memory (mirrors the synthesizable 1024x16 RAM):
        # index = byte_addr>>1, big-endian byte lanes (even addr = high byte).
        self.wmem = [0] * (self.MEM // 2)
        self.halted = False
        self.flags = dict(z=0, n=0, c=0, v=0)
        self.cycles = 0

    # program load: list of (byte_addr, 16-bit word). Words are word-aligned.
    def load_program(self, words):
        for a, w in words:
            self.wmem[(a >> 1) & 0x3FF] = w & 0xFFFF

    # byte view (big-endian) for comparison / framebuffer inspection
    @property
    def mem(self):
        b = bytearray(self.MEM)
        for i, w in enumerate(self.wmem):
            b[2*i]   = (w >> 8) & 0xFF
            b[2*i+1] =  w       & 0xFF
        return b

    # ── memory helpers (1024x16, byte-addressable, big-endian) ──
    def _rword(self, a):
        return self.wmem[(a >> 1) & 0x3FF]
    def _rbyte(self, a):
        w = self.wmem[(a >> 1) & 0x3FF]
        return (w >> 8) & 0xFF if (a & 1) == 0 else w & 0xFF
    def _wword(self, a, v):
        self.wmem[(a >> 1) & 0x3FF] = v & 0xFFFF
    def _wbyte(self, a, v):
        i = (a >> 1) & 0x3FF
        if a & 1: self.wmem[i] = (self.wmem[i] & 0xFF00) | (v & 0xFF)
        else:     self.wmem[i] = (self.wmem[i] & 0x00FF) | ((v & 0xFF) << 8)

    def _alu(self, op, a, b):
        a &= 0xFFFF; b &= 0xFFFF
        c = 0; v = 0
        if op == mc.ADD:
            r = a + b; c = (r >> 16) & 1
            v = ((~(a ^ b) & (a ^ r)) >> 15) & 1; r &= 0xFFFF
        elif op == mc.SUB:
            r = (a - b) & 0xFFFF; c = 1 if a >= b else 0
            v = (((a ^ b) & (a ^ r)) >> 15) & 1
        elif op == mc.MUL:  r = (a * b) & 0xFFFF
        elif op == mc.AND:  r = a & b
        elif op == mc.OR:   r = a | b
        elif op == mc.XOR:  r = a ^ b
        elif op == mc.NOT:  r = (~a) & 0xFFFF
        elif op == mc.SHL:  r = (a << (b & 0x1F)) & 0xFFFF
        elif op == mc.SHR:  r = (a >> (b & 0x1F)) & 0xFFFF
        elif op == mc.SLT:  r = 1 if sext(a,16) < sext(b,16) else 0
        elif op == mc.PASSA: r = a
        elif op == mc.PASSB: r = b
        else: r = 0
        return r, c, v

    def microstep(self):
        """Execute one CPU clock / ring-counter T-state.
        Returns True at an instruction boundary (a microword with `done`, or HLT)."""
        if self.halted:
            return True
        self.cycles += 1
        op = (self.ir >> 11) & 0x1F
        cw = ROM[op*NUM_T + self.t]

        # decode IR fields
        rd   = (self.ir >> 8) & 7
        rsA  = (self.ir >> 5) & 7
        rsB  = (self.ir >> 2) & 7
        imm8 =  self.ir & 0xFF
        off5 =  self.ir & 0x1F
        rel8 =  self.ir & 0xFF
        rel11=  self.ir & 0x7FF
        branch_rel = ( (sext(rel11,11) if op in (JMP,CALL) else sext(rel8,8)) << 1 ) & 0xFFFF

        # regfile read-port address muxes
        rfa = [rsA, rd, 6, 7][_fld(cw,'rfa_sel')]
        rfb = [rsB, rd, 7, 6][_fld(cw,'rfb_sel')]
        A = self.reg[rfa]; B = self.reg[rfb]
        is_zero = 1 if A == 0 else 0
        is_neg  = (A >> 15) & 1

        # snapshot PC: in hardware every consumer sees the registered (pre-edge)
        # value while pc_inc/pc_load compute the next value concurrently.
        pc_before = self.pc

        # ALU
        alu_a = pc_before if _fld(cw,'alu_a') else A
        bsel  = _fld(cw,'alu_b')
        alu_b = [B, sext(off5,5)&0xFFFF, sext(imm8,8)&0xFFFF, 2,
                 branch_rel, imm8 & 0x1F][bsel]
        alu_r, alu_c, alu_v = self._alu(_fld(cw,'alu_op'), alu_a, alu_b)

        # memory read (async, from current MAR)
        if _fld(cw,'mem_byte'):
            mem_rd = self._rbyte(self.mar) & 0xFF        # zero-extended byte
        else:
            mem_rd = self._rword(self.mar)

        # ───── clocked commit (all PC reads use pc_before) ─────
        new_pc = pc_before
        if _fld(cw,'pc_inc'):
            new_pc = (pc_before + 2) & 0x7FF
        if _fld(cw,'pc_load'):
            cond = _fld(cw,'pc_cond')
            take = (cond == 0) or (cond == 1 and is_zero) or (cond == 2 and is_neg)
            if take:
                new_pc = (alu_r if _fld(cw,'pc_src') == 0 else A) & 0x7FF
        self.pc = new_pc
        if _fld(cw,'ir_load'):
            self.ir = self.mdr & 0xFFFF
        if _fld(cw,'mar_load'):
            self.mar = (pc_before if _fld(cw,'mar_src') == 0 else alu_r) & 0x7FF
        if _fld(cw,'mdr_load'):
            self.mdr = (mem_rd if _fld(cw,'mdr_src') == 0 else B) & 0xFFFF
        if _fld(cw,'mem_we'):
            if _fld(cw,'mem_byte'):
                self._wbyte(self.mar, self.mdr & 0xFF)
            else:
                self._wword(self.mar, self.mdr)
        if _fld(cw,'rf_we'):
            waddr = [rd, 6, 7][_fld(cw,'rfw_sel')]
            src   = _fld(cw,'rfw_src')
            if   src == 0: wdata = alu_r
            elif src == 1: wdata = self.mdr
            elif src == 2: wdata = imm8 & 0xFF                  # LIL
            elif src == 3: wdata = ((imm8 & 0xFF) << 8) | (A & 0xFF)  # LIH
            elif src == 4: wdata = pc_before                    # PC link (PC_after)
            else:          wdata = 0
            self.reg[waddr] = wdata & 0xFFFF
        if _fld(cw,'status_we'):
            self.flags = dict(z=1 if alu_r==0 else 0, n=(alu_r>>15)&1,
                              c=alu_c, v=alu_v)
        if _fld(cw,'halt'):
            self.halted = True
            return True

        # ring-counter advance
        done = _fld(cw,'done')
        self.t = 0 if done else (self.t + 1) & (NUM_T - 1)
        return bool(done)

    def step_instruction(self, guard=128):
        """Run microsteps until one full instruction completes (or HLT)."""
        for _ in range(guard):
            if self.microstep():
                return
        raise RuntimeError("instruction did not complete within guard")

    def run(self, max_cycles=2_000_000):
        while not self.halted and self.cycles < max_cycles:
            self.microstep()
        return not self.halted   # True => hit cycle cap (likely a bug)
