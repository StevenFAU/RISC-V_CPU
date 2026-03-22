// Testbench for ALU Decoder
`timescale 1ns/1ps
`include "defines.v"

module tb_alu_decoder;
    reg  [1:0] alu_op;
    reg  [2:0] funct3;
    reg        funct7_bit30;
    wire [3:0] alu_control;

    alu_decoder uut (
        .alu_op(alu_op), .funct3(funct3),
        .funct7_bit30(funct7_bit30), .alu_control(alu_control)
    );

    integer pass = 0, fail = 0;

    task check(input [3:0] expected, input [8*32-1:0] msg);
        begin
            if (alu_control === expected) begin
                $display("PASS: %0s — alu_ctrl = %04b", msg, alu_control);
                pass = pass + 1;
            end else begin
                $display("FAIL: %0s — Expected %04b, Got %04b", msg, expected, alu_control);
                fail = fail + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_alu_decoder.vcd");
        $dumpvars(0, tb_alu_decoder);

        // Load/Store: always ADD
        alu_op = `ALUOP_LOAD_STORE; funct3 = 3'b000; funct7_bit30 = 0; #10;
        check(`ALU_ADD, "Load/Store -> ADD");

        // Branch: always SUB
        alu_op = `ALUOP_BRANCH; funct3 = 3'b000; funct7_bit30 = 0; #10;
        check(`ALU_SUB, "Branch -> SUB");

        // R-type: all 10 operations
        alu_op = `ALUOP_R_TYPE;

        funct3 = `F3_ADD_SUB; funct7_bit30 = 0; #10;
        check(`ALU_ADD, "R: ADD");

        funct3 = `F3_ADD_SUB; funct7_bit30 = 1; #10;
        check(`ALU_SUB, "R: SUB");

        funct3 = `F3_SLL; funct7_bit30 = 0; #10;
        check(`ALU_SLL, "R: SLL");

        funct3 = `F3_SLT; funct7_bit30 = 0; #10;
        check(`ALU_SLT, "R: SLT");

        funct3 = `F3_SLTU; funct7_bit30 = 0; #10;
        check(`ALU_SLTU, "R: SLTU");

        funct3 = `F3_XOR; funct7_bit30 = 0; #10;
        check(`ALU_XOR, "R: XOR");

        funct3 = `F3_SRL_SRA; funct7_bit30 = 0; #10;
        check(`ALU_SRL, "R: SRL");

        funct3 = `F3_SRL_SRA; funct7_bit30 = 1; #10;
        check(`ALU_SRA, "R: SRA");

        funct3 = `F3_OR; funct7_bit30 = 0; #10;
        check(`ALU_OR, "R: OR");

        funct3 = `F3_AND; funct7_bit30 = 0; #10;
        check(`ALU_AND, "R: AND");

        // I-type: key operations
        alu_op = `ALUOP_I_TYPE;

        funct3 = `F3_ADD_SUB; funct7_bit30 = 0; #10;
        check(`ALU_ADD, "I: ADDI");

        funct3 = `F3_SLT; funct7_bit30 = 0; #10;
        check(`ALU_SLT, "I: SLTI");

        funct3 = `F3_SLTU; funct7_bit30 = 0; #10;
        check(`ALU_SLTU, "I: SLTIU");

        funct3 = `F3_XOR; funct7_bit30 = 0; #10;
        check(`ALU_XOR, "I: XORI");

        funct3 = `F3_OR; funct7_bit30 = 0; #10;
        check(`ALU_OR, "I: ORI");

        funct3 = `F3_AND; funct7_bit30 = 0; #10;
        check(`ALU_AND, "I: ANDI");

        funct3 = `F3_SLL; funct7_bit30 = 0; #10;
        check(`ALU_SLL, "I: SLLI");

        funct3 = `F3_SRL_SRA; funct7_bit30 = 0; #10;
        check(`ALU_SRL, "I: SRLI");

        funct3 = `F3_SRL_SRA; funct7_bit30 = 1; #10;
        check(`ALU_SRA, "I: SRAI");

        $display("\n--- ALU Decoder Tests: %0d passed, %0d failed ---", pass, fail);
        if (fail > 0) $display("*** SOME TESTS FAILED ***");
        else $display("*** ALL TESTS PASSED ***");
        $finish;
    end
endmodule
