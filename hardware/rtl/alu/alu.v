// alu.v — TARA ALU. Combinational; op codes match microcode/ctrl_defs.vh.
//   0 ADD 1 SUB 2 MUL 3 AND 4 OR 5 XOR 6 NOT 7 SHL 8 SHR 9 SLT 10 PASSA 11 PASSB
//
// ADDER_STYLE selects the structural adder used for ADD/SUB/SLT so students can
// compare a ripple-carry against a carry-lookahead implementation:
//   ADDER_STYLE = 0 -> rca16   (ripple carry)
//   ADDER_STYLE = 1 -> cla16   (carry lookahead)
`default_nettype none
module alu #(
    parameter ADDER_STYLE = 1
) (
    input  wire [3:0]  op,
    input  wire [15:0] a,
    input  wire [15:0] b,
    output reg  [15:0] y,
    output wire        f_zero,
    output wire        f_neg,
    output wire        f_carry,
    output wire        f_ovf
);
    localparam ALU_ADD=0, ALU_SUB=1, ALU_MUL=2, ALU_AND=3, ALU_OR=4,
               ALU_XOR=5, ALU_NOT=6, ALU_SHL=7, ALU_SHR=8, ALU_SLT=9,
               ALU_PASSA=10, ALU_PASSB=11;

    // ── adder shared by ADD / SUB / SLT ──
    wire        sub   = (op == ALU_SUB) || (op == ALU_SLT);
    wire [15:0] b_eff = sub ? ~b : b;
    wire        cin   = sub ? 1'b1 : 1'b0;
    wire [15:0] sum;
    wire        cout;

    generate
        if (ADDER_STYLE == 0)
            rca16 add_u (.a(a), .b(b_eff), .cin(cin), .sum(sum), .cout(cout));
        else
            cla16 add_u (.a(a), .b(b_eff), .cin(cin), .sum(sum), .cout(cout));
    endgenerate

    wire ovf = (~(a[15] ^ b_eff[15])) & (a[15] ^ sum[15]);
    wire slt = sum[15] ^ ovf;            // signed a < b

    // ── logic / shift / multiply units ──
    wire [15:0] logic_y;
    reg  [1:0]  logic_sel;
    always @(*) case (op)
        ALU_AND: logic_sel = 2'd0;
        ALU_OR : logic_sel = 2'd1;
        ALU_XOR: logic_sel = 2'd2;
        default: logic_sel = 2'd3;       // NOT
    endcase
    logic_unit lu (.a(a), .b(b), .sel(logic_sel), .y(logic_y));

    wire [15:0] shift_y;
    shifter sh (.in(a), .shamt(b[4:0]), .right(op == ALU_SHR), .out(shift_y));

    wire [31:0] prod;
    mult16 mul (.a(a), .b(b), .p(prod));

    // ── result mux ──
    always @(*) begin
        case (op)
            ALU_ADD, ALU_SUB: y = sum;
            ALU_MUL:          y = prod[15:0];
            ALU_AND, ALU_OR, ALU_XOR, ALU_NOT: y = logic_y;
            ALU_SHL, ALU_SHR: y = shift_y;
            ALU_SLT:          y = {15'b0, slt};
            ALU_PASSA:        y = a;
            ALU_PASSB:        y = b;
            default:          y = 16'b0;
        endcase
    end

    assign f_zero  = (y == 16'b0);
    assign f_neg   = y[15];
    assign f_carry = cout;               // meaningful for ADD/SUB
    assign f_ovf   = ovf;
endmodule
`default_nettype wire
