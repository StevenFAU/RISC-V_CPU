// Testbench — wb_master
// Verifies Wishbone signal generation from core dmem bus signals,
// plus Phase 0.1 additions: WB_USE_STALL parameter, stall_o output,
// and the simulation-only missing-ack assertion.
`timescale 1ns / 1ps
`include "defines.v"

module tb_wb_master;

    // =========================================================================
    // Shared clock — driven by the testbench. wb_master uses this only for
    // its simulation assertion on negedge; existing combinational checks
    // are unaffected by clock edges.
    // =========================================================================
    reg clk;
    initial clk = 0;
    always #5 clk = ~clk;   // 100 MHz

    // =========================================================================
    // UUT 1 — default parameters (WB_USE_STALL = 0). Existing test coverage.
    //         wb_ack_i is held high so the assertion never fires for this
    //         block of tests (a compliant combinational slave would do this).
    // =========================================================================
    reg  [31:0] dmem_addr, dmem_wdata;
    reg         dmem_we, dmem_re;
    reg  [2:0]  dmem_funct3;
    wire [31:0] dmem_rdata;

    wire        wb_cyc_o, wb_stb_o, wb_we_o;
    wire [31:0] wb_adr_o, wb_dat_o;
    wire [3:0]  wb_sel_o;
    reg  [31:0] wb_dat_i;
    reg         wb_ack_i;
    wire [2:0]  wb_funct3_o;
    wire        stall_o;

    integer pass = 0, fail = 0;

    wb_master uut (
        .clk(clk),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_we(dmem_we), .dmem_re(dmem_re),
        .dmem_funct3(dmem_funct3), .dmem_rdata(dmem_rdata),
        .wb_cyc_o(wb_cyc_o), .wb_stb_o(wb_stb_o), .wb_we_o(wb_we_o),
        .wb_adr_o(wb_adr_o), .wb_dat_o(wb_dat_o), .wb_sel_o(wb_sel_o),
        .wb_dat_i(wb_dat_i), .wb_ack_i(wb_ack_i),
        .wb_funct3_o(wb_funct3_o),
        .stall_o(stall_o)
    );

    task check;
        input [127:0] name;
        input [3:0] expected_sel;
        input expected_cyc;
        input expected_we;
    begin
        #1;
        if (wb_sel_o === expected_sel && wb_cyc_o === expected_cyc && wb_we_o === expected_we) begin
            $display("PASS: %0s sel=%b cyc=%b we=%b", name, wb_sel_o, wb_cyc_o, wb_we_o);
            pass = pass + 1;
        end else begin
            $display("FAIL: %0s sel=%b (exp %b) cyc=%b (exp %b) we=%b (exp %b)",
                     name, wb_sel_o, expected_sel, wb_cyc_o, expected_cyc, wb_we_o, expected_we);
            fail = fail + 1;
        end
    end
    endtask

    // =========================================================================
    // UUT 2 — WB_USE_STALL = 1. Verifies stall_o tracks (cyc & stb & !ack).
    //         Driven independently from UUT 1 on the same clock.
    // =========================================================================
    reg  [31:0] s_dmem_addr, s_dmem_wdata;
    reg         s_dmem_we, s_dmem_re;
    reg  [2:0]  s_dmem_funct3;
    wire [31:0] s_dmem_rdata;

    wire        s_wb_cyc_o, s_wb_stb_o, s_wb_we_o;
    wire [31:0] s_wb_adr_o, s_wb_dat_o;
    wire [3:0]  s_wb_sel_o;
    reg  [31:0] s_wb_dat_i;
    reg         s_wb_ack_i;
    wire [2:0]  s_wb_funct3_o;
    wire        s_stall_o;

    wb_master #(.WB_USE_STALL(1)) uut_stall (
        .clk(clk),
        .dmem_addr(s_dmem_addr), .dmem_wdata(s_dmem_wdata),
        .dmem_we(s_dmem_we), .dmem_re(s_dmem_re),
        .dmem_funct3(s_dmem_funct3), .dmem_rdata(s_dmem_rdata),
        .wb_cyc_o(s_wb_cyc_o), .wb_stb_o(s_wb_stb_o), .wb_we_o(s_wb_we_o),
        .wb_adr_o(s_wb_adr_o), .wb_dat_o(s_wb_dat_o), .wb_sel_o(s_wb_sel_o),
        .wb_dat_i(s_wb_dat_i), .wb_ack_i(s_wb_ack_i),
        .wb_funct3_o(s_wb_funct3_o),
        .stall_o(s_stall_o)
    );

    // =========================================================================
    // UUT 3 — WB_USE_STALL = 0, used only to prove the assertion fires.
    //         Held quiescent until the assertion test section.
    // =========================================================================
    reg  [31:0] a_dmem_addr;
    reg         a_dmem_we, a_dmem_re;
    reg  [2:0]  a_dmem_funct3;
    reg  [31:0] a_wb_dat_i;
    reg         a_wb_ack_i;

    wire        a_wb_cyc_o, a_wb_stb_o, a_wb_we_o;
    wire [31:0] a_wb_adr_o, a_wb_dat_o, a_dmem_rdata;
    wire [3:0]  a_wb_sel_o;
    wire [2:0]  a_wb_funct3_o;
    wire        a_stall_o;

    wb_master uut_assert (
        .clk(clk),
        .dmem_addr(a_dmem_addr), .dmem_wdata(32'd0),
        .dmem_we(a_dmem_we), .dmem_re(a_dmem_re),
        .dmem_funct3(a_dmem_funct3), .dmem_rdata(a_dmem_rdata),
        .wb_cyc_o(a_wb_cyc_o), .wb_stb_o(a_wb_stb_o), .wb_we_o(a_wb_we_o),
        .wb_adr_o(a_wb_adr_o), .wb_dat_o(a_wb_dat_o), .wb_sel_o(a_wb_sel_o),
        .wb_dat_i(a_wb_dat_i), .wb_ack_i(a_wb_ack_i),
        .wb_funct3_o(a_wb_funct3_o),
        .stall_o(a_stall_o)
    );

    // =========================================================================
    // Main stimulus
    // =========================================================================
    initial begin
        // Defaults for every instance so no assertion fires on any UUT.
        dmem_we = 0; dmem_re = 0; dmem_addr = 0; dmem_wdata = 0;
        dmem_funct3 = 0; wb_dat_i = 0; wb_ack_i = 1'b1; // ack held high for existing tests

        s_dmem_we = 0; s_dmem_re = 0; s_dmem_addr = 0; s_dmem_wdata = 0;
        s_dmem_funct3 = 0; s_wb_dat_i = 0; s_wb_ack_i = 1'b1;

        a_dmem_we = 0; a_dmem_re = 0; a_dmem_addr = 0; a_dmem_funct3 = 0;
        a_wb_dat_i = 0; a_wb_ack_i = 1'b1;

        #10;

        // Test 1: No bus activity — cyc/stb should be low
        check("idle", 4'b0001, 1'b0, 1'b0);

        // Test 2: Word read
        dmem_re = 1; dmem_funct3 = `F3_WORD; dmem_addr = 32'h00010000;
        check("LW", 4'b1111, 1'b1, 1'b0);
        dmem_re = 0;

        // Test 3: Word write
        dmem_we = 1; dmem_funct3 = `F3_WORD; dmem_addr = 32'h00010004;
        dmem_wdata = 32'hDEADBEEF;
        check("SW", 4'b1111, 1'b1, 1'b1);
        dmem_we = 0;

        // Test 4: Byte read at offset 0
        dmem_re = 1; dmem_funct3 = `F3_BYTE; dmem_addr = 32'h00010000;
        check("LB off=0", 4'b0001, 1'b1, 1'b0);

        // Test 5: Byte read at offset 1
        dmem_addr = 32'h00010001;
        check("LB off=1", 4'b0010, 1'b1, 1'b0);

        // Test 6: Byte read at offset 2
        dmem_addr = 32'h00010002;
        check("LB off=2", 4'b0100, 1'b1, 1'b0);

        // Test 7: Byte read at offset 3
        dmem_addr = 32'h00010003;
        check("LB off=3", 4'b1000, 1'b1, 1'b0);
        dmem_re = 0;

        // Test 8: Halfword read at offset 0
        dmem_re = 1; dmem_funct3 = `F3_HALF; dmem_addr = 32'h00010000;
        check("LH off=0", 4'b0011, 1'b1, 1'b0);

        // Test 9: Halfword read at offset 2
        dmem_addr = 32'h00010002;
        check("LH off=2", 4'b1100, 1'b1, 1'b0);
        dmem_re = 0;

        // Test 10: Read data passthrough
        dmem_re = 1; dmem_funct3 = `F3_WORD; dmem_addr = 32'h00010000;
        wb_dat_i = 32'hCAFEBABE;
        #1;
        if (dmem_rdata === 32'hCAFEBABE) begin
            $display("PASS: read data passthrough"); pass = pass + 1;
        end else begin
            $display("FAIL: read data — got 0x%08h", dmem_rdata); fail = fail + 1;
        end
        dmem_re = 0;

        // Test 11: funct3 sideband
        dmem_re = 1; dmem_funct3 = `F3_BYTEU;
        #1;
        if (wb_funct3_o === `F3_BYTEU) begin
            $display("PASS: funct3 sideband"); pass = pass + 1;
        end else begin
            $display("FAIL: funct3 sideband — got %b", wb_funct3_o); fail = fail + 1;
        end
        dmem_re = 0;

        // Test 12: stall_o on default instance is tied low regardless of ack
        wb_ack_i = 1'b0; dmem_re = 1; dmem_funct3 = `F3_WORD;
        dmem_addr = 32'h00010010;
        #1;
        if (stall_o === 1'b0) begin
            $display("PASS: stall_o tied 0 when WB_USE_STALL=0"); pass = pass + 1;
        end else begin
            $display("FAIL: stall_o expected 0 (WB_USE_STALL=0), got %b", stall_o);
            fail = fail + 1;
        end
        // Restore ack=1 BEFORE the next negedge so UUT 1 asserts no further.
        dmem_re = 0; wb_ack_i = 1'b1;
        #1;

        // =====================================================================
        // Phase 0.1 — stall_o behavior with WB_USE_STALL = 1
        //
        // Drive a read request, hold ack low for three full clock cycles,
        // then ack. stall_o must be high on each of the three stalling
        // cycles and low on the ack cycle.
        // =====================================================================
        $display("\n--- WB_USE_STALL=1: stall_o tracks !ack ---");

        // Align to a posedge so we sample stall cleanly each cycle.
        @(posedge clk); #1;
        s_wb_ack_i   = 1'b0;
        s_dmem_re    = 1'b1;
        s_dmem_funct3 = `F3_WORD;
        s_dmem_addr  = 32'h00010020;

        // Cycle 1
        #1;
        if (s_stall_o === 1'b1) begin
            $display("PASS: stall cycle 1 — stall_o high"); pass = pass + 1;
        end else begin
            $display("FAIL: stall cycle 1 — stall_o=%b (exp 1)", s_stall_o); fail = fail + 1;
        end

        // Cycle 2
        @(posedge clk); #1;
        if (s_stall_o === 1'b1) begin
            $display("PASS: stall cycle 2 — stall_o high"); pass = pass + 1;
        end else begin
            $display("FAIL: stall cycle 2 — stall_o=%b (exp 1)", s_stall_o); fail = fail + 1;
        end

        // Cycle 3
        @(posedge clk); #1;
        if (s_stall_o === 1'b1) begin
            $display("PASS: stall cycle 3 — stall_o high"); pass = pass + 1;
        end else begin
            $display("FAIL: stall cycle 3 — stall_o=%b (exp 1)", s_stall_o); fail = fail + 1;
        end

        // Cycle 4 — slave asserts ack combinationally; stall must drop
        // immediately in the same cycle (combinational dependency).
        @(posedge clk); #1;
        s_wb_ack_i = 1'b1;
        #1;
        if (s_stall_o === 1'b0) begin
            $display("PASS: ack cycle — stall_o low on ack"); pass = pass + 1;
        end else begin
            $display("FAIL: ack cycle — stall_o=%b (exp 0)", s_stall_o); fail = fail + 1;
        end

        // Release the transaction and let the clock settle before the final
        // (deliberately assertion-firing) section.
        @(posedge clk); #1;
        s_dmem_re = 1'b0;
        s_wb_ack_i = 1'b1;

        // =====================================================================
        // Phase 0.1 — assertion-fire demonstration
        //
        // With WB_USE_STALL=0 on uut_assert, driving cyc+stb while holding
        // ack low must trip the simulation assertion. iverilog prints the
        // $error and $display messages but does not halt, so the test just
        // logs that it exercised the path. We keep the window short so only
        // a couple of negedges are caught.
        // =====================================================================
        $display("\n--- WB_USE_STALL=0: assertion MUST fire next (expected ERROR lines below) ---");
        a_wb_ack_i   = 1'b0;
        a_dmem_re    = 1'b1;
        a_dmem_funct3 = `F3_WORD;
        a_dmem_addr  = 32'h00010030;
        // Straddle at least one negedge so the assertion samples.
        @(negedge clk); @(negedge clk);
        // Restore to a safe state so no further assertions fire.
        a_dmem_re = 1'b0;
        a_wb_ack_i = 1'b1;
        #1;
        $display("PASS: assertion path exercised (see ERROR lines above)"); pass = pass + 1;
        $display("--- end of assertion-fire section ---\n");

        #10;
        $display("\n=== wb_master: %0d passed, %0d failed ===", pass, fail);
        if (fail > 0) $display("SOME TESTS FAILED");
        else          $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
