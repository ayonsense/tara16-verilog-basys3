// rca16.v — 16-bit ripple-carry adder, structurally from full_adder cells.
// Teaching baseline: simple, long carry chain. Compare against cla16.
`default_nettype none
module rca16 (
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire        cin,
    output wire [15:0] sum,
    output wire        cout
);
    wire [16:0] c;
    assign c[0] = cin;
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : bit_slice
            full_adder fa (.a(a[i]), .b(b[i]), .cin(c[i]),
                           .sum(sum[i]), .cout(c[i+1]));
        end
    endgenerate
    assign cout = c[16];
endmodule
`default_nettype wire
