`timescale 1 ps / 1 ps

module pe
#(
    parameter   D_W_ACC  = 64, //accumulator data width
    parameter   D_W      = 32  //operand data width
)
(
    input   wire                  clk,
    input   wire                  rst,
    input   wire                  init,
    input   wire    [D_W-1:0]     in_a,
    input   wire    [D_W-1:0]     in_b,
    output  reg     [D_W_ACC-1:0] out_sum,
    output  reg     [D_W-1:0]     out_b,
    output  reg     [D_W-1:0]     out_a,
    output  reg                  valid_D
);
reg     [D_W_ACC-1:0] counter = 0;


// enter your RTL here
always @(posedge clk)
begin
    if (rst == 1)
    begin
      valid_D <= 0;
      out_sum <= 0;
      out_a <= 0;
      out_b <= 0;
    end
    else if (init == 1)
    begin
      valid_D <= 1;
      out_sum <= counter;
      counter <= in_a*in_b;
      out_a <= in_a;
      out_b <= in_b;
    end
    else 
    begin
      valid_D <= 0;
      counter <= counter + in_a*in_b;
      out_a <= in_a;
      out_b <= in_b;
    end
end

endmodule
