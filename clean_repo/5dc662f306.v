// GNU General Public License
//
// Copyright : (c) 2023-2024 Javier Beiro Piñón
//           : (c) 2023-2024 Beatriz Navidad Vilches
//           : (c) 2023-2024 Stefano Petrilli
//
// This file is part of Abejaruco <https://github.com/Beanavil/Abejaruco>.
//
// Abejaruco is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version.
//
// Abejaruco is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Abejaruco placed on the LICENSE.md file of the root folder.
// If not, see <https://www.gnu.org/licenses/>.

module Memory #(parameter PROGRAM = "../../programs/zero.o")

  (input wire clk,
   input wire enable,
   input wire op,
   input wire [MEMORY_ADDRESS_SIZE-1:0] address,
   input wire [CACHE_LINE_SIZE-1:0] data_in,

   output reg [CACHE_LINE_SIZE-1:0] data_out,
   output reg data_ready
   //  output reg memory_in_use                   // Memory is use by another module
  );
`include "src/parameters.v"

  reg [7:0] memory [0:MEMORY_LOCATIONS-1];
  // State definitions
  reg [1:0] state;
  reg [2:0] counter;

  initial
  begin
    $readmemh(PROGRAM, memory);
    data_ready = 1'b0;
    state = 2'b00;
    counter = 3'b000;
  end

  always @(negedge clk)
  begin
    if(data_ready)
    begin
      data_ready = 0;
    end
  end

  always @(posedge clk)
  begin
    `MEMORY_DISPLAY($sformatf("The address is %h, the state is %h", address, enable));

    if (enable)
    begin
      case (state)
        2'b00: /*IDLE*/
        begin
          state <= 2'b01;
          counter <= 0;
        end

        2'b01: /*WAIT*/
        begin
          state <= 2'b10;
        end

        2'b10: /*WRITE or READ*/
        begin
          `MEMORY_DISPLAY($sformatf("op = %b", op));
          if (op) /*write*/
          begin
            `MEMORY_DISPLAY("Enter in write");
            for (integer i = 0; i < CACHE_LINE_SIZE / 8; i = i + 1)
            begin
              memory[address + i] = data_in[i*8 +: 8];
            end
          end
          else /*read*/
          begin
            `MEMORY_DISPLAY("Enter in read");
            for (integer i = 0; i < CACHE_LINE_SIZE / 8; i = i + 1)
            begin
              data_out[i*8 +: 8] = memory[address + i];
            end
          end

          data_ready = 1'b1;
          state = 2'b00;
        end
      endcase
    end
  end
endmodule
