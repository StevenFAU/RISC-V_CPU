// FPGA Top-Level Wrapper for Nexys4 DDR
// Instantiates: rv32i_core, imem, dmem, bus_decoder, uart_tx, uart_rx
// Target: Artix-7 XC7A100T, 100MHz, USB-UART at 115200

module fpga_top #(
    parameter IMEM_DEPTH = 16384, // 64KB instruction memory (16K words)
    parameter DMEM_DEPTH = 65536, // 64KB data memory (bytes)
    parameter CLK_FREQ   = 50_000_000,  // Core runs at 50MHz (100MHz / 2)
    parameter BAUD_RATE  = 115200
)(
    input  wire CLK100MHZ,
    input  wire CPU_RESETN,    // Active-low reset button
    input  wire UART_TXD_IN,  // FTDI TX -> FPGA RX (data into FPGA)
    output wire UART_RXD_OUT, // FPGA TX -> FTDI RX (data out of FPGA)
    output wire LED0,          // UART TX busy indicator
    output wire LED1           // UART RX valid indicator
);

    // Active-high reset from active-low button
    wire rst_raw = ~CPU_RESETN;

    // Clock divider: 100MHz -> 50MHz
    reg clk_div = 0;
    always @(posedge CLK100MHZ)
        clk_div <= ~clk_div;

    wire clk = clk_div;
    wire rst = rst_raw;

    // =========================================================================
    // Core bus signals
    // =========================================================================
    wire [31:0] imem_addr, imem_data;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire        dmem_we, dmem_re;
    wire [2:0]  dmem_funct3;
    wire [31:0] debug_pc, debug_instr;

    // RAM bus (from bus decoder)
    wire [31:0] ram_addr, ram_wdata, ram_rdata;
    wire        ram_we, ram_re;
    wire [2:0]  ram_funct3;

    // UART signals
    wire [7:0]  uart_tx_data;
    wire        uart_tx_send;
    wire        uart_tx_busy;
    wire [7:0]  uart_rx_data;
    wire        uart_rx_valid;
    wire        uart_rx_clear;

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
    imem #(.DEPTH(IMEM_DEPTH), .INIT_FILE("/home/otacon/Projects/RISC-V_CPU/rv32i/sim/firmware.hex")) u_imem (
        .addr(imem_addr), .instr(imem_data)
    );


    // =========================================================================
    // Bus Decoder — routes data bus to RAM or UART
    // =========================================================================
    bus_decoder u_bus (
        .clk(clk), .rst(rst),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_we(dmem_we), .dmem_re(dmem_re),
        .dmem_funct3(dmem_funct3), .dmem_rdata(dmem_rdata),
        .ram_addr(ram_addr), .ram_wdata(ram_wdata),
        .ram_we(ram_we), .ram_re(ram_re),
        .ram_funct3(ram_funct3), .ram_rdata(ram_rdata),
        .uart_tx_data(uart_tx_data), .uart_tx_send(uart_tx_send),
        .uart_tx_busy(uart_tx_busy),
        .uart_rx_data(uart_rx_data), .uart_rx_valid(uart_rx_valid),
        .uart_rx_clear(uart_rx_clear)
    );

    // =========================================================================
    // Data Memory (RAM)
    // =========================================================================
    dmem #(.DEPTH(DMEM_DEPTH), .INIT_FILE("/home/otacon/Projects/RISC-V_CPU/rv32i/sim/dmem_init_word.hex")) u_dmem (
        .clk(clk),
        .mem_read(ram_re), .mem_write(ram_we),
        .funct3(ram_funct3),
        .addr(ram_addr), .write_data(ram_wdata),
        .read_data(ram_rdata)
    );

    // =========================================================================
    // UART
    // =========================================================================
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
