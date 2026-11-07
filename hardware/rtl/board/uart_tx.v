// uart_tx.v — 8N1 UART transmitter. Pulse `send` while !busy to queue a byte.
//   DIV = clk_freq / baud   (100 MHz / 115200 = 868)
`default_nettype none
module uart_tx #(
    parameter integer DIV = 868
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       send,
    input  wire [7:0] data,
    output reg        tx,              // idles high
    output reg        busy
);
    initial begin tx = 1'b1; busy = 1'b0; end
    localparam IDLE=2'd0, START=2'd1, DATA=2'd2, STOP=2'd3;
    reg [1:0]  st   = IDLE;
    reg [15:0] cnt  = 16'd0;
    reg [2:0]  bidx = 3'd0;
    reg [7:0]  sh   = 8'd0;

    always @(posedge clk) begin
        if (rst) begin
            st <= IDLE; tx <= 1'b1; busy <= 1'b0; cnt <= 0;
        end else case (st)
            IDLE:  begin
                       tx <= 1'b1;
                       if (send) begin sh <= data; busy <= 1'b1; st <= START; cnt <= 0; end
                       else            busy <= 1'b0;
                   end
            START: begin
                       tx <= 1'b0;                                   // start bit
                       if (cnt == DIV-1) begin cnt <= 0; st <= DATA; bidx <= 0; end
                       else cnt <= cnt + 1'b1;
                   end
            DATA:  begin
                       tx <= sh[0];                                  // LSB first
                       if (cnt == DIV-1) begin
                           cnt <= 0; sh <= {1'b0, sh[7:1]};
                           if (bidx == 3'd7) st <= STOP; else bidx <= bidx + 1'b1;
                       end else cnt <= cnt + 1'b1;
                   end
            STOP:  begin
                       tx <= 1'b1;                                   // stop bit
                       if (cnt == DIV-1) begin cnt <= 0; st <= IDLE; busy <= 1'b0; end
                       else cnt <= cnt + 1'b1;
                   end
        endcase
    end
endmodule
`default_nettype wire
