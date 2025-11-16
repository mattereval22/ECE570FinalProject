module debouncer (
    clk,
    ce,
    
    btn,
    
    btn_debounced,
    btn_click
);
      
// Parameters

parameter COUNTER_WIDTH = 2;

// Ports

input clk, ce;

input btn;

output btn_debounced;
output btn_click;

// Wires/regs

reg [1:0]               btn_sync;
reg [1:0]               btn_debounced_internal;
reg [COUNTER_WIDTH-1:0] counter;

// Assignments

assign btn_debounced = btn_debounced_internal[0];
assign btn_click     = btn_debounced_internal[0] & ~btn_debounced_internal[1];

// Modules

// Processes

always @(posedge clk) begin
    if (ce) begin
        btn_sync <= {btn_sync[0], btn};
        
        if (btn_sync[1]) begin
            if (~(&counter)) begin
                counter <= counter + 1;
            end
        end else begin
            counter <= {COUNTER_WIDTH{1'b0}};
        end
        
        btn_debounced_internal <= {btn_debounced_internal[0], &counter};
    end
end
   
endmodule
