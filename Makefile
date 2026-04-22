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

# ---- RISC-V toolchain ----
# The `asm` target keeps using RISCV_PREFIX (system binaries) — assembly
# programs don't need newlib, so the Ubuntu gcc-riscv64-unknown-elf package
# is fine for them.
RISCV_PREFIX ?= riscv64-unknown-elf-
AS      = $(RISCV_PREFIX)as
LD      = $(RISCV_PREFIX)ld
OBJCOPY = $(RISCV_PREFIX)objcopy

# The `c` target needs a gcc that ships newlib-nano (nano.specs) built for
# rv32i/ilp32. No distro package supplies that — we build
# riscv-gnu-toolchain from source; see docs/toolchain.md for the procedure.
#
# Discovery order (first hit wins; override by passing RISCV_GCC=/path on the
# command line):
#   1. /opt/riscv/bin/riscv32-unknown-elf-gcc  (system-wide install)
#   2. $HOME/riscv/bin/riscv32-unknown-elf-gcc (per-user install)
#   3. riscv32-unknown-elf-gcc on PATH
#
# Sentinel "TOOLCHAIN_NOT_FOUND" makes detection failures explicit; the `c`
# target traps it and emits an actionable error pointing at docs/toolchain.md.
#
# We deliberately do NOT fall back to riscv64-unknown-elf-gcc from Ubuntu or
# from the Vivado bundle: both are missing working newlib-nano libs for
# rv32i/ilp32. See docs/toolchain.md "Why not X" section.
RISCV_GCC ?= $(shell \
    if [ -x /opt/riscv/bin/riscv32-unknown-elf-gcc ]; then \
        echo /opt/riscv/bin/riscv32-unknown-elf-gcc; \
    elif [ -x $$HOME/riscv/bin/riscv32-unknown-elf-gcc ]; then \
        echo $$HOME/riscv/bin/riscv32-unknown-elf-gcc; \
    elif command -v riscv32-unknown-elf-gcc >/dev/null 2>&1; then \
        command -v riscv32-unknown-elf-gcc; \
    else \
        echo "TOOLCHAIN_NOT_FOUND"; \
    fi)

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

# Run FPGA top-level testbench against the assembly "Hello, RISC-V!" program.
# Needs sim/firmware.hex + sim/dmem_init.hex (produced by `make asm PROG=hello`
# + manual DMEM image today — see sw/hello.S notes).
sim-fpga:
	@mkdir -p $(SIM_DIR)
	$(IVERILOG) -o $(SIM_DIR)/tb_fpga_top_asm.vvp \
		-I $(RTL_DIR) \
		$(wildcard $(RTL_DIR)/*.v) \
		$(TB_DIR)/tb_fpga_top_asm.v
	$(VVP) $(SIM_DIR)/tb_fpga_top_asm.vvp

# Run FPGA top-level testbench against the C "Hello from C!" program.
# Needs sim/hello_c.hex + sim/hello_c_dmem.hex (produced by `make c PROG=hello_c`).
sim-fpga-c:
	@mkdir -p $(SIM_DIR)
	$(IVERILOG) -o $(SIM_DIR)/tb_fpga_top_c.vvp \
		-I $(RTL_DIR) \
		$(wildcard $(RTL_DIR)/*.v) \
		$(TB_DIR)/tb_fpga_top_c.v
	$(VVP) $(SIM_DIR)/tb_fpga_top_c.vvp

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

# ---- C targets ----

# Build a C program into an IMEM + DMEM hex pair.
# Usage: make c PROG=hello_c
#
# Output files:
#   sim/$(PROG).elf         — full ELF, for size/objdump inspection
#   sim/$(PROG).hex         — IMEM image (.text+.text.init, word-addressed)
#   sim/$(PROG)_dmem.hex    — DMEM image (.rodata+.data, word-addressed, relative to DMEM base)
#
# Flags:
#   -march=rv32i -mabi=ilp32   — target ISA/ABI.
#   -nostartfiles              — no gcc startup glue; our crt0.S is authoritative.
#   -specs=nano.specs          — newlib-nano (smaller printf, no float by default).
#   -Os                        — optimize for size; printf is ~8-10 KB even so.
#   -ffunction-sections
#   -fdata-sections
#   -Wl,--gc-sections          — drop unused library functions at link time.
#   -T sw/c_link.ld            — Harvard-bus-aware linker script (see file header).
CFLAGS_C = -march=rv32i -mabi=ilp32 \
           -nostartfiles -specs=nano.specs \
           -Os -ffunction-sections -fdata-sections \
           -Wl,--gc-sections \
           -T $(SW_DIR)/c_link.ld

# Use the objcopy/size that ship with RISCV_GCC so we don't mismatch versions.
RISCV_BINDIR = $(dir $(RISCV_GCC))
RISCV_OBJCOPY = $(RISCV_BINDIR)riscv32-unknown-elf-objcopy
RISCV_SIZE    = $(RISCV_BINDIR)riscv32-unknown-elf-size

c: $(SW_DIR)/$(PROG).c $(SW_DIR)/crt0.S $(SW_DIR)/syscalls.c $(SW_DIR)/c_link.ld
	@mkdir -p $(SIM_DIR)
	@if [ "$(RISCV_GCC)" = "TOOLCHAIN_NOT_FOUND" ]; then \
		echo ""; \
		echo "ERROR: no RISC-V gcc with newlib-nano found."; \
		echo ""; \
		echo "  Discovery probed:"; \
		echo "    /opt/riscv/bin/riscv32-unknown-elf-gcc"; \
		echo "    $$HOME/riscv/bin/riscv32-unknown-elf-gcc"; \
		echo "    riscv32-unknown-elf-gcc on PATH"; \
		echo ""; \
		echo "  See docs/toolchain.md for the canonical build procedure."; \
		echo "  Override with: make c PROG=$(PROG) RISCV_GCC=/path/to/riscv32-unknown-elf-gcc"; \
		echo ""; \
		exit 1; \
	fi
	@echo "Using RISCV_GCC = $(RISCV_GCC)"
	$(RISCV_GCC) $(CFLAGS_C) \
		-o $(SIM_DIR)/$(PROG).elf \
		$(SW_DIR)/crt0.S $(SW_DIR)/$(PROG).c $(SW_DIR)/syscalls.c
	# Extract IMEM (.text + .text.init) → word-addressed hex.
	$(RISCV_OBJCOPY) -O verilog \
		--only-section=.text \
		$(SIM_DIR)/$(PROG).elf $(SIM_DIR)/$(PROG)_text.byte.hex
	python3 $(SIM_DIR)/make_imem_hex.py \
		$(SIM_DIR)/$(PROG)_text.byte.hex $(SIM_DIR)/$(PROG).hex
	# Extract DMEM (.rodata + .data), shift addresses from 0x00010000 → 0,
	# then convert to word-addressed hex.
	$(RISCV_OBJCOPY) -O verilog \
		--only-section=.rodata --only-section=.data \
		--change-section-address .rodata-0x00010000 \
		--change-section-address .data-0x00010000 \
		$(SIM_DIR)/$(PROG).elf $(SIM_DIR)/$(PROG)_dmem.byte.hex
	python3 $(SIM_DIR)/make_dmem_hex.py \
		$(SIM_DIR)/$(PROG)_dmem.byte.hex $(SIM_DIR)/$(PROG)_dmem.hex
	@rm -f $(SIM_DIR)/$(PROG)_text.byte.hex $(SIM_DIR)/$(PROG)_dmem.byte.hex
	@echo ""
	@echo "---- ELF section sizes ($(PROG).elf) ----"
	@$(RISCV_SIZE) $(SIM_DIR)/$(PROG).elf

# ---- Cleanup ----

clean:
	rm -rf $(SIM_DIR)/*.vvp $(SIM_DIR)/*.vcd $(SIM_DIR)/*.o $(SIM_DIR)/*.elf $(SIM_DIR)/*.hex

.PHONY: sim sim-top sim-fpga sim-fpga-c wave asm c clean
