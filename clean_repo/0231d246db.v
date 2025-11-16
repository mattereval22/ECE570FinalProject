`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    15:59:33 07/17/2024 
// Design Name: 
// Module Name:    m4 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module m2(b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,b10,b11,b12,b13,b14,b15,c0,c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11,c12,c13,c14,c15);
	input b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,b10,b11,b12,b13,b14,b15;
	output c0,c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11,c12,c13,c14,c15;
	assign c0= b13 ^ b8;
	assign c1= b14 ^ b9;
	assign c2= b10 ^ b12 ^ b15;
	assign c3= b11 ^ b12;
	assign c4= b0;
	assign c5= b1;
	assign c6= b2;
	assign c7= b3;
	assign c8= b3 ^ b4;
	assign c9= b0 ^ b5;
	assign c10= b1 ^ b6;
	assign c11= b2 ^ b3 ^ b7;
	assign c12= b8;
	assign c13= b9;
	assign c14= b10;
	assign c15= b11;
endmodule
