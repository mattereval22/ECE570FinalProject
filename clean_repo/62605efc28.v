`timescale 1ns/100ps
module FINAL_sys_tb ();
reg  REF_CLK,RST,UART_CLK,RX_IN;
wire STP_ERR;
wire PAR_ERR;
wire TX_OUT;
reg [10:0] farme,ref_frame;
reg [7:0] data_alu_1,data_alu_2;
SYS_TOP DUT (REF_CLK,RST,UART_CLK,RX_IN,TX_OUT,
PAR_ERR,STP_ERR);
integer i;
reg [10:0] test_data;
parameter REF_CLK_HALF_PERIOD= 10;
parameter UART_CLK_HALF_PERIOD = 125;
parameter TX_CLK_HALF_PERIOD = 4000;
reg TX_CLK ;
integer case_index,correct_count,error_count;
//clock generator blocks :
initial
begin
 case_index=0; 
 correct_count=0;
 error_count =0;
end
//REF_CLK::
initial begin
REF_CLK =0;
forever begin
    # REF_CLK_HALF_PERIOD ;
    REF_CLK =! REF_CLK ;
    error_count=0;
end
end

//UART_CLK::
initial begin
UART_CLK =0;
forever begin
    # UART_CLK_HALF_PERIOD ;
    UART_CLK =! UART_CLK ;
end
end


//UART_TX_CLK::
initial begin
TX_CLK =0;
forever begin
    # TX_CLK_HALF_PERIOD ;
    TX_CLK =! TX_CLK ;
end
end
///////////////////////applying the stimulus :
initial begin
RX_IN=1;
RST_ASSertion();
//test write rf operation
frame_transmitter (8'hAA,1,0);

frame_transmitter (8'h7,1,0);

frame_transmitter (8'haa,1,0);

// test read rf operation
frame_transmitter (8'hBB,1,0);

frame_transmitter (8'h7,1,0);

test_RF_OUT(8'haa,0);

///////test_alu ----- add
frame_transmitter (8'hCC,1,0);

frame_transmitter (8'h7,1,0);

frame_transmitter (8'h8,1,0);

frame_transmitter (8'h0,1,0);

test_ALU_OUT(16'h f ,0);

///////test_alu ----------- sub
frame_transmitter (8'hCC,1,0);

frame_transmitter (8'h7,1,0);

frame_transmitter (8'h2,1,0);

frame_transmitter (8'h1,1,0);

test_ALU_OUT(16'h  5,0);

///////test_alu ----------- mult
frame_transmitter (8'hCC,1,0);

frame_transmitter (8'h7,1,0);

frame_transmitter (8'h2,1,0);

frame_transmitter (8'h2,1,0);

test_ALU_OUT(16'he,0);
///////test_alu ----------- div
frame_transmitter (8'hCC,1,0);

frame_transmitter (8'hf,1,0);

frame_transmitter (8'h3,1,0);

frame_transmitter (8'h3,1,0);

test_ALU_OUT(16'h 5,0);
///////test_alu ----------- and
frame_transmitter (8'hCC,1,0);

frame_transmitter (8'd15,1,0);

frame_transmitter (8'h3,1,0);

frame_transmitter (8'h4,1,0);

test_ALU_OUT((15 & 3),0);

///////test_alu ----------- or
frame_transmitter (8'hCC,1,0);

frame_transmitter (8'd11,1,0);

frame_transmitter (8'h4,1,0);

frame_transmitter (8'h5,1,0);

test_ALU_OUT((11 | 4),0);

///////test_alu ----------- equal
frame_transmitter (8'hCC,1,0);

frame_transmitter (8'd 11,1,0);

frame_transmitter (8'd 11,1,0);

frame_transmitter (8'ha,1,0);

///////test_alu ----------- NO operands
frame_transmitter (8'hDD,1,0);

frame_transmitter (8'h0,1,0);
test_ALU_OUT(22,0);


////////////////////////

$display (" ///////////////////CHANGING UART CONFIGERATIONS///////////////////////////// ");
$display (" PRESCALE = 16 PAR_TYPE=1 PAR_EN = 1 ");
//test write rf operation
frame_transmitter (8'hAA,1,0);

frame_transmitter (8'd2,1,0);

frame_transmitter (8'b0100_0011,1,0);

frame_transmitter (8'hCC,1,1);

frame_transmitter (8'd 9,1,1);

frame_transmitter (8'd 15,1,1);

frame_transmitter (8'd 0,1,1);

test_ALU_OUT(24,1);


///test write rf operation
frame_transmitter (8'hAA,1,1);

frame_transmitter (8'hc,1,1);

frame_transmitter (8'hbb,1,1);

// test read rf operation
frame_transmitter (8'hBB,1,1);

frame_transmitter (8'hc,1,1);

test_RF_OUT(8'hbb,1);

repeat (10)
begin
    @(negedge TX_CLK);
end
$display("testbench is ended ");
$display("number of wrong cases is %0d",error_count);
$display("number of correct cases is %0d ",correct_count);
$stop;

end


task frame_transmitter (input [7:0] data,input parity_en,input PAR_TYP);
 begin
 if(parity_en)
 begin
    farme[9]=(!PAR_TYP)?(^(data)):(~^(data));
    farme[0]=0;
    farme[10]=1;
    farme[8:1] = data;
 end else begin
    farme[0]=0;
    farme[10]=1;
    farme[9]=1;
    farme[8:1] = data;
 end   
 for (i = 0; i <=10 ; i=i+1 ) begin
   @(negedge TX_CLK);
   RX_IN =farme[i]; 
 end
 end
endtask


task RST_ASSertion();
begin
RST=0;
$display("reset assertion :)"); 
repeat(2) begin @(negedge UART_CLK); end
if(TX_OUT !== 0)
begin
   $display("the design is reseted :)"); 
end else begin
    $display("error in reset  :("); 
end
RST=1;
repeat(4) begin @(negedge UART_CLK); end
end
endtask

task test_RF_OUT(input [7:0] expected_data,input PAR_TYP);
  begin
    case_index = case_index +1; 
   $display ("//////////////////case_ %0d /////////////////" ,case_index);
   @(negedge TX_OUT);
   for (i =0 ;i < 11 ;i=i+1 ) begin
   @(negedge TX_CLK) 
   test_data [i] = TX_OUT;  
   end
   ref_frame= {1'b1,((!PAR_TYP)?(^(expected_data)):(~^(expected_data))),expected_data,1'b0};
   if(test_data == ref_frame)
   begin
   $display("case %0d :read_operaton_succeded :)",case_index);
    correct_count=correct_count+1;
    end
   else begin
     $display("case %0d :read_operaton_failed :(",case_index);
      error_count =error_count+1;
   end
  end
endtask

task test_ALU_OUT(input [15:0] expected_data,input PAR_TYP);
  begin
   case_index = case_index +1; 
   $display ("//////////////////case_ %0d /////////////////" ,case_index);
   @(negedge TX_OUT);
   for (i =0 ;i < 11 ;i=i+1 ) begin
   @(negedge TX_CLK)
   if (0<i<9) begin
   data_alu_1[i-1] = TX_OUT;
   end
   test_data [i] = TX_OUT;  
   end
   ref_frame= {1'b1,((! PAR_TYP)?(^(expected_data[7:0])):(~^(expected_data[7:0]))),expected_data[7:0],1'b0};
   if(test_data == ref_frame)
   $display("case %0d : read_ALU_succeded_FIRST_FRAME :)" ,case_index);
   else begin
     $display("case %0d :read_alu_failed_FIRST_FRAME :(",case_index);
   end
      @(negedge TX_OUT);
      for (i =0 ;i < 11 ;i=i+1 ) begin
   @(negedge TX_CLK)
   if (0<i<9) begin
   data_alu_2[i-1] = TX_OUT;
   end
   test_data [i] = TX_OUT;  
   end
   ref_frame= {1'b1,((! PAR_TYP)?(^(expected_data[15:8])):(~^(expected_data[15:8]))),expected_data[15:8],1'b0};
   if(test_data == ref_frame)
   $display("case %0d :read_ALU_succeded_SECOND_FRAME :)",case_index);
   else begin
     $display("case %0d :read_alu_failed_SECOND_FRAME :(",case_index);
   end
   if(expected_data=={data_alu_2,data_alu_1})
   begin
   $display("case %0d :read_alu total value:)",case_index);
   correct_count=correct_count+1;
   end
   else begin
     $display("case %0d :read_operaton_alu total value :(",case_index);
     error_count =error_count+1;
   end
  end
endtask
endmodule