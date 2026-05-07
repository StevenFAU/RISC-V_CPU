# misaligned_load_test.S — Phase 1.2.2 end-to-end load_addr_misaligned demo.
#
# Triggers cause 4 (load_addr_misaligned) via LH at an odd half-word
# address inside the DMEM region. The trap fires on the LH cycle; the
# pre-issue gate suppresses dmem_re so the bus never sees the bad
# address. Handler verifies mepc / mcause / mtval / MIE-MPIE and prints
# "PASS\r\n" over UART.
#
# Without MRET (1.2.3) only one trap can be tested per program; the
# tb_rv32i_core_csr.v directed tests cover LW addr[1:0]=01/10/11
# variants with cycle-precision checks.
#
# Expected after the LH trap:
#   mepc          == address of the LH instruction
#   mcause        == 4 (load_addr_misaligned)
#   mtval         == 0x00010001 (the misaligned address)
#   mstatus.MIE   == 0 (was 1 going in)
#   mstatus.MPIE  == 1

.text
.globl _start

_start:
    # ---- UART base in a0 ----
    lui     a0, 0x80000              # a0 = 0x80000000

    # ---- Set mtvec to handler entry ----
    la      t0, handler
    csrrw   x0, mtvec, t0

    # ---- Set mstatus.MIE=1 (bit 3) ----
    addi    t0, x0, 0x008
    csrrw   x0, mstatus, t0

    # ---- Capture the trapping-instruction address ----
    la      s1, ld_pc

    # ---- Misaligned address: DMEM base + 1 (half-word odd) ----
    lui     s2, 0x10                 # s2 = 0x00010000
    addi    s2, s2, 1                # s2 = 0x00010001

    # ---- Trigger: LH at odd half-word -> cause 4 ----
ld_pc:
    lh      t1, 0(s2)

    # If we reach here, the trap path failed.
    j       fail

# =============================================================================
# Handler — verify trap state, then print PASS / FAIL.
# =============================================================================
handler:
    # ---- mepc == ld_pc ----
    csrrs   t1, mepc, x0
    bne     t1, s1, fail

    # ---- mcause == 4 ----
    csrrs   t1, mcause, x0
    addi    t2, x0, 4
    bne     t1, t2, fail

    # ---- mtval == 0x00010001 ----
    csrrs   t1, mtval, x0
    bne     t1, s2, fail

    # ---- mstatus.MIE == 0 ----
    csrrs   t1, mstatus, x0
    andi    t2, t1, 0x008
    bnez    t2, fail

    # ---- mstatus.MPIE == 1 ----
    andi    t2, t1, 0x080
    addi    t3, x0, 0x080
    bne     t2, t3, fail

pass:
    lui     a1, 0x10                 # -> pass_str
    j       print_loop

fail:
    lui     a1, 0x10
    addi    a1, a1, 8                # -> fail_str

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
