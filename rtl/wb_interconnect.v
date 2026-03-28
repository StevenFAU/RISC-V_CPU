// Wishbone B4 Interconnect — Single-master, multi-slave address decoder + mux
// Phase 1: DMEM only. UART/GPIO/Timer added in later phases.
//
// Address Map:
//   0x00010000 - 0x0001FFFF : DMEM (RAM)
//   0x80000000 - 0x8000000F : UART  (Phase 2)
//   0x80001000 - 0x80001007 : GPIO  (Phase 3)
//   0x80002000 - 0x8000200F : Timer (Phase 4)

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
    output wire [2:0]  wbs0_funct3_o
);

    // =========================================================================
    // Address decode
    // =========================================================================
    wire sel_dmem = (wbm_adr_i[31:16] == 16'h0001);

    // =========================================================================
    // Slave steering — active slave gets cyc/stb, others see 0
    // =========================================================================
    assign wbs0_cyc_o    = wbm_cyc_i & sel_dmem;
    assign wbs0_stb_o    = wbm_stb_i & sel_dmem;
    assign wbs0_we_o     = wbm_we_i;
    assign wbs0_adr_o    = wbm_adr_i;
    assign wbs0_dat_o    = wbm_dat_i;
    assign wbs0_sel_o    = wbm_sel_i;
    assign wbs0_funct3_o = wbm_funct3_i;

    // =========================================================================
    // Return mux — route selected slave's dat/ack back to master
    // =========================================================================
    always @(*) begin
        if (sel_dmem) begin
            wbm_dat_o = wbs0_dat_i;
            wbm_ack_o = wbs0_ack_i;
        end else begin
            wbm_dat_o = 32'd0;
            wbm_ack_o = 1'b0;
        end
    end

endmodule
