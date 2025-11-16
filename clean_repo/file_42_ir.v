module ir(
    input wire clk, 
    input wire rst,
    input wire ld_ir,
    input wire [7:0] mem_out,
    output reg [2:0] opcode,
    output reg [4:0] address
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        {opcode, address} <= 8'b0;
    end
    else if(ld_ir) begin
        opcode <= mem_out[7:5];
        address <= mem_out[4:0];
    end
    else begin
        opcode <= opcode; // Maintain current opcode
        address <= address; // Maintain current address
    end
end

endmodule