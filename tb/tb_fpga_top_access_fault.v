// FPGA Top-Level Testbench — Phase 1.2.2 access_fault_test asm program.
//
// End-to-end proof that the load_access_fault at-issue trap path works
// through the synthesized SoC. The asm program issues an LW from
// 0xF0000000 (an address outside every wb_interconnect slave window).
// wb_interconnect's bus_error_o pulses combinationally on the same
// cycle; the at-issue source composition catches it before regfile_we
// latches; the trap encoder fires (cause=5, mtval=0xF0000000); the
// handler verifies state and confirms the regfile destination kept its
// pre-trap sentinel, then prints "PASS\r\n" over UART.
//
// This testbench is also implicit verification that the pre-issue/at-
// issue gate split correctly broke the bus_error_i -> dmem_re ->
// bus_error_i combinational cycle. If the loop-break failed,
// bus_error_o would never assert (or simulation would oscillate) and
// no PASS would print.
//
// Loads sim/access_fault_test.hex (`make asm PROG=access_fault_test`).

`timescale 1ns/1ps

module tb_fpga_top_access_fault;

    parameter CLK_FREQ  = 1_000_000;
    parameter BAUD_RATE = 10_000;
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

    reg [7:0] expected [0:5];
    initial begin
        expected[0] = "P";
        expected[1] = "A";
        expected[2] = "S";
        expected[3] = "S";
        expected[4] = 8'h0D;
        expected[5] = 8'h0A;
    end

    integer i, pass, errors;

    initial begin
        $readmemh("sim/access_fault_test.hex", dut.u_imem.mem);

        dut.u_wb_dmem.u_dmem.mem[0] = 32'h53534150;
        dut.u_wb_dmem.u_dmem.mem[1] = 32'h00000A0D;
        dut.u_wb_dmem.u_dmem.mem[2] = 32'h4C494146;
        dut.u_wb_dmem.u_dmem.mem[3] = 32'h00000A0D;

        resetn = 0;
        repeat (10) @(posedge clk);
        resetn = 1;

        $display("--- Capturing UART output ---");

        for (i = 0; i < 6; i = i + 1)
            capture_uart_byte;

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
            $display("*** ACCESS_FAULT FPGA TEST PASSED -- LW-unmapped cause-5 trap verified ***");
        else
            $display("*** ACCESS_FAULT FPGA TEST FAILED -- %0d mismatches ***", errors);

        $finish;
    end
endmodule
