// Testbench — wb_uart
// Verifies UART TX/RX through Wishbone slave interface with loopback.
`timescale 1ns / 1ps

module tb_wb_uart;

    parameter CLK_FREQ  = 1_000_000;
    parameter BAUD_RATE = 10_000;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    reg        clk, rst;
    reg        wb_cyc, wb_stb, wb_we;
    reg [31:0] wb_adr, wb_dat;
    reg [3:0]  wb_sel;
    wire [31:0] wb_dat_o;
    wire        wb_ack;

    wire uart_tx_pin, uart_rx_pin;

    // Loopback: TX output feeds back to RX input
    assign uart_rx_pin = uart_tx_pin;

    integer pass = 0, fail = 0;

    wb_uart #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) uut (
        .clk(clk), .rst(rst),
        .wb_cyc_i(wb_cyc), .wb_stb_i(wb_stb), .wb_we_i(wb_we),
        .wb_adr_i(wb_adr), .wb_dat_i(wb_dat), .wb_sel_i(wb_sel),
        .wb_dat_o(wb_dat_o), .wb_ack_o(wb_ack),
        .uart_tx(uart_tx_pin),
        .uart_rx(uart_rx_pin)
    );

    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz sim clock (CLK_FREQ is for baud calc)

    // Helper: Wishbone write
    task wb_write;
        input [31:0] addr;
        input [31:0] data;
    begin
        @(posedge clk);
        wb_cyc = 1; wb_stb = 1; wb_we = 1;
        wb_adr = addr; wb_dat = data; wb_sel = 4'b1111;
        @(posedge clk);
        wb_cyc = 0; wb_stb = 0; wb_we = 0;
    end
    endtask

    // Helper: Wishbone read
    task wb_read;
        input [31:0] addr;
        output [31:0] data;
    begin
        @(posedge clk);
        wb_cyc = 1; wb_stb = 1; wb_we = 0;
        wb_adr = addr; wb_sel = 4'b1111;
        #1;
        data = wb_dat_o;
        @(posedge clk);
        wb_cyc = 0; wb_stb = 0;
    end
    endtask

    reg [31:0] rdata;

    initial begin
        $dumpfile("sim/tb_wb_uart.vcd");
        $dumpvars(0, tb_wb_uart);

        rst = 1; wb_cyc = 0; wb_stb = 0; wb_we = 0;
        wb_adr = 0; wb_dat = 0; wb_sel = 0;
        repeat (10) @(posedge clk);
        rst = 0;
        repeat (5) @(posedge clk);

        // === Test 1: Write TX data (send 'H') ===
        wb_write(32'h8000_0000, 32'h48);
        #1;

        // === Test 2: Read TX status — should be busy ===
        wb_read(32'h8000_0004, rdata);
        if (rdata[0] === 1'b1) begin
            $display("PASS: TX status shows busy"); pass = pass + 1;
        end else begin
            $display("FAIL: TX status — expected busy, got 0x%08h", rdata); fail = fail + 1;
        end

        // Wait for TX to finish
        wait (!uut.tx_busy);
        repeat (5) @(posedge clk);

        // === Test 3: TX not busy after completion ===
        wb_read(32'h8000_0004, rdata);
        if (rdata[0] === 1'b0) begin
            $display("PASS: TX not busy after completion"); pass = pass + 1;
        end else begin
            $display("FAIL: TX still busy"); fail = fail + 1;
        end

        // === Test 4: Wait for RX loopback ===
        // Need to wait for full byte transmission + RX processing + synchronizer
        repeat (CLKS_PER_BIT * 15) @(posedge clk);

        // === Test 5: RX status shows valid ===
        wb_read(32'h8000_000C, rdata);
        if (rdata[0] === 1'b1) begin
            $display("PASS: RX status shows valid"); pass = pass + 1;
        end else begin
            $display("FAIL: RX status — expected valid, got 0x%08h", rdata); fail = fail + 1;
        end

        // === Test 6: RX data matches sent byte ===
        wb_read(32'h8000_0008, rdata);
        if (rdata[7:0] === 8'h48) begin
            $display("PASS: RX data = 0x48 ('H')"); pass = pass + 1;
        end else begin
            $display("FAIL: RX data — expected 0x48, got 0x%02h", rdata[7:0]); fail = fail + 1;
        end

        // === Test 7: RX valid cleared after status read ===
        // The first read of 0xC set rx_clear, which takes effect next cycle
        repeat (2) @(posedge clk);
        wb_read(32'h8000_000C, rdata);
        if (rdata[0] === 1'b0) begin
            $display("PASS: RX valid cleared after status read"); pass = pass + 1;
        end else begin
            $display("FAIL: RX valid not cleared"); fail = fail + 1;
        end

        // === Test 8: Ack asserts on valid transaction ===
        wb_cyc = 1; wb_stb = 1; wb_we = 0;
        wb_adr = 32'h8000_0004; wb_sel = 4'b1111;
        #1;
        if (wb_ack === 1'b1) begin
            $display("PASS: Ack on valid WB transaction"); pass = pass + 1;
        end else begin
            $display("FAIL: No ack on valid WB transaction"); fail = fail + 1;
        end
        wb_cyc = 0; wb_stb = 0;

        #100;
        $display("\n=== wb_uart: %0d passed, %0d failed ===", pass, fail);
        if (fail > 0) $display("SOME TESTS FAILED");
        else          $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
