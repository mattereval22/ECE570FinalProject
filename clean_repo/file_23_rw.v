module rw (
    input rwD,
    input clk,
    output reg rwQ
);
    always @(posedge clk ) begin
        rwQ<=rwD;
    end
endmodule