module top_module(
    input clk,
    input in,
    input areset,
    output out); //
	
    parameter A=2'd0, B=2'd1, C=2'd2, D=2'd3;
    reg [1:0] c_state, n_state;
    
    // State transition logic
    always @(*) begin
        case (c_state)
            A: n_state = in ? B : A;
            B: n_state = in ? B : C;
            C: n_state = in ? D : A;
            D: n_state = in ? B : C;
            default: n_state = A;
        endcase
    end

    // State flip-flops with asynchronous reset
    always @(posedge clk or posedge areset) begin
        if (areset) begin
            c_state <= A;
        end
        else begin
            c_state <= n_state;
        end
    end

    // Output logic
    assign out = (c_state == D);

endmodule
