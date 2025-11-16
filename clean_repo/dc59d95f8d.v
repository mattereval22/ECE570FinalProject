module router
  #(parameter LOCAL_ADDR = 0,
    parameter LEVEL = 0, // for calculation of data widths
    parameter NUM_LEVELS = 4,
    parameter MIN_BIT_WIDTH = 8,
    parameter PACKET_WIDTH = 32,
    parameter FIFO_DEPTH_PARENT = 8,
    parameter FIFO_DEPTH_CHILD = 4,
    parameter DATA_WIDTH_PARENT = (1 << (NUM_LEVELS - LEVEL + $clog2(MIN_BIT_WIDTH) - 1)),
    parameter DATA_WIDTH_CHILD = (1 << (NUM_LEVELS - LEVEL-1 + $clog2(MIN_BIT_WIDTH) - 1))
    )
    (
     input                               clk, rst,
     
     // Parent transceiver ingress/egress
     input wire                          ingr_valid_parent,
     output wire                         ingr_ready_parent,
     input wire [DATA_WIDTH_PARENT-1:0]  ingr_data_parent,
     output wire                         egr_valid_parent,
     input wire                          egr_ready_parent,
     output wire [DATA_WIDTH_PARENT-1:0] egr_data_parent,

     // Left child transceiver ingress/egress
     input wire                          ingr_valid_childL,
     output wire                         ingr_ready_childL,
     input wire [DATA_WIDTH_CHILD-1:0]   ingr_data_childL,
     output wire                         egr_valid_childL,
     input wire                          egr_ready_childL,
     output wire [DATA_WIDTH_CHILD-1:0]  egr_data_childL,

     // Right child transceiver ingress/egress
     input wire                          ingr_valid_childR,
     output wire                         ingr_ready_childR,
     input wire [DATA_WIDTH_CHILD-1:0]   ingr_data_childR,
     output wire                         egr_valid_childR,
     input wire                          egr_ready_childR,
     output wire [DATA_WIDTH_CHILD-1:0]  egr_data_childR
     );

    // Forwarding channel between LEFT CHILD and PARENT
    wire [DATA_WIDTH_PARENT-1:0]         childL_parent_data;
    wire                                 childL_parent_valid;
    wire                                 childL_parent_ready;
    wire                                 childL_parent_last;
    wire [DATA_WIDTH_PARENT-1:0]         parent_childL_data;
    wire                                 parent_childL_valid;
    wire                                 parent_childL_ready;
    wire                                 parent_childL_last;

    // Forwarding channel between RIGHT CHILD and PARENT
    wire [DATA_WIDTH_PARENT-1:0]         childR_parent_data;
    wire                                 childR_parent_valid;
    wire                                 childR_parent_ready;
    wire                                 childR_parent_last;
    wire [DATA_WIDTH_PARENT-1:0]         parent_childR_data;
    wire                                 parent_childR_valid;
    wire                                 parent_childR_ready;
    wire                                 parent_childR_last;
    
    // Forwarding channel between RIGHT CHILD and LEFT CHILD
    wire [DATA_WIDTH_PARENT-1:0]         childR_childL_data;
    wire                                 childR_childL_valid;
    wire                                 childR_childL_ready;
    wire                                 childR_childL_last;
    wire [DATA_WIDTH_PARENT-1:0]         childL_childR_data;
    wire                                 childL_childR_valid;
    wire                                 childL_childR_ready;
    wire                                 childL_childR_last;

    // Processing channel between PE and PARENT
    wire [DATA_WIDTH_PARENT-1:0]         parent_pe_data;
    wire                                 parent_pe_valid;
    wire                                 parent_pe_ready;
    wire                                 parent_pe_last;
    wire [DATA_WIDTH_PARENT-1:0]         pe_parent_data;
    wire                                 pe_parent_valid;
    wire                                 pe_parent_ready;
    wire                                 pe_parent_last;

    // Processing channel between PE and LEFT CHILD
    wire [DATA_WIDTH_PARENT-1:0]         childL_pe_data;
    wire                                 childL_pe_valid;
    wire                                 childL_pe_ready;
    wire                                 childL_pe_last;
    wire [DATA_WIDTH_PARENT-1:0]         pe_childL_data;
    wire                                 pe_childL_valid;
    wire                                 pe_childL_ready;
    wire                                 pe_childL_last;
    
    // Processing channel between PE and RIGHT CHILD
    wire [DATA_WIDTH_PARENT-1:0]         childR_pe_data;
    wire                                 childR_pe_valid;
    wire                                 childR_pe_ready;
    wire                                 childR_pe_last;
    wire [DATA_WIDTH_PARENT-1:0]         pe_childR_data;
    wire                                 pe_childR_valid;
    wire                                 pe_childR_ready;
    wire                                 pe_childR_last;
    

    // PARENT transceiver
    transceiver #(.PACKET_WIDTH(PACKET_WIDTH),
                  .DATA_WIDTH_EXTERNAL(DATA_WIDTH_PARENT), .DATA_WIDTH_INTERNAL(DATA_WIDTH_PARENT),
                  .FIFO_DEPTH(FIFO_DEPTH_PARENT), .NUM_LEVELS(NUM_LEVELS), .LOCAL_ADDR(LOCAL_ADDR))
    parent_transceiver (.clk(clk), .rst(rst),
                        .in_valid_ingr(ingr_valid_parent), .in_ready_ingr(ingr_ready_parent), .in_data_ingr(ingr_data_parent), 
                        .out_valid_egr(egr_valid_parent), .out_ready_egr(egr_ready_parent), .out_data_egr(egr_data_parent),

                        // Inputs from other transceivers
                        .in_valid_fwd_A(childL_parent_valid),  
                        .in_ready_fwd_A(childL_parent_ready),  
                        .in_data_fwd_A(childL_parent_data),
                        .in_last_fwd_A(childL_parent_last),
        
                        .in_valid_fwd_B(childR_parent_valid),  
                        .in_ready_fwd_B(childR_parent_ready),  
                        .in_data_fwd_B(childR_parent_data),
                        .in_last_fwd_B(childR_parent_last),
        
                        .in_valid_proc(pe_parent_valid),   
                        .in_ready_proc(pe_parent_ready),   
                        .in_data_proc(pe_parent_data),
                        .in_last_proc(pe_parent_last),
        
                        // Outputs to other transceivers 
                        .out_valid_up(),    
                        .out_ready_up(1'b0),    
                        .out_data_up(),
                        .out_last_up(),
        
                        .out_valid_down_L(parent_childL_valid),
                        .out_ready_down_L(parent_childL_ready),
                        .out_data_down_L(parent_childL_data),
                        .out_last_down_L(parent_childL_last),
        
                        .out_valid_down_R(parent_childR_valid),
                        .out_ready_down_R(parent_childR_ready),
                        .out_data_down_R(parent_childR_data),
                        .out_last_down_R(parent_childR_last),
        
                        .out_valid_local(parent_pe_valid), 
                        .out_ready_local(parent_pe_ready), 
                        .out_data_local(parent_pe_data),
                        .out_last_local(parent_pe_last)
                        );

    // LEFT CHILD transceiver
    transceiver #(.PACKET_WIDTH(PACKET_WIDTH),
                  .DATA_WIDTH_EXTERNAL(DATA_WIDTH_CHILD), .DATA_WIDTH_INTERNAL(DATA_WIDTH_PARENT),
                  .FIFO_DEPTH(FIFO_DEPTH_CHILD), .NUM_LEVELS(NUM_LEVELS), .LOCAL_ADDR(LOCAL_ADDR))
    childL_transceiver (.clk(clk), .rst(rst),
                        .in_valid_ingr(ingr_valid_childL), .in_ready_ingr(ingr_ready_childL), .in_data_ingr(ingr_data_childL), 
                        .out_valid_egr(egr_valid_childL), .out_ready_egr(egr_ready_childL), .out_data_egr(egr_data_childL),

                        // Inputs from other transceivers
                        .in_valid_fwd_A(parent_childL_valid),  
                        .in_ready_fwd_A(parent_childL_ready),  
                        .in_data_fwd_A(parent_childL_data),
                        .in_last_fwd_A(parent_childL_last),
        
                        .in_valid_fwd_B(childR_childL_valid),  
                        .in_ready_fwd_B(childR_childL_ready),  
                        .in_data_fwd_B(childR_childL_data),
                        .in_last_fwd_B(childR_childL_last),
        
                        .in_valid_proc(pe_childL_valid),   
                        .in_ready_proc(pe_childL_ready),   
                        .in_data_proc(pe_childL_data),
                        .in_last_proc(pe_childL_last),
        
                        // Outputs to other transceivers 
                        .out_valid_up(childL_parent_valid),    
                        .out_ready_up(childL_parent_ready),    
                        .out_data_up(childL_parent_data),
                        .out_last_up(childL_parent_last),
        
                        .out_valid_down_L(),
                        .out_ready_down_L(1'b0),
                        .out_data_down_L(),
                        .out_last_down_L(),
        
                        .out_valid_down_R(childL_childR_valid),
                        .out_ready_down_R(childL_childR_ready),
                        .out_data_down_R(childL_childR_data),
                        .out_last_down_R(childL_childR_last),
        
                        .out_valid_local(childL_pe_valid), 
                        .out_ready_local(childL_pe_ready), 
                        .out_data_local(childL_pe_data),
                        .out_last_local(childL_pe_last)
                        );
    

    // RIGHT CHILD transceiver
    transceiver #(.PACKET_WIDTH(PACKET_WIDTH),
                  .DATA_WIDTH_EXTERNAL(DATA_WIDTH_CHILD), .DATA_WIDTH_INTERNAL(DATA_WIDTH_PARENT),
                  .FIFO_DEPTH(FIFO_DEPTH_CHILD), .NUM_LEVELS(NUM_LEVELS), .LOCAL_ADDR(LOCAL_ADDR))
    childR_transceiver (.clk(clk), .rst(rst),
                        .in_valid_ingr(ingr_valid_childR), .in_ready_ingr(ingr_ready_childR), .in_data_ingr(ingr_data_childR), 
                        .out_valid_egr(egr_valid_childR), .out_ready_egr(egr_ready_childR), .out_data_egr(egr_data_childR),

                        // Inputs from other transceivers
                        .in_valid_fwd_A(parent_childR_valid),  
                        .in_ready_fwd_A(parent_childR_ready),  
                        .in_data_fwd_A(parent_childR_data),
                        .in_last_fwd_A(parent_childR_last),
        
                        .in_valid_fwd_B(childR_childR_valid),  
                        .in_ready_fwd_B(childR_childR_ready),  
                        .in_data_fwd_B(childR_childR_data),
                        .in_last_fwd_B(childR_childR_last),
        
                        .in_valid_proc(pe_childR_valid),   
                        .in_ready_proc(pe_childR_ready),   
                        .in_data_proc(pe_childR_data),
                        .in_last_proc(pe_childR_last),
        
                        // Outputs to other transceivers 
                        .out_valid_up(childR_parent_valid),    
                        .out_ready_up(childR_parent_ready),    
                        .out_data_up(childR_parent_data),
                        .out_last_up(childR_parent_last),
        
                        .out_valid_down_L(childR_childL_valid),
                        .out_ready_down_L(childR_childL_ready),
                        .out_data_down_L(childR_childL_data),
                        .out_last_down_L(childR_childL_last),

                        .out_valid_down_R(),
                        .out_ready_down_R(1'b0),
                        .out_data_down_R(),
                        .out_last_down_R(),
        
                        .out_valid_local(childR_pe_valid), 
                        .out_ready_local(childR_pe_ready), 
                        .out_data_local(childR_pe_data),
                        .out_last_local(childR_pe_last)
                        );
    

endmodule
