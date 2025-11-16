/*
--------------------------------------------------------------------------------
 Title        : digital_top
 Project      : 180-voltmeter
 File         : digital_top.v
 Description  : Top-level digital control module that orchestrates the voltmeter
                system. Integrates analog signal sanitization, SPI slave interface,
                and provides control signals to the analog front-. Handles
                communication with external SPI master and manages analog control
                outputs for measurement operations.
 
 Author       : Tristan Wood tdwood2@ncsu.edu
 Created      : 2025-08-13
 License      : See LICENSE in the project root

 Revision History:
   - 1.0 2025-08-13 Tristan Wood Initial implementation

   - 2.0 2025-09-27 Tristan Wood 
        
--------------------------------------------------------------------------------
*/

module digital_top (
    input wire clk_i,
    input wire rst_n_i,

    // Analog Signals
    input wire comp_i,
    input wire analog_ready_i,
    input wire bypass_en_i,
    input wire idle_bypass_i,
    input wire auto_zero_bypass_i,
    input wire integrate_bypass_i,
    input wire deintegrate_bypass_i,
    input wire ref_sign_bypass_i,
    output wire idle_o,
    output wire auto_zero_o,
    output wire integrate_o,
    output wire deintegrate_o,
    output wire mode_sel_o,
    output wire ref_sign_o,

    // -- SPI Signals
    input wire spi_sclk_i,
    input wire spi_cs_i,
    input wire spi_mosi_i,
    output wire spi_miso_o,

    // Measurement Signals
    input wire mode_sel_i,
    input wire trigger_1_i,
    input wire trigger_2_i,
    output wire interrupt_o,
    output wire [11:0] measurement_count_o,

    // -- JTAG Signals
    input wire tck_i,
    input wire trst_i,
    input wire tms_i,
    input wire tdi_i,
    output wire tdo_o,
    output wire tdo_padoe_o,
    output wire [63:0] analog_dbg_o,

    // Boundary Scan Signals
    input wire [13:0] bsr_i,
    output wire [14:0] bsr_o,
    output wire [14:0] bsr_oe,
    output wire extest_select

);
    //---------------------------------------------------------
    // Declarations
    //---------------------------------------------------------
    wire clk;
    wire comp, analog_ready; 
    wire [4:0] cycle_count;
    wire [9:0] pulse_count;
    wire finished;
    wire increment;
    wire pulse_trigger;
    wire idle, auto_zero, integrate, deintegrate;

    wire measurement_en;
    wire [11:0] measurement_count;
    wire measurement_clear;

    wire [88:0] dbg_status;
    wire [216:0] dbg_ctrl;

    //---------------------------------------------------------
    // Instantiations
    //---------------------------------------------------------

    // Clock Divider
    clock_divider clock_divider_inst (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .clk_o(clk),
        .dbg_i(dbg_ctrl[96:80]), 
        .dbg_o(dbg_status[63:48]) 
    );

    // Analog 
    sync_and_filter sync_and_filter_comp_inst #(
        .CTR_DBG_DEFAULT(13'b0100001100010) // FILTERED = 0, MAX = 8, HIGH_THRESH = 6, LOW_THRESH = 2
    ) sync_and_filter_comp_inst (
        .clk_i(clk),
        .rst_n_i(rst_n_i),
        .async_i(comp_i),
        .clean_out_o(comp),
        .dbg_i(dbg_ctrl[79:66]), 
        .dbg_o(dbg_status[47:44]) 
    );

    sync_and_filter sync_and_filter_analog_ready_inst #(
        .CTR_DBG_DEFAULT(13'b0100001100010) // FILTERED = 0, MAX = 8, HIGH_THRESH = 6, LOW_THRESH = 2
    ) sync_and_filter_analog_ready_inst (
        .clk_i(clk),
        .rst_n_i(rst_n_i),
        .async_i(analog_ready_i),
        .clean_out_o(analog_ready),
        .dbg_i(dbg_ctrl[65:52]), 
        .dbg_o(dbg_status[43:40]) 
    );

    sync_and_filter sync_and_filter_mode_sel_inst #(
        .CTR_DBG_DEFAULT(13'b0100001100010) // FILTERED = 0, MAX = 8, HIGH_THRESH = 6, LOW_THRESH = 2
    ) sync_and_filter_mode_sel_inst (
        .clk_i(clk),
        .rst_n_i(rst_n_i),
        .async_i(mode_sel_i),
        .clean_out_o(mode_sel_o),
        .dbg_i(dbg_ctrl[51:38]), 
        .dbg_o(dbg_status[39:36]) 
    );

    sync_and_filter sync_and_filter_trigger_1_inst #(
        .CTR_DBG_DEFAULT(13'b0100001100010) // FILTERED = 0, MAX = 8, HIGH_THRESH = 6, LOW_THRESH = 2
    ) sync_and_filter_trigger_1_inst (
        .clk_i(clk),
        .rst_n_i(rst_n_i),
        .async_i(trigger_1_i),
        .clean_out_o(trigger_1),
        .dbg_i(dbg_ctrl[37:24]), 
        .dbg_o(dbg_status[35:32]) 
    );

    sync_and_filter sync_and_filter_trigger_2_inst #(
        .CTR_DBG_DEFAULT(13'b0100001100010) // FILTERED = 0, MAX = 8, HIGH_THRESH = 6, LOW_THRESH = 2
    ) sync_and_filter_trigger_2_inst (
        .clk_i(clk),
        .rst_n_i(rst_n_i),
        .async_i(trigger_2_i),
        .clean_out_o(trigger_2),
        .dbg_i(dbg_ctrl[23:10]), 
        .dbg_o(dbg_status[31:28]) 
    );

    // Counters
    cycle_counter cycle_counter_inst (
        .clk_i(clk),
        .rst_n_i(rst_n_i),
        .increment_i(increment),
        .finished_o(finished),
        .cycle_count_o(cycle_count),
        .dbg_o(dbg_status[27:23])
    );

    pulse_counter pulse_counter_inst (
        .clk_i(clk),
        .rst_n_i(rst_n_i),
        .trigger_i(pulse_trigger),
        .stop_i(finished),
        .increment_o(increment),
        .pulse_count_o(pulse_count),
        .dbg_i(dbg_ctrl[9:0]),
        .dbg_o(dbg_status[22:12])
    );

    measurement_counter measurement_counter_inst (
        .clk_i(clk),
        .rst_n_i(rst_n_i),
        .measurement_en_i(measurement_en),
        .measurement_clear_i(measurement_clear),
        .measurement_count_o(measurement_count),
        .dbg_o(dbg_status[11:0])
    );

    // State Machine
    state_machine state_machine_inst (
        .clk_i(clk),
        .rst_n_i(rst_n_i),
        .trigger_i(trigger_1 || trigger_2),
        .digital_ready_o(digital_ready_o),
        .pulse_trigger_o(pulse_trigger),
        .comp_i(comp),
        .analog_ready_i(analog_ready),
        .idle_o(idle),
        .auto_zero_o(auto_zero),
        .integrate_o(integrate),
        .deintegrate_o(deintegrate),
        .ref_sign_o(ref_sign_o),
        .cycle_count_i(cycle_count),
        .pulse_count_i(pulse_count),
        .measurement_count_i(measurement_count),
        .measurement_en_o(measurement_en),
        .measurement_clear_o(measurement_clear),
        .dbg_i(dbg_ctrl[152:97]),
        .dbg_o(dbg_status[88:64])
    );
    
    // SPI slave instance
    spi_slave #(
        .SPI_MODE(0)
    ) spi_slave_inst (
        .i_Rst_L(rst_n_i),
        .i_Clk(clk),
        .o_RX_DV(interrupt_o),
        .o_RX_Byte(spi_ctrl),
        .i_TX_DV(finished),
        .i_TX_Byte(dbg_status),
        .i_SPI_Clk(spi_sclk_i),
        .o_SPI_MISO(spi_miso_o),
        .i_SPI_MOSI(spi_mosi_i),
        .i_SPI_CS_n(spi_cs_i)
    );

    // JTAG Tap
    jtag_tap jtag_tap_inst(
        // JTAG Pins
        .tck_pad_i(tck_i),
        .trst_pad_i(trst_i),
        .tms_pad_i(tms_i),
        .tdi_pad_i(tdi_i),
        .tdo_pad_o(tdo_o),
        .tdo_padoe_o(tdo_padoe_o),

        // Output from jtag_tap to test_interface, to allow monitoring of TAP states
        .shift_dr_o(shift_dr),
        .pause_dr_o(pause_dr),
        .update_dr_o(update_dr),
        .capture_dr_o(capture_dr),
        .test_logic_reset_o(test_logic_reset),

        // Select signals for boundary scan or mbist (outputs that tell what instruction is currently loaded)
        .extest_select_o(extest_select),
        .sample_preload_select_o(sample_preload_select),
        .mbist_select_o(mbist_select),
        .debug_select_o(debug_select),

        // TDO signal that is connected to TDI of sub-modules.
        .tdo_o(chip_tdi),

        // Input from test_interface to jtag_tap, to allow monitoring of TAP states
        .debug_tdi_i(tdi_debug),
        .bs_chain_tdi_i(tdi_bs),
        .mbist_tdi_i(tdi_mbist)    
    );

    // JTAG Debug Module
    jtag_debug_module jtag_debug_module_inst(
        // JTAG Pins
        .tck_i(tck_i),
        .test_logic_reset_i(test_logic_reset),

        // Output from jtag_tap to test_interface, to allow monitoring of TAP states
        .shift_dr_i(shift_dr),
        .pause_dr_i(pause_dr),
        .update_dr_i(update_dr),
        .capture_dr_i(capture_dr),

        // Select signals for boundary scan or mbist (outputs that tell what instruction is currently loaded)
        .extest_select_i(extest_select),
        .sample_preload_select_i(sample_preload_select),
        .mbist_select_i(mbist_select),
        .debug_select_i(debug_select),

        // TDI signal that is connected to TDI of sub-modules.
        .tdi_i(chip_tdi),

        // Input from test_interface to jtag_tap, to allow monitoring of TAP states
        .debug_tdi_o(tdi_debug),
        .bs_chain_tdi_o(tdi_bs),
        .mbist_tdi_o(tdi_mbist),

        // Boundary Scan Signals
        .bsr_i(bsr_i),
        .bsr_o(bsr_o),
        .bsr_oe(bsr_oe),

        // Debug Signals
        .spi_ctrl_i(spi_ctrl),
        .dbg_i(dbg_status),
        .dbg_o(dbg_ctrl)
    );

    //---------------------------------------------------------
    // Assignments
    //---------------------------------------------------------
    assign analog_dbg_o = dbg_ctrl[216:153];
    assign idle_o = (bypass_en_i) ? idle_bypass_i : idle;
    assign auto_zero_o = (bypass_en_i) ? auto_zero_bypass_i : auto_zero;
    assign integrate_o = (bypass_en_i) ? integrate_bypass_i : integrate;
    assign deintegrate_o = (bypass_en_i) ? deintegrate_bypass_i : deintegrate;
    assign ref_sign_o = (bypass_en_i) ? ref_sign_bypass_i : ref_sign_o;
endmodule