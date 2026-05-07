// FPGA Top-Level Testbench — Phase 1.1 csr_test asm program.
//
// End-to-end proof that CSR instructions (CSRRW + CSRRS in this case) work
// in the synthesized memory map: BRAM-backed IMEM → core → csr_file →
// writeback path → Wishbone DMEM read for the .data string → UART TX.
//
// Loads sim/csr_test.hex (produced by `make asm PROG=csr_test`) and the
// hand-built PASS/FAIL string DMEM image, captures UART TX, verifies the
// expected output is "PASS\r\n" — i.e., the program wrote 0x12345678 to
// mscratch via CSRRW, read it back via CSRRS, and the readback matched.
//
// Mirrors tb/tb_fpga_top_asm.v's structure (the Phase 0.2 hello.S harness)
// since the dual-purpose tb_fpga_top_asm.v expects a specific string.
// Duplicate-and-rename pattern matches Phase 0.2's tb_fpga_top_c.v split.

`timescale 1ns/1ps

module tb_fpga_top_csr;

    // Use fast baud for simulation (matches tb_fpga_top_asm.v).
    parameter CLK_FREQ  = 1_000_000;
    parameter BAUD_RATE = 10_000;
    // Testbench samples on external clock (2x core clock), so double the count.
    localparam CLKS_PER_BIT = (CLK_FREQ / BAUD_RATE) * 2;

    reg  clk, resetn;
    wire uart_tx_out;
    wire [15:0] led;

    fpga_top #(
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .IMEM_INIT(""),
        .DMEM_INIT(""),
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .CLK100MHZ(clk),
        .CPU_RESETN(resetn),
        .UART_TXD_IN(1'b1),
        .UART_RXD_OUT(uart_tx_out),
        .LED(led),
        .SW(16'd0)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================================
    // UART RX decoder — captures TX output and builds received string
    // =========================================================================
    reg [7:0] rx_buffer [0:31];
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
    // Expected string: "PASS\r\n"
    // =========================================================================
    reg [7:0] expected [0:5];
    initial begin
        expected[0] = "P";
        expected[1] = "A";
        expected[2] = "S";
        expected[3] = "S";
        expected[4] = 8'h0D;  // \r
        expected[5] = 8'h0A;  // \n
    end

    // =========================================================================
    // Main test
    // =========================================================================
    integer i, pass, errors;

    initial begin
        // Load firmware (csr_test.hex) into IMEM.
        $readmemh("sim/csr_test.hex", dut.u_imem.mem);

        // Load PASS / FAIL strings into DMEM (wb_dmem strips upper address bits).
        // Layout matches sw/csr_test.S .data section:
        //   word 0 = "PASS"      -> 0x53534150 (little-endian)
        //   word 1 = "\r\n\0\0"  -> 0x00000A0D
        //   word 2 = "FAIL"      -> 0x4C494146
        //   word 3 = "\r\n\0\0"  -> 0x00000A0D
        dut.u_wb_dmem.u_dmem.mem[0] = 32'h53534150;
        dut.u_wb_dmem.u_dmem.mem[1] = 32'h00000A0D;
        dut.u_wb_dmem.u_dmem.mem[2] = 32'h4C494146;
        dut.u_wb_dmem.u_dmem.mem[3] = 32'h00000A0D;

        // Reset
        resetn = 0;
        repeat (10) @(posedge clk);
        resetn = 1;

        $display("--- Capturing UART output ---");

        // Capture 6 bytes (length of "PASS\r\n" or "FAIL\r\n")
        for (i = 0; i < 6; i = i + 1)
            capture_uart_byte;

        // Verify
        $display("\n--- Verification ---");
        pass = 0; errors = 0;
        for (i = 0; i < 6; i = i + 1) begin
            if (rx_buffer[i] === expected[i]) begin
                pass = pass + 1;
            end else begin
                $display("MISMATCH at byte %0d: expected 0x%02h, got 0x%02h",
                         i, expected[i], rx_buffer[i]);
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("*** CSR FPGA TEST PASSED -- \"PASS\\r\\n\" received correctly ***");
        else
            $display("*** CSR FPGA TEST FAILED -- %0d mismatches ***", errors);

        $finish;
    end
endmodule
