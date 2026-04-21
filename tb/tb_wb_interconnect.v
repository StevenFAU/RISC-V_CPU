// Testbench — wb_interconnect
// Verifies address decode steers to correct slave and muxes responses.
//
// Phase 0.1 (2026-04-21): tests 8–12 added to cover the tightened UART/GPIO/
// TIMER decodes. Out-of-range peripheral-window accesses must fall through
// to the unmapped path (no slave cyc, no ack). In-range boundary accesses
// for GPIO and TIMER are exercised to confirm the new windows are correct.
`timescale 1ns / 1ps

module tb_wb_interconnect;

    reg         wbm_cyc, wbm_stb, wbm_we;
    reg  [31:0] wbm_adr, wbm_dat;
    reg  [3:0]  wbm_sel;
    wire [31:0] wbm_dat_o;
    wire        wbm_ack_o;
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
        .wbs3_dat_i(wbs3_dat_i), .wbs3_ack_i(wbs3_ack_i)
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
        if (wbs0_cyc === 1 && wbs1_cyc === 0 && wbm_dat_o === 32'hBEEF_CAFE && wbm_ack_o === 1) begin
            $display("PASS: DMEM addr selects slave 0"); pass = pass + 1;
        end else begin
            $display("FAIL: DMEM addr"); fail = fail + 1;
        end

        // === Test 2: UART address — slave 1 selected ===
        wbm_adr = 32'h8000_0004;
        wbs0_dat_i = 32'h0; wbs0_ack_i = 0;
        wbs1_dat_i = 32'h0000_0001; wbs1_ack_i = 1;
        #1;
        if (wbs1_cyc === 1 && wbs0_cyc === 0 && wbm_dat_o === 32'h0000_0001 && wbm_ack_o === 1) begin
            $display("PASS: UART addr selects slave 1"); pass = pass + 1;
        end else begin
            $display("FAIL: UART addr — s1_cyc=%b s0_cyc=%b dat=%h ack=%b",
                     wbs1_cyc, wbs0_cyc, wbm_dat_o, wbm_ack_o); fail = fail + 1;
        end

        // === Test 3: Unmapped address — no slave selected ===
        wbm_adr = 32'h0002_0000;
        wbs0_ack_i = 1; wbs1_ack_i = 1;
        #1;
        if (wbs0_cyc === 0 && wbs1_cyc === 0 && wbm_ack_o === 0 && wbm_dat_o === 32'd0) begin
            $display("PASS: Unmapped addr — no slave, no ack"); pass = pass + 1;
        end else begin
            $display("FAIL: Unmapped addr"); fail = fail + 1;
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
        // Phase 0.1 new tests (8–12) — tightened UART/GPIO/TIMER decodes
        // =====================================================================

        // Common state for fall-through tests: all slaves ack-high so we can
        // prove the interconnect is the thing gating cyc/ack, not the slave.
        wbs0_ack_i = 1; wbs1_ack_i = 1; wbs2_ack_i = 1; wbs3_ack_i = 1;
        wbm_we = 0; wbm_sel = 4'b1111;

        // === Test 8: UART out-of-range access falls through ===
        // 0x80000010 was inside the old 4 KB UART page; the new decode stops
        // at 0x8000000F. Must now land in the unmapped path.
        wbm_adr = 32'h8000_0010;
        #1;
        if (wbs1_cyc === 0 && wbm_ack_o === 0 && wbm_dat_o === 32'd0) begin
            $display("PASS: UART out-of-range (0x80000010) -> unmapped"); pass = pass + 1;
        end else begin
            $display("FAIL: UART out-of-range still hits slave — s1_cyc=%b ack=%b dat=%h",
                     wbs1_cyc, wbm_ack_o, wbm_dat_o); fail = fail + 1;
        end

        // === Test 9: GPIO out-of-range access falls through ===
        // 0x80001008 was inside the old 4 KB GPIO page; new decode stops at
        // 0x80001007 (2 registers).
        wbm_adr = 32'h8000_1008;
        #1;
        if (wbs2_cyc === 0 && wbm_ack_o === 0 && wbm_dat_o === 32'd0) begin
            $display("PASS: GPIO out-of-range (0x80001008) -> unmapped"); pass = pass + 1;
        end else begin
            $display("FAIL: GPIO out-of-range still hits slave — s2_cyc=%b ack=%b dat=%h",
                     wbs2_cyc, wbm_ack_o, wbm_dat_o); fail = fail + 1;
        end

        // === Test 10: GPIO in-range boundaries still hit slave ===
        wbs2_dat_i = 32'hAAAA_5555;
        wbm_adr = 32'h8000_1000;
        #1;
        if (wbs2_cyc === 1 && wbm_ack_o === 1 && wbm_dat_o === 32'hAAAA_5555) begin
            $display("PASS: GPIO in-range low  (0x80001000) -> slave 2"); pass = pass + 1;
        end else begin
            $display("FAIL: GPIO in-range low — s2_cyc=%b ack=%b dat=%h",
                     wbs2_cyc, wbm_ack_o, wbm_dat_o); fail = fail + 1;
        end
        wbm_adr = 32'h8000_1004;
        #1;
        if (wbs2_cyc === 1 && wbm_ack_o === 1 && wbm_dat_o === 32'hAAAA_5555) begin
            $display("PASS: GPIO in-range high (0x80001004) -> slave 2"); pass = pass + 1;
        end else begin
            $display("FAIL: GPIO in-range high — s2_cyc=%b ack=%b dat=%h",
                     wbs2_cyc, wbm_ack_o, wbm_dat_o); fail = fail + 1;
        end

        // === Test 11: Timer out-of-range access falls through ===
        // 0x80002010 was inside the old 4 KB timer page; new decode stops at
        // 0x8000200F (4 registers).
        wbs2_dat_i = 32'd0;
        wbm_adr = 32'h8000_2010;
        #1;
        if (wbs3_cyc === 0 && wbm_ack_o === 0 && wbm_dat_o === 32'd0) begin
            $display("PASS: TIMER out-of-range (0x80002010) -> unmapped"); pass = pass + 1;
        end else begin
            $display("FAIL: TIMER out-of-range still hits slave — s3_cyc=%b ack=%b dat=%h",
                     wbs3_cyc, wbm_ack_o, wbm_dat_o); fail = fail + 1;
        end

        // === Test 12: Timer in-range boundaries still hit slave ===
        wbs3_dat_i = 32'hF00D_1234;
        wbm_adr = 32'h8000_2000;
        #1;
        if (wbs3_cyc === 1 && wbm_ack_o === 1 && wbm_dat_o === 32'hF00D_1234) begin
            $display("PASS: TIMER in-range low  (0x80002000) -> slave 3"); pass = pass + 1;
        end else begin
            $display("FAIL: TIMER in-range low — s3_cyc=%b ack=%b dat=%h",
                     wbs3_cyc, wbm_ack_o, wbm_dat_o); fail = fail + 1;
        end
        wbm_adr = 32'h8000_200C;
        #1;
        if (wbs3_cyc === 1 && wbm_ack_o === 1 && wbm_dat_o === 32'hF00D_1234) begin
            $display("PASS: TIMER in-range high (0x8000200C) -> slave 3"); pass = pass + 1;
        end else begin
            $display("FAIL: TIMER in-range high — s3_cyc=%b ack=%b dat=%h",
                     wbs3_cyc, wbm_ack_o, wbm_dat_o); fail = fail + 1;
        end

        wbm_cyc = 0; wbm_stb = 0;
        #10;
        $display("\n=== wb_interconnect: %0d passed, %0d failed ===", pass, fail);
        if (fail > 0) $display("SOME TESTS FAILED");
        else          $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
