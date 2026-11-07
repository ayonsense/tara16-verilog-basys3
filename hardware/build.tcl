# build.tcl — TARA CPU → Basys3 bitstream + program the board (Vivado batch).
#
# Run from anywhere (with the Basys3 plugged in over USB):
#     vivado -mode batch -source build.tcl
# Build only, skip programming:
#     vivado -mode batch -source build.tcl -tclargs noprogram
#
# Fixes the two classes of path problem a multi-directory HDL project hits:
#   1. `include "ctrl_defs.vh"   -> resolved via -include_dirs (microcode/)
#   2. $readmemh("microcode.mem"/"boot.hex"/"splash4.mem") -> passed as ABSOLUTE paths via
#      -generic, so they are found regardless of the working directory.
#
# Layout: this script lives in hardware/. The RTL is in hardware/rtl and the
# constraints in hardware/constraints; the generated memory images come from the
# tools in ../tools (microcode, programs) and supplied ROM assets. Build products are written
# to ../build.
#
# Prereq: tools/microcode/microcode.mem and tools/programs/boot.hex exist.
# Regenerate them from the CPU/ root with:
#     python3 tools/microcode/gen_microcode.py
#     python3 tools/programs/gen_prog.py        # or: ... gen_prog.py your_program.tara

set origin [file dirname [file normalize [info script]]]
set root   [file normalize $origin/..]
set part   xc7a35tcpg236-1
set splash_en 1

file mkdir $root/build

# ---- read sources ----
read_verilog [glob $origin/rtl/*/*.v]
read_xdc     $origin/constraints/tara_basys3.xdc

# ---- synthesize ----
synth_design -top tara_top -part $part \
    -include_dirs $root/tools/microcode \
    -generic "MEM_FILE=$root/tools/microcode/microcode.mem" \
    -generic "PROG_FILE=$root/tools/programs/boot.hex" \
    -generic "FONT_FILE=$root/tools/assets/font8x16.mem" \
    -generic "MSG_FILE=$root/tools/assets/msg.mem" \
    -generic "SPLASH_FILE=$root/tools/assets/splash4.mem" \
    -generic "SPLASH_EN=$splash_en"

# ---- implement ----
opt_design
place_design
route_design

# ---- reports + bitstream ----
report_utilization -file $root/build/util.rpt
report_timing_summary -file $root/build/timing.rpt
set bit $root/build/tara_top.bit
write_bitstream -force $bit
puts "BITSTREAM -> $bit"

# ---- program the Basys3 over JTAG ----
set do_program 1
if {[lsearch -exact $argv "noprogram"] >= 0} { set do_program 0 }

if {$do_program} {
    if {[catch {
        open_hw_manager
        connect_hw_server
        open_hw_target
        set dev [lindex [get_hw_devices xc7a35t*] 0]
        if {$dev eq ""} { error "no xc7a35t device found on the JTAG chain" }
        current_hw_device $dev
        refresh_hw_device -update_hw_probes false $dev
        set_property PROGRAM.FILE $bit $dev
        program_hw_devices $dev
        refresh_hw_device $dev
        puts "PROGRAMMED $dev"
        close_hw_target
        disconnect_hw_server
        close_hw_manager
    } err]} {
        puts "WARNING: could not program the board: $err"
        puts "The bitstream is ready at $bit — program it manually, or re-run"
        puts "with the board connected. (Build itself succeeded.)"
    }
} else {
    puts "Skipping board programming (noprogram)."
}
puts "DONE."
