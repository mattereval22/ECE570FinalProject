`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    13:54:22 07/17/2024 
// Design Name: 
// Module Name:    sb 
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
module sbox(x0,x1,x2,x3,y0,y1,y2,y3);
	input x0,x1,x2,x3;
	output y0,y1,y2,y3;
	sb4 sb4i(x0,x1,x2,x3,t0,t1,t2,t3);
	sb3 sb3i(t0,t1,t2,t3,t4,t5,t6,t7);
	sb2 sb2i(t4,t5,t6,t7,t8,t9,t10,t11);
	sb1 sb1i(t8,t9,t10,t11,y0,y1,y2,y3);
endmodule
