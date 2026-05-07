# ebreak_test.S — Phase 1.2.1 end-to-end EBREAK trap-entry demo.
#
# Mirrors sw/ecall_test.S structure: sets mtvec to a handler within
# this same .text section, sets mstatus.MIE=1 to exercise the
# MIE -> MPIE rotation, executes EBREAK, and verifies mepc / mcause /
# mstatus.MIE / mstatus.MPIE / mtval inside the handler. Prints
# "PASS\r\n" or "FAIL\r\n" over memory-mapped UART. Halts at the end
# (does NOT execute MRET — that lands in Phase 1.2.3).
#
# Memory map (matches sw/link.ld):
#   IMEM     0x00000000  (this code lives here)
#   DMEM     0x00010000  (PASS/FAIL strings live here, .data section)
#   UART TX  0x80000000  (data register)
#   UART TX  0x80000004  (status: bit 0 = busy)
#
# Trap state expectations after EBREAK:
#   mepc          == address of the EBREAK instruction (word-aligned)
#   mcause        == 3   (breakpoint)
#   mtval         == 0   (per spec — EBREAK has no tval)
#   mstatus.MIE   == 0   (was 1 going in -> cleared by trap entry)
#   mstatus.MPIE  == 1   (captures pre-trap MIE)

.text
.globl _start

_start:
    # ---- UART base in a0 ----
    lui     a0, 0x80000              # a0 = 0x80000000

    # ---- Set mtvec to handler entry ----
    la      t0, handler
    csrrw   x0, mtvec, t0

    # ---- Set mstatus.MIE=1 (bit 3) so the trap entry has a 1 -> 0 / 0 -> 1
    #      transition to observe ----
    addi    t0, x0, 0x008
    csrrw   x0, mstatus, t0

    # ---- Capture the address of the EBREAK instruction for the mepc check ----
    la      s1, ebreak_pc

    # ---- Trigger the trap ----
ebreak_pc:
    ebreak

    # Trap entry should redirect PC to `handler` before this fall-through
    # can execute. If we ever get here, the trap path failed.
    j       fail

# =============================================================================
# Handler — verify trap state, then print PASS or FAIL.
# Does NOT execute MRET (Phase 1.2.3 lights MRET decode up).
# =============================================================================
handler:
    # ---- Check mepc == address of the EBREAK instruction ----
    csrrs   t1, mepc, x0
    bne     t1, s1, fail

    # ---- Check mcause == 3 (breakpoint) ----
    csrrs   t1, mcause, x0
    addi    t2, x0, 3
    bne     t1, t2, fail

    # ---- Check mtval == 0 (per spec for EBREAK) ----
    csrrs   t1, mtval, x0
    bnez    t1, fail

    # ---- Check mstatus.MIE == 0 (trap entry cleared MIE) ----
    csrrs   t1, mstatus, x0
    andi    t2, t1, 0x008
    bnez    t2, fail

    # ---- Check mstatus.MPIE == 1 (trap entry captured pre-trap MIE=1) ----
    andi    t2, t1, 0x080
    addi    t3, x0, 0x080
    bne     t2, t3, fail

pass:
    lui     a1, 0x10                 # a1 = 0x00010000 -> pass_str
    j       print_loop

fail:
    lui     a1, 0x10
    addi    a1, a1, 8                # +8 -> fail_str

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
