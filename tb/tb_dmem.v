// Testbench for Data Memory
`timescale 1ns/1ps

module tb_dmem;
    reg         clk;
    reg         mem_read, mem_write;
    reg  [2:0]  funct3;
    reg  [31:0] addr, write_data;
    wire [31:0] read_data;

    dmem #(.DEPTH(256)) uut (
        .clk(clk), .mem_read(mem_read), .mem_write(mem_write),
        .funct3(funct3), .addr(addr), .write_data(write_data),
        .read_data(read_data)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass = 0, fail = 0;

    task check(input [31:0] expected, input [8*48-1:0] msg);
        begin
            if (read_data === expected) begin
                $display("PASS: %0s — data = 0x%08h", msg, read_data);
                pass = pass + 1;
            end else begin
                $display("FAIL: %0s — Expected 0x%08h, Got 0x%08h", msg, expected, read_data);
                fail = fail + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_dmem.vcd");
        $dumpvars(0, tb_dmem);

        mem_read = 0; mem_write = 0;

        // Test 1: Word write then word read
        mem_write = 1; funct3 = 3'b010; addr = 32'd0; write_data = 32'hDEADBEEF;
        @(posedge clk); #1;
        mem_write = 0; mem_read = 1; funct3 = 3'b010; addr = 32'd0; #1;
        check(32'hDEADBEEF, "SW then LW");

        // Test 2: Byte write then byte read (signed)
        mem_write = 1; mem_read = 0; funct3 = 3'b000; addr = 32'd16; write_data = 32'h000000F5;
        @(posedge clk); #1;
        mem_write = 0; mem_read = 1; funct3 = 3'b000; addr = 32'd16; #1;
        check(32'hFFFFFFF5, "SB then LB (sign-extended, 0xF5 -> -11)");

        // Test 3: Byte read unsigned
        funct3 = 3'b100; addr = 32'd16; #1;
        check(32'h000000F5, "LBU (zero-extended, 0xF5)");

        // Test 4: Halfword write then read (signed)
        mem_write = 1; mem_read = 0; funct3 = 3'b001; addr = 32'd32; write_data = 32'h0000ABCD;
        @(posedge clk); #1;
        mem_write = 0; mem_read = 1; funct3 = 3'b001; addr = 32'd32; #1;
        check(32'hFFFFABCD, "SH then LH (sign-extended, 0xABCD)");

        // Test 5: Halfword read unsigned
        funct3 = 3'b101; addr = 32'd32; #1;
        check(32'h0000ABCD, "LHU (zero-extended, 0xABCD)");

        // Test 6: Positive half (no sign extension)
        mem_write = 1; mem_read = 0; funct3 = 3'b001; addr = 32'd48; write_data = 32'h00001234;
        @(posedge clk); #1;
        mem_write = 0; mem_read = 1; funct3 = 3'b001; addr = 32'd48; #1;
        check(32'h00001234, "SH then LH (positive half, no sign ext)");

        // Test 7: Verify little-endian byte order
        mem_write = 1; mem_read = 0; funct3 = 3'b010; addr = 32'd64; write_data = 32'h04030201;
        @(posedge clk); #1;
        mem_write = 0; mem_read = 1; funct3 = 3'b100; addr = 32'd64; #1;
        check(32'h00000001, "LBU byte[0] of 0x04030201");
        funct3 = 3'b100; addr = 32'd65; #1;
        check(32'h00000002, "LBU byte[1] of 0x04030201");
        funct3 = 3'b100; addr = 32'd66; #1;
        check(32'h00000003, "LBU byte[2] of 0x04030201");
        funct3 = 3'b100; addr = 32'd67; #1;
        check(32'h00000004, "LBU byte[3] of 0x04030201");

        $display("\n--- DMEM Tests: %0d passed, %0d failed ---", pass, fail);
        if (fail > 0) $display("*** SOME TESTS FAILED ***");
        else $display("*** ALL TESTS PASSED ***");
        $finish;
    end
endmodule
