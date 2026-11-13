# Makefile — Icarus Verilog testbenches for the TARA CPU.
#   make           run every testbench
#   make cpu       run only the whole-CPU program test
#   make adders|alu|regfile
# Run from this sim/ directory.  RTL is in ../rtl; the generated headers come
# from the utilities in ../../tools (microcode, programs).

IV      = iverilog
VVP     = vvp
IFLAGS  = -g2012 -I../../tools/microcode -Ibuild

ALU_RTL  = ../rtl/alu/full_adder.v ../rtl/alu/rca16.v ../rtl/alu/cla4.v \
           ../rtl/alu/cla16.v ../rtl/alu/mult16.v ../rtl/alu/shifter.v \
           ../rtl/alu/logic_unit.v ../rtl/alu/alu.v
CORE_RTL = ../rtl/core/regfile.v ../rtl/core/pc.v ../rtl/core/ir.v \
           ../rtl/core/mar.v ../rtl/core/mdr.v ../rtl/core/status_reg.v
MEM_RTL  = ../rtl/mem/memory.v
CTRL_RTL = ../rtl/control/ring_counter.v ../rtl/control/control_rom.v \
           ../rtl/control/control_unit.v
CPU_RTL  = $(ALU_RTL) $(CORE_RTL) $(MEM_RTL) $(CTRL_RTL) ../rtl/cpu/tara_cpu.v

.PHONY: all adders alu regfile cpu keyboard microcode prog clean

all: microcode prog adders alu regfile cpu keyboard
	@echo "================ all testbenches done ================"

# (re)generate microcode + boot program before the CPU test
microcode:
	@python3 ../../tools/microcode/gen_microcode.py
prog:
	@TARA16_PROG_OUT=build python3 ../../tools/programs/gen_prog.py

adders: $(ALU_RTL) tb_adders.v
	$(IV) $(IFLAGS) -o tb_adders.vvp tb_adders.v $(ALU_RTL)
	$(VVP) tb_adders.vvp

alu: $(ALU_RTL) tb_alu.v
	$(IV) $(IFLAGS) -o tb_alu.vvp tb_alu.v $(ALU_RTL)
	$(VVP) tb_alu.vvp

regfile: ../rtl/core/regfile.v tb_regfile.v
	$(IV) $(IFLAGS) -o tb_regfile.vvp tb_regfile.v ../rtl/core/regfile.v
	$(VVP) tb_regfile.vvp

cpu: microcode prog $(CPU_RTL) tb_cpu.v
	$(IV) $(IFLAGS) -o tb_cpu.vvp tb_cpu.v $(CPU_RTL)
	$(VVP) tb_cpu.vvp

keyboard: ../rtl/board/ps2_rx.v ../rtl/board/ps2_keyboard.v tb_ps2_keyboard.v
	$(IV) $(IFLAGS) -o tb_ps2_keyboard.vvp tb_ps2_keyboard.v \
		../rtl/board/ps2_rx.v ../rtl/board/ps2_keyboard.v
	$(VVP) tb_ps2_keyboard.vvp

clean:
	rm -f *.vvp
