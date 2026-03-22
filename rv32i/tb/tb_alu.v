// Testbench for ALU — tests all 10 operations with edge cases
`timescale 1ns/1ps

module tb_alu;
    reg  [31:0] a, b;
    reg  [3:0]  alu_op;
    wire [31:0] result;
    wire        zero;

    alu uut (.a(a), .b(b), .alu_op(alu_op), .result(result), .zero(zero));

    integer pass = 0, fail = 0;

    task check(input [31:0] expected, input expected_zero, input [8*48-1:0] msg);
        begin
            if (result === expected && zero === expected_zero) begin
                $display("PASS: %0s", msg);
                pass = pass + 1;
            end else begin
                $display("FAIL: %0s — Expected 0x%08h (z=%0b), Got 0x%08h (z=%0b)",
                    msg, expected, expected_zero, result, zero);
                fail = fail + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_alu.vcd");
        $dumpvars(0, tb_alu);

        // --- ADD ---
        a = 32'd10; b = 32'd20; alu_op = 4'b0000; #10;
        check(32'd30, 0, "ADD: 10 + 20 = 30");

        a = 32'h7FFFFFFF; b = 32'd1; alu_op = 4'b0000; #10;
        check(32'h80000000, 0, "ADD: overflow MAX_INT + 1");

        // --- SUB ---
        a = 32'd30; b = 32'd10; alu_op = 4'b0001; #10;
        check(32'd20, 0, "SUB: 30 - 10 = 20");

        a = 32'd5; b = 32'd5; alu_op = 4'b0001; #10;
        check(32'd0, 1, "SUB: 5 - 5 = 0 (zero flag)");

        a = 32'd0; b = 32'd1; alu_op = 4'b0001; #10;
        check(32'hFFFFFFFF, 0, "SUB: 0 - 1 = -1 (underflow)");

        // --- AND ---
        a = 32'hFF00FF00; b = 32'h0F0F0F0F; alu_op = 4'b0010; #10;
        check(32'h0F000F00, 0, "AND");

        // --- OR ---
        a = 32'hFF00FF00; b = 32'h0F0F0F0F; alu_op = 4'b0011; #10;
        check(32'hFF0FFF0F, 0, "OR");

        // --- XOR ---
        a = 32'hFF00FF00; b = 32'h0F0F0F0F; alu_op = 4'b0100; #10;
        check(32'hF00FF00F, 0, "XOR");

        // --- SLL ---
        a = 32'h0000_0001; b = 32'd4; alu_op = 4'b0101; #10;
        check(32'h0000_0010, 0, "SLL: 1 << 4 = 16");

        a = 32'h8000_0000; b = 32'd1; alu_op = 4'b0101; #10;
        check(32'h0000_0000, 1, "SLL: shift out MSB");

        // --- SRL ---
        a = 32'h8000_0000; b = 32'd4; alu_op = 4'b0110; #10;
        check(32'h0800_0000, 0, "SRL: zero fill from left");

        // --- SRA ---
        a = 32'h8000_0000; b = 32'd4; alu_op = 4'b0111; #10;
        check(32'hF800_0000, 0, "SRA: sign extension from left");

        a = 32'h4000_0000; b = 32'd4; alu_op = 4'b0111; #10;
        check(32'h0400_0000, 0, "SRA: positive number, zero fill");

        // --- SLT (signed) ---
        a = 32'hFFFF_FFFF; b = 32'd1; alu_op = 4'b1000; #10;  // -1 < 1
        check(32'd1, 0, "SLT: -1 < 1 (signed)");

        a = 32'd1; b = 32'hFFFF_FFFF; alu_op = 4'b1000; #10;  // 1 < -1? No
        check(32'd0, 1, "SLT: 1 not < -1 (signed)");

        a = 32'd5; b = 32'd5; alu_op = 4'b1000; #10;  // equal
        check(32'd0, 1, "SLT: equal values");

        a = 32'h7FFFFFFF; b = 32'h80000000; alu_op = 4'b1000; #10; // MAX > MIN
        check(32'd0, 1, "SLT: MAX_INT not < MIN_INT");

        // --- SLTU (unsigned) ---
        a = 32'hFFFF_FFFF; b = 32'd1; alu_op = 4'b1001; #10;  // 0xFFFFFFFF > 1
        check(32'd0, 1, "SLTU: 0xFFFFFFFF not < 1 (unsigned)");

        a = 32'd0; b = 32'hFFFF_FFFF; alu_op = 4'b1001; #10;  // 0 < 0xFFFFFFFF
        check(32'd1, 0, "SLTU: 0 < 0xFFFFFFFF (unsigned)");

        a = 32'd0; b = 32'd0; alu_op = 4'b1001; #10;
        check(32'd0, 1, "SLTU: 0 not < 0");

        $display("\n--- ALU Tests: %0d passed, %0d failed ---", pass, fail);
        if (fail > 0) $display("*** SOME TESTS FAILED ***");
        else $display("*** ALL TESTS PASSED ***");
        $finish;
    end
endmodule
