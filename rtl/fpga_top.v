// FPGA Top-Level Wrapper for Nexys4 DDR
// Instantiates: rv32i_core, imem, wb_master, wb_interconnect, wb_dmem, wb_uart, wb_gpio, wb_timer
// Target: Artix-7 XC7A100T, 100MHz, USB-UART at 115200

module fpga_top #(
    parameter IMEM_DEPTH    = 16384,        // 64KB instruction memory (16K words)
    parameter DMEM_DEPTH    = 4096,         // 4KB data memory (bytes)
    parameter IMEM_INIT     = "firmware.hex",
    parameter DMEM_INIT     = "dmem_init.hex",
    parameter CLK_FREQ      = 50_000_000,   // Core runs at 50MHz (100MHz / 2)
    parameter BAUD_RATE     = 115200
)(
    input  wire CLK100MHZ,
    input  wire CPU_RESETN,    // Active-low reset button
    input  wire UART_TXD_IN,  // FTDI TX -> FPGA RX (data into FPGA)
    output wire UART_RXD_OUT, // FPGA TX -> FTDI RX (data out of FPGA)
    output wire [15:0] LED,    // GPIO output → LEDs
    input  wire [15:0] SW      // GPIO input  ← Slide switches
);

    // Clock divider: 100MHz -> 50MHz
    reg clk_div = 0;
    always @(posedge CLK100MHZ)
        clk_div <= ~clk_div;

    wire clk = clk_div;

    // Reset synchronizer — 2-FF to avoid metastability
    reg rst_sync1 = 1, rst_sync2 = 1;
    always @(posedge clk) begin
        rst_sync1 <= ~CPU_RESETN;
        rst_sync2 <= rst_sync1;
    end
    wire rst = rst_sync2;

    // =========================================================================
    // Core bus signals
    // =========================================================================
    // DEFERRED: `imem_addr` (the current-PC flavor of the fetch address) is
    // dead at the top level — `imem_addr_next` drives the BRAM for the
    // SYNC_READ=1 path. Keeping the port for now; the core's external
    // interface is revisited in Phase 4 (pipeline refactor), which is where
    // the port list trims happen.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] imem_addr, imem_addr_next, imem_data;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire        dmem_we, dmem_re;
    wire [2:0]  dmem_funct3;
    // debug_pc / debug_instr are the retirement-trace outputs from the core;
    // consumed in Phase 3 by the RVFI formal harness. Unwired today.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] debug_pc, debug_instr;
    /* verilator lint_on UNUSEDSIGNAL */

    // =========================================================================
    // Wishbone master signals
    // =========================================================================
    wire        wb_cyc, wb_stb, wb_we;
    wire [31:0] wb_adr, wb_dat_m2s;
    wire [3:0]  wb_sel;
    wire [31:0] wb_dat_s2m;
    wire        wb_ack;
    wire [2:0]  wb_funct3;

    // =========================================================================
    // Wishbone slave signals — DMEM (slave 0)
    // =========================================================================
    wire        wbs0_cyc, wbs0_stb, wbs0_we;
    wire [31:0] wbs0_adr, wbs0_dat_m2s;
    wire [3:0]  wbs0_sel;
    wire [31:0] wbs0_dat_s2m;
    wire        wbs0_ack;
    wire [2:0]  wbs0_funct3;

    // =========================================================================
    // Wishbone slave signals — UART (slave 1)
    // =========================================================================
    wire        wbs1_cyc, wbs1_stb, wbs1_we;
    wire [31:0] wbs1_adr, wbs1_dat_m2s;
    wire [3:0]  wbs1_sel;
    wire [31:0] wbs1_dat_s2m;
    wire        wbs1_ack;

    // =========================================================================
    // Wishbone slave signals — GPIO (slave 2)
    // =========================================================================
    wire        wbs2_cyc, wbs2_stb, wbs2_we;
    wire [31:0] wbs2_adr, wbs2_dat_m2s;
    wire [3:0]  wbs2_sel;
    wire [31:0] wbs2_dat_s2m;
    wire        wbs2_ack;

    // =========================================================================
    // Wishbone slave signals — Timer (slave 3)
    // =========================================================================
    wire        wbs3_cyc, wbs3_stb, wbs3_we;
    wire [31:0] wbs3_adr, wbs3_dat_m2s;
    wire [3:0]  wbs3_sel;
    wire [31:0] wbs3_dat_s2m;
    wire        wbs3_ack;
    // timer_irq is exposed by wb_timer but dangling — Phase 2 wires it into
    // the core's `irq_timer` input once CSRs + trap logic land in Phase 1.
    /* verilator lint_off UNUSEDSIGNAL */
    wire        timer_irq;
    /* verilator lint_on UNUSEDSIGNAL */

    // =========================================================================
    // CSR File ↔ Core interface (Phase 1.1)
    // =========================================================================
    // Decoder side (core → csr_file):
    wire [11:0] core_csr_addr;
    wire        core_csr_read_en;
    wire [2:0]  core_csr_write_op;
    wire [31:0] core_csr_write_data;
    // Read-back + illegal (csr_file → core):
    wire [31:0] csr_read_data;
    wire        csr_illegal;
    // Retirement (core → csr_file):
    wire        core_instret_tick;
    // Trap-related outputs (csr_file → core), routed through the core's port
    // list per Decision D1. Phase 1.1 doesn't consume them; Phase 1.2's trap
    // FSM (PC-redirect mux) does.
    wire [31:0] csr_mtvec;
    wire [31:0] csr_mepc;
    wire        csr_mstatus_mie;
    // illegal_inst_o from core: consumed inside the core itself in 1.2.1 as
    // the encoder's `illegal_inst` cause source. No fpga_top-level consumer
    // — the port is left empty on the core instance below (under the
    // PINCONNECTEMPTY scope around u_core).
    // mstatus_o from csr_file is debug visibility only — leave unconnected.

    // Phase 1.2.0: trap-entry signals from core to csr_file. Step 2 lights
    // these up; trap_return stays tied 1'b0 at u_csr_file until 1.2.2's
    // MRET decode lands. csr_file already enforces the
    // trap_enter > trap_return > csr_write_op priority internally.
    wire        core_trap_enter;
    wire [31:0] core_trap_pc;
    wire [31:0] core_trap_cause;
    wire [31:0] core_trap_tval;

    // =========================================================================
    // CPU Core
    // =========================================================================
    /* verilator lint_off PINCONNECTEMPTY */
    rv32i_core u_core (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_data(imem_data),
        .imem_addr_next(imem_addr_next),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_rdata(dmem_rdata), .dmem_we(dmem_we),
        .dmem_re(dmem_re), .dmem_funct3(dmem_funct3),
        // CSR interface
        .csr_addr_o(core_csr_addr),
        .csr_read_en_o(core_csr_read_en),
        .csr_write_op_o(core_csr_write_op),
        .csr_write_data_o(core_csr_write_data),
        .csr_read_data_i(csr_read_data),
        .csr_illegal_i(csr_illegal),
        .instret_tick_o(core_instret_tick),
        // illegal_inst_o consumed internally by the trap encoder; no
        // top-level consumer (the trap_enter / trap_cause outputs already
        // expose the resulting trap state).
        .illegal_inst_o(/* unconnected */),
        // Phase 1.2.0 trap-entry outputs to csr_file
        .trap_enter_o(core_trap_enter),
        .trap_pc_o(core_trap_pc),
        .trap_cause_o(core_trap_cause),
        .trap_tval_o(core_trap_tval),
        .mtvec_i(csr_mtvec),
        .mepc_i(csr_mepc),
        .mstatus_mie_i(csr_mstatus_mie),
        .debug_pc(debug_pc), .debug_instr(debug_instr)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // =========================================================================
    // CSR File (Phase 1.1 + 1.2.0)
    // =========================================================================
    // Phase 1.2.0 Step 2: trap-entry inputs are now driven by the core's
    // trap encoder. trap_return stays tied 1'b0 — 1.2.2's MRET decode is
    // its consumer. mstatus_o is debug-only; leave unconnected.
    /* verilator lint_off PINCONNECTEMPTY */
    csr_file u_csr_file (
        .clk(clk), .rst(rst),
        // Instruction-driven access from core
        .csr_addr(core_csr_addr),
        .csr_read_en(core_csr_read_en),
        .csr_write_op(core_csr_write_op),
        .csr_write_data(core_csr_write_data),
        .csr_read_data(csr_read_data),
        .csr_illegal(csr_illegal),
        // Trap entry — Phase 1.2.0 Step 2
        .trap_enter(core_trap_enter),
        .trap_pc(core_trap_pc),
        .trap_cause(core_trap_cause),
        .trap_tval(core_trap_tval),
        // Trap return (MRET) — Phase 1.2.2
        .trap_return(1'b0),
        // Retirement tick from core (gated on !trap_enter inside the core)
        .instret_tick(core_instret_tick),
        // Outputs to core (consumed by 1.2.0's PC-redirect mux)
        .mtvec_o(csr_mtvec),
        .mepc_o(csr_mepc),
        .mstatus_mie_o(csr_mstatus_mie),
        // Debug visibility — unused at fpga_top
        .mstatus_o()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // =========================================================================
    // Instruction Memory
    // =========================================================================
    // SYNC_READ=1: BRAM mode — addr driven by imem_addr_next (= pc_next)
    // so registered output aligns with pc_current after the clock edge
    imem #(.DEPTH(IMEM_DEPTH), .INIT_FILE(IMEM_INIT), .SYNC_READ(1)) u_imem (
        .clk(clk), .addr(imem_addr_next), .instr(imem_data)
    );

    // =========================================================================
    // Wishbone Master Bridge
    // =========================================================================
    // WB_USE_STALL left at its default (0). Phase 4 flips this parameter
    // and wires stall_o into the pipelined core.
    /* verilator lint_off PINCONNECTEMPTY */
    wb_master u_wb_master (
        .clk(clk),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_we(dmem_we), .dmem_re(dmem_re),
        .dmem_funct3(dmem_funct3), .dmem_rdata(dmem_rdata),
        .wb_cyc_o(wb_cyc), .wb_stb_o(wb_stb), .wb_we_o(wb_we),
        .wb_adr_o(wb_adr), .wb_dat_o(wb_dat_m2s), .wb_sel_o(wb_sel),
        .wb_dat_i(wb_dat_s2m), .wb_ack_i(wb_ack),
        .wb_funct3_o(wb_funct3),
        .stall_o(/* unconnected — reserved for Phase 4 pipeline */)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // =========================================================================
    // Wishbone Interconnect
    // =========================================================================
    // bus_error_o deliberately unconnected here — Phase 1's load/store
    // access-fault trap is the consumer, per docs/phase0_changelog.md.
    /* verilator lint_off PINCONNECTEMPTY */
    wb_interconnect u_wb_ic (
        .wbm_cyc_i(wb_cyc), .wbm_stb_i(wb_stb), .wbm_we_i(wb_we),
        .wbm_adr_i(wb_adr), .wbm_dat_i(wb_dat_m2s), .wbm_sel_i(wb_sel),
        .wbm_dat_o(wb_dat_s2m), .wbm_ack_o(wb_ack),
        .wbm_funct3_i(wb_funct3),
        // Slave 0: DMEM
        .wbs0_cyc_o(wbs0_cyc), .wbs0_stb_o(wbs0_stb), .wbs0_we_o(wbs0_we),
        .wbs0_adr_o(wbs0_adr), .wbs0_dat_o(wbs0_dat_m2s), .wbs0_sel_o(wbs0_sel),
        .wbs0_dat_i(wbs0_dat_s2m), .wbs0_ack_i(wbs0_ack),
        .wbs0_funct3_o(wbs0_funct3),
        // Slave 1: UART
        .wbs1_cyc_o(wbs1_cyc), .wbs1_stb_o(wbs1_stb), .wbs1_we_o(wbs1_we),
        .wbs1_adr_o(wbs1_adr), .wbs1_dat_o(wbs1_dat_m2s), .wbs1_sel_o(wbs1_sel),
        .wbs1_dat_i(wbs1_dat_s2m), .wbs1_ack_i(wbs1_ack),
        // Slave 2: GPIO
        .wbs2_cyc_o(wbs2_cyc), .wbs2_stb_o(wbs2_stb), .wbs2_we_o(wbs2_we),
        .wbs2_adr_o(wbs2_adr), .wbs2_dat_o(wbs2_dat_m2s), .wbs2_sel_o(wbs2_sel),
        .wbs2_dat_i(wbs2_dat_s2m), .wbs2_ack_i(wbs2_ack),
        // Slave 3: Timer
        .wbs3_cyc_o(wbs3_cyc), .wbs3_stb_o(wbs3_stb), .wbs3_we_o(wbs3_we),
        .wbs3_adr_o(wbs3_adr), .wbs3_dat_o(wbs3_dat_m2s), .wbs3_sel_o(wbs3_sel),
        .wbs3_dat_i(wbs3_dat_s2m), .wbs3_ack_i(wbs3_ack),
        // bus_error_o unconnected — consumed by access-fault trap in Phase 1
        .bus_error_o(/* unconnected */)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // =========================================================================
    // Data Memory (Wishbone Slave 0)
    // =========================================================================
    wb_dmem #(.DEPTH(DMEM_DEPTH), .INIT_FILE(DMEM_INIT)) u_wb_dmem (
        .clk(clk), .rst(rst),
        .wb_cyc_i(wbs0_cyc), .wb_stb_i(wbs0_stb), .wb_we_i(wbs0_we),
        .wb_adr_i(wbs0_adr), .wb_dat_i(wbs0_dat_m2s), .wb_sel_i(wbs0_sel),
        .wb_dat_o(wbs0_dat_s2m), .wb_ack_o(wbs0_ack),
        .wb_funct3_i(wbs0_funct3)
    );

    // =========================================================================
    // UART (Wishbone Slave 1)
    // =========================================================================
    wb_uart #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_wb_uart (
        .clk(clk), .rst(rst),
        .wb_cyc_i(wbs1_cyc), .wb_stb_i(wbs1_stb), .wb_we_i(wbs1_we),
        .wb_adr_i(wbs1_adr), .wb_dat_i(wbs1_dat_m2s), .wb_sel_i(wbs1_sel),
        .wb_dat_o(wbs1_dat_s2m), .wb_ack_o(wbs1_ack),
        .uart_tx(UART_RXD_OUT),
        .uart_rx(UART_TXD_IN)
    );

    // =========================================================================
    // GPIO (Wishbone Slave 2)
    // =========================================================================
    wb_gpio u_wb_gpio (
        .clk(clk), .rst(rst),
        .wb_cyc_i(wbs2_cyc), .wb_stb_i(wbs2_stb), .wb_we_i(wbs2_we),
        .wb_adr_i(wbs2_adr), .wb_dat_i(wbs2_dat_m2s), .wb_sel_i(wbs2_sel),
        .wb_dat_o(wbs2_dat_s2m), .wb_ack_o(wbs2_ack),
        .gpio_out(LED),
        .gpio_in(SW)
    );

    // =========================================================================
    // Timer (Wishbone Slave 3)
    // =========================================================================
    wb_timer u_wb_timer (
        .clk(clk), .rst(rst),
        .wb_cyc_i(wbs3_cyc), .wb_stb_i(wbs3_stb), .wb_we_i(wbs3_we),
        .wb_adr_i(wbs3_adr), .wb_dat_i(wbs3_dat_m2s), .wb_sel_i(wbs3_sel),
        .wb_dat_o(wbs3_dat_s2m), .wb_ack_o(wbs3_ack),
        .timer_irq(timer_irq)
    );

endmodule
