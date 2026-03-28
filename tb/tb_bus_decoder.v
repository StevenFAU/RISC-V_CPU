// Testbench for Bus Decoder
// Verifies address routing between RAM and UART
`timescale 1ns/1ps

module tb_bus_decoder;

    parameter CLK_FREQ  = 1_000_000;
    parameter BAUD_RATE = 10_000;

    reg        clk, rst;

    // Core bus signals (stimulus)
    reg  [31:0] dmem_addr, dmem_wdata;
    reg         dmem_we, dmem_re;
    reg  [2:0]  dmem_funct3;
    wire [31:0] dmem_rdata;

    // RAM signals
    wire [31:0] ram_addr, ram_wdata, ram_rdata;
    wire        ram_we, ram_re;
    wire [2:0]  ram_funct3;

    // UART signals
    wire [7:0]  uart_tx_data;
    wire        uart_tx_send, uart_tx_busy;
    wire [7:0]  uart_rx_data;
    wire        uart_rx_valid, uart_rx_clear;

    // UART TX/RX for loopback
    wire tx_line;

    bus_decoder uut (
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

    // Actual RAM for testing
    dmem #(.DEPTH(256)) u_ram (
        .clk(clk),
        .mem_read(ram_re), .mem_write(ram_we),
        .funct3(ram_funct3),
        .addr(ram_addr), .write_data(ram_wdata),
        .read_data(ram_rdata)
    );

    // Actual UART for testing
    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_tx (
        .clk(clk), .rst(rst),
        .data(uart_tx_data), .send(uart_tx_send),
        .tx(tx_line), .busy(uart_tx_busy)
    );

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_rx (
        .clk(clk), .rst(rst),
        .rx(tx_line),
        .data(uart_rx_data), .valid(uart_rx_valid)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass = 0, fail = 0;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    initial begin
        $dumpfile("sim/tb_bus_decoder.vcd");
        $dumpvars(0, tb_bus_decoder);

        rst = 1; dmem_addr = 0; dmem_wdata = 0; dmem_we = 0; dmem_re = 0; dmem_funct3 = 3'b010;
        repeat (10) @(posedge clk);
        rst = 0;
        repeat (5) @(posedge clk);

        // ===== Test 1: RAM write and read (DMEM range) =====
        // Write 0xCAFEBABE to RAM address 0x00010000
        dmem_addr = 32'h0001_0000; dmem_wdata = 32'hCAFEBABE;
        dmem_we = 1; dmem_funct3 = 3'b010; // SW
        @(posedge clk); #1;
        dmem_we = 0;
        @(posedge clk);

        // Read it back
        dmem_re = 1; dmem_addr = 32'h0001_0000; dmem_funct3 = 3'b010; // LW
        @(posedge clk); #1;
        if (dmem_rdata === 32'hCAFEBABE) begin
            $display("PASS: RAM write/read 0xCAFEBABE at DMEM base"); pass = pass + 1;
        end else begin
            $display("FAIL: RAM read — expected 0xCAFEBABE, got 0x%08h", dmem_rdata); fail = fail + 1;
        end
        dmem_re = 0;
        @(posedge clk);

        // ===== Test 1b: Unmapped write — RAM we stays low =====
        dmem_addr = 32'h0002_0000; dmem_wdata = 32'hDEAD_DEAD;
        dmem_we = 1; dmem_funct3 = 3'b010;
        @(posedge clk); #1;
        if (ram_we === 1'b0) begin
            $display("PASS: Unmapped write (0x00020000) does not hit RAM"); pass = pass + 1;
        end else begin
            $display("FAIL: Unmapped write leaked to RAM"); fail = fail + 1;
        end
        dmem_we = 0;
        @(posedge clk);

        // ===== Test 1c: Unmapped read — returns 0 =====
        dmem_addr = 32'h0002_0000; dmem_re = 1; dmem_funct3 = 3'b010;
        @(posedge clk); #1;
        if (dmem_rdata === 32'd0) begin
            $display("PASS: Unmapped read (0x00020000) returns 0"); pass = pass + 1;
        end else begin
            $display("FAIL: Unmapped read — expected 0, got 0x%08h", dmem_rdata); fail = fail + 1;
        end
        dmem_re = 0;
        @(posedge clk);

        // ===== Test 2: RAM signals don't fire for UART address =====
        // Use UART status address (read-only) to check routing without triggering TX
        dmem_addr = 32'h8000_0004; dmem_wdata = 32'h42; dmem_we = 1;
        @(posedge clk); #1;
        if (ram_we === 1'b0) begin
            $display("PASS: UART write does not hit RAM"); pass = pass + 1;
        end else begin
            $display("FAIL: UART write leaked to RAM"); fail = fail + 1;
        end
        dmem_we = 0;
        @(posedge clk);

        // ===== Test 3: UART TX send pulse =====
        dmem_addr = 32'h8000_0000; dmem_wdata = 32'h48; // 'H'
        dmem_we = 1; dmem_funct3 = 3'b010;
        @(posedge clk); #1;
        if (uart_tx_send === 1'b1 && uart_tx_data === 8'h48) begin
            $display("PASS: UART TX send pulse with data 0x48"); pass = pass + 1;
        end else begin
            $display("FAIL: UART TX send=%b data=0x%02h", uart_tx_send, uart_tx_data); fail = fail + 1;
        end
        dmem_we = 0;
        @(posedge clk);

        // ===== Test 4: UART TX status (busy) =====
        dmem_addr = 32'h8000_0004; dmem_re = 1; dmem_funct3 = 3'b010;
        @(posedge clk); #1;
        if (dmem_rdata[0] === 1'b1) begin
            $display("PASS: UART TX status shows busy"); pass = pass + 1;
        end else begin
            $display("FAIL: UART TX status — expected busy=1, got 0x%08h", dmem_rdata); fail = fail + 1;
        end
        dmem_re = 0;

        // Wait for TX to finish
        wait (!uart_tx_busy);
        repeat (5) @(posedge clk);

        // Check not busy
        dmem_addr = 32'h8000_0004; dmem_re = 1;
        @(posedge clk); #1;
        if (dmem_rdata[0] === 1'b0) begin
            $display("PASS: UART TX status shows not busy after completion"); pass = pass + 1;
        end else begin
            $display("FAIL: UART TX still busy after completion"); fail = fail + 1;
        end
        dmem_re = 0;

        // ===== Test 5: UART RX via loopback =====
        // The byte we sent ('H') should have arrived at RX via loopback
        // Need to wait for full byte transmission + synchronizer delay + RX processing
        // 10 bits (start + 8 data + stop) + generous margin for synchronizer
        repeat (CLKS_PER_BIT * 15) @(posedge clk);

        // Read RX status
        dmem_addr = 32'h8000_000C; dmem_re = 1;
        @(posedge clk); #1;
        if (dmem_rdata[0] === 1'b1) begin
            $display("PASS: UART RX status shows valid"); pass = pass + 1;
        end else begin
            $display("FAIL: UART RX status — expected valid=1, got 0x%08h", dmem_rdata); fail = fail + 1;
        end
        dmem_re = 0;
        @(posedge clk);

        // Read RX data
        dmem_addr = 32'h8000_0008; dmem_re = 1;
        @(posedge clk); #1;
        if (dmem_rdata[7:0] === 8'h48) begin
            $display("PASS: UART RX data = 0x48 ('H')"); pass = pass + 1;
        end else begin
            $display("FAIL: UART RX data — expected 0x48, got 0x%02h", dmem_rdata[7:0]); fail = fail + 1;
        end
        dmem_re = 0;
        @(posedge clk);

        // Read RX status again — should be cleared after reading status
        dmem_addr = 32'h8000_000C; dmem_re = 1;
        @(posedge clk); #1;
        if (dmem_rdata[0] === 1'b0) begin
            $display("PASS: UART RX valid cleared after status read"); pass = pass + 1;
        end else begin
            $display("FAIL: UART RX valid not cleared"); fail = fail + 1;
        end
        dmem_re = 0;

        $display("\n--- Bus Decoder Tests: %0d passed, %0d failed ---", pass, fail);
        if (fail > 0) $display("*** SOME TESTS FAILED ***");
        else $display("*** ALL TESTS PASSED ***");
        $finish;
    end
endmodule
