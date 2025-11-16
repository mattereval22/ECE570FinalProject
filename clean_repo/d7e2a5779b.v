`timescale 1ns/1ps

module ProgramCounter(PC,clk,reset,PCplus4,ConBA,JT,DatabusA,ILLOP,XADR,ALUOut,PCSrc);
	output	[31:0]PC;
	input	clk;
	input	reset;
	input	[31:0]PCplus4;
	input	[31:0]ConBA;
	input	[25:0]JT;
	input	[31:0]DatabusA;
	input	[31:0]ILLOP;
	input	[31:0]XADR;
	input	ALUOut;
	input	[2:0]PCSrc;

	reg		[31:0]PC;
	wire	[31:0]addr1;
	assign	addr1 = (ALUOut == 0) ? PCplus4 : {PC[31],ConBA[30:0]};
	
	always@(posedge clk or negedge reset)
	begin
		if(~reset) PC <= 32'h80000000;
		else
		begin
			case (PCSrc[2:0])
				0 : PC <= PCplus4;
				1 : PC <= addr1;
				2 : PC <= {PC[31],3'b0,JT,2'b0};
				3 : PC <= DatabusA;
				4 : PC <= ILLOP;
				default : PC <= XADR;
			endcase
		end
	end
endmodule
		


