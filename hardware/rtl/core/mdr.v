// mdr.v — 16-bit memory data register (holds word read from / to be written
// to memory, or a register value being stored).
`default_nettype none
module mdr (
    input  wire        clk,
    input  wire        rst,
    input  wire        load,
    input  wire [15:0] din,
    output reg  [15:0] mdr_out
);
    always @(posedge clk or posedge rst) begin     // async reset
        if (rst)       mdr_out <= 16'b0;
        else if (load) mdr_out <= din;
    end
endmodule
`default_nettype wire
