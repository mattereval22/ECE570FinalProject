// UART Receiver Module
module uart_rx
  #(parameter CLKS_PER_BIT = 434) // Default: 50MHz/115200baud
  (
   input        i_clk,          // Input clock
   input        i_rx_serial,    // Serial input bit
   output       o_rx_dv,        // Data Valid signal (received byte valid)
   output [7:0] o_rx_byte       // Received byte
   );
  
  // State machine states
  parameter IDLE         = 3'b000;
  parameter RX_START_BIT = 3'b001;
  parameter RX_DATA_BITS = 3'b010;
  parameter RX_STOP_BIT  = 3'b011;
  parameter CLEANUP      = 3'b100;
  
  reg [2:0]    r_state     = IDLE;
  reg [15:0]   r_clk_count = 0;
  reg [2:0]    r_bit_index = 0;
  reg [7:0]    r_rx_byte   = 0;
  reg          r_rx_dv     = 0;
  reg [1:0]    r_rx_data   = 2'b11; // Double register input for metastability
  
  // Output assignments
  assign o_rx_dv    = r_rx_dv;
  assign o_rx_byte  = r_rx_byte;
  
  // Purpose: Double-register the incoming data for metastability
  always @(posedge i_clk)
    begin
      r_rx_data <= {r_rx_data[0], i_rx_serial};
    end
  
  // Main state machine
  always @(posedge i_clk)
    begin
      case (r_state)
        IDLE :
          begin
            r_rx_dv     <= 1'b0;
            r_clk_count <= 0;
            r_bit_index <= 0;
            
            if (r_rx_data[1] == 1'b0)          // Start bit detected
              r_state <= RX_START_BIT;
            else
              r_state <= IDLE;
          end
        
        // Verify middle of start bit still low
        RX_START_BIT :
          begin
            if (r_clk_count == (CLKS_PER_BIT-1)/2)
              begin
                if (r_rx_data[1] == 1'b0)
                  begin
                    r_clk_count <= 0;  // Reset counter, found middle
                    r_state     <= RX_DATA_BITS;
                  end
                else
                  r_state <= IDLE;
              end
            else
              begin
                r_clk_count <= r_clk_count + 1;
                r_state     <= RX_START_BIT;
              end
          end 
        
        // Read data bits
        RX_DATA_BITS :
          begin
            // Wait for middle of bit period
            if (r_clk_count < CLKS_PER_BIT-1)
              begin
                r_clk_count <= r_clk_count + 1;
                r_state     <= RX_DATA_BITS;
              end
            else
              begin
                r_clk_count          <= 0;
                r_rx_byte[r_bit_index] <= r_rx_data[1]; // Sample the bit
                
                // Check if we have received all bits
                if (r_bit_index < 7)
                  begin
                    r_bit_index <= r_bit_index + 1;
                    r_state     <= RX_DATA_BITS;
                  end
                else
                  begin
                    r_bit_index <= 0;
                    r_state     <= RX_STOP_BIT;
                  end
              end
          end 
        
        // Check for stop bit
        RX_STOP_BIT :
          begin
            // Wait for middle of stop bit
            if (r_clk_count < CLKS_PER_BIT-1)
              begin
                r_clk_count <= r_clk_count + 1;
                r_state     <= RX_STOP_BIT;
              end
            else
              begin
                r_rx_dv     <= 1'b1;  // Indicate received byte valid
                r_clk_count <= 0;
                r_state     <= CLEANUP;
              end
          end 
        
        // Stay here for one clock cycle
        CLEANUP :
          begin
            r_state <= IDLE;
            r_rx_dv <= 1'b0;
          end
        
        default :
          r_state <= IDLE;
        
      endcase
    end
endmodule
