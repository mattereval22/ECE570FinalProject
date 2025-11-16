module DR_Reg(
    input INR,LD,clk/*,CLR*/
    ,input[7:0] in
    ,output reg [7:0] out
) ;

initial begin
    out=8'h0;
end
    always @(posedge clk ) begin
        // if(CLR) out<=8'b0;
         if(LD)  out <=in;
         if(INR)  out<=out+1;
    end

endmodule


