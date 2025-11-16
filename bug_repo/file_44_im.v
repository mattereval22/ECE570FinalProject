`include    ".\\head_mips.v"

module im_8k( addr, dout ) ;
  input  [21:2] addr ;  //adress bus
  output [31:0] dout ;  //32-bit memory output
  
  reg [31:0] im [`STO_IM-1:0] ;
  
  assign dout = im [(addr-`PC_INITIAL)>>2] ;
  
  
  initial
    $readmemh ( "code.txt", im ) ;
    
endmodule