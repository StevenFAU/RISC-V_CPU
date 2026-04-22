// Data Memory — word-based storage with byte enables for BRAM inference
// Supports LB/LH/LW/LBU/LHU and SB/SH/SW
`include "defines.v"

module dmem #(
    parameter DEPTH     = 4096,  // Bytes (must be multiple of 4)
    parameter INIT_FILE = ""
)(
    input  wire        clk,
    // Note: mem_read is accepted but unused — reads are unconditional (combinational).
    // Connected by wb_dmem.v for interface completeness; removing would require
    // changing all instantiation sites for no functional benefit.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire        mem_read,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire        mem_write,
    input  wire [2:0]  funct3,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    output reg  [31:0] read_data
);

    // Word-based storage — distributed RAM (async read required for single-cycle loads)
    // BRAM inference requires synchronous reads, which would need pipeline changes.
    localparam WORDS = DEPTH / 4;
    (* ram_style = "distributed" *) reg [31:0] mem [0:WORDS-1];

    // Optional initialization from hex file (word-addressed)
    generate
        if (INIT_FILE != "") begin : gen_init
            initial $readmemh(INIT_FILE, mem);
        end
    endgenerate

    // DEFERRED (Phase 0.3+): word_addr could be declared [$clog2(WORDS)-1:0]
    // to match the 10 bits actually used for indexing, which would drop both
    // of these waivers. Kept oversized for now to avoid RTL churn during the
    // infrastructure-only Phase 0.3 scope.
    //   - WIDTHEXPAND: RHS is 30 bits (addr[31:2]), LHS is 32 bits → zero-extend.
    //   - UNUSEDSIGNAL: only word_addr[$clog2(WORDS)-1:0] is read by mem[].
    /* verilator lint_off WIDTHEXPAND */
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] word_addr = addr[31:2];
    /* verilator lint_on UNUSEDSIGNAL */
    /* verilator lint_on WIDTHEXPAND */
    wire [1:0]  byte_off  = addr[1:0];

    // Read the full word from memory
    wire [31:0] raw_word = mem[word_addr];

    // --- Read (combinational) — extract and sign/zero extend ---
    always @(*) begin
        case (funct3)
            `F3_BYTE: begin  // LB — sign-extended byte
                case (byte_off)
                    2'd0: read_data = {{24{raw_word[7]}},  raw_word[7:0]};
                    2'd1: read_data = {{24{raw_word[15]}}, raw_word[15:8]};
                    2'd2: read_data = {{24{raw_word[23]}}, raw_word[23:16]};
                    2'd3: read_data = {{24{raw_word[31]}}, raw_word[31:24]};
                endcase
            end
            `F3_HALF: begin  // LH — sign-extended halfword
                case (byte_off[1])
                    1'b0: read_data = {{16{raw_word[15]}}, raw_word[15:0]};
                    1'b1: read_data = {{16{raw_word[31]}}, raw_word[31:16]};
                endcase
            end
            `F3_WORD:    // LW — full word
                read_data = raw_word;
            `F3_BYTEU: begin  // LBU — zero-extended byte
                case (byte_off)
                    2'd0: read_data = {24'd0, raw_word[7:0]};
                    2'd1: read_data = {24'd0, raw_word[15:8]};
                    2'd2: read_data = {24'd0, raw_word[23:16]};
                    2'd3: read_data = {24'd0, raw_word[31:24]};
                endcase
            end
            `F3_HALFU: begin  // LHU — zero-extended halfword
                case (byte_off[1])
                    1'b0: read_data = {16'd0, raw_word[15:0]};
                    1'b1: read_data = {16'd0, raw_word[31:16]};
                endcase
            end
            default:
                read_data = 32'd0;
        endcase
    end

    // --- Write (synchronous) — byte-enable pattern for BRAM ---
    always @(posedge clk) begin
        if (mem_write) begin
            case (funct3)
                `F3_BYTE: begin  // SB
                    case (byte_off)
                        2'd0: mem[word_addr][7:0]   <= write_data[7:0];
                        2'd1: mem[word_addr][15:8]  <= write_data[7:0];
                        2'd2: mem[word_addr][23:16] <= write_data[7:0];
                        2'd3: mem[word_addr][31:24] <= write_data[7:0];
                    endcase
                end
                `F3_HALF: begin  // SH (little-endian)
                    case (byte_off[1])
                        1'b0: mem[word_addr][15:0]  <= write_data[15:0];
                        1'b1: mem[word_addr][31:16] <= write_data[15:0];
                    endcase
                end
                `F3_WORD:  // SW
                    mem[word_addr] <= write_data;
                default: ; // No write
            endcase
        end
    end

endmodule
