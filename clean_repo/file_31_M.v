module M #(
    parameter WIDTH=16)
(
    input clk,
    input WE,       
    input [15:0] W_DATA,  
    input [11:0] IN_ADF,
    output reg [15:0] R_DATA    

);
// ANIL BUDAK - 2574812
reg [15:0] MEMORY [0:4095];


integer i;
initial begin
    // Initialize the MEMORY with 0s
    for (i = 0; i < 4096; i = i + 1) begin
        MEMORY[i] = 16'b0;
    end
end

// READ
always @(*) begin
    R_DATA = MEMORY[IN_ADF];
end

// WRITE
always @(posedge clk) begin
    if (WE) begin
        MEMORY[IN_ADF] <= W_DATA;
    end
end

endmodule
