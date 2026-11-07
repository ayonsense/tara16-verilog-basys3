// regfile.v — 8 x 16-bit register file, two async read ports, one sync write.
// R6 is the link register (CALL/RET); R7 is the stack pointer (PUSH/POP).
// Conventions are enforced by the microcode, not by this module.
`default_nettype none
module regfile (
    input  wire        clk,
    input  wire        rst,
    input  wire [2:0]  raddr_a,
    input  wire [2:0]  raddr_b,
    output wire [15:0] rdata_a,
    output wire [15:0] rdata_b,
    input  wire        we,
    input  wire [2:0]  waddr,
    input  wire [15:0] wdata,
    // debug taps
    output wire [15:0] r0, output wire [15:0] r1,
    output wire [15:0] r2, output wire [15:0] r3,
    output wire [15:0] r4, output wire [15:0] r5,
    output wire [15:0] r6, output wire [15:0] r7
);
    reg [15:0] regs [0:7];
    integer i;

    always @(posedge clk or posedge rst) begin     // async reset
        if (rst)
            for (i = 0; i < 8; i = i + 1) regs[i] <= 16'b0;
        else if (we)
            regs[waddr] <= wdata;
    end

    assign rdata_a = regs[raddr_a];
    assign rdata_b = regs[raddr_b];
    assign {r0,r1,r2,r3,r4,r5,r6,r7} =
        {regs[0],regs[1],regs[2],regs[3],regs[4],regs[5],regs[6],regs[7]};
endmodule
`default_nettype wire
