// Data Memory — byte-addressable, supports LB/LH/LW/LBU/LHU and SB/SH/SW
`include "defines.v"

module dmem #(
    parameter DEPTH = 4096  // Bytes
)(
    input  wire        clk,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [2:0]  funct3,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    output reg  [31:0] read_data
);

    reg [7:0] mem [0:DEPTH-1];

    wire [31:0] byte_addr = addr;

    // --- Read (combinational) ---
    always @(*) begin
        case (funct3)
            `F3_BYTE:   // LB — sign-extended byte
                read_data = {{24{mem[byte_addr][7]}}, mem[byte_addr]};
            `F3_HALF:   // LH — sign-extended halfword
                read_data = {{16{mem[byte_addr+1][7]}}, mem[byte_addr+1], mem[byte_addr]};
            `F3_WORD:   // LW — full word (little-endian)
                read_data = {mem[byte_addr+3], mem[byte_addr+2], mem[byte_addr+1], mem[byte_addr]};
            `F3_BYTEU:  // LBU — zero-extended byte
                read_data = {24'd0, mem[byte_addr]};
            `F3_HALFU:  // LHU — zero-extended halfword
                read_data = {16'd0, mem[byte_addr+1], mem[byte_addr]};
            default:
                read_data = 32'd0;
        endcase
    end

    // --- Write (synchronous) ---
    always @(posedge clk) begin
        if (mem_write) begin
            case (funct3)
                `F3_BYTE:   // SB
                    mem[byte_addr] <= write_data[7:0];
                `F3_HALF: begin // SH (little-endian)
                    mem[byte_addr]   <= write_data[7:0];
                    mem[byte_addr+1] <= write_data[15:8];
                end
                `F3_WORD: begin // SW (little-endian)
                    mem[byte_addr]   <= write_data[7:0];
                    mem[byte_addr+1] <= write_data[15:8];
                    mem[byte_addr+2] <= write_data[23:16];
                    mem[byte_addr+3] <= write_data[31:24];
                end
                default: ; // No write
            endcase
        end
    end

endmodule
