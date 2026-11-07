// tb_adders.v — randomised check of rca16 and cla16 against Verilog '+'.
`timescale 1ns/1ps
module tb_adders;
    reg  [15:0] a, b;
    reg         cin;
    wire [15:0] s_rca, s_cla;
    wire        c_rca, c_cla;
    integer i, errors;

    rca16 u_rca (.a(a), .b(b), .cin(cin), .sum(s_rca), .cout(c_rca));
    cla16 u_cla (.a(a), .b(b), .cin(cin), .sum(s_cla), .cout(c_cla));

    initial begin
        errors = 0;
        for (i = 0; i < 20000; i = i + 1) begin
            a = $random; b = $random; cin = $random;
            #1;
            if ({c_rca, s_rca} !== (a + b + cin)) begin
                $display("RCA FAIL a=%h b=%h cin=%b got=%h exp=%h",
                         a, b, cin, {c_rca,s_rca}, (a+b+cin)); errors = errors + 1;
            end
            if ({c_cla, s_cla} !== (a + b + cin)) begin
                $display("CLA FAIL a=%h b=%h cin=%b got=%h exp=%h",
                         a, b, cin, {c_cla,s_cla}, (a+b+cin)); errors = errors + 1;
            end
            if (s_rca !== s_cla) begin
                $display("RCA/CLA DIFFER a=%h b=%h", a, b); errors = errors + 1;
            end
        end
        if (errors == 0) $display("tb_adders: PASS (40000 checks)");
        else             $display("tb_adders: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
