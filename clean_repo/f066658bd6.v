module AC #(parameter size = 16) (AC_OUT , CLK , CLR , LD ,INC , AC_INP,reset); 
input CLK , CLR , LD ,INC ,reset;
input [size - 1 :0] AC_INP ;
output reg [size - 1 :0] AC_OUT ;


always @(negedge CLK, posedge reset) begin
   if (reset)begin
    AC_OUT <= 0;
   end
else  if (CLR) begin 
        AC_OUT <= 0;
    end 
    
    else if (LD) begin
        AC_OUT <= AC_INP ; 
    end
    
    else if(INC) begin
        AC_OUT <= AC_OUT + 1;  
    end 
  else
    AC_OUT <= AC_OUT;
end

endmodule

