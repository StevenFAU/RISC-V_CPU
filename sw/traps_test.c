/*
 * traps_test.c — Phase 1.2.4 end-to-end M-mode trap dispatcher test.
 *
 * Exercises every M-mode synchronous cause source the trap path was
 * built up across Phases 1.2.0 - 1.2.3:
 *
 *   0  inst_addr_misaligned   — JAL with imm[1]=1 (raw .word encoding)
 *   2  illegal_instruction    — CSRRW to RO mvendorid (raw .word per
 *                               Decision 8 in PHASE1.2.4_HANDOFF.md;
 *                               only path where the regfile_we gate is
 *                               observable from a single instruction)
 *   3  breakpoint             — EBREAK
 *   4  load_addr_misaligned   — LH at odd address inside DMEM
 *   5  load_access_fault      — LW from unmapped 0xF0000000 (per
 *                               Decision 9 — reuses the address that
 *                               1.2.2's sw/access_fault_test.S verified)
 *   6  store_addr_misaligned  — SH at odd address inside DMEM
 *   7  store_access_fault     — SW to unmapped 0xF0000000
 *  11  ecall_m                — ECALL
 *
 * Single C program, ONE dispatcher trap handler that decodes mcause
 * and routes to per-cause logic. Decisions 2, 3, 4 in the handoff:
 *   - Dispatcher pattern (not eight smaller programs) — exercises real
 *     C-level dispatch, mirrors rv32mi structure for 1.2.5, bisect-clean.
 *   - All eight causes in a single run for cross-cutting validation.
 *   - MRET round-trip is implicitly tested: every cause's handler MRETs
 *     out to continue, so failure to progress past cause N reveals MRET
 *     breakage without separate MRET-specific instrumentation.
 *
 * mtvec is installed in software (Decision 5) via _mtvec_setup, called
 * from the extended crt0.S before main. The dispatcher in this file
 * advances mepc by 4 (Decision 7 — every trapping instruction here is
 * a 4-byte RV32I op) and the trampoline mrets, so each cause resumes
 * at the instruction immediately following its trigger.
 *
 * Memory map (matches sw/c_link.ld):
 *   IMEM     0x00000000  (this code lives here)
 *   DMEM     0x00010000  (.rodata + .data + .bss + stack live here)
 *   UART TX  0x80000000  (data); 0x80000004 (status: bit 0 = busy)
 *
 * Output:
 *   "PASS\r\n" if all eight causes triggered with the expected mcause /
 *   mepc / mtval and mstatus rotation. Otherwise "FAIL\r\n" followed
 *   by a per-cause dump (name, triggered Y/N, observed vs expected).
 *   ASCII only — UART output convention (CHAT_HANDOFF.md).
 */

#include <stdint.h>

/* =====================================================================
 * UART (memory-mapped) — direct access to avoid pulling in newlib /
 * printf. printf would link in _write from syscalls.c plus a couple KB
 * of newlib code; we only need PASS/FAIL and per-cause hex dumps.
 * ===================================================================== */
#define UART_TX_DATA   ((volatile uint32_t *)0x80000000u)
#define UART_TX_STATUS ((volatile uint32_t *)0x80000004u)
#define UART_TX_BUSY   0x1u

static void uart_putc(char c) {
    while ((*UART_TX_STATUS) & UART_TX_BUSY) { /* spin */ }
    *UART_TX_DATA = (uint32_t)(uint8_t)c;
}

static void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

static void uart_puthex32(uint32_t v) {
    static const char hex[] = "0123456789ABCDEF";
    for (int shift = 28; shift >= 0; shift -= 4) {
        uart_putc(hex[(v >> shift) & 0xF]);
    }
}

/* =====================================================================
 * Cause numbers and mstatus bits
 * ===================================================================== */
#define CAUSE_INST_ADDR_MISALIGNED  0u
#define CAUSE_ILLEGAL_INSTRUCTION   2u
#define CAUSE_BREAKPOINT            3u
#define CAUSE_LOAD_ADDR_MISALIGNED  4u
#define CAUSE_LOAD_ACCESS_FAULT     5u
#define CAUSE_STORE_ADDR_MISALIGNED 6u
#define CAUSE_STORE_ACCESS_FAULT    7u
#define CAUSE_ECALL_M               11u

#define MSTATUS_MIE  0x008u
#define MSTATUS_MPIE 0x080u

/* =====================================================================
 * Per-cause observation table. The dispatcher records observed CSR
 * state into observations[current_idx]; main pre-populates the
 * "expected" fields per cause and the trigger PC right before firing.
 * ===================================================================== */
struct observation {
    const char *name;
    uint32_t expected_mcause;
    uint32_t expected_mtval;
    uint32_t expected_mepc;     /* captured from `lla` immediately before trigger */
    uint32_t obs_mcause;
    uint32_t obs_mepc;
    uint32_t obs_mtval;
    uint32_t obs_mstatus;
    int triggered;
};

#define NUM_CAUSES 8

/* Volatile because the dispatcher mutates from "interrupt" context;
 * keep the compiler from caching across the trap boundary. */
static volatile struct observation observations[NUM_CAUSES];
static volatile int current_idx = -1;

/* =====================================================================
 * Trap entry — trampoline (sw/traps_test_trampoline.S) sits at mtvec,
 * saves caller-saved regs, calls into here, restores, mrets.
 *
 * Reads architectural CSRs (post-trap-entry view: mstatus.MIE has just
 * been cleared, mstatus.MPIE captures pre-trap MIE), records them, and
 * advances mepc past the 4-byte trapping instruction so MRET resumes
 * at the next instruction.
 * ===================================================================== */
extern void trap_trampoline(void);

void trap_dispatcher(void) {
    uint32_t mcause, mepc, mtval, mstatus;
    __asm__ volatile ("csrr %0, mcause"  : "=r"(mcause));
    __asm__ volatile ("csrr %0, mepc"    : "=r"(mepc));
    __asm__ volatile ("csrr %0, mtval"   : "=r"(mtval));
    __asm__ volatile ("csrr %0, mstatus" : "=r"(mstatus));

    int i = current_idx;
    if (i >= 0 && i < NUM_CAUSES) {
        observations[i].triggered  = 1;
        observations[i].obs_mcause  = mcause;
        observations[i].obs_mepc    = mepc;
        observations[i].obs_mtval   = mtval;
        observations[i].obs_mstatus = mstatus;
    }

    /* Advance past 4-byte trapping op so MRET resumes at next inst. */
    uint32_t next_pc = mepc + 4u;
    __asm__ volatile ("csrw mepc, %0" :: "r"(next_pc));
    /* Trampoline now restores regs and mrets. */
}

/* _mtvec_setup overrides the weak no-op in crt0.S. Called by crt0
 * before main, so any trap fired from main lands in the trampoline. */
void _mtvec_setup(void) {
    __asm__ volatile ("csrw mtvec, %0" :: "r"((uint32_t)&trap_trampoline));
}

/* Force mstatus to a known pre-trigger state: MIE=1, MPIE=0. After
 * trap entry, observed mstatus should have MIE=0 / MPIE=1 (rotation).
 * After MRET, mstatus is MIE=1 / MPIE=1 — calling enable_mie()
 * before each subsequent trigger drops MPIE back to 0 so each test
 * sees the same starting mstatus. */
static inline void enable_mie(void) {
    __asm__ volatile ("csrw mstatus, %0" :: "r"((uint32_t)MSTATUS_MIE));
}

static void init_observations(void) {
    observations[0].name             = "ECALL";
    observations[0].expected_mcause  = CAUSE_ECALL_M;
    observations[0].expected_mtval   = 0u;

    observations[1].name             = "EBREAK";
    observations[1].expected_mcause  = CAUSE_BREAKPOINT;
    observations[1].expected_mtval   = 0u;

    observations[2].name             = "ILLEGAL_INST";
    observations[2].expected_mcause  = CAUSE_ILLEGAL_INSTRUCTION;
    observations[2].expected_mtval   = 0xF1129EF3u;  /* csrrw t4, mvendorid, t0 */

    observations[3].name             = "INST_ADDR_MISALIGNED";
    observations[3].expected_mcause  = CAUSE_INST_ADDR_MISALIGNED;
    /* expected_mtval = jal_pc + 6 — set after capture. */

    observations[4].name             = "LOAD_ADDR_MISALIGNED";
    observations[4].expected_mcause  = CAUSE_LOAD_ADDR_MISALIGNED;
    observations[4].expected_mtval   = 0x00010001u;

    observations[5].name             = "STORE_ADDR_MISALIGNED";
    observations[5].expected_mcause  = CAUSE_STORE_ADDR_MISALIGNED;
    observations[5].expected_mtval   = 0x00010025u;

    observations[6].name             = "LOAD_ACCESS_FAULT";
    observations[6].expected_mcause  = CAUSE_LOAD_ACCESS_FAULT;
    observations[6].expected_mtval   = 0xF0000000u;

    observations[7].name             = "STORE_ACCESS_FAULT";
    observations[7].expected_mcause  = CAUSE_STORE_ACCESS_FAULT;
    observations[7].expected_mtval   = 0xF0000000u;
}

static int observation_passes(int i) {
    /* Cast away volatile for read-only access in the verification loop. */
    const struct observation *o = (const struct observation *)&observations[i];
    if (!o->triggered)                                  return 0;
    if (o->obs_mcause  != o->expected_mcause)           return 0;
    if (o->obs_mtval   != o->expected_mtval)            return 0;
    if (o->obs_mepc    != o->expected_mepc)             return 0;
    if ((o->obs_mstatus & MSTATUS_MPIE) != MSTATUS_MPIE) return 0;
    if ((o->obs_mstatus & MSTATUS_MIE)  != 0u)          return 0;
    return 1;
}

static void dump_observation(int i) {
    const struct observation *o = (const struct observation *)&observations[i];
    uart_puts("  ");
    uart_puts(o->name);
    uart_puts(": trig=");
    uart_putc(o->triggered ? 'Y' : 'N');
    uart_puts(" mcause=");      uart_puthex32(o->obs_mcause);
    uart_puts(" mepc=");        uart_puthex32(o->obs_mepc);
    uart_puts(" mtval=");       uart_puthex32(o->obs_mtval);
    uart_puts(" mstatus=");     uart_puthex32(o->obs_mstatus);
    uart_puts(" exp_mcause=");  uart_puthex32(o->expected_mcause);
    uart_puts(" exp_mepc=");    uart_puthex32(o->expected_mepc);
    uart_puts(" exp_mtval=");   uart_puthex32(o->expected_mtval);
    uart_puts("\r\n");
}

/* =====================================================================
 * main — fire each cause in turn. Each trigger uses a small inline
 * asm block that:
 *   - captures the trigger PC via `lla` of a label co-located with the
 *     trapping instruction (so observations[i].expected_mepc holds the
 *     exact PC the trap path will write into mepc),
 *   - executes the trapping instruction.
 *
 * After each trap, control returns to the instruction immediately
 * following the trigger inside the same asm block; main proceeds to
 * the next cause.
 *
 * Notes on the inline asm:
 *   - "memory" clobber prevents reordering of observations[].* writes
 *     across the trap boundary.
 *   - Scratch registers (t0/t1/t4) are listed in clobbers, so GCC
 *     won't allocate them as the output `pc` register.
 *   - .word encodings are used where the assembler refuses to emit
 *     the deliberately-illegal instruction (csrrw t4, mvendorid, t0)
 *     or where GAS won't emit a misaligned target field (jal +6).
 * ===================================================================== */
int main(void) {
    init_observations();
    enable_mie();

    /* ----- 0: ECALL (mcause=11) -------------------------------------- */
    current_idx = 0;
    {
        uint32_t pc;
        __asm__ volatile (
            "lla %0, 1f\n"
            "1: ecall\n"
            : "=r"(pc) :: "memory"
        );
        observations[0].expected_mepc = pc;
    }
    enable_mie();

    /* ----- 1: EBREAK (mcause=3) -------------------------------------- */
    current_idx = 1;
    {
        uint32_t pc;
        __asm__ volatile (
            "lla %0, 1f\n"
            "1: ebreak\n"
            : "=r"(pc) :: "memory"
        );
        observations[1].expected_mepc = pc;
    }
    enable_mie();

    /* ----- 2: ILLEGAL_INST (mcause=2) — csrrw t4, mvendorid, t0 ------ */
    /* Encoded as .word 0xF1129EF3 — the assembler accepts it when
     * Zicsr is enabled, but raw .word makes mtval's expected value
     * (= the instruction word, per spec for illegal_inst) explicit
     * and survives unrelated assembler/march changes. */
    current_idx = 2;
    {
        uint32_t pc;
        __asm__ volatile (
            "lla %0, 1f\n"
            "1: .word 0xF1129EF3\n"
            : "=r"(pc) :: "t0", "t4", "memory"
        );
        observations[2].expected_mepc = pc;
    }
    enable_mie();

    /* ----- 3: INST_ADDR_MISALIGNED (mcause=0) — jal +6 -------------- */
    /* Encoded as .word 0x0060006F — GAS won't emit a J-imm with
     * bit 1 set against an aligned label (matches the trick from
     * sw/misaligned_jump_test.S). rd=x0 so no register conflict. */
    current_idx = 3;
    {
        uint32_t pc;
        __asm__ volatile (
            "lla %0, 1f\n"
            "1: .word 0x0060006F\n"
            : "=r"(pc) :: "memory"
        );
        observations[3].expected_mepc  = pc;
        observations[3].expected_mtval = pc + 6u;
    }
    enable_mie();

    /* ----- 4: LOAD_ADDR_MISALIGNED (mcause=4) — LH at 0x10001 -------- */
    current_idx = 4;
    {
        uint32_t pc;
        __asm__ volatile (
            "li t0, 0x10001\n"
            "lla %0, 1f\n"
            "1: lh t1, 0(t0)\n"
            : "=r"(pc) :: "t0", "t1", "memory"
        );
        observations[4].expected_mepc = pc;
    }
    enable_mie();

    /* ----- 5: STORE_ADDR_MISALIGNED (mcause=6) — SH at 0x10025 ------- */
    current_idx = 5;
    {
        uint32_t pc;
        __asm__ volatile (
            "li t0, 0x10025\n"
            "li t1, 0x1234\n"
            "lla %0, 1f\n"
            "1: sh t1, 0(t0)\n"
            : "=r"(pc) :: "t0", "t1", "memory"
        );
        observations[5].expected_mepc = pc;
    }
    enable_mie();

    /* ----- 6: LOAD_ACCESS_FAULT (mcause=5) — LW from 0xF0000000 ------ */
    current_idx = 6;
    {
        uint32_t pc;
        __asm__ volatile (
            "lui t0, 0xF0000\n"
            "lla %0, 1f\n"
            "1: lw t1, 0(t0)\n"
            : "=r"(pc) :: "t0", "t1", "memory"
        );
        observations[6].expected_mepc = pc;
    }
    enable_mie();

    /* ----- 7: STORE_ACCESS_FAULT (mcause=7) — SW to 0xF0000000 ------- */
    current_idx = 7;
    {
        uint32_t pc;
        __asm__ volatile (
            "lui t0, 0xF0000\n"
            "li  t1, 0xDEADBEEF\n"
            "lla %0, 1f\n"
            "1: sw t1, 0(t0)\n"
            : "=r"(pc) :: "t0", "t1", "memory"
        );
        observations[7].expected_mepc = pc;
    }

    /* ----- Verify all observations ----------------------------------- */
    int all_pass = 1;
    for (int i = 0; i < NUM_CAUSES; i++) {
        if (!observation_passes(i)) {
            all_pass = 0;
        }
    }

    if (all_pass) {
        uart_puts("PASS\r\n");
        return 0;
    } else {
        uart_puts("FAIL\r\n");
        for (int i = 0; i < NUM_CAUSES; i++) {
            dump_observation(i);
        }
        return 1;
    }
}
