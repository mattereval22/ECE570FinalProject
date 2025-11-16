`timescale 100ps / 100ps

module RF(
    input [1:0] addr1,
    input [1:0] addr2,
    input [1:0] addr3,
    input [15:0] data3,
    input write,
    input clk,
    input reset,
    output reg [15:0] data1,
    output reg [15:0] data2
    );
    
    reg [15:0] reg1;
    reg [15:0] reg2;
    reg [15:0] reg3;
    reg [15:0] reg4;
    
    always @(posedge clk) begin
        if (reset == 1) begin
            reg1 <= 0;
            reg2 <= 0;
            reg3 <= 0;
            reg4 <= 0;
        end
        else if (write == 1) begin
            case (addr3)
                2'b00: reg1 <= data3;
                2'b01: reg2 <= data3;
                2'b10: reg3 <= data3;
                2'b11: reg4 <= data3;
            endcase
        end
    end
    
    always @(*) begin
        case (addr1)
            2'b00: data1 = reg1;
            2'b01: data1 = reg2;
            2'b10: data1 = reg3;
            2'b11: data1 = reg4;
        endcase

        case (addr2)
            2'b00: data2 = reg1;
            2'b01: data2 = reg2;
            2'b10: data2 = reg3;
            2'b11: data2 = reg4;
        endcase
    end
endmodule