// Instruction Memory — read-only, word-addressed
// Loads contents from hex file via $readmemh

module imem #(
    parameter DEPTH = 1024  // Number of 32-bit words
)(
    input  wire [31:0] addr,
    output wire [31:0] instr
);

    reg [31:0] mem [0:DEPTH-1];

    // Byte-addressed input, word-aligned: drop bottom 2 bits
    assign instr = mem[addr[31:2]];

    // Load program from hex file — path set by testbench via $readmemh
    // (Testbench or top-level calls $readmemh on imem.mem)

endmodule
