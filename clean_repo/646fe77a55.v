//zf.v
//フラグ管理，あまり意味はない
module zf(rst_n, zfin, zfout);
	input wire rst_n;
	input wire zfin;
	output reg zfout;

always @(*) begin
	if(!rst_n)begin
		zfout <= 0;
	end else begin
		zfout <= zfin;
	end
end

endmodule
