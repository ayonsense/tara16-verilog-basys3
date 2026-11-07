// seg7.v — 4-digit hex display driver for the Basys3 7-segment display.
// Shows a 16-bit value in hex; segments and anodes are active-LOW.
`default_nettype none
module seg7 (
    input  wire        clk,        // board clock (100 MHz)
    input  wire [15:0] value,
    output reg  [6:0]  seg,        // {g,f,e,d,c,b,a} active-low
    output reg  [3:0]  an          // active-low digit enables
);
    reg [16:0] refresh = 17'b0;
    always @(posedge clk) refresh <= refresh + 1'b1;
    wire [1:0] sel = refresh[16:15];   // ~1.5 kHz per digit

    reg [3:0] nib;
    always @(*) begin
        case (sel)
            2'd0: begin an = 4'b1110; nib = value[3:0];   end
            2'd1: begin an = 4'b1101; nib = value[7:4];   end
            2'd2: begin an = 4'b1011; nib = value[11:8];  end
            default: begin an = 4'b0111; nib = value[15:12]; end
        endcase
    end

    always @(*) begin
        case (nib)                     // active-low {g,f,e,d,c,b,a}
            4'h0: seg = 7'b1000000;  4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;  4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;  4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;  4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;  4'h9: seg = 7'b0010000;
            4'hA: seg = 7'b0001000;  4'hB: seg = 7'b0000011;
            4'hC: seg = 7'b1000110;  4'hD: seg = 7'b0100001;
            4'hE: seg = 7'b0000110;  default: seg = 7'b0001110;  // F
        endcase
    end
endmodule
`default_nettype wire
