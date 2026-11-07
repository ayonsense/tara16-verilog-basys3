PYTHON ?= python3
VIVADO ?= vivado
.DEFAULT_GOAL := help
.PHONY: help test verify bitstream program flash
help:
	@printf '%s\n' 'make test       Run RTL tests' 'make verify     Compare microcode model with Studio' 'make bitstream  Build Basys 3 image (requires Vivado)' 'make program    Program FPGA SRAM' 'make flash      Program persistent SPI flash'
test:
	$(MAKE) -C hardware/sim
verify:
	$(PYTHON) tools/model/verify.py
bitstream:
	$(VIVADO) -mode batch -notrace -source hardware/build.tcl -tclargs noprogram
program:
	openFPGALoader -b basys3 build/tara_top.bit
flash:
	openFPGALoader -b basys3 --write-flash --verify --reset build/tara_top.bit
