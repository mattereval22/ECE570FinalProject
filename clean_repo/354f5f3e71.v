module OR(output Y,input A,B);
     or(Y,A,B);
endmodule

module or_gate;
     reg A,B;
     wire Y;

     OR instance0(Y,A,B);

     initial begin
        $dumpfile("orgate.vcd");
        $dumpvars(1);
        $display("Or gate realisation \nA B Y");
        $monitor(A," ",B," ",Y);

        A=0;B=0;#1;
        A=0;B=1;#1;
        A=1;B=0;#1;
        A=1;B=1;#1;
     end
endmodule