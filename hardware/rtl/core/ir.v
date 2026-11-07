// ir.v — 16-bit instruction register.
`default_nettype none
module ir (
    input  wire        clk,
    input  wire        rst,
    input  wire        load,
    input  wire [15:0] din,
    output reg  [15:0] ir_out
);
    always @(posedge clk or posedge rst) begin     // async reset
        if (rst)       ir_out <= 16'b0;
        else if (load) ir_out <= din;
    end
endmodule
`default_nettype wire
