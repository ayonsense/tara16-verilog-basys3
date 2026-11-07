// vga_sync.v — 640x480 @ 60 Hz VGA timing (25 MHz pixel clock).
// (Reused from the proven VGA/vga_tara_mem design.)
//   H (800/line): Active 640 | FP 16 | Sync 96 | BP 48
//   V (525/frame): Active 480 | FP 10 | Sync 2  | BP 33
//   hsync/vsync active LOW; video_on HIGH only in the active region.
`default_nettype none
module vga_sync (
    input  wire        clk_25,
    input  wire        reset,
    output reg  [9:0]  h_count,
    output reg  [9:0]  v_count,
    output wire        hsync,
    output wire        vsync,
    output wire        video_on
);
    localparam H_ACTIVE=640, H_FP=16, H_SYNC=96, H_BP=48;
    localparam V_ACTIVE=480, V_FP=10, V_SYNC=2,  V_BP=33;
    localparam H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;  // 800
    localparam V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;  // 525
    localparam HS_START = H_ACTIVE + H_FP, HS_END = HS_START + H_SYNC;
    localparam VS_START = V_ACTIVE + V_FP, VS_END = VS_START + V_SYNC;

    always @(posedge clk_25) begin
        if (reset)                       h_count <= 0;
        else if (h_count == H_TOTAL-1)   h_count <= 0;
        else                             h_count <= h_count + 1;
    end
    always @(posedge clk_25) begin
        if (reset)                       v_count <= 0;
        else if (h_count == H_TOTAL-1) begin
            if (v_count == V_TOTAL-1)    v_count <= 0;
            else                         v_count <= v_count + 1;
        end
    end
    assign hsync    = ~((h_count >= HS_START) && (h_count < HS_END));
    assign vsync    = ~((v_count >= VS_START) && (v_count < VS_END));
    assign video_on = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
endmodule
`default_nettype wire
