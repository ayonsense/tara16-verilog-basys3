// mar.v — 11-bit memory address register (addresses the 2 KB memory).
`default_nettype none
module mar (
    input  wire        clk,
    input  wire        rst,
    input  wire        load,
    input  wire [15:0] din,
    output reg  [10:0] mar_out
);
    always @(posedge clk or posedge rst) begin     // async reset
        if (rst)       mar_out <= 11'b0;
        else if (load) mar_out <= din[10:0];
    end
endmodule
`default_nettype wire
