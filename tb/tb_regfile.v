// Testbench for Register File
`timescale 1ns/1ps

module tb_regfile;
    reg         clk, we;
    reg  [4:0]  rs1_addr, rs2_addr, rd_addr;
    reg  [31:0] rd_data;
    wire [31:0] rs1_data, rs2_data;

    regfile uut (
        .clk(clk), .we(we),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
        .rd_addr(rd_addr), .rd_data(rd_data),
        .rs1_data(rs1_data), .rs2_data(rs2_data)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass = 0, fail = 0;

    task check_rs1(input [31:0] expected, input [8*40-1:0] msg);
        begin
            if (rs1_data === expected) begin
                $display("PASS: %0s — rs1 = 0x%08h", msg, rs1_data);
                pass = pass + 1;
            end else begin
                $display("FAIL: %0s — Expected 0x%08h, Got 0x%08h", msg, expected, rs1_data);
                fail = fail + 1;
            end
        end
    endtask

    task check_rs2(input [31:0] expected, input [8*40-1:0] msg);
        begin
            if (rs2_data === expected) begin
                $display("PASS: %0s — rs2 = 0x%08h", msg, rs2_data);
                pass = pass + 1;
            end else begin
                $display("FAIL: %0s — Expected 0x%08h, Got 0x%08h", msg, expected, rs2_data);
                fail = fail + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_regfile.vcd");
        $dumpvars(0, tb_regfile);

        // Initialize
        we = 0; rs1_addr = 0; rs2_addr = 0; rd_addr = 0; rd_data = 0;

        // Test 1: x0 reads zero
        rs1_addr = 5'd0; #1;
        check_rs1(32'd0, "x0 reads zero");

        // Test 2: Write to x1, then read
        we = 1; rd_addr = 5'd1; rd_data = 32'hAABBCCDD;
        @(posedge clk); #1;
        we = 0; rs1_addr = 5'd1; #1;
        check_rs1(32'hAABBCCDD, "Write x1 then read");

        // Test 3: Write to x0 should be ignored
        we = 1; rd_addr = 5'd0; rd_data = 32'hFFFFFFFF;
        @(posedge clk); #1;
        we = 0; rs1_addr = 5'd0; #1;
        check_rs1(32'd0, "x0 still zero after write");

        // Test 4: Both read ports simultaneously
        we = 1; rd_addr = 5'd2; rd_data = 32'h12345678;
        @(posedge clk); #1;
        we = 0; rs1_addr = 5'd1; rs2_addr = 5'd2; #1;
        check_rs1(32'hAABBCCDD, "Dual read port1 (x1)");
        check_rs2(32'h12345678, "Dual read port2 (x2)");

        // Test 5: Write to x31 (highest register)
        we = 1; rd_addr = 5'd31; rd_data = 32'hDEADBEEF;
        @(posedge clk); #1;
        we = 0; rs1_addr = 5'd31; #1;
        check_rs1(32'hDEADBEEF, "Write/read x31");

        $display("\n--- Regfile Tests: %0d passed, %0d failed ---", pass, fail);
        if (fail > 0) $display("*** SOME TESTS FAILED ***");
        else $display("*** ALL TESTS PASSED ***");
        $finish;
    end
endmodule
