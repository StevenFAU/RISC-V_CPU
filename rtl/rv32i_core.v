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

    // Illegal-instruction detection. Unconnected at fpga_top through 1.2.0
    // (UNUSEDSIGNAL waiver on `core_illegal_inst` there); 1.2.1 wires it in
    // as a cause source on the trap encoder.
    output wire        illegal_inst_o,

    // Trap-entry outputs (Phase 1.2.0 Step 2). Drive csr_file's trap ports
    // directly. `trap_return_o` is intentionally NOT here in 1.2.0 — MRET
    // is Phase 1.2.2; csr_file.trap_return stays tied 1'b0 at fpga_top.
    output wire        trap_enter_o,
    output wire [31:0] trap_pc_o,
    output wire [31:0] trap_cause_o,
    output wire [31:0] trap_tval_o,

    // Trap-related CSR outputs from csr_file. mtvec_i is consumed by the
    // PC-mux's trap-entry select (1.2.0 Step 2); mepc_i is wired into the
    // mux but dead-pathed (1.2.2's MRET activates it); mstatus_mie_i is
    // still unused in 1.2.0 (Phase 2 interrupts).
    input  wire [31:0] mtvec_i,
    input  wire [31:0] mepc_i,
    /* verilator lint_off UNUSEDSIGNAL */
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
    // Bus-write/read enables are gated on `!trap_enter_w` so a trapping
    // instruction issues no DMEM transaction on the cycle it traps. For
    // ECALL the gating is a structural no-op (decode already drives
    // mem_write=mem_read=0 on SYSTEM-funct3=0), but the gate is in place
    // for 1.2.1's misaligned-load/store and bus-error trap sources, where
    // the trapping instruction is a real load/store with mem_write/
    // mem_read=1 — those will become trivial encoder-input changes once
    // the gate exists.
    assign imem_addr      = pc_current;
    assign imem_addr_next = rst ? 32'd0 : pc_next;
    assign dmem_addr      = alu_result;
    assign dmem_wdata   = rs2_data;
    assign dmem_we      = mem_write & ~trap_enter_w;
    assign dmem_re      = mem_read  & ~trap_enter_w;
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
    // PC-next mux — Phase 1.2.0 Step 2 extends with trap-entry / trap-return
    // inputs. Trap entry takes highest priority (overrides branch and jump
    // on the same cycle); trap-return is dead-pathed in 1.2.0 (the select
    // is a literal 1'b0) and lights up in 1.2.2 by replacing that literal
    // with the real `trap_return` signal.
    // =========================================================================
    wire trap_return_select_dead = 1'b0;  // 1.2.2: replace with trap_return signal
    assign pc_next = trap_enter_w             ? mtvec_i :
                     trap_return_select_dead  ? mepc_i :
                     ctrl_jump                ? jump_target :
                     branch_taken             ? branch_target :
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
    // Decoded inline here rather than threading another funct12-aware path
    // through control.v: control.v already collapses funct3=000 into
    // illegal_system, and the rs1/rd/imm12 fields are already plumbed at
    // this level. EBREAK (imm12=0x001) and MRET (imm12=0x302) stay illegal
    // until 1.2.1 / 1.2.2 take them over.
    wire ecall_m = (opcode == `OP_SYSTEM)
                && (funct3 == 3'b000)
                && (csr_addr_f == 12'h000)
                && (rs1_addr == 5'b0)
                && (rd_addr == 5'b0);

    // Cause-priority encoder inputs — all eight declared per the "design
    // for all consumers at module creation" principle. Only ecall_m drives
    // a real signal in 1.2.0; the rest are tied 1'b0 and lit up in 1.2.1
    // by replacing the literal-zero ties with the real signal sources.
    // Cause codes match RISC-V Privileged spec; priority order also matches
    // (highest to lowest in the encoder's if/else chain below).
    wire trap_inst_addr_misaligned  = 1'b0;  // 1.2.1: branch/jump target [1:0] != 0
    wire trap_illegal_inst          = 1'b0;  // 1.2.1: from illegal_inst_o
    wire trap_ebreak                = 1'b0;  // 1.2.1: SYSTEM funct3=0 imm12=0x001
    wire trap_load_addr_misaligned  = 1'b0;  // 1.2.1: LH addr[0] | LW addr[1:0]
    wire trap_load_access_fault     = 1'b0;  // 1.2.1: bus_error_o & load
    wire trap_store_addr_misaligned = 1'b0;  // 1.2.1: SH/SW analogous
    wire trap_store_access_fault    = 1'b0;  // 1.2.1: bus_error_o & store
    wire trap_ecall_m               = ecall_m;

    // Combinational priority encoder. Lowest-index cause wins, matching
    // Decision 3 from docs/handoffs/phase1_context.md (RISC-V spec order).
    reg        trap_enter_w;
    reg [3:0]  trap_cause_code;
    always @(*) begin
        trap_enter_w    = 1'b1;
        if      (trap_inst_addr_misaligned)  trap_cause_code = 4'd0;
        else if (trap_illegal_inst)          trap_cause_code = 4'd2;
        else if (trap_ebreak)                trap_cause_code = 4'd3;
        else if (trap_load_addr_misaligned)  trap_cause_code = 4'd4;
        else if (trap_load_access_fault)     trap_cause_code = 4'd5;
        else if (trap_store_addr_misaligned) trap_cause_code = 4'd6;
        else if (trap_store_access_fault)    trap_cause_code = 4'd7;
        else if (trap_ecall_m)               trap_cause_code = 4'd11;
        else begin
            trap_cause_code = 4'd0;
            trap_enter_w    = 1'b0;
        end
    end

    // Encoder outputs. csr_file masks trap_pc[1:0] internally on the mepc
    // write, so passing the raw current PC is correct.
    wire [31:0] trap_cause_w = {28'b0, trap_cause_code};
    wire [31:0] trap_tval_w  = 32'b0;          // ECALL/EBREAK have tval=0
    wire [31:0] trap_pc_w    = pc_current;

    // Step 2 of 1.2.0: encoder outputs are routed both to the PC-mux above
    // (mtvec_i select on trap_enter_w) and out to fpga_top via the new
    // top-level trap-entry ports below. The PC-mux trap-entry select takes
    // priority over branch/jump per the encoder placement above.
    assign trap_enter_o = trap_enter_w;
    assign trap_pc_o    = trap_pc_w;
    assign trap_cause_o = trap_cause_w;
    assign trap_tval_o  = trap_tval_w;

    // =========================================================================
    // Phase 1.1 — illegal-instruction detection + retirement tick
    // =========================================================================
    // illegal_inst_o is the OR of:
    //   * csr_illegal_i  — CSR-file detected RO write or unimplemented addr
    //   * illegal_system — SYSTEM funct3=0 (ECALL/EBREAK/MRET/WFI), MASKED
    //     by ecall_m so legal ECALLs no longer raise illegal. EBREAK / MRET
    //     / unknown SYSTEM-funct3=0 encodings still pulse illegal here
    //     until 1.2.1 / 1.2.2 take them over.
    //   * illegal_opcode — unrecognized opcode at the decoder default branch
    // Unconnected at fpga_top in 1.1/1.2.0; 1.2.1 wires it in as a cause
    // source on the trap encoder.
    assign illegal_inst_o = csr_illegal_i | (illegal_system & ~ecall_m) | illegal_opcode;

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
