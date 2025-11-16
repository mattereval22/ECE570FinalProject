`timescale 1ns / 1ps

module jk(clk,j,k,q,qb );
input clk,j,k;
output q,qb;
reg q,qb;
always@(posedge clk)
begin
case({j,k})
  2'b00:q=q;
  2'b01:q=0;
  2'b10:q=1;
  2'b11:q=~q;
endcase
qb=~q;
end  

endmodule
