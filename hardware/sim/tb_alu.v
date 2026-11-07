// tb_alu.v — randomised check of the ALU against behavioural references.
`timescale 1ns/1ps
module tb_alu;
    reg  [3:0]  op;
    reg  [15:0] a, b;
    wire [15:0] y;
    wire        z, n, c, v;
    integer i, k, errors;
    reg  [15:0] exp;

    localparam ADD=0,SUB=1,MUL=2,AND=3,OR=4,XOR=5,NOT=6,SHL=7,SHR=8,SLT=9,PA=10,PB=11;

    alu #(.ADDER_STYLE(1)) dut (.op(op), .a(a), .b(b), .y(y),
                                .f_zero(z), .f_neg(n), .f_carry(c), .f_ovf(v));

    function [15:0] ref_alu(input [3:0] o, input [15:0] x, input [15:0] w);
        begin
            case (o)
                ADD: ref_alu = x + w;
                SUB: ref_alu = x - w;
                MUL: ref_alu = x * w;
                AND: ref_alu = x & w;
                OR : ref_alu = x | w;
                XOR: ref_alu = x ^ w;
                NOT: ref_alu = ~x;
                SHL: ref_alu = x << (w[4:0]);
                SHR: ref_alu = x >> (w[4:0]);
                SLT: ref_alu = ($signed(x) < $signed(w)) ? 16'd1 : 16'd0;
                PA : ref_alu = x;
                PB : ref_alu = w;
                default: ref_alu = 16'h0;
            endcase
        end
    endfunction

    initial begin
        errors = 0;
        for (i = 0; i < 30000; i = i + 1) begin
            a = $random; b = $random;
            for (k = 0; k <= 11; k = k + 1) begin
                op = k[3:0]; #1;
                exp = ref_alu(op, a, b);
                if (y !== exp) begin
                    $display("ALU FAIL op=%0d a=%h b=%h got=%h exp=%h",
                             op, a, b, y, exp); errors = errors + 1;
                end
                if (z !== (y == 16'b0)) begin
                    $display("ALU Z FAIL op=%0d y=%h z=%b", op, y, z);
                    errors = errors + 1;
                end
            end
        end
        if (errors == 0) $display("tb_alu: PASS");
        else             $display("tb_alu: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
