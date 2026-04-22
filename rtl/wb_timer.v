// Wishbone B4 Slave — CLINT-style Timer
// 64-bit free-running counter (mtime) at core clock rate.
// 64-bit comparator (mtimecmp) — timer_irq asserts when mtime >= mtimecmp.
//
// Register Map:
//   +0x0: mtime_lo    (R/W)
//   +0x4: mtime_hi    (R/W)
//   +0x8: mtimecmp_lo (R/W)
//   +0xC: mtimecmp_hi (R/W)
//
// Immediate combinational ack.
//
// Phase 0.1 hardened (2026-04-21):
//   * Write/increment semantics: a write to mtime_lo or mtime_hi replaces
//     that half and skips the increment for that cycle. The unwritten half
//     is preserved as-is (no carry injected). Simultaneous writes to both
//     halves are not supported by the bus (one 32-bit transaction per
//     cycle), so no carry ambiguity arises. Writes to mtimecmp_lo/hi never
//     affect the mtime increment path.
//   * Reset values: both mtime and mtimecmp reset to 64'hFFFFFFFF_FFFFFFFF.
//     Rationale: the comparator timer_irq = (mtime >= mtimecmp) must be
//     well-defined at reset without relying on the mtimecmp default being
//     larger than mtime. With both at all-1s, the comparator is true for
//     exactly one cycle before the first increment wraps mtime to 0; real
//     software writes mtimecmp before enabling mstatus.MIE, so this is
//     benign. The previous scheme (mtime=0, mtimecmp=all-1s) was fragile
//     — any future change to mtimecmp's default would have spuriously
//     asserted timer_irq at startup.
//   * Reset style: synchronous active-high reset, matching `pc.v`,
//     `wb_dmem.v`, and the 2-FF reset synchronizer in `fpga_top.v`.

module wb_timer (
    input  wire        clk,
    input  wire        rst,

    // Wishbone slave interface
    input  wire        wb_cyc_i,
    input  wire        wb_stb_i,
    input  wire        wb_we_i,
    // Standard WB slave pattern: address fully decoded by wb_interconnect;
    // slave only uses the register-offset bits (adr_i[3:0]). Byte selects
    // ignored — word-only slave (mtime/mtimecmp are 32-bit halves).
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    input  wire [3:0]  wb_sel_i,
    /* verilator lint_on UNUSEDSIGNAL */
    output reg  [31:0] wb_dat_o,
    output wire        wb_ack_o,

    // IRQ output (active-high, exposed but not wired to core yet)
    output wire        timer_irq
);

    // =========================================================================
    // Wishbone handshake — combinational ack
    // =========================================================================
    wire valid = wb_cyc_i & wb_stb_i;
    assign wb_ack_o = valid;

    // =========================================================================
    // Register decode
    // =========================================================================
    wire [3:0] reg_sel = wb_adr_i[3:0];

    // =========================================================================
    // Timer registers
    // =========================================================================
    reg [63:0] mtime;
    reg [63:0] mtimecmp;

    // =========================================================================
    // Next-state logic for mtime
    //   - Write to mtime_lo: replace low half, preserve high, skip tick
    //   - Write to mtime_hi: replace high half, preserve low, skip tick
    //   - Otherwise:         free-running increment
    // =========================================================================
    wire write_mtime_lo = valid && wb_we_i && (reg_sel == 4'h0);
    wire write_mtime_hi = valid && wb_we_i && (reg_sel == 4'h4);

    reg [63:0] mtime_next;
    always @(*) begin
        if (write_mtime_lo)
            mtime_next = {mtime[63:32], wb_dat_i};
        else if (write_mtime_hi)
            mtime_next = {wb_dat_i, mtime[31:0]};
        else
            mtime_next = mtime + 64'd1;
    end

    // =========================================================================
    // Register update — synchronous active-high reset
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            mtime    <= 64'hFFFFFFFF_FFFFFFFF;
            mtimecmp <= 64'hFFFFFFFF_FFFFFFFF;
        end else begin
            mtime <= mtime_next;

            if (valid && wb_we_i) begin
                case (reg_sel)
                    4'h8: mtimecmp[31:0]  <= wb_dat_i;
                    4'hC: mtimecmp[63:32] <= wb_dat_i;
                    default: ;
                endcase
            end
        end
    end

    // =========================================================================
    // Comparator — IRQ when mtime >= mtimecmp
    // =========================================================================
    assign timer_irq = (mtime >= mtimecmp);

    // =========================================================================
    // Read mux — combinational
    // =========================================================================
    always @(*) begin
        wb_dat_o = 32'd0;
        if (valid && ~wb_we_i) begin
            case (reg_sel)
                4'h0: wb_dat_o = mtime[31:0];
                4'h4: wb_dat_o = mtime[63:32];
                4'h8: wb_dat_o = mtimecmp[31:0];
                4'hC: wb_dat_o = mtimecmp[63:32];
                default: wb_dat_o = 32'd0;
            endcase
        end
    end

endmodule
