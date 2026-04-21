// Wishbone B4 Master Bridge — Zero-Wait-State (Phase 0.1 hardened)
// Translates rv32i_core dmem bus signals to Wishbone B4 classic interface.
// Generates wb_sel from funct3 + addr[1:0] per RISC-V load/store encoding.
//
// LIMITATION (unchanged): This bridge assumes all slaves return ack and read
// data combinationally in the same cycle (zero wait states). wb_ack_i is
// accepted as a port for Wishbone compliance but is not yet propagated as a
// stall/ready into rv32i_core. Any future slave with non-zero latency will
// silently corrupt reads unless the pipeline consumes a stall.
//
// Phase 0.1 partial mitigation:
//   - Simulation-only assertion on every negedge clk fires if (cyc & stb &
//     !ack) is sampled while WB_USE_STALL == 0. This catches the class of
//     bug — a slave that fails to ack combinationally — before silicon.
//   - Optional stall_o output: when WB_USE_STALL is set to 1 at elaboration,
//     stall_o = (cyc & stb & !ack) so a future core can stall on it. Default
//     (WB_USE_STALL = 0) ties stall_o to 0 and preserves original behavior.
//     Nothing currently consumes this wire; it exists so Phase 4's pipeline
//     refactor can flip the parameter and wire stall_o into the core without
//     a port-list change.
//
// The full fix (true wait-state support end-to-end through rv32i_core) is
// deferred to Phase 4 of the Tier 1 roadmap.
`include "defines.v"

module wb_master #(
    // When 1, stall_o = cyc & stb & !ack (intended for pipelined cores).
    // When 0, stall_o is tied to 0 and a simulation assertion fires if the
    // master ever sees cyc & stb & !ack — the bug this parameter guards.
    parameter WB_USE_STALL = 0
) (
    // Clock — used only for the simulation-only assertion below. Synthesis
    // tools drop the always @(negedge clk) block inside the `ifndef SYNTHESIS
    // guard, so no real register is inferred.
    input  wire        clk,

    // Core data memory bus (from rv32i_core)
    input  wire [31:0] dmem_addr,
    input  wire [31:0] dmem_wdata,
    input  wire        dmem_we,
    input  wire        dmem_re,
    input  wire [2:0]  dmem_funct3,
    output wire [31:0] dmem_rdata,

    // Wishbone master interface
    output wire        wb_cyc_o,
    output wire        wb_stb_o,
    output wire        wb_we_o,
    output wire [31:0] wb_adr_o,
    output wire [31:0] wb_dat_o,
    output wire [3:0]  wb_sel_o,
    input  wire [31:0] wb_dat_i,
    input  wire        wb_ack_i,

    // Sideband — pass funct3 through for slaves that need sign-extension info
    output wire [2:0]  wb_funct3_o,

    // Optional stall output — Phase 4 hook. Tied 0 when WB_USE_STALL == 0.
    output wire        stall_o
);

    // =========================================================================
    // Bus cycle — active on any load or store
    // =========================================================================
    assign wb_cyc_o = dmem_we | dmem_re;
    assign wb_stb_o = dmem_we | dmem_re;
    assign wb_we_o  = dmem_we;
    assign wb_adr_o = dmem_addr;
    assign wb_dat_o = dmem_wdata;

    // =========================================================================
    // Read data passthrough
    // =========================================================================
    assign dmem_rdata = wb_dat_i;

    // =========================================================================
    // Sideband — funct3 passthrough
    // =========================================================================
    assign wb_funct3_o = dmem_funct3;

    // =========================================================================
    // Byte lane select — derived from funct3 and addr[1:0]
    // =========================================================================
    reg [3:0] sel;
    always @(*) begin
        case (dmem_funct3[1:0])  // Lower 2 bits encode width (bit 2 is sign)
            2'b00: begin  // Byte (LB/LBU/SB)
                case (dmem_addr[1:0])
                    2'd0: sel = 4'b0001;
                    2'd1: sel = 4'b0010;
                    2'd2: sel = 4'b0100;
                    2'd3: sel = 4'b1000;
                endcase
            end
            2'b01: begin  // Halfword (LH/LHU/SH)
                case (dmem_addr[1])
                    1'b0: sel = 4'b0011;
                    1'b1: sel = 4'b1100;
                endcase
            end
            2'b10:    // Word (LW/SW)
                sel = 4'b1111;
            default:
                sel = 4'b1111;
        endcase
    end

    assign wb_sel_o = sel;

    // =========================================================================
    // Optional stall output (Phase 4 hook)
    // =========================================================================
    generate
        if (WB_USE_STALL) begin : g_stall_live
            assign stall_o = wb_cyc_o & wb_stb_o & ~wb_ack_i;
        end else begin : g_stall_tied
            assign stall_o = 1'b0;
        end
    endgenerate

    // =========================================================================
    // Simulation-only assertion: catches the "silently ignored wb_ack_i" bug.
    // Synthesis tools dropping this block leave behavior unchanged in silicon.
    // =========================================================================
`ifndef SYNTHESIS
    always @(negedge clk) begin
        if (WB_USE_STALL == 0 && wb_cyc_o === 1'b1
                               && wb_stb_o === 1'b1
                               && wb_ack_i !== 1'b1) begin
            $display("[%0t] wb_master ASSERT: cyc&stb asserted with wb_ack_i=%b (addr=0x%08h we=%b). A slave failed to ack combinationally; this would corrupt reads in silicon. Set WB_USE_STALL=1 and consume stall_o, or fix the slave.",
                     $time, wb_ack_i, wb_adr_o, wb_we_o);
            // $error prints "ERROR" to the transcript but does not halt
            // iverilog simulation — matches the "log, don't halt" intent.
            $error("wb_master: missing wb_ack_i while cyc&stb asserted (WB_USE_STALL=0)");
        end
    end
`endif

endmodule
