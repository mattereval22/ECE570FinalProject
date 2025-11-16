module alu(
		input		[3:0]	ctl,
		input		[31:0]	a, b,
		output reg	[31:0]	out,
		output				zero );

	wire [31:0] sub_ab;
	wire [31:0] add_ab;

	always @(*) begin
		case (ctl)
			4'b0000:  out = a & b;				/* and */
			4'b0001:  out = a | b;				/* or */
			4'b0010:  out = a + b;				/* add */
			4'b0110:  out = a - b;				/* sub */
	        4'b0111:  out = (a < b) ? 32'b00000000000000000000000000000001 : 32'b0; //slt
			default: out = 0;
		endcase
	end
	assign zero = (0 == out)? 1 : out;
endmodule


module alu_control(ALUOp,funct,ALUCon);
	input [1:0] ALUOp;
	input [5:0] funct;
	output [3:0] ALUCon;

	reg [3:0] ALUCon;

	always @(*) begin
		case(ALUOp)
			2'b00: ALUCon <= 4'b0010;    // lw, sw
			2'b01: ALUCon <= 4'b0110;    // beq
            2'b10 :
              begin
                case (funct)
                  6'b100000: ALUCon <= 4'b0010;
                  6'b100010: ALUCon <= 4'b0110;
                  6'b100101: ALUCon <= 4'b0001;
                  6'b100100: ALUCon <= 4'b0000;
                  6'b101010: ALUCon <= 4'b0111;
                  default: 	 ALUCon <= 4'b0000;
                endcase
              end
			default: ALUCon <= 4'b0000;
		endcase
	end

endmodule

module control_unit (
	input[5:0] 	op,
  	output reg [1:0] regdst,
  	output reg regwrite,
	output 	reg branch,
	output	reg jump,
	output	reg memread,
  	output reg [1:0]memtoreg,
  	output reg memwrite,
	output	reg [1:0] aluop,
	output	reg aluscr );

	always @(*) begin
		// default
		// R-type
		branch 		<= 1'b0;
		jump 		<= 1'b0;
		memread 	<= 1'b0;
      	memtoreg[1:0]	<= 2'b00;
		memwrite	<= 1'b0;
		aluop[1:0]	<= 2'b10;
		aluscr		<= 1'b0;
      	regdst[1:0] <= 2'b01;
		regwrite	<= 1'b1;

		case(op)
			6'b10_0011: begin // lw
				regdst[1:0]	<= 2'b00;
				memread		<= 1'b1;
              	aluop[1:0]	<= 2'b00;
				aluscr		<= 1'b1;
              memtoreg[1:0]	<= 2'b01;
			end
			6'b10_1011: begin // sw
              	aluop[1]	<= 1'b0;
				aluscr		<= 1'b1;
				memwrite 	<= 1'b1;
				regwrite	<= 1'b0;
			end
			6'b00_0100: begin // beq
				branch		<= 1'b1;
				aluop[1:0]	<= 2'b01;
				regwrite	<= 1'b0;
			end
			6'b00_1000: begin // addi
              	regdst[1:0] <= 2'b00;
				aluop[1] 	<= 1'b0;
				aluscr   	<= 1'b1;
			end
          	6'b00_0010: begin //jump
              jump	<= 1'b1;
              regwrite	<= 1'b0;
            end
          	6'b00_0011: begin
              jump <= 1'b1;
              regdst[1:0]	<= 2'b10;
              memtoreg[1:0]	<= 2'b10;

            end
			6'b00_0000: begin // add
			end
		endcase
	end
endmodule


module datamem(dataOut, address, dataIn, readmode, writemode);
    output reg [31:0] dataOut;
    input [31:0] address;
    input [31:0] dataIn;
    input readmode;
    input writemode;

  reg [31:0] dMemory [2499:250];

    always@ (readmode or writemode)
    begin
        if (writemode == 1)
          dMemory[address >> 2]=dataIn; //store data
        if (readmode == 1)
          dataOut = dMemory[address >> 2]; //load data
    end

endmodule

module instr_mem (	input [31:0] address,
					output [31:0] instruction );

 	reg [31:0] memory [249:0];
 	integer i;

	initial
		begin
			for (i=0; i<250; i=i+1)
              memory[i] = 32'b0;
 				// Insert MIPS's assembly here start at memory[10] = ...
          //memory[10] = 32'b000000_01000_01001_01010_00000_100000;    // add $t2, $t0, $1
          //memory[11] = 32'b000100_01000_01000_0000000000000100;		 // beq $t0, $t0,
          //memory[12] = 32'b000010_00000_00000_00000_00000_101000;
          memory[10] = 32'b001000_00000_01000_00000_00000_000101;    // addi     $t0,    $0,     5
          memory[11] = 32'b101011_00100_00101_00000_00000_000000;    //110100 sw
          memory[12] = 32'b100011_00100_00110_00000_00000_000000; 	// 111000 lw
		end

	assign instruction = memory[address >> 2];

endmodule

module mux32_2to1(out, in0, in1, sel);
    output reg  [31:0] out;
    input [31:0] in0;
    input [31:0] in1;
	input sel;

  	always @(sel)
    begin
		case (sel)
			1'b0: out = in0;
			1'b1: out = in1;
		endcase
    end
endmodule

module mux32_3to1 (out, in0, in1, in2, sel);
  	output reg  [31:0] out;
	input [31:0] in0;
	input [31:0] in1;
	input [31:0] in2;
  	input [1:0] sel;

  	always @(sel)
    begin
		case (sel)
			2'b00: out = in0;
			2'b01: out = in1;
			2'b10: out = in2;
		endcase
    end
endmodule

module mux5_2to1(out, in0, in1, sel);
	output reg  [4:0] out;
	input [4:0] in0;
	input [4:0] in1;
	input sel;

  	always @(sel)
    begin
		case (sel)
			1'b0: out = in0;
			1'b1: out = in1;
		endcase
    end
endmodule

module mux5_3to1 (out, in0, in1, in2, sel);
	output reg  [4:0] out;
	input [4:0] in0;
	input [4:0] in1;
	input [4:0] in2;
  	input [1:0] sel;

  	always @(sel)
    begin
		case (sel)
			2'b00: out = in0;
			2'b01: out = in1;
			2'b10: out = in2;
		endcase
    end
endmodule

module registerMemory (
	input[4:0]reg_read1,
	input[4:0]reg_read2,
	input[4:0]reg_write,
  	input[1:0] regwrite_con, //register wirte from control unit
  	input[31:0] write_data,
	output reg[31:0] data1,
	output reg[31:0] data2
	);

 	reg[31:0]reg_mem[31:0];
  	integer i;
  	initial
      begin
  for (i=0;i<32;i++) reg_mem[i] = 0;
    //reg_mem[reg_read1] = 32'b00_0000000000_0000000000_000000100;
        reg_mem[8] = 32'b00_0000000000_0000000000_111101000; //MEM(1000)
        reg_mem[9] = 32'b00_0000000000_0000000000_0000000010; //data to MEM(1000)
        //reg_mem[10] = 32'b00_0000000000_0000000000_0000000010; //data to MEM(1000)
  end
 	always @(*) begin
		if (reg_read1 == 0)
				data1 = 0;
		else if ((reg_read1 == reg_write) && regwrite_con)
				data1 = write_data;
		else
				data1 = reg_mem[reg_read1][31:0];
	end

	always @(*) begin
		if (reg_read2 == 0)
				data2 = 0;
		else if ((reg_read2 == reg_write) && regwrite_con)
				data2 = write_data;
		else
				data2 = reg_mem[reg_read2][31:0];
	end

	always @(*) begin
		if (regwrite_con && reg_write != 0)
			// write a non $zero register
          reg_mem[reg_write] <= write_data;
	end
endmodule

module sign_extended (
  output signed [31:0] out,
input signed [15:0] in);

assign out = in;

endmodule

module cpu (
  	  input clk,
  	  output reg [31:0] addr,
  	  output reg [31:0] pc,
	  output [31:0] instruction,
	  output [1:0] cu_regdst,
	  output cu_jump, cu_branch, cu_memread,
	  output [1:0] cu_memtoreg,
	  output [1:0] cu_aluop,
	  output cu_memwrite, cu_aluscr, cu_regwrite,
	  output [4:0] mux1_regwrite,
	  output [31:0] mux3_writedata,
	  output [31:0] reg_readdata1, reg_readdata2,
	  output [31:0] signext_out,
	  output [31:0] mux2_out,
	  output [31:0] alu_out,
	  output alu_zero,
	  output [3:0] aluctrl_out,
	  output [31:0] dmem_readdata,
	  output bBranch
	  );
  		reg[31:0] pc;
  		initial begin
          addr = 32'b0000_0000_0000_0000_0000_0000_0010_1000;
        end


  		reg [31:0] ra;
  		parameter ra_addr = 5'b11111;

	    instr_mem instrmem (addr,instruction);

	    control_unit contrlu (instruction[31:26],
                              cu_regdst, cu_regwrite, cu_branch,
	                          cu_jump, cu_memread, cu_memtoreg,
	                          cu_memwrite, cu_aluop, cu_aluscr );

  		mux5_3to1 mux01 (mux1_regwrite, instruction[20:16], instruction[15:11], ra_addr, cu_regdst[1:0]);

	  	registerMemory regmem ( .reg_read1(instruction[25:21]),
								.reg_read2(instruction[20:16]),
	                           	.reg_write(mux1_regwrite[4:0]),
	                          	.regwrite_con(cu_regwrite),
	                          	.write_data(mux3_writedata),
	                          	.data1(reg_readdata1),
	                          	.data2(reg_readdata2));

	  	sign_extended signext (signext_out[31:0], instruction[15:0]);

	  	mux32_2to1 mux02 (mux2_out, reg_readdata2, signext_out, cu_aluscr);

	    alu_control aluctrl (cu_aluop, instruction[5:0], aluctrl_out);

	    alu ALU (aluctrl_out, reg_readdata1, mux2_out, alu_out, alu_zero);

	    datamem data_mem (dmem_readdata, alu_out, reg_readdata2, cu_memread, cu_memwrite);

    always @(posedge clk) begin
       pc <= addr + 4;

    end
  		//assign addr = pc;
  		mux32_3to1 mux03(mux3_writedata, alu_out, dmem_readdata, pc, cu_memtoreg);

	    and AND1(bBranch, cu_branch, alu_zero );

	  	reg[31:0] branch_shiftl2_result;
	  	assign branch_shiftl2_result = signext_out << 2;

	  	reg[31:0] j_addr;
	  	assign j_addr = {pc[31:28],(instruction[25:0] << 2)};

	  reg[31:0] b_addr;
	  assign b_addr = pc + branch_shiftl2_result;
	  reg[31:0] mux04_result;

	  mux32_2to1 mux04 (mux04_result, pc, b_addr, bBranch);
	  mux32_2to1 mux05 (mux05_result, mux04_result, j_addr, cu_jump);
  //always @(posedge clk) begin

  //end

	  //assign out = mux05_result; //next address output
endmodule
