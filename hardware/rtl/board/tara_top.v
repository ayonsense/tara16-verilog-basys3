// tara_top.v — Basys3 top level: TARA CPU + VGA framebuffer scaler + teaching
// clock/step control + 7-seg/LED debug + serial boot-loader hook.
//
// Switches / buttons:
//   sw[0]    run(1) / single-step(0)       btnC : reset
//   sw[1]    full-speed(1) / 5kHz slow(0)  btnU : single-step / game UP
//   sw[2]    loader enable (ESP32)         btnD : game DOWN
//   sw[4]    game QUIT key                 btnL : game LEFT
//   sw[15:14] 7-seg src: 0 PC 1 IR 2 reg 3 sw   btnR : game RIGHT
//   sw[13:11] register select (R0..R7)
//   JA[2:0]  ESP32 serial loader: {active, sclk, sdata}
//
// Keyboard: WASD/arrows drive movement; Q resets/restarts like btnC.
// Game inputs are memory-mapped one-hot at 0x5FF: {QUIT,RIGHT,LEFT,DOWN,UP}.
// VGA: 0x600-0x7FF framebuffer scaled to 640x480 (amber), with a bold-white
// banner in the top border, black top/bottom borders, and a 4bpp colour splash.
`default_nettype none
module tara_top #(
    parameter MEM_FILE    = "microcode.mem",
    parameter PROG_FILE   = "boot.hex",
    parameter FONT_FILE   = "font8x16.mem",
    parameter MSG_FILE    = "msg.mem",
    parameter SPLASH_FILE = "splash4.mem",
    parameter SPLASH_EN   = 1,            // boot splash on (1) / off (0)
    parameter SPLASH_CYCLES = 200_000_000 // ~2 s @ 100 MHz
) (
    input  wire        clk,                 // 100 MHz (W5)
    input  wire [15:0] sw,
    input  wire        btnC, btnU, btnD, btnL, btnR,
    input  wire        PS2Clk, PS2Data,     // USB-HID keyboard (PS/2) C17/B17
    input  wire        RsRx,                // USB-UART host -> FPGA (B18)
    output wire        RsTx,                // USB-UART FPGA -> host (A18)
    input  wire [2:0]  JA,                  // serial loader inputs
    output wire [15:0] led,
    output wire [6:0]  seg,
    output wire [3:0]  an,
    output wire        Hsync,
    output wire        Vsync,
    output wire [3:0]  vgaRed,
    output wire [3:0]  vgaGreen,
    output wire [3:0]  vgaBlue
);
    // ── 25 MHz pixel clock (100/4) ──
    reg [1:0] pdiv = 2'b0;
    always @(posedge clk) pdiv <= pdiv + 1'b1;
    wire clk_25 = pdiv[1];

    // ── CPU clock & reset (auto clock = counter bit tap; see clock_step.v) ──
    wire cpu_clk, rst_core, auto_clk;
    wire kbd_reset_req;
    clock_step clkstep_u (
        .clk100(clk), .reset_btn(btnC | kbd_reset_req),
        .run(sw[0]), .speed_fast(sw[1]), .step_btn(btnU),
        .cpu_clk(cpu_clk), .rst(rst_core), .auto_clk(auto_clk)
    );

    // ── game inputs: buttons + PS/2 keyboard -> one-hot bits at 0x5FF ──
    //   bit0=UP bit1=DOWN bit2=LEFT bit3=RIGHT bit4=QUIT
    // Buttons: btnU/D/L/R + sw[4]=QUIT (synchronized).
    reg [4:0] key_s0 = 5'b0;
    reg [4:0] key_s1 = 5'b0;
    always @(posedge clk) begin
        key_s0 <= {sw[4], btnR, btnL, btnD, btnU};
        key_s1 <= key_s0;
    end
    // PS/2 keyboard: arrows or WASD for movement; Q resets like btnC.
    wire [7:0] ps2_sc;
    wire       ps2_valid;
    wire [4:0] kbd_keys;
    ps2_rx ps2rx_u (
        .clk(clk), .rst(rst_core),
        .ps2_clk_in(PS2Clk), .ps2_data_in(PS2Data),
        .data(ps2_sc), .valid(ps2_valid)
    );
    ps2_keyboard kbd_u (
        .clk(clk), .rst(rst_core),
        .sc(ps2_sc), .sc_valid(ps2_valid),
        .keys(kbd_keys), .reset_req(kbd_reset_req)
    );
    // buttons OR keyboard -> the value returned by a read of 0x5FF
    wire [4:0] host_keys;
    wire [7:0] key_bits = {3'b000, key_s1 | kbd_keys | host_keys};

    // ── serial boot loader (idle unless ESP32 drives JA) ──
    wire        esp_we, loading;
    wire [10:0] esp_addr;
    wire [7:0]  esp_data;
    // Loader is OPT-IN via sw[2]: with sw[2]=0 the loader can never assert
    // (a floating JA pin cannot freeze the CPU). Set sw[2]=1 only when an ESP32
    // is actually driving the JA pins.
    prog_loader loader_u (
        .clk(clk), .active(sw[2] & JA[2]), .sclk(JA[1]), .sdata(JA[0]),
        .ld_we(esp_we), .ld_addr(esp_addr), .ld_data(esp_data), .loading(loading)
    );
    // ── UART memory monitor (host debug over the USB-UART / RsRx,RsTx) ──
    wire [7:0]  urx_data;  wire urx_valid;
    wire [7:0]  utx_data;  wire utx_send, utx_busy;
    wire        mon_we;    wire [10:0] mon_addr;  wire [7:0] mon_data;
    wire [10:0] host_addr; wire [15:0] host_rword;
    wire        cpu_hold;
    uart_rx urx_u (.clk(clk), .rst(rst_core), .rx(RsRx),
                   .data(urx_data), .valid(urx_valid));
    uart_tx utx_u (.clk(clk), .rst(rst_core), .send(utx_send), .data(utx_data),
                   .tx(RsTx), .busy(utx_busy));
    mem_monitor mon_u (
        .clk(clk), .rst(rst_core),
        .rx_data(urx_data), .rx_valid(urx_valid),
        .tx_send(utx_send), .tx_data(utx_data), .tx_busy(utx_busy),
        .host_addr(host_addr), .host_rword(host_rword),
        .mon_we(mon_we), .mon_addr(mon_addr), .mon_data(mon_data),
        .cpu_hold(cpu_hold), .host_keys(host_keys)
    );
    // memory write port: monitor has priority over the ESP32 loader
    wire        ld_we   = mon_we ? 1'b1     : esp_we;
    wire [10:0] ld_addr = mon_we ? mon_addr : esp_addr;
    wire [7:0]  ld_data = mon_we ? mon_data : esp_data;

    // ── boot splash: full-screen for ~2 s after reset (btnC) or power-on ──
    reg [31:0] splash_cnt = 32'd0;
    always @(posedge clk or posedge rst_core) begin
        if (rst_core)                         splash_cnt <= 32'd0;
        else if (splash_cnt < SPLASH_CYCLES)  splash_cnt <= splash_cnt + 32'd1;
    end
    wire splash_active = (SPLASH_EN != 0) && (splash_cnt < SPLASH_CYCLES);

    // Keep the CPU parked at PC=0 while the splash is visible. Otherwise a fast
    // program can restart and halt behind the splash before the display returns.
    wire cpu_rst = rst_core | splash_active | loading | cpu_hold;

    // ── framebuffer read wires (scaler <-> CPU memory) ──
    wire [8:0] fb_addr;
    wire [7:0] fb_byte;

    // ── CPU ──
    wire [15:0] dbg_pc, dbg_ir, r0,r1,r2,r3,r4,r5,r6,r7;
    wire [2:0]  dbg_tstate;
    wire        dbg_halted;
    wire [3:0]  dbg_flags;

    tara_cpu #(.MEM_FILE(MEM_FILE), .PROG_FILE(PROG_FILE), .ADDER_STYLE(1)) cpu_u (
        .clk(cpu_clk), .clk_mem(clk), .rst(cpu_rst),
        .ld_we(ld_we), .ld_addr(ld_addr), .ld_data(ld_data),
        .key_bits(key_bits),
        .host_addr(host_addr), .host_rword(host_rword),
        .vga_addr(fb_addr), .vga_rbyte(fb_byte),
        .dbg_pc(dbg_pc), .dbg_ir(dbg_ir), .dbg_tstate(dbg_tstate),
        .dbg_halted(dbg_halted), .dbg_flags(dbg_flags),
        .dbg_r0(r0), .dbg_r1(r1), .dbg_r2(r2), .dbg_r3(r3),
        .dbg_r4(r4), .dbg_r5(r5), .dbg_r6(r6), .dbg_r7(r7)
    );

    // ── VGA scaler (own 25 MHz domain; async framebuffer read) + banner ──
    vga_scaler #(.FONT_FILE(FONT_FILE), .MSG_FILE(MSG_FILE),
                 .SPLASH_FILE(SPLASH_FILE)) scaler_u (
        .clk_25(clk_25), .reset(1'b0),
        .splash_active(splash_active),
        .fb_addr(fb_addr), .fb_byte(fb_byte),
        .Hsync(Hsync), .Vsync(Vsync),
        .vgaRed(vgaRed), .vgaGreen(vgaGreen), .vgaBlue(vgaBlue)
    );

    // ── 7-seg debug: source selected by sw[15:14] ──
    //   00 = PC
    //   01 = IR
    //   10 = register chosen by sw[13:11]  (R0..R7)
    //   11 = raw switch value {sw}  -> flip the switches and read them in hex
    reg [15:0] regsel;
    always @(*) case (sw[13:11])
        3'd0: regsel = r0;  3'd1: regsel = r1;
        3'd2: regsel = r2;  3'd3: regsel = r3;
        3'd4: regsel = r4;  3'd5: regsel = r5;
        3'd6: regsel = r6;  default: regsel = r7;
    endcase
    reg [15:0] seg_val;
    always @(*) case (sw[15:14])
        2'd0: seg_val = dbg_pc;
        2'd1: seg_val = dbg_ir;
        2'd2: seg_val = regsel;
        default: seg_val = sw;          // raw switch value
    endcase
    seg7 seg_u (.clk(clk), .value(seg_val), .seg(seg), .an(an));

    // ── LEDs (exactly 16 bits): ──
    //  led[15]=halted  led[14]=loading  led[13:10]={Z,N,C,V}
    //  led[9:8]=00     led[7:5]=Tstate  led[4:0]=R0[4:0]
    assign led = {dbg_halted, loading, dbg_flags, 2'b00, dbg_tstate, r0[4:0]};
endmodule
`default_nettype wire
