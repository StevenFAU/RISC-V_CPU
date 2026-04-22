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
    // Only addr[$clog2(DEPTH)+1:2] indexes the memory — low 2 bits are the
    // word alignment and high bits are above the IMEM window.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] addr,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire [31:0] instr
);

    // ram_style = "block" guides Vivado to infer BRAM when SYNC_READ=1.
    // For SYNC_READ=0 (async read), Vivado ignores this and uses distributed RAM.
    (* ram_style = "block" *) reg [31:0] mem [0:DEPTH-1];

    generate
        if (INIT_FILE != "") begin : gen_init
            initial $readmemh(INIT_FILE, mem);
        end
    endgenerate

    // Bound address to actual depth — unbounded addr[31:2] can block BRAM inference
    wire [$clog2(DEPTH)-1:0] word_addr = addr[$clog2(DEPTH)+1:2];

    generate
        if (SYNC_READ) begin : gen_sync
            // Registered read — Vivado infers BRAM
            reg [31:0] instr_reg;
            always @(posedge clk)
                instr_reg <= mem[word_addr];
            assign instr = instr_reg;
        end else begin : gen_async
            // Combinational read — distributed RAM
            assign instr = mem[word_addr];
        end
    endgenerate

endmodule
