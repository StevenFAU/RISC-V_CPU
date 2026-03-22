// Testbench for UART Receiver
`timescale 1ns/1ps

module tb_uart_rx;

    parameter CLK_FREQ  = 1_000_000;
    parameter BAUD_RATE = 10_000;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE; // 100

    reg        clk, rst;
    reg        rx;
    wire [7:0] data;
    wire       valid;

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) uut (
        .clk(clk), .rst(rst),
        .rx(rx), .data(data), .valid(valid)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass = 0, fail = 0;

    // Task: send a serial byte on the rx line
    task send_serial_byte(input [7:0] byte_val);
        integer b;
        begin
            // Start bit
            rx = 1'b0;
            repeat (CLKS_PER_BIT) @(posedge clk);

            // 8 data bits, LSB first
            for (b = 0; b < 8; b = b + 1) begin
                rx = byte_val[b];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end

            // Stop bit
            rx = 1'b1;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    task test_byte(input [7:0] byte_val, input [8*16-1:0] msg);
        begin
            send_serial_byte(byte_val);

            // Wait a few cycles for valid pulse (synchronizer delay)
            repeat (5) @(posedge clk);

            if (data === byte_val) begin
                $display("PASS: %0s — RX 0x%02h", msg, data);
                pass = pass + 1;
            end else begin
                $display("FAIL: %0s — Expected 0x%02h, Got 0x%02h", msg, byte_val, data);
                fail = fail + 1;
            end
        end
    endtask

    // Monitor valid pulses
    reg valid_seen;
    always @(posedge clk) begin
        if (valid) valid_seen <= 1'b1;
    end

    initial begin
        $dumpfile("sim/tb_uart_rx.vcd");
        $dumpvars(0, tb_uart_rx);

        rst = 1; rx = 1'b1; valid_seen = 0;
        repeat (10) @(posedge clk);
        rst = 0;
        repeat (10) @(posedge clk);

        // Test multiple bytes
        test_byte(8'h48, "RX 'H'");
        test_byte(8'h69, "RX 'i'");
        test_byte(8'h21, "RX '!'");
        test_byte(8'h00, "RX 0x00");
        test_byte(8'hFF, "RX 0xFF");

        // Test glitch recovery: send a false start bit then go high
        $display("Testing glitch recovery...");
        rx = 1'b0;
        repeat (CLKS_PER_BIT / 4) @(posedge clk); // Short low pulse
        rx = 1'b1;
        repeat (CLKS_PER_BIT * 2) @(posedge clk); // Wait

        // Should still receive a valid byte after the glitch
        test_byte(8'hA5, "Post-glitch RX");

        $display("\n--- UART RX Tests: %0d passed, %0d failed ---", pass, fail);
        if (fail > 0) $display("*** SOME TESTS FAILED ***");
        else $display("*** ALL TESTS PASSED ***");
        $finish;
    end
endmodule
