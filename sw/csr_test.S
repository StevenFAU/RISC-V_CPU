# csr_test.S — Phase 1.1 end-to-end CSR integration demo.
#
# Writes a known value (0x12345678) to mscratch via CSRRW, reads it back via
# CSRRS, compares, and prints "PASS\r\n" or "FAIL\r\n" over memory-mapped UART.
# Proves the SYSTEM-opcode + CSR-instruction path works in the synthesized
# memory map (BRAM IMEM, Wishbone DMEM, real UART) — not just the integration
# testbench harness.
#
# Memory map (matches sw/link.ld):
#   IMEM     0x00000000  (this code lives here)
#   DMEM     0x00010000  (PASS/FAIL strings live here, .data section)
#   UART TX  0x80000000  (data register)
#   UART TX  0x80000004  (status: bit 0 = busy)

.text
.globl _start

_start:
    # ---- UART base ----
    lui   a0, 0x80000              # a0 = 0x80000000

    # ---- Build test value 0x12345678 in a4 ----
    lui   a4, 0x12345              # a4 = 0x12345000
    addi  a4, a4, 0x678            # a4 = 0x12345678

    # ---- Phase 1.1 CSR instructions ----
    csrrw x0, mscratch, a4         # mscratch <- a4 (rd=x0; write happens)
    csrrs a5, mscratch, x0         # a5 <- mscratch (rs1=x0; read-only)

    # ---- Compare ----
    bne   a4, a5, fail

pass:
    # a1 -> pass_str at DMEM[0x00010000 + 0]
    lui   a1, 0x10                 # a1 = 0x00010000
    j     print_loop

fail:
    # a1 -> fail_str at DMEM[0x00010000 + 8]
    lui   a1, 0x10
    addi  a1, a1, 8

print_loop:
    lbu   a2, 0(a1)                # load next byte
    beqz  a2, done                 # halt on null terminator
poll_busy:
    lw    a3, 4(a0)                # read UART status
    andi  a3, a3, 1                # isolate busy bit
    bnez  a3, poll_busy            # spin while busy
    sw    a2, 0(a0)                # send byte
    addi  a1, a1, 1                # advance pointer
    j     print_loop

done:
    j     done                     # halt

# -----------------------------------------------------------------------------
# .data — PASS / FAIL strings, 8-byte aligned per slot for clean offsets.
# DMEM word layout (little-endian):
#   word 0 = "PASS"        (0x53534150)
#   word 1 = "\r\n\0\0"    (0x00000A0D)
#   word 2 = "FAIL"        (0x4C494146)
#   word 3 = "\r\n\0\0"    (0x00000A0D)
# -----------------------------------------------------------------------------
.data
.balign 4
.globl pass_str
pass_str:
    .byte 'P', 'A', 'S', 'S'
    .byte '\r', '\n', 0,   0
.globl fail_str
fail_str:
    .byte 'F', 'A', 'I', 'L'
    .byte '\r', '\n', 0,   0
