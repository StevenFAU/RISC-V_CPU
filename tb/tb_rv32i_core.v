// Integration Testbench for RV32I Single-Cycle Core
// Instantiates external IMEM and DMEM, wires them to the core's bus ports.
`timescale 1ns/1ps

module tb_rv32i_core;
    reg  clk, rst;
    wire [31:0] debug_pc, debug_instr;

    parameter IMEM_DEPTH = 256;
    parameter DMEM_DEPTH = 4096;
    parameter MAX_CYCLES = 500;

    // Core bus signals
    wire [31:0] imem_addr, imem_data;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire        dmem_we, dmem_re;
    wire [2:0]  dmem_funct3;

    rv32i_core uut (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_data(imem_data),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_rdata(dmem_rdata), .dmem_we(dmem_we),
        .dmem_re(dmem_re), .dmem_funct3(dmem_funct3),
        .debug_pc(debug_pc), .debug_instr(debug_instr)
    );

    imem #(.DEPTH(IMEM_DEPTH)) u_imem (
        .addr(imem_addr), .instr(imem_data)
    );

    // Strip upper bits to match bus decoder behavior (DMEM at 0x00010000-0x0001FFFF)
    wire [31:0] dmem_addr_masked = {16'd0, dmem_addr[15:0]};

    dmem #(.DEPTH(DMEM_DEPTH)) u_dmem (
        .clk(clk),
        .mem_read(dmem_re), .mem_write(dmem_we),
        .funct3(dmem_funct3),
        .addr(dmem_addr_masked), .write_data(dmem_wdata),
        .read_data(dmem_rdata)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer cycle_count;
    integer i;

    // Signature: test_basic.S stores 0xDEADBEEF at DMEM[0x00010000]
    // Bus decoder strips upper bits, so it lands at word 0 in DMEM
    wire [31:0] sig_word = u_dmem.mem[0];

    initial begin
        $dumpfile("sim/tb_rv32i_core.vcd");
        $dumpvars(0, tb_rv32i_core);

        // Load test program
        $readmemh("sim/test_basic.hex", u_imem.mem);

        // Reset
        rst = 1;
        @(posedge clk); @(posedge clk);
        rst = 0;

        for (cycle_count = 0; cycle_count < MAX_CYCLES; cycle_count = cycle_count + 1) begin
            @(posedge clk);
            #1;

            if (debug_instr !== 32'hxxxxxxxx && debug_instr !== 32'h0)
                $display("Cycle %3d: PC=0x%08h  Instr=0x%08h", cycle_count, debug_pc, debug_instr);

            // ECALL halt
            if (debug_instr == 32'h00000073) begin
                $display("\n--- ECALL detected at cycle %0d, PC=0x%08h ---", cycle_count, debug_pc);
                cycle_count = MAX_CYCLES;
            end
        end

        // Check pass signature
        $display("\nSignature word at DMEM[0]: 0x%08h", sig_word);
        if (sig_word === 32'hDEADBEEF)
            $display("*** INTEGRATION TEST PASSED ***");
        else
            $display("*** INTEGRATION TEST FAILED — expected 0xDEADBEEF ***");

        // Dump nonzero registers
        $display("\n--- Register File Dump ---");
        for (i = 0; i < 32; i = i + 1) begin
            if (uut.u_regfile.regs[i] !== 32'h0 && i != 0)
                $display("  x%02d = 0x%08h (%0d)", i, uut.u_regfile.regs[i], $signed(uut.u_regfile.regs[i]));
        end

        $finish;
    end
endmodule
