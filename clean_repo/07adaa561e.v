`timescale 1ns / 1ps

module TB;

    reg CLK, CLK_SYS, CLK_MUL, Reset;
	 wire CS, WE, CS_P;
	 reg [31:0] Data_BUS_READ, Prog_BUS_READ, writeBack;
    wire [31:0] ADDR, Data_BUS_WRITE, ADDR_Prog; 
	 
    cpu DUT (
        .CLK(CLK),
        .Reset(Reset),
        .Data_BUS_READ(Data_BUS_READ),
        .Prog_BUS_READ(Prog_BUS_READ),
        .ADDR(ADDR),
        .Data_BUS_WRITE(Data_BUS_WRITE),
        .ADDR_Prog(ADDR_Prog),
        .CS(CS),
		  .WE(WE),
		  .CS_P(CS_P)
		     );

    initial begin

		$init_signal_spy("DUT/CLK_SYS","CLK_SYS",1);
		$init_signal_spy("DUT/CLK_MUL","CLK_MUL",1);
		$init_signal_spy("DUT/writeBack","writeBack",1);
		
		CLK = 0;
		Reset = 1;
		
		Data_BUS_READ = 32'h0;
		Prog_BUS_READ = 32'h0;
		
		#10 Reset = 0;


		#100000 $stop;
    end

    always #10 CLK = ~CLK;

endmodule
