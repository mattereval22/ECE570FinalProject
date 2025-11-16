`timescale 1ns/1ps

`timescale 1ns/1ps

module uart_full_duplex_system_tb;

    // Señales del sistema
    reg clk_sys;
    reg rst;
    reg tx_start;
    reg tx_start_2;
    reg [7:0] tx_data_in;
    reg [7:0] tx_data_in_2;
    wire [7:0] rx_data_out;
    wire [7:0] rx_data_out_2;
    wire tx_ready;
    wire tx_ready_2;
    wire rx_valid;
    wire rx_valid_2;
    wire [2:0] tx_state;
    wire [2:0] tx_state_2;
    wire [2:0] rx_state;
    wire [2:0] rx_state_2;

    // Instancia del sistema full duplex
    uart_full_duplex_system uut (
        .clk_sys(clk_sys),
        .rst(rst),
        .tx_start(tx_start),
        .tx_start_2(tx_start_2),
        .tx_data_in(tx_data_in),
        .tx_data_in_2(tx_data_in_2),
        .rx_data_out(rx_data_out),
        .rx_data_out_2(rx_data_out_2),
        .tx_ready(tx_ready),
        .tx_ready_2(tx_ready_2),
        .rx_valid(rx_valid),
        .rx_valid_2(rx_valid_2),
        .tx_state(tx_state),
        .tx_state_2(tx_state_2),
        .rx_state(rx_state),
        .rx_state_2(rx_state_2)
    );

    
    
    // Generar reloj del sistema
    initial clk_sys = 0;
    always #5 clk_sys = ~clk_sys; // Periodo de 10ns

    // Simulación
    initial begin
        // Inicializar señales
        rst = 1;
        tx_start = 0;
        tx_start_2 = 0;
        tx_data_in = 8'h00;
        tx_data_in_2 = 8'h00;

        // Liberar reset
        #20 rst = 0;

        // Enviar datos del módulo 1 al módulo 2
        #30;
        tx_data_in = 8'hA5; // Dato 0xA5 desde el módulo 1
        tx_start = 1;
        #30 tx_start = 0; // Desactivar la señal de inicio

        // Esperar a que el receptor del módulo 2 reciba el dato
        wait(rx_valid_2);
        $display("Módulo 2 recibió: %h", rx_data_out_2);

        // Enviar datos del módulo 2 al módulo 1
        #50;
        tx_data_in_2 = 8'h38; // Dato 0x3C desde el módulo 2
        tx_start_2 = 1;
        #30 tx_start_2 = 0; // Desactivar la señal de inicio

        // Esperar a que el receptor del módulo 1 reciba el dato
        wait(rx_valid);
        $display("Módulo 1 recibió: %h", rx_data_out);

        // Finalizar simulación
        #400;
        $finish;
    end

    // Monitor para observar las señales clave
   initial begin
    $monitor("Time: %0dns | TX1 Ready: %b | RX1 Valid: %b | TX1 State: %b | RX1 State: %b | RX1 Data: %h || TX2 Ready: %b | RX2 Valid: %b | TX2 State: %b | RX2 State: %b | RX2 Data: %h",
                 $time, tx_ready, rx_valid, tx_state, rx_state, rx_data_out,
                 tx_ready_2, rx_valid_2, tx_state_2, rx_state_2, rx_data_out_2);
    end


    // Dumps para GTKWave
    initial begin
        $dumpfile("uart_full_duplex_system_tb.vcd");
        $dumpvars(0, uart_full_duplex_system_tb);
    end
endmodule
