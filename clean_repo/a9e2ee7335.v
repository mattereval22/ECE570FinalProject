module L2(clock, CDB, CPUreceiver, selectedEmit);

input[21:0]CDB; //recebe mensagem do barramento comum
input[21:0]CPUreceiver; //recebe mensagem do processador
input clock;
reg[15:0]Data[3:0]; //armazena o dado, quando valido, do banco nos processadores
reg[2:0]Tag[3:0]; //armazena as tags presentes nos dois processadores
reg[1:0]Sharers[3:0]; //armazena quais processadores compartilham determinada tag, possui 1 quando o processador da posicao possui a tag
reg[1:0]State[3:0]; //guarda o estado de cada banco (linha)

wire[1:0]newState[3:0];
wire[3:0]soma;
wire[3:0]reset;
wire[3:0]clear;
wire[21:0]emit[3:0];
wire[21:0]pcEmit[1:0];

output reg[21:0]selectedEmit; //capaz de emitir dados no CDB

initial begin

	Data[0] = 16'b0000000000001010; //0010
	Data[1] = 16'b0000000000001000; //0008
	Data[2] = 16'b0000000001000100; //0068
	Data[3] = 16'b0000000000010010; //0018
	
	Tag[0] = 3'b000; //100 = Mem[0]
	Tag[1] = 3'b001; //108 = Mem[1]
	Tag[2] = 3'b110; //130 = Mem[6]
	Tag[3] = 3'b011; //118 = Mem[3]
	
	 //00=DI 01=DS 10=DM
	State[0] = 2'b10; //DM
	State[1] = 2'b01; //DS
	State[2] = 2'b10; //DM
	State[3] = 2'b01; //DS
	
	
	//[ P0?, P1? ]
	Sharers[0] = 2'b10;
	Sharers[1] = 2'b10;
	Sharers[2] = 2'b01;
	Sharers[3] = 2'b01;

	selectedEmit = 22'b1111111111111111111111;
	
end

StateMachineDir B0(clock, State[0], cdb, newState[0], emit[0], soma[0], reset[0], clear[0]);
StateMachineDir B1(clock, State[1], cdb, newState[1], emit[1], soma[1], reset[1], clear[1]);
StateMachineDir B2(clock, State[2], cdb, newState[2], emit[2], soma[2], reset[2], clear[2]);
StateMachineDir B3(clock, State[3], cdb, newState[3], emit[3], soma[3], reset[3], clear[3]);

PC0 pc00(clock, CDB, pcEmit[0], emitPC0, dataWB);
PC1 pc01(clock, CDB, pcEmit[1], emitPC1, dataWB);


always@(posedge clock)
begin
	selectedEmit = 22'b1111111111111111111111;

	if(CDB != 22'b1111111111111111111111)
	begin
		if(Tag[0] == CDB[15:13])
		begin
			State[0] = newState[0];
			if(soma[0] == 1'b1)
			begin
				Sharers[0][CDB[12]] = 1;
			end
			else if(reset[0] == 1'b1)
			begin
				Sharers[0][0] = 0;
				Sharers[0][1] = 0;
				Sharers[0][CDB[12]] = 1;
			end
			else if(clear[0] == 1'b1)
			begin
				Sharers[0][0] = 0;
				Sharers[0][1] = 0;
			end
			selectedEmit = {emit[0][21:16], Tag[0][3:0], CDB[12], 12'b0};
		end
		else if(Tag[1] == CDB[15:13])
		begin
			State[1] = newState[1];
			if(soma[1] == 1'b1)
			begin
				Sharers[1][CDB[12]] = 1;
			end
			else if(reset[1] == 1'b1)
			begin
				Sharers[1][0] = 0;
				Sharers[1][1] = 0;
				Sharers[1][CDB[12]] = 1;
			end
			else if(clear[1] == 1'b1)
			begin
				Sharers[1][0] = 0;
				Sharers[1][1] = 0;
			end
			selectedEmit = {emit[1][21:16], Tag[1][3:0], CDB[12], 12'b0};
		end
		else if(Tag[2] == CDB[15:13])
		begin
			State[2] = newState[2];
			if(soma[2] == 1'b1)
			begin
				Sharers[2][CDB[12]] = 1;
			end
			else if(reset[2] == 1'b1)
			begin
				Sharers[2][0] = 0;
				Sharers[2][1] = 0;
				Sharers[2][CDB[12]] = 1;
			end
			else if(clear[2] == 1'b1)
			begin
				Sharers[2][0] = 0;
				Sharers[2][1] = 0;
			end
			selectedEmit = {emit[2][21:16], Tag[2][3:0], CDB[12], 12'b0};
		end
		else if(Tag[3] == CDB[15:13])
		begin
			State[3] = newState[3];
			if(soma[3] == 1'b1)
			begin
				Sharers[3][CDB[12]] = 1;
			end
			else if(reset[3] == 1'b1)
			begin
				Sharers[3][0] = 0;
				Sharers[3][1] = 0;
				Sharers[3][CDB[12]] = 1;
			end
			else if(clear[3] == 1'b1)
			begin
				Sharers[3][0] = 0;
				Sharers[3][1] = 0;
			end
			selectedEmit = {emit[3][21:16], Tag[3][3:0], CDB[12], 12'b0};
		end
	end
	

end


endmodule
