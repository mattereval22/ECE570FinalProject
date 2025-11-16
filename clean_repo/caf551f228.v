module OR(
    input [31:0] A,
    input [31:0] B,
    output reg[31:0] rezultat
);

integer i;

always @(*) begin
    for(i = 0; i < 32; i = i + 1) begin
        rezultat[i] = A[i] | B[i];
    end
end

endmodule