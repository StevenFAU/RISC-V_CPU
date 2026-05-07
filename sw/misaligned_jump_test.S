# misaligned_jump_test.S — Phase 1.2.1 end-to-end inst_addr_misaligned demo.
#
# Exercises three decision points for the inst_addr_misaligned cause
# source. Without MRET (1.2.3) we can only fire one trap per program;
# the inline must-NOT-trap cases run before the trap-trigger and rely
# on PC progression for verification:
#
#   1. JALR with imm[0]=1 (masked away by spec & ~1) -> aligned target
#      -> must NOT trap. JALR completes and writes pc_plus4 to rd.
#
#   2. BEQ NOT-taken with misaligned imm[1]=1 -> branch_taken=0 ->
#      misalignment detection condition is gated off -> must NOT trap.
#      Encoded as raw .word because GAS won't emit a B-imm with bit 1
#      set against a word-aligned label.
#
#   3. JAL with misaligned imm[1]=1 -> trap fires. Encoded as raw
#      .word for the same reason. Handler verifies mepc/mcause/mtval.
#
# If (1) or (2) accidentally trapped, mepc would point to their PCs
# instead of the JAL's PC and the handler would route to FAIL. The
# tb_rv32i_core_csr.v directed tests cover the full taken-BEQ /
# JALR-target[1]=1 trap variants with cycle-precision checks.

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

    # =========================================================================
    # Case 1 — JALR with imm[0]=1 (masked) -> must NOT trap
    # =========================================================================
    # target = (jalr_landing + 1) & ~1 = jalr_landing (aligned).
    # If the bit-0 mask were not applied before misalignment detection,
    # this would falsely flag misalignment and trap.
    la      t0, jalr_landing
    jalr    t1, 1(t0)

    # If JALR fell through (no trap), PC arrives at jalr_landing.
jalr_landing:

    # =========================================================================
    # Case 2 — BEQ NOT-taken with misaligned imm[1]=1 -> must NOT trap
    # =========================================================================
    # t2 != t3, so the branch is not taken; misaligned target is never
    # fetched. Encoded as `.word`: BEQ t2, t3, +6
    #   rs1=t2(x7), rs2=t3(x28), funct3=000, imm[12:1]=0x003 (offset 6,
    #   imm[0] implicit 0). Encoding: 0x01C38363.
    addi    t2, x0, 5
    addi    t3, x0, 7
    .word   0x01C38363

    # =========================================================================
    # Case 3 — JAL with misaligned imm[1]=1 -> DOES trap
    # =========================================================================
    # Capture the trapping-instruction address; handler checks mepc.
    la      s1, jal_pc

jal_pc:
    # JAL x0, +6 (offset 6 from this PC, target = jal_pc + 6, misaligned).
    # Encoded as `.word`: rd=x0, imm[20:1] for offset 6.
    #   Encoding: 0x0060006F.
    .word   0x0060006F

    # Unreached if the trap path works.
    j       fail

# =============================================================================
# Handler — verify the JAL's trap state, then print PASS or FAIL.
# =============================================================================
handler:
    # ---- mepc == jal_pc ----
    csrrs   t1, mepc, x0
    bne     t1, s1, fail

    # ---- mcause == 0 (inst_addr_misaligned) ----
    csrrs   t1, mcause, x0
    bnez    t1, fail

    # ---- mtval == jal_pc + 6 (misaligned target) ----
    csrrs   t1, mtval, x0
    addi    t2, s1, 6
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
