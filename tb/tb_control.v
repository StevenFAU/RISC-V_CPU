// Testbench for Main Decoder (control.v)
//
// Phase 1.1: control.v gained `funct3` input + 5 new outputs (is_csr,
// csr_op, csr_use_imm, illegal_system, illegal_opcode). The legacy 8-signal
// check is preserved; new tests cover SYSTEM-CSR variants, the
// SYSTEM-funct3==0 placeholder, and the unknown-opcode illegal_opcode pulse.
`timescale 1ns/1ps
`include "defines.v"

module tb_control;
    reg  [6:0] opcode;
    reg  [2:0] funct3;
    wire       reg_write, mem_to_reg, mem_write, mem_read, alu_src, branch, jump;
    wire [1:0] alu_op;
    wire       is_csr;
    wire [2:0] csr_op;
    wire       csr_use_imm;
    wire       illegal_system;
    wire       illegal_opcode;

    control uut (
        .opcode(opcode), .funct3(funct3),
        .reg_write(reg_write), .mem_to_reg(mem_to_reg),
        .mem_write(mem_write), .mem_read(mem_read),
        .alu_src(alu_src), .branch(branch), .jump(jump),
        .alu_op(alu_op),
        .is_csr(is_csr), .csr_op(csr_op),
        .csr_use_imm(csr_use_imm),
        .illegal_system(illegal_system),
        .illegal_opcode(illegal_opcode)
    );

    integer pass = 0, fail = 0;

    // Legacy 8-signal check (covers reg_write/mem_to_reg/mem_write/mem_read/
    // alu_src/branch/jump/alu_op). Phase 1.1 outputs verified separately.
    task check_legacy(
        input exp_rw, input exp_m2r, input exp_mw, input exp_mr,
        input exp_as, input exp_br, input exp_jmp, input [1:0] exp_aluop,
        input [8*40-1:0] msg
    );
        begin
            if (reg_write === exp_rw && mem_to_reg === exp_m2r &&
                mem_write === exp_mw && mem_read === exp_mr &&
                alu_src === exp_as && branch === exp_br &&
                jump === exp_jmp && alu_op === exp_aluop) begin
                $display("PASS: %0s", msg);
                pass = pass + 1;
            end else begin
                $display("FAIL: %0s", msg);
                $display("  rw=%b m2r=%b mw=%b mr=%b as=%b br=%b jmp=%b aluop=%b",
                    reg_write, mem_to_reg, mem_write, mem_read, alu_src, branch, jump, alu_op);
                $display("  Expected: rw=%b m2r=%b mw=%b mr=%b as=%b br=%b jmp=%b aluop=%b",
                    exp_rw, exp_m2r, exp_mw, exp_mr, exp_as, exp_br, exp_jmp, exp_aluop);
                fail = fail + 1;
            end
        end
    endtask

    // Phase 1.1 CSR-output check.
    task check_csr(
        input exp_is_csr, input [2:0] exp_csr_op, input exp_use_imm,
        input exp_illegal_sys, input exp_illegal_op,
        input [8*40-1:0] msg
    );
        begin
            if (is_csr === exp_is_csr && csr_op === exp_csr_op &&
                csr_use_imm === exp_use_imm &&
                illegal_system === exp_illegal_sys &&
                illegal_opcode === exp_illegal_op) begin
                $display("PASS: %0s", msg);
                pass = pass + 1;
            end else begin
                $display("FAIL: %0s", msg);
                $display("  is_csr=%b csr_op=%b use_imm=%b ill_sys=%b ill_op=%b",
                    is_csr, csr_op, csr_use_imm, illegal_system, illegal_opcode);
                $display("  Expected: is_csr=%b csr_op=%b use_imm=%b ill_sys=%b ill_op=%b",
                    exp_is_csr, exp_csr_op, exp_use_imm, exp_illegal_sys, exp_illegal_op);
                fail = fail + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_control.vcd");
        $dumpvars(0, tb_control);

        // ---- Legacy opcodes (funct3 = 0 by default; doesn't affect non-SYSTEM) ----
        funct3 = 3'b000;

        //                              rw m2r mw  mr  as  br  jmp aluop
        opcode = `OP_R_TYPE; #10;
        check_legacy(                    1, 0,  0,  0,  0,  0,  0, `ALUOP_R_TYPE,    "R-type");
        check_csr(0, 3'b000, 1'b0, 1'b0, 1'b0,                                       "R-type: no CSR signals");

        opcode = `OP_I_ALU; #10;
        check_legacy(                    1, 0,  0,  0,  1,  0,  0, `ALUOP_I_TYPE,    "I-type ALU");

        opcode = `OP_LOAD; #10;
        check_legacy(                    1, 1,  0,  1,  1,  0,  0, `ALUOP_LOAD_STORE,"Load");

        opcode = `OP_STORE; #10;
        check_legacy(                    0, 0,  1,  0,  1,  0,  0, `ALUOP_LOAD_STORE,"Store");

        opcode = `OP_BRANCH; #10;
        check_legacy(                    0, 0,  0,  0,  0,  1,  0, `ALUOP_BRANCH,    "Branch");

        opcode = `OP_JAL; #10;
        check_legacy(                    1, 0,  0,  0,  0,  0,  1, `ALUOP_LOAD_STORE,"JAL");

        opcode = `OP_JALR; #10;
        check_legacy(                    1, 0,  0,  0,  1,  0,  1, `ALUOP_LOAD_STORE,"JALR");

        opcode = `OP_LUI; #10;
        check_legacy(                    1, 0,  0,  0,  1,  0,  0, `ALUOP_LOAD_STORE,"LUI");

        opcode = `OP_AUIPC; #10;
        check_legacy(                    1, 0,  0,  0,  1,  0,  0, `ALUOP_LOAD_STORE,"AUIPC");

        opcode = `OP_CUSTOM0; #10;
        check_legacy(                    0, 0,  0,  0,  0,  0,  0, `ALUOP_LOAD_STORE,"CUSTOM0 (safe)");
        check_csr(0, 3'b000, 1'b0, 1'b0, 1'b0,                                       "CUSTOM0: no illegal");

        // ---- Phase 1.1: SYSTEM opcode CSR variants ----
        // All SYSTEM CSR ops: reg_write=1, alu_src=0, no mem/branch/jump,
        // alu_op stays at default ALUOP_LOAD_STORE.
        // is_csr=1, csr_op = {0, funct3[1:0]}, csr_use_imm = funct3[2].

        opcode = `OP_SYSTEM; funct3 = 3'b001; #10;  // CSRRW
        check_legacy(                    1, 0,  0,  0,  0,  0,  0, `ALUOP_LOAD_STORE,"CSRRW legacy");
        check_csr(1, 3'b001, 1'b0, 1'b0, 1'b0,                                       "CSRRW: write/no-imm");

        opcode = `OP_SYSTEM; funct3 = 3'b010; #10;  // CSRRS
        check_csr(1, 3'b010, 1'b0, 1'b0, 1'b0,                                       "CSRRS: set/no-imm");

        opcode = `OP_SYSTEM; funct3 = 3'b011; #10;  // CSRRC
        check_csr(1, 3'b011, 1'b0, 1'b0, 1'b0,                                       "CSRRC: clear/no-imm");

        opcode = `OP_SYSTEM; funct3 = 3'b101; #10;  // CSRRWI
        check_csr(1, 3'b001, 1'b1, 1'b0, 1'b0,                                       "CSRRWI: write/imm");

        opcode = `OP_SYSTEM; funct3 = 3'b110; #10;  // CSRRSI
        check_csr(1, 3'b010, 1'b1, 1'b0, 1'b0,                                       "CSRRSI: set/imm");

        opcode = `OP_SYSTEM; funct3 = 3'b111; #10;  // CSRRCI
        check_csr(1, 3'b011, 1'b1, 1'b0, 1'b0,                                       "CSRRCI: clear/imm");

        // ---- Phase 1.1: SYSTEM funct3==0 placeholder (ECALL/EBREAK/MRET/WFI) ----
        opcode = `OP_SYSTEM; funct3 = 3'b000; #10;
        check_legacy(                    0, 0,  0,  0,  0,  0,  0, `ALUOP_LOAD_STORE,"SYSTEM f3=0: no writeback");
        check_csr(0, 3'b000, 1'b0, 1'b1, 1'b0,                                       "SYSTEM f3=0: illegal_system");

        // ---- Phase 1.1: unknown-opcode pulse ----
        // Pick an arbitrary unallocated opcode (custom-1 = 7'b0101011).
        opcode = 7'b0101011; funct3 = 3'b000; #10;
        check_legacy(                    0, 0,  0,  0,  0,  0,  0, `ALUOP_LOAD_STORE,"Unknown opcode: safe defaults");
        check_csr(0, 3'b000, 1'b0, 1'b0, 1'b1,                                       "Unknown opcode: illegal_opcode");

        // Verify CUSTOM0 still does NOT pulse illegal_opcode (reserved, not illegal).
        opcode = `OP_CUSTOM0; funct3 = 3'b000; #10;
        check_csr(0, 3'b000, 1'b0, 1'b0, 1'b0,                                       "CUSTOM0: reserved, not illegal");

        $display("\n--- Control Tests: %0d passed, %0d failed ---", pass, fail);
        if (fail > 0) $display("*** SOME TESTS FAILED ***");
        else $display("*** ALL TESTS PASSED ***");
        $finish;
    end
endmodule
