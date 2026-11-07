// pc.v — program counter. 11-bit effective address space (mem is 2 KB),
// stored in 16 bits but masked to 0x7FF, matching the golden simulator.
// load has priority over inc (they are never asserted together in microcode).
`default_nettype none
module pc (
    input  wire        clk,
    input  wire        rst,
    input  wire        inc,         // PC <- PC + 2
    input  wire        load,        // PC <- din  (already condition-gated)
    input  wire [15:0] din,
    output reg  [15:0] pc_out
);
    always @(posedge clk or posedge rst) begin     // async reset
        if (rst)        pc_out <= 16'b0;
        else if (load)  pc_out <= din & 16'h07FF;
        else if (inc)   pc_out <= (pc_out + 16'd2) & 16'h07FF;
    end
endmodule
`default_nettype wire
