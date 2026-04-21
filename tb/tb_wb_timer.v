// Testbench — wb_timer
// Verifies free-running counter, register read/write, and IRQ assertion.
// Phase 0.1 hardening (2026-04-21):
//   * Tests 9/11 prove the write/increment race fix: a write to
//     mtime_lo/mtime_hi replaces that half and skips the increment that
//     cycle; the untouched half is preserved and then resumes incrementing.
//   * Test 10 proves the reset-IRQ story: after the first post-reset tick
//     (which wraps all-1s → 0), timer_irq stays de-asserted with mtimecmp
//     still at its reset default, so no software touches are required for
//     a clean startup.
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
    reg [31:0] captured_lo;
    reg        irq_bad;
    integer    i;

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
        // Reset value is all-1s; first tick wraps to 0. After ~10 more ticks
        // mtime_lo should be a small non-zero value.
        repeat (10) @(posedge clk);
        wb_cyc = 1; wb_stb = 1; wb_we = 0;
        wb_adr = 32'h8000_2000;
        #1;
        if (wb_dat_o > 32'd0 && wb_dat_o < 32'd100) begin
            $display("PASS: mtime_lo > 0 after cycles (got %0d)", wb_dat_o); pass = pass + 1;
        end else begin
            $display("FAIL: mtime_lo = 0x%08h after cycles", wb_dat_o); fail = fail + 1;
        end
        wb_cyc = 0; wb_stb = 0;

        // === Test 2: mtime_hi = 0 (counter hasn't wrapped again) ===
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

        // =====================================================================
        // Phase 0.1 new tests (9, 10, 11)
        // =====================================================================

        // === Test 9: write-while-incrementing race ===
        // Write mtime_lo = 0x00001000; wait 5 ticks; read back.
        // Expected: exactly 0x00001005 — the write replaces the low half and
        // skips that cycle's increment, so the counter resumes cleanly from
        // the written value. With the pre-fix code the write clobbered the
        // increment ("last NBA wins"), which was the bug this test guards.
        wb_cyc = 1; wb_stb = 1; wb_we = 1;
        wb_adr = 32'h8000_2000; wb_dat = 32'h0000_1000;
        @(posedge clk); #1;
        wb_we = 0;
        // 5 more posedges of free-running increment
        repeat (5) @(posedge clk);
        #1;
        wb_adr = 32'h8000_2000;
        #1;
        if (wb_dat_o === 32'h0000_1005) begin
            $display("PASS: mtime_lo race fix — wrote 0x1000, 5 ticks later = 0x%08h", wb_dat_o);
            pass = pass + 1;
        end else begin
            $display("FAIL: mtime_lo race fix — expected 0x00001005, got 0x%08h", wb_dat_o);
            fail = fail + 1;
        end
        wb_cyc = 0; wb_stb = 0;

        // === Test 10: IRQ does not fire at reset (after wrap tick) ===
        // Reset puts mtime = mtimecmp = all-1s. timer_irq = (mtime >= mtimecmp)
        // is transiently true, but the very next clock tick wraps mtime to 0
        // and IRQ clears. Verify IRQ stays 0 for 5 subsequent cycles with no
        // software touching mtimecmp.
        rst = 1;
        wb_cyc = 0; wb_stb = 0; wb_we = 0;
        repeat (3) @(posedge clk);
        rst = 0;
        @(posedge clk);  // wrap tick: mtime goes all-1s -> 0
        #1;
        irq_bad = 1'b0;
        for (i = 0; i < 5; i = i + 1) begin
            if (timer_irq !== 1'b0) irq_bad = 1'b1;
            @(posedge clk); #1;
        end
        if (irq_bad === 1'b0) begin
            $display("PASS: timer_irq stays 0 for 5 cycles after reset wrap");
            pass = pass + 1;
        end else begin
            $display("FAIL: timer_irq asserted post-reset without software touch");
            fail = fail + 1;
        end

        // === Test 11: write to mtime_hi preserves mtime_lo ===
        // Symmetric partner to Test 9. Capture mtime_lo, write mtime_hi, then
        // read mtime_lo without any intervening clock edges. The written-half
        // cycle skips the increment, so mtime_lo must still match the
        // captured value exactly.
        wb_cyc = 1; wb_stb = 1; wb_we = 0;
        wb_adr = 32'h8000_2000;
        #1;
        captured_lo = wb_dat_o;
        // Drive the write on the next posedge
        wb_we = 1;
        wb_adr = 32'h8000_2004; wb_dat = 32'h5555_5555;
        @(posedge clk); #1;
        // mtime_hi now = 0x55555555, mtime_lo preserved (no increment this cycle)
        wb_we = 0;
        wb_adr = 32'h8000_2000;
        #1;
        if (wb_dat_o === captured_lo) begin
            $display("PASS: mtime_hi write preserves mtime_lo (both = 0x%08h)",
                     captured_lo);
            pass = pass + 1;
        end else begin
            $display("FAIL: mtime_hi write leaked into mtime_lo — captured 0x%08h, got 0x%08h",
                     captured_lo, wb_dat_o);
            fail = fail + 1;
        end
        // Sanity: mtime_hi really did take the new value
        wb_adr = 32'h8000_2004;
        #1;
        if (wb_dat_o === 32'h5555_5555) begin
            $display("PASS: mtime_hi readback = 0x55555555"); pass = pass + 1;
        end else begin
            $display("FAIL: mtime_hi readback = 0x%08h", wb_dat_o); fail = fail + 1;
        end
        wb_cyc = 0; wb_stb = 0;

        #20;
        $display("\n=== wb_timer: %0d passed, %0d failed ===", pass, fail);
        if (fail > 0) $display("SOME TESTS FAILED");
        else          $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
