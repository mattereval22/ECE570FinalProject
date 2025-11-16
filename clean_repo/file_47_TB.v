`timescale 1ns/100ps
module TB();
parameter T_CLK = 20;
parameter T_CLK_SYS = T_CLK*32; 

reg CLK;

reg RST;
reg [31:0] Prog_BUS_READ;
reg [31:0] Data_BUS_READ;
wire [31:0] ADDR, ADDR_Prog;
wire CS, CS_P, WR_RD;
wire [31:0] Data_BUS_WRITE;


cpu DUT (CLK, RST, Prog_BUS_READ, Data_BUS_READ, ADDR, ADDR_Prog, CS, CS_P, WR_RD, Data_BUS_WRITE);

reg CLK_SYS, CLK_MUL;
reg [31:0] writeBack;

initial begin
	$init_signal_spy("/DUT/CLK_SYS", "CLK_SYS", 1);
	$init_signal_spy("/DUT/CLK_MUL", "CLK_MUL", 1);
	$init_signal_spy("/DUT/writeBack", "writeBack", 1);

	CLK = 0;
	RST = 1;
	Prog_BUS_READ = 32'bz;
	Data_BUS_READ = 32'bz;
	#T_CLK
	RST = 0;

	wait (ADDR == 16'h0DEF);
	#(T_CLK_SYS/2)
	$display("[Com hazzard] Data_BUS_WRITE = %d",Data_BUS_WRITE);

	#(T_CLK_SYS*3/2);

	wait (ADDR == 16'h0DEF);
	#(T_CLK_SYS/2);

	$display("[Sem hazzard] Data_BUS_WRITE = %d", Data_BUS_WRITE);
	$display("Valor esperado: %d", (32'd4001 - 'd2001) * (32'd5001 - 32'd3001));

	#(T_CLK_SYS * 2) 
	$stop;
end

always # (T_CLK/2) CLK = ~CLK;

endmodule

