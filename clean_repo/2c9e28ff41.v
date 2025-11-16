module tb_bidir_tsb();
	// Test ports
	reg A, C;
	wire wA, wC;
	reg [1:0] cfg;
	wire B, D;

	assign wA = A;
	assign wC = C;

	bidir_tsb t1(cfg, wA, B);
	bidir_tsb t2(cfg, D, wC);
	initial begin
		#10 A = 1'b0; cfg = 2'b00;
		$monitor("A = %b, cfg = %b, B = %b",
				A, cfg, B);
		#10 A = 1'b0; cfg = 2'b00;
		#10 A = 1'b1; cfg = 2'b00;
		#10 A = 1'b0; cfg = 2'b10;
		#10 A = 1'b1; cfg = 2'b10;
		#10 A = 1'b0; cfg = 2'b01;
		#10 A = 1'b1; cfg = 2'b01;
		#10 C = 1'b0; cfg = 1'b0;
		$monitor("C = %b, cfg = %b, D = %b",
				C, cfg, D);
		#10 C = 1'b0; cfg = 2'b00;
		#10 C = 1'b1; cfg = 2'b00;
		#10 C = 1'b0; cfg = 2'b10;
		#10 C = 1'b1; cfg = 2'b10;
		#10 C = 1'b0; cfg = 2'b01;
		#10 C = 1'b1; cfg = 2'b01;
	end
endmodule

