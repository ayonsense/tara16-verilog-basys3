// tara_cpu.v — TARA microprogrammed CPU: datapath + control + unified memory.
// One-to-one with the verified Python model (model/tara_pymodel.py): the same
// 40-bit control words drive the same PC/IR/MAR/MDR/regfile/ALU datapath.

`default_nettype none
`include "ctrl_defs.vh"
module tara_cpu #(
    parameter MEM_FILE   = "microcode.mem",   // control store
    parameter PROG_FILE  = "",                // boot program ($readmemh bytes)
    parameter ADDER_STYLE = 1                 // 0=RCA, 1=CLA for ADD/SUB/SLT
) (
    input  wire        clk,         // CPU clock (slow / stoppable)
    input  wire        clk_mem,     // memory write clock (always-on, e.g. 100 MHz)
    input  wire        rst,
    // boot loader port (ESP32 / GPIO, future)
    input  wire        ld_we,
    input  wire [10:0] ld_addr,
    input  wire [7:0]  ld_data,
    // memory-mapped game inputs (read at 0x5FF)
    input  wire [7:0]  key_bits,
    // host monitor read port (async word read; byte address)
    input  wire [10:0] host_addr,
    output wire [15:0] host_rword,
    // VGA framebuffer read port
    input  wire [8:0]  vga_addr,
    output wire [7:0]  vga_rbyte,
    // debug / observation
    output wire [15:0] dbg_pc,
    output wire [15:0] dbg_ir,
    output wire [2:0]  dbg_tstate,
    output wire        dbg_halted,
    output wire [3:0]  dbg_flags,             // {Z,N,C,V}
    output wire [15:0] dbg_r0, output wire [15:0] dbg_r1,
    output wire [15:0] dbg_r2, output wire [15:0] dbg_r3,
    output wire [15:0] dbg_r4, output wire [15:0] dbg_r5,
    output wire [15:0] dbg_r6, output wire [15:0] dbg_r7
);
    // ── control ──
    wire [`CW_WIDTH-1:0] cw;
    wire [2:0]          tstate;
    wire [7:0]          t_onehot;
    wire                halted;
    wire [15:0]         ir_out;

    control_unit #(.MEM_FILE(MEM_FILE)) ctrl_u (
        .clk(clk), .rst(rst), .opcode(ir_out[15:11]),
        .cw(cw), .tstate(tstate), .tstate_onehot(t_onehot), .halted(halted)
    );

    // ── IR field decode ──
    wire [2:0]  rd   = ir_out[10:8];
    wire [2:0]  rsA  = ir_out[7:5];
    wire [2:0]  rsB  = ir_out[4:2];
    wire [7:0]  imm8 = ir_out[7:0];
    wire [4:0]  off5 = ir_out[4:0];
    wire [7:0]  rel8 = ir_out[7:0];
    wire [10:0] rel11= ir_out[10:0];
    wire [4:0]  opcode = ir_out[15:11];

    wire is_jmp_call = (opcode == 5'd22) || (opcode == 5'd23);
    wire [15:0] branch_rel = is_jmp_call ? {{4{rel11[10]}}, rel11, 1'b0}
                                         : {{7{rel8[7]}},  rel8,  1'b0};

    // ── register-file address muxes ──
    reg [2:0] rfa_addr, rfb_addr, rfw_addr;
    always @(*) begin
        case (`CW_RFA_SEL(cw))
            2'd0: rfa_addr = rsA;
            2'd1: rfa_addr = rd;
            2'd2: rfa_addr = 3'd6;
            default: rfa_addr = 3'd7;
        endcase
        case (`CW_RFB_SEL(cw))
            2'd0: rfb_addr = rsB;
            2'd1: rfb_addr = rd;
            2'd2: rfb_addr = 3'd7;
            default: rfb_addr = 3'd6;
        endcase
        case (`CW_RFW_SEL(cw))
            2'd0: rfw_addr = rd;
            2'd1: rfw_addr = 3'd6;
            default: rfw_addr = 3'd7;
        endcase
    end

    wire [15:0] rdA, rdB;
    wire [15:0] pc_out;

    // ── ALU operand muxes ──
    wire [15:0] alu_a = `CW_ALU_A(cw) ? pc_out : rdA;
    reg  [15:0] alu_b;
    always @(*) begin
        case (`CW_ALU_B(cw))
            3'd0: alu_b = rdB;
            3'd1: alu_b = {{11{off5[4]}}, off5};      // sext5(off5)
            3'd2: alu_b = {{8{imm8[7]}}, imm8};       // sext8(imm8)
            3'd3: alu_b = 16'd2;                      // const 2
            3'd4: alu_b = branch_rel;                 // sext(rel)<<1
            3'd5: alu_b = {11'b0, imm8[4:0]};         // shamt
            default: alu_b = 16'd0;
        endcase
    end

    wire [15:0] alu_y;
    wire f_z, f_n, f_c, f_v;
    alu #(.ADDER_STYLE(ADDER_STYLE)) alu_u (
        .op(`CW_ALU_OP(cw)), .a(alu_a), .b(alu_b), .y(alu_y),
        .f_zero(f_z), .f_neg(f_n), .f_carry(f_c), .f_ovf(f_v)
    );

    // ── branch comparator (independent of status flags) ──
    wire is_zero = (rdA == 16'b0);
    wire is_neg  = rdA[15];
    reg  take;
    always @(*) case (`CW_PC_COND(cw))
        2'd0: take = 1'b1;
        2'd1: take = is_zero;
        2'd2: take = is_neg;
        default: take = 1'b1;
    endcase

    // ── memory ──
    wire [10:0] mar_out;
    wire [15:0] mdr_out;
    wire [15:0] mem_rdata;

    memory #(.INIT_FILE(PROG_FILE)) mem_u (
        .clk(clk_mem),                       // write port on the always-on clock
        .cpu_addr(mar_out), .cpu_byte(`CW_MEM_BYTE(cw)),
        .cpu_we(`CW_MEM_WE(cw)), .cpu_wdata(mdr_out), .cpu_rdata(mem_rdata),
        .key_bits(key_bits),
        .host_addr(host_addr), .host_rword(host_rword),
        .vga_addr(vga_addr), .vga_rbyte(vga_rbyte),
        .ld_we(ld_we), .ld_addr(ld_addr), .ld_data(ld_data)
    );

    // ── datapath registers ──
    pc pc_u (
        .clk(clk), .rst(rst),
        .inc(`CW_PC_INC(cw)),
        .load(`CW_PC_LOAD(cw) & take),
        .din(`CW_PC_SRC(cw) ? rdA : alu_y),
        .pc_out(pc_out)
    );

    ir ir_u (
        .clk(clk), .rst(rst), .load(`CW_IR_LOAD(cw)),
        .din(mdr_out), .ir_out(ir_out)
    );

    mar mar_u (
        .clk(clk), .rst(rst), .load(`CW_MAR_LOAD(cw)),
        .din(`CW_MAR_SRC(cw) ? alu_y : pc_out), .mar_out(mar_out)
    );

    mdr mdr_u (
        .clk(clk), .rst(rst), .load(`CW_MDR_LOAD(cw)),
        .din(`CW_MDR_SRC(cw) ? rdB : mem_rdata), .mdr_out(mdr_out)
    );

    // ── regfile write-data mux ──
    reg [15:0] rf_wdata;
    always @(*) begin
        case (`CW_RFW_SRC(cw))
            3'd0: rf_wdata = alu_y;                         // ALU result
            3'd1: rf_wdata = mdr_out;                       // memory load
            3'd2: rf_wdata = {8'b0, imm8};                  // LIL
            3'd3: rf_wdata = {imm8, rdA[7:0]};              // LIH
            3'd4: rf_wdata = pc_out;                        // PC link (CALL)
            default: rf_wdata = 16'b0;
        endcase
    end

    regfile rf_u (
        .clk(clk), .rst(rst),
        .raddr_a(rfa_addr), .raddr_b(rfb_addr),
        .rdata_a(rdA), .rdata_b(rdB),
        .we(`CW_RF_WE(cw)), .waddr(rfw_addr), .wdata(rf_wdata),
        .r0(dbg_r0), .r1(dbg_r1), .r2(dbg_r2), .r3(dbg_r3),
        .r4(dbg_r4), .r5(dbg_r5), .r6(dbg_r6), .r7(dbg_r7)
    );

    // ── status register (observational) ──
    wire s_z, s_n, s_c, s_v;
    status_reg st_u (
        .clk(clk), .rst(rst), .we(`CW_STATUS_WE(cw)),
        .z_in(f_z), .n_in(f_n), .c_in(f_c), .v_in(f_v),
        .z(s_z), .n(s_n), .c(s_c), .v(s_v)
    );

    // ── debug taps ──
    assign dbg_pc     = pc_out;
    assign dbg_ir     = ir_out;
    assign dbg_tstate = tstate;
    assign dbg_halted = halted;
    assign dbg_flags  = {s_z, s_n, s_c, s_v};
endmodule
`default_nettype wire
