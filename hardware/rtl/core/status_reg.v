// status_reg.v — observational Z/N/C/V flags latched from the ALU when
// status_we is asserted. NOTE: TARA is flag-free; branches use a direct
// register comparator, not these flags. This register exists for debug/LED
// display and the course narrative about condition codes.
`default_nettype none
module status_reg (
    input  wire clk,
    input  wire rst,
    input  wire we,
    input  wire z_in,
    input  wire n_in,
    input  wire c_in,
    input  wire v_in,
    output reg  z,
    output reg  n,
    output reg  c,
    output reg  v
);
    always @(posedge clk or posedge rst) begin     // async reset
        if (rst)      {z, n, c, v} <= 4'b0;
        else if (we)  {z, n, c, v} <= {z_in, n_in, c_in, v_in};
    end
endmodule
`default_nettype wire
