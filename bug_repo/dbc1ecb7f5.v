`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/10/2020 05:51:09 PM
// Design Name: 
// Module Name: IF
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module IF(
    input clk, reset,
    input PCSrc, PC_write,
    input [31:0] PC_Branch,
    output [31:0] PC_IF, INSTRUCTION_IF
    );
    
    wire [31:0] out_mux, out_pc, out_adder;
    
    mux2_1 mux(out_adder, PC_Branch, PCSrc, out_mux);
    PC pc(clk, reset, PC_write, out_mux, out_pc);
    instruction_memory mem(out_pc, INSTRUCTION_IF);
    adder add(out_pc, 4, out_adder);
    
    assign PC_IF = out_pc;
    
endmodule
