# Phase 1 Changelog — CSRs, Traps, M-Mode

Running log of fixes/changes landed during Phase 1 of `TIER1_ROADMAP.md`.
Newest entries at top.

## 2026-04-22 (Phase 1.0)
- [rtl] Standalone CSR file — `rtl/csr_file.v`.
  - 13 M-mode CSRs (`mstatus`, `misa` RO, `mie`, `mtvec`, `mscratch`,
    `mepc`, `mcause`, `mtval`, `mip`, plus `mvendorid`/`marchid`/
    `mimpid`/`mhartid` all RO=0).
  - 64-bit `mcycle`/`minstret` with `mcycleh`/`minstreth` and the
    user-RO aliases `cycle`/`cycleh`/`instret`/`instreth`.
  - Per-CSR write masks: `mstatus` MIE+MPIE only (MPP=11 hardwired);
    `mie` MEIE/MTIE/MSIE only; `mtvec` BASE bits [31:2] (MODE=00);
    `mepc` bits [31:2]; `mip` MSIP-only software-writable.
  - Multi-source write priority designed in for the Phase 1.2
    consumers from the start: `trap_enter > trap_return >
    csr_write_op`. Phase 1.0 testbench ties trap inputs low; the
    chain is exercised by directed tests so the FSM can wire in
    without restructuring.
  - Counter write/increment race handled like `wb_timer`'s mtime: a
    write to either half replaces it and skips that cycle's
    increment; the unwritten half is preserved.
  - `csr_illegal` asserts on (a) read of an unimplemented address,
    (b) any non-zero write op to a read-only CSR, or (c) any
    non-zero write op to an unimplemented address. Feeds into the
    Phase 1.3 illegal-instruction trap path.
  - `\`ifndef SYNTHESIS` assertion for `trap_enter && trap_return`
    mutual exclusion — a structural invariant the Phase 1.2 FSM must
    respect.
  - `time`/`timeh` (CSR addresses 0xC01/0xC81) deliberately deferred
    — see `docs/tech_debt.md`. MMIO read of `wb_timer.mtime_lo/hi`
    from software is already the spec-compliant alternative.
- [tb] Self-checking `tb/tb_csr_file.v` — 63 directed checks across
  8 categories: reset values, write-then-read with masks, RO-CSR
  write rejection, CSRRS/CSRRC, counter behavior (free-run, tick,
  write/increment race), trap entry, MRET, and the trap-enter >
  csr_write_op priority chain. Helper tasks (`do_write`/`do_read`/
  `do_set`/`do_clear`/`try_write_ro`/`expect_eq32`/`expect_true`)
  keep the test bodies compact.
- [docs] `docs/csr_map.md` — full field-level CSR reference, write
  masks, reset values, write-source priority, CSR-instruction
  semantics, counter behavior, and a table of what's deliberately
  not implemented.
- [docs] `docs/phase1_context.md` — Phase 1 design decisions
  (Option B' 13-register set, write-priority chain, `time`/`timeh`
  deferral, phasing 1.0 → 1.4) imported from the planning handoff.
- [planning] `TIER1_ROADMAP.md` — Phase 1 sub-section 1.0 added for
  the standalone CSR file; section 1.1 rescoped to
  decode + writeback wiring; section 1.2 rescoped to the trap FSM
  (ECALL/EBREAK/MRET decode + trap entry/exit wiring).

### Verification
- `verilator --lint-only -Irtl -Wall rtl/csr_file.v` — clean (one
  `UNUSEDSIGNAL` waiver on `trap_pc[1:0]` since the bits are
  intentionally dropped by the word-alignment write mask on `mepc`).
- `make sim MOD=csr_file` — 63 PASS / 0 FAIL, "ALL TESTS PASSED".
- Full Phase 0 regression unchanged:
  - All 17 unit testbenches pass.
  - `make sim-top` integration test passes.
  - `make sim-fpga` "Hello, RISC-V!" passes.
  - `tests/Makefile run-all` rv32ui compliance: 37/37.
