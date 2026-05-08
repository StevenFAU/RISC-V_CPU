# mret_test.S — Phase 1.2.3 end-to-end MRET demo.
#
# Minimal "MRET in M-mode redirects PC to mepc and rotates mstatus"
# test outside any prior trap context. Sets mtvec to a fail handler
# (so any spurious trap takes us to FAIL), sets mepc to the post-MRET
# resume target, prearms mstatus (MIE=0, MPIE=1) so the rotation is
# observable, then executes MRET. The resume target verifies the
# rotated mstatus and prints "PASS\r\n" over memory-mapped UART.
#
# Memory map (matches sw/link.ld):
#   IMEM     0x00000000  (this code lives here)
#   DMEM     0x00010000  (PASS/FAIL strings live here, .data section)
#   UART TX  0x80000000  (data register)
#   UART TX  0x80000004  (status: bit 0 = busy)
#
# Architectural state expectations after MRET:
#   PC            == mret_target (the address we wrote into mepc)
#   mstatus.MIE   == 1   (rotated from old MPIE=1)
#   mstatus.MPIE  == 1   (set to 1 per spec on MRET)

.text
.globl _start

_start:
    # ---- UART base in a0 ----
    lui     a0, 0x80000              # a0 = 0x80000000

    # ---- Set mtvec to the trap_handler (fail path: any spurious trap is a bug) ----
    la      t0, trap_handler
    csrrw   x0, mtvec, t0

    # ---- Set mepc to the MRET resume target ----
    la      t0, mret_target
    csrrw   x0, mepc, t0

    # ---- Prearm mstatus: MIE=0 (bit 3), MPIE=1 (bit 7) -> 0x080 ----
    addi    t0, x0, 0x080
    csrrw   x0, mstatus, t0

    # ---- Execute MRET. PC -> mepc; mstatus.MIE <- old MPIE; MPIE <- 1. ----
    mret

    # If MRET fell through, the redirect is broken.
    j       fail

# =============================================================================
# MRET resume target — verify mstatus rotation, then print PASS.
# =============================================================================
mret_target:
    # ---- Check mstatus.MIE == 1 (rotated from old MPIE=1) ----
    csrrs   t1, mstatus, x0
    andi    t2, t1, 0x008
    addi    t3, x0, 0x008
    bne     t2, t3, fail

    # ---- Check mstatus.MPIE == 1 (set to 1 per spec on MRET) ----
    andi    t2, t1, 0x080
    addi    t3, x0, 0x080
    bne     t2, t3, fail

pass:
    lui     a1, 0x10                 # a1 = 0x00010000 -> pass_str
    j       print_loop

fail:
    lui     a1, 0x10
    addi    a1, a1, 8                # +8 -> fail_str
    j       print_loop

# =============================================================================
# Trap handler — any trap reaching here is a bug. Falls through to FAIL.
# =============================================================================
trap_handler:
    j       fail

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
