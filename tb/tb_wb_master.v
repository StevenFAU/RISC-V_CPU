// Testbench — wb_master
// Verifies Wishbone signal generation from core dmem bus signals.
`timescale 1ns / 1ps
`include "defines.v"

module tb_wb_master;

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

    integer pass = 0, fail = 0;

    wb_master uut (
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_we(dmem_we), .dmem_re(dmem_re),
        .dmem_funct3(dmem_funct3), .dmem_rdata(dmem_rdata),
        .wb_cyc_o(wb_cyc_o), .wb_stb_o(wb_stb_o), .wb_we_o(wb_we_o),
        .wb_adr_o(wb_adr_o), .wb_dat_o(wb_dat_o), .wb_sel_o(wb_sel_o),
        .wb_dat_i(wb_dat_i), .wb_ack_i(wb_ack_i),
        .wb_funct3_o(wb_funct3_o)
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

    initial begin
        dmem_we = 0; dmem_re = 0; dmem_addr = 0; dmem_wdata = 0;
        dmem_funct3 = 0; wb_dat_i = 0; wb_ack_i = 0;
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

        #10;
        $display("\n=== wb_master: %0d passed, %0d failed ===", pass, fail);
        if (fail > 0) $display("SOME TESTS FAILED");
        else          $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
