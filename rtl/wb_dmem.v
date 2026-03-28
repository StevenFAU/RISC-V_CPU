// Wishbone B4 Slave — Data Memory Wrapper
// Wraps existing dmem.v with Wishbone slave interface.
// Uses funct3 sideband from master to preserve sign-extension behavior.
// Immediate combinational ack (single-cycle, no wait states).
`include "defines.v"

module wb_dmem #(
    parameter DEPTH     = 65536,
    parameter INIT_FILE = ""
)(
    input  wire        clk,
    input  wire        rst,

    // Wishbone slave interface
    input  wire        wb_cyc_i,
    input  wire        wb_stb_i,
    input  wire        wb_we_i,
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    input  wire [3:0]  wb_sel_i,
    output wire [31:0] wb_dat_o,
    output wire        wb_ack_o,

    // Sideband — funct3 from master (preserves sign/unsigned for loads)
    input  wire [2:0]  wb_funct3_i
);

    // =========================================================================
    // Wishbone handshake — combinational ack
    // =========================================================================
    wire valid = wb_cyc_i & wb_stb_i;
    assign wb_ack_o = valid;

    // =========================================================================
    // Address masking — strip upper bits (DMEM at 0x00010000-0x0001FFFF)
    // =========================================================================
    wire [31:0] local_addr = {16'd0, wb_adr_i[15:0]};

    // =========================================================================
    // Inner dmem instance
    // =========================================================================
    dmem #(.DEPTH(DEPTH), .INIT_FILE(INIT_FILE)) u_dmem (
        .clk(clk),
        .mem_read(valid & ~wb_we_i),
        .mem_write(valid & wb_we_i),
        .funct3(wb_funct3_i),
        .addr(local_addr),
        .write_data(wb_dat_i),
        .read_data(wb_dat_o)
    );

endmodule
