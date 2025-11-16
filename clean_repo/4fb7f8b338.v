module TB (
);

    // Signals 
    reg Hclk, Hresetn;
    wire [31:0] Haddr,HWdata,HRdata,Paddr,PRdata,PWdata,Paddr_out,PWdata_out;
    wire Hwrite,Hreadyin,Penable,Pwrite,Hreadyout,Pwrite_out,Penable_out;
    wire [1:0] Htrans, Hresp;
    wire [2:0] Psel,Psel_out;

    // Modules instantiation
    AHB_Master M1(
    .Hclk (Hclk),
    .Hresetn (Hresetn),
    .Hreadyout (Hreadyout),
    .Hresp (Hresp),
    .Hrdata (HRdata),
    .Hwrite (Hwrite),
    .Hreadyin (Hreadyin),
    .Htrans (Htrans),
    .Hwdata (HWdata),
    .Haddr (Haddr)
    );

    Top M2(
    .Hclk (Hclk),
    .Hresetn (Hresetn),
    .Hwrite (Hwrite),
    .Hreadyin (Hreadyin),
    .Htrans (Htrans),
    .HWdata (HWdata),
    .Haddr (Haddr),
    .PRdata (PRdata),
    .Penable (Penable),
    .Pwrite (Pwrite),
    .Hreadyout (Hreadyout),
    .Hresp (Hresp),
    .Pselx (Psel),
    .PWdata (PWdata),
    .Paddr (Paddr),
    .HRdata (HRdata)
    );

    APB_Interface M3(
    .Pwrite (Pwrite), 
    .Penable (Penable), 
    .Pselx (Psel), 
    .Paddr (Paddr), 
    .Pwdata (PWdata), 
    .Pwriteout (Pwrite_out),
    .Penableout (Penable_out),
    .Pselxout (Psel_out),
    .Paddrout (Paddr_out),
    .Pwdataout (PWdata_out),
    .Prdata (PRdata)
    );
    
    // Clock generation
    initial Hclk = 1'b0;
    always #1 Hclk = ~Hclk;

    // Reset task --> activates reset in one clk cycle
    task reset; begin
       @(negedge Hclk) Hresetn = 1'b0;
       @(negedge Hclk) Hresetn = 1'b1; 
    end
    endtask

    // Test scenarios
    initial begin
        reset;
        M1.Write_transfer(); #60;
        //M1.Read_transfer(); #60;
        //M1.Burst_incr4_write(); #60;
        //M1.Burst_incr4_read(); #60;
        $finish;
    end 
endmodule
