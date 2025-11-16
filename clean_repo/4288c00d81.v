module
LU (S0,S1,X,Y,F3);
//S0,S1 are the select bases
input X,Y,S0,S1;
output F3;
wire X0,X1,X2,X3;
and G1(X0,X,Y);
//if S0=S1=0 then we have the ‘and’ of our inputs(X,Y) as an output
or G2(X1,X,Y);
//if S1=0 S0=1 then we have the ‘or’ of our inputs(X,Y) as an output
not G3(X,X);
//if S1=1 0=0 then we have the ‘not’ of X
xor G4(X3,X,Y);
//if S0=S1=1 then we have the ‘xor’ of our inputs(X,Y) as an output
MUX_4_1 m1(S0,S1,X0,X1,X2,X3,F3);
Endmodule
