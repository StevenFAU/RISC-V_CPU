// Compliance Testbench for RV32I Core
// Unified byte-addressed memory connected via core's external bus ports.
// Monitors writes to tohost (0x1000) for pass/fail.
//
// =========================================================================
// MEMORY MODEL — important context for readers
// =========================================================================
// This testbench models a unified 16 KB byte-addressed memory starting at
// address 0x00000000. Both instruction fetch and data access go through
// this single array (`mem[0..16383]`).
//
// This is DIFFERENT from the synthesized hardware memory map, which has
// IMEM at 0x00000000 and DMEM at 0x00010000 (see `sw/link.ld`).
//
// Compliance tests use a separate linker script (`tests/link.ld`) that
// places all sections within the 16 KB testbench window:
//   .text.init at 0x00000000
//   .tohost    at 0x00001000
//   .data      at 0x00002000
//
// The testbench works because compliance tests are linked for the
// testbench layout, not the hardware layout. Hand-written programs in
// `sw/` use `sw/link.ld` and target the hardware layout instead — they
// are NOT compatible with this testbench.
//
// If you're debugging "why does my test program silently read zeros,"
// check which linker script your program was built with.
// =========================================================================
`timescale 1ns/1ps

module tb_compliance;

    reg clk, rst;

    // =========================================================================
    // Unified memory — 16 KB byte-addressed
    // =========================================================================
    // MEM_SIZE must match the upper bound assumed by tests/link.ld.
    // Currently 16 KB — resizing here means touching the linker script too.
    parameter MEM_SIZE   = 16384;
    parameter TOHOST_ADDR = 32'h00001000;
    parameter MAX_CYCLES  = 10000;

    reg [7:0] mem [0:MEM_SIZE-1];

    // =========================================================================
    // Core bus signals
    // =========================================================================
    wire [31:0] imem_addr, imem_addr_next, imem_data;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire        dmem_we, dmem_re;
    wire [2:0]  dmem_funct3;
    wire [31:0] debug_pc, debug_instr;

    // =========================================================================
    // CSR file <-> core interface wiring
    // =========================================================================
    // Phase 1.2.5 Step 1: csr_file is now instantiated alongside rv32i_core in
    // this harness, mirroring the fpga_top.v topology. rv32ui programs do not
    // execute CSR instructions and do not take synchronous traps, so the
    // csr_file is exercised only by its retirement-counter tick from the core
    // — its outputs to the core (mtvec/mepc/mstatus_mie) remain at reset
    // values throughout an rv32ui run. rv32mi tests, conversely, drive the
    // full CSR + trap path.
    //
    // The unified-memory model in this testbench is unchanged. csr_file's
    // interface to the core is via dedicated CSR / trap-entry ports that
    // bypass the bus, so the bus-level structural difference between this
    // harness and fpga_top is not relevant to the integration here.
    wire [11:0] core_csr_addr;
    wire        core_csr_read_en;
    wire [2:0]  core_csr_write_op;
    wire [31:0] core_csr_write_data;
    wire [31:0] csr_read_data;
    wire        csr_illegal;
    wire        core_instret_tick;
    wire [31:0] csr_mtvec;
    wire [31:0] csr_mepc;
    wire        csr_mstatus_mie;
    wire        core_trap_enter;
    wire [31:0] core_trap_pc;
    wire [31:0] core_trap_cause;
    wire [31:0] core_trap_tval;
    wire        core_trap_return;

    // =========================================================================
    // Core instance
    // =========================================================================
    // illegal_inst_o is consumed internally by the core's trap encoder; no
    // harness-level consumer (the trap_*_o ports already expose the trap
    // state). bus_error_i is tied 1'b0 here — there is no wb_interconnect in
    // this harness, the unified memory model decodes every address inside the
    // 16 KB window, and access-fault behavior is therefore not exercisable
    // here. rv32mi access-fault tests, if any, will (E) against the harness
    // and either be re-classified or sourced from a harness extension in a
    // later step; Step 1 keeps the tie-off explicit to avoid floating-input
    // X-propagation.
    /* verilator lint_off PINCONNECTEMPTY */
    rv32i_core dut (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_data(imem_data),
        .imem_addr_next(imem_addr_next),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_rdata(dmem_rdata), .dmem_we(dmem_we),
        .dmem_re(dmem_re), .dmem_funct3(dmem_funct3),
        // CSR interface
        .csr_addr_o(core_csr_addr),
        .csr_read_en_o(core_csr_read_en),
        .csr_write_op_o(core_csr_write_op),
        .csr_write_data_o(core_csr_write_data),
        .csr_read_data_i(csr_read_data),
        .csr_illegal_i(csr_illegal),
        .instret_tick_o(core_instret_tick),
        .illegal_inst_o(/* unconnected — exposed via trap_*_o */),
        // Trap-entry outputs to csr_file
        .trap_enter_o(core_trap_enter),
        .trap_pc_o(core_trap_pc),
        .trap_cause_o(core_trap_cause),
        .trap_tval_o(core_trap_tval),
        // Trap-return output to csr_file (Phase 1.2.3)
        .trap_return_o(core_trap_return),
        .mtvec_i(csr_mtvec),
        .mepc_i(csr_mepc),
        .mstatus_mie_i(csr_mstatus_mie),
        // No wb_interconnect in this harness; access faults not exercised.
        .bus_error_i(1'b0),
        .debug_pc(debug_pc), .debug_instr(debug_instr)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // =========================================================================
    // CSR file instance
    // =========================================================================
    // Mirrors fpga_top.v u_csr_file. mstatus_o is debug-only visibility and
    // unconsumed at harness level (same as fpga_top).
    /* verilator lint_off PINCONNECTEMPTY */
    csr_file u_csr_file (
        .clk(clk), .rst(rst),
        .csr_addr(core_csr_addr),
        .csr_read_en(core_csr_read_en),
        .csr_write_op(core_csr_write_op),
        .csr_write_data(core_csr_write_data),
        .csr_read_data(csr_read_data),
        .csr_illegal(csr_illegal),
        .trap_enter(core_trap_enter),
        .trap_pc(core_trap_pc),
        .trap_cause(core_trap_cause),
        .trap_tval(core_trap_tval),
        .trap_return(core_trap_return),
        .instret_tick(core_instret_tick),
        .mtvec_o(csr_mtvec),
        .mepc_o(csr_mepc),
        .mstatus_mie_o(csr_mstatus_mie),
        .mstatus_o(/* debug-only — unconsumed */)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // =========================================================================
    // Instruction fetch — combinational read from unified memory
    // =========================================================================
    assign imem_data = {mem[imem_addr+3], mem[imem_addr+2],
                        mem[imem_addr+1], mem[imem_addr]};

    // =========================================================================
    // Data memory read — combinational, width-aware
    // =========================================================================
    reg [31:0] dmem_rdata_r;
    assign dmem_rdata = dmem_rdata_r;

    always @(*) begin
        if (dmem_re) begin
            case (dmem_funct3)
                3'b000: dmem_rdata_r = {{24{mem[dmem_addr][7]}}, mem[dmem_addr]};                       // LB
                3'b001: dmem_rdata_r = {{16{mem[dmem_addr+1][7]}}, mem[dmem_addr+1], mem[dmem_addr]};   // LH
                3'b010: dmem_rdata_r = {mem[dmem_addr+3], mem[dmem_addr+2], mem[dmem_addr+1], mem[dmem_addr]}; // LW
                3'b100: dmem_rdata_r = {24'd0, mem[dmem_addr]};                                         // LBU
                3'b101: dmem_rdata_r = {16'd0, mem[dmem_addr+1], mem[dmem_addr]};                       // LHU
                default: dmem_rdata_r = 32'd0;
            endcase
        end else begin
            dmem_rdata_r = 32'd0;
        end
    end

    // =========================================================================
    // Data memory write — synchronous
    // =========================================================================
    always @(posedge clk) begin
        if (dmem_we) begin
            case (dmem_funct3)
                3'b000: // SB
                    mem[dmem_addr] <= dmem_wdata[7:0];
                3'b001: begin // SH
                    mem[dmem_addr]   <= dmem_wdata[7:0];
                    mem[dmem_addr+1] <= dmem_wdata[15:8];
                end
                3'b010: begin // SW
                    mem[dmem_addr]   <= dmem_wdata[7:0];
                    mem[dmem_addr+1] <= dmem_wdata[15:8];
                    mem[dmem_addr+2] <= dmem_wdata[23:16];
                    mem[dmem_addr+3] <= dmem_wdata[31:24];
                end
                default: ;
            endcase
        end
    end

    // =========================================================================
    // Clock
    // =========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================================
    // tohost monitoring — read from unified mem
    // =========================================================================
    wire [31:0] tohost_val = {mem[TOHOST_ADDR+3], mem[TOHOST_ADDR+2],
                              mem[TOHOST_ADDR+1], mem[TOHOST_ADDR]};

    // =========================================================================
    // Test execution
    // =========================================================================
    reg [256*8-1:0] firmware;
    integer cycle_count;
    integer i;

    initial begin
        if (!$value$plusargs("firmware=%s", firmware)) begin
            $display("ERROR: No +firmware=<path> specified");
            $finish;
        end

        // Initialize memory to zero
        for (i = 0; i < MEM_SIZE; i = i + 1)
            mem[i] = 8'h00;

        // Load firmware (byte-addressed hex from objcopy -O verilog)
        $readmemh(firmware, mem);

        // Reset
        rst = 1;
        @(posedge clk); @(posedge clk);
        rst = 0;

        // Run with watchdog
        for (cycle_count = 0; cycle_count < MAX_CYCLES; cycle_count = cycle_count + 1) begin
            @(posedge clk);
            #1;

            // Check tohost
            if (tohost_val != 32'd0) begin
                if (tohost_val == 32'd1) begin
                    $display("PASS (cycles: %0d)", cycle_count);
                end else begin
                    $display("FAIL: test %0d (tohost=0x%08h, cycles: %0d)",
                             tohost_val >> 1, tohost_val, cycle_count);
                end
                $finish;
            end
        end

        $display("TIMEOUT after %0d cycles", MAX_CYCLES);
        $finish;
    end

endmodule
