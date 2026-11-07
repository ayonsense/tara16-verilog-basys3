// clock_step.v — CPU clock & reset controller for teaching/debug on Basys3.
//
//   run = 1 : CPU runs on a divided "auto" clock (a counter bit tap):
//             auto_clk frequency = 100 MHz / 2^(BIT+1)
//               SLOW_BIT = 14 -> ~3.05 kHz   (≈ 100e6 / 2^15)
//               SLOW_BIT = 24 -> ~2.98 Hz
//               FAST_BIT =  4 -> ~3.05 MHz
//             pick SLOW_BIT / FAST_BIT to taste.
//   run = 0 : single-step — each press of step_btn gives exactly one CPU clock
//             rising edge (the debounced button level IS the clock).
//
// All sources are synchronous to clk100, so the cpu_clk mux is glitch-safe for
// the human-operated switches used here. Route cpu_clk on a global buffer (BUFG).
`default_nettype none
module clock_step #(
    parameter SLOW_BIT = 12,     // slow auto-clock = 100 MHz / 2^(SLOW_BIT+1)
    parameter FAST_BIT = 10,     // fast auto-clock = 100 MHz / 2^(FAST_BIT+1)
    parameter RESET_HOLD_CYCLES = 1_000_000  // hold reset ~10 ms @ 100 MHz
) (
    input  wire clk100,
    input  wire reset_btn,       // active-high (Basys3 btnC)
    input  wire run,             // sw: 1 = auto run, 0 = single step
    input  wire speed_fast,      // sw: 1 = fast auto, 0 = slow auto
    input  wire step_btn,        // momentary: advance one CPU clock
    output wire cpu_clk,
    output reg  rst,
    output wire auto_clk         // exposed for a debug LED
);
    // free-running divider
    reg [31:0] cnt = 32'b0;
    assign auto_clk = speed_fast ? cnt[FAST_BIT] : cnt[SLOW_BIT];

    // Synchronize and stretch reset.  btnC should restart the whole CPU, not
    // just the VGA splash; holding rst for several slow-clock periods keeps the
    // PC at 0x000 until the microsequencer and derived clock are in a known
    // phase again.
    reg [1:0] rst_sync = 2'b0;
    reg [31:0] rst_hold = RESET_HOLD_CYCLES;
    always @(posedge clk100) begin
        rst_sync <= {rst_sync[0], reset_btn};
        if (rst_sync[1]) begin
            rst_hold <= RESET_HOLD_CYCLES;
            rst      <= 1'b1;
            cnt      <= 32'b0;
        end else if (rst_hold != 32'b0) begin
            rst_hold <= rst_hold - 32'd1;
            rst      <= 1'b1;
            cnt      <= 32'b0;
        end else begin
            rst      <= 1'b0;
            cnt      <= cnt + 32'd1;
        end
    end

    // debounce step button -> clean level (= the single-step clock)
    reg [19:0] db_cnt = 20'b0;
    reg        btn_sync = 1'b0;
    reg        step_clean = 1'b0;
    always @(posedge clk100) begin
        btn_sync <= step_btn;
        if (btn_sync == step_clean) db_cnt <= 20'b0;
        else begin
            db_cnt <= db_cnt + 20'd1;
            if (&db_cnt) step_clean <= btn_sync;     // stable ~10 ms -> accept
        end
    end

    assign cpu_clk = run ? auto_clk : step_clean;
endmodule
`default_nettype wire
