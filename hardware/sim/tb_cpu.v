// tb_cpu.v — whole-CPU test: load boot.hex, free-run to HLT, check registers
// against the golden simulator's expected state (prog/boot_expected.vh).
`timescale 1ns/1ps
module tb_cpu;
    reg clk, rst;
    wire [15:0] pc, ir;
    wire [2:0]  tstate;
    wire        halted;
    wire [3:0]  flags;
    wire [15:0] r0,r1,r2,r3,r4,r5,r6,r7;
    integer cyc, errors;

    `include "boot_expected.vh"

    tara_cpu #(
        .MEM_FILE ("../../tools/microcode/microcode.mem"),
        .PROG_FILE("build/boot.hex"),
        .ADDER_STYLE(1)
    ) dut (
        .clk(clk), .clk_mem(clk), .rst(rst),
        .ld_we(1'b0), .ld_addr(11'b0), .ld_data(8'b0),
        .key_bits(8'b0), .host_addr(11'b0), .host_rword(),
        .vga_addr(9'b0), .vga_rbyte(),
        .dbg_pc(pc), .dbg_ir(ir), .dbg_tstate(tstate),
        .dbg_halted(halted), .dbg_flags(flags),
        .dbg_r0(r0),.dbg_r1(r1),.dbg_r2(r2),.dbg_r3(r3),
        .dbg_r4(r4),.dbg_r5(r5),.dbg_r6(r6),.dbg_r7(r7)
    );

    always #5 clk = ~clk;

    task chk(input [15:0] got, input [15:0] exp, input [127:0] nm);
        begin
            if (got !== exp) begin
                $display("  %0s FAIL got=%h exp=%h", nm, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 0; rst = 1; errors = 0; cyc = 0;
        repeat (4) @(negedge clk);
        rst = 0;

        // run until halt or timeout
        while (!halted && cyc < 200000) begin
            @(posedge clk); cyc = cyc + 1;
        end

        if (!halted) begin
            $fatal(1, "tb_cpu: FAIL — CPU did not halt within %0d cycles", cyc);
        end

        $display("tb_cpu: halted after %0d CPU clocks. PC=%h", cyc, pc);
        chk(r0, EXP_R0, "R0"); chk(r1, EXP_R1, "R1");
        chk(r2, EXP_R2, "R2"); chk(r3, EXP_R3, "R3");
        chk(r4, EXP_R4, "R4"); chk(r5, EXP_R5, "R5");
        chk(r6, EXP_R6, "R6"); chk(r7, EXP_R7, "R7");

        if (errors == 0) begin
            $display("tb_cpu: PASS (all registers match golden)");
            $finish;
        end else begin
            $fatal(1, "tb_cpu: FAIL (%0d register mismatches)", errors);
        end
    end
endmodule
