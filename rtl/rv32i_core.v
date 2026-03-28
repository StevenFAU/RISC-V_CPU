// RV32I Single-Cycle Core — Top-Level Datapath
// Memory is external: core exposes instruction fetch and data memory bus ports.
`include "defines.v"

module rv32i_core (
    input  wire        clk,
    input  wire        rst,

    // Instruction fetch bus
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_data,

    // Data memory bus
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    input  wire [31:0] dmem_rdata,
    output wire        dmem_we,
    output wire        dmem_re,
    output wire [2:0]  dmem_funct3,

    // Pre-fetch address for BRAM-based IMEM (= pc_next, forced to 0 during reset)
    output wire [31:0] imem_addr_next,

    // Debug/RVFI access to architectural state
    output wire [31:0] debug_pc,
    output wire [31:0] debug_instr
);

    // =========================================================================
    // Internal wires
    // =========================================================================

    // PC
    wire [31:0] pc_current, pc_next, pc_plus4;

    // Instruction
    wire [31:0] instr = imem_data;

    // Register file
    wire [31:0] rs1_data, rs2_data, rd_data;

    // Immediate
    wire [31:0] imm;

    // ALU
    wire [31:0] alu_a, alu_b, alu_result;
    wire [3:0]  alu_control;

    // Control signals
    wire        reg_write, mem_to_reg, mem_write, mem_read;
    wire        alu_src, ctrl_branch, ctrl_jump;
    wire [1:0]  alu_op;

    // Branch/Jump resolution
    wire        branch_taken;
    wire [31:0] branch_target, jump_target;

    // Instruction fields
    wire [6:0]  opcode       = instr[6:0];
    wire [4:0]  rd_addr      = instr[11:7];
    wire [2:0]  funct3       = instr[14:12];
    wire [4:0]  rs1_addr     = instr[19:15];
    wire [4:0]  rs2_addr     = instr[24:20];
    wire        funct7_bit30 = instr[30];

    // =========================================================================
    // Bus outputs
    // =========================================================================
    assign imem_addr      = pc_current;
    assign imem_addr_next = rst ? 32'd0 : pc_next;
    assign dmem_addr      = alu_result;
    assign dmem_wdata   = rs2_data;
    assign dmem_we      = mem_write;
    assign dmem_re      = mem_read;
    assign dmem_funct3  = funct3;

    // =========================================================================
    // Debug outputs
    // =========================================================================
    assign debug_pc    = pc_current;
    assign debug_instr = instr;

    // =========================================================================
    // PC + 4
    // =========================================================================
    assign pc_plus4 = pc_current + 32'd4;

    // =========================================================================
    // Branch condition evaluation (all 6 branch types)
    // =========================================================================
    reg branch_condition;
    always @(*) begin
        case (funct3)
            `F3_BEQ:  branch_condition = (rs1_data == rs2_data);
            `F3_BNE:  branch_condition = (rs1_data != rs2_data);
            `F3_BLT:  branch_condition = ($signed(rs1_data) < $signed(rs2_data));
            `F3_BGE:  branch_condition = ($signed(rs1_data) >= $signed(rs2_data));
            `F3_BLTU: branch_condition = (rs1_data < rs2_data);
            `F3_BGEU: branch_condition = (rs1_data >= rs2_data);
            default:  branch_condition = 1'b0;
        endcase
    end

    assign branch_taken = ctrl_branch & branch_condition;

    // =========================================================================
    // Branch and Jump targets
    // =========================================================================
    assign branch_target = pc_current + imm;
    // JALR: target = (rs1 + imm) & ~1
    assign jump_target = (opcode == `OP_JALR) ?
                         ((rs1_data + imm) & 32'hFFFFFFFE) :
                         (pc_current + imm);  // JAL

    // =========================================================================
    // PC-next mux
    // =========================================================================
    assign pc_next = ctrl_jump    ? jump_target :
                     branch_taken ? branch_target :
                     pc_plus4;

    // =========================================================================
    // ALU input muxes
    // =========================================================================
    assign alu_a = (opcode == `OP_AUIPC) ? pc_current : rs1_data;
    assign alu_b = alu_src ? imm : rs2_data;

    // =========================================================================
    // Write-back mux: ALU result vs memory load vs PC+4 (JAL/JALR) vs imm (LUI)
    // =========================================================================
    assign rd_data = (opcode == `OP_LUI) ? imm :
                     (ctrl_jump)          ? pc_plus4 :
                     (mem_to_reg)         ? dmem_rdata :
                     alu_result;

    // =========================================================================
    // Module instances
    // =========================================================================

    pc u_pc (
        .clk(clk),
        .rst(rst),
        .pc_next(pc_next),
        .pc(pc_current)
    );

    regfile u_regfile (
        .clk(clk),
        .we(reg_write),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data)
    );

    immgen u_immgen (
        .instr(instr),
        .imm(imm)
    );

    control u_control (
        .opcode(opcode),
        .reg_write(reg_write),
        .mem_to_reg(mem_to_reg),
        .mem_write(mem_write),
        .mem_read(mem_read),
        .alu_src(alu_src),
        .branch(ctrl_branch),
        .jump(ctrl_jump),
        .alu_op(alu_op)
    );

    alu_decoder u_alu_decoder (
        .alu_op(alu_op),
        .funct3(funct3),
        .funct7_bit30(funct7_bit30),
        .alu_control(alu_control)
    );

    alu u_alu (
        .a(alu_a),
        .b(alu_b),
        .alu_op(alu_control),
        .result(alu_result),
        .zero()
    );

endmodule
