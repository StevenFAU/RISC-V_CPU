// Bus Decoder — routes data memory bus between RAM and UART peripherals
// Address map:
//   0x00010000 - 0x0001FFFF : Data RAM (64KB)
//   0x80000000 : UART TX data  (write byte to transmit)
//   0x80000004 : UART TX status (bit 0 = busy)
//   0x80000008 : UART RX data  (read received byte)
//   0x8000000C : UART RX status (bit 0 = valid, read clears it)
//
// Clean combinational address decode — no buffering or pipelining.
// Designed for easy extension with additional peripherals.

module bus_decoder (
    input  wire        clk,
    input  wire        rst,

    // Core data memory bus (from rv32i_core)
    input  wire [31:0] dmem_addr,
    input  wire [31:0] dmem_wdata,
    input  wire        dmem_we,
    input  wire        dmem_re,
    input  wire [2:0]  dmem_funct3,
    output reg  [31:0] dmem_rdata,

    // RAM interface
    output wire [31:0] ram_addr,
    output wire [31:0] ram_wdata,
    output wire        ram_we,
    output wire        ram_re,
    output wire [2:0]  ram_funct3,
    input  wire [31:0] ram_rdata,

    // UART TX interface
    output reg  [7:0]  uart_tx_data,
    output reg         uart_tx_send,
    input  wire        uart_tx_busy,

    // UART RX interface
    input  wire [7:0]  uart_rx_data,
    input  wire        uart_rx_valid,
    output reg         uart_rx_clear
);

    // =========================================================================
    // Address decode — top 4 bits determine peripheral
    // =========================================================================
    wire sel_uart = (dmem_addr[31:28] == 4'h8);                    // 0x8xxxxxxx -> UART
    wire sel_ram  = (dmem_addr[31:16] == 16'h0001);                // 0x00010000-0x0001FFFF -> RAM
    wire sel_none = ~sel_uart & ~sel_ram;                           // Unmapped

    // =========================================================================
    // RAM pass-through (active when not UART)
    // Strip upper bits: RAM occupies 0x00010000-0x0001FFFF, mask to 0x0000-0xFFFF
    // =========================================================================
    assign ram_addr   = {16'd0, dmem_addr[15:0]};
    assign ram_wdata  = dmem_wdata;
    assign ram_we     = dmem_we & sel_ram;
    assign ram_re     = dmem_re & sel_ram;
    assign ram_funct3 = dmem_funct3;

    // =========================================================================
    // UART register decode (by byte offset within UART region)
    // =========================================================================
    wire [3:0] uart_reg = dmem_addr[3:0];

    // RX valid latch — holds valid until read by CPU
    // Clear is registered: takes effect one cycle after the status read,
    // so the read sees the valid flag before it gets cleared.
    reg rx_valid_latch;
    reg [7:0] rx_data_latch;
    reg rx_clear_pending;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_valid_latch <= 1'b0;
            rx_data_latch  <= 8'd0;
            rx_clear_pending <= 1'b0;
        end else begin
            // Clear from previous cycle's status read
            if (rx_clear_pending) begin
                rx_valid_latch   <= 1'b0;
                rx_clear_pending <= 1'b0;
            end
            // Capture incoming RX data (takes priority over clear)
            if (uart_rx_valid) begin
                rx_valid_latch <= 1'b1;
                rx_data_latch  <= uart_rx_data;
            end
            // Register the clear request for next cycle
            if (uart_rx_clear)
                rx_clear_pending <= 1'b1;
        end
    end

    // =========================================================================
    // UART writes (TX data register)
    // =========================================================================
    always @(*) begin
        uart_tx_data = dmem_wdata[7:0];
        uart_tx_send = 1'b0;

        if (dmem_we && sel_uart && uart_reg == 4'h0) begin
            // Write to 0x80000000 — TX data
            uart_tx_send = 1'b1;
        end
    end

    // =========================================================================
    // UART reads / RX clear
    // =========================================================================
    always @(*) begin
        uart_rx_clear = 1'b0;

        if (sel_uart && dmem_re) begin
            case (uart_reg)
                4'h0: dmem_rdata = 32'd0;                         // TX data (write-only)
                4'h4: dmem_rdata = {31'd0, uart_tx_busy};         // TX status
                4'h8: dmem_rdata = {24'd0, rx_data_latch};        // RX data
                4'hC: begin
                    dmem_rdata    = {31'd0, rx_valid_latch};       // RX status
                    uart_rx_clear = 1'b1;                          // Reading clears valid
                end
                default: dmem_rdata = 32'd0;
            endcase
        end else if (sel_ram) begin
            dmem_rdata = ram_rdata;
        end else begin
            dmem_rdata = 32'd0;  // Unmapped address
        end
    end

endmodule
