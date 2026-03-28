// Instruction Memory — word-addressed, read-only
// SYNC_READ=0: combinational read (distributed RAM, for simulation/testbenches)
// SYNC_READ=1: registered read (BRAM-friendly, for synthesis)
//
// When SYNC_READ=1, drive addr with pc_next (not pc_current) so the 1-cycle
// BRAM latency is hidden — the output aligns with pc_current after the edge.

module imem #(
    parameter DEPTH     = 1024,
    parameter INIT_FILE = "",
    parameter SYNC_READ = 0
)(
    input  wire        clk,
    input  wire [31:0] addr,
    output wire [31:0] instr
);

    reg [31:0] mem [0:DEPTH-1];

    generate
        if (INIT_FILE != "") begin : gen_init
            initial $readmemh(INIT_FILE, mem);
        end
    endgenerate

    generate
        if (SYNC_READ) begin : gen_sync
            // Registered read — Vivado infers BRAM automatically
            reg [31:0] instr_reg;
            always @(posedge clk)
                instr_reg <= mem[addr[31:2]];
            assign instr = instr_reg;
        end else begin : gen_async
            // Combinational read — distributed RAM
            assign instr = mem[addr[31:2]];
        end
    endgenerate

endmodule
