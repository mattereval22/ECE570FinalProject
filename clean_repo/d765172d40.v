module SPI_Luks (
  input wire clk,
  input wire rstn,
  input wire valid,
  output reg ready,                           //  0 == master can retrieve data from slave
  output reg ss,                              //  0 sets slave in selected state
  output reg sclk,
  output reg [7:0] toMemory = 0,              //  takes 8 bits from rx_data (4-11) and sends it to memory
  input wire miso
);

  // Internal signals
reg [15:0] rx_data = 16'h0000;                //  collects data comming from slave
reg [4:0] counter = 0;                        //  counts 16 bits comming from slave
reg [2:0] state;

localparam zero=0, one=1, two=2, three=3, RST=4, IDLE=7;

// Initialize
initial begin
  state <= 7;
end

always @(posedge clk or negedge rstn) begin
  if (~rstn) begin
    state <= 4;
  end
  case (state) 
    zero: begin
      if (~ss) begin                              //  starts counter for sclk generating
        sclk <= ~sclk;  
      end
      state <= state + 1;
    end
    one: begin
      if (valid && sclk) begin
        counter <= counter + 1;
      end
      state <= state + 1;
    end
    two: begin
      if (valid && ~sclk) begin                  //  when valid, starts recieving data from slave
        rx_data [15:0] <= {rx_data[14:0], miso};  //  shifts old data and appends new data from slave
      end                                         //  slave sends data from msb to lsb
      if (counter == 16 && ~sclk) begin              //  6 == end of recieving data
        ready <= 1;                               //  it is placed in negedge because otherwise it would send extra data to memory
      end
      state <= state + 1;
    end
    three: begin
      if (ready == 1) begin                       //  when ready slave is deselected and it sends value from slave to memory
        ss <= 1;
        toMemory [7:0] <= rx_data [11:4];
        state <= 7;
      end else begin
        state <= 0;
      end
    end
    RST: begin
      rx_data <= 0;
      toMemory <= 0;                              //  sclk needs to be set in constant high state until it gets chip select
      state <= 7;
    end
    IDLE: begin
      sclk <= 1'b1;                               // Initialize sclk to high
      ss <= 1;
      ready <= 0;
      counter <= 0;

      if (valid) begin
        state <= 0;
        ss <= 0;
        toMemory <= 0;
      end
    end
  endcase
end

endmodule
