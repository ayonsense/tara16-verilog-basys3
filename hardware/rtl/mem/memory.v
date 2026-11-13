// memory.v — TARA unified 2 KB memory, organised as 1024 x 16-bit words.
//
// Byte-addressable, big-endian (even byte = high lane, odd byte = low lane),
// exactly the semantics of the golden simulator for word-aligned word accesses
// (verified by model/verify.py). One SYNCHRONOUS write port — byte stores use a
// read-modify-write of the whole word so writes are full-width and the array
// maps to distributed RAM (NOT a 2-write-port memory, which previously blew up
// to ~68k LUTs). Reads are ASYNCHRONOUS, preserving the CPU's multi-cycle timing.
//
//   CPU port : word or zero-extended byte read; word or byte write
//   VGA port : async byte read at 0x600 + vga_addr (framebuffer)
//   Loader   : byte write (ESP32/GPIO, future), priority over CPU writes
//
// INIT_FILE is $readmemh'd as one 16-bit WORD per line (see prog/gen_prog.py).
`default_nettype none
module memory #(
    parameter INIT_FILE = "",
    parameter [10:0] FB_BASE = 11'h600
) (
    input  wire        clk,
    // CPU port
    input  wire [10:0] cpu_addr,
    input  wire        cpu_byte,         // 1 = byte access, 0 = word
    input  wire        cpu_we,
    input  wire [15:0] cpu_wdata,
    output wire [15:0] cpu_rdata,        // byte access is zero-extended
    // memory-mapped game inputs: a byte read of 0x5FF returns these live bits
    //   {3'b0, QUIT, RIGHT, LEFT, DOWN, UP}  (one-hot, active high)
    input  wire [7:0]  key_bits,
    // VGA framebuffer read port (local 0..511 -> CPU 0x600..0x7FF)
    input  wire [8:0]  vga_addr,
    output wire [7:0]  vga_rbyte,
    // host monitor read port (async word read; byte address)
    input  wire [10:0] host_addr,
    output wire [15:0] host_rword,
    // boot loader / monitor write port — byte granular
    input  wire        ld_we,
    input  wire [10:0] ld_addr,
    input  wire [7:0]  ld_data
);
    (* ram_style = "distributed" *)
    reg [15:0] wmem [0:1023];

    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) wmem[i] = 16'h0000;
        if (INIT_FILE != "") $readmemh(INIT_FILE, wmem);
    end

    // address decode: index = addr>>1, lane = addr[0] (0 = high byte)
    wire [9:0] cpu_wi   = cpu_addr[10:1];
    wire       cpu_lane = cpu_addr[0];

    wire [10:0] fb_addr = FB_BASE + {2'b0, vga_addr};
    wire [9:0]  vga_wi   = fb_addr[10:1];
    wire        vga_lane = fb_addr[0];

    // ── single synchronous write port (loader priority); full-width writes ──
    wire        wr_en   = ld_we | cpu_we;
    wire [9:0]  wr_wi   = ld_we ? ld_addr[10:1] : cpu_wi;
    wire        wr_lane = ld_we ? ld_addr[0]    : cpu_lane;
    wire        wr_byte = ld_we ? 1'b1          : cpu_byte;
    wire [7:0]  wr_bd   = ld_we ? ld_data       : cpu_wdata[7:0];
    wire [15:0] wr_cur  = wmem[wr_wi];           // current word (for RMW byte store)

    always @(posedge clk) begin
        if (wr_en) begin
            if (wr_byte)
                wmem[wr_wi] <= wr_lane ? {wr_cur[15:8], wr_bd}      // low byte
                                       : {wr_bd, wr_cur[7:0]};      // high byte
            else
                wmem[wr_wi] <= cpu_wdata;                           // full word
        end
    end

    // ── asynchronous reads ──
    wire [15:0] cpu_word = wmem[cpu_wi];
    wire        is_key   = cpu_byte && (cpu_addr == 11'h5FF);  // input port
    assign cpu_rdata = is_key   ? {8'b0, key_bits}
                     : cpu_byte ? (cpu_lane ? {8'b0, cpu_word[7:0]}
                                            : {8'b0, cpu_word[15:8]})
                                : cpu_word;

    wire [15:0] vga_word = wmem[vga_wi];
    assign vga_rbyte = vga_lane ? vga_word[7:0] : vga_word[15:8];

    // host monitor: async word read (byte address -> word index)
    // Expose the live keyboard byte to the host monitor as well as to the CPU.
    // This makes address 0x5FF useful for diagnosing buttons, the Basys 3
    // USB-HID keyboard, and Studio-forwarded keys without changing CPU state.
    wire host_reads_keys = (host_addr[10:1] == 10'h2FF);
    assign host_rword = host_reads_keys
                      ? {8'b0, key_bits}
                      : wmem[host_addr[10:1]];
endmodule
`default_nettype wire
