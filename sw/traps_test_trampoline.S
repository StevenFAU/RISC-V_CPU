/*
 * traps_test_trampoline.S — asm stub at mtvec for sw/traps_test.c.
 *
 * Standard RISC-V bare-metal trap trampoline:
 *   1. Save caller-saved (t0-t6, a0-a7, ra) to the trapped program's
 *      stack. Callee-saved registers (s0-s11, sp, gp, tp) are preserved
 *      by trap_dispatcher's normal ABI compliance.
 *   2. Call trap_dispatcher (C function in traps_test.c).
 *   3. Restore caller-saved registers.
 *   4. mret — restores PC from mepc and rotates mstatus.
 *
 * Word-aligned via .balign 4 so its address satisfies mtvec's BASE
 * alignment (mtvec.MODE is hardwired to 0 in csr_file; direct mode).
 *
 * The trampoline runs in M-mode and uses the trapped program's sp.
 * traps_test.c never traps from a context with sp invalid (crt0 sets
 * sp before calling main; main doesn't perturb sp), so this is safe.
 */

.option arch, +zicsr

    .section .text, "ax"
    .balign 4
    .globl trap_trampoline
    .type  trap_trampoline, @function

trap_trampoline:
    addi sp, sp, -64
    sw   ra,  0(sp)
    sw   t0,  4(sp)
    sw   t1,  8(sp)
    sw   t2, 12(sp)
    sw   a0, 16(sp)
    sw   a1, 20(sp)
    sw   a2, 24(sp)
    sw   a3, 28(sp)
    sw   a4, 32(sp)
    sw   a5, 36(sp)
    sw   a6, 40(sp)
    sw   a7, 44(sp)
    sw   t3, 48(sp)
    sw   t4, 52(sp)
    sw   t5, 56(sp)
    sw   t6, 60(sp)

    call trap_dispatcher

    lw   ra,  0(sp)
    lw   t0,  4(sp)
    lw   t1,  8(sp)
    lw   t2, 12(sp)
    lw   a0, 16(sp)
    lw   a1, 20(sp)
    lw   a2, 24(sp)
    lw   a3, 28(sp)
    lw   a4, 32(sp)
    lw   a5, 36(sp)
    lw   a6, 40(sp)
    lw   a7, 44(sp)
    lw   t3, 48(sp)
    lw   t4, 52(sp)
    lw   t5, 56(sp)
    lw   t6, 60(sp)
    addi sp, sp, 64

    mret

    .size trap_trampoline, . - trap_trampoline
