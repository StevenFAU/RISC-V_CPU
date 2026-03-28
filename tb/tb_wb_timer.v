// Testbench — wb_timer
// Verifies free-running counter, register read/write, and IRQ assertion.
`timescale 1ns / 1ps

module tb_wb_timer;

    reg        clk, rst;
    reg        wb_cyc, wb_stb, wb_we;
    reg [31:0] wb_adr, wb_dat;
    reg [3:0]  wb_sel;
    wire [31:0] wb_dat_o;
    wire        wb_ack;
    wire        timer_irq;

    integer pass = 0, fail = 0;

    wb_timer uut (
        .clk(clk), .rst(rst),
        .wb_cyc_i(wb_cyc), .wb_stb_i(wb_stb), .wb_we_i(wb_we),
        .wb_adr_i(wb_adr), .wb_dat_i(wb_dat), .wb_sel_i(wb_sel),
        .wb_dat_o(wb_dat_o), .wb_ack_o(wb_ack),
        .timer_irq(timer_irq)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rst = 1; wb_cyc = 0; wb_stb = 0; wb_we = 0;
        wb_adr = 0; wb_dat = 0; wb_sel = 4'b1111;
        repeat (5) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);

        // === Test 1: mtime increments after reset ===
        repeat (10) @(posedge clk);
        wb_cyc = 1; wb_stb = 1; wb_we = 0;
        wb_adr = 32'h8000_2000;
        #1;
        if (wb_dat_o > 32'd0) begin
            $display("PASS: mtime_lo > 0 after cycles (got %0d)", wb_dat_o); pass = pass + 1;
        end else begin
            $display("FAIL: mtime_lo = 0 after cycles"); fail = fail + 1;
        end
        wb_cyc = 0; wb_stb = 0;

        // === Test 2: mtime_hi = 0 (counter hasn't wrapped) ===
        wb_cyc = 1; wb_stb = 1; wb_we = 0;
        wb_adr = 32'h8000_2004;
        #1;
        if (wb_dat_o === 32'd0) begin
            $display("PASS: mtime_hi = 0"); pass = pass + 1;
        end else begin
            $display("FAIL: mtime_hi = 0x%08h", wb_dat_o); fail = fail + 1;
        end
        wb_cyc = 0; wb_stb = 0;

        // === Test 3: Write and read back mtimecmp_lo ===
        wb_cyc = 1; wb_stb = 1; wb_we = 1;
        wb_adr = 32'h8000_2008; wb_dat = 32'hDEAD_BEEF;
        @(posedge clk);  // Write sampled
        #1;
        wb_cyc = 0; wb_stb = 0; wb_we = 0;
        @(posedge clk); #1;
        // Read back
        wb_cyc = 1; wb_stb = 1; wb_we = 0;
        wb_adr = 32'h8000_2008;
        #1;
        if (wb_dat_o === 32'hDEAD_BEEF) begin
            $display("PASS: mtimecmp_lo readback = 0xDEADBEEF"); pass = pass + 1;
        end else begin
            $display("FAIL: mtimecmp_lo readback = 0x%08h", wb_dat_o); fail = fail + 1;
        end
        wb_cyc = 0; wb_stb = 0;

        // === Test 4: Write and read back mtimecmp_hi ===
        wb_cyc = 1; wb_stb = 1; wb_we = 1;
        wb_adr = 32'h8000_200C; wb_dat = 32'hCAFE_BABE;
        @(posedge clk);  // Write sampled
        #1;
        wb_cyc = 0; wb_stb = 0; wb_we = 0;
        @(posedge clk); #1;
        // Read back
        wb_cyc = 1; wb_stb = 1; wb_we = 0;
        wb_adr = 32'h8000_200C;
        #1;
        if (wb_dat_o === 32'hCAFE_BABE) begin
            $display("PASS: mtimecmp_hi readback = 0xCAFEBABE"); pass = pass + 1;
        end else begin
            $display("FAIL: mtimecmp_hi readback = 0x%08h", wb_dat_o); fail = fail + 1;
        end
        wb_cyc = 0; wb_stb = 0;

        // === Test 5: IRQ is de-asserted (mtime << mtimecmp) ===
        // mtimecmp = 0xCAFEBABE_DEADBEEF, mtime is tiny
        #1;
        if (timer_irq === 1'b0) begin
            $display("PASS: IRQ de-asserted (mtime < mtimecmp)"); pass = pass + 1;
        end else begin
            $display("FAIL: IRQ should be 0"); fail = fail + 1;
        end

        // === Test 6: Set mtimecmp to 0 — IRQ asserts ===
        wb_cyc = 1; wb_stb = 1; wb_we = 1;
        wb_adr = 32'h8000_2008; wb_dat = 32'd0;
        @(posedge clk); #1;
        wb_adr = 32'h8000_200C; wb_dat = 32'd0;
        @(posedge clk); #1;
        wb_cyc = 0; wb_stb = 0; wb_we = 0;
        @(posedge clk); #1;
        if (timer_irq === 1'b1) begin
            $display("PASS: IRQ asserted (mtime >= 0)"); pass = pass + 1;
        end else begin
            $display("FAIL: IRQ should be 1 when mtimecmp=0"); fail = fail + 1;
        end

        // === Test 7: Write mtime_lo to 0, read back small value ===
        wb_cyc = 1; wb_stb = 1; wb_we = 1;
        wb_adr = 32'h8000_2000; wb_dat = 32'h0000_0000;
        @(posedge clk); #1;
        wb_we = 0;
        #1;
        if (wb_dat_o < 32'd5) begin
            $display("PASS: mtime_lo near 0 after write (got %0d)", wb_dat_o); pass = pass + 1;
        end else begin
            $display("FAIL: mtime_lo after write = %0d", wb_dat_o); fail = fail + 1;
        end
        wb_cyc = 0; wb_stb = 0;

        // === Test 8: Ack on valid transaction ===
        wb_cyc = 1; wb_stb = 1; wb_we = 0;
        wb_adr = 32'h8000_2000;
        #1;
        if (wb_ack === 1'b1) begin
            $display("PASS: Ack on valid WB transaction"); pass = pass + 1;
        end else begin
            $display("FAIL: No ack"); fail = fail + 1;
        end
        wb_cyc = 0; wb_stb = 0;

        #20;
        $display("\n=== wb_timer: %0d passed, %0d failed ===", pass, fail);
        if (fail > 0) $display("SOME TESTS FAILED");
        else          $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
