# Phase 1 Changelog — CSRs, Traps, M-Mode

Running log of fixes/changes landed during Phase 1 of `TIER1_ROADMAP.md`.
Newest entries at top.

## 2026-05-06 (Phase 1.1)

- [feat] Phase 1.1 — SYSTEM opcode decode + CSR-instruction integration
  into `rv32i_core.v`. The six CSR instructions (CSRRW, CSRRS, CSRRC,
  CSRRWI, CSRRSI, CSRRCI) are fully functional; ECALL/EBREAK/MRET decode
  to an illegal-instruction placeholder consumed by Phase 1.2's trap
  FSM. (commits `de2515f` + `1ee341c` + `f1cedd3` + `8fd6a8d` + `782f12c`)
- [rtl] `rtl/defines.v` — added `OP_SYSTEM` macro (`7'b1110011`).
- [rtl] `rtl/control.v` — `funct3` input added; new outputs
  `is_csr` / `csr_op[2:0]` / `csr_use_imm` / `illegal_system` /
  `illegal_opcode`. The rs1=x0 / zimm=0 no-write gating is applied at
  the use site in `rv32i_core.v` rather than in the decoder, keeping
  control.v minimal. **Behavior change:** `illegal_opcode` pulses on
  the case-statement default branch, where Phase 1.0 silently produced
  a NOP-ish state — recorded for future bisect, although rv32ui
  programs use only allocated opcodes so the new pulse never fires
  under that test set.
- [rtl] `rtl/rv32i_core.v` — extended port list:
  - Outputs (decoder-driven): `csr_addr_o` / `csr_read_en_o` /
    `csr_write_op_o` / `csr_write_data_o`.
  - Inputs (csr_file → core): `csr_read_data_i` / `csr_illegal_i`.
  - Retirement: `instret_tick_o = !rst` (single-cycle).
  - Illegal: `illegal_inst_o = csr_illegal_i | illegal_system |
    illegal_opcode` (unconnected at fpga_top until Phase 1.2 consumes).
  - Trap-related (per Decision D1 from `docs/phase1_context.md`):
    `mtvec_i` / `mepc_i` / `mstatus_mie_i` enter the core's port list
    now, awaiting Phase 1.2's PC-redirect mux. `lint_off UNUSEDSIGNAL`
    documents the intent.
  - Writeback mux extended from 4 sources to 5: CSR readback added,
    placed first in the priority chain (mutually exclusive with the
    others by opcode, so order is for readability).
  - `csr_write_data_o` selects between `rs1_data` and the
    zero-extended 5-bit immediate (`{27'b0, rs1_addr}`) on
    `csr_use_imm`. The CSRRW-rd=x0 read-suppression and CSRRS/C-rs1=x0
    write-suppression both happen at this site.
- [rtl] `rtl/fpga_top.v` — `csr_file` instantiated as a sibling of
  `rv32i_core`. Trap entry/exit and `core_illegal_inst` left
  unconnected awaiting Phase 1.2; `mstatus_o` from `csr_file` left
  unconnected (debug-visibility port; consumed by `tb_csr_file.v`).
- [tb] `tb/tb_control.v` — 24/24 PASS. Coverage doubled: SYSTEM-CSR
  variants, the SYSTEM-funct3-0 placeholder, unknown-opcode
  illegal_opcode pulse, CUSTOM0-not-illegal preservation.
- [tb] `tb/tb_rv32i_core_csr.v` (new) — directed integration TB for
  the core+csr_file integration path. 14 tests, 26 individual checks:
  CSRRW round-trip, CSRRS set, CSRRC clear, rs1=x0/zimm=0 no-write
  gating (×4 variants), rd=x0 write-still-happens, CSRRWI immediate,
  RO-write illegal, unimpl-read illegal, minstret/mcycle counter
  reads, RMW old-vs-new atomic semantic. CI auto-pickup confirmed.
- [tb] `tb/tb_compliance.v` + `tb/tb_rv32i_core.v` — port-list
  updates: tied new core inputs to safe defaults, outputs left
  unconnected via `lint_off PINCONNECTEMPTY`. Compliance harness was
  the load-bearing check; rv32ui 37/37 pass with cycle counts
  byte-identical to the Phase 1.0 baseline (verified after each of
  the four Phase 1.1 RTL/asm commits).
- [sw] `sw/csr_test.S` (new) — minimal end-to-end CSR demo. Writes
  `0x12345678` to `mscratch` via CSRRW, reads back via CSRRS, prints
  `PASS\r\n` or `FAIL\r\n` over memory-mapped UART. Reuses the
  poll-and-send pattern from `sw/hello.S`.
- [tb] `tb/tb_fpga_top_csr.v` (new) — duplicate-and-rename of
  `tb_fpga_top_asm.v` per the Phase 0.2 hello_c precedent. Loads
  `sim/csr_test.hex` + DMEM strings, expects `PASS\r\n`.
- [build] `Makefile` — `asm` target now uses `-march=rv32i_zicsr`.
  Ubuntu binutils 2.42 split Zicsr from base RV32I; required for the
  CSR mnemonics in csr_test.S, harmless for non-CSR programs (verified
  by re-running `sim-fpga` with hello.S — still passes). New
  `sim-fpga-csr` target.
- [ci] `.github/workflows/ci.yml` — added `fpga_top_csr` to the
  unit-TB skip list (firmware-dependent, like fpga_top_asm /
  fpga_top_c). `tb_rv32i_core_csr` is self-contained and remains in
  the auto-pickup path.
- [docs] `docs/datapath.md` — writeback mux diagram updated to 5
  sources; new "SYSTEM-Opcode Decode (Phase 1.1)" section documenting
  the decoder outputs and the core-side consumption.
- [docs] `docs/csr_map.md` — Phase 1.1 integration note prepended.

### Verification
- `verilator --lint-only -Irtl -Wall --top-module fpga_top rtl/*.v`:
  clean.
- `make sim MOD=rv32i_core_csr`: 26/26 PASS, "ALL TESTS PASSED".
- `make sim MOD=csr_file`: 63/63 PASS (Phase 1.0 unchanged).
- `make sim MOD=control`: 24/24 PASS.
- All 17 other CI-eligible unit testbenches: PASS, no regression.
- `cd tests && make run-all`: 37/37 PASS, all 37 cycle counts
  byte-identical to the Phase 1.0 baseline (verified after each of
  the five Phase 1.1 commits — the load-bearing check that integration
  introduced no behavioral drift on existing instructions).
- `make sim-fpga` with `sw/hello.S`: PASS, "Hello, RISC-V!\r\n".
- `make sim-fpga-csr` with `sw/csr_test.S`: PASS, "PASS\r\n" received
  end-to-end through the full SoC path.

### Phase 1.0 interface validation
The `csr_file` module landed in Phase 1.0 with a deliberately
pre-shaped interface (designed for all consumers). Phase 1.1
integration consumed every Phase-1.0 port without modification:
- `csr_addr` / `csr_read_en` / `csr_write_op` / `csr_write_data` —
  driven by the core's decode + operand paths.
- `csr_read_data` / `csr_illegal` — consumed by writeback mux and the
  illegal_inst signal aggregation.
- `instret_tick` — driven by `!rst`.
- `mtvec_o` / `mepc_o` / `mstatus_mie_o` — routed through the core's
  port list awaiting Phase 1.2.
- `trap_enter` / `trap_pc` / `trap_cause` / `trap_tval` /
  `trap_return` — tied 0 awaiting Phase 1.2 (chain pre-built in 1.0).
- `mstatus_o` — debug-visibility, consumed only by `tb_csr_file.v`.

No interface weakness was discovered; the 1.0 interface is exactly the
right shape for 1.1's needs and 1.2's trap FSM should slot in without
restructuring.

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
