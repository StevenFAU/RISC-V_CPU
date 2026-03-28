# RV32I Single-Cycle RISC-V Core — Build System
# Simulation: Icarus Verilog + GTKWave
# Synthesis: Vivado (xc7a100tcsg324-1, Nexys4 DDR)

IVERILOG = iverilog
VVP      = vvp
GTKWAVE  = gtkwave

RTL_DIR  = rtl
TB_DIR   = tb
SIM_DIR  = sim
SW_DIR   = sw

# All RTL sources (exclude fpga_top.v to avoid $readmemh warnings in unit tests)
RTL_ALL = $(filter-out $(RTL_DIR)/fpga_top.v, $(wildcard $(RTL_DIR)/*.v))

# RISC-V toolchain
RISCV_PREFIX ?= riscv64-unknown-elf-
AS      = $(RISCV_PREFIX)as
LD      = $(RISCV_PREFIX)ld
OBJCOPY = $(RISCV_PREFIX)objcopy

# ---- Simulation targets ----

# Compile and run a single module testbench
# Usage: make sim MOD=alu
sim: $(TB_DIR)/tb_$(MOD).v
	@mkdir -p $(SIM_DIR)
	$(IVERILOG) -o $(SIM_DIR)/tb_$(MOD).vvp \
		-I $(RTL_DIR) \
		$(RTL_ALL) \
		$(TB_DIR)/tb_$(MOD).v
	$(VVP) $(SIM_DIR)/tb_$(MOD).vvp

# Run full-core integration testbench
sim-top:
	@mkdir -p $(SIM_DIR)
	$(IVERILOG) -o $(SIM_DIR)/tb_rv32i_core.vvp \
		-I $(RTL_DIR) \
		$(RTL_ALL) \
		$(TB_DIR)/tb_rv32i_core.v
	$(VVP) $(SIM_DIR)/tb_rv32i_core.vvp

# Run FPGA top-level testbench (includes fpga_top.v; needs sim/firmware.hex)
sim-fpga:
	@mkdir -p $(SIM_DIR)
	$(IVERILOG) -o $(SIM_DIR)/tb_fpga_top.vvp \
		-I $(RTL_DIR) \
		$(wildcard $(RTL_DIR)/*.v) \
		$(TB_DIR)/tb_fpga_top.v
	$(VVP) $(SIM_DIR)/tb_fpga_top.vvp

# Open GTKWave on most recent VCD for a module
# Usage: make wave MOD=alu
wave:
	$(GTKWAVE) $(SIM_DIR)/tb_$(MOD).vcd &

# ---- Assembly targets ----

# Assemble a test program: .S -> .o -> .elf -> .hex
# Usage: make asm PROG=test_basic
asm: $(SW_DIR)/$(PROG).S
	@mkdir -p $(SIM_DIR)
	$(AS) -march=rv32i -mabi=ilp32 -o $(SIM_DIR)/$(PROG).o $(SW_DIR)/$(PROG).S
	$(LD) -m elf32lriscv -T $(SW_DIR)/link.ld -o $(SIM_DIR)/$(PROG).elf $(SIM_DIR)/$(PROG).o
	$(OBJCOPY) -O verilog $(SIM_DIR)/$(PROG).elf $(SIM_DIR)/$(PROG)_byte.hex
	python3 $(SIM_DIR)/make_imem_hex.py $(SIM_DIR)/$(PROG)_byte.hex $(SIM_DIR)/$(PROG).hex
	@rm -f $(SIM_DIR)/$(PROG)_byte.hex

# ---- Cleanup ----

clean:
	rm -rf $(SIM_DIR)/*.vvp $(SIM_DIR)/*.vcd $(SIM_DIR)/*.o $(SIM_DIR)/*.elf $(SIM_DIR)/*.hex

.PHONY: sim sim-top sim-fpga wave asm clean
