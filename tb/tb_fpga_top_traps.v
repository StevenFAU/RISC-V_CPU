// FPGA Top-Level Testbench — Phase 1.2.4 traps_test C program.
//
// End-to-end proof of the C-level trap-dispatcher path through the
// synthesized SoC. Loads the IMEM (sw/traps_test.c + crt0 +
// trampoline) and DMEM (.rodata strings + .data + bss reservation)
// images produced by `make c-traps`, runs the program, and verifies
// the UART TX emits "PASS\r\n".
//
// What this exercises in one run (cause -> trigger):
//   0  inst_addr_misaligned   — JAL with imm[1]=1 (.word)
//   2  illegal_instruction    — CSRRW to RO mvendorid (.word)
//   3  breakpoint             — EBREAK
//   4  load_addr_misaligned   — LH at 0x00010001
//   5  load_access_fault      — LW from 0xF0000000
//   6  store_addr_misaligned  — SH at 0x00010025
//   7  store_access_fault     — SW to 0xF0000000
//  11  ecall_m                — ECALL
//
// Implicit MRET round-trip coverage (Decision 4 in PHASE1.2.4_HANDOFF.md):
// each cause's handler advances mepc by 4 and MRETs, so progressing
// from one trigger to the next requires MRET to work. Reaching the
// final UART output proves all eight MRETs succeeded.
//
// Mirrors tb/tb_fpga_top_c.v structure (the existing template for
// IMEM_INIT/DMEM_INIT C-program tests). IMEM depth is 1024 words
// (4 KB) — traps_test.elf .text is ~1.7 KB, fits comfortably and
// keeps simulation fast.

`timescale 1ns/1ps

module tb_fpga_top_traps;

    // Fast baud for simulation. CLK_FREQ is the core clock (after /2
    // divider); tb samples on the external 2x clock, hence the *2 in
    // CLKS_PER_BIT.
    parameter CLK_FREQ  = 1_000_000;
    parameter BAUD_RATE = 10_000;
    localparam CLKS_PER_BIT = (CLK_FREQ / BAUD_RATE) * 2;

    reg  clk, resetn;
    wire uart_tx_out;
    wire [15:0] led;

    fpga_top #(
        .IMEM_DEPTH(1024),
        .DMEM_DEPTH(4096),
        .IMEM_INIT("sim/traps_test.hex"),
        .DMEM_INIT("sim/traps_test_dmem.hex"),
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
    // UART RX decoder — captures TX output
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
    //
    // On FAIL, traps_test.c emits "FAIL\r\n" first, then a per-cause
    // dump. We capture exactly 6 bytes; mismatch routes to the FAILED
    // banner and the dump (visible in the RX log above) tells the
    // user which cause(s) failed.
    // =========================================================================
    localparam integer EXPECTED_LEN = 6;
    reg [7:0] expected [0:EXPECTED_LEN-1];
    initial begin
        expected[0] = "P";
        expected[1] = "A";
        expected[2] = "S";
        expected[3] = "S";
        expected[4] = 8'h0D; // \r
        expected[5] = 8'h0A; // \n
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
            $display("*** TRAPS TEST PASSED -- \"PASS\\r\\n\" received correctly ***");
        else
            $display("*** TRAPS TEST FAILED -- %0d mismatches ***", errors);

        $finish;
    end
endmodule
