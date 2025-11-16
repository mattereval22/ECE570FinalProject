
module IO (
    IO_ENABLE,
    DB,
    AB,
    CB,
    DREQ,DACK,CLK

);
output reg DREQ;
input IO_ENABLE;
inout [7:0] DB;
inout [7:0] AB;
inout [3:0] CB;
input CLK;
input DACK;
reg  [7:0]  IO_MEM [254:0];
initial begin
IO_MEM[30] = 11110000;
IO_MEM[31] = 00001111;
IO_MEM[32] = 01010101;
IO_MEM[33] = 00000001;

end

assign CB = 4'bzzzz;
assign AB = 8'bzzzzzzzz;
assign DB = (CB[3]&&DACK===1)?(IO_MEM[AB+5]):8'bzzzzzzzz;

always @(IO_ENABLE) begin
    DREQ <= IO_ENABLE;
    
end
always @ (posedge CLK)
if(CB[2]&!CB[3])begin
    if(DACK)begin IO_MEM[AB+3]<=DB;  end
end
    
endmodule