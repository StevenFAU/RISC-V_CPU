# illegal_test.S — Phase 1.2.1 end-to-end illegal-instruction trap demo
#                  + observable regfile_we gate (sentinel register).
#
# Triggers an illegal-instruction trap by attempting CSRRW to a RO CSR
# (mvendorid). This is the only path in the current core where
# illegal_inst_o pulses while the decoder also asserts reg_write=1
# (since is_csr=1 for SYSTEM funct3 != 0). The 1.2.0 regfile_we gate
# (`reg_write & ~trap_enter_w`) is therefore observable here: without
# the gate, the trap cycle would clobber rd with the (zero-valued) RO
# read; with the gate, rd is preserved at its pre-trap sentinel.
#
# Note on "illegal opcode" vs "illegal instruction": the 1.2.1 handoff
# language preferred a true unknown opcode for this test, but
# control.v's default branch keeps reg_write=0 for unrecognized
# opcodes, so a true unknown-opcode trigger would not exercise the
# regfile_we gate observably. The CSR-illegal path used here still
# asserts the same architectural cause (cause = 2, illegal_instruction)
# and exercises the same RTL gate (regfile.we line in rv32i_core.v).
#
# Expected after the CSRRW trap:
#   mepc          == address of the trapping CSRRW instruction
#   mcause        == 2 (illegal instruction)
#   mtval         == the encoded 32-bit instruction word
#                    csrrw t4, mvendorid, t0 = 0xF1129EF3
#   t4 (sentinel) == 0xDEADBEEF (unchanged by the gated regfile write)
#   mstatus.MIE   == 0 (was 1 going in -> cleared by trap entry)
#   mstatus.MPIE  == 1 (captures pre-trap MIE)

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

    # ---- Pre-load t4 with the sentinel value the gate must preserve ----
    li      t4, 0xDEADBEEF

    # ---- Source operand for the RO write (any non-zero value) ----
    addi    t0, x0, 1

    # ---- Capture the trapping-instruction address ----
    la      s1, illegal_pc

    # ---- Trigger the trap: CSRRW to RO mvendorid with non-zero rs1.
    #      csr_illegal_i pulses; trap_enter_w fires; the regfile_we gate
    #      blocks the would-be write to t4 (rd). t4 must survive at the
    #      sentinel value. ----
illegal_pc:
    csrrw   t4, mvendorid, t0

    # If we get here, the trap path failed.
    j       fail

# =============================================================================
# Handler — verify trap state + sentinel preservation, then print PASS/FAIL.
# =============================================================================
handler:
    # ---- mepc == illegal_pc ----
    csrrs   t1, mepc, x0
    bne     t1, s1, fail

    # ---- mcause == 2 ----
    csrrs   t1, mcause, x0
    addi    t2, x0, 2
    bne     t1, t2, fail

    # ---- mtval == encoded csrrw t4, mvendorid, t0 = 0xF1129EF3 ----
    csrrs   t1, mtval, x0
    li      t2, 0xF1129EF3
    bne     t1, t2, fail

    # ---- t4 sentinel preserved (this is the regfile_we gate proof) ----
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
