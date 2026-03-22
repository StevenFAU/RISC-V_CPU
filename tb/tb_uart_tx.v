// Testbench for UART Transmitter
// Uses fast baud rate (CLK_FREQ/BAUD_RATE ratio) for quick simulation
`timescale 1ns/1ps

module tb_uart_tx;

    // Use smaller ratio for fast simulation: 100 clocks per bit
    parameter CLK_FREQ  = 1_000_000;
    parameter BAUD_RATE = 10_000;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE; // 100

    reg        clk, rst;
    reg  [7:0] data;
    reg        send;
    wire       tx, busy;

    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) uut (
        .clk(clk), .rst(rst),
        .data(data), .send(send),
        .tx(tx), .busy(busy)
    );

    initial clk = 0;
    always #5 clk = ~clk; // 100MHz sim clock (period irrelevant, baud counter drives timing)

    integer pass = 0, fail = 0;
    integer i;
    reg [7:0] captured_byte;

    // Task: capture one transmitted byte by sampling tx at mid-bit
    task capture_byte;
        output [7:0] result;
        integer b;
        begin
            // Wait for start bit (tx goes low)
            wait (tx == 1'b0);

            // Verify start bit — wait to mid-bit
            repeat (CLKS_PER_BIT / 2) @(posedge clk);
            if (tx !== 1'b0) begin
                $display("FAIL: Start bit not low at midpoint");
                fail = fail + 1;
            end

            // Sample 8 data bits at mid-bit
            for (b = 0; b < 8; b = b + 1) begin
                repeat (CLKS_PER_BIT) @(posedge clk);
                result[b] = tx; // LSB first
            end

            // Check stop bit
            repeat (CLKS_PER_BIT) @(posedge clk);
            if (tx !== 1'b1) begin
                $display("FAIL: Stop bit not high");
                fail = fail + 1;
            end

            // Wait for stop bit to complete
            repeat (CLKS_PER_BIT / 2) @(posedge clk);
        end
    endtask

    task send_and_verify(input [7:0] byte_val, input [8*16-1:0] msg);
        begin
            // Send byte
            @(posedge clk);
            data = byte_val;
            send = 1;
            @(posedge clk);
            send = 0;

            if (!busy) begin
                $display("FAIL: %0s — busy not asserted", msg);
                fail = fail + 1;
            end

            // Capture transmitted byte
            capture_byte(captured_byte);

            if (captured_byte === byte_val) begin
                $display("PASS: %0s — TX 0x%02h", msg, captured_byte);
                pass = pass + 1;
            end else begin
                $display("FAIL: %0s — Expected 0x%02h, Got 0x%02h", msg, byte_val, captured_byte);
                fail = fail + 1;
            end

            // Wait for busy to drop
            wait (!busy);
        end
    endtask

    initial begin
        $dumpfile("sim/tb_uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);

        rst = 1; send = 0; data = 0;
        repeat (5) @(posedge clk);
        rst = 0;
        repeat (5) @(posedge clk);

        // Verify idle state
        if (tx !== 1'b1) begin
            $display("FAIL: TX should idle high");
            fail = fail + 1;
        end else begin
            $display("PASS: TX idles high");
            pass = pass + 1;
        end

        // Send test bytes
        send_and_verify(8'h48, "Send 'H'");
        send_and_verify(8'h69, "Send 'i'");
        send_and_verify(8'h21, "Send '!'");
        send_and_verify(8'h00, "Send 0x00");
        send_and_verify(8'hFF, "Send 0xFF");
        send_and_verify(8'h55, "Send 0x55");
        send_and_verify(8'hAA, "Send 0xAA");

        $display("\n--- UART TX Tests: %0d passed, %0d failed ---", pass, fail);
        if (fail > 0) $display("*** SOME TESTS FAILED ***");
        else $display("*** ALL TESTS PASSED ***");
        $finish;
    end
endmodule
