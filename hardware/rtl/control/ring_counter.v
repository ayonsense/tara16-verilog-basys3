// ring_counter.v — T-state generator (one-hot ring, 8 states T0..T7).
// Restart forces T0 (end of an instruction); en gates advancement (halt/stall).
// Outputs both the one-hot ring (handy on LEDs) and the encoded 3-bit Tstate.
`default_nettype none
module ring_counter (
    input  wire       clk,
    input  wire       rst,
    input  wire       en,         // advance when high
    input  wire       restart,    // force back to T0 next edge ('done')
    output reg  [7:0] onehot,
    output reg  [2:0] tstate
);
    // Power-on value MUST be T0 (not 0): on FPGA config the FFs come up at this
    // value, so the CPU self-starts at T0 even before any reset is pressed.
    // (Rotating an all-zero onehot would stay zero and freeze the CPU.)
    initial onehot = 8'b0000_0001;

    always @(posedge clk or posedge rst) begin     // async reset
        if (rst)            onehot <= 8'b0000_0001;
        else if (restart)   onehot <= 8'b0000_0001;
        else if (en)        onehot <= {onehot[6:0], onehot[7]};   // rotate left
    end

    always @(*) begin
        case (onehot)
            8'b0000_0001: tstate = 3'd0;
            8'b0000_0010: tstate = 3'd1;
            8'b0000_0100: tstate = 3'd2;
            8'b0000_1000: tstate = 3'd3;
            8'b0001_0000: tstate = 3'd4;
            8'b0010_0000: tstate = 3'd5;
            8'b0100_0000: tstate = 3'd6;
            default:      tstate = 3'd7;
        endcase
    end
endmodule
`default_nettype wire
