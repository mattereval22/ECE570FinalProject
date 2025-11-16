module AC (
	input [7:0] data_in,
	input load, clk,
	output reg [7:0] data_out
);
 
 always @ (posedge clk)
	if (load) data_out <= data_in; 
endmodule