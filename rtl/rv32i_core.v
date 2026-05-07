// RV32I Single-Cycle Core — Top-Level Datapath
// Memory is external: core exposes instruction fetch and data memory bus ports.
//
// Phase 1.1 wired CSR-instruction decode + writeback into the datapath:
//
//   * SYSTEM-opcode decode: control.v emits is_csr / csr_op / csr_use_imm /
//     illegal_system / illegal_opcode. The core consumes those to drive the
//     csr_addr_o / csr_read_en_o / csr_write_op_o / csr_write_data_o ports
//     into the external csr_file, and routes csr_read_data_i back through a
//     new (5th) source on the writeback mux.
//
//   * illegal_inst_o = csr_illegal_i | illegal_system | illegal_opcode.
//     Phase 1.1 leaves this output unconnected at fpga_top; Phase 1.2's
//     trap FSM consumes it.
//
//   * instret_tick_o = !rst — single-cycle core retires every non-reset
//     cycle. Phase 1.2 may refine to gate on !illegal_inst once the trap
//     path materializes (so trapped cycles don't double-count as retires).
//
//   * mtvec_i / mepc_i / mstatus_mie_i are inputs from csr_file, plumbed
//     through the core's port list now per the "designed for all
//     consumers" principle even though Phase 1.1 doesn't read them. Phase
//     1.2's PC-redirect mux lives inside the core, so adding the ports
//     here in 1.1 avoids a port-list churn when the trap FSM lands.
//     The lint_off UNUSEDSIGNAL waivers around them mark this intent.

`include "defines.v"

module rv32i_core (
    input  wire        clk,
    input  wire        rst,

    // Instruction fetch bus
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_data,

    // Data memory bus
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    input  wire [31:0] dmem_rdata,
    output wire        dmem_we,
    output wire        dmem_re,
    output wire [2:0]  dmem_funct3,

    // Pre-fetch address for BRAM-based IMEM (= pc_next, forced to 0 during reset)
    output wire [31:0] imem_addr_next,

    // -------- Phase 1.1: CSR-file interface --------
    // Outputs (decoder-driven)
    output wire [11:0] csr_addr_o,
    output wire        csr_read_en_o,
    output wire [2:0]  csr_write_op_o,    // 000=none 001=write 010=set 011=clear
    output wire [31:0] csr_write_data_o,

    // Inputs (csr_file → core)
    input  wire [31:0] csr_read_data_i,
    input  wire        csr_illegal_i,

    // Retirement tick (drives csr_file.instret_tick)
    output wire        instret_tick_o,

    // Illegal-instruction detection (unconnected at fpga_top in 1.1; consumed
    // by the Phase 1.2 trap path)
    output wire        illegal_inst_o,

    // Trap-related CSR outputs from csr_file, routed through for Phase 1.2's
    // PC-redirect mux. Tied unused in 1.1.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] mtvec_i,
    input  wire [31:0] mepc_i,
    input  wire        mstatus_mie_i,
    /* verilator lint_on UNUSEDSIGNAL */

    // Debug/RVFI access to architectural state
    output wire [31:0] debug_pc,
    output wire [31:0] debug_instr
);

    // =========================================================================
    // Internal wires
    // =========================================================================

    // PC
    wire [31:0] pc_current, pc_next, pc_plus4;

    // Instruction
    wire [31:0] instr = imem_data;

    // Register file
    wire [31:0] rs1_data, rs2_data, rd_data;

    // Immediate
    wire [31:0] imm;

    // ALU
    wire [31:0] alu_a, alu_b, alu_result;
    wire [3:0]  alu_control;

    // Control signals
    wire        reg_write, mem_to_reg, mem_write, mem_read;
    wire        alu_src, ctrl_branch, ctrl_jump;
    wire [1:0]  alu_op;

    // Phase 1.1 control outputs (consumed below).
    wire        is_csr;
    wire [2:0]  csr_op;
    wire        csr_use_imm;
    wire        illegal_system;
    wire        illegal_opcode;

    // Branch/Jump resolution
    wire        branch_taken;
    wire [31:0] branch_target, jump_target;

    // Instruction fields
    wire [6:0]  opcode       = instr[6:0];
    wire [4:0]  rd_addr      = instr[11:7];
    wire [2:0]  funct3       = instr[14:12];
    wire [4:0]  rs1_addr     = instr[19:15];
    wire [4:0]  rs2_addr     = instr[24:20];
    wire        funct7_bit30 = instr[30];
    wire [11:0] csr_addr_f   = instr[31:20];   // CSR address field for CSR insts

    // =========================================================================
    // Bus outputs
    // =========================================================================
    assign imem_addr      = pc_current;
    assign imem_addr_next = rst ? 32'd0 : pc_next;
    assign dmem_addr      = alu_result;
    assign dmem_wdata   = rs2_data;
    assign dmem_we      = mem_write;
    assign dmem_re      = mem_read;
    assign dmem_funct3  = funct3;

    // =========================================================================
    // Debug outputs
    // =========================================================================
    assign debug_pc    = pc_current;
    assign debug_instr = instr;

    // =========================================================================
    // PC + 4
    // =========================================================================
    assign pc_plus4 = pc_current + 32'd4;

    // =========================================================================
    // Branch condition evaluation (all 6 branch types)
    // =========================================================================
    reg branch_condition;
    always @(*) begin
        case (funct3)
            `F3_BEQ:  branch_condition = (rs1_data == rs2_data);
            `F3_BNE:  branch_condition = (rs1_data != rs2_data);
            `F3_BLT:  branch_condition = ($signed(rs1_data) < $signed(rs2_data));
            `F3_BGE:  branch_condition = ($signed(rs1_data) >= $signed(rs2_data));
            `F3_BLTU: branch_condition = (rs1_data < rs2_data);
            `F3_BGEU: branch_condition = (rs1_data >= rs2_data);
            default:  branch_condition = 1'b0;
        endcase
    end

    assign branch_taken = ctrl_branch & branch_condition;

    // =========================================================================
    // Branch and Jump targets
    // =========================================================================
    assign branch_target = pc_current + imm;
    // JALR: target = (rs1 + imm) & ~1
    assign jump_target = (opcode == `OP_JALR) ?
                         ((rs1_data + imm) & 32'hFFFFFFFE) :
                         (pc_current + imm);  // JAL

    // =========================================================================
    // PC-next mux
    // =========================================================================
    assign pc_next = ctrl_jump    ? jump_target :
                     branch_taken ? branch_target :
                     pc_plus4;

    // =========================================================================
    // ALU input muxes
    // =========================================================================
    assign alu_a = (opcode == `OP_AUIPC) ? pc_current : rs1_data;
    assign alu_b = alu_src ? imm : rs2_data;

    // =========================================================================
    // Phase 1.1 — CSR-instruction operand and write-op gating
    // =========================================================================
    // Source operand for CSR write:
    //   register variants:  rs1_data
    //   immediate variants: zero-extended 5-bit rs1 field (= zimm)
    wire [31:0] csr_src_data = csr_use_imm ? {27'b0, rs1_addr} : rs1_data;

    // "No-write" optimization (RV-Privileged Spec):
    //   CSRRW/CSRRWI: always write (even if rs1=x0 / zimm=0).
    //   CSRRS/CSRRC and CSRRSI/CSRRCI: write only if source operand non-zero.
    //
    // For register variants the source-zero check is rs1_addr==0 (regfile
    // gate already returns 0 for x0). For immediate variants the check is
    // also rs1_addr==0 since rs1_addr IS the zimm field.
    wire src_is_zero = (rs1_addr == 5'b0);
    wire write_op_active = (csr_op == 3'b001) ||                      // CSRRW(I): always
                           ((csr_op == 3'b010 || csr_op == 3'b011) && !src_is_zero);

    assign csr_addr_o       = csr_addr_f;
    assign csr_write_op_o   = is_csr && write_op_active ? csr_op : 3'b000;
    assign csr_write_data_o = csr_src_data;

    // CSR read suppression for CSRRW with rd=x0: the read still happens in
    // csr_file but its side-effects (e.g. read-of-RO triggering csr_illegal)
    // are gated by csr_read_en. Phase 1.0's csr_file returns 0 when read_en
    // is low.
    assign csr_read_en_o = is_csr && (rd_addr != 5'b0);

    // =========================================================================
    // Write-back mux — Phase 1.1 grows from 4 sources to 5 (CSR added).
    // =========================================================================
    // CSR is placed first since SYSTEM doesn't share an opcode with any of
    // LUI/JAL/JALR/LOAD; the priority order is mutually-exclusive in
    // practice, ordered for readability.
    assign rd_data = is_csr               ? csr_read_data_i :
                     (opcode == `OP_LUI)  ? imm :
                     (ctrl_jump)          ? pc_plus4 :
                     (mem_to_reg)         ? dmem_rdata :
                                            alu_result;

    // =========================================================================
    // Phase 1.1 — illegal-instruction detection + retirement tick
    // =========================================================================
    // illegal_inst_o is the OR of:
    //   * csr_illegal_i  — CSR-file detected RO write or unimplemented addr
    //   * illegal_system — SYSTEM-opcode placeholder (ECALL/EBREAK/MRET/WFI)
    //   * illegal_opcode — unrecognized opcode at the decoder default branch
    // Unconnected at fpga_top in 1.1; Phase 1.2's trap FSM consumes it.
    assign illegal_inst_o = csr_illegal_i | illegal_system | illegal_opcode;

    // Single-cycle core retires every non-reset cycle. Phase 1.2 may gate
    // this on !illegal_inst once the trap path can suppress retirement of
    // a faulting instruction.
    assign instret_tick_o = !rst;

    // =========================================================================
    // Module instances
    // =========================================================================

    pc u_pc (
        .clk(clk),
        .rst(rst),
        .pc_next(pc_next),
        .pc(pc_current)
    );

    regfile u_regfile (
        .clk(clk),
        .we(reg_write),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data)
    );

    immgen u_immgen (
        .instr(instr),
        .imm(imm)
    );

    control u_control (
        .opcode(opcode),
        .funct3(funct3),
        .reg_write(reg_write),
        .mem_to_reg(mem_to_reg),
        .mem_write(mem_write),
        .mem_read(mem_read),
        .alu_src(alu_src),
        .branch(ctrl_branch),
        .jump(ctrl_jump),
        .alu_op(alu_op),
        .is_csr(is_csr),
        .csr_op(csr_op),
        .csr_use_imm(csr_use_imm),
        .illegal_system(illegal_system),
        .illegal_opcode(illegal_opcode)
    );

    alu_decoder u_alu_decoder (
        .alu_op(alu_op),
        .funct3(funct3),
        .funct7_bit30(funct7_bit30),
        .alu_control(alu_control)
    );

    // ALU zero flag is unused — branch logic evaluates alu_result directly
    // in the control/PC path, so no zero comparator is wired here.
    /* verilator lint_off PINCONNECTEMPTY */
    alu u_alu (
        .a(alu_a),
        .b(alu_b),
        .alu_op(alu_control),
        .result(alu_result),
        .zero()
    );
    /* verilator lint_on PINCONNECTEMPTY */

endmodule
