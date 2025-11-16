// de.v
module de (
  input [3:0] morse_in,
  input [2:0] num,
  input clk,
  output [4:0] out
);

  alphaROM r (
    .out(out),
    .in_morse_bit(num),
    .morse_in(morse_in),
    .clk(clk)
  );

endmodule
