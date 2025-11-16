
module R(SET,OUT_R,reset,clock,rst);
	input SET,reset,clock,rst;
	output reg OUT_R;

	always @(negedge clock,posedge rst)begin
	  if(rst)begin
		OUT_R = 1'b0;
	  end else
	  if(reset)  begin
		OUT_R = 1'b0;
	  end
	  else if(SET)begin
		OUT_R = 1'b1;	
	  end
	end
endmodule
