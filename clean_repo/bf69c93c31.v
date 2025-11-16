`timescale 1ns/1ps
module fu (
    input [4:0] ex_rs1_address,
    input [4:0] ex_rs2_address,
    input [4:0] mem_rd_address,
    input [4:0] wb_rd_address,
    input mem_reg_write,
    input wb_reg_write,
    output reg [1:0] forward1,
    output reg [1:0] forward2
);

// 00: use current value (no forwarding)
// 01: forward from EX/MEM
// 10: forward from MEM/WB


always @(*) begin
    forward1 = 2'b00;
    forward2 = 2'b00;
    if (mem_reg_write && (mem_rd_address != 5'b0)) begin
        if (mem_rd_address == ex_rs1_address) begin
            forward1 = 2'b01;
        end
        if (mem_rd_address == ex_rs2_address) begin
            forward2 = 2'b01;
        end
    end
    if (wb_reg_write && (wb_rd_address != 5'b0)) begin
        if ((wb_rd_address == ex_rs1_address) && (forward1 == 2'b00)) begin
            forward1 = 2'b10;
        end
        if ((wb_rd_address == ex_rs2_address) && (forward2 == 2'b00)) begin
            forward2 = 2'b10;
        end
    end
end
endmodule


