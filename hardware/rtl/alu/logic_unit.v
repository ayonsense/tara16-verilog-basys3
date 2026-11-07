// logic_unit.v — bitwise AND / OR / XOR / NOT(a).
`default_nettype none
module logic_unit (
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire [1:0]  sel,     // 0=AND, 1=OR, 2=XOR, 3=NOT a
    output reg  [15:0] y
);
    always @(*) begin
        case (sel)
            2'd0: y = a & b;
            2'd1: y = a | b;
            2'd2: y = a ^ b;
            default: y = ~a;
        endcase
    end
endmodule
`default_nettype wire
