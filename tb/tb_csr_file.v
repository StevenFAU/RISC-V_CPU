// Testbench — csr_file (Phase 1.0)
//
// Self-checking directed tests across 8 categories:
//   1. Reset values
//   2. Write-then-read for each R/W CSR
//   3. Read-only CSRs reject writes (csr_illegal asserts; storage doesn't change)
//   4. Set/clear (CSRRS/CSRRC) operations on mscratch
//   5. Counter behavior (mcycle free-runs; minstret gated by tick;
//      write/increment race for both)
//   6. Trap-entry side effects (mepc/mcause/mtval/mstatus update)
//   7. Trap-return side effects (mstatus.MIE <- MPIE; MPIE <- 1)
//   8. Priority — trap_enter beats csr_write_op on mepc in same cycle
//
// Driver convention (matches the Phase 1.1 instruction-decode wiring):
//   * Reads assert csr_read_en for one cycle and sample csr_read_data
//     combinationally that same cycle (read mux is purely combinational).
//   * Writes assert csr_write_op != 0 with csr_write_data and the new value
//     latches on the next posedge clk.
//
// Helper tasks (do_write/do_read/expect_eq) keep the bodies compact.

`timescale 1ns / 1ps

module tb_csr_file;

    // CSR address map (mirror of csr_file.v localparams) ---------------------
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

    localparam [2:0] OP_NONE  = 3'b000;
    localparam [2:0] OP_WRITE = 3'b001;
    localparam [2:0] OP_SET   = 3'b010;
    localparam [2:0] OP_CLEAR = 3'b011;

    // DUT ports --------------------------------------------------------------
    reg         clk, rst;
    reg  [11:0] csr_addr;
    reg         csr_read_en;
    reg  [2:0]  csr_write_op;
    reg  [31:0] csr_write_data;
    wire [31:0] csr_read_data;
    wire        csr_illegal;

    reg         trap_enter;
    reg  [31:0] trap_pc, trap_cause, trap_tval;
    reg         trap_return;
    reg         instret_tick;

    wire [31:0] mtvec_o, mepc_o, mstatus_o;
    wire        mstatus_mie_o;

    integer pass = 0, fail = 0;
    reg [31:0] tmp32;
    reg [31:0] inst_before;

    csr_file uut (
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
        .trap_return(trap_return),
        .instret_tick(instret_tick),
        .mtvec_o(mtvec_o),
        .mepc_o(mepc_o),
        .mstatus_mie_o(mstatus_mie_o),
        .mstatus_o(mstatus_o)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // -----------------------------------------------------------------------
    // Helper tasks
    // -----------------------------------------------------------------------

    // Idle the instruction-driven inputs (does not touch trap_*).
    task idle_inst;
        begin
            csr_addr       = 12'h000;
            csr_read_en    = 1'b0;
            csr_write_op   = OP_NONE;
            csr_write_data = 32'b0;
        end
    endtask

    // CSRRW: write `data` into `addr`. Latches on the next posedge clk; the
    // task returns just after #1 past that edge with inputs idled again.
    task do_write(input [11:0] addr, input [31:0] data);
        begin
            csr_addr       = addr;
            csr_read_en    = 1'b0;
            csr_write_op   = OP_WRITE;
            csr_write_data = data;
            @(posedge clk); #1;
            idle_inst;
        end
    endtask

    // CSRRS: set bits, then read back updated value (one combined task to
    // exercise the RMW path used by Cat 4).
    task do_set(input [11:0] addr, input [31:0] mask);
        begin
            csr_addr       = addr;
            csr_read_en    = 1'b0;
            csr_write_op   = OP_SET;
            csr_write_data = mask;
            @(posedge clk); #1;
            idle_inst;
        end
    endtask

    // CSRRC: clear bits.
    task do_clear(input [11:0] addr, input [31:0] mask);
        begin
            csr_addr       = addr;
            csr_read_en    = 1'b0;
            csr_write_op   = OP_CLEAR;
            csr_write_data = mask;
            @(posedge clk); #1;
            idle_inst;
        end
    endtask

    // Drive a read, sample combinationally, return value via output reg.
    task do_read(input [11:0] addr, output [31:0] value);
        begin
            csr_addr       = addr;
            csr_read_en    = 1'b1;
            csr_write_op   = OP_NONE;
            csr_write_data = 32'b0;
            #1;
            value = csr_read_data;
            idle_inst;
        end
    endtask

    // Drive a write attempt to a known-RO CSR, watch csr_illegal in the same
    // cycle, then idle. Returns the captured illegal flag for the caller to
    // assert against.
    task try_write_ro(input [11:0] addr, output illegal);
        begin
            csr_addr       = addr;
            csr_read_en    = 1'b0;
            csr_write_op   = OP_WRITE;
            csr_write_data = 32'hAAAA_5555;
            #1;
            illegal = csr_illegal;
            @(posedge clk); #1;
            idle_inst;
        end
    endtask

    task expect_eq32(input [255:0] label, input [31:0] got, input [31:0] want);
        begin
            if (got === want) begin
                $display("PASS: %0s = 0x%08h", label, got);
                pass = pass + 1;
            end else begin
                $display("FAIL: %0s = 0x%08h (want 0x%08h)", label, got, want);
                fail = fail + 1;
            end
        end
    endtask

    task expect_true(input [255:0] label, input cond);
        begin
            if (cond === 1'b1) begin
                $display("PASS: %0s", label);
                pass = pass + 1;
            end else begin
                $display("FAIL: %0s", label);
                fail = fail + 1;
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Stimulus
    // -----------------------------------------------------------------------
    initial begin
        // --- Reset ---
        rst          = 1'b1;
        idle_inst;
        trap_enter   = 1'b0;
        trap_return  = 1'b0;
        trap_pc      = 32'b0;
        trap_cause   = 32'b0;
        trap_tval    = 32'b0;
        instret_tick = 1'b0;

        repeat (3) @(posedge clk);
        rst = 1'b0;
        @(posedge clk); #1;

        // ====================================================================
        // Category 1: Reset values
        // mstatus_val composed: {19'b0, 2'b11(MPP), 3'b0, MPIE, 3'b0, MIE, 3'b0}
        //   = 0x0000_1800 with MIE=MPIE=0
        // ====================================================================
        $display("\n--- Category 1: Reset values ---");
        do_read(CSR_MSTATUS,   tmp32); expect_eq32("reset mstatus",   tmp32, 32'h0000_1800);
        do_read(CSR_MISA,      tmp32); expect_eq32("reset misa",      tmp32, 32'h4000_0100);
        do_read(CSR_MIE,       tmp32); expect_eq32("reset mie",       tmp32, 32'h0000_0000);
        do_read(CSR_MTVEC,     tmp32); expect_eq32("reset mtvec",     tmp32, 32'h0000_0000);
        do_read(CSR_MSCRATCH,  tmp32); expect_eq32("reset mscratch",  tmp32, 32'h0000_0000);
        do_read(CSR_MEPC,      tmp32); expect_eq32("reset mepc",      tmp32, 32'h0000_0000);
        do_read(CSR_MCAUSE,    tmp32); expect_eq32("reset mcause",    tmp32, 32'h0000_0000);
        do_read(CSR_MTVAL,     tmp32); expect_eq32("reset mtval",     tmp32, 32'h0000_0000);
        do_read(CSR_MIP,       tmp32); expect_eq32("reset mip",       tmp32, 32'h0000_0000);
        do_read(CSR_MVENDORID, tmp32); expect_eq32("reset mvendorid", tmp32, 32'h0000_0000);
        do_read(CSR_MARCHID,   tmp32); expect_eq32("reset marchid",   tmp32, 32'h0000_0000);
        do_read(CSR_MIMPID,    tmp32); expect_eq32("reset mimpid",    tmp32, 32'h0000_0000);
        do_read(CSR_MHARTID,   tmp32); expect_eq32("reset mhartid",   tmp32, 32'h0000_0000);

        expect_eq32("reset mtvec_o",     mtvec_o,     32'h0000_0000);
        expect_eq32("reset mepc_o",      mepc_o,      32'h0000_0000);
        expect_true("reset mstatus_mie_o == 0", mstatus_mie_o === 1'b0);

        // ====================================================================
        // Category 2: Write-then-read for each R/W CSR
        // Writes use CSRRW; readback verifies the per-CSR write mask.
        // ====================================================================
        $display("\n--- Category 2: Write-then-read R/W CSRs ---");

        // mscratch: full 32-bit, no mask
        do_write(CSR_MSCRATCH, 32'hCAFE_BABE);
        do_read(CSR_MSCRATCH, tmp32);
        expect_eq32("mscratch readback", tmp32, 32'hCAFE_BABE);

        // mtvec: low 2 bits forced to 0
        do_write(CSR_MTVEC, 32'h8000_0103);
        do_read(CSR_MTVEC, tmp32);
        expect_eq32("mtvec masks low 2 bits", tmp32, 32'h8000_0100);
        expect_eq32("mtvec_o reflects write", mtvec_o, 32'h8000_0100);

        // mepc: low 2 bits forced to 0
        do_write(CSR_MEPC, 32'h0000_4007);
        do_read(CSR_MEPC, tmp32);
        expect_eq32("mepc masks low 2 bits", tmp32, 32'h0000_4004);
        expect_eq32("mepc_o reflects write", mepc_o, 32'h0000_4004);

        // mcause: full 32-bit
        do_write(CSR_MCAUSE, 32'h8000_000B);
        do_read(CSR_MCAUSE, tmp32);
        expect_eq32("mcause readback", tmp32, 32'h8000_000B);

        // mtval: full 32-bit
        do_write(CSR_MTVAL, 32'h1234_5678);
        do_read(CSR_MTVAL, tmp32);
        expect_eq32("mtval readback", tmp32, 32'h1234_5678);

        // mstatus: write-mask is MIE (bit 3) + MPIE (bit 7); MPP=11 hardwired.
        // Write 0x0000_0088 → both MIE and MPIE set; readback = 0x0000_1888.
        do_write(CSR_MSTATUS, 32'h0000_0088);
        do_read(CSR_MSTATUS, tmp32);
        expect_eq32("mstatus MIE+MPIE set", tmp32, 32'h0000_1888);
        expect_true("mstatus_mie_o tracks MIE bit", mstatus_mie_o === 1'b1);

        // mie: mask is MEIE (11) + MTIE (7) + MSIE (3). Write 0x0000_0888.
        do_write(CSR_MIE, 32'h0000_0FFF);
        do_read(CSR_MIE, tmp32);
        expect_eq32("mie write-mask", tmp32, 32'h0000_0888);

        // mip: only MSIP (bit 3) is software-writable; MTIP/MEIP RO=0.
        do_write(CSR_MIP, 32'hFFFF_FFFF);
        do_read(CSR_MIP, tmp32);
        expect_eq32("mip MSIP-only writable", tmp32, 32'h0000_0008);

        // ====================================================================
        // Category 3: Read-only CSRs reject writes (csr_illegal asserts; the
        // RO storage value doesn't change).
        // ====================================================================
        $display("\n--- Category 3: RO CSRs reject writes ---");

        try_write_ro(CSR_MISA,      tmp32[0]);
        expect_true("misa write -> csr_illegal", tmp32[0] === 1'b1);
        do_read(CSR_MISA, tmp32);
        expect_eq32("misa unchanged after RO write", tmp32, 32'h4000_0100);

        try_write_ro(CSR_MVENDORID, tmp32[0]);
        expect_true("mvendorid write -> csr_illegal", tmp32[0] === 1'b1);

        try_write_ro(CSR_MHARTID,   tmp32[0]);
        expect_true("mhartid write -> csr_illegal", tmp32[0] === 1'b1);

        try_write_ro(CSR_CYCLE,     tmp32[0]);
        expect_true("cycle (user-RO alias) write -> csr_illegal", tmp32[0] === 1'b1);

        // Write to an unimplemented address: csr_illegal must assert.
        csr_addr       = 12'h7C0;
        csr_read_en    = 1'b0;
        csr_write_op   = OP_WRITE;
        csr_write_data = 32'hDEAD_BEEF;
        #1;
        expect_true("write to 0x7C0 -> csr_illegal", csr_illegal === 1'b1);
        @(posedge clk); #1;
        idle_inst;

        // Read of an unimplemented address: csr_illegal must assert.
        csr_addr    = 12'h7C0;
        csr_read_en = 1'b1;
        #1;
        expect_true("read of 0x7C0 -> csr_illegal", csr_illegal === 1'b1);
        idle_inst;
        @(posedge clk); #1;

        // ====================================================================
        // Category 4: Set/clear ops on mscratch
        // ====================================================================
        $display("\n--- Category 4: CSRRS / CSRRC on mscratch ---");

        do_write(CSR_MSCRATCH, 32'h0000_F00F);
        do_set  (CSR_MSCRATCH, 32'h0F00_0000);
        do_read (CSR_MSCRATCH, tmp32);
        expect_eq32("mscratch after set 0x0F000000", tmp32, 32'h0F00_F00F);

        do_clear(CSR_MSCRATCH, 32'h0000_F000);
        do_read (CSR_MSCRATCH, tmp32);
        expect_eq32("mscratch after clear 0x0000F000", tmp32, 32'h0F00_000F);

        // CSRRS with mask=0 must leave the value untouched (canonical "read"
        // form for CSRRS x0 idiom).
        do_set  (CSR_MSCRATCH, 32'h0000_0000);
        do_read (CSR_MSCRATCH, tmp32);
        expect_eq32("mscratch CSRRS x0 leaves value alone", tmp32, 32'h0F00_000F);

        // CSRRC with mask=0 likewise.
        do_clear(CSR_MSCRATCH, 32'h0000_0000);
        do_read (CSR_MSCRATCH, tmp32);
        expect_eq32("mscratch CSRRC x0 leaves value alone", tmp32, 32'h0F00_000F);

        // ====================================================================
        // Category 5: Counter behavior
        //   * mcycle free-runs every clock
        //   * minstret only increments on instret_tick
        //   * write to either half replaces it and skips that cycle's increment
        // ====================================================================
        $display("\n--- Category 5: Counter behavior ---");

        // 5a. mcycle free-runs: write 100, wait 5 cycles, read back 105.
        do_write(CSR_MCYCLE, 32'd100);
        repeat (5) @(posedge clk); #1;
        do_read(CSR_MCYCLE, tmp32);
        expect_eq32("mcycle = 105 after 5 ticks past write of 100", tmp32, 32'd105);

        // 5b. cycle (user RO alias) reads same value as mcycle.
        do_read(CSR_CYCLE, tmp32);
        // 1 more posedge has elapsed inside do_read? No — do_read uses #1 only.
        // mcycle is still incremented by the previous read's idle, which costs 0
        // posedges. So cycle should read mcycle's current value.
        expect_true("cycle RO alias matches mcycle (within 2)",
                    (tmp32 >= 32'd105) && (tmp32 <= 32'd107));

        // 5c. mcycleh: write a sentinel, read back. (Counter's low half keeps
        // ticking but the high half should hold the written sentinel.)
        do_write(CSR_MCYCLEH, 32'hAABB_CCDD);
        do_read(CSR_MCYCLEH, tmp32);
        expect_eq32("mcycleh readback after write", tmp32, 32'hAABB_CCDD);

        // 5d. minstret holds when instret_tick=0.
        do_write(CSR_MINSTRET, 32'd0);
        instret_tick = 1'b0;
        repeat (5) @(posedge clk); #1;
        do_read(CSR_MINSTRET, tmp32);
        expect_eq32("minstret holds at 0 with no tick", tmp32, 32'd0);

        // 5e. minstret increments on tick (5 ticks → +5).
        instret_tick = 1'b1;
        repeat (5) @(posedge clk); #1;
        instret_tick = 1'b0;
        do_read(CSR_MINSTRET, tmp32);
        expect_eq32("minstret = 5 after 5 ticks", tmp32, 32'd5);

        // 5f. instret (user RO alias) matches minstret.
        do_read(CSR_INSTRET, tmp32);
        expect_eq32("instret RO alias matches minstret", tmp32, 32'd5);

        // 5g. minstreth holds + writeable.
        do_write(CSR_MINSTRETH, 32'h1122_3344);
        do_read(CSR_MINSTRETH, tmp32);
        expect_eq32("minstreth readback", tmp32, 32'h1122_3344);

        // 5h. minstret write/tick race: write 200 with tick=1 — write wins,
        // increment skipped that cycle. Then 5 more ticks → 205.
        instret_tick   = 1'b1;
        csr_addr       = CSR_MINSTRET;
        csr_read_en    = 1'b0;
        csr_write_op   = OP_WRITE;
        csr_write_data = 32'd200;
        @(posedge clk); #1;        // write+tick edge: write wins
        idle_inst;
        // 5 more pure-tick edges
        repeat (5) @(posedge clk); #1;
        instret_tick = 1'b0;
        do_read(CSR_MINSTRET, tmp32);
        expect_eq32("minstret race: write=200, +5 ticks = 205", tmp32, 32'd205);

        // 5i. mcycle low/high independence: write low to a known value, then
        // high to a sentinel, low keeps ticking.
        do_write(CSR_MCYCLE, 32'd0);
        do_write(CSR_MCYCLEH, 32'd0);
        // Each do_write costs one posedge; mcycle low has incremented once
        // between the two (from 0 to 1 on the second write's edge — but that
        // edge is a write to mcycleh, so low half should preserve, not bump).
        // Verify low half now reads 0.
        do_read(CSR_MCYCLE, tmp32);
        expect_eq32("mcycle low preserved by mcycleh write", tmp32, 32'd0);

        // 5j. Read mcycleh just-written value.
        do_read(CSR_MCYCLEH, tmp32);
        expect_eq32("mcycleh = 0 after write", tmp32, 32'd0);

        // ====================================================================
        // Category 6: Trap-entry side effects
        //   trap_enter for one cycle:
        //     mepc  <- {trap_pc[31:2], 2'b00}
        //     mcause <- trap_cause
        //     mtval  <- trap_tval
        //     mstatus.MPIE <- mstatus.MIE
        //     mstatus.MIE  <- 0
        // ====================================================================
        $display("\n--- Category 6: Trap entry ---");

        // Pre-state: MIE=1, MPIE=0. Set up by writing mstatus = 0x0000_0008.
        do_write(CSR_MSTATUS, 32'h0000_0008);
        do_read (CSR_MSTATUS, tmp32);
        expect_eq32("mstatus pre-trap (MIE=1, MPIE=0)", tmp32, 32'h0000_1808);

        // Drive trap_enter for one cycle.
        trap_pc    = 32'h0000_8007;   // low 2 bits get masked off → 0x0000_8004
        trap_cause = 32'h8000_000B;   // M-mode external interrupt
        trap_tval  = 32'h0000_0000;
        trap_enter = 1'b1;
        @(posedge clk); #1;
        trap_enter = 1'b0;
        trap_pc    = 32'b0;
        trap_cause = 32'b0;
        trap_tval  = 32'b0;

        do_read(CSR_MEPC,   tmp32); expect_eq32("trap mepc captured", tmp32, 32'h0000_8004);
        do_read(CSR_MCAUSE, tmp32); expect_eq32("trap mcause captured", tmp32, 32'h8000_000B);
        do_read(CSR_MTVAL,  tmp32); expect_eq32("trap mtval captured (=0)", tmp32, 32'h0000_0000);
        do_read(CSR_MSTATUS, tmp32);
        expect_eq32("trap mstatus: MIE->0, MPIE<-old MIE(1)", tmp32, 32'h0000_1880);
        expect_true("trap mstatus_mie_o cleared", mstatus_mie_o === 1'b0);

        // Trap with non-zero mtval (e.g., mis-aligned load address)
        trap_pc    = 32'h0000_2000;
        trap_cause = 32'h0000_0004;   // Load address misaligned
        trap_tval  = 32'hDEAD_BEE2;
        trap_enter = 1'b1;
        @(posedge clk); #1;
        trap_enter = 1'b0;
        trap_pc = 32'b0; trap_cause = 32'b0; trap_tval = 32'b0;
        do_read(CSR_MTVAL, tmp32);
        expect_eq32("trap mtval captured (non-zero)", tmp32, 32'hDEAD_BEE2);

        // ====================================================================
        // Category 7: Trap return (MRET)
        //   trap_return for one cycle:
        //     mstatus.MIE  <- mstatus.MPIE
        //     mstatus.MPIE <- 1
        // Set pre-state explicitly via a write so this category is isolated
        // from the trap-entry sequence above (which left MIE=MPIE=0).
        // ====================================================================
        $display("\n--- Category 7: Trap return (MRET) ---");

        // Set MIE=0, MPIE=1 so MRET should restore MIE to 1.
        do_write(CSR_MSTATUS, 32'h0000_0080);
        do_read (CSR_MSTATUS, tmp32);
        expect_eq32("pre-MRET mstatus (MIE=0, MPIE=1)", tmp32, 32'h0000_1880);

        trap_return = 1'b1;
        @(posedge clk); #1;
        trap_return = 1'b0;

        do_read(CSR_MSTATUS, tmp32);
        // After MRET: MIE <- old MPIE(1), MPIE <- 1 → both bits 3 and 7 set.
        expect_eq32("post-MRET mstatus: MIE<-MPIE, MPIE<-1", tmp32, 32'h0000_1888);
        expect_true("post-MRET mstatus_mie_o set", mstatus_mie_o === 1'b1);

        // Second MRET from MIE=1, MPIE=1 should be a no-op shape: MIE stays 1,
        // MPIE stays 1.
        trap_return = 1'b1;
        @(posedge clk); #1;
        trap_return = 1'b0;
        do_read(CSR_MSTATUS, tmp32);
        expect_eq32("MRET from (1,1) keeps both set", tmp32, 32'h0000_1888);

        // ====================================================================
        // Category 8: Priority — trap_enter beats csr_write_op on mepc
        //   In the same cycle: software CSRRW to mepc with 0xAAAA_AAAC, AND
        //   trap_enter with trap_pc=0x0000_5004. mepc must end up at the
        //   masked trap_pc, not the software value.
        // ====================================================================
        $display("\n--- Category 8: Priority trap_enter > csr_write_op ---");

        // First, give mepc a sentinel so a missed update is obvious.
        do_write(CSR_MEPC, 32'h0000_1000);
        do_read (CSR_MEPC, tmp32);
        expect_eq32("mepc sentinel before priority test", tmp32, 32'h0000_1000);

        // Drive both writers in the same cycle.
        csr_addr       = CSR_MEPC;
        csr_read_en    = 1'b0;
        csr_write_op   = OP_WRITE;
        csr_write_data = 32'hAAAA_AAAC;
        trap_pc        = 32'h0000_5007;   // → masked to 0x0000_5004
        trap_cause     = 32'h0000_0002;
        trap_tval      = 32'h0000_0000;
        trap_enter     = 1'b1;
        @(posedge clk); #1;
        trap_enter     = 1'b0;
        trap_pc = 32'b0; trap_cause = 32'b0; trap_tval = 32'b0;
        idle_inst;

        do_read(CSR_MEPC, tmp32);
        expect_eq32("mepc priority: trap_pc wins (masked)", tmp32, 32'h0000_5004);

        // Mirror priority for mcause: in same cycle write mcause + trap_enter
        // with cause=0x0000_0007. Reload sentinel first.
        do_write(CSR_MCAUSE, 32'h1111_1111);
        do_read (CSR_MCAUSE, tmp32);
        expect_eq32("mcause sentinel before priority test", tmp32, 32'h1111_1111);

        csr_addr       = CSR_MCAUSE;
        csr_read_en    = 1'b0;
        csr_write_op   = OP_WRITE;
        csr_write_data = 32'h2222_2222;
        trap_cause     = 32'h0000_0007;
        trap_pc        = 32'b0;
        trap_tval      = 32'b0;
        trap_enter     = 1'b1;
        @(posedge clk); #1;
        trap_enter     = 1'b0;
        trap_cause     = 32'b0;
        idle_inst;

        do_read(CSR_MCAUSE, tmp32);
        expect_eq32("mcause priority: trap_cause wins", tmp32, 32'h0000_0007);

        // ====================================================================
        // Summary
        // ====================================================================
        #20;
        $display("\n=== csr_file: %0d passed, %0d failed ===", pass, fail);
        if (fail > 0) $display("SOME TESTS FAILED");
        else          $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
