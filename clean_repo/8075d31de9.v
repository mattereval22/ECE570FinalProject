module HA (Sum, Carry, A, B);
output Sum, Carry;
input A, B;

and c1 (Carry, A, B);
xor c2 (Sum, A, B);

endmodule