`timescale 1ns/10ps

// `include "Core.v"

module MM (
    clk,
    rst,
    in_data,
    row_end,
    col_end,
    out_data,
    is_legal,
    change_row,
    valid,
    busy
);

    input clk;
    input rst;
    input [7:0] in_data;
    input row_end;
    input col_end;

    output signed [19:0] out_data;
    output is_legal;
    output change_row;
    output valid;
    output reg busy;

    // States
    // CAO: Compute and Output
    parameter [1:0] IDLE = 2'b00;
    parameter [1:0] READ = 2'b01;
    parameter [1:0] CAO = 2'b10;

    // Internal signals
    reg [1:0] current_state = IDLE;

    reg [7:0] previous_in_data;
    reg previous_row_end;
    reg previous_col_end;

    reg next_matrix;

    reg can_read;
    reg can_cao;

    reg [1:0] row_counter;
    reg [1:0] col_counter;

    wire done_cao;

    reg done_rst = 0;


    always @(posedge clk) begin
        previous_in_data <= in_data;
        previous_row_end <= row_end;
        previous_col_end <= col_end;
    end


    always @(posedge clk) begin
        if (rst && !done_rst) begin
            busy <= 0;

            next_matrix <= 0;

            can_read <= 0;
            can_cao <= 0;

            row_counter <= 0;
            col_counter <= 0;

            done_rst <= 1;
        end else if (!rst && done_rst) begin
            case (current_state)
                IDLE: begin
                    busy <= 0;

                    next_matrix <= 0;

                    can_read <= 1;
                    can_cao <= 0;

                    row_counter <= 0;
                    col_counter <= 0;

                    current_state <= READ;
                end
                READ: begin
                    if (previous_row_end && previous_col_end) begin
                        if (next_matrix) begin
                            busy <= 1;

                            next_matrix <= 0;

                            can_read <= 0;
                            can_cao <= 1;

                            current_state <= CAO;
                        end else begin
                            next_matrix <= 1;
                        end

                        row_counter <= 0;
                        col_counter <= 0;
                    end else begin
                        if (!previous_row_end && previous_col_end) begin
                            row_counter <= row_counter + 1;
                            col_counter <= 0;
                        end else begin
                            col_counter <= col_counter + 1;
                        end
                    end
                end
                CAO: begin
                    if (done_cao) begin
                        busy <= 0;

                        can_cao <= 0;

                        current_state <= IDLE;
                    end
                end
            endcase
        end
    end

    Core core (
        .clk(clk),
        .rst(rst),
        .in_data(previous_in_data),
        .next_matrix(next_matrix),
        .can_read(can_read),
        .can_cao(can_cao),
        .row_counter(row_counter),
        .col_counter(col_counter),
        .out_data(out_data),
        .is_legal(is_legal),
        .change_row(change_row),
        .valid(valid),
        .done_cao(done_cao)
    );

endmodule
