// Register File — 32 x 32-bit, two async read ports, one sync write port
// x0 hardwired to zero

module regfile (
    input  wire        clk,
    input  wire        we,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data
);

    reg [31:0] regs [0:31];

    // Initialize to zero for simulation cleanliness
    integer i;
    initial for (i = 0; i < 32; i = i + 1) regs[i] = 32'd0;

    // Async reads — x0 always returns 0
    assign rs1_data = (rs1_addr == 5'd0) ? 32'd0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? 32'd0 : regs[rs2_addr];

    // Sync write — ignore writes to x0
    always @(posedge clk) begin
        if (we && rd_addr != 5'd0)
            regs[rd_addr] <= rd_data;
    end

endmodule
