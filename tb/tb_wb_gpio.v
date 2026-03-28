// Testbench — wb_gpio
// Verifies output register write/readback and input register reads.
`timescale 1ns / 1ps

module tb_wb_gpio;

    reg        clk, rst;
    reg        wb_cyc, wb_stb, wb_we;
    reg [31:0] wb_adr, wb_dat;
    reg [3:0]  wb_sel;
    wire [31:0] wb_dat_o;
    wire        wb_ack;
    wire [15:0] gpio_out;
    reg  [15:0] gpio_in;

    integer pass = 0, fail = 0;

    wb_gpio uut (
        .clk(clk), .rst(rst),
        .wb_cyc_i(wb_cyc), .wb_stb_i(wb_stb), .wb_we_i(wb_we),
        .wb_adr_i(wb_adr), .wb_dat_i(wb_dat), .wb_sel_i(wb_sel),
        .wb_dat_o(wb_dat_o), .wb_ack_o(wb_ack),
        .gpio_out(gpio_out), .gpio_in(gpio_in)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rst = 1; wb_cyc = 0; wb_stb = 0; wb_we = 0;
        wb_adr = 0; wb_dat = 0; wb_sel = 4'b1111;
        gpio_in = 16'h0000;
        repeat (5) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);

        // === Test 1: Write output register ===
        wb_cyc = 1; wb_stb = 1; wb_we = 1;
        wb_adr = 32'h8000_1000; wb_dat = 32'h0000_A5A5;
        @(posedge clk);  // Write sampled here
        #1;
        wb_cyc = 0; wb_stb = 0; wb_we = 0;
        @(posedge clk); #1;
        if (gpio_out === 16'hA5A5) begin
            $display("PASS: GPIO output = 0xA5A5"); pass = pass + 1;
        end else begin
            $display("FAIL: GPIO output — expected 0xA5A5, got 0x%04h", gpio_out); fail = fail + 1;
        end

        // === Test 2: Read back output register ===
        wb_cyc = 1; wb_stb = 1; wb_we = 0;
        wb_adr = 32'h8000_1000;
        #1;
        if (wb_dat_o === 32'h0000_A5A5) begin
            $display("PASS: Output readback = 0xA5A5"); pass = pass + 1;
        end else begin
            $display("FAIL: Output readback — got 0x%08h", wb_dat_o); fail = fail + 1;
        end
        wb_cyc = 0; wb_stb = 0;

        // === Test 3: Read input register (switches) ===
        gpio_in = 16'h1234;
        #1;
        wb_cyc = 1; wb_stb = 1; wb_we = 0;
        wb_adr = 32'h8000_1004;
        #1;
        if (wb_dat_o === 32'h0000_1234) begin
            $display("PASS: Input register = 0x1234"); pass = pass + 1;
        end else begin
            $display("FAIL: Input register — got 0x%08h", wb_dat_o); fail = fail + 1;
        end
        wb_cyc = 0; wb_stb = 0;

        // === Test 4: Reset clears output ===
        rst = 1;
        @(posedge clk); @(posedge clk);
        rst = 0;
        #1;
        if (gpio_out === 16'h0000) begin
            $display("PASS: Reset clears GPIO output"); pass = pass + 1;
        end else begin
            $display("FAIL: GPIO output after reset — got 0x%04h", gpio_out); fail = fail + 1;
        end

        // === Test 5: Ack on valid transaction ===
        wb_cyc = 1; wb_stb = 1; wb_we = 0;
        wb_adr = 32'h8000_1000;
        #1;
        if (wb_ack === 1'b1) begin
            $display("PASS: Ack on valid WB transaction"); pass = pass + 1;
        end else begin
            $display("FAIL: No ack"); fail = fail + 1;
        end
        wb_cyc = 0; wb_stb = 0;

        #20;
        $display("\n=== wb_gpio: %0d passed, %0d failed ===", pass, fail);
        if (fail > 0) $display("SOME TESTS FAILED");
        else          $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
