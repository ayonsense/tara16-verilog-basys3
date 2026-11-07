// ps2_keyboard.v — turns PS/2 scancodes (Set 2) into TARA board controls.
//
// Tracks make/break (F0 prefix) and extended (E0 prefix) codes and holds a
// level per key. Arrow keys and WASD produce the game-direction bits read at
// 0x5FF. Q is a keyboard reset request, equivalent to Basys3 btnC.
//
//   UP    : Up arrow (E0 75) or W (1D)        DOWN  : Down arrow (E0 72) or S (1B)
//   LEFT  : Left arrow (E0 6B) or A (1C)       RIGHT : Right arrow (E0 74) or D (23)
//   RESET : Q (15)
`default_nettype none
module ps2_keyboard (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] sc,           // scancode byte from ps2_rx
    input  wire       sc_valid,     // 1-cycle strobe
    output reg  [4:0] keys,         // {unused,RIGHT,LEFT,DOWN,UP} held levels
    output reg        reset_req     // held while Q is pressed
);
    // Set-2 scancodes
    localparam [7:0] W=8'h1D, A=8'h1C, S=8'h1B, D=8'h23, Q=8'h15;
    localparam [7:0] E_UP=8'h75, E_DOWN=8'h72, E_LEFT=8'h6B, E_RIGHT=8'h74;
    localparam [7:0] EXT=8'hE0, BRK=8'hF0;

    reg extended = 1'b0;            // last code was E0
    reg break_   = 1'b0;           // last code was F0 (this is a key release)

    always @(posedge clk) begin
        if (rst) begin
            keys <= 5'b0; reset_req <= 1'b0; extended <= 1'b0; break_ <= 1'b0;
        end else if (sc_valid) begin
            if (sc == EXT)       extended <= 1'b1;
            else if (sc == BRK)  break_   <= 1'b1;
            else begin
                // make sets the bit (~break_ = 1), break clears it (~break_ = 0)
                if ((extended && sc==E_UP)    || (!extended && sc==W)) keys[0] <= ~break_;
                if ((extended && sc==E_DOWN)  || (!extended && sc==S)) keys[1] <= ~break_;
                if ((extended && sc==E_LEFT)  || (!extended && sc==A)) keys[2] <= ~break_;
                if ((extended && sc==E_RIGHT) || (!extended && sc==D)) keys[3] <= ~break_;
                if (!extended && sc==Q)                                reset_req <= ~break_;
                extended <= 1'b0;
                break_   <= 1'b0;
            end
        end
    end
endmodule
`default_nettype wire
