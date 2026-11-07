// cla16.v — 16-bit carry-lookahead adder: four cla4 blocks with a
// second-level lookahead over the block generate/propagate signals.
`default_nettype none
module cla16 (
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire        cin,
    output wire [15:0] sum,
    output wire        cout
);
    wire [3:0] pg, gg;          // per-block propagate / generate
    wire c0 = cin;

    // second-level (block) carries
    wire c1 = gg[0] | (pg[0] & c0);
    wire c2 = gg[1] | (pg[1] & gg[0]) | (pg[1] & pg[0] & c0);
    wire c3 = gg[2] | (pg[2] & gg[1]) | (pg[2] & pg[1] & gg[0]) | (pg[2] & pg[1] & pg[0] & c0);
    wire c4 = gg[3] | (pg[3] & gg[2]) | (pg[3] & pg[2] & gg[1])
                    | (pg[3] & pg[2] & pg[1] & gg[0]) | (pg[3] & pg[2] & pg[1] & pg[0] & c0);

    cla4 b0 (.a(a[ 3: 0]), .b(b[ 3: 0]), .cin(c0), .sum(sum[ 3: 0]), .cout(), .pg(pg[0]), .gg(gg[0]));
    cla4 b1 (.a(a[ 7: 4]), .b(b[ 7: 4]), .cin(c1), .sum(sum[ 7: 4]), .cout(), .pg(pg[1]), .gg(gg[1]));
    cla4 b2 (.a(a[11: 8]), .b(b[11: 8]), .cin(c2), .sum(sum[11: 8]), .cout(), .pg(pg[2]), .gg(gg[2]));
    cla4 b3 (.a(a[15:12]), .b(b[15:12]), .cin(c3), .sum(sum[15:12]), .cout(), .pg(pg[3]), .gg(gg[3]));

    assign cout = c4;
endmodule
`default_nettype wire
