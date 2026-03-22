// UART Loopback Test — TX output feeds RX input
`timescale 1ns/1ps

module tb_uart_loopback;

    parameter CLK_FREQ  = 1_000_000;
    parameter BAUD_RATE = 10_000;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    reg        clk, rst;
    reg  [7:0] tx_data;
    reg        tx_send;
    wire       tx_line, tx_busy;
    wire [7:0] rx_data;
    wire       rx_valid;

    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_tx (
        .clk(clk), .rst(rst),
        .data(tx_data), .send(tx_send),
        .tx(tx_line), .busy(tx_busy)
    );

    // Loopback: TX output drives RX input
    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_rx (
        .clk(clk), .rst(rst),
        .rx(tx_line),
        .data(rx_data), .valid(rx_valid)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass = 0, fail = 0;
    integer total_sent = 0;

    // Test data: various patterns
    reg [7:0] test_bytes [0:23];
    initial begin
        test_bytes[0]  = 8'h00;
        test_bytes[1]  = 8'hFF;
        test_bytes[2]  = 8'h55;
        test_bytes[3]  = 8'hAA;
        test_bytes[4]  = 8'h48; // H
        test_bytes[5]  = 8'h65; // e
        test_bytes[6]  = 8'h6C; // l
        test_bytes[7]  = 8'h6C; // l
        test_bytes[8]  = 8'h6F; // o
        test_bytes[9]  = 8'h2C; // ,
        test_bytes[10] = 8'h20; // (space)
        test_bytes[11] = 8'h52; // R
        test_bytes[12] = 8'h49; // I
        test_bytes[13] = 8'h53; // S
        test_bytes[14] = 8'h43; // C
        test_bytes[15] = 8'h2D; // -
        test_bytes[16] = 8'h56; // V
        test_bytes[17] = 8'h21; // !
        test_bytes[18] = 8'h0A; // \n
        test_bytes[19] = 8'h01;
        test_bytes[20] = 8'h80;
        test_bytes[21] = 8'h7F;
        test_bytes[22] = 8'hFE;
        test_bytes[23] = 8'h42;
    end

    // Receive side — check each received byte
    reg [7:0] expected_byte;
    integer rx_count;
    initial rx_count = 0;

    always @(posedge clk) begin
        if (rx_valid) begin
            expected_byte = test_bytes[rx_count];
            if (rx_data === expected_byte) begin
                $display("PASS: Byte %0d — TX 0x%02h, RX 0x%02h", rx_count, expected_byte, rx_data);
                pass = pass + 1;
            end else begin
                $display("FAIL: Byte %0d — TX 0x%02h, RX 0x%02h", rx_count, expected_byte, rx_data);
                fail = fail + 1;
            end
            rx_count = rx_count + 1;
        end
    end

    integer idx;
    initial begin
        $dumpfile("sim/tb_uart_loopback.vcd");
        $dumpvars(0, tb_uart_loopback);

        rst = 1; tx_send = 0; tx_data = 0;
        repeat (10) @(posedge clk);
        rst = 0;
        repeat (10) @(posedge clk);

        // Send all 24 test bytes back-to-back
        for (idx = 0; idx < 24; idx = idx + 1) begin
            // Wait for TX not busy
            wait (!tx_busy);
            @(posedge clk);
            tx_data = test_bytes[idx];
            tx_send = 1;
            @(posedge clk);
            tx_send = 0;
            total_sent = total_sent + 1;
        end

        // Wait for last byte to be received
        wait (!tx_busy);
        repeat (CLKS_PER_BIT * 5) @(posedge clk);

        $display("\n--- UART Loopback: %0d sent, %0d received, %0d passed, %0d failed ---",
                 total_sent, rx_count, pass, fail);
        if (fail > 0 || rx_count != total_sent)
            $display("*** SOME TESTS FAILED ***");
        else
            $display("*** ALL TESTS PASSED ***");
        $finish;
    end
endmodule
