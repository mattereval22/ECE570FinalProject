`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    11:34:20 11/01/2024 
// Design Name: 
// Module Name:    DM 
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

module DM(
	 input [31:0] PC,
    input clk,
    input WE,
    input [31:0] A,
    input [31:0] Din,
    input reset,
    output [31:0] Dout
    );
reg [31:0] Mem [3071:0];
wire [12:0] Ad;
integer i;

initial begin
	for(i = 0; i < 3072; i = i + 1)begin
		Mem[i] = 32'b0;
	end
end

assign Ad = A[14:2];
assign Dout = Mem[Ad];

always @(posedge clk)begin
	if(reset)begin
		for(i = 0; i < 3072; i = i + 1)begin
			Mem[i] = 32'b0;
		end		
	end
	else if(WE) begin
		Mem[Ad] = Din;
		$display("%d@%h: *%h <= %h", $time, PC, A, Din);
	end
end

endmodule
