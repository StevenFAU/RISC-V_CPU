// Testbench for Main Decoder (control.v)
`timescale 1ns/1ps
`include "defines.v"

module tb_control;
    reg  [6:0] opcode;
    wire       reg_write, mem_to_reg, mem_write, mem_read, alu_src, branch, jump;
    wire [1:0] alu_op;

    control uut (
        .opcode(opcode),
        .reg_write(reg_write), .mem_to_reg(mem_to_reg),
        .mem_write(mem_write), .mem_read(mem_read),
        .alu_src(alu_src), .branch(branch), .jump(jump),
        .alu_op(alu_op)
    );

    integer pass = 0, fail = 0;

    task check(
        input exp_rw, input exp_m2r, input exp_mw, input exp_mr,
        input exp_as, input exp_br, input exp_jmp, input [1:0] exp_aluop,
        input [8*20-1:0] msg
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

    initial begin
        $dumpfile("sim/tb_control.vcd");
        $dumpvars(0, tb_control);

        //                            rw m2r mw  mr  as  br  jmp aluop
        opcode = `OP_R_TYPE; #10;
        check(                         1, 0,  0,  0,  0,  0,  0, `ALUOP_R_TYPE, "R-type");

        opcode = `OP_I_ALU; #10;
        check(                         1, 0,  0,  0,  1,  0,  0, `ALUOP_I_TYPE, "I-type ALU");

        opcode = `OP_LOAD; #10;
        check(                         1, 1,  0,  1,  1,  0,  0, `ALUOP_LOAD_STORE, "Load");

        opcode = `OP_STORE; #10;
        check(                         0, 0,  1,  0,  1,  0,  0, `ALUOP_LOAD_STORE, "Store");

        opcode = `OP_BRANCH; #10;
        check(                         0, 0,  0,  0,  0,  1,  0, `ALUOP_BRANCH, "Branch");

        opcode = `OP_JAL; #10;
        check(                         1, 0,  0,  0,  0,  0,  1, `ALUOP_LOAD_STORE, "JAL");

        opcode = `OP_JALR; #10;
        check(                         1, 0,  0,  0,  1,  0,  1, `ALUOP_LOAD_STORE, "JALR");

        opcode = `OP_LUI; #10;
        check(                         1, 0,  0,  0,  1,  0,  0, `ALUOP_LOAD_STORE, "LUI");

        opcode = `OP_AUIPC; #10;
        check(                         1, 0,  0,  0,  1,  0,  0, `ALUOP_LOAD_STORE, "AUIPC");

        opcode = `OP_CUSTOM0; #10;
        check(                         0, 0,  0,  0,  0,  0,  0, `ALUOP_LOAD_STORE, "CUSTOM0 (safe)");

        $display("\n--- Control Tests: %0d passed, %0d failed ---", pass, fail);
        if (fail > 0) $display("*** SOME TESTS FAILED ***");
        else $display("*** ALL TESTS PASSED ***");
        $finish;
    end
endmodule
