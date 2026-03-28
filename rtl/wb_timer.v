// Wishbone B4 Slave — CLINT-style Timer
// 64-bit free-running counter (mtime) at core clock rate.
// 64-bit comparator (mtimecmp) — timer_irq asserts when mtime >= mtimecmp.
//
// Register Map:
//   +0x0: mtime_lo    (R/W)
//   +0x4: mtime_hi    (R/W)
//   +0x8: mtimecmp_lo (R/W)
//   +0xC: mtimecmp_hi (R/W)
//
// Immediate combinational ack.

module wb_timer (
    input  wire        clk,
    input  wire        rst,

    // Wishbone slave interface
    input  wire        wb_cyc_i,
    input  wire        wb_stb_i,
    input  wire        wb_we_i,
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    input  wire [3:0]  wb_sel_i,
    output reg  [31:0] wb_dat_o,
    output wire        wb_ack_o,

    // IRQ output (active-high, exposed but not wired to core yet)
    output wire        timer_irq
);

    // =========================================================================
    // Wishbone handshake — combinational ack
    // =========================================================================
    wire valid = wb_cyc_i & wb_stb_i;
    assign wb_ack_o = valid;

    // =========================================================================
    // Register decode
    // =========================================================================
    wire [3:0] reg_sel = wb_adr_i[3:0];

    // =========================================================================
    // Timer registers
    // =========================================================================
    reg [63:0] mtime;
    reg [63:0] mtimecmp;

    // =========================================================================
    // Free-running counter + register writes
    // =========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mtime    <= 64'd0;
            mtimecmp <= 64'hFFFFFFFF_FFFFFFFF;  // Default: IRQ disabled (max compare)
        end else begin
            // Free-running increment
            mtime <= mtime + 64'd1;

            // Register writes override counter
            if (valid && wb_we_i) begin
                case (reg_sel)
                    4'h0: mtime[31:0]     <= wb_dat_i;
                    4'h4: mtime[63:32]    <= wb_dat_i;
                    4'h8: mtimecmp[31:0]  <= wb_dat_i;
                    4'hC: mtimecmp[63:32] <= wb_dat_i;
                    default: ;
                endcase
            end
        end
    end

    // =========================================================================
    // Comparator — IRQ when mtime >= mtimecmp
    // =========================================================================
    assign timer_irq = (mtime >= mtimecmp);

    // =========================================================================
    // Read mux — combinational
    // =========================================================================
    always @(*) begin
        wb_dat_o = 32'd0;
        if (valid && ~wb_we_i) begin
            case (reg_sel)
                4'h0: wb_dat_o = mtime[31:0];
                4'h4: wb_dat_o = mtime[63:32];
                4'h8: wb_dat_o = mtimecmp[31:0];
                4'hC: wb_dat_o = mtimecmp[63:32];
                default: wb_dat_o = 32'd0;
            endcase
        end
    end

endmodule
