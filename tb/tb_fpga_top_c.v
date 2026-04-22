// FPGA Top-Level Testbench — C "Hello from C!" path.
//
// Loads sim/hello_c.hex (IMEM) + sim/hello_c_dmem.hex (DMEM), produced by
// `make c PROG=hello_c`. Captures UART TX output and verifies that newlib-
// nano's printf emits exactly "Hello from C!\n".
//
// Driven by `make sim-fpga-c`. The assembly analogue is tb_fpga_top_asm.v.
`timescale 1ns/1ps

module tb_fpga_top_c;

    // Fast baud for simulation. CLK_FREQ is the core clock (after /2
    // divider); tb samples on the external 2x clock, hence the *2 in
    // CLKS_PER_BIT.
    parameter CLK_FREQ  = 1_000_000;
    parameter BAUD_RATE = 10_000;
    localparam CLKS_PER_BIT = (CLK_FREQ / BAUD_RATE) * 2;

    reg  clk, resetn;
    wire uart_tx_out;
    wire [15:0] led;

    // IMEM depth must be large enough to hold newlib-nano's printf
    // (~8-10 KB of .text). Match the synthesized size of 16K words.
    fpga_top #(
        .IMEM_DEPTH(16384),
        .DMEM_DEPTH(4096),
        .IMEM_INIT("sim/hello_c.hex"),
        .DMEM_INIT("sim/hello_c_dmem.hex"),
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .CLK100MHZ(clk),
        .CPU_RESETN(resetn),
        .UART_TXD_IN(1'b1),     // RX idle high (not used in this test)
        .UART_RXD_OUT(uart_tx_out),
        .LED(led),
        .SW(16'd0)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================================
    // UART RX decoder — captures TX output
    // =========================================================================
    reg [7:0] rx_buffer [0:63];
    integer   rx_count;
    reg [7:0] rx_byte;
    integer   b;

    initial rx_count = 0;

    task capture_uart_byte;
        begin
            wait (uart_tx_out == 1'b0);
            repeat (CLKS_PER_BIT / 2) @(posedge clk);
            for (b = 0; b < 8; b = b + 1) begin
                repeat (CLKS_PER_BIT) @(posedge clk);
                rx_byte[b] = uart_tx_out;
            end
            repeat (CLKS_PER_BIT) @(posedge clk);
            rx_buffer[rx_count] = rx_byte;
            $display("  RX[%0d]: 0x%02h '%c'", rx_count, rx_byte,
                     (rx_byte >= 8'h20 && rx_byte < 8'h7F) ? rx_byte : 8'h2E);
            rx_count = rx_count + 1;
        end
    endtask

    // =========================================================================
    // Expected string: "Hello from C!\n"  (14 bytes; printf emits just \n)
    // =========================================================================
    localparam integer EXPECTED_LEN = 14;
    reg [7:0] expected [0:EXPECTED_LEN-1];
    initial begin
        expected[0]  = "H";
        expected[1]  = "e";
        expected[2]  = "l";
        expected[3]  = "l";
        expected[4]  = "o";
        expected[5]  = " ";
        expected[6]  = "f";
        expected[7]  = "r";
        expected[8]  = "o";
        expected[9]  = "m";
        expected[10] = " ";
        expected[11] = "C";
        expected[12] = "!";
        expected[13] = 8'h0A; // \n
    end

    // =========================================================================
    // Main test
    // =========================================================================
    integer i, pass, errors;

    initial begin
        resetn = 0;
        repeat (10) @(posedge clk);
        resetn = 1;

        $display("--- Capturing UART output ---");

        for (i = 0; i < EXPECTED_LEN; i = i + 1)
            capture_uart_byte;

        $display("\n--- Verification ---");
        pass = 0; errors = 0;
        for (i = 0; i < EXPECTED_LEN; i = i + 1) begin
            if (rx_buffer[i] === expected[i]) begin
                pass = pass + 1;
            end else begin
                $display("MISMATCH at byte %0d: expected 0x%02h, got 0x%02h",
                         i, expected[i], rx_buffer[i]);
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("*** FPGA TOP C TEST PASSED — \"Hello from C!\\n\" received correctly ***");
        else
            $display("*** FPGA TOP C TEST FAILED — %0d mismatches ***", errors);

        $finish;
    end
endmodule
