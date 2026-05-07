// FPGA Top-Level Testbench — Phase 1.2.1 illegal_test asm program.
//
// End-to-end proof that the illegal-instruction trap path + the
// regfile_we side-effect gate work through the synthesized SoC.
// CSRRW to RO mvendorid pulses csr_illegal_i; the trap encoder fires
// (cause=2); the gate prevents the would-be regfile write to t4 from
// clobbering its 0xDEADBEEF sentinel; the handler verifies mepc /
// mcause / mtval / mstatus AND that t4 still holds the sentinel,
// then prints "PASS\r\n" over UART.
//
// Loads sim/illegal_test.hex (produced by `make asm PROG=illegal_test`)
// and the PASS/FAIL string DMEM image. Mirrors tb/tb_fpga_top_ecall.v.

`timescale 1ns/1ps

module tb_fpga_top_illegal;

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
        $readmemh("sim/illegal_test.hex", dut.u_imem.mem);

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
            $display("*** ILLEGAL_INST FPGA TEST PASSED -- sentinel x29 preserved through trap ***");
        else
            $display("*** ILLEGAL_INST FPGA TEST FAILED -- %0d mismatches ***", errors);

        $finish;
    end
endmodule
