`timescale 1ns / 10ps
module AccuTest ();
  reg clk,reset;
  reg [3:0] step;

  wire [3:0] Yo;

  Accumulator Accu(.step(step),.reset(reset),.clk(clk),.Yo(Yo));

  initial begin
    step = 4'b0001;
    clk = 0;
    reset = 0;
  end

  always begin
    #100 clk = ~clk;
  end

  always begin
    #2000 reset = ~reset;
  end

endmodule // AccuTest
