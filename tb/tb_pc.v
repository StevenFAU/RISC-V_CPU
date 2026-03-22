// Testbench for Program Counter
`timescale 1ns/1ps

module tb_pc;
    reg        clk, rst;
    reg [31:0] pc_next;
    wire [31:0] pc;

    pc uut (.clk(clk), .rst(rst), .pc_next(pc_next), .pc(pc));

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass = 0, fail = 0;

    task check(input [31:0] expected, input [8*32-1:0] msg);
        begin
            if (pc === expected) begin
                $display("PASS: %0s — PC = 0x%08h", msg, pc);
                pass = pass + 1;
            end else begin
                $display("FAIL: %0s — Expected 0x%08h, Got 0x%08h", msg, expected, pc);
                fail = fail + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_pc.vcd");
        $dumpvars(0, tb_pc);

        // Test 1: Assert reset and wait for it to take effect
        rst = 1; pc_next = 32'h0;
        @(posedge clk); @(negedge clk);
        check(32'h0000_0000, "Reset to 0");

        // Test 2: Release reset, load sequential address
        rst = 0; pc_next = 32'h0000_0004;
        @(posedge clk); @(negedge clk);
        check(32'h0000_0004, "Sequential PC+4");

        // Test 3: Another increment
        pc_next = 32'h0000_0008;
        @(posedge clk); @(negedge clk);
        check(32'h0000_0008, "Sequential PC+8");

        // Test 4: Branch target
        pc_next = 32'h0000_0100;
        @(posedge clk); @(negedge clk);
        check(32'h0000_0100, "Branch target load");

        // Test 5: Reset during operation
        rst = 1;
        @(posedge clk); @(negedge clk);
        check(32'h0000_0000, "Reset during operation");

        $display("\n--- PC Tests: %0d passed, %0d failed ---", pass, fail);
        if (fail > 0) $display("*** SOME TESTS FAILED ***");
        else $display("*** ALL TESTS PASSED ***");
        $finish;
    end
endmodule
