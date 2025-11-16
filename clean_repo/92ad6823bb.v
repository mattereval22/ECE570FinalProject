
module MUX2_1 (a, b, sel, out);	 
	input a, b, sel;
	output out;
	wire w1, w2, w3;
	and and1(w1, b, sel);
	not not1(w3, sel);
	and and2(w2, a, w3);
	or or1(out, w1, w2);
endmodule
