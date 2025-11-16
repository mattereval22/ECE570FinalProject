module SC (clock, reset, count);
    input clock;
    input reset;

    output reg [3:0] count = 4'b0000;

    always @(posedge clock) begin
        if (reset == 1) begin
            count <= 4'b0000;
        end
        else begin
            count <= count + 1;
        end
    end
endmodule