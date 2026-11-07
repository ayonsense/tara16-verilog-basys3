// mult16.v — 16x16 unsigned multiplier (combinational shift-add).
// Produces the full 32-bit product; the ALU keeps the low 16 bits (MUL).
`default_nettype none
module mult16 (
    input  wire [15:0] a,
    input  wire [15:0] b,
    output wire [31:0] p
);
    // Explicit shift-add of the 16 partial products (teaching form).
    integer i;
    reg [31:0] acc;
    always @(*) begin
        acc = 32'd0;
        for (i = 0; i < 16; i = i + 1)
            if (b[i]) acc = acc + ({16'b0, a} << i);
    end
    assign p = acc;
endmodule
`default_nettype wire
