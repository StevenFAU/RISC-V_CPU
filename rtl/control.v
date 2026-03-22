// Main Decoder — generates control signals from opcode
`include "defines.v"

module control (
    input  wire [6:0] opcode,
    output reg        reg_write,
    output reg        mem_to_reg,
    output reg        mem_write,
    output reg        mem_read,
    output reg        alu_src,     // 0: register, 1: immediate
    output reg        branch,
    output reg        jump,
    output reg [1:0]  alu_op
);

    always @(*) begin
        // Defaults — safe values
        reg_write  = 1'b0;
        mem_to_reg = 1'b0;
        mem_write  = 1'b0;
        mem_read   = 1'b0;
        alu_src    = 1'b0;
        branch     = 1'b0;
        jump       = 1'b0;
        alu_op     = `ALUOP_LOAD_STORE;

        case (opcode)
            `OP_R_TYPE: begin
                reg_write = 1'b1;
                alu_op    = `ALUOP_R_TYPE;
            end

            `OP_I_ALU: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = `ALUOP_I_TYPE;
            end

            `OP_LOAD: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                mem_to_reg = 1'b1;
                mem_read   = 1'b1;
                alu_op     = `ALUOP_LOAD_STORE;
            end

            `OP_STORE: begin
                alu_src   = 1'b1;
                mem_write = 1'b1;
                alu_op    = `ALUOP_LOAD_STORE;
            end

            `OP_BRANCH: begin
                branch = 1'b1;
                alu_op = `ALUOP_BRANCH;
            end

            `OP_JAL: begin
                reg_write = 1'b1;
                jump      = 1'b1;
            end

            `OP_JALR: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                jump      = 1'b1;
            end

            `OP_LUI: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
            end

            `OP_AUIPC: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
            end

            `OP_CUSTOM0: begin
                // Future accelerator — recognized but generates safe defaults
            end

            default: begin
                // Unknown opcode — all signals stay at safe defaults
            end
        endcase
    end

endmodule
