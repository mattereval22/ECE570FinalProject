module ym (a,b,c,d,e,f,g,dp,D3,D2,D1,D0);
input D3,D2,D1,D0;
output a,b,c,d,e,f,g,dp;
reg a,b,c,d,e,f,g,dp;
always@(D3,D2,D1,D0)
begin
    case ({D3,D2,D1,D0})
        4'd0: {dp,g,f,e,d,c,b,a} = 8'hc0;
        4'd1: {dp,g,f,e,d,c,b,a} = 8'hf9;
        4'd2: {dp,g,f,e,d,c,b,a} = 8'ha4;
        4'd3: {dp,g,f,e,d,c,b,a} = 8'hb0;
        4'd4: {dp,g,f,e,d,c,b,a} = 8'h99;
        4'd5: {dp,g,f,e,d,c,b,a} = 8'h92;
        4'd6: {dp,g,f,e,d,c,b,a} = 8'h82;
        4'd7: {dp,g,f,e,d,c,b,a} = 8'hf8;
        4'd8: {dp,g,f,e,d,c,b,a} = 8'h80;
        4'd9: {dp,g,f,e,d,c,b,a} = 8'h90;
        default: {dp,g,f,e,d,c,b,a} = 8'hfe;
    endcase
end
endmodule
