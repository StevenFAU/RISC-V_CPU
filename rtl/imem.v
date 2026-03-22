// Instruction Memory — read-only, word-addressed
// Loads contents from hex file via $readmemh

module imem #(
    parameter DEPTH     = 1024,  // Number of 32-bit words
    parameter INIT_FILE = ""
)(
    input  wire [31:0] addr,
    output wire [31:0] instr
);

    reg [31:0] mem [0:DEPTH-1];

    // Byte-addressed input, word-aligned: drop bottom 2 bits
    assign instr = mem[addr[31:2]];

    // Optional initialization from hex file
    generate
        if (INIT_FILE != "") begin : gen_init
            initial $readmemh(INIT_FILE, mem);
        end
    endgenerate

endmodule
