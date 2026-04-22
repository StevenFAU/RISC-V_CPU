# Phase 1 Context & Handoff — for Chat Continuity

This document captures the Phase 1 planning state and the Phase 1.0 handoff. Upload it to the project knowledge of a fresh chat window to resume work without losing design context.

---

## Current Repo State (entering Phase 1)

- **Tag:** `phase0-complete`
- **Last commit before Phase 1:** `ad78ef5` (phase0 closure)
- **Compliance:** rv32ui 37/37 green.
- **Infrastructure:** Verilator lint clean (29 documented waivers), GitHub Actions CI with three parallel jobs (lint, unit, compliance), C toolchain via purpose-built rv32i/ilp32 + newlib-nano, `make c PROG=<name>` target working, `printf("Hello from C!\n")` verified in sim-fpga.
- **Deferred items in `docs/tech_debt.md`:** C-build CI coverage, actions/checkout@v4 Node 20 deprecation, hardware verification of `hello_c.hex`.

Phase 0.4 (testbench harness upgrade) was deliberately deferred to Phase 4 — it was speculative infrastructure for a bus contract the pipeline refactor will define.

---

## Phase 1 Scope Summary

Phase 1 adds CSRs, synchronous exceptions, and M-mode trap handling to the single-cycle RV32I core. This is the first phase that modifies the core's execution semantics (Phase 0 was additive infrastructure).

### Sub-phase structure

| Sub-phase | Scope | Commits |
|-----------|-------|---------|
| 1.0 | CSR file as standalone module | 2-3 (preamble + RTL + docs) |
| 1.1 | SYSTEM opcode + CSR instruction integration into core | 1-2 |
| 1.2 | Trap entry/exit, exception causes, MRET | 1-2 |
| 1.3 | rv32mi compliance bringup | 1+ |

Estimated total: 3-4 weeks of focused part-time work.

---

## Design Decisions (locked in before any coding)

### Decision 1 — CSR set (Option B', 13 registers)

Implement: `mstatus`, `mie`, `mip`, `mtvec`, `mepc`, `mcause`, `mtval`, `mscratch`, `mhartid`, `mvendorid`, `marchid`, `mimpid`, `misa`, plus the 64-bit counters `mcycle`/`mcycleh` and `minstret`/`minstreth` with user-mode read-only aliases (`cycle`/`cycleh`/`instret`/`instreth`).

**Skipped:** `time`/`timeh` CSR aliases. Software reads mtime via MMIO (spec-compliant). Cross-bus timing path deferred to tech debt.

### Decision 2 — Write mask strategy

Per-CSR hardcoded masks. Each CSR has its own write-enable pattern baked into the always block. No generic masking framework.

### Decision 3 — Trap priority ordering

Full spec priority ordering:
1. Instruction address misaligned
2. Instruction access fault
3. Illegal instruction
4. Breakpoint
5. Load/store address misaligned
6. Load/store access fault
7. Ecall

Implemented as a priority encoder in Phase 1.2. The CSR file's interface must not preclude this.

### Decision 4 — `bus_error_o` handling

Treat `bus_error_o` as a *synchronous exception*, not an interrupt. It fires on the cycle of a load/store that hits an unmapped address. Core samples it during execute and raises load-access-fault or store-access-fault at retirement. The 1-bit port into the core is separate from Phase 2's `irq_timer`/`irq_external`/`irq_software` inputs.

### Decision 5 — rv32mi compliance bringup order

Unit tests first, compliance second. Each sub-phase has its own unit-testbench gate that must pass before compliance is even attempted. rv32mi stands up in Phase 1.3 as independent verification of everything 1.0–1.2 built.

### Decision 6 — C trap handler timing

Write `sw/traps_test.c` in Phase 1.2 when the hardware it depends on exists. Phase 1.0's unit tests are pure Verilog; Phase 1.1's tests are asm; Phase 1.2 is where C test programs land.

---

## Scope-Level Revision (committed)

**Phase 3 splits into 3a and 3b.** Formal verification layers alongside the capability it verifies:

- **Phase 3a:** Formal on single-cycle, trap-capable core (after Phase 1, before Phase 2).
- **Phase 3b:** Formal extended to interrupts (after Phase 2, before Phase 4).

**New ordering:** 1 → 3a → 2 → 3b → 4 → 5.

**Rationale:** Interrupts introduce nondeterminism that's architecturally harder to prove than synchronous traps. Splitting the formal work lets each proof verify a specific capability addition rather than one giant proof carrying the whole sync+async burden.

---

## New Tech Debt Items (added this planning session)

To append to `docs/tech_debt.md`:

- `time`/`timeh` CSR aliasing to mtime — deferred due to cross-bus timing path; memory-mapped access works and is spec-compliant.
- Bus fabric lacks assertion-based regression (decode correctness, handshake invariants). Consider adding assertions alongside Phase 3a/3b formal work.
- Simulation coverage metrics not collected. Verilator supports coverage; consider adding in Phase 3 window.

---

## Phase 1.0 Handoff

**Context:** Tier 1 Phase 1.0 — CSR file as a standalone module. Phase 0 complete (tag `phase0-complete`). This is the first sub-phase of Phase 1.

**Model/effort:** Opus 4.7, high effort. Run `/clear` before pasting.

### Critical framing — read this before anything else

This handoff has two goals:

1. **Deliver a working `rtl/csr_file.v` module** with 13 M-mode CSRs, per-CSR write masks, and a standalone testbench proving the module against directed unit tests. The module is not integrated with the core in this phase.

2. **Design the module's interface so that Phase 1.2's trap entry/exit logic slots in without restructuring.** The CSR file is a shared resource: Phase 1.1's CSR instructions will write it, and Phase 1.2's trap entry will *also* write it (updating `mepc`, `mcause`, `mtval` on trap entry; updating `mstatus.MPIE`/`MIE` on both trap entry and MRET). If the Phase 1.0 interface has a single write port, Phase 1.2 has to retrofit. If Phase 1.0 has a multi-source priority write port, Phase 1.2 just wires into it. **We're doing the latter.**

This is the "design for all consumers at module creation" principle. Bake it in now; don't retrofit it later.

### Design decisions already made (don't rescope)

From the Phase 1 planning discussion (captured above):

- **CSR set:** 13 CSRs total. See the full table below.
- **Write mask strategy:** Per-CSR hardcoded masks.
- **Trap priority:** Full spec priority ordering (implemented in Phase 1.2, but the CSR file's interface must not preclude it).
- **Identity CSRs hardwired to zero:** `mvendorid`, `marchid`, `mimpid`, `mhartid`.
- **`misa` hardwired to `0x40000100`:** MXL=32 (bits 31:30 = 01), I-bit set (bit 8). Read-only.
- **Counters (`cycle`, `cycleh`, `instret`, `instreth`) are 64-bit free-running.**
  - `cycle` increments every non-reset clock cycle.
  - `instret` increments on every retired-instruction cycle. Phase 1.0 does NOT wire `instret_tick` to anything real yet — it's an input port, and Phase 1.1 will wire it to the core's retirement signal. For Phase 1.0 testing, the testbench drives it directly.
  - These are software-writable (useful for calibration), per the spec.
- **`time`/`timeh` NOT implemented as CSRs.** Software reads mtime via MMIO. Added to tech debt.

### The complete CSR list for Phase 1.0

| Address | Name | Access | Reset | Notes |
|---------|------|--------|-------|-------|
| 0x300 | mstatus | RW (masked) | 0 | Only MIE (bit 3) and MPIE (bit 7) writable in Phase 1. MPP (bits 12:11) hardwired to 2'b11 (M-mode). All other bits WPRI (reads return 0, writes ignored). |
| 0x301 | misa | RO | 0x40000100 | MXL=32, I set. Writes ignored. |
| 0x304 | mie | RW (masked) | 0 | MTIE (7), MSIE (3), MEIE (11) writable. Rest WPRI. |
| 0x305 | mtvec | RW (masked) | 0 | MODE (bits 1:0) = hardwired 00 (direct mode only). BASE (31:2) writable. |
| 0x340 | mscratch | RW | 0 | Fully writable, no mask. |
| 0x341 | mepc | RW (masked) | 0 | Bits [1:0] hardwired to 00 (IALIGN=32). |
| 0x342 | mcause | RW | 0 | Fully writable. Interrupt bit (31) and exception code (30:0). |
| 0x343 | mtval | RW | 0 | Fully writable. |
| 0x344 | mip | RW (masked) | 0 | MTIP (7), MSIP (3), MEIP (11) readable. Writes: MSIP software-writable, MTIP/MEIP read-only (hardware-driven). |
| 0xF11 | mvendorid | RO | 0 | Writes ignored. |
| 0xF12 | marchid | RO | 0 | Writes ignored. |
| 0xF13 | mimpid | RO | 0 | Writes ignored. |
| 0xF14 | mhartid | RO | 0 | Writes ignored. |
| 0xB00 | mcycle | RW | 0 | Low 32 bits of 64-bit free-running counter. |
| 0xB02 | minstret | RW | 0 | Low 32 bits of 64-bit retired-instruction counter. |
| 0xB80 | mcycleh | RW | 0 | High 32 bits of mcycle. |
| 0xB82 | minstreth | RW | 0 | High 32 bits of minstret. |
| 0xC00 | cycle | RO | — | Mirror of mcycle. (User-mode counter, read-only alias.) |
| 0xC02 | instret | RO | — | Mirror of minstret. |
| 0xC80 | cycleh | RO | — | Mirror of mcycleh. |
| 0xC82 | instreth | RO | — | Mirror of minstreth. |

21 entries but only 13 *registers* — the `cycle`/`instret` user-mode addresses are read-only aliases of the M-mode counters. They share the same underlying 64-bit counters.

### Module interface

```verilog
module csr_file (
    input  wire         clk,
    input  wire         rst,       // synchronous active-high, per repo convention

    // --- Instruction-driven access (used by Phase 1.1 CSR instructions) ---
    input  wire [11:0]  csr_addr,      // CSR address
    input  wire         csr_read_en,   // assert to request a read
    input  wire [2:0]   csr_write_op,  // 3'b000 = none, 3'b001 = write, 3'b010 = set, 3'b011 = clear
    input  wire [31:0]  csr_write_data,
    output reg  [31:0]  csr_read_data,
    output wire         csr_illegal,   // asserts on access to unimplemented address, or write to RO

    // --- Trap-entry-driven access (wired in Phase 1.2) ---
    input  wire         trap_enter,    // assert for 1 cycle to enter a trap
    input  wire [31:0]  trap_pc,       // → mepc
    input  wire [31:0]  trap_cause,    // → mcause
    input  wire [31:0]  trap_tval,     // → mtval

    // --- MRET-driven access (wired in Phase 1.2) ---
    input  wire         trap_return,   // assert for 1 cycle on MRET

    // --- Counter tick inputs (instret wired in Phase 1.1, cycle internal) ---
    input  wire         instret_tick,  // assert for 1 cycle per retired instruction

    // --- Outputs to core ---
    output wire [31:0]  mtvec_o,       // used on trap entry (PC redirect)
    output wire [31:0]  mepc_o,        // used on MRET (PC restore)
    output wire         mstatus_mie_o, // current MIE bit (used by interrupt logic in Phase 2)

    // --- Debug ---
    output wire [31:0]  mstatus_o      // full mstatus for debug visibility
);
```

### Critical interface notes

- **Write-source priority:** `trap_enter` > `trap_return` > `csr_write_op`. In Phase 1.0, `trap_enter` and `trap_return` are held low by the testbench. In Phase 1.2 they'll be driven by the core's trap FSM. The priority must be correct from day one.

- **`csr_illegal` fires when:** (a) `csr_read_en` asserts on an unimplemented address, (b) `csr_write_op != 000` on a read-only CSR, or (c) `csr_write_op != 000` on an unimplemented address. Phase 1.1 will route this into the illegal-instruction detection path.

- **CSRRS/CSRRC with rs1=x0 do NOT write.** Spec detail: CSRRS/CSRRC only write if the write data is nonzero. Use `csr_write_op = 000` in the decoder for these cases — the CSR file doesn't need to know. CSRRW with rd=x0 still writes. The CSR file shouldn't care about the destination register; that's the decoder's problem.

- **`csr_read_data` is combinational on `csr_addr` when `csr_read_en` is asserted.** When `csr_read_en` is low, read_data is `0`. Avoids reads having side effects.

- **Counter increments:** `mcycle`/`mcycleh` increment every cycle when `!rst`. `minstret`/`minstreth` increment on every cycle where `instret_tick` is asserted. Writes take priority over increments (same pattern as `wb_timer`).

- **`mstatus` on trap entry:** `MPIE <- MIE`, `MIE <- 0`, `MPP <- 2'b11`. On MRET: `MIE <- MPIE`, `MPIE <- 1`, MPP stays M-mode. Code these specific bit manipulations explicitly.

### What to do

#### Step 1 — Housekeeping preamble (first commit of the phase)

Before writing RTL, land a small documentation-only commit:

1. **Update `TIER1_ROADMAP.md`:** split Phase 3 into 3a (formal on single-cycle, trap-capable core, before interrupts) and 3b (formal extended to interrupts, after Phase 2). Reorder: 1 → 3a → 2 → 3b → 4 → 5. Add a one-paragraph rationale.

2. **Update `docs/tech_debt.md`** with three new items:
   - `time`/`timeh` CSR aliasing deferred (memory-mapped access works).
   - Bus fabric lacks assertion-based regression; consider adding alongside Phase 3a/3b formal work.
   - Simulation coverage metrics not collected; consider adding in Phase 3 window.

3. **Commit:** `phase1: roadmap updates — split phase 3, tech debt additions`. Body notes the rationale.

#### Step 2 — Read existing code

Before writing `csr_file.v`:
- `TIER1_ROADMAP.md` (Phase 1 section, post-update).
- `rtl/rv32i_core.v` — writeback path and control signals.
- `rtl/control.v`, `rtl/alu_decoder.v` — decode style to match.
- `rtl/wb_timer.v` — write/increment race handling pattern.
- `rtl/pc.v` — reset style reference.
- `tb/tb_wb_timer.v` — self-checking TB structure reference.
- `docs/lint_waivers.md` — waiver style.

#### Step 3 — Implement `rtl/csr_file.v`

Follow the interface above exactly. Implementation notes:

- **Header comment:** document the full CSR list, the write-source priority, the "designed for Phase 1.2 trap integration" note. Reference TIER1_ROADMAP.md Phase 1.

- **Style:** match the repo — Verilog-2001, synchronous active-high reset, explicit widths, no latches. Lint must pass on first try.

- **Structure:**
  - Declare each CSR as a register (or bundle of fields for mstatus/mie/mip).
  - Combinational decode: given `csr_addr`, compute `(is_valid, is_readonly, read_data, write_mask)`.
  - Main always block: reset, then write-source priority chain per CSR.
  - Counter increment logic as separate always blocks for clarity.

- **Size budget:** target < 400 lines. Over 500 means over-abstraction; collapse.

- **Assertion:** one `ifndef SYNTHESIS` assertion — fire if both `trap_enter` and `trap_return` assert in the same cycle.

#### Step 4 — Write `tb/tb_csr_file.v`

Target: ~50 directed checks across all CSRs. Categories:

- **Category 1 — Reset values.** Read every implemented CSR after reset, verify reset value. Read an unimplemented address, verify `csr_illegal`. (~15 checks)

- **Category 2 — Write-then-read.** For every writable CSR, write a test pattern (e.g., `0xA5A5A5A5`), read back, verify only legal bits stuck. Verify mstatus WPRI bits, mtvec MODE hardwiring, mepc bits [1:0] hardwiring. (~10 checks)

- **Category 3 — Read-only CSRs reject writes.** For every RO CSR, write a nonzero pattern, verify read returns reset value, verify `csr_illegal` fires. (~6 checks)

- **Category 4 — Set/clear operations.** Pick `mscratch`. Write `0x00FF`. Set `0xF000`. Read back `0xF0FF`. Clear `0x00F0`. Read back `0xF00F`. (~4 checks)

- **Category 5 — Counter behavior.** Tick clock 100 cycles, read `mcycle`, expect ~100. Verify `mcycleh` stays 0 until overflow. Write to `mcycle`, verify write sticks and counting resumes. Assert `instret_tick` for 5 cycles, read `minstret`, expect 5. (~10 checks)

- **Category 6 — Trap entry simulation.** Drive `trap_enter=1` for one cycle with specific pc/cause/tval. Verify mepc/mcause/mtval got written. Verify MIE cleared, MPIE = old MIE. (~4 checks)

- **Category 7 — Trap return simulation.** Set up post-trap state. Drive `trap_return=1`. Verify MIE restored from MPIE, MPIE becomes 1, `mepc_o` output reflects saved PC. (~3 checks)

- **Category 8 — Priority.** Drive `trap_enter=1` AND `csr_write_op=001` targeting mepc simultaneously. Verify trap_enter wins. (~2 checks)

Each check prints pass/fail with a descriptive label. Summary: `PASSED X/Y tests` → `ALL PASSED` if Y==X (matches CI parsing).

#### Step 5 — Verify

- `make sim MOD=csr_file` — all directed tests green.
- `verilator --lint-only -Irtl -Wall rtl/csr_file.v rtl/*.v` — exits zero.
- All Phase 0 regressions pass: every existing `tb_*.v`, rv32ui 37/37, `make sim-fpga`, CI green.
- No file under `rtl/` other than `rtl/csr_file.v` modified. If you want to change `rv32i_core.v`, stop — that's Phase 1.1.

#### Step 6 — Documentation

- **Create `docs/csr_map.md`.** Authoritative reference:
  - Full CSR table (field-level detail for mstatus, mie, mip).
  - Write mask per CSR (hex and bit list).
  - Reset values and rationale.
  - Write-source priority and rationale.
  - What's NOT implemented and why.

- **Append to `docs/phase1_changelog.md`** (create if doesn't exist):
  ```
  - [feat] phase 1.0: csr_file module with 13 M-mode CSRs
    - instruction-access, trap-entry, and trap-return ports designed for Phase 1.1/1.2 integration
    - per-CSR hardcoded write masks
    - 64-bit free-running cycle and instret counters
    - standalone testbench with [N] directed checks across 8 categories
    - see docs/csr_map.md for the authoritative CSR reference
  ```

- **Update `TIER1_ROADMAP.md`** — mark Phase 1.0 complete with commit hash.

#### Step 7 — Commit and push

Three commits total (including Step 1 preamble):

1. `phase1: roadmap updates — split phase 3, tech debt additions` (Step 1).
2. `phase1: csr_file module — 13 M-mode CSRs, multi-source write priority` (RTL + TB).
3. `phase1: csr_file documentation — csr_map.md, changelog, roadmap` (optional — fold into #2 if small).

Push to main. CI must go green.

### Do NOT

- Do not modify `rtl/rv32i_core.v` or integrate the CSR file with the core. Phase 1.1.
- Do not implement any instruction decode. The CSR file's `csr_write_op` input is set by the testbench in 1.0; 1.1 wires it to the decoder.
- Do not implement `time`/`timeh` as CSRs.
- Do not implement MRET or ECALL or any actual trap-taking behavior. The CSR file only implements the *side effects* of trap entry/exit. The actual FSM lives in the core, Phase 1.2.
- Do not skip any of the 8 testbench categories.
- Do not over-abstract. No generic "CSR base class" or table-driven decoder. Explicit per-CSR handling is the repo style.

### Gate

- `tb_csr_file.v` passes all directed tests (~50 checks).
- Phase 0 regressions clean.
- `docs/csr_map.md` exists and documents all 13 CSRs.
- Roadmap updated, changelog appended.
- Preamble commit landed before RTL commit.
- All commits pushed, CI green.

### Report back with

- Three commit hashes (preamble, RTL, docs — or two if docs folded in).
- Exact count of directed checks in `tb_csr_file.v`.
- Module's LUT count from `verilator --lint-only --stats -Irtl rtl/*.v` (find csr_file entry).
- Any deviations from the interface spec with rationale. The interface is load-bearing for Phase 1.2.
- Any surprises in testbench writing — specifically, did any category reveal a bug in the RTL that unit-testing-as-you-go caught?

---

## Notes for the Resumed Chat

When picking up in a new chat:

1. Upload this document to the new chat's project knowledge.
2. Confirm the last commit hash on main matches expectations (should be `ad78ef5` if Phase 1.0 hasn't started, or the Phase 1.0 commits if it has).
3. Reference this doc by name ("per PHASE1_CONTEXT.md, here's where we are…") so the new chat grounds in the committed design rather than re-litigating it.
4. If the new chat wants to revisit a design decision, push back — these were settled deliberately after multiple rounds of discussion. Changing them mid-phase is expensive; changing them across chat sessions is doubly expensive because the rationale gets lost.

The Phase 1 plan is intentionally conservative on scope and deliberate on interface design. The "design for all consumers at module creation" principle in Phase 1.0 is the single most important thing for Phase 1.2 to land smoothly. Preserve it.
