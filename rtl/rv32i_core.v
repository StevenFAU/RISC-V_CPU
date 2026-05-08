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
// Phase 1.2.0 adds the trap-entry skeleton:
//
//   * Cause priority encoder built in full skeleton form — all eight sync-
//     cause inputs declared, only `ecall_m` driven this sub-phase. The
//     remaining seven are tied 1'b0 here and lit up in 1.2.1 by replacing
//     the literal-zero ties with the real signal sources, with no encoder
//     restructuring.
//
//   * ECALL is decoded inline at this top level (SYSTEM, funct3=0,
//     imm12=0x000, rs1=0, rd=0). Decision #9 from the Phase 1.2.0 handoff:
//     ECALL is removed from `illegal_inst_o`; EBREAK / MRET / unknown
//     SYSTEM-funct3=0 encodings stay illegal until 1.2.1 / 1.2.2 take
//     over.
//
//   * Encoder outputs (`trap_enter` / `trap_pc` / `trap_cause` /
//     `trap_tval`) are NOT yet routed to the PC mux or up to fpga_top in
//     this Step-1 commit — Step 2 of the sub-phase plumbs them. Internal
//     wires sit under a temporary UNUSEDSIGNAL waiver until then.
//
// Carried-forward Phase 1.1 notes:
//
//   * illegal_inst_o = csr_illegal_i | (illegal_system & !ecall_m) |
//     illegal_opcode. ECALL no longer fires the illegal path; EBREAK /
//     MRET / unknown SYSTEM-funct3=0 still do.
//
//   * instret_tick_o = !rst — single-cycle core retires every non-reset
//     cycle. Phase 1.2.0 Step 2 gates this on `!trap_enter` so a trapping
//     instruction does not retire.
//
//   * mtvec_i / mepc_i / mstatus_mie_i are inputs from csr_file, plumbed
//     through the core's port list now per the "designed for all
//     consumers" principle even though Phase 1.1 doesn't read them. Phase
//     1.2.0 Step 2's PC-redirect mux is the consumer.

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

    // Illegal-instruction detection. Consumed internally by the trap
    // encoder's `illegal_inst` cause-source input (1.2.1); left empty on
    // the fpga_top instance — the trap_*_o ports already expose the
    // resulting trap state to the top.
    output wire        illegal_inst_o,

    // Trap-entry outputs (Phase 1.2.0 Step 2). Drive csr_file's trap ports
    // directly. `trap_return_o` (Phase 1.2.3) drives csr_file.trap_return
    // from `mret_m`; csr_file already handles the mstatus rotation
    // (MIE <- MPIE; MPIE <- 1) on trap_return per its 1.0 implementation.
    output wire        trap_enter_o,
    output wire [31:0] trap_pc_o,
    output wire [31:0] trap_cause_o,
    output wire [31:0] trap_tval_o,
    output wire        trap_return_o,

    // Trap-related CSR outputs from csr_file. mtvec_i is consumed by the
    // PC-mux's trap-entry select (1.2.0 Step 2); mepc_i is wired into the
    // mux but dead-pathed (1.2.2's MRET activates it); mstatus_mie_i is
    // still unused in 1.2.0 (Phase 2 interrupts).
    input  wire [31:0] mtvec_i,
    input  wire [31:0] mepc_i,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire        mstatus_mie_i,
    /* verilator lint_on UNUSEDSIGNAL */

    // Phase 1.2.2 — bus-error sideband from wb_interconnect. Asserts
    // combinationally on the same cycle as the load/store transaction
    // when the address decodes to no slave (unmapped). Consumed by the
    // at-issue trap source composition for cause 5 (load_access_fault)
    // and cause 7 (store_access_fault).
    input  wire        bus_error_i,

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
    // Bus outputs — Phase 1.2.2 pre-issue/at-issue gate split
    // =========================================================================
    // dmem_re / dmem_we are gated on `~pre_issue_trap_w` (NOT `~trap_enter_w`).
    // Pre-issue traps (ECALL / EBREAK / illegal_inst / inst_addr_misaligned /
    // load_addr_misaligned / store_addr_misaligned) are detected before the
    // bus is even consulted, so suppressing the issue is correct.
    //
    // At-issue traps (load_access_fault / store_access_fault) are detected
    // FROM bus_error_i, which itself requires dmem_re / dmem_we to be
    // asserted for the bus to attempt the access. Gating dmem_re / dmem_we
    // on at_issue_trap_w would create a combinational cycle (bus_error_i
    // would never assert and access faults would silently NOP). So the
    // gates here use only pre_issue_trap_w; the at-issue path catches the
    // error before regfile_we / instret_tick latch.
    //
    // regfile_we and instret_tick (below) keep gating on the full
    // trap_enter_w — they are latch-side gates, not issue-side.
    //
    // at-issue trap detection assumes bus_error_i is combinational.
    // If bus_error_i becomes registered (e.g., for timing closure), this
    // gate becomes a latched-error model: load_access_fault would fire
    // one cycle late, after writeback has already happened.
    //
    // This sub-phase also assumes single-cycle bus completion
    // (wb_master.WB_USE_STALL=0). If the bus becomes multi-cycle,
    // dmem_re/dmem_we would need to remain asserted across cycles, but
    // pre_issue_trap_w suppresses them — the bus protocol would break.
    //
    // Both dependencies are filed in docs/tech_debt.md. See
    // docs/handoffs/PHASE1.2.2_HANDOFF.md for full rationale.
    assign imem_addr      = pc_current;
    assign imem_addr_next = rst ? 32'd0 : pc_next;
    assign dmem_addr      = alu_result;
    assign dmem_wdata   = rs2_data;
    assign dmem_we      = mem_write & ~pre_issue_trap_w;
    assign dmem_re      = mem_read  & ~pre_issue_trap_w;
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
    // JALR: target = (rs1 + imm) & ~1   (bit 0 force-zeroed by spec)
    assign jump_target = (opcode == `OP_JALR) ?
                         ((rs1_data + imm) & 32'hFFFFFFFE) :
                         (pc_current + imm);  // JAL

    // Combined "would-be next PC" for misalignment detection / mtval. JAL,
    // JALR, and taken branches are mutually exclusive in the same cycle —
    // ctrl_jump selects jump_target (covers JAL and JALR); branch_taken
    // implies !ctrl_jump and selects branch_target. JAL's J-imm and
    // branch's B-imm both have imm[0]=0 by encoding, so target[0] is
    // always 0 for branches/JAL; JALR's target[0] is force-zeroed by the
    // & ~1 mask above. Misalignment therefore reduces to target[1] != 0,
    // but the [1:0] != 0 form is kept for spec parity (the optimizer
    // folds it).
    wire [31:0] misaligned_target = ctrl_jump ? jump_target : branch_target;
    wire        inst_addr_misaligned_w =
                    (ctrl_jump    && (jump_target[1:0]   != 2'b00)) ||
                    (branch_taken && (branch_target[1:0] != 2'b00));

    // =========================================================================
    // Phase 1.2.2 — Load / Store address-misalignment detection
    // =========================================================================
    // Combinational on the LSU-computed `dmem_addr`. Per-instruction width
    // check: LW/SW require addr[1:0]==0; LH/LHU/SH require addr[0]==0;
    // LB/LBU/SB never misalign (byte access). The mem_read/mem_write
    // qualifiers prevent non-LSU instructions (whose `dmem_addr` carries
    // arbitrary bits) from tripping the detection.
    //
    // mtval for these causes is `dmem_addr` itself — the misaligned address
    // (NOT masked to alignment). csr_file does not mask trap_tval.
    wire load_addr_misaligned_w =
            mem_read & (
                ((funct3 == `F3_WORD)                              && (dmem_addr[1:0] != 2'b00)) ||
                (((funct3 == `F3_HALF) || (funct3 == `F3_HALFU))   && (dmem_addr[0]   != 1'b0))
            );
    wire store_addr_misaligned_w =
            mem_write & (
                ((funct3 == `F3_WORD) && (dmem_addr[1:0] != 2'b00)) ||
                ((funct3 == `F3_HALF) && (dmem_addr[0]   != 1'b0))
            );

    // =========================================================================
    // PC-next mux — Phase 1.2.0 wired the mtvec_i / mepc_i inputs; Phase
    // 1.2.3 activates the trap-return select. Trap entry takes highest
    // priority (overrides trap-return, branch, and jump on the same cycle);
    // trap-return select is now driven by `mret_m`. trap_enter and mret_m
    // cannot both fire on the same cycle in M-only operation — MRET itself
    // does not synchronously fault — but the priority is structurally
    // correct anyway.
    // =========================================================================
    assign pc_next = trap_enter_w  ? mtvec_i :
                     mret_m        ? mepc_i :
                     ctrl_jump     ? jump_target :
                     branch_taken  ? branch_target :
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
    // Phase 1.2.0 — ECALL decode + cause-priority encoder (skeleton)
    // =========================================================================
    // ECALL: SYSTEM (opcode 0x73), funct3=000, imm12=0x000, rs1=0, rd=0.
    // EBREAK: SYSTEM (opcode 0x73), funct3=000, imm12=0x001, rs1=0, rd=0.
    // MRET:   SYSTEM (opcode 0x73), funct3=000, imm12=0x302, rs1=0, rd=0.
    // Decoded inline here rather than threading another funct12-aware path
    // through control.v: control.v already collapses funct3=000 into
    // illegal_system, and the rs1/rd/imm12 fields are already plumbed at
    // this level. MRET joins ECALL/EBREAK in 1.2.3 — its carve-out term
    // closes the M-mode SYSTEM funct3=0 chain (see illegal_inst_o below).
    wire ecall_m = (opcode == `OP_SYSTEM)
                && (funct3 == 3'b000)
                && (csr_addr_f == 12'h000)
                && (rs1_addr == 5'b0)
                && (rd_addr == 5'b0);
    wire ebreak_m = (opcode == `OP_SYSTEM)
                 && (funct3 == 3'b000)
                 && (csr_addr_f == 12'h001)
                 && (rs1_addr == 5'b0)
                 && (rd_addr == 5'b0);
    wire mret_m = (opcode == `OP_SYSTEM)
               && (funct3 == 3'b000)
               && (csr_addr_f == 12'h302)
               && (rs1_addr == 5'b0)
               && (rd_addr == 5'b0);

    // Cause-priority encoder inputs — all eight declared per the "design
    // for all consumers at module creation" principle. Only ecall_m drives
    // a real signal in 1.2.0; the rest are tied 1'b0 and lit up in 1.2.1
    // by replacing the literal-zero ties with the real signal sources.
    // Cause codes match RISC-V Privileged spec; priority order also matches
    // (highest to lowest in the encoder's if/else chain below).
    // Phase 1.2.2 — pre-issue trap composition. All causes detected before
    // the bus is consulted. Used to gate dmem_re / dmem_we so a trapping
    // load/store does not initiate a bus transaction.
    wire pre_issue_trap_w = inst_addr_misaligned_w
                          | illegal_inst_o
                          | ebreak_m
                          | load_addr_misaligned_w
                          | store_addr_misaligned_w
                          | ecall_m;

    // Phase 1.2.2 — at-issue trap source composition. dmem_re / dmem_we
    // here are the GATED forms (post `~pre_issue_trap_w`), so a misaligned
    // load/store deasserts them before the bus sees the address. The
    // ~load_addr_misaligned_w / ~store_addr_misaligned_w qualifiers make
    // the mutual exclusion local to the gate definition rather than
    // depending on encoder priority — defense in depth at zero cost.
    wire load_access_fault_w  = bus_error_i & dmem_re & ~load_addr_misaligned_w;
    wire store_access_fault_w = bus_error_i & dmem_we & ~store_addr_misaligned_w;

    wire at_issue_trap_w = load_access_fault_w | store_access_fault_w;

    wire trap_inst_addr_misaligned  = inst_addr_misaligned_w;
    wire trap_illegal_inst          = illegal_inst_o;
    wire trap_ebreak                = ebreak_m;
    wire trap_load_addr_misaligned  = load_addr_misaligned_w;
    wire trap_load_access_fault     = load_access_fault_w;
    wire trap_store_addr_misaligned = store_addr_misaligned_w;
    wire trap_store_access_fault    = store_access_fault_w;
    wire trap_ecall_m               = ecall_m;

    // Combinational priority encoder. Lowest-index cause wins, matching
    // Decision 3 from docs/handoffs/phase1_context.md (RISC-V spec order).
    // The same priority chain also selects trap_tval — co-driven here so
    // the cause/tval pair is always consistent.
    //
    // Phase 1.2.2: trap_enter_w is now a continuous assign of
    // (pre_issue_trap_w | at_issue_trap_w) so the structural split is
    // explicit at the trap-entry signal itself. The always block drives
    // only trap_cause_code and trap_tval_w from the priority chain.
    wire       trap_enter_w = pre_issue_trap_w | at_issue_trap_w;
    reg [3:0]  trap_cause_code;
    reg [31:0] trap_tval_w;
    always @(*) begin
        if (trap_inst_addr_misaligned) begin
            trap_cause_code = 4'd0;
            trap_tval_w     = misaligned_target;
        end else if (trap_illegal_inst) begin
            trap_cause_code = 4'd2;
            trap_tval_w     = instr;            // 32-bit instruction word
        end else if (trap_ebreak) begin
            trap_cause_code = 4'd3;
            trap_tval_w     = 32'b0;            // per spec
        end else if (trap_load_addr_misaligned) begin
            trap_cause_code = 4'd4;
            trap_tval_w     = dmem_addr;        // misaligned load address
        end else if (trap_load_access_fault) begin
            trap_cause_code = 4'd5;
            trap_tval_w     = dmem_addr;        // unmapped load address
        end else if (trap_store_addr_misaligned) begin
            trap_cause_code = 4'd6;
            trap_tval_w     = dmem_addr;        // misaligned store address
        end else if (trap_store_access_fault) begin
            trap_cause_code = 4'd7;
            trap_tval_w     = dmem_addr;        // unmapped store address
        end else if (trap_ecall_m) begin
            trap_cause_code = 4'd11;
            trap_tval_w     = 32'b0;            // per spec
        end else begin
            trap_cause_code = 4'd0;
            trap_tval_w     = 32'b0;
        end
    end

    // Encoder outputs. csr_file masks trap_pc[1:0] internally on the mepc
    // write so passing the raw current PC is correct. csr_file does NOT
    // mask trap_tval — for inst_addr_misaligned the misaligned target's
    // low bits ARE the relevant data and must reach mtval unmodified.
    wire [31:0] trap_cause_w = {28'b0, trap_cause_code};
    wire [31:0] trap_pc_w    = pc_current;

    // Step 2 of 1.2.0: encoder outputs are routed both to the PC-mux above
    // (mtvec_i select on trap_enter_w) and out to fpga_top via the new
    // top-level trap-entry ports below. The PC-mux trap-entry select takes
    // priority over branch/jump per the encoder placement above.
    assign trap_enter_o  = trap_enter_w;
    assign trap_pc_o     = trap_pc_w;
    assign trap_cause_o  = trap_cause_w;
    assign trap_tval_o   = trap_tval_w;
    // Phase 1.2.3: trap_return_o lights up MRET's effect on csr_file.
    // csr_file already enforces trap_enter > trap_return priority
    // internally, so a hypothetical same-cycle assertion of both (which
    // cannot happen in M-only — MRET does not synchronously fault) is
    // resolved correctly by csr_file in addition to the PC-mux ordering
    // above.
    assign trap_return_o = mret_m;

    // =========================================================================
    // Phase 1.1 — illegal-instruction detection + retirement tick
    // =========================================================================
    // illegal_inst_o is the OR of:
    //   * csr_illegal_i  — CSR-file detected RO write or unimplemented addr
    //   * illegal_system — SYSTEM funct3=0 (ECALL/EBREAK/MRET/WFI), with
    //     legal SYSTEM funct3=0 encodings carved out one at a time:
    //       ECALL  carved out 1.2.0 (& ~ecall_m)   — funct3=0, imm12=0x000
    //       EBREAK carved out 1.2.1 (& ~ebreak_m)  — funct3=0, imm12=0x001
    //       MRET   carved out 1.2.3 (& ~mret_m)    — funct3=0, imm12=0x302
    //     Chain is now COMPLETE for all M-mode SYSTEM funct3=0 instructions
    //     implemented in this CPU. Future instructions in this family
    //     (Zihintntl variants, hypothetical privileged additions) MUST
    //     extend this chain with their own explicit ~<inst>_m term per the
    //     established convention. They cannot silently inherit "is illegal"
    //     by being unrecognized — that is the bug this convention prevents
    //     — and they cannot silently inherit "is legal" by failing to
    //     carve out. Future SYSTEM instructions with funct3 != 0 are
    //     unaffected by this chain (they take separate decode paths).
    //   * illegal_opcode — unrecognized opcode at the decoder default branch
    // Now consumed in 1.2.1 as the encoder's `illegal_inst` cause source.
    assign illegal_inst_o = csr_illegal_i | (illegal_system & ~ecall_m & ~ebreak_m & ~mret_m) | illegal_opcode;

    // Single-cycle core retires every non-reset cycle, EXCEPT on a trap-
    // entry cycle: the trapping instruction did not retire, so minstret
    // must not advance. mcycle continues to tick in csr_file
    // (trap-entry-independent free-running counter — see csr_file.v
    // mcycle_reg block).
    assign instret_tick_o = !rst & ~trap_enter_w;

    // =========================================================================
    // Module instances
    // =========================================================================

    pc u_pc (
        .clk(clk),
        .rst(rst),
        .pc_next(pc_next),
        .pc(pc_current)
    );

    // regfile write-enable is gated on `!trap_enter_w` so a trapping
    // instruction does not write its rd. For ECALL the gating is a no-op
    // (decode sets reg_write=0 since is_csr=0 on funct3=000), but the gate
    // is in place for 1.2.1's illegal-instruction trap source where the
    // trapping opcode could carry an rd field that decode would otherwise
    // honor.
    regfile u_regfile (
        .clk(clk),
        .we(reg_write & ~trap_enter_w),
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
