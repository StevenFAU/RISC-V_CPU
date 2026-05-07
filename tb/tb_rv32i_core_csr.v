// Integration testbench — rv32i_core + csr_file (Phase 1.1 + 1.2.0 + 1.2.1)
//
// Exercises the SYSTEM-opcode + CSR-instruction integration path and the
// Phase 1.2.x trap-entry path. NOT a compliance test — directed, scenario-
// by-scenario. Each test is a tiny asm sequence (3-7 instructions ending
// with `j .`) loaded into a unified word-addressed memory; the harness
// runs for a fixed cycle budget and samples regfile / CSR storage via
// hierarchical references.
//
// Test programs are built from typed encoding helpers (enc_addi / enc_lui
// / enc_csrrw / enc_jal / enc_jalr / enc_beq / etc.) so the literal hex
// never appears in the test bodies.
//
// Coverage map (24 directed tests):
//   1.  CSRRW round-trip — write 0xDEADBEEF, read back via CSRRS.
//   2.  CSRRS set        — 0x00FF |= 0xF000 -> 0xF0FF.
//   3.  CSRRC clear      — 0xF0FF &= ~0x00F0 -> 0xF00F.
//   4.  CSRRS rs1=x0     — read-only, no write side effect.
//   5.  CSRRW rd=x0      — write happens, x0 stays 0.
//   6.  CSRRWI           — 5-bit immediate write path.
//   7.  Write to RO      — CSRRW mvendorid pulses illegal_inst_o.
//   8.  Read unimpl      — CSRRS 0x7C0 returns 0 + illegal_inst_o pulses.
//   9.  minstret count   — retired-instruction counter via CSRRS.
//   10. mcycle delta     — two reads, verify delta matches instruction count.
//   11. CSRRSI zimm=0    — read-only, no write.
//   12. CSRRCI zimm=0    — read-only, no write.
//   13. CSRRC normal     — non-zero rs1 clears bits, rd captures OLD value.
//   14. CSRRW read+write — rd captures OLD CSR, CSR captures NEW rs1.
//   15. ECALL trap entry — full check (mepc, mcause, MIE/MPIE, PC redirect,
//                          instret_tick gate, illegal_inst_o quiet).
//   16. ECALL with MIE=0 going in — MPIE captures 0 (preserves prior MIE).
//   17. ECALL with different mtvec value — confirms PC mux selects mtvec_i.
//   18. EBREAK trap entry — mepc/mcause=3/mtval=0/MIE-MPIE/PC redirect,
//                            instret gate, illegal_inst_o quiet.
//   19. illegal_inst trap entry + observable regfile_we gate — CSRRW to RO
//                            mvendorid clobber-attempt; sentinel x5 survives.
//                            mtval = the 32-bit illegal instruction word.
//   20. inst_addr_misaligned via JAL — misaligned offset, mtval=target.
//   21. inst_addr_misaligned via taken BEQ — same.
//   22. BEQ NOT-taken with misaligned imm — must NOT trap (target never fetched).
//   23. inst_addr_misaligned via JALR (target[1]=1 after mask) — trap fires.
//   24. JALR with imm[0]=1 (masked) — must NOT trap; verifies bit-0 mask
//                            is applied BEFORE misalignment detection.

`timescale 1ns/1ps
`include "defines.v"

module tb_rv32i_core_csr;

    parameter MEM_DEPTH = 256;          // word-addressed
    parameter CYCLES_PER_TEST = 50;     // generous for any 3-7-instr sequence

    // -------------------------------------------------------------------------
    // Clock + reset
    // -------------------------------------------------------------------------
    reg clk;
    reg rst;
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Unified word-addressed memory (instruction fetch only; DMEM tied off)
    // -------------------------------------------------------------------------
    reg [31:0] mem [0:MEM_DEPTH-1];

    // -------------------------------------------------------------------------
    // Core bus signals
    // -------------------------------------------------------------------------
    wire [31:0] imem_addr, imem_addr_next, imem_data;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] dmem_addr, dmem_wdata;
    wire        dmem_we, dmem_re;
    wire [2:0]  dmem_funct3;
    wire [31:0] debug_pc, debug_instr;
    wire [31:0] imem_addr_next_dummy = imem_addr_next; // silence unused
    /* verilator lint_on UNUSEDSIGNAL */

    // CSR-interface
    wire [11:0] csr_addr;
    wire        csr_read_en;
    wire [2:0]  csr_write_op;
    wire [31:0] csr_write_data;
    wire [31:0] csr_read_data;
    wire        csr_illegal;
    wire        instret_tick;
    wire        illegal_inst;
    wire [31:0] csr_mtvec, csr_mepc;
    wire        csr_mstatus_mie;

    // Phase 1.2.0 trap-entry signals from core to csr_file
    wire        trap_enter;
    wire [31:0] trap_pc;
    wire [31:0] trap_cause;
    wire [31:0] trap_tval;

    // -------------------------------------------------------------------------
    // IMEM read: combinational, word-addressed.
    // imem_addr[31:2] indexes mem[]. PC stays small (<= 50 bytes) for these
    // tests, so the natural truncation to MEM_DEPTH is harmless.
    // -------------------------------------------------------------------------
    assign imem_data = mem[imem_addr[31:2]];

    // DMEM tied off — no test sequence executes a load/store.
    assign dmem_rdata = 32'd0;
    wire [31:0] dmem_rdata;
    /* verilator lint_off UNUSEDSIGNAL */
    wire dmem_re_unused = dmem_re;
    wire dmem_we_unused = dmem_we;
    /* verilator lint_on UNUSEDSIGNAL */

    // -------------------------------------------------------------------------
    // DUT — core
    // -------------------------------------------------------------------------
    rv32i_core u_core (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_data(imem_data),
        .imem_addr_next(imem_addr_next),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_rdata(dmem_rdata), .dmem_we(dmem_we),
        .dmem_re(dmem_re), .dmem_funct3(dmem_funct3),
        .csr_addr_o(csr_addr),
        .csr_read_en_o(csr_read_en),
        .csr_write_op_o(csr_write_op),
        .csr_write_data_o(csr_write_data),
        .csr_read_data_i(csr_read_data),
        .csr_illegal_i(csr_illegal),
        .instret_tick_o(instret_tick),
        .illegal_inst_o(illegal_inst),
        .trap_enter_o(trap_enter),
        .trap_pc_o(trap_pc),
        .trap_cause_o(trap_cause),
        .trap_tval_o(trap_tval),
        .mtvec_i(csr_mtvec),
        .mepc_i(csr_mepc),
        .mstatus_mie_i(csr_mstatus_mie),
        .debug_pc(debug_pc), .debug_instr(debug_instr)
    );

    // -------------------------------------------------------------------------
    // DUT — csr_file (Phase 1.2.0: trap-entry inputs now driven by the core's
    // trap encoder, mirroring fpga_top wiring; trap_return stays tied 0
    // until 1.2.2's MRET decode lands)
    // -------------------------------------------------------------------------
    /* verilator lint_off PINCONNECTEMPTY */
    csr_file u_csr_file (
        .clk(clk), .rst(rst),
        .csr_addr(csr_addr),
        .csr_read_en(csr_read_en),
        .csr_write_op(csr_write_op),
        .csr_write_data(csr_write_data),
        .csr_read_data(csr_read_data),
        .csr_illegal(csr_illegal),
        .trap_enter(trap_enter),
        .trap_pc(trap_pc),
        .trap_cause(trap_cause),
        .trap_tval(trap_tval),
        .trap_return(1'b0),
        .instret_tick(instret_tick),
        .mtvec_o(csr_mtvec),
        .mepc_o(csr_mepc),
        .mstatus_mie_o(csr_mstatus_mie),
        .mstatus_o()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // -------------------------------------------------------------------------
    // Illegal-instruction capture — latches on any illegal_inst pulse during
    // the test sequence. Cleared by reset (which begin_test pulses).
    // -------------------------------------------------------------------------
    reg seen_illegal;
    always @(posedge clk) begin
        if (rst)
            seen_illegal <= 1'b0;
        else if (illegal_inst)
            seen_illegal <= 1'b1;
    end

    // -------------------------------------------------------------------------
    // Phase 1.2.0 trap-entry probes:
    //   seen_trap_enter            — latches on any trap_enter pulse.
    //   trap_with_instret_observed — latches if trap_enter && instret_tick are
    //                                ever asserted in the same cycle (must
    //                                stay 0 — trapping instructions don't
    //                                retire, see Decision #8 in the 1.2.0
    //                                handoff).
    // Both clear on reset (begin_test pulses reset).
    // -------------------------------------------------------------------------
    reg seen_trap_enter;
    reg trap_with_instret_observed;
    always @(posedge clk) begin
        if (rst) begin
            seen_trap_enter            <= 1'b0;
            trap_with_instret_observed <= 1'b0;
        end else begin
            if (trap_enter)
                seen_trap_enter <= 1'b1;
            if (trap_enter && instret_tick)
                trap_with_instret_observed <= 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Test bookkeeping
    // -------------------------------------------------------------------------
    integer pass_n = 0;
    integer fail_n = 0;
    integer test_num = 0;

    // -------------------------------------------------------------------------
    // CSR address localparams (mirror csr_file.v)
    // -------------------------------------------------------------------------
    localparam [11:0] MSCRATCH   = 12'h340;
    localparam [11:0] MVENDORID  = 12'hF11;
    localparam [11:0] MINSTRET   = 12'hB02;
    localparam [11:0] MCYCLE     = 12'hB00;
    localparam [11:0] CSR_UNIMPL = 12'h7C0;
    // Phase 1.2.0 — trap-entry test set
    localparam [11:0] MSTATUS    = 12'h300;
    localparam [11:0] MTVEC      = 12'h305;
    localparam [11:0] MEPC       = 12'h341;
    localparam [11:0] MCAUSE     = 12'h342;

    // -------------------------------------------------------------------------
    // Encoding helpers — typed instruction builders.
    // -------------------------------------------------------------------------
    function [31:0] enc_addi;
        input [4:0] rd;
        input [4:0] rs1;
        input [11:0] imm;
        begin enc_addi = {imm, rs1, 3'b000, rd, 7'b0010011}; end
    endfunction

    function [31:0] enc_lui;
        input [4:0] rd;
        input [19:0] imm;
        begin enc_lui = {imm, rd, 7'b0110111}; end
    endfunction

    function [31:0] enc_sub;
        input [4:0] rd;
        input [4:0] rs1;
        input [4:0] rs2;
        begin enc_sub = {7'b0100000, rs2, rs1, 3'b000, rd, 7'b0110011}; end
    endfunction

    function [31:0] enc_csr_reg;     // CSRRW/CSRRS/CSRRC (funct3 in [2:0])
        input [4:0]  rd;
        input [4:0]  rs1;
        input [11:0] csr;
        input [2:0]  funct3;
        begin enc_csr_reg = {csr, rs1, funct3, rd, 7'b1110011}; end
    endfunction

    function [31:0] enc_csr_imm;     // CSRRWI/CSRRSI/CSRRCI
        input [4:0]  rd;
        input [4:0]  zimm;
        input [11:0] csr;
        input [2:0]  funct3;
        begin enc_csr_imm = {csr, zimm, funct3, rd, 7'b1110011}; end
    endfunction

    localparam [31:0] HALT = 32'h0000006F;   // J . == JAL x0, 0

    // ECALL  — SYSTEM (0x73), funct3=000, imm12=0x000, rs1=0, rd=0.
    // EBREAK — SYSTEM (0x73), funct3=000, imm12=0x001, rs1=0, rd=0.
    // localparams (not functions) — Verilog-2001 forbids zero-port functions.
    localparam [31:0] ECALL  = 32'h00000073;
    localparam [31:0] EBREAK = 32'h00100073;

    // J-type encoder. imm[0] is implicit zero per the JAL encoding (imm[0]
    // bit is not present in the instruction word). Caller passes a 21-bit
    // imm where imm[0] is ignored; only imm[20:1] is encoded.
    function [31:0] enc_jal;
        input [4:0]  rd;
        input [20:0] imm;
        begin
            enc_jal = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
        end
    endfunction

    // I-type JALR. imm12 is signed; the resulting target has bit 0 force-
    // zeroed by spec (the core applies the & ~32'b1 mask).
    function [31:0] enc_jalr;
        input [4:0]  rd;
        input [4:0]  rs1;
        input [11:0] imm;
        begin
            enc_jalr = {imm, rs1, 3'b000, rd, 7'b1100111};
        end
    endfunction

    // B-type encoder. funct3 selects the branch flavor (BEQ=000, BNE=001,
    // ...). imm[0] is implicit zero per the B encoding.
    function [31:0] enc_branch;
        input [4:0]  rs1;
        input [4:0]  rs2;
        input [2:0]  funct3;
        input [12:0] imm;
        begin
            enc_branch = {imm[12], imm[10:5], rs2, rs1, funct3,
                          imm[4:1], imm[11], 7'b1100011};
        end
    endfunction
    function [31:0] beq;
        input [4:0]  rs1;
        input [4:0]  rs2;
        input [12:0] imm;
        begin beq = enc_branch(rs1, rs2, 3'b000, imm); end
    endfunction

    // Convenience wrappers
    function [31:0] csrrw;  input [4:0] rd, rs1; input [11:0] csr;
        begin csrrw  = enc_csr_reg(rd, rs1, csr, 3'b001); end
    endfunction
    function [31:0] csrrs;  input [4:0] rd, rs1; input [11:0] csr;
        begin csrrs  = enc_csr_reg(rd, rs1, csr, 3'b010); end
    endfunction
    function [31:0] csrrc;  input [4:0] rd, rs1; input [11:0] csr;
        begin csrrc  = enc_csr_reg(rd, rs1, csr, 3'b011); end
    endfunction
    function [31:0] csrrwi; input [4:0] rd, zimm; input [11:0] csr;
        begin csrrwi = enc_csr_imm(rd, zimm, csr, 3'b101); end
    endfunction
    function [31:0] csrrsi; input [4:0] rd, zimm; input [11:0] csr;
        begin csrrsi = enc_csr_imm(rd, zimm, csr, 3'b110); end
    endfunction
    function [31:0] csrrci; input [4:0] rd, zimm; input [11:0] csr;
        begin csrrci = enc_csr_imm(rd, zimm, csr, 3'b111); end
    endfunction

    // -------------------------------------------------------------------------
    // Tasks
    // -------------------------------------------------------------------------
    task clear_mem;
        integer i;
        begin
            for (i = 0; i < MEM_DEPTH; i = i + 1)
                mem[i] = 32'h00000013;   // NOP = ADDI x0, x0, 0
        end
    endtask

    task clear_regs;
        integer i;
        begin
            // regfile.v has no synchronous reset path. Force-zero via
            // hierarchical reference between tests so register state
            // doesn't leak across scenarios.
            for (i = 0; i < 32; i = i + 1)
                u_core.u_regfile.regs[i] = 32'd0;
        end
    endtask

    task begin_test(input [8*64-1:0] desc);
        begin
            test_num = test_num + 1;
            $display("=== Test %0d: %0s ===", test_num, desc);
            clear_mem;
            // Pulse reset for two cycles — clears all CSRs (mscratch, mcycle,
            // minstret, mstatus, ...) and the PC. seen_illegal also clears
            // because the always-block has a sync-reset branch.
            rst = 1;
            @(posedge clk); @(posedge clk);
            // Force-zero the regfile (no built-in reset path).
            clear_regs;
            // Drop reset; from the next posedge onward the program runs.
            rst = 0;
        end
    endtask

    task run_for_cycles(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(posedge clk);
        end
    endtask

    task expect_eq32(input [8*64-1:0] desc,
                     input [31:0]      actual,
                     input [31:0]      expected);
        begin
            if (actual === expected) begin
                $display("  PASS: %0s = 0x%08h", desc, actual);
                pass_n = pass_n + 1;
            end else begin
                $display("  FAIL: %0s expected 0x%08h got 0x%08h",
                         desc, expected, actual);
                fail_n = fail_n + 1;
            end
        end
    endtask

    task expect_bool(input [8*64-1:0] desc,
                     input             actual,
                     input             expected);
        begin
            if (actual === expected) begin
                $display("  PASS: %0s = %0b", desc, actual);
                pass_n = pass_n + 1;
            end else begin
                $display("  FAIL: %0s expected %0b got %0b",
                         desc, expected, actual);
                fail_n = fail_n + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("sim/tb_rv32i_core_csr.vcd");
        $dumpvars(0, tb_rv32i_core_csr);

        rst = 1;

        // ---- TEST 1: CSRRW round-trip on mscratch ----
        // x1 = 0xDEADBEEF (LUI 0xDEADC + ADDI -273); CSRRW writes mscratch
        // (rd=x0 to keep x0 a control); CSRRS reads it back into x5.
        begin_test("CSRRW round-trip mscratch");
        mem[0] = enc_lui (5'd1, 20'hDEADC);
        mem[1] = enc_addi(5'd1, 5'd1, 12'hEEF);     // -273
        mem[2] = csrrw   (5'd0, 5'd1, MSCRATCH);
        mem[3] = csrrs   (5'd5, 5'd0, MSCRATCH);
        mem[4] = HALT;
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("x1 = 0xDEADBEEF",       u_core.u_regfile.regs[1], 32'hDEADBEEF);
        expect_eq32("mscratch = 0xDEADBEEF", u_csr_file.mscratch_reg,  32'hDEADBEEF);
        expect_eq32("x5 readback",            u_core.u_regfile.regs[5], 32'hDEADBEEF);

        // ---- TEST 2: CSRRS set ----
        begin_test("CSRRS set 0xF000 over 0x00FF");
        mem[0] = enc_addi(5'd1, 5'd0, 12'h0FF);
        mem[1] = csrrw   (5'd0, 5'd1, MSCRATCH);
        mem[2] = enc_lui (5'd2, 20'h0000F);          // x2 = 0xF000
        mem[3] = csrrs   (5'd0, 5'd2, MSCRATCH);
        mem[4] = HALT;
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("mscratch = 0xF0FF", u_csr_file.mscratch_reg, 32'h0000F0FF);

        // ---- TEST 3: CSRRC clear ----
        begin_test("CSRRC clear 0x00F0 over 0xF0FF");
        mem[0] = enc_addi(5'd1, 5'd0, 12'h0FF);
        mem[1] = csrrw   (5'd0, 5'd1, MSCRATCH);
        mem[2] = enc_lui (5'd2, 20'h0000F);
        mem[3] = csrrs   (5'd0, 5'd2, MSCRATCH);     // -> 0xF0FF
        mem[4] = enc_addi(5'd3, 5'd0, 12'h0F0);
        mem[5] = csrrc   (5'd0, 5'd3, MSCRATCH);     // &= ~0x0F0 -> 0xF00F
        mem[6] = HALT;
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("mscratch = 0xF00F", u_csr_file.mscratch_reg, 32'h0000F00F);

        // ---- TEST 4: CSRRS rs1=x0 — no write ----
        begin_test("CSRRS rs1=x0 leaves storage unchanged");
        mem[0] = enc_addi(5'd1, 5'd0, 12'h7AB);
        mem[1] = csrrw   (5'd0, 5'd1, MSCRATCH);     // mscratch = 0x7AB
        mem[2] = csrrs   (5'd5, 5'd0, MSCRATCH);     // read only — rs1=x0, no write
        mem[3] = HALT;
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("mscratch unchanged 0x7AB", u_csr_file.mscratch_reg,  32'h000007AB);
        expect_eq32("x5 = 0x7AB",                u_core.u_regfile.regs[5], 32'h000007AB);

        // ---- TEST 5: CSRRW rd=x0 — write still happens ----
        begin_test("CSRRW rd=x0 writes; x0 stays 0");
        mem[0] = enc_addi(5'd1, 5'd0, 12'h111);
        mem[1] = csrrw   (5'd0, 5'd1, MSCRATCH);
        mem[2] = HALT;
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("mscratch = 0x111", u_csr_file.mscratch_reg,  32'h00000111);
        expect_eq32("x0 stays 0",        u_core.u_regfile.regs[0], 32'h00000000);

        // ---- TEST 6: CSRRWI 5-bit immediate ----
        begin_test("CSRRWI writes 5-bit zimm");
        mem[0] = csrrwi(5'd5, 5'd17, MSCRATCH);      // x5 = old (0); mscratch <- 17
        mem[1] = HALT;
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("mscratch = 17", u_csr_file.mscratch_reg,  32'd17);
        expect_eq32("x5 = old (0)",  u_core.u_regfile.regs[5], 32'd0);

        // ---- TEST 7: Write to RO mvendorid ----
        begin_test("CSRRW to mvendorid (RO) pulses illegal");
        mem[0] = enc_addi(5'd1, 5'd0, 12'h456);
        mem[1] = csrrw   (5'd0, 5'd1, MVENDORID);    // attempt write to RO
        mem[2] = HALT;
        run_for_cycles(CYCLES_PER_TEST);
        expect_bool("illegal_inst pulsed (RO write)", seen_illegal, 1'b1);

        // ---- TEST 8: Read unimplemented CSR ----
        begin_test("CSRRS read unimpl 0x7C0 pulses illegal");
        mem[0] = csrrs(5'd5, 5'd0, CSR_UNIMPL);
        mem[1] = HALT;
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("x5 = 0 (unimpl returns 0)", u_core.u_regfile.regs[5], 32'd0);
        expect_bool("illegal_inst pulsed (unimpl)", seen_illegal,           1'b1);

        // ---- TEST 9: minstret count ----
        // CSRRS at PC=12 is the 4th instruction; minstret_reg=3 going in.
        begin_test("CSRRS minstret returns retired count");
        mem[0] = enc_addi(5'd1, 5'd0, 12'd1);
        mem[1] = enc_addi(5'd1, 5'd0, 12'd2);
        mem[2] = enc_addi(5'd1, 5'd0, 12'd3);
        mem[3] = csrrs   (5'd5, 5'd0, MINSTRET);
        mem[4] = HALT;
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("x5 = 3", u_core.u_regfile.regs[5], 32'd3);

        // ---- TEST 10: mcycle delta ----
        begin_test("mcycle increments each cycle");
        mem[0] = csrrs   (5'd5, 5'd0, MCYCLE);       // x5 = 0
        mem[1] = enc_addi(5'd1, 5'd0, 12'd0);
        mem[2] = enc_addi(5'd1, 5'd0, 12'd0);
        mem[3] = csrrs   (5'd6, 5'd0, MCYCLE);       // x6 = 3
        mem[4] = enc_sub (5'd7, 5'd6, 5'd5);          // x7 = 3
        mem[5] = HALT;
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("x5 = 0 (cycle at I0)", u_core.u_regfile.regs[5], 32'd0);
        expect_eq32("x6 = 3 (cycle at I3)", u_core.u_regfile.regs[6], 32'd3);
        expect_eq32("x7 = x6 - x5 = 3",      u_core.u_regfile.regs[7], 32'd3);

        // ---- TEST 11: CSRRSI zimm=0 — no write ----
        begin_test("CSRRSI zimm=0 leaves storage unchanged");
        mem[0] = enc_addi(5'd1, 5'd0, 12'h234);
        mem[1] = csrrw   (5'd0, 5'd1, MSCRATCH);
        mem[2] = csrrsi  (5'd5, 5'd0, MSCRATCH);     // zimm=0 -> read-only
        mem[3] = HALT;
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("mscratch unchanged 0x234", u_csr_file.mscratch_reg,  32'h00000234);
        expect_eq32("x5 = 0x234",                u_core.u_regfile.regs[5], 32'h00000234);

        // ---- TEST 12: CSRRCI zimm=0 — no write ----
        begin_test("CSRRCI zimm=0 leaves storage unchanged");
        mem[0] = enc_addi(5'd1, 5'd0, 12'h345);
        mem[1] = csrrw   (5'd0, 5'd1, MSCRATCH);
        mem[2] = csrrci  (5'd5, 5'd0, MSCRATCH);     // zimm=0 -> read-only
        mem[3] = HALT;
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("mscratch unchanged 0x345", u_csr_file.mscratch_reg,  32'h00000345);
        expect_eq32("x5 = 0x345",                u_core.u_regfile.regs[5], 32'h00000345);

        // ---- TEST 13: CSRRC normal-clear with rd capturing OLD ----
        begin_test("CSRRC normal: rd=OLD, CSR cleared");
        mem[0] = enc_addi(5'd1, 5'd0, 12'h7FF);
        mem[1] = csrrw   (5'd0, 5'd1, MSCRATCH);     // mscratch = 0x7FF
        mem[2] = enc_addi(5'd2, 5'd0, 12'h00F);
        mem[3] = csrrc   (5'd5, 5'd2, MSCRATCH);     // x5=0x7FF (old); mscratch &= ~0x00F = 0x7F0
        mem[4] = HALT;
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("mscratch = 0x7F0",  u_csr_file.mscratch_reg,  32'h000007F0);
        expect_eq32("x5 = 0x7FF (old)",   u_core.u_regfile.regs[5], 32'h000007FF);

        // ---- TEST 14: CSRRW simultaneous read+write (rd=OLD, CSR=NEW) ----
        begin_test("CSRRW: rd captures OLD, CSR captures NEW");
        mem[0] = enc_addi(5'd1, 5'd0, 12'h0AA);
        mem[1] = csrrw   (5'd0, 5'd1, MSCRATCH);     // mscratch = 0xAA
        mem[2] = enc_addi(5'd2, 5'd0, 12'h0BB);
        mem[3] = csrrw   (5'd5, 5'd2, MSCRATCH);     // x5 <- 0xAA, mscratch <- 0xBB
        mem[4] = HALT;
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("x5 = 0x0AA (old)",       u_core.u_regfile.regs[5], 32'h000000AA);
        expect_eq32("mscratch = 0x0BB (new)",  u_csr_file.mscratch_reg,  32'h000000BB);

        // =====================================================================
        // Phase 1.2.0 — ECALL trap-entry directed tests
        // =====================================================================

        // ---- TEST 15: ECALL trap entry — full check ----
        // mtvec = 0x40 (= byte 64, mem[16]). Pre-trap mstatus.MIE = 1.
        // ECALL at PC=16 (= mem[4]). Expectations:
        //   mepc          == 0x10 (PC of the ECALL itself)
        //   mcause        == 0x0B (M-mode environment call, cause code 11)
        //   mstatus.MIE   == 0    (trap entry cleared MIE)
        //   mstatus.MPIE  == 1    (captures pre-trap MIE=1)
        //   debug_pc      == 0x40 (handler — at HALT, looping)
        //   trap_enter pulsed at least once
        //   trap_enter && instret_tick never asserted in the same cycle
        //   illegal_inst_o never pulsed (ECALL is legal in 1.2.0)
        begin_test("ECALL: trap entry (mepc/mcause/mstatus/PC, instret gate)");
        mem[0]  = enc_addi(5'd1, 5'd0, 12'h040);   // x1 = 0x40 (mtvec target)
        mem[1]  = csrrw   (5'd0, 5'd1, MTVEC);      // mtvec = 0x40
        mem[2]  = enc_addi(5'd2, 5'd0, 12'h008);   // x2 = MIE bit (3)
        mem[3]  = csrrw   (5'd0, 5'd2, MSTATUS);    // mstatus.MIE <- 1
        mem[4]  = ECALL;                        // PC=0x10 — trap here
        mem[5]  = HALT;                             // (unreached if trap works)
        mem[16] = HALT;                             // handler: just halt (no MRET in 1.2.0)
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("mepc captures ECALL PC (0x10)",
                    u_csr_file.mepc_reg,             32'h00000010);
        expect_eq32("mcause = 0x0B (env call)",
                    u_csr_file.mcause_reg,           32'h0000000B);
        expect_bool("mstatus.MIE  cleared to 0",
                    u_csr_file.mstatus_mie,          1'b0);
        expect_bool("mstatus.MPIE captured pre-trap MIE=1",
                    u_csr_file.mstatus_mpie,         1'b1);
        expect_eq32("PC redirected to mtvec (0x40)",
                    debug_pc,                        32'h00000040);
        expect_bool("trap_enter pulsed",
                    seen_trap_enter,                 1'b1);
        expect_bool("instret_tick gated on trap-entry cycle",
                    trap_with_instret_observed,      1'b0);
        expect_bool("illegal_inst_o quiet (ECALL is legal)",
                    seen_illegal,                    1'b0);

        // ---- TEST 16: ECALL with MIE=0 going in — MPIE captures 0 ----
        // Reset gives mstatus.MIE=0; we skip the explicit MIE write.
        // After trap entry, MPIE should latch 0 (the prior MIE).
        begin_test("ECALL: pre-trap MIE=0 -> MPIE captures 0");
        mem[0]  = enc_addi(5'd1, 5'd0, 12'h040);
        mem[1]  = csrrw   (5'd0, 5'd1, MTVEC);      // mtvec = 0x40, MIE stays 0
        mem[2]  = ECALL;                        // PC=0x08 — trap here
        mem[3]  = HALT;
        mem[16] = HALT;                             // handler
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("mepc captures ECALL PC (0x08)",
                    u_csr_file.mepc_reg,             32'h00000008);
        expect_bool("mstatus.MIE  stays 0",
                    u_csr_file.mstatus_mie,          1'b0);
        expect_bool("mstatus.MPIE captured pre-trap MIE=0",
                    u_csr_file.mstatus_mpie,         1'b0);

        // ---- TEST 17: ECALL with a different mtvec value ----
        // mtvec = 0x80 (= byte 128, mem[32]). Confirms PC mux selects mtvec_i
        // rather than a hardwired constant.
        begin_test("ECALL: PC redirect uses mtvec_i (mtvec=0x80)");
        mem[0]  = enc_addi(5'd1, 5'd0, 12'h080);   // x1 = 0x80
        mem[1]  = csrrw   (5'd0, 5'd1, MTVEC);      // mtvec = 0x80
        mem[2]  = ECALL;                        // PC=0x08 — trap here
        mem[3]  = HALT;
        mem[32] = HALT;                             // handler at 0x80
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("PC redirected to mtvec (0x80)",
                    debug_pc,                        32'h00000080);
        expect_eq32("mepc captures ECALL PC (0x08)",
                    u_csr_file.mepc_reg,             32'h00000008);
        expect_eq32("mcause = 0x0B (env call)",
                    u_csr_file.mcause_reg,           32'h0000000B);

        // =====================================================================
        // Phase 1.2.1 — EBREAK / illegal_inst / inst_addr_misaligned
        // =====================================================================

        // ---- TEST 18: EBREAK trap entry — full check ----
        // mtvec = 0x40, pre-trap MIE = 1. EBREAK at PC = 0x10 (mem[4]).
        // Expect: mepc=0x10, mcause=3, mtval=0 (per spec), MIE/MPIE rotate,
        // PC redirected to mtvec, instret_tick gated on the trap cycle,
        // illegal_inst_o quiet (EBREAK is now legal as of 1.2.1's carve-out).
        begin_test("EBREAK: trap entry (mepc/mcause=3/mtval=0/mstatus, gates)");
        mem[0]  = enc_addi(5'd1, 5'd0, 12'h040);
        mem[1]  = csrrw   (5'd0, 5'd1, MTVEC);
        mem[2]  = enc_addi(5'd2, 5'd0, 12'h008);
        mem[3]  = csrrw   (5'd0, 5'd2, MSTATUS);    // MIE <- 1
        mem[4]  = EBREAK;                           // PC = 0x10
        mem[5]  = HALT;                             // unreached
        mem[16] = HALT;                             // handler at 0x40
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("mepc captures EBREAK PC (0x10)",
                    u_csr_file.mepc_reg,             32'h00000010);
        expect_eq32("mcause = 0x03 (breakpoint)",
                    u_csr_file.mcause_reg,           32'h00000003);
        expect_eq32("mtval = 0 (EBREAK has no tval per spec)",
                    u_csr_file.mtval_reg,            32'h00000000);
        expect_bool("mstatus.MIE  cleared to 0",
                    u_csr_file.mstatus_mie,          1'b0);
        expect_bool("mstatus.MPIE captured pre-trap MIE=1",
                    u_csr_file.mstatus_mpie,         1'b1);
        expect_eq32("PC redirected to mtvec (0x40)",
                    debug_pc,                        32'h00000040);
        expect_bool("trap_enter pulsed",
                    seen_trap_enter,                 1'b1);
        expect_bool("instret_tick gated on trap-entry cycle",
                    trap_with_instret_observed,      1'b0);
        expect_bool("illegal_inst_o quiet (EBREAK is legal in 1.2.1)",
                    seen_illegal,                    1'b0);

        // ---- TEST 19: illegal_inst trap + observable regfile_we gate ----
        // The 1.2.0 regfile_we gate (`reg_write & ~trap_enter_w`) is
        // structurally a no-op for ECALL/EBREAK (decoder forces reg_write=0
        // on SYSTEM funct3=0). It IS observable on the CSR-illegal path:
        // CSRRW to a RO CSR pulses csr_illegal_i AND keeps reg_write=1
        // (since is_csr=1), so without the gate the trap cycle would
        // clobber rd with the (zero-valued) RO read. The sentinel test
        // here demonstrates the gate prevents that clobber.
        //
        // This is the only path in the current core where illegal_inst_o
        // pulses while reg_write would otherwise be 1 — control.v's
        // default branch keeps reg_write=0 for true unknown opcodes, so a
        // genuine "illegal opcode" trigger does not exercise the gate.
        // Verifying the gate via CSR-illegal still tests the same RTL gate
        // (line in rv32i_core.v: `regfile.we(reg_write & ~trap_enter_w)`).
        begin_test("illegal_inst: regfile_we gate preserves sentinel x5");
        mem[0]  = enc_addi(5'd1, 5'd0, 12'h080);
        mem[1]  = csrrw   (5'd0, 5'd1, MTVEC);      // mtvec = 0x80
        mem[2]  = enc_lui (5'd5, 20'hDEADC);        // x5 = 0xDEADC000
        mem[3]  = enc_addi(5'd5, 5'd5, 12'hEEF);    // x5 = 0xDEADBEEF (sentinel)
        mem[4]  = csrrw   (5'd5, 5'd1, MVENDORID);  // PC=0x10. RO write.
        mem[5]  = HALT;                             // unreached
        mem[32] = HALT;                             // handler at 0x80
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("mepc captures illegal-inst PC (0x10)",
                    u_csr_file.mepc_reg,             32'h00000010);
        expect_eq32("mcause = 0x02 (illegal instruction)",
                    u_csr_file.mcause_reg,           32'h00000002);
        expect_eq32("mtval = encoded illegal instruction word",
                    u_csr_file.mtval_reg,
                    csrrw(5'd5, 5'd1, MVENDORID));
        expect_eq32("x5 sentinel preserved (regfile_we gate proven)",
                    u_core.u_regfile.regs[5],        32'hDEADBEEF);
        expect_eq32("PC redirected to mtvec (0x80)",
                    debug_pc,                        32'h00000080);
        expect_bool("trap_enter pulsed",
                    seen_trap_enter,                 1'b1);
        expect_bool("instret_tick gated on trap-entry cycle",
                    trap_with_instret_observed,      1'b0);

        // ---- TEST 20: inst_addr_misaligned via JAL ----
        // JAL with imm[1]=1 produces a misaligned target. PC=0x10, imm=6,
        // target = 0x16. Trap fires on the JAL's cycle; the misaligned
        // fetch never happens (PC redirects to mtvec).
        begin_test("inst_addr_misaligned via JAL with imm[1]=1");
        mem[0]  = enc_addi(5'd1, 5'd0, 12'h040);
        mem[1]  = csrrw   (5'd0, 5'd1, MTVEC);
        mem[2]  = enc_addi(5'd2, 5'd0, 12'h008);
        mem[3]  = csrrw   (5'd0, 5'd2, MSTATUS);
        mem[4]  = enc_jal (5'd0, 21'h000006);       // PC=0x10, target=0x16
        mem[5]  = HALT;
        mem[16] = HALT;                             // handler at 0x40
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("mepc captures JAL PC (0x10)",
                    u_csr_file.mepc_reg,             32'h00000010);
        expect_eq32("mcause = 0x00 (inst_addr_misaligned)",
                    u_csr_file.mcause_reg,           32'h00000000);
        expect_eq32("mtval = misaligned target (0x16)",
                    u_csr_file.mtval_reg,            32'h00000016);
        expect_eq32("PC redirected to mtvec (0x40)",
                    debug_pc,                        32'h00000040);
        expect_bool("trap_enter pulsed",
                    seen_trap_enter,                 1'b1);

        // ---- TEST 21: inst_addr_misaligned via taken BEQ ----
        // BEQ with operands equal (taken) and imm[1]=1. PC=0x10, imm=6,
        // target = 0x16. Detection condition: branch_taken && target[1:0]
        // != 0.
        begin_test("inst_addr_misaligned via taken BEQ with imm[1]=1");
        mem[0]  = enc_addi(5'd1, 5'd0, 12'h040);
        mem[1]  = csrrw   (5'd0, 5'd1, MTVEC);
        mem[2]  = enc_addi(5'd3, 5'd0, 12'h005);
        mem[3]  = enc_addi(5'd4, 5'd0, 12'h005);    // x3 == x4
        mem[4]  = beq     (5'd3, 5'd4, 13'h0006);   // PC=0x10, taken, target=0x16
        mem[5]  = HALT;
        mem[16] = HALT;
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("mepc captures BEQ PC (0x10)",
                    u_csr_file.mepc_reg,             32'h00000010);
        expect_eq32("mcause = 0x00",
                    u_csr_file.mcause_reg,           32'h00000000);
        expect_eq32("mtval = misaligned target (0x16)",
                    u_csr_file.mtval_reg,            32'h00000016);
        expect_eq32("PC redirected to mtvec (0x40)",
                    debug_pc,                        32'h00000040);
        expect_bool("trap_enter pulsed",
                    seen_trap_enter,                 1'b1);

        // ---- TEST 22: BEQ NOT-taken with misaligned imm — must NOT trap ----
        // x3 != x4 -> branch not taken -> misaligned target never fetched.
        // Detection condition is gated on branch_taken; trap must not fire.
        begin_test("BEQ not-taken with misaligned imm: NO trap fires");
        mem[0]  = enc_addi(5'd1, 5'd0, 12'h040);
        mem[1]  = csrrw   (5'd0, 5'd1, MTVEC);
        mem[2]  = enc_addi(5'd3, 5'd0, 12'h005);
        mem[3]  = enc_addi(5'd4, 5'd0, 12'h007);    // x3 != x4
        mem[4]  = beq     (5'd3, 5'd4, 13'h0006);   // PC=0x10, NOT taken
        mem[5]  = HALT;                             // PC=0x14 fall-through here
        mem[16] = HALT;
        run_for_cycles(CYCLES_PER_TEST);
        expect_bool("trap_enter never pulsed",
                    seen_trap_enter,                 1'b0);
        expect_eq32("mepc unchanged (still 0)",
                    u_csr_file.mepc_reg,             32'h00000000);
        expect_eq32("mcause unchanged (still 0)",
                    u_csr_file.mcause_reg,           32'h00000000);
        expect_eq32("mtval unchanged (still 0)",
                    u_csr_file.mtval_reg,            32'h00000000);
        expect_eq32("PC at fall-through HALT (0x14)",
                    debug_pc,                        32'h00000014);

        // ---- TEST 23: inst_addr_misaligned via JALR with target[1]=1 ----
        // x6 = 0x10, JALR imm=2 -> (0x10+2)&~1 = 0x12. target[1]=1 ->
        // misaligned. JALR is unconditional; the trap fires on JALR's
        // cycle.
        begin_test("inst_addr_misaligned via JALR target[1]=1 after mask");
        mem[0]  = enc_addi(5'd1, 5'd0, 12'h040);
        mem[1]  = csrrw   (5'd0, 5'd1, MTVEC);
        mem[2]  = enc_addi(5'd6, 5'd0, 12'h010);    // x6 = 0x10
        mem[3]  = enc_jalr(5'd0, 5'd6, 12'h002);    // PC=0x0C, target=0x12
        mem[4]  = HALT;
        mem[16] = HALT;
        run_for_cycles(CYCLES_PER_TEST);
        expect_eq32("mepc captures JALR PC (0x0C)",
                    u_csr_file.mepc_reg,             32'h0000000C);
        expect_eq32("mcause = 0x00",
                    u_csr_file.mcause_reg,           32'h00000000);
        expect_eq32("mtval = masked misaligned target (0x12)",
                    u_csr_file.mtval_reg,            32'h00000012);
        expect_eq32("PC redirected to mtvec (0x40)",
                    debug_pc,                        32'h00000040);
        expect_bool("trap_enter pulsed",
                    seen_trap_enter,                 1'b1);

        // ---- TEST 24: JALR with imm[0]=1 (masked) — must NOT trap ----
        // x6 = 0x10, JALR imm=1 -> (0x10+1)&~1 = 0x10. target[1]=0 -> no
        // trap. Verifies the spec-mandated bit-0 mask is applied BEFORE
        // misalignment detection: only target[1] participates in the
        // check on JALR. JALR also writes pc_plus4 to rd; we observe x7
        // to confirm the JALR completed (no trap suppressed it).
        begin_test("JALR with imm[0]=1 masked: NO trap, JALR completes");
        mem[0]  = enc_addi(5'd6, 5'd0, 12'h010);    // PC=0x00, x6 = 0x10
        mem[1]  = enc_jalr(5'd7, 5'd6, 12'h001);    // PC=0x04, target=0x10
        mem[2]  = HALT;                             // unreached
        mem[3]  = HALT;                             // unreached
        mem[4]  = HALT;                             // PC=0x10, JALR lands here
        run_for_cycles(CYCLES_PER_TEST);
        expect_bool("trap_enter never pulsed",
                    seen_trap_enter,                 1'b0);
        expect_eq32("x7 = pc_plus4 of JALR (0x08)",
                    u_core.u_regfile.regs[7],        32'h00000008);
        expect_eq32("PC at JALR-target HALT (0x10)",
                    debug_pc,                        32'h00000010);
        expect_eq32("mepc unchanged (still 0)",
                    u_csr_file.mepc_reg,             32'h00000000);
        expect_eq32("mcause unchanged (still 0)",
                    u_csr_file.mcause_reg,           32'h00000000);

        // ---- Summary ----
        $display("");
        $display("=== tb_rv32i_core_csr: %0d passed, %0d failed ===",
                 pass_n, fail_n);
        if (fail_n == 0)
            $display("ALL TESTS PASSED");
        else
            $display("*** SOME TESTS FAILED ***");
        $finish;
    end
endmodule
