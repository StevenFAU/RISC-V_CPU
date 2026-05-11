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

# All rv32mi tests (Phase 1.2.5)
RV32MI_TESTS = breakpoint csr illegal instret_overflow \
               lh-misaligned lw-misaligned ma_addr ma_fetch \
               mcsr pmpaddr sbreak scall shamt \
               sh-misaligned sw-misaligned zicntr

# rv32ui compilation flags
CFLAGS = -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles \
         -T link.ld \
         -I env/custom \
         -I isa/macros/scalar

# rv32mi compilation flags. -march=rv32i_zicsr (vs rv32i for rv32ui)
# is required because rv32mi sources use CSR instructions explicitly.
# env/rv32mi_p is the project-forked M-mode env (Phase 1.2.5 Step 3).
MI_CFLAGS = -march=rv32i_zicsr -mabi=ilp32 -nostdlib -nostartfiles \
            -T env/rv32mi_p/link.ld \
            -I env/rv32mi_p \
            -I isa/macros/scalar

# RTL sources for compliance testbench (no imem.v/dmem.v — memory is in testbench)
# Phase 1.2.5: csr_file.v added — tb_compliance now instantiates the CSR file
# alongside rv32i_core so trap-taking rv32mi tests can be hosted.
RTL_SRCS = $(RTL_DIR)/defines.v $(RTL_DIR)/pc.v $(RTL_DIR)/regfile.v \
           $(RTL_DIR)/immgen.v $(RTL_DIR)/control.v $(RTL_DIR)/alu_decoder.v \
           $(RTL_DIR)/alu.v $(RTL_DIR)/csr_file.v $(RTL_DIR)/rv32i_core.v

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

# rv32mi build rules. Prefix rv32mi_ keeps these distinct from the
# rv32ui pattern rule above so they cannot collide on test names.
$(BUILD_DIR)/rv32mi_%.elf: isa/rv32mi/%.S
	@mkdir -p $(BUILD_DIR)
	$(GCC) $(MI_CFLAGS) -o $@ $<

# Compile all rv32mi tests
test-rv32mi-all: $(patsubst %,$(BUILD_DIR)/rv32mi_%.hex,$(RV32MI_TESTS))

# Run a single rv32mi test: make run-rv32mi TEST=csr
run-rv32mi-one: $(BUILD_DIR)/tb_compliance.vvp $(BUILD_DIR)/rv32mi_$(TEST).hex
	$(VVP) $(BUILD_DIR)/tb_compliance.vvp +firmware=$(BUILD_DIR)/rv32mi_$(TEST).hex

# Run all rv32mi tests and report results (mirror of run-all for rv32ui)
run-rv32mi: $(BUILD_DIR)/tb_compliance.vvp test-rv32mi-all
	@echo "================================================================"
	@echo "RV32MI Compliance Test Results"
	@echo "================================================================"
	@pass=0; fail=0; timeout=0; total=0; \
	for test in $(RV32MI_TESTS); do \
		total=$$((total + 1)); \
		result=$$($(VVP) $(BUILD_DIR)/tb_compliance.vvp +firmware=$(BUILD_DIR)/rv32mi_$$test.hex 2>&1 | grep -E "PASS|FAIL|TIMEOUT"); \
		if echo "$$result" | grep -q "^PASS"; then \
			status="PASS"; pass=$$((pass + 1)); \
		elif echo "$$result" | grep -q "^FAIL"; then \
			status="FAIL"; fail=$$((fail + 1)); \
		else \
			status="TIMEOUT"; timeout=$$((timeout + 1)); \
		fi; \
		printf "  %-18s %s\n" "$$test" "$$result"; \
	done; \
	echo "================================================================"; \
	echo "Total: $$total  Pass: $$pass  Fail: $$fail  Timeout: $$timeout"; \
	echo "================================================================"

clean:
	rm -rf $(BUILD_DIR)

.PHONY: test test-all run run-all dump test-rv32mi-all run-rv32mi run-rv32mi-one clean
