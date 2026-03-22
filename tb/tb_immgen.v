// Testbench for Immediate Generator
`timescale 1ns/1ps

module tb_immgen;
    reg  [31:0] instr;
    wire [31:0] imm;

    immgen uut (.instr(instr), .imm(imm));

    integer pass = 0, fail = 0;

    task check(input [31:0] expected, input [8*48-1:0] msg);
        begin
            if (imm === expected) begin
                $display("PASS: %0s — imm = 0x%08h (%0d)", msg, imm, $signed(imm));
                pass = pass + 1;
            end else begin
                $display("FAIL: %0s — Expected 0x%08h, Got 0x%08h", msg, expected, imm);
                fail = fail + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_immgen.vcd");
        $dumpvars(0, tb_immgen);

        // I-type: ADDI x1, x0, 5 -> imm = 5
        // Encoding: imm[11:0]=000000000101, rs1=00000, f3=000, rd=00001, op=0010011
        instr = 32'h00500093; #10;
        check(32'd5, "I-type positive: ADDI x1,x0,5");

        // I-type negative: ADDI x1, x0, -1 -> imm = 0xFFF = -1 sign-extended
        // imm[11:0]=111111111111
        instr = 32'hFFF00093; #10;
        check(32'hFFFFFFFF, "I-type negative: ADDI x1,x0,-1");

        // S-type: SW x2, 8(x1) -> imm = 8
        // imm[11:5]=0000000, rs2=00010, rs1=00001, f3=010, imm[4:0]=01000, op=0100011
        instr = 32'h0020A423; #10;
        check(32'd8, "S-type positive: SW x2,8(x1)");

        // S-type negative: SW x2, -4(x1) -> imm = -4
        // imm = 0xFFC = 111111111100
        instr = 32'hFE20AE23; #10;
        check(32'hFFFFFFFC, "S-type negative: SW x2,-4(x1)");

        // B-type: BEQ x0, x0, +8 -> imm = 8
        // imm[12|10:5]=0000000, rs2=00000, rs1=00000, f3=000, imm[4:1|11]=01000, op=1100011
        instr = 32'h00000463; #10;
        check(32'd8, "B-type positive: BEQ +8");

        // B-type negative: BEQ x0, x0, -8 -> imm = -8
        instr = 32'hFE000CE3; #10;
        check(32'hFFFFFFF8, "B-type negative: BEQ -8");

        // U-type: LUI x1, 0xDEADB -> imm = 0xDEADB000
        instr = 32'hDEADB0B7; #10;
        check(32'hDEADB000, "U-type: LUI 0xDEADB");

        // J-type: JAL x1, +8 -> imm = 8
        // imm[20|10:1|11|19:12]
        instr = 32'h008000EF; #10;
        check(32'd8, "J-type positive: JAL +8");

        // J-type negative: JAL x1, -4
        instr = 32'hFFDFF0EF; #10;
        check(32'hFFFFFFFC, "J-type negative: JAL -4");

        $display("\n--- ImmGen Tests: %0d passed, %0d failed ---", pass, fail);
        if (fail > 0) $display("*** SOME TESTS FAILED ***");
        else $display("*** ALL TESTS PASSED ***");
        $finish;
    end
endmodule
