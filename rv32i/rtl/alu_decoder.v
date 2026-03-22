// ALU Decoder — maps alu_op + funct3 + funct7_bit30 to alu_control
`include "defines.v"

module alu_decoder (
    input  wire [1:0] alu_op,
    input  wire [2:0] funct3,
    input  wire       funct7_bit30,
    output reg  [3:0] alu_control
);

    always @(*) begin
        case (alu_op)
            `ALUOP_LOAD_STORE:
                // Load/Store: always ADD for address calc
                alu_control = `ALU_ADD;

            `ALUOP_BRANCH:
                // Branch: SUB for comparison (zero flag check)
                alu_control = `ALU_SUB;

            `ALUOP_R_TYPE:
                // R-type: decode funct3 + funct7
                case (funct3)
                    `F3_ADD_SUB: alu_control = funct7_bit30 ? `ALU_SUB : `ALU_ADD;
                    `F3_SLL:     alu_control = `ALU_SLL;
                    `F3_SLT:     alu_control = `ALU_SLT;
                    `F3_SLTU:    alu_control = `ALU_SLTU;
                    `F3_XOR:     alu_control = `ALU_XOR;
                    `F3_SRL_SRA: alu_control = funct7_bit30 ? `ALU_SRA : `ALU_SRL;
                    `F3_OR:      alu_control = `ALU_OR;
                    `F3_AND:     alu_control = `ALU_AND;
                    default:     alu_control = `ALU_ADD;
                endcase

            `ALUOP_I_TYPE:
                // I-type: decode funct3, funct7 only matters for shifts
                case (funct3)
                    `F3_ADD_SUB: alu_control = `ALU_ADD;  // ADDI (no SUBI)
                    `F3_SLL:     alu_control = `ALU_SLL;
                    `F3_SLT:     alu_control = `ALU_SLT;
                    `F3_SLTU:    alu_control = `ALU_SLTU;
                    `F3_XOR:     alu_control = `ALU_XOR;
                    `F3_SRL_SRA: alu_control = funct7_bit30 ? `ALU_SRA : `ALU_SRL;
                    `F3_OR:      alu_control = `ALU_OR;
                    `F3_AND:     alu_control = `ALU_AND;
                    default:     alu_control = `ALU_ADD;
                endcase

            default:
                alu_control = `ALU_ADD;
        endcase
    end

endmodule
