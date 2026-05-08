# ecall_mret_roundtrip_test.S — Phase 1.2.3 architectural milestone.
#
# End-to-end ECALL -> handler -> MRET -> resume round-trip. Sets up
# mtvec, sets mstatus.MIE=1, fires ECALL. The handler reads mepc,
# advances it past the ECALL (mepc + 4), writes it back, and executes
# MRET. The resumed program executes the instruction immediately after
# the ECALL — that is the "PASS" print path.
#
# Memory map (matches sw/link.ld):
#   IMEM     0x00000000  (this code lives here)
#   DMEM     0x00010000  (PASS/FAIL strings live here, .data section)
#   UART TX  0x80000000  (data register)
#   UART TX  0x80000004  (status: bit 0 = busy)
#
# Round-trip state expectations:
#   ECALL takes the trap (mepc captures ECALL PC; mcause=11; MIE rotates).
#   Handler computes mepc + 4 and writes it back.
#   MRET redirects PC to mepc + 4 (instruction immediately after ECALL).
#   mstatus.MIE rotates back to 1 (from MPIE captured on trap entry).
#   The resumed program prints "PASS\r\n" — proves the handler actually
#   executed AND the round-trip resumed at the correct address.

.text
.globl _start

_start:
    # ---- UART base in a0 ----
    lui     a0, 0x80000              # a0 = 0x80000000

    # ---- Set mtvec to the handler ----
    la      t0, handler
    csrrw   x0, mtvec, t0

    # ---- Set mstatus.MIE=1 (bit 3) so MIE/MPIE rotate observably ----
    addi    t0, x0, 0x008
    csrrw   x0, mstatus, t0

    # ---- Trigger the trap. After MRET, execution resumes at the
    #      instruction immediately following this ECALL. ----
ecall_pc:
    ecall

# =============================================================================
# Post-ECALL resume target. The handler advances mepc by 4 and MRETs;
# control returns here. Print PASS.
# =============================================================================
post_ecall:
    lui     a1, 0x10                 # a1 = 0x00010000 -> pass_str
    j       print_loop

# =============================================================================
# Handler — advance mepc past the ECALL instruction (4 bytes), then MRET.
# A failed return path (e.g., MRET broken, mepc rewrite broken) falls
# through to FAIL.
# =============================================================================
handler:
    csrrs   t1, mepc, x0             # t1 = mepc (= address of ECALL)
    addi    t1, t1, 4                # advance past the 4-byte ECALL
    csrrw   x0, mepc, t1             # mepc = mepc + 4
    mret                             # return to instruction after ECALL

    # MRET should not fall through; if it does, print FAIL.
    j       fail

fail:
    lui     a1, 0x10
    addi    a1, a1, 8                # +8 -> fail_str
    j       print_loop

print_loop:
    lbu     a2, 0(a1)
    beqz    a2, done
poll_busy:
    lw      a3, 4(a0)
    andi    a3, a3, 1
    bnez    a3, poll_busy
    sw      a2, 0(a0)
    addi    a1, a1, 1
    j       print_loop

done:
    j       done

# =============================================================================
# .data — PASS / FAIL strings, layout matches the testbench's preload:
#   word 0 = "PASS"        (0x53534150)
#   word 1 = "\r\n\0\0"    (0x00000A0D)
#   word 2 = "FAIL"        (0x4C494146)
#   word 3 = "\r\n\0\0"    (0x00000A0D)
# =============================================================================
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
