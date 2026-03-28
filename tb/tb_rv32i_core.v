// Integration Testbench for RV32I Single-Cycle Core
// Wires core through Wishbone stack: wb_master → wb_interconnect → wb_dmem
`timescale 1ns/1ps

module tb_rv32i_core;
    reg  clk, rst;
    wire [31:0] debug_pc, debug_instr;

    parameter IMEM_DEPTH = 256;
    parameter DMEM_DEPTH = 4096;
    parameter MAX_CYCLES = 500;

    // Core bus signals
    wire [31:0] imem_addr, imem_addr_next, imem_data;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire        dmem_we, dmem_re;
    wire [2:0]  dmem_funct3;

    // Wishbone master signals
    wire        wb_cyc, wb_stb, wb_we;
    wire [31:0] wb_adr, wb_dat_m2s, wb_dat_s2m;
    wire [3:0]  wb_sel;
    wire        wb_ack;
    wire [2:0]  wb_funct3;

    // Wishbone slave 0 (DMEM) signals
    wire        wbs0_cyc, wbs0_stb, wbs0_we;
    wire [31:0] wbs0_adr, wbs0_dat_m2s, wbs0_dat_s2m;
    wire [3:0]  wbs0_sel;
    wire        wbs0_ack;
    wire [2:0]  wbs0_funct3;

    rv32i_core uut (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_data(imem_data),
        .imem_addr_next(imem_addr_next),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_rdata(dmem_rdata), .dmem_we(dmem_we),
        .dmem_re(dmem_re), .dmem_funct3(dmem_funct3),
        .debug_pc(debug_pc), .debug_instr(debug_instr)
    );

    // Async read (SYNC_READ=0) — testbench uses pc_current, not pc_next
    imem #(.DEPTH(IMEM_DEPTH)) u_imem (
        .clk(clk), .addr(imem_addr), .instr(imem_data)
    );

    wb_master u_wb_master (
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_we(dmem_we), .dmem_re(dmem_re),
        .dmem_funct3(dmem_funct3), .dmem_rdata(dmem_rdata),
        .wb_cyc_o(wb_cyc), .wb_stb_o(wb_stb), .wb_we_o(wb_we),
        .wb_adr_o(wb_adr), .wb_dat_o(wb_dat_m2s), .wb_sel_o(wb_sel),
        .wb_dat_i(wb_dat_s2m), .wb_ack_i(wb_ack),
        .wb_funct3_o(wb_funct3)
    );

    wb_interconnect u_wb_ic (
        .wbm_cyc_i(wb_cyc), .wbm_stb_i(wb_stb), .wbm_we_i(wb_we),
        .wbm_adr_i(wb_adr), .wbm_dat_i(wb_dat_m2s), .wbm_sel_i(wb_sel),
        .wbm_dat_o(wb_dat_s2m), .wbm_ack_o(wb_ack),
        .wbm_funct3_i(wb_funct3),
        .wbs0_cyc_o(wbs0_cyc), .wbs0_stb_o(wbs0_stb), .wbs0_we_o(wbs0_we),
        .wbs0_adr_o(wbs0_adr), .wbs0_dat_o(wbs0_dat_m2s), .wbs0_sel_o(wbs0_sel),
        .wbs0_dat_i(wbs0_dat_s2m), .wbs0_ack_i(wbs0_ack),
        .wbs0_funct3_o(wbs0_funct3)
    );

    wb_dmem #(.DEPTH(DMEM_DEPTH)) u_wb_dmem (
        .clk(clk), .rst(rst),
        .wb_cyc_i(wbs0_cyc), .wb_stb_i(wbs0_stb), .wb_we_i(wbs0_we),
        .wb_adr_i(wbs0_adr), .wb_dat_i(wbs0_dat_m2s), .wb_sel_i(wbs0_sel),
        .wb_dat_o(wbs0_dat_s2m), .wb_ack_o(wbs0_ack),
        .wb_funct3_i(wbs0_funct3)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer cycle_count;
    integer i;

    // Signature: test_basic.S stores 0xDEADBEEF at DMEM[0x00010000]
    // wb_dmem strips upper bits, so it lands at word 0 in inner dmem
    wire [31:0] sig_word = u_wb_dmem.u_dmem.mem[0];

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
