`ifndef _OR
`define _OR
`include "Not.v"

module Or(out, inA, inB);
    output wire out;
    input  wire inA;
    input  wire inB;

    wire notOutA;
    wire notOutB;

    Not  gate1(.out(notOutA), .in(inA));
    Not  gate2(.out(notOutB), .in(inB));
    nand gate3(out, notOutA, notOutB);
endmodule
`endif
