`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Dmitry Matyunin (https://github.com/mcjtag)
// 
// Create Date: 09.07.2024 11:30:57
// Design Name: adder
// Description: Adder Top Module
//  Set of Adders:
//   1) Ripple Carry Adder ("rca")
//   2) Hierarchical Carry Look-Ahead ("hcla")
//   3) Kogge-Stone Adder Radix-2 ("ksa")
//   4) Sklansky Adder Radix-2 ("skla")
//   5) Han-Carlson Adder Radix-2 ("hca")
//   6) Brent-Kung Adder Radix-2 ("bka")
//   7) Ladner-Fischer Adder Radix-2 ("lfa")
// License: MIT
//  Copyright (c) 2024 Dmitry Matyunin
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
// 
//////////////////////////////////////////////////////////////////////////////////

module adder #(
	parameter WIDTH = 32,
	parameter TYPE = "rca"
)
(
	input wire [WIDTH-1:0]a,	// input operand A
	input wire [WIDTH-1:0]b,	// input operand B
	output wire [WIDTH:0]p,		// output product: A+B
	input wire sgn,				// signed operation  : 0 - unsigned, 1 - signed
	input wire sub				// subtract operation: 0 - add, 1 - subtract
);

wire [WIDTH-1:0]sum;
wire ovf, cout;

assign ovf = (a[WIDTH-1] == b[WIDTH-1]^sub) && (a[WIDTH-1] != sum[WIDTH-1]);
assign p = (sgn) ? {ovf ? cout : sum[WIDTH-1], sum} : {cout^sub, sum};
	
generate case (TYPE)
	"rca": begin
		adder_rca #(
			.WIDTH(WIDTH)
		) adder_inst (
			.a(a),
			.b(sub ? ~b : b),
			.ci(sub),
			.po({cout, sum})
		);
	end
	"hcla": begin
		adder_hcla #(
		.WIDTH(WIDTH)
	) adder_inst (
		.a(a),
		.b(sub ? ~b : b),
		.ci(sub),
		.po({cout, sum})
	);
	end
	"ksa": begin
		adder_ksa_r2 #(
			.WIDTH(WIDTH)
		) adder_inst (
			.a(a),
			.b(sub ? ~b : b),
			.ci(sub),
			.po({cout, sum})
		);
	end
	"skla": begin
		adder_skla_r2 #(
			.WIDTH(WIDTH)
		) adder_inst (
			.a(a),
			.b(sub ? ~b : b),
			.ci(sub),
			.po({cout, sum})
		);
	end
	"hca": begin
		adder_hca_r2 #(
			.WIDTH(WIDTH)
		) adder_inst (
			.a(a),
			.b(sub ? ~b : b),
			.ci(sub),
			.po({cout, sum})
		);
	end
	"bka": begin
		adder_bka_r2 #(
			.WIDTH(WIDTH)
		) adder_inst (
			.a(a),
			.b(sub ? ~b : b),
			.ci(sub),
			.po({cout, sum})
		);
	end
	"lfa": begin
		adder_lfa_r2 #(
			.WIDTH(WIDTH)
		) adder_inst (
			.a(a),
			.b(sub ? ~b : b),
			.ci(sub),
			.po({cout, sum})
		);
	end
endcase endgenerate

endmodule
