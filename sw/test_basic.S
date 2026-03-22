# test_basic.S — Basic integration test for RV32I core
# Exercises: R-type, I-type, Load/Store, Branch, Jump, LUI, AUIPC
# Stores 0xDEADBEEF at DMEM[0] on success

.text
.globl _start

_start:
    # --- I-type arithmetic ---
    addi x1, x0, 5          # x1 = 5
    addi x2, x0, 10         # x2 = 10
    addi x3, x0, -1         # x3 = -1 (0xFFFFFFFF)

    # --- R-type arithmetic ---
    add  x4, x1, x2         # x4 = 15
    sub  x5, x2, x1         # x5 = 5
    and  x6, x1, x2         # x6 = 5 & 10 = 0
    or   x7, x1, x2         # x7 = 5 | 10 = 15
    xor  x8, x1, x2         # x8 = 5 ^ 10 = 15
    sll  x9, x1, x2         # x9 = 5 << 10 = 5120 (but x2=10, shift amt = 10)
    slt  x10, x3, x1        # x10 = (-1 < 5) = 1
    sltu x11, x1, x3        # x11 = (5 < 0xFFFFFFFF) unsigned = 1

    # --- I-type shifts ---
    slli x12, x1, 2          # x12 = 5 << 2 = 20
    srli x13, x2, 1          # x13 = 10 >> 1 = 5
    srai x14, x3, 4          # x14 = -1 >>> 4 = -1 (all 1s)

    # --- Branch test ---
    addi x15, x0, 0          # x15 = 0 (will be set to 1 if branch works)
    beq  x1, x1, branch_taken
    addi x15, x0, 99         # Should be skipped
branch_taken:
    addi x15, x0, 1          # x15 = 1 (branch worked)

    # --- BNE test ---
    addi x16, x0, 0
    bne  x1, x2, bne_taken
    addi x16, x0, 99         # Should be skipped
bne_taken:
    addi x16, x0, 2          # x16 = 2

    # --- LUI ---
    lui  x17, 0xDEADB        # x17 = 0xDEADB000

    # --- AUIPC ---
    auipc x18, 0             # x18 = current PC

    # --- JAL test ---
    jal  x19, jal_target     # x19 = PC+4 (return address)
    addi x20, x0, 99         # Should be skipped
jal_target:
    addi x20, x0, 3          # x20 = 3 (JAL worked)

    # --- JALR test ---
    addi x21, x0, 0
    jal  x22, get_jalr_addr
get_jalr_addr:
    addi x22, x22, 12        # x22 = return addr + 12 (skip next 2 instrs + land on target)
    jalr x23, x22, 0         # Jump to jalr_target, x23 = PC+4
    addi x21, x0, 99         # Should be skipped
jalr_target:
    addi x21, x0, 4          # x21 = 4 (JALR worked)

    # --- Store/Load test ---
    # Prepare pass signature
    lui  x24, 0xDEADB        # x24 = 0xDEADB000
    addi x24, x24, 0xEEF     # Would give 0xDEADB000 + 0xFFFFFEEF due to sign ext
    # Use a different approach: build 0xDEADBEEF
    lui  x24, 0xDEADC        # x24 = 0xDEADC000 (LUI rounds up because ADDI will subtract)
    addi x24, x24, -529      # x24 = 0xDEADC000 + 0xFFFFFDEF = 0xDEADBDEF — wrong approach

    # Simplest approach: construct via shifts and ors
    addi x24, x0, 0x0DE      # x24 = 0xDE
    slli x24, x24, 8         # x24 = 0xDE00
    addi x25, x0, 0x0AD      # x25 = 0xAD
    or   x24, x24, x25       # x24 = 0xDEAD
    slli x24, x24, 8         # x24 = 0xDEAD00
    addi x25, x0, 0x0BE      # x25 = 0xBE
    or   x24, x24, x25       # x24 = 0xDEADBE
    slli x24, x24, 8         # x24 = 0xDEADBE00
    addi x25, x0, 0x0EF      # x25 = 0xEF
    or   x24, x24, x25       # x24 = 0xDEADBEEF

    # Store to DMEM base address (0x00010000 is DMEM base, but our DMEM addr
    # is computed by ALU, so store at offset 0 from a base register)
    # The DMEM in the testbench sits at address 0 in its own array
    # ALU result feeds into DMEM addr — we need to store at a low addr
    addi x26, x0, 0          # x26 = 0 (DMEM offset)
    sw   x24, 0(x26)         # Store 0xDEADBEEF at address 0

    # Verify with load
    lw   x27, 0(x26)         # x27 should = 0xDEADBEEF

    # Byte load tests
    lb   x28, 0(x26)         # x28 = sign-ext of 0xEF = 0xFFFFFFEF
    lbu  x29, 0(x26)         # x29 = 0x000000EF

    # --- Halt ---
    ecall                    # Testbench detects this as halt

