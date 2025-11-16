module BR(
input Regwrite,
input [31:0]Din,
input [4:0]RA1,RA2,WA,
output  [31:0]DR1,DR2

);

reg [31:0]Breg[0:128];

initial
begin

$readmemb("/home/ise/Desktop/Proyecto/TestF1_BReg.mem",Breg);

end

    assign DR1 = Breg[RA1];
    assign DR2 = Breg[RA2];

always @*
begin
 //escribir
 if (Regwrite == 1)
   Breg[WA]=Din;

end

endmodule

