// vga_scaler.v — scans out the TARA 64x64 framebuffer onto 640x480 VGA, with a
// bold-white text banner in the top border and black top/bottom borders.
//
//   Horizontal : 10 VGA px per TARA pixel -> 64*10 = 640 (fills width)
//   Vertical   :  7 VGA px per TARA pixel -> 64*7  = 448, centred in 16px borders
//   Packing    : byte = y*8 + x/8 ; bit = 7-(x&7) (MSB first) ; y=0 is BOTTOM row.
//
//   Top border (rows 0..15)  : banner text, white on black (8x16 bold-mono font,
//                              80 columns; message in msg.mem, centered).
//   Bottom border (rows 464..479) : black.
`default_nettype none
module vga_scaler #(
    parameter FONT_FILE   = "font8x16.mem", // 128 glyphs x 16 rows
    parameter MSG_FILE    = "msg.mem",      // 80 ASCII columns
    parameter SPLASH_FILE = "splash4.mem"   // 640x480 4bpp indexed-color splash
) (
    input  wire        clk_25,
    input  wire        reset,
    input  wire        splash_active,       // 1 = show the boot splash full-screen
    // framebuffer read interface (to memory.v VGA port)
    output wire [8:0]  fb_addr,             // local 0..511
    input  wire [7:0]  fb_byte,
    // VGA outputs
    output wire        Hsync,
    output wire        Vsync,
    output wire [3:0]  vgaRed,
    output wire [3:0]  vgaGreen,
    output wire [3:0]  vgaBlue
);
    wire [9:0] h_count, v_count;
    wire       video_on;

    vga_sync sync_u (
        .clk_25(clk_25), .reset(reset),
        .h_count(h_count), .v_count(v_count),
        .hsync(Hsync), .vsync(Vsync), .video_on(video_on)
    );

    // Layout (480 rows): [ TOP_BAND banner ][ V_IMG framebuffer ][ remainder black ]
    //   TOP_BAND = 20 : banner band; the 16-row font is centered with FONT_OFF
    //                   black rows above (and the rest below) -> ~black padding.
    //   V_IMG    = 448: 64 TARA rows * 7 px, follows the banner directly.
    //   bottom remainder (480-TOP_BAND-V_IMG = 12 rows) is black.
    // (To remove the bottom strip entirely, set TOP_BAND = 32.)
    localparam [9:0] TOP_BAND = 10'd20;
    localparam [9:0] V_IMG    = 10'd448;
    localparam [9:0] FONT_OFF = (TOP_BAND - 10'd16) / 2;   // center the 16-row font (=2)

    wire in_top    = (v_count < TOP_BAND);
    wire in_img_v  = (v_count >= TOP_BAND) && (v_count < TOP_BAND + V_IMG);
    wire in_bottom = (v_count >= TOP_BAND + V_IMG);

    // ── framebuffer scaling (image area) ──
    wire [9:0] tcol     = h_count / 10;
    wire [9:0] vy       = v_count - TOP_BAND;
    wire [9:0] trow_top = vy / 7;
    wire [5:0] tara_y   = 6'd63 - trow_top[5:0];     // y-flip
    assign fb_addr  = {tara_y, tcol[5:3]};
    wire   pixel_on = fb_byte[3'd7 - tcol[2:0]];

    // ── text banner ROMs ──
    (* rom_style = "distributed" *) reg [7:0] fontrom [0:2047];
    (* rom_style = "distributed" *) reg [7:0] msgrom  [0:79];
    initial begin
        $readmemh(FONT_FILE, fontrom);
        $readmemh(MSG_FILE,  msgrom);
    end

    // 16-row font cell placed at rows [FONT_OFF, FONT_OFF+15] of the band;
    // rows outside the cell are black, giving the +5/-5 padding around the text.
    wire [9:0] frow    = v_count - FONT_OFF;
    wire       in_text = (v_count >= FONT_OFF) && (v_count < FONT_OFF + 10'd16);
    wire [6:0] col     = h_count[9:3];               // character column 0..79
    wire [7:0] ascii   = msgrom[col];
    wire [7:0] fontrow = fontrom[{ascii[6:0], frow[3:0]}];
    wire       text_pix = in_text & fontrow[3'd7 - h_count[2:0]];

    // ── boot splash ROM (640x480 4bpp indexed colour, 320 bytes/row) ──
    // Each byte stores two pixels: high nibble = even x, low nibble = odd x.
    // The palette below expands the 4-bit index to the Basys3 native 12-bit VGA.
    wire [17:0] s_addr = video_on ? ((v_count * 18'd320) + {9'b0, h_count[9:1]})
                                  : 18'd0;
    wire [7:0]  s_byte;
    reg         s_low_nibble;

    // Use XPM for this >1 Mbit ROM so Vivado controls the Artix-7 BRAM
    // decomposition explicitly. The inferred narrow/deep mapping used by
    // Vivado 2026.1 creates an illegal RAMB36E1 cascade (REQP-1962).
    xpm_memory_sprom #(
        .ADDR_WIDTH_A(18),
        .CASCADE_HEIGHT(1),
        .MEMORY_INIT_FILE(SPLASH_FILE),
        .MEMORY_PRIMITIVE("block"),
        .MEMORY_SIZE(1_228_800),
        .READ_DATA_WIDTH_A(8),
        .READ_LATENCY_A(1),
        .USE_MEM_INIT(1)
    ) splash_rom_u (
        .douta(s_byte),
        .addra(s_addr),
        .clka(clk_25),
        .ena(1'b1),
        .regcea(1'b1),
        .rsta(1'b0),
        .sleep(1'b0),
        .injectsbiterra(1'b0),
        .injectdbiterra(1'b0),
        .sbiterra(),
        .dbiterra()
    );

    always @(posedge clk_25) begin
        s_low_nibble <= h_count[0];
    end
    wire [3:0] splash_idx = s_low_nibble ? s_byte[3:0] : s_byte[7:4];

    function [11:0] splash_rgb;
        input [3:0] idx;
        begin
            case (idx)
                4'h0: splash_rgb = 12'h000; // black
                4'h1: splash_rgb = 12'h800; // maroon
                4'h2: splash_rgb = 12'hF00; // red
                4'h3: splash_rgb = 12'hF80; // orange
                4'h4: splash_rgb = 12'hFC0; // gold
                4'h5: splash_rgb = 12'hFF4; // yellow
                4'h6: splash_rgb = 12'h080; // green
                4'h7: splash_rgb = 12'h0A8; // teal
                4'h8: splash_rgb = 12'h0CF; // cyan
                4'h9: splash_rgb = 12'h06F; // blue
                4'hA: splash_rgb = 12'h46F; // indigo
                4'hB: splash_rgb = 12'h80C; // violet
                4'hC: splash_rgb = 12'h777; // gray
                4'hD: splash_rgb = 12'hBBB; // light gray
                4'hE: splash_rgb = 12'hFFF; // white
                default: splash_rgb = 12'hA00; // IITM deep red
            endcase
        end
    endfunction

    // ── colour ──
    reg [3:0] r, g, b;
    always @(*) begin
        if (!video_on)          {r,g,b} = 12'h000;          // blanking
        else if (splash_active) {r,g,b} = splash_rgb(splash_idx);          // splash
        else if (in_top)        {r,g,b} = text_pix ? 12'hFFF : 12'h000;    // banner
        else if (in_bottom)     {r,g,b} = 12'h000;          // black bottom border
        else if (pixel_on)      {r,g,b} = 12'hFA0;          // amber lit pixel
        else                    {r,g,b} = 12'h000;          // unlit
    end
    assign vgaRed   = r;
    assign vgaGreen = g;
    assign vgaBlue  = b;
endmodule
`default_nettype wire
