// Wishbone B4 Slave — GPIO Peripheral
// Reg 0x0: output register → drives active-high LEDs[15:0]
// Reg 0x4: input register  ← reads slide switches SW[15:0]
// Immediate combinational ack.

module wb_gpio (
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

    // Physical I/O
    output reg  [15:0] gpio_out,   // → LEDs
    input  wire [15:0] gpio_in     // ← Switches
);

    // =========================================================================
    // Wishbone handshake — combinational ack
    // =========================================================================
    wire valid = wb_cyc_i & wb_stb_i;
    assign wb_ack_o = valid;

    // =========================================================================
    // Register decode
    // =========================================================================
    wire [2:0] reg_sel = wb_adr_i[2:0];

    // =========================================================================
    // Output register — synchronous write
    // =========================================================================
    always @(posedge clk) begin
        if (rst)
            gpio_out <= 16'd0;
        else if (valid && wb_we_i && reg_sel == 3'h0)
            gpio_out <= wb_dat_i[15:0];
    end

    // =========================================================================
    // Read mux — combinational
    // =========================================================================
    always @(*) begin
        wb_dat_o = 32'd0;
        if (valid && ~wb_we_i) begin
            case (reg_sel)
                3'h0: wb_dat_o = {16'd0, gpio_out};    // Output register readback
                3'h4: wb_dat_o = {16'd0, gpio_in};     // Input (switches)
                default: wb_dat_o = 32'd0;
            endcase
        end
    end

endmodule
