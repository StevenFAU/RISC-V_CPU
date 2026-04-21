// Wishbone B4 Interconnect — Single-master, multi-slave address decoder + mux
//
// Address Map:
//   0x00010000 - 0x0001FFFF : DMEM (RAM)   — Slave 0
//   0x80000000 - 0x8000000F : UART         — Slave 1
//   0x80001000 - 0x80001007 : GPIO         — Slave 2 (Phase 3)
//   0x80002000 - 0x8000200F : Timer        — Slave 3 (Phase 4)
//
// Phase 0.1 (2026-04-21): Unmapped-access policy
//
// An active bus cycle (cyc & stb) to an address that decodes to no slave
// is handled as a "bus error":
//   * wbm_ack_o asserts in the same cycle (auto-ack) — prevents the master
//     from hanging while waiting for an ack that no slave will produce.
//     Without this, once Phase 4 wires wb_master's stall_o into the
//     pipeline, any stray load/store would deadlock the core.
//   * wbm_dat_o returns 32'd0 — deterministic, so trace diffs show exactly
//     what the core saw on the bad load.
//   * bus_error_o asserts combinationally, same cycle as the bad access.
//     It is unconnected in Phase 0 (the wire exists at fpga_top for later
//     consumption) and becomes the source signal for the load/store
//     access-fault trap added in Phase 1. Must stay combinational so the
//     trap can fire in the same cycle the core sees the bogus rdata.
// Idle cycles (cyc=0 or stb=0) are treated as idle: no ack, no bus_error,
// zero rdata — the bus is quiet.
//
// Writes to unmapped addresses are discarded on the floor: no slave sees
// wbs*_cyc asserted, so the write never reaches a register. The master
// still sees an ack and can retire the store.

module wb_interconnect (
    // Wishbone master port (from wb_master)
    input  wire        wbm_cyc_i,
    input  wire        wbm_stb_i,
    input  wire        wbm_we_i,
    input  wire [31:0] wbm_adr_i,
    input  wire [31:0] wbm_dat_i,
    input  wire [3:0]  wbm_sel_i,
    output reg  [31:0] wbm_dat_o,
    output reg         wbm_ack_o,

    // Sideband from master
    input  wire [2:0]  wbm_funct3_i,

    // Slave 0: DMEM
    output wire        wbs0_cyc_o,
    output wire        wbs0_stb_o,
    output wire        wbs0_we_o,
    output wire [31:0] wbs0_adr_o,
    output wire [31:0] wbs0_dat_o,
    output wire [3:0]  wbs0_sel_o,
    input  wire [31:0] wbs0_dat_i,
    input  wire        wbs0_ack_i,
    output wire [2:0]  wbs0_funct3_o,

    // Slave 1: UART
    output wire        wbs1_cyc_o,
    output wire        wbs1_stb_o,
    output wire        wbs1_we_o,
    output wire [31:0] wbs1_adr_o,
    output wire [31:0] wbs1_dat_o,
    output wire [3:0]  wbs1_sel_o,
    input  wire [31:0] wbs1_dat_i,
    input  wire        wbs1_ack_i,

    // Slave 2: GPIO
    output wire        wbs2_cyc_o,
    output wire        wbs2_stb_o,
    output wire        wbs2_we_o,
    output wire [31:0] wbs2_adr_o,
    output wire [31:0] wbs2_dat_o,
    output wire [3:0]  wbs2_sel_o,
    input  wire [31:0] wbs2_dat_i,
    input  wire        wbs2_ack_i,

    // Slave 3: Timer
    output wire        wbs3_cyc_o,
    output wire        wbs3_stb_o,
    output wire        wbs3_we_o,
    output wire [31:0] wbs3_adr_o,
    output wire [31:0] wbs3_dat_o,
    output wire [3:0]  wbs3_sel_o,
    input  wire [31:0] wbs3_dat_i,
    input  wire        wbs3_ack_i,

    // Bus error — asserts combinationally when an active cycle hits an
    // unmapped address. Unconnected in Phase 0; consumed by the Phase 1
    // load/store access-fault trap. Must remain combinational.
    output wire        bus_error_o
);

    // =========================================================================
    // Address decode
    //
    // Phase 0.1 (2026-04-21): UART/GPIO/TIMER tightened to exactly match the
    // documented register windows. Previously these were all decoded as 4 KB
    // regions (addr[31:12] == page), which silently aliased every mismatched
    // address inside the page back onto the real registers. Out-of-range
    // accesses now fall through to the unmapped path (return 0, no ack).
    //
    // DMEM stays broad (16-bit match on addr[31:16] covers 64 KB) on purpose
    // — it's a memory region, not a register block, and future sizing changes
    // (8 KB, 16 KB, etc.) should live inside this window without touching the
    // interconnect.
    // =========================================================================
    wire sel_dmem  = (wbm_adr_i[31:16] == 16'h0001);
    wire sel_uart  = (wbm_adr_i >= 32'h8000_0000) && (wbm_adr_i <= 32'h8000_000F);
    wire sel_gpio  = (wbm_adr_i >= 32'h8000_1000) && (wbm_adr_i <= 32'h8000_1007);
    wire sel_timer = (wbm_adr_i >= 32'h8000_2000) && (wbm_adr_i <= 32'h8000_200F);

    // =========================================================================
    // Unmapped-active detection (Phase 0.1)
    //
    // An active cycle with no matching slave decode. Drives bus_error_o and
    // enables the auto-ack path in the return mux below. Idle cycles
    // (cyc=0 or stb=0) do NOT count as unmapped — the bus is just quiet.
    // =========================================================================
    wire wbm_active = wbm_cyc_i & wbm_stb_i;
    wire unmapped   = wbm_active & ~(sel_dmem | sel_uart | sel_gpio | sel_timer);

    assign bus_error_o = unmapped;

    // =========================================================================
    // Slave 0: DMEM — steering
    // =========================================================================
    assign wbs0_cyc_o    = wbm_cyc_i & sel_dmem;
    assign wbs0_stb_o    = wbm_stb_i & sel_dmem;
    assign wbs0_we_o     = wbm_we_i;
    assign wbs0_adr_o    = wbm_adr_i;
    assign wbs0_dat_o    = wbm_dat_i;
    assign wbs0_sel_o    = wbm_sel_i;
    assign wbs0_funct3_o = wbm_funct3_i;

    // =========================================================================
    // Slave 1: UART — steering
    // =========================================================================
    assign wbs1_cyc_o = wbm_cyc_i & sel_uart;
    assign wbs1_stb_o = wbm_stb_i & sel_uart;
    assign wbs1_we_o  = wbm_we_i;
    assign wbs1_adr_o = wbm_adr_i;
    assign wbs1_dat_o = wbm_dat_i;
    assign wbs1_sel_o = wbm_sel_i;

    // =========================================================================
    // Slave 2: GPIO — steering
    // =========================================================================
    assign wbs2_cyc_o = wbm_cyc_i & sel_gpio;
    assign wbs2_stb_o = wbm_stb_i & sel_gpio;
    assign wbs2_we_o  = wbm_we_i;
    assign wbs2_adr_o = wbm_adr_i;
    assign wbs2_dat_o = wbm_dat_i;
    assign wbs2_sel_o = wbm_sel_i;

    // =========================================================================
    // Slave 3: Timer — steering
    // =========================================================================
    assign wbs3_cyc_o = wbm_cyc_i & sel_timer;
    assign wbs3_stb_o = wbm_stb_i & sel_timer;
    assign wbs3_we_o  = wbm_we_i;
    assign wbs3_adr_o = wbm_adr_i;
    assign wbs3_dat_o = wbm_dat_i;
    assign wbs3_sel_o = wbm_sel_i;

    // =========================================================================
    // Return mux — route selected slave's dat/ack back to master.
    //
    // Phase 0.1: an unmapped ACTIVE cycle auto-acks with zero rdata so the
    // master can retire the transaction. An idle bus (no active cycle)
    // stays quiescent.
    // =========================================================================
    always @(*) begin
        if (sel_dmem) begin
            wbm_dat_o = wbs0_dat_i;
            wbm_ack_o = wbs0_ack_i;
        end else if (sel_uart) begin
            wbm_dat_o = wbs1_dat_i;
            wbm_ack_o = wbs1_ack_i;
        end else if (sel_gpio) begin
            wbm_dat_o = wbs2_dat_i;
            wbm_ack_o = wbs2_ack_i;
        end else if (sel_timer) begin
            wbm_dat_o = wbs3_dat_i;
            wbm_ack_o = wbs3_ack_i;
        end else if (unmapped) begin
            wbm_dat_o = 32'd0;
            wbm_ack_o = 1'b1;
        end else begin
            wbm_dat_o = 32'd0;
            wbm_ack_o = 1'b0;
        end
    end

endmodule
