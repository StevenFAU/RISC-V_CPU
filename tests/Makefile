# RISC-V Compliance Test Build System
RISCV_PREFIX ?= riscv64-unknown-elf-
GCC     = $(RISCV_PREFIX)gcc
OBJCOPY = $(RISCV_PREFIX)objcopy
OBJDUMP = $(RISCV_PREFIX)objdump

IVERILOG = iverilog
VVP      = vvp

BUILD_DIR = build
RTL_DIR   = ../rtl
TB_DIR    = ../tb

# All rv32ui tests (excluding fence_i which requires I-cache, and ld_st which is RV64)
RV32UI_TESTS = add addi and andi auipc \
               beq bge bgeu blt bltu bne \
               jal jalr \
               lb lbu lh lhu lw \
               lui \
               or ori \
               sb sh sw \
               sll slli \
               slt slti sltiu sltu \
               sra srai \
               srl srli \
               sub \
               xor xori

# Compilation flags
CFLAGS = -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles \
         -T link.ld \
         -I env/custom \
         -I isa/macros/scalar

# RTL sources for compliance testbench (no imem.v/dmem.v — memory is in testbench)
RTL_SRCS = $(RTL_DIR)/defines.v $(RTL_DIR)/pc.v $(RTL_DIR)/regfile.v \
           $(RTL_DIR)/immgen.v $(RTL_DIR)/control.v $(RTL_DIR)/alu_decoder.v \
           $(RTL_DIR)/alu.v $(RTL_DIR)/rv32i_core.v

# Compile testbench (once)
$(BUILD_DIR)/tb_compliance.vvp: $(TB_DIR)/tb_compliance.v $(RTL_SRCS)
	@mkdir -p $(BUILD_DIR)
	$(IVERILOG) -o $@ -I $(RTL_DIR) $(RTL_SRCS) $(TB_DIR)/tb_compliance.v

# Compile a single test: make test TEST=add
test: $(BUILD_DIR)/$(TEST).hex

$(BUILD_DIR)/%.elf: isa/rv32ui/%.S
	@mkdir -p $(BUILD_DIR)
	$(GCC) $(CFLAGS) -o $@ $<

$(BUILD_DIR)/%.hex: $(BUILD_DIR)/%.elf
	$(OBJCOPY) -O verilog $< $@

$(BUILD_DIR)/%.dump: $(BUILD_DIR)/%.elf
	$(OBJDUMP) -d $< > $@

# Run a single test: make run TEST=add
run: $(BUILD_DIR)/tb_compliance.vvp $(BUILD_DIR)/$(TEST).hex
	$(VVP) $(BUILD_DIR)/tb_compliance.vvp +firmware=$(BUILD_DIR)/$(TEST).hex

# Compile all tests
test-all: $(patsubst %,$(BUILD_DIR)/%.hex,$(RV32UI_TESTS))

# Run all tests and report results
run-all: $(BUILD_DIR)/tb_compliance.vvp test-all
	@echo "================================================================"
	@echo "RV32UI Compliance Test Results"
	@echo "================================================================"
	@pass=0; fail=0; timeout=0; total=0; \
	for test in $(RV32UI_TESTS); do \
		total=$$((total + 1)); \
		result=$$($(VVP) $(BUILD_DIR)/tb_compliance.vvp +firmware=$(BUILD_DIR)/$$test.hex 2>&1 | grep -E "PASS|FAIL|TIMEOUT"); \
		if echo "$$result" | grep -q "^PASS"; then \
			status="PASS"; pass=$$((pass + 1)); \
		elif echo "$$result" | grep -q "^FAIL"; then \
			status="FAIL"; fail=$$((fail + 1)); \
		else \
			status="TIMEOUT"; timeout=$$((timeout + 1)); \
		fi; \
		printf "  %-12s %s\n" "$$test" "$$result"; \
	done; \
	echo "================================================================"; \
	echo "Total: $$total  Pass: $$pass  Fail: $$fail  Timeout: $$timeout"; \
	echo "================================================================"

# Dump disassembly for a test: make dump TEST=add
dump: $(BUILD_DIR)/$(TEST).dump
	@cat $<

clean:
	rm -rf $(BUILD_DIR)

.PHONY: test test-all run run-all dump clean
