// FPGA Top-Level Wrapper for Nexys4 DDR
// Instantiates: rv32i_core, imem, wb_master, wb_interconnect, wb_dmem, uart_tx, uart_rx
// Target: Artix-7 XC7A100T, 100MHz, USB-UART at 115200

module fpga_top #(
    parameter IMEM_DEPTH    = 16384,        // 64KB instruction memory (16K words)
    parameter DMEM_DEPTH    = 65536,        // 64KB data memory (bytes)
    parameter IMEM_INIT     = "firmware.hex",
    parameter DMEM_INIT     = "dmem_init.hex",
    parameter CLK_FREQ      = 50_000_000,   // Core runs at 50MHz (100MHz / 2)
    parameter BAUD_RATE     = 115200
)(
    input  wire CLK100MHZ,
    input  wire CPU_RESETN,    // Active-low reset button
    input  wire UART_TXD_IN,  // FTDI TX -> FPGA RX (data into FPGA)
    output wire UART_RXD_OUT, // FPGA TX -> FTDI RX (data out of FPGA)
    output wire LED0,          // UART TX busy indicator
    output wire LED1           // UART RX valid indicator
);

    // Clock divider: 100MHz -> 50MHz
    reg clk_div = 0;
    always @(posedge CLK100MHZ)
        clk_div <= ~clk_div;

    wire clk = clk_div;

    // Reset synchronizer — 2-FF to avoid metastability
    reg rst_sync1 = 1, rst_sync2 = 1;
    always @(posedge clk) begin
        rst_sync1 <= ~CPU_RESETN;
        rst_sync2 <= rst_sync1;
    end
    wire rst = rst_sync2;

    // =========================================================================
    // Core bus signals
    // =========================================================================
    wire [31:0] imem_addr, imem_data;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire        dmem_we, dmem_re;
    wire [2:0]  dmem_funct3;
    wire [31:0] debug_pc, debug_instr;

    // =========================================================================
    // Wishbone master signals
    // =========================================================================
    wire        wb_cyc, wb_stb, wb_we;
    wire [31:0] wb_adr, wb_dat_m2s;
    wire [3:0]  wb_sel;
    wire [31:0] wb_dat_s2m;
    wire        wb_ack;
    wire [2:0]  wb_funct3;

    // =========================================================================
    // Wishbone slave signals — DMEM (slave 0)
    // =========================================================================
    wire        wbs0_cyc, wbs0_stb, wbs0_we;
    wire [31:0] wbs0_adr, wbs0_dat_m2s;
    wire [3:0]  wbs0_sel;
    wire [31:0] wbs0_dat_s2m;
    wire        wbs0_ack;
    wire [2:0]  wbs0_funct3;

    // =========================================================================
    // UART signals (directly wired for Phase 1 — UART not yet on Wishbone)
    // =========================================================================
    wire [7:0]  uart_tx_data;
    wire        uart_tx_send;
    wire        uart_tx_busy;
    wire [7:0]  uart_rx_data;
    wire        uart_rx_valid;

    // =========================================================================
    // CPU Core
    // =========================================================================
    rv32i_core u_core (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_data(imem_data),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_rdata(dmem_rdata), .dmem_we(dmem_we),
        .dmem_re(dmem_re), .dmem_funct3(dmem_funct3),
        .debug_pc(debug_pc), .debug_instr(debug_instr)
    );

    // =========================================================================
    // Instruction Memory
    // =========================================================================
    imem #(.DEPTH(IMEM_DEPTH), .INIT_FILE(IMEM_INIT)) u_imem (
        .addr(imem_addr), .instr(imem_data)
    );

    // =========================================================================
    // Wishbone Master Bridge
    // =========================================================================
    wb_master u_wb_master (
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_we(dmem_we), .dmem_re(dmem_re),
        .dmem_funct3(dmem_funct3), .dmem_rdata(dmem_rdata),
        .wb_cyc_o(wb_cyc), .wb_stb_o(wb_stb), .wb_we_o(wb_we),
        .wb_adr_o(wb_adr), .wb_dat_o(wb_dat_m2s), .wb_sel_o(wb_sel),
        .wb_dat_i(wb_dat_s2m), .wb_ack_i(wb_ack),
        .wb_funct3_o(wb_funct3)
    );

    // =========================================================================
    // Wishbone Interconnect
    // =========================================================================
    wb_interconnect u_wb_ic (
        .wbm_cyc_i(wb_cyc), .wbm_stb_i(wb_stb), .wbm_we_i(wb_we),
        .wbm_adr_i(wb_adr), .wbm_dat_i(wb_dat_m2s), .wbm_sel_i(wb_sel),
        .wbm_dat_o(wb_dat_s2m), .wbm_ack_o(wb_ack),
        .wbm_funct3_i(wb_funct3),
        // Slave 0: DMEM
        .wbs0_cyc_o(wbs0_cyc), .wbs0_stb_o(wbs0_stb), .wbs0_we_o(wbs0_we),
        .wbs0_adr_o(wbs0_adr), .wbs0_dat_o(wbs0_dat_m2s), .wbs0_sel_o(wbs0_sel),
        .wbs0_dat_i(wbs0_dat_s2m), .wbs0_ack_i(wbs0_ack),
        .wbs0_funct3_o(wbs0_funct3)
    );

    // =========================================================================
    // Data Memory (Wishbone Slave)
    // =========================================================================
    wb_dmem #(.DEPTH(DMEM_DEPTH), .INIT_FILE(DMEM_INIT)) u_wb_dmem (
        .clk(clk), .rst(rst),
        .wb_cyc_i(wbs0_cyc), .wb_stb_i(wbs0_stb), .wb_we_i(wbs0_we),
        .wb_adr_i(wbs0_adr), .wb_dat_i(wbs0_dat_m2s), .wb_sel_i(wbs0_sel),
        .wb_dat_o(wbs0_dat_s2m), .wb_ack_o(wbs0_ack),
        .wb_funct3_i(wbs0_funct3)
    );

    // =========================================================================
    // UART (not yet on Wishbone — Phase 2)
    // TX/RX modules still instantiated for LED indicators
    // =========================================================================
    assign uart_tx_data = 8'd0;
    assign uart_tx_send = 1'b0;

    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_uart_tx (
        .clk(clk), .rst(rst),
        .data(uart_tx_data), .send(uart_tx_send),
        .tx(UART_RXD_OUT), .busy(uart_tx_busy)
    );

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_uart_rx (
        .clk(clk), .rst(rst),
        .rx(UART_TXD_IN),
        .data(uart_rx_data), .valid(uart_rx_valid)
    );

    // =========================================================================
    // Debug LEDs
    // =========================================================================
    assign LED0 = uart_tx_busy;
    assign LED1 = uart_rx_valid;

endmodule
