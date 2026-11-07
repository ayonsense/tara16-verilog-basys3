// prog_loader.v — serial boot loader hook for the future ESP32 link.
//
// The long-term plan is an ESP32 that receives TARA machine code over the air
// and clocks it into the board over a few GPIO wires. This module is that
// receiver: a simple 3-wire serial loader (active, sclk, sdata) that shifts in
// bytes MSB-first and writes them sequentially into memory starting at 0x000,
// holding the CPU in reset (`loading`) until the transfer ends.
//
//   active : high for the whole transfer (resets the write pointer on its edge)
//   sclk   : one rising edge per bit (ESP32-driven)
//   sdata  : the bit, sampled on sclk's rising edge
//
// For the current Vivado bring-up this stays idle (active=0) and the program is
// baked in via memory.v's $readmemh; nothing else changes when the ESP32 lands.
`default_nettype none
module prog_loader (
    input  wire        clk,        // board clock (100 MHz)
    input  wire        active,
    input  wire        sclk,
    input  wire        sdata,
    output reg         ld_we,
    output reg  [10:0] ld_addr,
    output reg  [7:0]  ld_data,
    output wire        loading
);
    // synchronize async inputs
    reg [2:0] act_s, sclk_s, sdat_s;
    always @(posedge clk) begin
        act_s  <= {act_s[1:0],  active};
        sclk_s <= {sclk_s[1:0], sclk};
        sdat_s <= {sdat_s[1:0], sdata};
    end
    wire act      = act_s[2];
    wire act_rise = act_s[1] & ~act_s[2];
    wire sclk_rise= sclk_s[1] & ~sclk_s[2];
    wire bit_in   = sdat_s[2];

    reg [2:0] bitcnt;
    reg [7:0] shreg;

    always @(posedge clk) begin
        ld_we <= 1'b0;
        if (act_rise) begin
            ld_addr <= 11'd0;
            bitcnt  <= 3'd0;
        end else if (act && sclk_rise) begin
            shreg <= {shreg[6:0], bit_in};
            if (bitcnt == 3'd7) begin
                ld_data <= {shreg[6:0], bit_in};   // completed byte
                ld_we   <= 1'b1;
                bitcnt  <= 3'd0;
            end else begin
                bitcnt  <= bitcnt + 3'd1;
            end
        end else if (ld_we) begin
            ld_addr <= ld_addr + 11'd1;            // advance after each write
        end
    end

    assign loading = act;
endmodule
`default_nettype wire
