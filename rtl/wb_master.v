// Wishbone B4 Master Bridge
// Translates rv32i_core dmem bus signals to Wishbone B4 classic interface.
// Generates wb_sel from funct3 + addr[1:0] per RISC-V load/store encoding.
`include "defines.v"

module wb_master (
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
    output wire [2:0]  wb_funct3_o
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

endmodule
