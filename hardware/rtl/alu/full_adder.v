// full_adder.v — 1-bit full adder (the cell RCA/CLA are built from).
`default_nettype none
module full_adder (
    input  wire a,
    input  wire b,
    input  wire cin,
    output wire sum,
    output wire cout
);
    assign sum  = a ^ b ^ cin;
    assign cout = (a & b) | (a & cin) | (b & cin);
endmodule
`default_nettype wire
