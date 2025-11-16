module AddressCounter(SCL,START,STOP, LoadAddLSB, LoadAddMSB, IncrAddr, shiftRegOut, AddrRegOut);

input SCL,LoadAddLSB,LoadAddMSB, IncrAddr, shiftRegOut,START,STOP;

wire [7:0] shiftRegOut;
reg [7:0] tempAddr;
output reg [15:0] AddrRegOut;

always @(posedge START)
 AddrRegOut = 16'b0;

always @(posedge IncrAddr or posedge LoadAddLSB or posedge LoadAddMSB)
begin
	if(LoadAddLSB==1)
	begin
		AddrRegOut[7:0] = shiftRegOut;
	end

	if(LoadAddMSB==1)
	begin
		AddrRegOut[15:8]=shiftRegOut;
	end

	if(IncrAddr==1)
	begin
		tempAddr = AddrRegOut[7:0];
		tempAddr = tempAddr + 1;
		AddrRegOut[7:0] = tempAddr;
	end
end

endmodule
