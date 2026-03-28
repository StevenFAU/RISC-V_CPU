// Wishbone B4 Slave — UART TX/RX Wrapper
// Wraps existing uart_tx.v + uart_rx.v with Wishbone slave interface.
// Register layout (same as old bus_decoder):
//   +0x0: TX data   (W)  — write byte to transmit
//   +0x4: TX status (R)  — bit 0: busy
//   +0x8: RX data   (R)  — last received byte
//   +0xC: RX status (R)  — bit 0: valid (reading clears after 1 cycle)
// Immediate combinational ack.

module wb_uart #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire        clk,
    input  wire        rst,

    // Wishbone slave interface
    input  wire        wb_cyc_i,
    input  wire        wb_stb_i,
    input  wire        wb_we_i,
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    input  wire [3:0]  wb_sel_i,
    output reg  [31:0] wb_dat_o,
    output wire        wb_ack_o,

    // Physical UART pins
    output wire        uart_tx,
    input  wire        uart_rx
);

    // =========================================================================
    // Wishbone handshake — combinational ack
    // =========================================================================
    wire valid = wb_cyc_i & wb_stb_i;
    assign wb_ack_o = valid;

    // =========================================================================
    // Register decode — byte offset within UART region
    // =========================================================================
    wire [3:0] reg_sel = wb_adr_i[3:0];

    // =========================================================================
    // UART TX instance
    // =========================================================================
    wire [7:0] tx_data;
    reg        tx_send;
    wire       tx_busy;

    assign tx_data = wb_dat_i[7:0];

    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_uart_tx (
        .clk(clk), .rst(rst),
        .data(tx_data), .send(tx_send),
        .tx(uart_tx), .busy(tx_busy)
    );

    // =========================================================================
    // UART RX instance
    // =========================================================================
    wire [7:0] rx_data_raw;
    wire       rx_valid_raw;

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_uart_rx (
        .clk(clk), .rst(rst),
        .rx(uart_rx),
        .data(rx_data_raw), .valid(rx_valid_raw)
    );

    // =========================================================================
    // RX valid latch — holds valid until CPU reads status register
    // Clear is registered: takes effect one cycle after the status read,
    // so the read sees the valid flag before it gets cleared.
    // =========================================================================
    reg rx_valid_latch;
    reg [7:0] rx_data_latch;
    reg rx_clear_pending;
    reg rx_clear;

    always @(posedge clk) begin
        if (rst) begin
            rx_valid_latch   <= 1'b0;
            rx_data_latch    <= 8'd0;
            rx_clear_pending <= 1'b0;
        end else begin
            // Clear from previous cycle's status read
            if (rx_clear_pending) begin
                rx_valid_latch   <= 1'b0;
                rx_clear_pending <= 1'b0;
            end
            // Capture incoming RX data (takes priority over clear)
            if (rx_valid_raw) begin
                rx_valid_latch <= 1'b1;
                rx_data_latch  <= rx_data_raw;
            end
            // Register the clear request for next cycle
            if (rx_clear)
                rx_clear_pending <= 1'b1;
        end
    end

    // =========================================================================
    // TX write — send pulse on write to +0x0
    // =========================================================================
    always @(*) begin
        tx_send = 1'b0;
        if (valid && wb_we_i && reg_sel == 4'h0)
            tx_send = 1'b1;
    end

    // =========================================================================
    // Read mux / RX clear
    // =========================================================================
    always @(*) begin
        wb_dat_o = 32'd0;
        rx_clear = 1'b0;

        if (valid && ~wb_we_i) begin
            case (reg_sel)
                4'h0: wb_dat_o = 32'd0;                         // TX data (write-only)
                4'h4: wb_dat_o = {31'd0, tx_busy};              // TX status
                4'h8: wb_dat_o = {24'd0, rx_data_latch};        // RX data
                4'hC: begin
                    wb_dat_o = {31'd0, rx_valid_latch};          // RX status
                    rx_clear = 1'b1;                              // Reading clears valid
                end
                default: wb_dat_o = 32'd0;
            endcase
        end
    end

endmodule
