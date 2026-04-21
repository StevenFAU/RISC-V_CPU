// Testbench — wb_interconnect
// Verifies address decode steers to correct slave and muxes responses.
//
// Phase 0.1 (2026-04-21) history:
//   * Tests 8–12 added for the tightened UART/GPIO/TIMER decodes.
//   * Test 3 re-stated and Tests 13–17 added for the new unmapped-access
//     policy: an active cycle to an unmapped address auto-acks with
//     wbm_dat_o=0 and asserts combinational bus_error_o. Idle cycles stay
//     quiescent. This prevents bus hangs once Phase 4 wires the master
//     stall through to the pipeline, and hands Phase 1 a clean signal to
//     hang the load/store access-fault trap off of.
`timescale 1ns / 1ps

module tb_wb_interconnect;

    reg         wbm_cyc, wbm_stb, wbm_we;
    reg  [31:0] wbm_adr, wbm_dat;
    reg  [3:0]  wbm_sel;
    wire [31:0] wbm_dat_o;
    wire        wbm_ack_o;
    wire        bus_error;
    reg  [2:0]  wbm_funct3;

    // Slave 0 (DMEM)
    wire        wbs0_cyc, wbs0_stb, wbs0_we;
    wire [31:0] wbs0_adr, wbs0_dat;
    wire [3:0]  wbs0_sel;
    reg  [31:0] wbs0_dat_i;
    reg         wbs0_ack_i;
    wire [2:0]  wbs0_funct3;

    // Slave 1 (UART)
    wire        wbs1_cyc, wbs1_stb, wbs1_we;
    wire [31:0] wbs1_adr, wbs1_dat;
    wire [3:0]  wbs1_sel;
    reg  [31:0] wbs1_dat_i;
    reg         wbs1_ack_i;

    // Slave 2 (GPIO)
    wire        wbs2_cyc, wbs2_stb, wbs2_we;
    wire [31:0] wbs2_adr, wbs2_dat;
    wire [3:0]  wbs2_sel;
    reg  [31:0] wbs2_dat_i;
    reg         wbs2_ack_i;

    // Slave 3 (TIMER)
    wire        wbs3_cyc, wbs3_stb, wbs3_we;
    wire [31:0] wbs3_adr, wbs3_dat;
    wire [3:0]  wbs3_sel;
    reg  [31:0] wbs3_dat_i;
    reg         wbs3_ack_i;

    integer pass = 0, fail = 0;

    wb_interconnect uut (
        .wbm_cyc_i(wbm_cyc), .wbm_stb_i(wbm_stb), .wbm_we_i(wbm_we),
        .wbm_adr_i(wbm_adr), .wbm_dat_i(wbm_dat), .wbm_sel_i(wbm_sel),
        .wbm_dat_o(wbm_dat_o), .wbm_ack_o(wbm_ack_o),
        .wbm_funct3_i(wbm_funct3),
        // Slave 0
        .wbs0_cyc_o(wbs0_cyc), .wbs0_stb_o(wbs0_stb), .wbs0_we_o(wbs0_we),
        .wbs0_adr_o(wbs0_adr), .wbs0_dat_o(wbs0_dat), .wbs0_sel_o(wbs0_sel),
        .wbs0_dat_i(wbs0_dat_i), .wbs0_ack_i(wbs0_ack_i),
        .wbs0_funct3_o(wbs0_funct3),
        // Slave 1
        .wbs1_cyc_o(wbs1_cyc), .wbs1_stb_o(wbs1_stb), .wbs1_we_o(wbs1_we),
        .wbs1_adr_o(wbs1_adr), .wbs1_dat_o(wbs1_dat), .wbs1_sel_o(wbs1_sel),
        .wbs1_dat_i(wbs1_dat_i), .wbs1_ack_i(wbs1_ack_i),
        // Slave 2
        .wbs2_cyc_o(wbs2_cyc), .wbs2_stb_o(wbs2_stb), .wbs2_we_o(wbs2_we),
        .wbs2_adr_o(wbs2_adr), .wbs2_dat_o(wbs2_dat), .wbs2_sel_o(wbs2_sel),
        .wbs2_dat_i(wbs2_dat_i), .wbs2_ack_i(wbs2_ack_i),
        // Slave 3
        .wbs3_cyc_o(wbs3_cyc), .wbs3_stb_o(wbs3_stb), .wbs3_we_o(wbs3_we),
        .wbs3_adr_o(wbs3_adr), .wbs3_dat_o(wbs3_dat), .wbs3_sel_o(wbs3_sel),
        .wbs3_dat_i(wbs3_dat_i), .wbs3_ack_i(wbs3_ack_i),
        .bus_error_o(bus_error)
    );

    initial begin
        wbm_cyc = 0; wbm_stb = 0; wbm_we = 0;
        wbm_adr = 0; wbm_dat = 0; wbm_sel = 0; wbm_funct3 = 0;
        wbs0_dat_i = 0; wbs0_ack_i = 0;
        wbs1_dat_i = 0; wbs1_ack_i = 0;
        wbs2_dat_i = 0; wbs2_ack_i = 0;
        wbs3_dat_i = 0; wbs3_ack_i = 0;
        #10;

        // === Test 1: DMEM address — slave 0 selected ===
        wbm_cyc = 1; wbm_stb = 1; wbm_we = 0;
        wbm_adr = 32'h0001_0100; wbm_sel = 4'b1111;
        wbs0_dat_i = 32'hBEEF_CAFE; wbs0_ack_i = 1;
        wbs1_dat_i = 32'h0; wbs1_ack_i = 0;
        #1;
        if (wbs0_cyc === 1 && wbs1_cyc === 0 && wbm_dat_o === 32'hBEEF_CAFE
                && wbm_ack_o === 1 && bus_error === 1'b0) begin
            $display("PASS: DMEM addr selects slave 0"); pass = pass + 1;
        end else begin
            $display("FAIL: DMEM addr"); fail = fail + 1;
        end

        // === Test 2: UART address — slave 1 selected ===
        wbm_adr = 32'h8000_0004;
        wbs0_dat_i = 32'h0; wbs0_ack_i = 0;
        wbs1_dat_i = 32'h0000_0001; wbs1_ack_i = 1;
        #1;
        if (wbs1_cyc === 1 && wbs0_cyc === 0 && wbm_dat_o === 32'h0000_0001
                && wbm_ack_o === 1 && bus_error === 1'b0) begin
            $display("PASS: UART addr selects slave 1"); pass = pass + 1;
        end else begin
            $display("FAIL: UART addr — s1_cyc=%b s0_cyc=%b dat=%h ack=%b be=%b",
                     wbs1_cyc, wbs0_cyc, wbm_dat_o, wbm_ack_o, bus_error); fail = fail + 1;
        end

        // === Test 3: Unmapped addr — acks with bus_error ===
        // Phase 0.1 behavior change: previously no-ack, no-dat. Now auto-acks
        // with zero rdata and raises bus_error_o combinationally. This is the
        // hook for the Phase 1 load/store access-fault trap.
        wbm_adr = 32'h0002_0000;
        wbs0_ack_i = 1; wbs1_ack_i = 1;
        #1;
        if (wbs0_cyc === 0 && wbs1_cyc === 0
                && wbm_ack_o === 1'b1
                && wbm_dat_o === 32'd0
                && bus_error === 1'b1) begin
            $display("PASS: Unmapped addr — acks with bus_error"); pass = pass + 1;
        end else begin
            $display("FAIL: Unmapped addr — s0_cyc=%b s1_cyc=%b ack=%b dat=%h be=%b",
                     wbs0_cyc, wbs1_cyc, wbm_ack_o, wbm_dat_o, bus_error); fail = fail + 1;
        end

        // === Test 4: Write enable passthrough ===
        wbm_adr = 32'h0001_0000; wbm_we = 1;
        #1;
        if (wbs0_we === 1) begin
            $display("PASS: Write enable passthrough"); pass = pass + 1;
        end else begin
            $display("FAIL: Write enable not passed"); fail = fail + 1;
        end

        // === Test 5: sel passthrough ===
        wbm_sel = 4'b0010;
        #1;
        if (wbs0_sel === 4'b0010) begin
            $display("PASS: sel passthrough to DMEM"); pass = pass + 1;
        end else begin
            $display("FAIL: sel — got %b", wbs0_sel); fail = fail + 1;
        end

        // === Test 6: funct3 sideband passthrough ===
        wbm_funct3 = 3'b101;
        #1;
        if (wbs0_funct3 === 3'b101) begin
            $display("PASS: funct3 sideband passthrough"); pass = pass + 1;
        end else begin
            $display("FAIL: funct3 sideband — got %b", wbs0_funct3); fail = fail + 1;
        end

        // === Test 7: UART sel passthrough ===
        wbm_adr = 32'h8000_0000; wbm_sel = 4'b0001;
        #1;
        if (wbs1_sel === 4'b0001) begin
            $display("PASS: sel passthrough to UART"); pass = pass + 1;
        end else begin
            $display("FAIL: UART sel — got %b", wbs1_sel); fail = fail + 1;
        end

        // =====================================================================
        // Phase 0.1 new tests (8–17) — tightened decodes + bus_error policy
        // =====================================================================

        // Common state for fall-through tests: all slaves ack-high so we can
        // prove the interconnect is the thing gating cyc, not the slave.
        wbs0_ack_i = 1; wbs1_ack_i = 1; wbs2_ack_i = 1; wbs3_ack_i = 1;
        wbm_we = 0; wbm_sel = 4'b1111;

        // === Test 8: UART out-of-range access falls through (bus_error) ===
        // 0x80000010 was inside the old 4 KB UART page; the new decode stops
        // at 0x8000000F. The new unmapped policy auto-acks AND raises
        // bus_error_o — the slave still does not see cyc asserted.
        wbm_adr = 32'h8000_0010;
        #1;
        if (wbs1_cyc === 0 && wbm_ack_o === 1'b1
                && wbm_dat_o === 32'd0
                && bus_error === 1'b1) begin
            $display("PASS: UART out-of-range (0x80000010) -> bus_error+ack");
            pass = pass + 1;
        end else begin
            $display("FAIL: UART out-of-range — s1_cyc=%b ack=%b dat=%h be=%b",
                     wbs1_cyc, wbm_ack_o, wbm_dat_o, bus_error); fail = fail + 1;
        end

        // === Test 9: GPIO out-of-range access falls through (bus_error) ===
        // 0x80001008 was inside the old 4 KB GPIO page; new decode stops at
        // 0x80001007 (2 registers).
        wbm_adr = 32'h8000_1008;
        #1;
        if (wbs2_cyc === 0 && wbm_ack_o === 1'b1
                && wbm_dat_o === 32'd0
                && bus_error === 1'b1) begin
            $display("PASS: GPIO out-of-range (0x80001008) -> bus_error+ack");
            pass = pass + 1;
        end else begin
            $display("FAIL: GPIO out-of-range — s2_cyc=%b ack=%b dat=%h be=%b",
                     wbs2_cyc, wbm_ack_o, wbm_dat_o, bus_error); fail = fail + 1;
        end

        // === Test 10: GPIO in-range boundaries still hit slave ===
        wbs2_dat_i = 32'hAAAA_5555;
        wbm_adr = 32'h8000_1000;
        #1;
        if (wbs2_cyc === 1 && wbm_ack_o === 1 && wbm_dat_o === 32'hAAAA_5555
                && bus_error === 1'b0) begin
            $display("PASS: GPIO in-range low  (0x80001000) -> slave 2"); pass = pass + 1;
        end else begin
            $display("FAIL: GPIO in-range low — s2_cyc=%b ack=%b dat=%h be=%b",
                     wbs2_cyc, wbm_ack_o, wbm_dat_o, bus_error); fail = fail + 1;
        end
        wbm_adr = 32'h8000_1004;
        #1;
        if (wbs2_cyc === 1 && wbm_ack_o === 1 && wbm_dat_o === 32'hAAAA_5555
                && bus_error === 1'b0) begin
            $display("PASS: GPIO in-range high (0x80001004) -> slave 2"); pass = pass + 1;
        end else begin
            $display("FAIL: GPIO in-range high — s2_cyc=%b ack=%b dat=%h be=%b",
                     wbs2_cyc, wbm_ack_o, wbm_dat_o, bus_error); fail = fail + 1;
        end

        // === Test 11: Timer out-of-range access falls through (bus_error) ===
        // 0x80002010 was inside the old 4 KB timer page; new decode stops at
        // 0x8000200F (4 registers).
        wbs2_dat_i = 32'd0;
        wbm_adr = 32'h8000_2010;
        #1;
        if (wbs3_cyc === 0 && wbm_ack_o === 1'b1
                && wbm_dat_o === 32'd0
                && bus_error === 1'b1) begin
            $display("PASS: TIMER out-of-range (0x80002010) -> bus_error+ack");
            pass = pass + 1;
        end else begin
            $display("FAIL: TIMER out-of-range — s3_cyc=%b ack=%b dat=%h be=%b",
                     wbs3_cyc, wbm_ack_o, wbm_dat_o, bus_error); fail = fail + 1;
        end

        // === Test 12: Timer in-range boundaries still hit slave ===
        wbs3_dat_i = 32'hF00D_1234;
        wbm_adr = 32'h8000_2000;
        #1;
        if (wbs3_cyc === 1 && wbm_ack_o === 1 && wbm_dat_o === 32'hF00D_1234
                && bus_error === 1'b0) begin
            $display("PASS: TIMER in-range low  (0x80002000) -> slave 3"); pass = pass + 1;
        end else begin
            $display("FAIL: TIMER in-range low — s3_cyc=%b ack=%b dat=%h be=%b",
                     wbs3_cyc, wbm_ack_o, wbm_dat_o, bus_error); fail = fail + 1;
        end
        wbm_adr = 32'h8000_200C;
        #1;
        if (wbs3_cyc === 1 && wbm_ack_o === 1 && wbm_dat_o === 32'hF00D_1234
                && bus_error === 1'b0) begin
            $display("PASS: TIMER in-range high (0x8000200C) -> slave 3"); pass = pass + 1;
        end else begin
            $display("FAIL: TIMER in-range high — s3_cyc=%b ack=%b dat=%h be=%b",
                     wbs3_cyc, wbm_ack_o, wbm_dat_o, bus_error); fail = fail + 1;
        end

        // === Test 13: Mapped DMEM access does not raise bus_error ===
        wbs0_dat_i = 32'h1234_5678;
        wbm_adr = 32'h0001_0100;
        #1;
        if (bus_error === 1'b0 && wbs0_cyc === 1'b1 && wbm_ack_o === 1'b1) begin
            $display("PASS: mapped DMEM access — bus_error=0"); pass = pass + 1;
        end else begin
            $display("FAIL: mapped DMEM — be=%b s0_cyc=%b ack=%b",
                     bus_error, wbs0_cyc, wbm_ack_o); fail = fail + 1;
        end

        // === Test 14: Mapped UART access does not raise bus_error ===
        wbs1_dat_i = 32'h8765_4321;
        wbm_adr = 32'h8000_0004;
        #1;
        if (bus_error === 1'b0 && wbs1_cyc === 1'b1 && wbm_ack_o === 1'b1) begin
            $display("PASS: mapped UART access — bus_error=0"); pass = pass + 1;
        end else begin
            $display("FAIL: mapped UART — be=%b s1_cyc=%b ack=%b",
                     bus_error, wbs1_cyc, wbm_ack_o); fail = fail + 1;
        end

        // === Test 15: Idle cycle — no bus_error, no ack ===
        // Drive an unmapped address on the bus with cyc=stb=0. The
        // interconnect must treat this as idle: no bus_error, no ack.
        // This guards against the naive bug where bus_error is derived
        // from just "no slave matched" without the cyc&stb gate.
        wbm_cyc = 0; wbm_stb = 0;
        wbm_adr = 32'h0002_0000;
        #1;
        if (bus_error === 1'b0 && wbm_ack_o === 1'b0) begin
            $display("PASS: idle cycle — no bus_error, no ack"); pass = pass + 1;
        end else begin
            $display("FAIL: idle cycle — be=%b ack=%b (expected 0,0)",
                     bus_error, wbm_ack_o); fail = fail + 1;
        end

        // === Test 16: Out-of-range-within-peripheral raises bus_error ===
        // Exercises the interaction with bug #3's tightened UART decode:
        // 0x80000010 sits inside the old 4 KB UART page but past the new
        // 16-byte register window. bus_error_o MUST assert; wbm_ack_o=1;
        // no slave sees cyc asserted.
        wbm_cyc = 1; wbm_stb = 1; wbm_we = 0;
        wbm_adr = 32'h8000_0010;
        #1;
        if (bus_error === 1'b1 && wbm_ack_o === 1'b1
                && wbs0_cyc === 1'b0 && wbs1_cyc === 1'b0
                && wbs2_cyc === 1'b0 && wbs3_cyc === 1'b0) begin
            $display("PASS: out-of-range peripheral (UART+0x10) -> bus_error");
            pass = pass + 1;
        end else begin
            $display("FAIL: out-of-range peripheral — be=%b ack=%b cycs=%b%b%b%b",
                     bus_error, wbm_ack_o, wbs0_cyc, wbs1_cyc, wbs2_cyc, wbs3_cyc);
            fail = fail + 1;
        end

        // === Test 17: bus_error is combinational (same-cycle tracking) ===
        // Transition the address from a mapped (DMEM) value to an unmapped
        // value with no intervening clock edge. bus_error_o must flip in
        // the same delta cycle — protects against someone registering it
        // and breaking the Phase 1 trap semantics.
        wbm_cyc = 1; wbm_stb = 1;
        wbm_adr = 32'h0001_0100;   // mapped (DMEM)
        #1;
        if (bus_error !== 1'b0) begin
            $display("FAIL: pre-transition bus_error=%b (expected 0)", bus_error);
            fail = fail + 1;
        end
        wbm_adr = 32'h4000_0000;   // unmapped — no clock edge between
        #1;
        if (bus_error === 1'b1) begin
            $display("PASS: bus_error tracks combinationally (mapped->unmapped)");
            pass = pass + 1;
        end else begin
            $display("FAIL: bus_error did not track same-cycle — be=%b",
                     bus_error); fail = fail + 1;
        end
        wbm_adr = 32'h0001_0100;   // back to mapped — again no clock edge
        #1;
        if (bus_error === 1'b0) begin
            $display("PASS: bus_error tracks combinationally (unmapped->mapped)");
            pass = pass + 1;
        end else begin
            $display("FAIL: bus_error stuck high after remap — be=%b",
                     bus_error); fail = fail + 1;
        end

        wbm_cyc = 0; wbm_stb = 0;
        #10;
        $display("\n=== wb_interconnect: %0d passed, %0d failed ===", pass, fail);
        if (fail > 0) $display("SOME TESTS FAILED");
        else          $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
