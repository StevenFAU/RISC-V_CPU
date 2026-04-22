// UART Transmitter — 8N1, parameterized baud rate
// Idles high. Pulse `send` to begin transmission. `busy` high while transmitting.

module uart_tx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data,
    input  wire       send,
    output reg        tx,
    output wire       busy
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    // States
    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;   // Baud rate counter
    reg [2:0]  bit_idx;   // Which data bit (0–7)
    reg [7:0]  shift_reg; // Latched data

    // DEFERRED (Phase 0.3+): the `clk_cnt == CLKS_PER_BIT - 1` comparisons
    // below mix a 16-bit LHS with a 32-bit RHS expression. Functionally safe
    // — CLKS_PER_BIT is ~434 at 50 MHz / 115200 and fits in 16 bits — but
    // the RHS should be cast explicitly. Leaving as-is for now because Phase
    // 0.3 is scoped to infrastructure (lint + CI), not RTL width cleanups.
    /* verilator lint_off WIDTHEXPAND */

    assign busy = (state != S_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            tx        <= 1'b1;
            clk_cnt   <= 16'd0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    tx <= 1'b1;
                    if (send) begin
                        shift_reg <= data;
                        state     <= S_START;
                        clk_cnt   <= 16'd0;
                    end
                end

                S_START: begin
                    tx <= 1'b0; // Start bit
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        bit_idx <= 3'd0;
                        state   <= S_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_DATA: begin
                    tx <= shift_reg[bit_idx]; // LSB first
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        if (bit_idx == 3'd7)
                            state <= S_STOP;
                        else
                            bit_idx <= bit_idx + 1;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_STOP: begin
                    tx <= 1'b1; // Stop bit
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        state   <= S_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
            endcase
        end
    end
    /* verilator lint_on WIDTHEXPAND */

endmodule
