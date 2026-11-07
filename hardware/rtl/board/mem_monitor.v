// mem_monitor.v — UART command interface to the TARA memory (host debug).
//
// Protocol (115200 8N1), byte address A (16b, even), word count C (16b):
//   Ping : 'P'                        -> replies 0xA5
//   Read : 'R' AH AL CH CL            -> C words, each {hi,lo} big-endian
//   Write: 'W' AH AL CH CL <2C bytes> -> writes C words, replies 'K' (0x4B)
//
// Each transmitted byte uses a two-phase handshake: issue tx_send when the UART
// is idle, then WAIT for tx_busy to rise before moving on — otherwise the next
// byte would be queued a cycle too early (while busy is still 0) and dropped.
//
// Reads use an independent async port (live, even while the CPU runs). Writes go
// through the shared single write port (byte granular, two bytes per word) — for
// predictable results pause the CPU (single-step mode) before writing.
`default_nettype none
module mem_monitor (
    input  wire        clk,
    input  wire        rst,
    // UART
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    output reg         tx_send,
    output reg  [7:0]  tx_data,
    input  wire        tx_busy,
    // memory host read port (async)
    output wire [10:0] host_addr,
    input  wire [15:0] host_rword,
    // memory write port (byte granular; muxed with the ESP32 loader in top)
    output reg         mon_we,
    output reg  [10:0] mon_addr,
    output reg  [7:0]  mon_data,
    // soft CPU hold: 'H' holds the CPU in reset, 'G' releases it (run from PC=0)
    output reg         cpu_hold
);
    initial cpu_hold = 1'b0;
    localparam [3:0] IDLE=0, HDR=1,
                     RD_HI=2, RD_HW=3, RD_LO=4, RD_LW=5,
                     WR_HI=6, WR_LO=7, ACK=8, ACK_W=9;
    reg [3:0]  st   = IDLE;
    reg        wr   = 1'b0;          // current command is a write
    reg [1:0]  hi   = 2'd0;          // header byte index 0..3
    reg [15:0] addr = 16'd0;         // byte address
    reg [15:0] cnt  = 16'd0;         // words remaining

    assign host_addr = addr[10:0];

    always @(posedge clk) begin
        tx_send <= 1'b0;
        mon_we  <= 1'b0;
        if (rst) begin
            st <= IDLE; hi <= 0; cpu_hold <= 1'b0;
        end else case (st)
            IDLE: if (rx_valid) begin
                      hi <= 0;
                      if      (rx_data == "R") begin wr <= 1'b0; st <= HDR; end
                      else if (rx_data == "W") begin wr <= 1'b1; st <= HDR; end
                      else if (rx_data == "H") cpu_hold <= 1'b1;   // hold CPU in reset
                      else if (rx_data == "G") cpu_hold <= 1'b0;   // release -> run @PC=0
                      else if (rx_data == "P" && !tx_busy) begin
                          tx_data <= 8'hA5; tx_send <= 1'b1;        // ping reply
                      end
                  end

            HDR: if (rx_valid) begin
                      case (hi)
                          2'd0: addr[15:8] <= rx_data;
                          2'd1: addr[7:0]  <= rx_data;
                          2'd2: cnt[15:8]  <= rx_data;
                          2'd3: cnt[7:0]   <= rx_data;
                      endcase
                      if (hi == 2'd3) begin
                          if ({cnt[15:8], rx_data} == 16'd0) st <= IDLE;
                          else st <= wr ? WR_HI : RD_HI;
                      end else hi <= hi + 1'b1;
                  end

            // ── read: send hi byte, wait for accept, send lo byte, wait, next ──
            RD_HI: if (!tx_busy) begin
                       tx_data <= host_rword[15:8]; tx_send <= 1'b1; st <= RD_HW;
                   end
            RD_HW: if (tx_busy) st <= RD_LO;                  // byte accepted
            RD_LO: if (!tx_busy) begin
                       tx_data <= host_rword[7:0]; tx_send <= 1'b1; st <= RD_LW;
                   end
            RD_LW: if (tx_busy) begin
                       addr <= addr + 16'd2;
                       if (cnt == 16'd1) st <= IDLE;
                       else begin cnt <= cnt - 1'b1; st <= RD_HI; end
                   end

            // ── write: receive hi then lo byte, store both ──
            WR_HI: if (rx_valid) begin
                       mon_addr <= addr[10:0]; mon_data <= rx_data; mon_we <= 1'b1;
                       st <= WR_LO;
                   end
            WR_LO: if (rx_valid) begin
                       mon_addr <= addr[10:0] + 11'd1; mon_data <= rx_data; mon_we <= 1'b1;
                       addr <= addr + 16'd2;
                       if (cnt == 16'd1) st <= ACK;
                       else begin cnt <= cnt - 1'b1; st <= WR_HI; end
                   end

            ACK:   if (!tx_busy) begin tx_data <= "K"; tx_send <= 1'b1; st <= ACK_W; end
            ACK_W: if (tx_busy) st <= IDLE;
        endcase
    end
endmodule
`default_nettype wire
