// Compliance Testbench for RV32I Core
// Unified byte-addressed memory connected via core's external bus ports.
// Monitors writes to tohost (0x1000) for pass/fail.
`timescale 1ns/1ps

module tb_compliance;

    reg clk, rst;

    // =========================================================================
    // Unified memory — 16 KB byte-addressed
    // =========================================================================
    parameter MEM_SIZE   = 16384;
    parameter TOHOST_ADDR = 32'h00001000;
    parameter MAX_CYCLES  = 10000;

    reg [7:0] mem [0:MEM_SIZE-1];

    // =========================================================================
    // Core bus signals
    // =========================================================================
    wire [31:0] imem_addr, imem_data;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire        dmem_we, dmem_re;
    wire [2:0]  dmem_funct3;
    wire [31:0] debug_pc, debug_instr;

    // =========================================================================
    // Core instance
    // =========================================================================
    rv32i_core dut (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_data(imem_data),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_rdata(dmem_rdata), .dmem_we(dmem_we),
        .dmem_re(dmem_re), .dmem_funct3(dmem_funct3),
        .debug_pc(debug_pc), .debug_instr(debug_instr)
    );

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
