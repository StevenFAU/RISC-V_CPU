// Main Decoder — generates control signals from opcode (and funct3 for SYSTEM)
`include "defines.v"

module control (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,        // Phase 1.1: SYSTEM-opcode subdecode

    // Existing control signals
    output reg        reg_write,
    output reg        mem_to_reg,
    output reg        mem_write,
    output reg        mem_read,
    output reg        alu_src,       // 0: register, 1: immediate
    output reg        branch,
    output reg        jump,
    output reg [1:0]  alu_op,

    // Phase 1.1: SYSTEM-opcode + CSR instruction outputs
    // is_csr        — 1 for CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI
    // csr_op        — {1'b0, funct3[1:0]}: 001=write, 010=set, 011=clear
    //                 The rs1=x0 / zimm=0 "no-write" gating is applied at the
    //                 use site in rv32i_core.v (per handoff guidance).
    // csr_use_imm   — funct3[2]: high for immediate variants (CSRRWI/SI/CI).
    // illegal_system — opcode==SYSTEM && funct3==000 — placeholder for
    //                  ECALL/EBREAK/MRET/WFI; Phase 1.2 subdivides via imm[31:20].
    // illegal_opcode — pulses on the case-statement default branch when an
    //                  unknown opcode is fetched. New in Phase 1.1; OR'd into
    //                  rv32i_core.illegal_inst_o (unconnected at fpga_top
    //                  until Phase 1.2's trap FSM consumes it). Semantic
    //                  change vs Phase 1.0: previously unknown opcodes were
    //                  silently NOP-ish; they now raise illegal_inst_o.
    output reg        is_csr,
    output reg [2:0]  csr_op,
    output reg        csr_use_imm,
    output reg        illegal_system,
    output reg        illegal_opcode
);

    always @(*) begin
        // Defaults — safe values
        reg_write      = 1'b0;
        mem_to_reg     = 1'b0;
        mem_write      = 1'b0;
        mem_read       = 1'b0;
        alu_src        = 1'b0;
        branch         = 1'b0;
        jump           = 1'b0;
        alu_op         = `ALUOP_LOAD_STORE;
        is_csr         = 1'b0;
        csr_op         = 3'b000;
        csr_use_imm    = 1'b0;
        illegal_system = 1'b0;
        illegal_opcode = 1'b0;

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
                // Future accelerator — recognized but generates safe defaults.
                // Deliberately NOT illegal_opcode: reserved opcode space.
            end

            `OP_MISC_MEM: begin
                // FENCE (funct3=000) and FENCE.I (funct3=001). Both decoded
                // as NOP on this microarchitecture:
                //   * FENCE constrains memory ordering between hart and other
                //     observers. Our single-cycle, single-hart core has no
                //     store buffer, no reorder buffer, and a strictly
                //     sequential memory model — every load/store completes
                //     before the next instruction issues. There is no
                //     ordering to enforce; NOP is conformant.
                //   * FENCE.I synchronizes the instruction and data streams.
                //     Our core has no I-cache and fetches from the same
                //     unified memory hierarchy as data accesses; any store
                //     to instruction memory is visible to the next fetch
                //     without explicit synchronization. NOP is conformant.
                // All control signals stay at safe defaults — no writeback,
                // no memory access, no branch, no trap.
                //
                // Phase 1.2.5 prerequisite: env/p's RVTEST_PASS / RVTEST_FAIL
                // macros emit `fence;` as the first instruction; without
                // this decode path, every rv32mi test infinite-loops at the
                // fail trampoline. The rv32ui-minimal env (env/custom)
                // avoids fence, which is why rv32ui passed before this
                // commit — FENCE was simply never executed.
            end

            `OP_SYSTEM: begin
                // funct3 != 0 => CSR instruction (CSRRW/S/C and immediate forms).
                // funct3 == 0 => ECALL/EBREAK/MRET/WFI placeholder (illegal in 1.1).
                is_csr         = (funct3 != 3'b000);
                csr_op         = is_csr ? {1'b0, funct3[1:0]} : 3'b000;
                csr_use_imm    = is_csr & funct3[2];
                illegal_system = (funct3 == 3'b000);
                reg_write      = is_csr;  // CSR writeback; placeholders don't write rd
            end

            default: begin
                // Genuinely unknown opcode — assert illegal_opcode for the
                // Phase 1.2 trap path. All other signals stay at safe defaults.
                illegal_opcode = 1'b1;
            end
        endcase
    end

endmodule
