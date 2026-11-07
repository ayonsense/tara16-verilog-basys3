// uart_rx.v — 8N1 UART receiver. Samples each data position at its centre.
//   DIV = clk_freq / baud   (100 MHz / 115200 = 868)
`default_nettype none
module uart_rx #(
    parameter integer DIV = 868
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,            // async serial in (idles high)
    output reg  [7:0] data,
    output reg        valid          // 1-cycle strobe when `data` is fresh
);
    reg rx0 = 1'b1;
    reg rx1 = 1'b1;
    always @(posedge clk) begin rx0 <= rx; rx1 <= rx0; end

    localparam IDLE=2'd0, START=2'd1, DATA=2'd2, STOP=2'd3;
    reg [1:0]  st   = IDLE;
    reg [15:0] cnt  = 16'd0;
    reg [2:0]  bidx = 3'd0;
    reg [7:0]  sh   = 8'd0;

    always @(posedge clk) begin
        valid <= 1'b0;
        if (rst) begin
            st <= IDLE; cnt <= 0; bidx <= 0;
        end else case (st)
            IDLE:  if (~rx1) begin st <= START; cnt <= 0; end       // start (line low)
            START: if (cnt == DIV/2) begin
                       cnt <= 0;
                       if (~rx1) begin st <= DATA; bidx <= 0; end    // still low at centre
                       else        st <= IDLE;                       // false start
                   end else cnt <= cnt + 1'b1;
            DATA:  if (cnt == DIV-1) begin
                       cnt <= 0; sh <= {rx1, sh[7:1]};               // LSB first
                       if (bidx == 3'd7) st <= STOP; else bidx <= bidx + 1'b1;
                   end else cnt <= cnt + 1'b1;
            STOP:  if (cnt == DIV-1) begin
                       st <= IDLE; data <= sh; valid <= 1'b1;
                   end else cnt <= cnt + 1'b1;
        endcase
    end
endmodule
`default_nettype wire
