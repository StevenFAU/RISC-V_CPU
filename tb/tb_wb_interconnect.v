// Testbench — wb_interconnect
// Verifies address decode steers to correct slave and muxes responses.
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

    integer pass = 0, fail = 0;

    wb_interconnect uut (
        .wbm_cyc_i(wbm_cyc), .wbm_stb_i(wbm_stb), .wbm_we_i(wbm_we),
        .wbm_adr_i(wbm_adr), .wbm_dat_i(wbm_dat), .wbm_sel_i(wbm_sel),
        .wbm_dat_o(wbm_dat_o), .wbm_ack_o(wbm_ack_o),
        .wbm_funct3_i(wbm_funct3),
        .wbs0_cyc_o(wbs0_cyc), .wbs0_stb_o(wbs0_stb), .wbs0_we_o(wbs0_we),
        .wbs0_adr_o(wbs0_adr), .wbs0_dat_o(wbs0_dat), .wbs0_sel_o(wbs0_sel),
        .wbs0_dat_i(wbs0_dat_i), .wbs0_ack_i(wbs0_ack_i),
        .wbs0_funct3_o(wbs0_funct3)
    );

    initial begin
        wbm_cyc = 0; wbm_stb = 0; wbm_we = 0;
        wbm_adr = 0; wbm_dat = 0; wbm_sel = 0; wbm_funct3 = 0;
        wbs0_dat_i = 0; wbs0_ack_i = 0;
        #10;

        // === Test 1: DMEM address — slave 0 selected ===
        wbm_cyc = 1; wbm_stb = 1; wbm_we = 0;
        wbm_adr = 32'h0001_0100; wbm_sel = 4'b1111;
        wbs0_dat_i = 32'hBEEF_CAFE; wbs0_ack_i = 1;
        #1;
        if (wbs0_cyc === 1 && wbs0_stb === 1 && wbm_dat_o === 32'hBEEF_CAFE && wbm_ack_o === 1) begin
            $display("PASS: DMEM addr selects slave 0"); pass = pass + 1;
        end else begin
            $display("FAIL: DMEM addr — cyc=%b stb=%b dat=%h ack=%b",
                     wbs0_cyc, wbs0_stb, wbm_dat_o, wbm_ack_o); fail = fail + 1;
        end

        // === Test 2: Unmapped address — no slave selected ===
        wbm_adr = 32'h0002_0000;
        wbs0_ack_i = 1;
        #1;
        if (wbs0_cyc === 0 && wbs0_stb === 0 && wbm_ack_o === 0 && wbm_dat_o === 32'd0) begin
            $display("PASS: Unmapped addr — no slave, no ack"); pass = pass + 1;
        end else begin
            $display("FAIL: Unmapped addr — cyc=%b stb=%b ack=%b dat=%h",
                     wbs0_cyc, wbs0_stb, wbm_ack_o, wbm_dat_o); fail = fail + 1;
        end

        // === Test 3: UART address space (future) — currently unmapped ===
        wbm_adr = 32'h8000_0000;
        #1;
        if (wbs0_cyc === 0 && wbm_ack_o === 0) begin
            $display("PASS: UART addr unmapped in Phase 1"); pass = pass + 1;
        end else begin
            $display("FAIL: UART addr should be unmapped"); fail = fail + 1;
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
            $display("PASS: sel passthrough"); pass = pass + 1;
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

        wbm_cyc = 0; wbm_stb = 0;
        #10;
        $display("\n=== wb_interconnect: %0d passed, %0d failed ===", pass, fail);
        if (fail > 0) $display("SOME TESTS FAILED");
        else          $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
