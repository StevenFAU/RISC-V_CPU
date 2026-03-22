// Testbench for Instruction Memory
`timescale 1ns/1ps

module tb_imem;
    reg  [31:0] addr;
    wire [31:0] instr;

    imem #(.DEPTH(16)) uut (.addr(addr), .instr(instr));

    integer pass = 0, fail = 0;

    task check(input [31:0] expected, input [8*40-1:0] msg);
        begin
            if (instr === expected) begin
                $display("PASS: %0s — instr = 0x%08h", msg, instr);
                pass = pass + 1;
            end else begin
                $display("FAIL: %0s — Expected 0x%08h, Got 0x%08h", msg, expected, instr);
                fail = fail + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_imem.vcd");
        $dumpvars(0, tb_imem);

        // Preload memory with test data
        uut.mem[0]  = 32'h00500093; // ADDI x1, x0, 5
        uut.mem[1]  = 32'h00A00113; // ADDI x2, x0, 10
        uut.mem[2]  = 32'h002081B3; // ADD  x3, x1, x2
        uut.mem[3]  = 32'hDEADBEEF; // Test pattern
        uut.mem[15] = 32'hCAFEBABE; // Last word

        #10;
        // Test byte-address 0 -> word 0
        addr = 32'h0000_0000; #10;
        check(32'h00500093, "Addr 0x00: ADDI x1");

        // Test byte-address 4 -> word 1
        addr = 32'h0000_0004; #10;
        check(32'h00A00113, "Addr 0x04: ADDI x2");

        // Test byte-address 8 -> word 2
        addr = 32'h0000_0008; #10;
        check(32'h002081B3, "Addr 0x08: ADD x3");

        // Test byte-address 12 -> word 3
        addr = 32'h0000_000C; #10;
        check(32'hDEADBEEF, "Addr 0x0C: Test pattern");

        // Test last address: byte-address 60 -> word 15
        addr = 32'h0000_003C; #10;
        check(32'hCAFEBABE, "Addr 0x3C: Last word");

        $display("\n--- IMEM Tests: %0d passed, %0d failed ---", pass, fail);
        if (fail > 0) $display("*** SOME TESTS FAILED ***");
        else $display("*** ALL TESTS PASSED ***");
        $finish;
    end
endmodule
