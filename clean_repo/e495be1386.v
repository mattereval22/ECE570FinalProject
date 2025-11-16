`timescale 1ns / 10ps
module IR(
	input clk,
	input  reset,
	input  ir_read,
	
	output reg [3:0]HEX0,
	output reg [3:0]HEX1,
	output reg [3:0]HEX2,
	output reg [3:0]HEX3,
	output reg [3:0]HEX4,
	output reg [3:0]HEX5,
	output reg [3:0]HEX6,
	output reg [3:0]HEX7,
	output reg rx_complete

);
reg [31:0]out;
reg [8:0]clk100khz;
reg [9:0]h_counter,l_counter;
reg [1:0]state;
reg [4:0]counter;
wire clk100khz_wire;
wire ir_read_wire_neg;
wire ir_read_wire_pos;

always@(posedge clk or negedge reset)
begin
	if(!reset)clk100khz<=9'd0;
	else begin
		if(clk100khz == 9'd499 ) clk100khz<=5'd0;
		else clk100khz <= clk100khz + 1'b1;
	end
end

always@(posedge clk or negedge reset)
begin
	if(!reset)begin
		state <= 2'd0;
		h_counter <= 10'd0;
		l_counter <= 10'd0;
		counter<=5'b0;
		HEX0<=4'd0;
		HEX1<=4'd0;
		HEX2<=4'd0;
		HEX3<=4'd0;
		HEX4<=4'd0;
		HEX5<=4'd0;
		HEX6<=4'd0;
		HEX7<=4'd0;
		rx_complete<=1'b0;
	end
	else begin
		if(clk100khz_wire) begin
			if(ir_read)h_counter <= h_counter + 1'b1;
			else l_counter <= l_counter + 1'b1;
		end
		
		case(state)
			2'd0:begin
				HEX7 <=out[31:28];
				HEX6 <=out[27:24];
				HEX5 <=out[23:20];
				HEX4 <=out[19:16];
				HEX3 <=out[15:12];
				HEX2 <=out[11:8];
				HEX1 <=out[7:4];
				HEX0 <=out[3:0];
				if(ir_read_wire_neg)begin
					h_counter <= 10'd0;
					l_counter <= 10'd0;
					if(l_counter<10'd950 && l_counter>10'd850 && h_counter<10'd500 && h_counter>10'd400)
						state<=2'd1;
				end
			end
			2'd1:begin
				if(ir_read_wire_neg)begin
					h_counter <= 10'd0;
					l_counter <= 10'd0;
					if(l_counter<10'd61 && l_counter>10'd51 && h_counter<10'd174 && h_counter>10'd164)
						out[counter]<=1'b1;
					if(l_counter<10'd61 && l_counter>10'd51 && h_counter<10'd61 && h_counter>10'd51)
						out[counter]<=1'b0;
					counter<=counter+1'b1;
					if(counter==5'd31)begin
						state<=2'd2;
						rx_complete<=1'b1;
					end
				end
			end
			2'd2:begin
				counter<=counter+1'b1;
				if(counter==5'd31)begin
					state<=2'd0;
					rx_complete<=1'b0;
				end
			end

		endcase
	end
end


neg_edge_detect u1(clk,reset,clk100khz[8],clk100khz_wire);
neg_edge_detect u2(clk,reset,ir_read,ir_read_wire_neg);
pos_edge_detect u3(clk,reset,ir_read,ir_read_wire_pos);

endmodule