//D LATCH WITH SYNCHRONOUS RESET
module d_latch(d,clk,rst,q);
  input d,clk,rst;
  output reg q;
  always @(clk,d)
  begin
    if(clk)
      	if(!rst)
        q<=0;
   	else
      	q<=d;
  end
endmodule
								// D LATCH WITH ASYNCHRONOUS RESET
module d_latch(d,clk,rst,q);
  input d,clk,rst;
  output reg q;
  always @(clk,d,rst)
  begin
    if(!rst)
      q<=0;
    else
      if(clk)
         q<=d;
  end
endmodule
								// TEST BENCH
module tb;
  reg clk,d,rst;
  wire q;
  d_latch dut(.d(d),.clk(clk),.rst(rst),.q(q));
  
  initial begin
    clk=0;
    rst=0;
    d=1;
    #2 rst=1;
    #4 d=0;
    #8 d=1;
    #10 d=0;
    #16 d=1;
    #27 d=0;
      #100 $finish;
  end
  always #5 clk=~clk;

  //generate waveform
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0,rst,q,d,clk);
  end
endmodule
