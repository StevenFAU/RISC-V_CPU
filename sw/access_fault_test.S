# access_fault_test.S — Phase 1.2.2 end-to-end load_access_fault demo.
#
# Triggers cause 5 (load_access_fault) by issuing an aligned LW to an
# unmapped address (0xF0000000, which falls outside every wb_interconnect
# slave window). The bus auto-acks with rdata=0 and bus_error_o pulses
# combinationally; the at-issue trap path catches the error before
# regfile_we / instret_tick can latch.
#
# Without MRET (1.2.3) only one trap can be tested per program; the
# tb_rv32i_core_csr.v directed tests cover the store_access_fault
# (cause 7) and the misaligned-LW-to-unmapped mutual-exclusion case.
#
# Expected after the LW trap:
#   mepc          == LW instruction address
#   mcause        == 5 (load_access_fault)
#   mtval         == 0xF0000000 (the unmapped address)
#   x rd unchanged (regfile_we gate prevents the would-be load)
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

    # ---- Set mstatus.MIE=1 ----
    addi    t0, x0, 0x008
    csrrw   x0, mstatus, t0

    # ---- Pre-load t4 with a sentinel; the regfile_we gate must
    #      preserve it through the trap. ----
    li      t4, 0xDEADBEEF

    # ---- Capture the trapping-instruction address ----
    la      s1, lf_pc

    # ---- Unmapped address: 0xF0000000 ----
    lui     s2, 0xF0000              # s2 = 0xF0000000

    # ---- Trigger: LW from unmapped addr -> cause 5 ----
lf_pc:
    lw      t4, 0(s2)

    # If we reach here, the trap path failed.
    j       fail

# =============================================================================
# Handler — verify trap state + sentinel, then print PASS / FAIL.
# =============================================================================
handler:
    # ---- mepc == lf_pc ----
    csrrs   t1, mepc, x0
    bne     t1, s1, fail

    # ---- mcause == 5 ----
    csrrs   t1, mcause, x0
    addi    t2, x0, 5
    bne     t1, t2, fail

    # ---- mtval == 0xF0000000 ----
    csrrs   t1, mtval, x0
    bne     t1, s2, fail

    # ---- t4 sentinel preserved (regfile_we gate proven on at-issue path) ----
    li      t2, 0xDEADBEEF
    bne     t4, t2, fail

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
