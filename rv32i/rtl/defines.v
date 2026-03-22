// =============================================================================
// RV32I Definitions — Opcodes, funct3, funct7, ALU operations
// Style: `define macros (used throughout all modules)
// =============================================================================

// ----- Opcodes (bits [6:0] of instruction) -----
`define OP_R_TYPE   7'b0110011  // R-type arithmetic
`define OP_I_ALU    7'b0010011  // I-type arithmetic (ADDI, etc.)
`define OP_LOAD     7'b0000011  // Load (LB, LH, LW, LBU, LHU)
`define OP_STORE    7'b0100011  // Store (SB, SH, SW)
`define OP_BRANCH   7'b1100011  // Branch (BEQ, BNE, BLT, BGE, BLTU, BGEU)
`define OP_JAL      7'b1101111  // Jump and Link
`define OP_JALR     7'b1100111  // Jump and Link Register
`define OP_LUI      7'b0110111  // Load Upper Immediate
`define OP_AUIPC    7'b0010111  // Add Upper Immediate to PC
`define OP_CUSTOM0  7'b0001011  // Reserved for future custom accelerator

// ----- funct3 fields -----

// R-type and I-type ALU funct3
`define F3_ADD_SUB  3'b000
`define F3_SLL      3'b001
`define F3_SLT      3'b010
`define F3_SLTU     3'b011
`define F3_XOR      3'b100
`define F3_SRL_SRA  3'b101
`define F3_OR       3'b110
`define F3_AND      3'b111

// Branch funct3
`define F3_BEQ      3'b000
`define F3_BNE      3'b001
`define F3_BLT      3'b100
`define F3_BGE      3'b101
`define F3_BLTU     3'b110
`define F3_BGEU     3'b111

// Load/Store funct3 (width)
`define F3_BYTE     3'b000  // LB / SB
`define F3_HALF     3'b001  // LH / SH
`define F3_WORD     3'b010  // LW / SW
`define F3_BYTEU    3'b100  // LBU
`define F3_HALFU    3'b101  // LHU

// ----- funct7 distinguishing bit -----
`define F7_NORMAL   1'b0    // ADD, SRL
`define F7_ALT      1'b1    // SUB, SRA

// ----- ALU Operation Codes (4-bit internal encoding) -----
`define ALU_ADD     4'b0000
`define ALU_SUB     4'b0001
`define ALU_AND     4'b0010
`define ALU_OR      4'b0011
`define ALU_XOR     4'b0100
`define ALU_SLL     4'b0101
`define ALU_SRL     4'b0110
`define ALU_SRA     4'b0111
`define ALU_SLT     4'b1000
`define ALU_SLTU    4'b1001

// ----- ALU Op from main decoder (2-bit) -----
// Used by main control to tell ALU decoder what category of operation
`define ALUOP_LOAD_STORE 2'b00  // ADD for address calculation
`define ALUOP_BRANCH     2'b01  // SUB for comparison
`define ALUOP_R_TYPE     2'b10  // Look at funct3/funct7
`define ALUOP_I_TYPE     2'b11  // Look at funct3 (funct7 for shifts)
