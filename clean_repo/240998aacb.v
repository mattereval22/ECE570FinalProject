module Data_Memory(
    output reg [31:0] readdata,
    input [31:0] address,
    input [31:0] writedata,
    input memwrite,
    input memread,
    input clk
);
    reg [31:0] DM [255:0]; // 256-word memory

    // Initialize memory with incremental values
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            DM[i] = i;
        end
    end

    always @(posedge clk) begin
        if (memwrite)
            DM[address >> 2] <= writedata; // Divide by 4 to get the correct word address
    end

    always @(posedge clk) begin
        if (memread)
            readdata <= DM[address >> 2]; // Divide by 4 to get the correct word address
    end
endmodule


/*

# Time =                    0, Address = 00000014, WriteData = 00000000, ReadData = xxxxxxxx, MemWrite = 0, MemRead = 0
# Time =                   20, Address = 00000014, WriteData = 000000e5, ReadData = xxxxxxxx, MemWrite = 0, MemRead = 1
# Time =                   30, Address = 00000014, WriteData = 000000e5, ReadData = 00000005, MemWrite = 0, MemRead = 1
# Time =                   40, Address = 00000014, WriteData = 00000f14, ReadData = 00000005, MemWrite = 1, MemRead = 0
# Time =                   60, Address = 00000018, WriteData = 0000000a, ReadData = 00000005, MemWrite = 1, MemRead = 0
# Time =                   80, Address = 00000014, WriteData = 0000009e, ReadData = 00000005, MemWrite = 0, MemRead = 1
# Time =                   90, Address = 00000014, WriteData = 0000009e, ReadData = 00000f14, MemWrite = 0, MemRead = 1
# Time =                  100, Address = 00000018, WriteData = 0000007f, ReadData = 00000f14, MemWrite = 0, MemRead = 1
# Time =                  110, Address = 00000018, WriteData = 0000007f, ReadData = 0000000a, MemWrite = 0, MemRead = 1

*/