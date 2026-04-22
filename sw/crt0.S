/*
 * crt0.S — C runtime startup for RV32I bare-metal programs.
 *
 * Runs before main(). Responsibilities:
 *   1. Initialize stack pointer to _stack_top (defined in sw/c_link.ld).
 *   2. Zero the .bss region between _bss_start and _bss_end.
 *   3. Call main().
 *   4. After main returns, spin forever — there is nowhere to "exit" to.
 *
 * Notes:
 *   - Section .text.init is placed first in IMEM by c_link.ld so _start
 *     lands at 0x00000000, matching the core's reset PC.
 *   - Linked with -nostartfiles so this is the ONLY startup glue. Do not
 *     rely on newlib's _init/_fini; we don't have constructors.
 *   - .option norelax disables linker relaxation around the gp setup — we
 *     don't use gp, but the pattern is conventional for RV32 crt0.
 */

    .section .text.init, "ax"
    .globl _start
    .type  _start, @function

_start:
    /* Disable linker relaxation while gp is uninitialized. We never set gp
     * (newlib-nano doesn't need it for anything we compile), but keeping
     * this idiom here makes it safe to add later without surprises. */
    .option push
    .option norelax

    /* Initialize stack pointer. _stack_top = ORIGIN(DMEM) + LENGTH(DMEM). */
    la    sp, _stack_top

    .option pop

    /* Zero .bss. _bss_start / _bss_end are provided by the linker script. */
    la    t0, _bss_start
    la    t1, _bss_end
bss_clear:
    bgeu  t0, t1, bss_done
    sw    zero, 0(t0)
    addi  t0, t0, 4
    j     bss_clear
bss_done:

    /* argc/argv unused in bare-metal, but pass sane defaults in case some
     * library function peeks at them. */
    li    a0, 0
    li    a1, 0

    call  main

    /* main returned. Nowhere to go — halt in an infinite loop. */
hang:
    j     hang

    .size _start, . - _start
