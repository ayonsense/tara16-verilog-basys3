// ps2_rx.v — PS/2 receiver (device -> host). On the Basys3 the USB-HID bridge
// presents a USB keyboard as a PS/2 device on PS2Clk (C17) / PS2Data (B17).
//
// The keyboard supplies the clock (~10-17 kHz). Each frame is 11 bits, sampled
// on the FALLING edge of PS2Clk: start(0), data[0..7] LSB-first, odd parity,
// stop(1). This module synchronizes the lines to the 100 MHz domain, assembles
// one byte per frame, and pulses `valid` for one clk when a scancode is ready.
`default_nettype none
module ps2_rx (
    input  wire       clk,          // 100 MHz system clock
    input  wire       rst,
    input  wire       ps2_clk_in,   // PS2Clk  (async, open-collector w/ pullup)
    input  wire       ps2_data_in,  // PS2Data (async)
    output reg  [7:0] data,         // received scancode byte
    output reg        valid         // 1-cycle strobe when `data` is fresh
);
    // ── synchronize the async PS/2 lines ──
    reg s0=0;                       // PS2Clk
    reg s1=0;
    reg s2=0;
    reg d0=0;                       // PS2Data
    reg d1=0;
    always @(posedge clk) begin
        s0 <= ps2_clk_in;  s1 <= s0;  s2 <= s1;
        d0 <= ps2_data_in; d1 <= d0;
    end
    wire fall = s2 & ~s1;           // falling edge of PS2Clk (sample point)

    // ── frame assembly ──
    reg [10:0] shift = 11'b0;
    reg [3:0]  cnt   = 4'd0;
    reg        done  = 1'b0;
    reg [15:0] wd    = 16'd0;       // watchdog to resync between frames

    always @(posedge clk) begin
        valid <= 1'b0;
        if (rst) begin
            cnt <= 0; done <= 0; wd <= 0;
        end else begin
            // watchdog: a long idle gap (~0.65 ms) resynchronizes the bit count
            if (fall) wd <= 0;
            else begin
                wd <= wd + 1'b1;
                if (&wd) cnt <= 0;
            end

            if (fall) begin
                shift <= {d1, shift[10:1]};         // shift in (LSB arrives first)
                if (cnt == 4'd10) begin cnt <= 0; done <= 1'b1; end
                else            begin cnt <= cnt + 1'b1; done <= 1'b0; end
            end else if (done) begin
                done  <= 1'b0;
                data  <= shift[8:1];                // data[0..7] = shift[1..8]
                valid <= 1'b1;
            end
        end
    end
endmodule
`default_nettype wire
