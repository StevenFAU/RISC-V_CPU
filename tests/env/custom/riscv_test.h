// Custom minimal test environment for RV32I core (no CSR support)
// Replaces the stock riscv-tests env/p/riscv_test.h

#ifndef _ENV_CUSTOM_H
#define _ENV_CUSTOM_H

//-----------------------------------------------------------------------
// Minimal macros — no CSRs, no trap handling
//-----------------------------------------------------------------------

#define RVTEST_RV64U
#define RVTEST_RV32U

#define TESTNUM gp

#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .align  2;                                                      \
        .globl _start;                                                  \
_start:                                                                 \
        /* Initialize all registers to zero */                          \
        li x1, 0;                                                       \
        li x2, 0;                                                       \
        li x3, 0;                                                       \
        li x4, 0;                                                       \
        li x5, 0;                                                       \
        li x6, 0;                                                       \
        li x7, 0;                                                       \
        li x8, 0;                                                       \
        li x9, 0;                                                       \
        li x10, 0;                                                      \
        li x11, 0;                                                      \
        li x12, 0;                                                      \
        li x13, 0;                                                      \
        li x14, 0;                                                      \
        li x15, 0;                                                      \
        li x16, 0;                                                      \
        li x17, 0;                                                      \
        li x18, 0;                                                      \
        li x19, 0;                                                      \
        li x20, 0;                                                      \
        li x21, 0;                                                      \
        li x22, 0;                                                      \
        li x23, 0;                                                      \
        li x24, 0;                                                      \
        li x25, 0;                                                      \
        li x26, 0;                                                      \
        li x27, 0;                                                      \
        li x28, 0;                                                      \
        li x29, 0;                                                      \
        li x30, 0;                                                      \
        li x31, 0;                                                      \
        li TESTNUM, 0;                                                  \

#define RVTEST_CODE_END                                                 \
        unimp

//-----------------------------------------------------------------------
// Pass/Fail — write result to tohost memory location, then infinite loop
//-----------------------------------------------------------------------

#define RVTEST_PASS                                                     \
        li TESTNUM, 1;                                                  \
        la t0, tohost;                                                  \
        sw TESTNUM, 0(t0);                                              \
        j .;

#define RVTEST_FAIL                                                     \
1:      beqz TESTNUM, 1b;                                               \
        sll TESTNUM, TESTNUM, 1;                                        \
        or TESTNUM, TESTNUM, 1;                                         \
        la t0, tohost;                                                  \
        sw TESTNUM, 0(t0);                                              \
        j .;

//-----------------------------------------------------------------------
// Data Section Macro
//-----------------------------------------------------------------------

#define EXTRA_DATA

#define RVTEST_DATA_BEGIN                                               \
        EXTRA_DATA                                                      \
        .pushsection .tohost,"aw",@progbits;                            \
        .align 6; .global tohost; tohost: .word 0;                      \
        .align 6; .global fromhost; fromhost: .word 0;                  \
        .popsection;                                                    \
        .align 4; .global begin_signature; begin_signature:

#define RVTEST_DATA_END .align 4; .global end_signature; end_signature:

#endif
