// ====================================================
//      Module Implementation of All UI Components
// ====================================================

module UI (
    input masterEnablewire,
    input CLOCK_50,
	input resetN,
    input [3:0] KEY,

    output [6:0] HEX0, 
    output [6:0] HEX1, 
    output [6:0] HEX2, 
    output [6:0] HEX3,
    output [6:0] HEX4,
    output [6:0] HEX5, 
	output [3:0] counter,
	output blackout,
	output canBuildWire
	);
	 

	wire enableEveryOneSecond;
    wire enableEveryHalfSecond;
	wire canBuild;

    // One second enableDC from here
    RateDivider #(.SPEED(1)) U0 (.clk(CLOCK_50), .enable(enableEveryOneSecond));
    
    // Half second enableDC from here
	RateDivider #(.SPEED(7)) U1 (.clk(CLOCK_50), .enable(enableEveryHalfSecond));


    // Implement game counter on HEX 5, 4, 3  
    gameTimeCounter U2 (.masterEnable(masterEnablewire), .enableDC(enableEveryOneSecond), .reset(resetN), .Clock(CLOCK_50), .hex3(HEX3), .hex4(HEX4), .hex5(HEX5));
    
    // Implement blackout cool down counter on HEX 2, 1 
    BlackOutCoolDown U3 (.enableDC(enableEveryOneSecond && masterEnablewire), .triggerButton(!KEY[3]), .clk(CLOCK_50), .ability(blackout), .hexCounterWireTens(HEX2), .hexCounterWireOnes(HEX1));
    
    // Implement gate cool down counter on HEX 0
    GateCoolDown U4 (.enableDC(enableEveryOneSecond && masterEnablewire), .triggerButton(!KEY[2]), .clk(CLOCK_50), .ability(canBuild), .hexCounterWire(HEX0));

    // Implement gate selection feature
    SelectGate U5 (.enableDC(enableEveryHalfSecond && masterEnablewire), .nextButton(!KEY[0]), .backButton(!KEY[1]), .clk(CLOCK_50), .canBuild(canBuild), .indicatorLoc(counter));
	
	assign canBuildWire = canBuild;

endmodule

