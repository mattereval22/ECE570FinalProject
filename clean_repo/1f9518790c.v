//`define BENCH

`define NANO9K
`include "clockworks.v"

module core(
	input         clk,
        input 	      resetn,
	output [31:0] IO_mem_addr,  // IO mem address
	input  [31:0] IO_mem_rdata, // data read from IO
	output [31:0] IO_mem_wdata, // data written to IO
	output        IO_mem_wr    // IO write flag
);
	`ifdef BENCH
		parameter dsz=16384, isz=16384;
	`elsif NANO9K	
		parameter dsz=4096, isz=4096;
	`else
		parameter dsz=8192, isz=8192;
	`endif
	
	reg [31:0] RAM [0:dsz-1];
	reg [31:0] ROM [0:isz-1];

	initial begin
        	$readmemh("PROGROM.hex", ROM);
        	$readmemh("DATARAM.hex", RAM);
    	end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function [6:0] opcode; input [31:0] I; opcode = I[6:0  ]; endfunction
	function [2:0] funct3; input [31:0] I; funct3 = I[14:12]; endfunction
	function [6:0] funct7; input [31:0] I; funct7 = I[31:25]; endfunction
	function [4:0] rs1ID ; input [31:0] I; rs1ID  = I[19:15]; endfunction
	function [4:0] rs2ID ; input [31:0] I; rs2ID  = I[24:20]; endfunction
	function [4:0] rdID  ; input [31:0] I; rdID   = (isBtype(I) | isStype(I)) ? 0 : I[11:7]; endfunction
	function [4:0] shamt ; input [31:0] I; shamt  = I[24:20]; endfunction
	function [1:0] csrId ; input [31:0] I; csrId = {I[27],I[21]};endfunction

	function [31:0] Iimm; input [31:0] I; Iimm = {{21{I[31]}}, I[30:20]};                        endfunction
	function [31:0] Simm; input [31:0] I; Simm = {{21{I[31]}}, I[30:25], I[11:7]};               endfunction
	function [31:0] Bimm; input [31:0] I; Bimm = {{20{I[31]}}, I[7], I[30:25], I[11:8], 1'b0};   endfunction
	function [31:0] Uimm; input [31:0] I; Uimm = {I[31], I[30:12], {12{1'b0}}};                  endfunction
	function [31:0] Jimm; input [31:0] I; Jimm = {{12{I[31]}}, I[19:12], I[20], I[30:21], 1'b0}; endfunction

	function isRtype ; input [31:0] I; isRtype=opcode(I)==7'b0110011; endfunction	
	function isLoad  ; input [31:0] I; isLoad =opcode(I)==7'b0000011; endfunction
	function isRimm  ; input [31:0] I; isRimm =opcode(I)==7'b0010011; endfunction 
	function isStype ; input [31:0] I; isStype=opcode(I)==7'b0100011; endfunction
	function isBtype ; input [31:0] I; isBtype=opcode(I)==7'b1100011; endfunction
	function isLUI   ; input [31:0] I; isLUI  =opcode(I)==7'b0110111; endfunction
	function isAUIPC ; input [31:0] I; isAUIPC=opcode(I)==7'b0010111; endfunction
	function isJAL   ; input [31:0] I; isJAL  =opcode(I)==7'b1101111; endfunction
	function isJALR  ; input [31:0] I; isJALR =opcode(I)==7'b1100111; endfunction
	function isSYSTEM; input [31:0] I; isSYSTEM=(I[6:0]==7'b1110011); endfunction

	function writes_rd; input [31:0] I; writes_rd = !isStype(I) & !isBtype(I)           ; endfunction
	function reads_rs1; input [31:0] I; reads_rs1 = !(isJAL(I) | isAUIPC(I) | isLUI(I)) ; endfunction
	function reads_rs2; input [31:0] I; reads_rs2 = isRtype(I) | isBtype(I) | isStype(I); endfunction

	function isEBREAK; input [31:0] I; isEBREAK = (isSYSTEM(I) && funct3(I) == 3'b000); endfunction
	function isCSRRS; input [31:0] I; isCSRRS = (isSYSTEM(I) && funct3(I) == 3'b010); endfunction

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	reg [63:0] cycle;
	reg [63:0] instret;

	always@(posedge clk) begin
		cycle <= !resetn ? 0 : cycle + 1;
	end

	localparam NOP = 32'b0000000_00000_00000_000_00000_0110011;

	wire rs1_HAZ = !fd_NOP & reads_rs1(fd_IR) & rs1ID(fd_IR)!=0 &    (
		       	(writes_rd(de_IR) & (rs1ID(fd_IR) == rdID(de_IR))) |
		        (writes_rd(em_IR) & (rs1ID(fd_IR) == rdID(em_IR))) ); 
	
	wire rs2_HAZ = !fd_NOP & reads_rs2(fd_IR) & rs2ID(fd_IR)!=0 &    (
		       	(writes_rd(de_IR) & (rs2ID(fd_IR) == rdID(de_IR))) |
		        (writes_rd(em_IR) & (rs2ID(fd_IR) == rdID(em_IR))) ); 
	
	wire halt = resetn & isEBREAK(de_IR);	

	wire data_HAZ = rs1_HAZ | rs2_HAZ;

	wire f_stall = data_HAZ | halt;
	wire d_stall = data_HAZ | halt;

	wire e_flush = e_JoB | data_HAZ;
	wire d_flush = e_JoB;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	reg [31:0] f_PC;

	always@(posedge clk) begin
		if(!f_stall) begin
			fd_IR <= ROM[f_PC[15:2]];
			fd_PC <= f_PC;
			f_PC  <= f_PC+4;
		end

		if(JoB) 
			f_PC <= JoB_ADDR;

		fd_NOP <= d_flush | !resetn;

		if(!resetn) begin
			f_PC  <=0;
		end
	
	end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	reg [31:0] fd_IR, fd_PC;
        reg fd_NOP;
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	wire        wb_enable;
	wire [31:0] wb_DATA;
	wire [4:0]  wb_rdID;

	reg [31:0] reg_file[0:31];
	
	always@(posedge clk) begin
		if(!d_stall) begin
			de_IR <= (e_flush | fd_NOP) ? NOP : fd_IR;
			de_PC <= fd_PC;	
		end	

		if(e_flush)
			de_IR <= NOP;
		
		if(wb_enable) begin
			reg_file[wb_rdID] <= wb_DATA;
		end

	end	

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	reg [31:0] de_IR, de_PC;
	wire [31:0] de_rs1 = reg_file[rs1ID(de_IR)];
       	wire [31:0] de_rs2 = reg_file[rs2ID(de_IR)];

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


	wire [31:0] e_ALUin1 = de_rs1;
	wire [31:0] e_ALUin2 = (isRtype(de_IR) | isBtype(de_IR))? de_rs2 : Iimm(de_IR);	

	wire e_minus = de_IR[30] & isRtype(de_IR);
	wire e_arith_shift = de_IR[30];
	wire [32:0] e_ALUminus = {1'b1, ~e_ALUin2} + {1'b0, e_ALUin1} + 33'b1;
	wire [31:0] e_ALUplus  = e_ALUin1 + e_ALUin2;

	wire e_LT = (e_ALUin1[31] ^ e_ALUin2[31]) ? e_ALUin1[31] : e_ALUminus[32];
	wire e_LTU = e_ALUminus[32];
	wire e_EQ = (e_ALUminus[31:0]==0);

	function [31:0] flip32; input [31:0] x;
		 flip32 = {x[ 0], x[ 1], x[ 2], x[ 3], x[ 4], x[ 5], x[ 6], x[ 7], 
			   x[ 8], x[ 9], x[10], x[11], x[12], x[13], x[14], x[15], 
			   x[16], x[17], x[18], x[19], x[20], x[21], x[22], x[23],
                           x[24], x[25], x[26], x[27], x[28], x[29], x[30], x[31]};
	endfunction

	wire [31:0] e_shifter_IN = (funct3(de_IR)==3'b001) ? flip32(e_ALUin1) : e_ALUin1;

	/* verilator lint_off WIDTH */
        wire [31:0] e_shifter = $signed({e_arith_shift & e_ALUin1[31], e_shifter_IN}) >>> e_ALUin2[4:0];
	/* verilator lint_on WIDTH */

	wire [31:0] e_left_shift = flip32(e_shifter);

	reg [31:0] e_ALUout;
	always@(*) begin
		case(funct3(de_IR))
			3'b000: e_ALUout = e_minus ? e_ALUminus[31:0] : e_ALUplus ;
			3'b001: e_ALUout = e_left_shift;
			3'b010: e_ALUout = {31'b0, e_LT};
			3'b011: e_ALUout = {31'b0, e_LTU};
			3'b100: e_ALUout = e_ALUin1 ^ e_ALUin2;
			3'b101: e_ALUout = e_shifter;
			3'b110: e_ALUout = (e_ALUin1 | e_ALUin2);
			3'b111: e_ALUout = (e_ALUin1 & e_ALUin2);	
		endcase
	end

	reg e_takeB;
	always@(*) begin
		case(funct3(de_IR))
			3'b000: e_takeB = e_EQ;
			3'b001: e_takeB = !e_EQ;
			3'b100: e_takeB = e_LT;
			3'b101: e_takeB = !e_LT;
			3'b110: e_takeB = e_LTU;
			3'b111: e_takeB = !e_LTU;
			default: e_takeB = 1'b0;
		endcase
	
	end

	wire [31:0] e_RES = (isJAL(de_IR) | isJALR(de_IR)) ? de_PC+4           :
			    isLUI(de_IR)                   ? Uimm(de_IR)       :
			    isAUIPC(de_IR)                 ? de_PC+Uimm(de_IR) :
			    e_ALUout			                       ;

	wire e_JoB = isJAL(de_IR) | isJALR(de_IR) | (isBtype(de_IR) & e_takeB);
	
	wire [31:0] e_JoB_ADDR = isBtype(de_IR) ? de_PC + Bimm(de_IR)   :
	       			 isJAL(de_IR)	? de_PC + Jimm(de_IR)   :
				 		  {e_ALUplus[31:1],1'b0};

	always@(posedge clk) begin
		em_IR  <= de_IR;
		em_PC  <= de_PC;
		em_rs2 <= de_rs2;
		em_RES <= e_RES;
		em_ADDR <= isStype(de_IR) ? de_rs1 + Simm(de_IR) :
					    de_rs1 + Iimm(de_IR) ;
	end
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	reg[31:0] em_IR, em_PC, em_rs2, em_RES, em_ADDR;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	wire [2:0] m_funct3 = funct3(em_IR);
	wire m_isB = (m_funct3[1:0] == 2'b00);
	wire m_isH = (m_funct3[1:0] == 2'b01);


	wire [31:0] m_store_DATA;
	assign m_store_DATA[ 7:0 ] = em_rs2[7:0];
	assign m_store_DATA[15:8 ] = em_ADDR[0] ? em_rs2[7:0]  : em_rs2[15:8 ] ;
	assign m_store_DATA[23:16] = em_ADDR[1] ? em_rs2[7:0]  : em_rs2[23:16] ;
	assign m_store_DATA[31:24] = em_ADDR[0] ? em_rs2[7:0]  :
				     em_ADDR[1] ? em_rs2[15:8] : em_rs2[31:24] ;

	wire [3:0] m_store_WMASK = m_isB ? (em_ADDR[1] ? (em_ADDR[0] ? 4'b1000 : 4'b0100)  :
							 (em_ADDR[0] ? 4'b0010 : 4'b0001)) :
				   m_isH ? (em_ADDR[1] ? 4'b1100 : 4'b0011)                :
				   4'b1111;

	wire M_isIO  = em_ADDR[22];
	wire M_isRAM = !M_isIO;

	assign IO_mem_addr  = em_ADDR;
	assign IO_mem_wr    = isStype(em_IR) & M_isIO;
	assign IO_mem_wdata = em_rs2;

	wire [3:0] m_WMASK = {4{isStype(em_IR) & M_isRAM}} & m_store_WMASK;

	wire [13:0] m_word_ADDR = em_ADDR[15:2];

	always@(posedge clk) begin
		mw_Mdata <= RAM[m_word_ADDR];
		if(m_WMASK[0]) RAM[m_word_ADDR][ 7:0 ] <= m_store_DATA[ 7:0 ];
		if(m_WMASK[1]) RAM[m_word_ADDR][15:8 ] <= m_store_DATA[15:8 ];
		if(m_WMASK[2]) RAM[m_word_ADDR][23:16] <= m_store_DATA[23:16];
		if(m_WMASK[3]) RAM[m_word_ADDR][31:24] <= m_store_DATA[31:24];
	end

	always@(posedge clk) begin
		mw_IR     <= em_IR;
		mw_PC     <= em_PC;
		mw_RES    <= em_RES;
		mw_IO_RES <= IO_mem_rdata;
		mw_ADDR   <= em_ADDR;

		case(csrId(em_IR)) 
			2'b00: mw_CSR_RES <= cycle[31:0];
			2'b10: mw_CSR_RES <= cycle[63:32];
			2'b01: mw_CSR_RES <= instret[31:0];
			2'b11: mw_CSR_RES <= instret[63:32];	 
		endcase 

		if(!resetn) begin
			instret <= 0;
		end else if(mw_IR != NOP) begin
			instret <= instret + 1;
		end
	end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	reg [31:0] mw_IR, mw_PC, mw_RES, mw_IO_RES, mw_ADDR, mw_Mdata, mw_CSR_RES;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	wire [2:0] w_funct3 = funct3(mw_IR);

	wire w_isB = (w_funct3[1:0] == 2'b00);
	wire w_isH = (w_funct3[1:0] == 2'b01);
	wire w_sign_e = !w_funct3[2];
	wire W_isIO   = mw_ADDR[22];

	wire [15:0] w_loadH = mw_ADDR[1] ? mw_Mdata[31:16] : mw_Mdata[15:0];
	wire [ 7:0] w_loadB = mw_ADDR[0] ? w_loadH[15:8 ] : w_loadH[7: 0];
	wire w_load_sign    = w_sign_e & (w_isB ? w_loadB[7] : w_loadH[15]);

	wire [31:0] w_mem_RES = w_isB ? {{24{w_load_sign}}, w_loadB} :
				w_isH ? {{16{w_load_sign}}, w_loadH} :
							    mw_Mdata ;

	assign wb_DATA = isLoad(mw_IR) ? (W_isIO ? mw_IO_RES : w_mem_RES):
			 isCSRRS(mw_IR)? mw_CSR_RES:
					 mw_RES    ;

	assign wb_enable = writes_rd(mw_IR) & (rdID(mw_IR)!=0);

	assign wb_rdID = rdID(mw_IR);

	wire JoB = e_JoB;
	wire [31:0] JoB_ADDR = e_JoB_ADDR;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	`ifdef BENCH
	   always @(posedge clk) begin
		   if(halt) $finish(); 
	   end
	`endif

endmodule

module SOC( input CLK, input RESET, output [5:0] LEDS );

	wire resetn, clk;

	wire [31:0] IO_mem_addr, IO_mem_rdata, IO_mem_wdata;
	wire IO_mem_wr;

	core CPU(
		.clk(clk),
		.resetn(resetn),
		.IO_mem_addr(IO_mem_addr),
		.IO_mem_rdata(IO_mem_rdata),
		.IO_mem_wdata(IO_mem_wdata),
		.IO_mem_wr(IO_mem_wr)
	);

	assign LEDS = IO_mem_wdata[5:0];

	wire [13:0] IO_wordaddr = IO_mem_addr[15:2];
	wire uart_valid = IO_mem_wr & IO_wordaddr[1];

	`ifdef BENCH
		always@(posedge clk) begin
			if(uart_valid) begin
				$write("%c", IO_mem_wdata[7:0]);
				$fflush(32'h8000_0001);
			end
		end
	`endif

	Clockworks CW(
		.CLK(CLK),
		.RESET(RESET),
		.clk(clk),
		.resetn(resetn)
	);

endmodule

