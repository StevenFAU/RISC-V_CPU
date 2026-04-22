// CSR File — M-Mode Control & Status Registers (Phase 1.0)
//
// Implements 13 M-mode CSRs plus the 64-bit cycle/instret counters with
// their user-mode read-only aliases. Standalone module — not yet
// integrated with rv32i_core.v. Phase 1.1 wires the SYSTEM-opcode CSR-
// instruction decode into the csr_addr/csr_read_en/csr_write_op ports;
// Phase 1.2 wires trap entry/exit into the trap_enter/trap_return ports.
// See docs/csr_map.md for the field-level CSR reference and
// TIER1_ROADMAP.md Phase 1 for the phasing plan.
//
// CSR address map (21 addresses, 13 stored M-mode registers + 4 64-bit
// counters; user-mode counter aliases share storage with the M-mode
// originals):
//
//   0x300 mstatus    R/W (mask: MIE bit 3, MPIE bit 7; MPP=11 hardwired)
//   0x301 misa       RO  (= 32'h40000100 — MXL=32, I-bit set)
//   0x304 mie        R/W (mask: MEIE bit 11, MTIE bit 7, MSIE bit 3)
//   0x305 mtvec      R/W (mask: BASE bits [31:2]; MODE [1:0]=00 hardwired)
//   0x340 mscratch   R/W (no mask)
//   0x341 mepc       R/W (mask: bits [31:2]; bits [1:0]=00 hardwired)
//   0x342 mcause     R/W (no mask)
//   0x343 mtval      R/W (no mask)
//   0x344 mip        R/W (MSIP bit 3 software-writable; MTIP/MEIP read-
//                         only — driven by hardware in Phase 2, tied 0)
//   0xF11..0xF14     RO  (mvendorid/marchid/mimpid/mhartid — all 0)
//   0xB00 mcycle     R/W (low 32 bits of 64-bit free-running counter)
//   0xB80 mcycleh    R/W (high 32 bits of mcycle)
//   0xB02 minstret   R/W (low 32 bits of 64-bit retired-instr counter)
//   0xB82 minstreth  R/W (high 32 bits of minstret)
//   0xC00/C80/C02/C82  RO aliases (cycle/cycleh/instret/instreth — share
//                         storage with the corresponding mcycle/minstret
//                         halves)
//
// Write-source priority — for any CSR with multiple writers in the same
// cycle, the implemented order is:
//
//   trap_enter  >  trap_return  >  csr_write_op
//
// In Phase 1.0 trap_enter/trap_return are tied low by the testbench; the
// priority is in place so Phase 1.2's trap FSM can wire into the existing
// chain without restructuring (designed for all consumers at module
// creation — see docs/phase1_context.md).
//
// Counter writes vs increment: writes to mcycle/mcycleh (or minstret/
// minstreth) replace the addressed half and skip that cycle's increment,
// matching the wb_timer write/increment-race pattern.

module csr_file (
    input  wire         clk,
    input  wire         rst,

    // --- Instruction-driven access (Phase 1.1 CSR instructions) ---
    input  wire [11:0]  csr_addr,
    input  wire         csr_read_en,
    input  wire [2:0]   csr_write_op,    // 000=none 001=write 010=set 011=clear
    input  wire [31:0]  csr_write_data,
    output reg  [31:0]  csr_read_data,
    output wire         csr_illegal,

    // --- Trap-entry-driven access (Phase 1.2 FSM) ---
    input  wire         trap_enter,
    // trap_pc[1:0] are dropped by the {trap_pc[31:2], 2'b00} write mask on
    // mepc — instructions are word-aligned so the low bits carry no info.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0]  trap_pc,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [31:0]  trap_cause,
    input  wire [31:0]  trap_tval,

    // --- MRET-driven access (Phase 1.2 FSM) ---
    input  wire         trap_return,

    // --- Counter tick inputs (instret driven by core retirement Phase 1.1) ---
    input  wire         instret_tick,

    // --- Outputs to core ---
    output wire [31:0]  mtvec_o,
    output wire [31:0]  mepc_o,
    output wire         mstatus_mie_o,

    // --- Debug visibility ---
    output wire [31:0]  mstatus_o
);

    // =========================================================================
    // CSR address map
    // =========================================================================
    localparam [11:0] CSR_MSTATUS   = 12'h300;
    localparam [11:0] CSR_MISA      = 12'h301;
    localparam [11:0] CSR_MIE       = 12'h304;
    localparam [11:0] CSR_MTVEC     = 12'h305;
    localparam [11:0] CSR_MSCRATCH  = 12'h340;
    localparam [11:0] CSR_MEPC      = 12'h341;
    localparam [11:0] CSR_MCAUSE    = 12'h342;
    localparam [11:0] CSR_MTVAL     = 12'h343;
    localparam [11:0] CSR_MIP       = 12'h344;
    localparam [11:0] CSR_MVENDORID = 12'hF11;
    localparam [11:0] CSR_MARCHID   = 12'hF12;
    localparam [11:0] CSR_MIMPID    = 12'hF13;
    localparam [11:0] CSR_MHARTID   = 12'hF14;
    localparam [11:0] CSR_MCYCLE    = 12'hB00;
    localparam [11:0] CSR_MINSTRET  = 12'hB02;
    localparam [11:0] CSR_MCYCLEH   = 12'hB80;
    localparam [11:0] CSR_MINSTRETH = 12'hB82;
    localparam [11:0] CSR_CYCLE     = 12'hC00;
    localparam [11:0] CSR_INSTRET   = 12'hC02;
    localparam [11:0] CSR_CYCLEH    = 12'hC80;
    localparam [11:0] CSR_INSTRETH  = 12'hC82;

    localparam [31:0] MISA_VAL = 32'h40000100;  // MXL=32 (bits 31:30 = 01), I-bit set (bit 8)

    // =========================================================================
    // Storage — only the writable bits are kept; composed-read wires below
    // re-assemble the full 32-bit view including hardwired fields.
    // =========================================================================
    reg        mstatus_mie;
    reg        mstatus_mpie;
    reg        mie_meie;
    reg        mie_mtie;
    reg        mie_msie;
    reg [31:0] mtvec_reg;        // bits [1:0] always 0 (write-masked)
    reg [31:0] mscratch_reg;
    reg [31:0] mepc_reg;         // bits [1:0] always 0 (write-masked)
    reg [31:0] mcause_reg;
    reg [31:0] mtval_reg;
    reg        mip_msip;         // MTIP/MEIP tied 0 in Phase 1.0
    reg [63:0] mcycle_reg;
    reg [63:0] minstret_reg;

    // =========================================================================
    // Composed read values
    // =========================================================================
    wire [31:0] mstatus_val = {19'b0, 2'b11, 3'b0,
                               mstatus_mpie, 3'b0,
                               mstatus_mie,  3'b0};
    wire [31:0] mie_val     = {20'b0,
                               mie_meie, 3'b0,
                               mie_mtie, 3'b0,
                               mie_msie, 3'b0};
    wire [31:0] mip_val     = {28'b0, mip_msip, 3'b0};

    wire [31:0] mcycle_lo   = mcycle_reg[31:0];
    wire [31:0] mcycle_hi   = mcycle_reg[63:32];
    wire [31:0] minstret_lo = minstret_reg[31:0];
    wire [31:0] minstret_hi = minstret_reg[63:32];

    // =========================================================================
    // Address decode + read mux
    // =========================================================================
    reg        is_valid;
    reg        is_readonly;
    reg [31:0] read_value_pre;

    always @(*) begin
        is_valid       = 1'b1;
        is_readonly    = 1'b0;
        read_value_pre = 32'b0;
        case (csr_addr)
            CSR_MSTATUS:   read_value_pre = mstatus_val;
            CSR_MISA:      begin read_value_pre = MISA_VAL;     is_readonly = 1'b1; end
            CSR_MIE:       read_value_pre = mie_val;
            CSR_MTVEC:     read_value_pre = mtvec_reg;
            CSR_MSCRATCH:  read_value_pre = mscratch_reg;
            CSR_MEPC:      read_value_pre = mepc_reg;
            CSR_MCAUSE:    read_value_pre = mcause_reg;
            CSR_MTVAL:     read_value_pre = mtval_reg;
            CSR_MIP:       read_value_pre = mip_val;
            CSR_MVENDORID: begin read_value_pre = 32'b0;        is_readonly = 1'b1; end
            CSR_MARCHID:   begin read_value_pre = 32'b0;        is_readonly = 1'b1; end
            CSR_MIMPID:    begin read_value_pre = 32'b0;        is_readonly = 1'b1; end
            CSR_MHARTID:   begin read_value_pre = 32'b0;        is_readonly = 1'b1; end
            CSR_MCYCLE:    read_value_pre = mcycle_lo;
            CSR_MINSTRET:  read_value_pre = minstret_lo;
            CSR_MCYCLEH:   read_value_pre = mcycle_hi;
            CSR_MINSTRETH: read_value_pre = minstret_hi;
            CSR_CYCLE:     begin read_value_pre = mcycle_lo;    is_readonly = 1'b1; end
            CSR_INSTRET:   begin read_value_pre = minstret_lo;  is_readonly = 1'b1; end
            CSR_CYCLEH:    begin read_value_pre = mcycle_hi;    is_readonly = 1'b1; end
            CSR_INSTRETH:  begin read_value_pre = minstret_hi;  is_readonly = 1'b1; end
            default:       is_valid = 1'b0;
        endcase
    end

    // csr_read_data is 0 unless csr_read_en is asserted (avoids reads having
    // side effects through downstream consumers).
    always @(*) begin
        csr_read_data = csr_read_en ? read_value_pre : 32'b0;
    end

    // csr_illegal fires on:
    //   (a) read of an unimplemented address, or
    //   (b) write attempt to a read-only CSR, or
    //   (c) write attempt to an unimplemented address.
    assign csr_illegal = (csr_read_en && !is_valid) ||
                         ((csr_write_op != 3'b000) && (!is_valid || is_readonly));

    // =========================================================================
    // CSR-instruction modified value (CSRRW=001 / CSRRS=010 / CSRRC=011)
    // For CSRRS/CSRRC, the read value used here is read_value_pre — the
    // current storage view, regardless of csr_read_en — matching the spec's
    // RMW semantics independent of whether the destination register is x0.
    // =========================================================================
    reg [31:0] csr_modified_value;
    always @(*) begin
        case (csr_write_op)
            3'b001:  csr_modified_value = csr_write_data;
            3'b010:  csr_modified_value = read_value_pre |  csr_write_data;
            3'b011:  csr_modified_value = read_value_pre & ~csr_write_data;
            default: csr_modified_value = read_value_pre;
        endcase
    end

    // =========================================================================
    // Per-CSR write enables (instruction-driven). trap_enter/trap_return get
    // priority within each CSR's update block via the if-elseif chain below.
    // =========================================================================
    wire csr_inst_active = (csr_write_op != 3'b000) && is_valid && !is_readonly;

    wire write_mstatus   = csr_inst_active && (csr_addr == CSR_MSTATUS);
    wire write_mie       = csr_inst_active && (csr_addr == CSR_MIE);
    wire write_mtvec     = csr_inst_active && (csr_addr == CSR_MTVEC);
    wire write_mscratch  = csr_inst_active && (csr_addr == CSR_MSCRATCH);
    wire write_mepc      = csr_inst_active && (csr_addr == CSR_MEPC);
    wire write_mcause    = csr_inst_active && (csr_addr == CSR_MCAUSE);
    wire write_mtval     = csr_inst_active && (csr_addr == CSR_MTVAL);
    wire write_mip       = csr_inst_active && (csr_addr == CSR_MIP);
    wire write_mcycle    = csr_inst_active && (csr_addr == CSR_MCYCLE);
    wire write_mcycleh   = csr_inst_active && (csr_addr == CSR_MCYCLEH);
    wire write_minstret  = csr_inst_active && (csr_addr == CSR_MINSTRET);
    wire write_minstreth = csr_inst_active && (csr_addr == CSR_MINSTRETH);

    // =========================================================================
    // mstatus update — trap_enter > trap_return > csr_write_op
    //   trap_enter:  MPIE <- MIE; MIE <- 0
    //   trap_return: MIE  <- MPIE; MPIE <- 1
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            mstatus_mie  <= 1'b0;
            mstatus_mpie <= 1'b0;
        end else if (trap_enter) begin
            mstatus_mpie <= mstatus_mie;
            mstatus_mie  <= 1'b0;
        end else if (trap_return) begin
            mstatus_mie  <= mstatus_mpie;
            mstatus_mpie <= 1'b1;
        end else if (write_mstatus) begin
            mstatus_mie  <= csr_modified_value[3];
            mstatus_mpie <= csr_modified_value[7];
        end
    end

    // =========================================================================
    // mie update — csr_write_op only (mask: MEIE/MTIE/MSIE)
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            mie_meie <= 1'b0;
            mie_mtie <= 1'b0;
            mie_msie <= 1'b0;
        end else if (write_mie) begin
            mie_meie <= csr_modified_value[11];
            mie_mtie <= csr_modified_value[7];
            mie_msie <= csr_modified_value[3];
        end
    end

    // =========================================================================
    // mtvec update — csr_write_op only (mask: BASE bits [31:2])
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            mtvec_reg <= 32'b0;
        end else if (write_mtvec) begin
            mtvec_reg <= {csr_modified_value[31:2], 2'b00};
        end
    end

    // =========================================================================
    // mscratch update — csr_write_op only (no mask)
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            mscratch_reg <= 32'b0;
        end else if (write_mscratch) begin
            mscratch_reg <= csr_modified_value;
        end
    end

    // =========================================================================
    // mepc update — trap_enter > csr_write_op (mask: bits [31:2])
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            mepc_reg <= 32'b0;
        end else if (trap_enter) begin
            mepc_reg <= {trap_pc[31:2], 2'b00};
        end else if (write_mepc) begin
            mepc_reg <= {csr_modified_value[31:2], 2'b00};
        end
    end

    // =========================================================================
    // mcause update — trap_enter > csr_write_op (no mask)
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            mcause_reg <= 32'b0;
        end else if (trap_enter) begin
            mcause_reg <= trap_cause;
        end else if (write_mcause) begin
            mcause_reg <= csr_modified_value;
        end
    end

    // =========================================================================
    // mtval update — trap_enter > csr_write_op (no mask)
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            mtval_reg <= 32'b0;
        end else if (trap_enter) begin
            mtval_reg <= trap_tval;
        end else if (write_mtval) begin
            mtval_reg <= csr_modified_value;
        end
    end

    // =========================================================================
    // mip update — csr_write_op writes MSIP only. MTIP/MEIP are read-only
    // (driven by hardware in Phase 2) and tied to 0 here.
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            mip_msip <= 1'b0;
        end else if (write_mip) begin
            mip_msip <= csr_modified_value[3];
        end
    end

    // =========================================================================
    // mcycle update — csr_write_op (low/high) > free-running increment.
    // Same write/increment race pattern as wb_timer's mtime: a write to
    // either half replaces that half and skips that cycle's increment;
    // the unwritten half is preserved.
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            mcycle_reg <= 64'b0;
        end else if (write_mcycle) begin
            mcycle_reg <= {mcycle_reg[63:32], csr_modified_value};
        end else if (write_mcycleh) begin
            mcycle_reg <= {csr_modified_value, mcycle_reg[31:0]};
        end else begin
            mcycle_reg <= mcycle_reg + 64'd1;
        end
    end

    // =========================================================================
    // minstret update — csr_write_op (low/high) > tick. Increments only when
    // instret_tick is asserted; otherwise holds. Phase 1.1 ties instret_tick
    // to the core's retirement signal; Phase 1.0 testbench drives it directly.
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            minstret_reg <= 64'b0;
        end else if (write_minstret) begin
            minstret_reg <= {minstret_reg[63:32], csr_modified_value};
        end else if (write_minstreth) begin
            minstret_reg <= {csr_modified_value, minstret_reg[31:0]};
        end else if (instret_tick) begin
            minstret_reg <= minstret_reg + 64'd1;
        end
    end

    // =========================================================================
    // Outputs to core
    // =========================================================================
    assign mtvec_o       = mtvec_reg;
    assign mepc_o        = mepc_reg;
    assign mstatus_mie_o = mstatus_mie;
    assign mstatus_o     = mstatus_val;

    // =========================================================================
    // Simulation-only assertion: trap_enter and trap_return are mutually
    // exclusive. Phase 1.2's trap FSM must never assert both in the same
    // cycle (one is for taking a trap, the other for MRET-returning from
    // one — they cannot overlap by construction).
    // =========================================================================
`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (!rst && trap_enter && trap_return) begin
            $display("[csr_file] FATAL @%0t: trap_enter and trap_return asserted in same cycle",
                     $time);
            $finish;
        end
    end
`endif

endmodule
