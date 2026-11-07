// cla4.v — 4-bit carry-lookahead adder block.
// Exposes block generate (gg) / propagate (pg) for a second-level lookahead.
`default_nettype none
module cla4 (
    input  wire [3:0] a,
    input  wire [3:0] b,
    input  wire       cin,
    output wire [3:0] sum,
    output wire       cout,   // local carry-out (for standalone use)
    output wire       pg,     // group propagate  = &p
    output wire       gg      // group generate
);
    wire [3:0] g = a & b;     // generate
    wire [3:0] p = a ^ b;     // propagate

    wire c1 =  g[0] | (p[0] & cin);
    wire c2 =  g[1] | (p[1] & g[0]) | (p[1] & p[0] & cin);
    wire c3 =  g[2] | (p[2] & g[1]) | (p[2] & p[1] & g[0]) | (p[2] & p[1] & p[0] & cin);

    assign sum[0] = p[0] ^ cin;
    assign sum[1] = p[1] ^ c1;
    assign sum[2] = p[2] ^ c2;
    assign sum[3] = p[3] ^ c3;

    assign gg   = g[3] | (p[3] & g[2]) | (p[3] & p[2] & g[1]) | (p[3] & p[2] & p[1] & g[0]);
    assign pg   = &p;
    assign cout = gg | (pg & cin);
endmodule
`default_nettype wire
