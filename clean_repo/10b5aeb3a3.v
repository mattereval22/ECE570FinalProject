// A1 Q3
// Full Adder Module (Structural)
module FA(input A, B, C, output COUT, S);

    wire x, y, z;  // Intermediate wires

    // XOR gate for Sum
    xor g1(S, A, B, C);

    // AND gates for carry generation
    and g2(y, A, B);
    and g3(z, C, x);

    // OR gate for final carry out (COUT)
    or g4(x, A, B);
    or g5(COUT, y, z);

endmodule

// Testbench for Full Adder (FA)
module tb_FA;
    reg A, B, C;   // Inputs to the FA
    wire COUT, S;  // Outputs from the FA

    // Instantiate the Full Adder (FA)
    FA uut(.A(A), .B(B), .C(C), .COUT(COUT), .S(S));

    // Stimulate the inputs and observe the outputs
    initial begin
        // Generate the VCD file for waveform dumping
        $dumpfile("FA.vcd");  // Corrected the file name
        $dumpvars(0, tb_FA);  // Dump all signals in tb_FA module

        // Monitor the values of inputs and outputs
        $monitor("Time %t, A = %b, B = %b, C = %b, COUT = %b, S = %b", $time, A, B, C, COUT, S);

        // Apply stimulus (input values for different time steps)
        #10 A = 0; B = 0; C = 0;
        #10 A = 0; B = 0; C = 1;
        #10 A = 0; B = 1; C = 0;
        #10 A = 0; B = 1; C = 1;
        #10 A = 1; B = 0; C = 0;
        #10 A = 1; B = 0; C = 1;
        #10 A = 1; B = 1; C = 0;
        #10 A = 1; B = 1; C = 1;

        $finish;  // End the simulation
    end 
endmodule


