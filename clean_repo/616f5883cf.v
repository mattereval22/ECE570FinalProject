module neuron_state (
    input      [511:0] cur,
    input      [511:0] vol,
    input      [ 31:0] vt,
    input      [  1:0] VL,
    output reg [511:0] vol_out
);
  reg     [31:0] VOLT [32];
  reg            SPIKE[32];
  reg     [ 3:0] len;

  integer        i;

  always @(*) begin
    len = 4'd0;
    if (VL == 2'b00) len = 4'd0;
    else if (VL == 2'b01) len = 4'd3;
    else if (VL == 2'b10) len = 4'd15;

    for (i = 0; i <= len; i = i + 1) begin
      VOLT[i] = vol[32*i+:32] + cur[32*i+:32] - (vol[32*i+:32] >> 2);
      if (VOLT[i] >= vt) begin
        SPIKE[i] = 1'b1;
        //VOLT[i]  = 32'd0;
      end
    end
  end

  integer j;
  always @(*) begin
    for (j = 0; j < 16; j = j + 1) begin
      vol_out[32*j+:32] = VOLT[j];
    end
  end
endmodule
