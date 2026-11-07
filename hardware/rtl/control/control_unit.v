// control_unit.v — microsequencer. Generates the per-cycle control word for the
// datapath from {opcode, Tstate}, drives the ring counter, and latches HLT.
//
// While halted, the effective control word is forced to 0 (all register-load
// enables off) and the ring counter is frozen, so the CPU does nothing until
// reset — even though the clock keeps toggling.
`default_nettype none
`include "ctrl_defs.vh"
module control_unit #(
    parameter MEM_FILE = "microcode.mem"
) (
    input  wire                clk,
    input  wire                rst,
    input  wire [4:0]           opcode,        // IR[15:11]
    output wire [`CW_WIDTH-1:0]  cw,            // effective control word
    output wire [2:0]           tstate,
    output wire [7:0]           tstate_onehot,
    output reg                  halted
);
    wire [`CW_WIDTH-1:0] cw_raw;
    wire [2:0]           t;
    wire [7:0]           oneh;

    // microcode lookup
    control_rom #(.MEM_FILE(MEM_FILE), .CW_WIDTH(`CW_WIDTH)) rom_u (
        .addr({opcode, t}), .cw(cw_raw)
    );

    // gate everything off while halted
    wire [`CW_WIDTH-1:0] cw_eff = halted ? {`CW_WIDTH{1'b0}} : cw_raw;
    assign cw            = cw_eff;
    assign tstate        = t;
    assign tstate_onehot = oneh;

    initial halted = 1'b0;          // self-start un-halted at config

    wire done     = `CW_DONE(cw_eff);
    wire halt_bit = `CW_HALT(cw_eff);

    ring_counter ring_u (
        .clk(clk), .rst(rst), .en(~halted), .restart(done),
        .onehot(oneh), .tstate(t)
    );

    always @(posedge clk or posedge rst) begin     // async reset
        if (rst)            halted <= 1'b0;
        else if (halt_bit)  halted <= 1'b1;
    end
endmodule
`default_nettype wire
