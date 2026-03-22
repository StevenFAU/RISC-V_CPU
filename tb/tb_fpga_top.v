// FPGA Top-Level Testbench
// Loads hello firmware, captures UART TX output, verifies "Hello, RISC-V!\n"
`timescale 1ns/1ps

module tb_fpga_top;

    // Use fast baud for simulation
    parameter CLK_FREQ  = 1_000_000;
    parameter BAUD_RATE = 10_000;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    reg  clk, resetn;
    wire uart_tx_out;

    fpga_top #(
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .CLK100MHZ(clk),
        .CPU_RESETN(resetn),
        .UART_TXD_IN(1'b1),     // RX idle high (not used in this test)
        .UART_RXD_OUT(uart_tx_out),
        .LED0(),
        .LED1()
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================================
    // UART RX decoder — captures TX output and builds received string
    // =========================================================================
    reg [7:0] rx_buffer [0:63];
    integer   rx_count;
    reg [7:0] rx_byte;
    integer   b;

    initial rx_count = 0;

    task capture_uart_byte;
        begin
            // Wait for start bit
            wait (uart_tx_out == 1'b0);
            // Wait to mid-bit of start bit
            repeat (CLKS_PER_BIT / 2) @(posedge clk);

            // Sample 8 data bits at mid-bit
            for (b = 0; b < 8; b = b + 1) begin
                repeat (CLKS_PER_BIT) @(posedge clk);
                rx_byte[b] = uart_tx_out;
            end

            // Wait through stop bit
            repeat (CLKS_PER_BIT) @(posedge clk);

            rx_buffer[rx_count] = rx_byte;
            $display("  RX[%0d]: 0x%02h '%c'", rx_count, rx_byte,
                     (rx_byte >= 8'h20 && rx_byte < 8'h7F) ? rx_byte : 8'h2E);
            rx_count = rx_count + 1;
        end
    endtask

    // =========================================================================
    // Expected string
    // =========================================================================
    reg [8*20-1:0] expected_str;
    integer expected_len;
    initial begin
        expected_str = "Hello, RISC-V!\n";
        expected_len = 15;
    end

    // Expected bytes (easier to compare)
    reg [7:0] expected [0:15];
    initial begin
        expected[0]  = "H";
        expected[1]  = "e";
        expected[2]  = "l";
        expected[3]  = "l";
        expected[4]  = "o";
        expected[5]  = ",";
        expected[6]  = " ";
        expected[7]  = "R";
        expected[8]  = "I";
        expected[9]  = "S";
        expected[10] = "C";
        expected[11] = "-";
        expected[12] = "V";
        expected[13] = "!";
        expected[14] = 8'h0A; // \n
    end

    // =========================================================================
    // Main test
    // =========================================================================
    integer i, pass, errors;

    initial begin
        // Skip VCD dump — large memory arrays make it impractical

        // Load firmware into IMEM (word-addressed hex) and DMEM (string data)
        $readmemh("sim/firmware.hex", dut.u_imem.mem);
        // Load string data into DMEM at offset 0 (bus decoder strips base address)
        // DMEM is now word-based: mem[0] = {byte3, byte2, byte1, byte0}
        dut.u_dmem.mem[0] = 32'h6C6C6548; // "Hell" little-endian
        dut.u_dmem.mem[1] = 32'h52202C6F; // "o, R" little-endian
        dut.u_dmem.mem[2] = 32'h2D435349; // "ISC-" little-endian
        dut.u_dmem.mem[3] = 32'h000A2156; // "V!\n\0" little-endian

        // Reset
        resetn = 0;
        repeat (10) @(posedge clk);
        resetn = 1;

        $display("--- Capturing UART output ---");

        // Capture 15 bytes (length of "Hello, RISC-V!\n")
        for (i = 0; i < 15; i = i + 1)
            capture_uart_byte;

        // Verify
        $display("\n--- Verification ---");
        pass = 0; errors = 0;
        for (i = 0; i < 15; i = i + 1) begin
            if (rx_buffer[i] === expected[i]) begin
                pass = pass + 1;
            end else begin
                $display("MISMATCH at byte %0d: expected 0x%02h, got 0x%02h", i, expected[i], rx_buffer[i]);
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("*** FPGA TOP TEST PASSED — \"Hello, RISC-V!\\n\" received correctly ***");
        else
            $display("*** FPGA TOP TEST FAILED — %0d mismatches ***", errors);

        $finish;
    end
endmodule
