// tb_ps2_keyboard.v — PS/2 Set-2 make/break frames become held game keys.
`timescale 1ns/1ps
module tb_ps2_keyboard;
    reg clk = 0, rst = 1;
    reg ps2_clk = 1, ps2_data = 1;
    wire [7:0] sc;
    wire sc_valid;
    wire [4:0] keys;
    wire reset_req;
    integer errors = 0;

    ps2_rx rx (
        .clk(clk), .rst(rst), .ps2_clk_in(ps2_clk),
        .ps2_data_in(ps2_data), .data(sc), .valid(sc_valid)
    );
    ps2_keyboard decode (
        .clk(clk), .rst(rst), .sc(sc), .sc_valid(sc_valid),
        .keys(keys), .reset_req(reset_req)
    );
    always #5 clk = ~clk;

    task send_bit(input bit value);
        begin
            ps2_data = value; #200;
            ps2_clk = 0; #200;
            ps2_clk = 1; #200;
        end
    endtask

    task send_byte(input [7:0] value);
        integer i;
        reg parity;
        begin
            parity = ~^value; // odd parity bit
            send_bit(0);
            for (i = 0; i < 8; i = i + 1) send_bit(value[i]);
            send_bit(parity);
            send_bit(1);
            ps2_data = 1;
            #1000;
        end
    endtask

    task check(input condition, input [127:0] label_text);
        begin
            if (!condition) begin
                $display("%0s FAIL keys=%b reset=%b sc=%h", label_text, keys, reset_req, sc);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        #100; rst = 0; #1000;

        send_byte(8'h1D);                    // W make
        check(keys == 5'b00001, "W make");
        send_byte(8'hF0); send_byte(8'h1D);  // W break
        check(keys == 5'b00000, "W break");

        send_byte(8'hE0); send_byte(8'h6B);  // Left arrow make
        check(keys == 5'b00100, "Left make");
        send_byte(8'hE0); send_byte(8'hF0); send_byte(8'h6B);
        check(keys == 5'b00000, "Left break");

        send_byte(8'h15);                    // Q make/release
        check(reset_req == 1'b1, "Q make");
        send_byte(8'hF0); send_byte(8'h15);
        check(reset_req == 1'b0, "Q break");

        if (errors == 0) begin
            $display("tb_ps2_keyboard: PASS");
            $finish;
        end
        $fatal(1, "tb_ps2_keyboard: FAIL (%0d errors)", errors);
    end
endmodule
