# misaligned_store_test.S — Phase 1.2.2 end-to-end store_addr_misaligned
#                            demo + observable dmem_we gate.
#
# Pre-stores a known sentinel (0xCAFEBABE) to an aligned DMEM location
# via a legal SW. Then attempts an SH to an odd half-word address: the
# pre-issue gate must suppress dmem_we, so the would-be store does NOT
# reach the bus and the sentinel survives. Trap cause = 6
# (store_addr_misaligned).
#
# Handler verifies trap state AND reads back the aligned location to
# confirm sentinel preservation — observable proof that dmem_we was
# gated. If the gate were broken, the misaligned SH would land its
# lower 16 bits in tb_dmem at the same word index and the readback
# would show 0xCAFE_xxxx (not 0xCAFEBABE), routing the handler to FAIL.
#
# Expected after the SH trap:
#   mepc           == SH instruction address
#   mcause         == 6
#   mtval          == 0x00010025 (the misaligned address)
#   *(0x00010024)  == 0xCAFEBABE (sentinel preserved)

.text
.globl _start

_start:
    # ---- UART base in a0 ----
    lui     a0, 0x80000              # a0 = 0x80000000

    # ---- Set mtvec to handler entry ----
    la      t0, handler
    csrrw   x0, mtvec, t0

    # ---- Set mstatus.MIE=1 ----
    addi    t0, x0, 0x008
    csrrw   x0, mstatus, t0

    # ---- DMEM aligned location for sentinel: 0x00010024 ----
    lui     s3, 0x10
    addi    s3, s3, 0x24             # s3 = 0x00010024 (aligned)

    # ---- Pre-store sentinel 0xCAFEBABE via legal SW ----
    li      t0, 0xCAFEBABE
    sw      t0, 0(s3)                # *(0x10024) = 0xCAFEBABE

    # ---- Capture the trapping-instruction address ----
    la      s1, st_pc

    # ---- Misaligned half-word address: 0x00010025 (odd) ----
    addi    s2, s3, 1                # s2 = 0x00010025

    # ---- Would-be data: 0x1234. If gate broken, lower halfword
    #      lands in *(s3) and corrupts sentinel.
    li      t1, 0x1234

    # ---- Trigger: SH at odd half-word -> cause 6 ----
st_pc:
    sh      t1, 0(s2)

    # If we reach here, the trap path failed.
    j       fail

# =============================================================================
# Handler — verify trap state + sentinel preservation, then print PASS / FAIL.
# =============================================================================
handler:
    # ---- mepc == st_pc ----
    csrrs   t1, mepc, x0
    bne     t1, s1, fail

    # ---- mcause == 6 ----
    csrrs   t1, mcause, x0
    addi    t2, x0, 6
    bne     t1, t2, fail

    # ---- mtval == 0x00010025 ----
    csrrs   t1, mtval, x0
    bne     t1, s2, fail

    # ---- Sentinel preservation: read back aligned location ----
    lw      t1, 0(s3)
    li      t2, 0xCAFEBABE
    bne     t1, t2, fail

    # ---- mstatus.MIE == 0 ----
    csrrs   t1, mstatus, x0
    andi    t2, t1, 0x008
    bnez    t2, fail

    # ---- mstatus.MPIE == 1 ----
    andi    t2, t1, 0x080
    addi    t3, x0, 0x080
    bne     t2, t3, fail

pass:
    lui     a1, 0x10
    j       print_loop

fail:
    lui     a1, 0x10
    addi    a1, a1, 8

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
