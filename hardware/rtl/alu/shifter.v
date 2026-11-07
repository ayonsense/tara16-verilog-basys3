// shifter.v — 16-bit logical barrel shifter (SHL / SHR), shamt 0..31.
// Shift amounts >= 16 yield 0, matching the golden simulator's masking.
`default_nettype none
module shifter (
    input  wire [15:0] in,
    input  wire [4:0]  shamt,
    input  wire        right,    // 0 = shift left (SHL), 1 = shift right (SHR)
    output wire [15:0] out
);
    assign out = right ? (in >> shamt) : (in << shamt);
endmodule
`default_nettype wire
