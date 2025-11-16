module AT_block(
    input  wire [2:0]          phi_r,
    input  wire signed [19:0]  xs, ys,    // first-octant cosine (xs) and sine (ys)
    output reg  signed [19:0]  sin_out, cos_out
);

    // Intermediate shifted versions with sign bit zeroed
    wire [18:0] xs_shifted = xs[19:1];
    wire [18:0] ys_shifted = ys[19:1];

    // Function to apply sign manually (set MSB = 1 if negative)
    function [19:0] make_signed;
        input [18:0] val;
        input        sign;  // 0 = positive, 1 = negative
        begin
            make_signed = {sign, val};
        end
    endfunction

    always @* begin
        case (phi_r)
            3'b000: begin sin_out = make_signed(ys_shifted, 1'b0); cos_out = make_signed(xs_shifted, 1'b0); end
            3'b001: begin sin_out = make_signed(xs_shifted, 1'b0); cos_out = make_signed(ys_shifted, 1'b0); end
            3'b010: begin sin_out = make_signed(xs_shifted, 1'b0); cos_out = make_signed(ys_shifted, 1'b1); end
            3'b011: begin sin_out = make_signed(ys_shifted, 1'b0); cos_out = make_signed(xs_shifted, 1'b1); end
            3'b100: begin sin_out = make_signed(ys_shifted, 1'b1); cos_out = make_signed(xs_shifted, 1'b1); end
            3'b101: begin sin_out = make_signed(xs_shifted, 1'b1); cos_out = make_signed(ys_shifted, 1'b1); end
            3'b110: begin sin_out = make_signed(xs_shifted, 1'b1); cos_out = make_signed(ys_shifted, 1'b0); end
            3'b111: begin sin_out = make_signed(ys_shifted, 1'b1); cos_out = make_signed(xs_shifted, 1'b0); end
            default: begin sin_out = 20'b0; cos_out = 20'b0; end
        endcase
    end

endmodule
