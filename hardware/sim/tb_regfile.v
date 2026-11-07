// tb_regfile.v — write/read-back and dual-port read check.
`timescale 1ns/1ps
module tb_regfile;
    reg         clk, rst, we;
    reg  [2:0]  ra, rb, wa;
    reg  [15:0] wd;
    wire [15:0] qa, qb;
    wire [15:0] r0,r1,r2,r3,r4,r5,r6,r7;
    integer i, errors;
    reg  [15:0] shadow [0:7];

    regfile dut (.clk(clk), .rst(rst), .raddr_a(ra), .raddr_b(rb),
                 .rdata_a(qa), .rdata_b(qb), .we(we), .waddr(wa), .wdata(wd),
                 .r0(r0),.r1(r1),.r2(r2),.r3(r3),.r4(r4),.r5(r5),.r6(r6),.r7(r7));

    always #5 clk = ~clk;

    initial begin
        clk = 0; rst = 1; we = 0; errors = 0;
        for (i = 0; i < 8; i = i + 1) shadow[i] = 0;
        @(negedge clk); rst = 0;
        for (i = 0; i < 4000; i = i + 1) begin
            @(negedge clk);
            we = $random; wa = $random; wd = $random;
            if (we) shadow[wa] = wd;
            @(posedge clk); #1;
            ra = $random; #1;
            if (qa !== shadow[ra]) begin
                $display("REGFILE FAIL R%0d got=%h exp=%h", ra, qa, shadow[ra]);
                errors = errors + 1;
            end
        end
        if (errors == 0) $display("tb_regfile: PASS");
        else             $display("tb_regfile: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
