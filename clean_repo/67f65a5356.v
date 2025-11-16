// Master clock - Signed, 9662e103-129a

/*
To add in later revisions:
 - WDT clk
 - LSI clk
*/

module mc (
	input wire rst,
	input wire clk_en,
	output reg clk
);
	reg in_clk_en;

	initial begin
		clk = 0;
		in_clk_en = 0;
	end

	always @(negedge rst) begin
		in_clk_en <= 1'b1;
	end

	always #5 begin
		if (!rst && in_clk_en && clk_en) begin
			clk <= ~clk;
		end
		else begin
			clk <= 0;
		end
	end	
endmodule