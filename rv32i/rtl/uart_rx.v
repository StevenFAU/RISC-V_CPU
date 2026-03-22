// UART Receiver — 8N1, parameterized baud rate
// 2-stage synchronizer on rx input. Samples at mid-bit.
// `valid` pulses high for one cycle when a byte is received.

module uart_rx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    // States
    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    // 2-stage synchronizer for metastability protection
    reg rx_sync1, rx_sync2;
    always @(posedge clk) begin
        rx_sync1 <= rx;
        rx_sync2 <= rx_sync1;
    end
    wire rx_s = rx_sync2;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift_reg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= S_IDLE;
            clk_cnt   <= 16'd0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
            data      <= 8'd0;
            valid     <= 1'b0;
        end else begin
            valid <= 1'b0; // Default: valid is a one-cycle pulse

            case (state)
                S_IDLE: begin
                    if (rx_s == 1'b0) begin
                        // Falling edge detected — potential start bit
                        state   <= S_START;
                        clk_cnt <= 16'd0;
                    end
                end

                S_START: begin
                    // Sample at midpoint of start bit
                    if (clk_cnt == (CLKS_PER_BIT / 2) - 1) begin
                        if (rx_s == 1'b0) begin
                            // Valid start bit
                            clk_cnt <= 16'd0;
                            bit_idx <= 3'd0;
                            state   <= S_DATA;
                        end else begin
                            // Glitch — false start, go back to idle
                            state <= S_IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_DATA: begin
                    // Sample at midpoint of each data bit
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        shift_reg[bit_idx] <= rx_s; // LSB first
                        if (bit_idx == 3'd7)
                            state <= S_STOP;
                        else
                            bit_idx <= bit_idx + 1;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_STOP: begin
                    // Wait for midpoint of stop bit
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        if (rx_s == 1'b1) begin
                            // Valid stop bit — output the received byte
                            data  <= shift_reg;
                            valid <= 1'b1;
                        end
                        // Return to idle regardless
                        state   <= S_IDLE;
                        clk_cnt <= 16'd0;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
            endcase
        end
    end

endmodule
