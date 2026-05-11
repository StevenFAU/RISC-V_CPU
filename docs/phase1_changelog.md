# Phase 1 Changelog — CSRs, Traps, M-Mode

Running log of fixes/changes landed during Phase 1 of `TIER1_ROADMAP.md`.
Newest entries at top.

## 2026-05-10 (Phase 1.2.5)

- [feat] Phase 1.2.5 — sixth and final sub-phase of the Phase 1.2
  trap work. **rv32mi compliance bringup** against the upstream
  riscv-tests suite. Structurally distinct from every prior sub-phase:
  rather than "we built X and tested X," this one is "an external
  compliance suite tests the spec implementation; failures are
  diagnostic information." N=16 rv32mi tests classified — 14 PASS,
  2 signed-off (O), zero (F) / (D) / (E) / (U) remaining. rv32ui
  37/37 byte-identical to `phase1.2.4-complete` through 11 commits.
  **Phase 1.2 synchronous trap work is complete and rv32mi-compliant
  within the documented (O) scope.** No Phase 2 (interrupt) work
  was done.

  Commits (chronological):
  `cf60e7b` csr_file integration into tb_compliance ·
  `044e307` rv32mi inventory + pre-classification ·
  `6e3bcc1` Checkpoint 2 sign-offs + (F) pre-flag notes ·
  `985cc9f` fork riscv-tests env/p/ to tests/env/rv32mi_p/ (verbatim) ·
  `0d7ba67` env stub unimplemented CSR inits ·
  `342adda` control.v decode FENCE-as-NOP (rv32mi prerequisite) ·
  `1b60a4f` env memory map adjustments ·
  `d2674b0` rv32mi first compliance run + triage ·
  `ee02594` fix misa WARL semantics ·
  `6bd91a0` fix SLLI/SRLI/SRAI funct7 validation ·
  [Step 6 closure commit, this entry].

- [tb] `tb/tb_compliance.v` — instantiates `csr_file` alongside
  `rv32i_core`, mirroring the `fpga_top.v` topology. CSR / trap-entry
  / MRET interface ports route between core and csr_file via dedicated
  wires; the unified 16 KB byte-addressed memory model is unchanged.
  `bus_error_i` tied `1'b0` (no `wb_interconnect` in this harness;
  unified-mem decodes every in-range address; access faults not
  exercisable here). `illegal_inst_o` and `csr_file.mstatus_o` left
  unconnected per `fpga_top.v` precedent. No `irq_*` ports exist on
  `rv32i_core` today (Phase 2 work).

- [env] `tests/env/rv32mi_p/` — project-tracked fork of upstream
  `rv32i/tests/env/p/`. Three fork commits for diff reviewability:
    1. **Verbatim copy** from `env/p/`. Establishes the baseline so
       subsequent diffs are isolated patches.
    2. **Stubbed unimplemented-CSR writes** in startup macros
       (`INIT_PMP`, `INIT_RNMI`, `INIT_SATP`, `DELEGATE_NO_TRAPS`)
       and inline `csrw stvec, t0` / `csrw medeleg, t0` in
       `reset_vector`. Eight CSR writes stubbed across five sites;
       targets: `pmpaddr0`, `pmpcfg0`, `CSR_MNSTATUS`, `satp`,
       `medeleg` (×2), `mideleg`, `stvec`. Local `la t0, 1f; csrw
       mtvec, t0; ...; 1:` recover-trampoline preserved in each
       macro as defense-in-depth. Comment form is block-comment
       `/* original-inst -- rationale */` rather than `//` because
       cpp's `//` strips through macro `\` continuations and breaks
       expansion; documented in a header comment in the file. All
       remaining csrw/csrwi target implemented CSRs (mtvec / mie /
       mstatus / mepc / mhartid / mcause).
    3. **Memory map adapted** from base `0x80000000` to `0x00000000`
       for `tb_compliance`'s 16 KB unified-mem window. `.tohost`
       pinned at `0x1000` matching `TOHOST_ADDR`. Explicit linker
       ASSERTs on `.text.init` overflowing `0x1000` and `_end`
       overflowing `0x4000`. Trampoline shape, CSR-init order, and
       tohost mechanism preserved verbatim per the fork discipline
       (§4.3 of handoff).

  **Location correction:** originally directed to live at
  `rv32i/tests/env/rv32mi_p/`, but `rv32i/` is an untracked external
  git checkout in the project tree (own `.git` inside, listed as one
  untracked entry by `git status`). Redirected to project-root path
  `tests/env/rv32mi_p/` (parallel to existing tracked
  `tests/env/custom/`) at Checkpoint 2 sign-off. Upstream-diff
  visibility preserved via `diff -r rv32i/tests/env/p/
  tests/env/rv32mi_p/`.

- [env] `tests/env/rv32mi_p/expected_failures.md` — full audit
  trail of (O) classifications. The pre-classified (O) category
  list grew from four (interrupts / vectored mtvec / S-mode /
  time-timeh) to **six** with the two new categories added at
  Checkpoint 2 sign-off: **Sdtrig** (Debug-spec hardware triggers)
  and **PMP** (Physical Memory Protection). Two signed-off (O)
  recordings: `breakpoint` (Sdtrig) and `pmpaddr` (PMP).

- [env] **`mscratch` handler-stack trampoline pattern documented
  but not required.** env/p's trap_vector is single-stack with
  caller-saved register save/restore handled by the test's own
  `mtvec_handler`; no rv32mi test deliberately corrupts `sp`, so
  the single-stack approach suffices. The `csrrw sp, mscratch, sp`
  atomic-swap pattern is reserved for Phase 6+ OS-arc work (or
  custom tests that intentionally exercise stack edge cases) and
  documented in `docs/CHAT_HANDOFF.md` so future readers know when
  to invoke it.

- [build] `tests/Makefile` —
  - `RV32MI_TESTS` list (16 tests).
  - `MI_CFLAGS = -march=rv32i_zicsr -mabi=ilp32 -nostdlib
    -nostartfiles -T env/rv32mi_p/link.ld -I env/rv32mi_p
    -I isa/macros/scalar`. **`-march=rv32i_zicsr` (vs `rv32i` for
    rv32ui)** is required because rv32mi sources use CSR instructions
    (`csrr`, `csrw`, `csrrs`, …) explicitly; rv32ui sources never do.
    This is an audit-clear build-flag difference between the two
    suites, NOT a cross-cutting convention.
  - `test-rv32mi-all` / `run-rv32mi` / `run-rv32mi-one TEST=<name>`
    targets mirror the existing `test-all` / `run-all` / `run TEST=`
    patterns for rv32ui. Build artifacts prefixed `rv32mi_*` to avoid
    pattern-rule collisions on shared `BUILD_DIR`.
  - `RTL_SRCS` for `tb_compliance` gains `csr_file.v` (without it
    iverilog cannot resolve the `csr_file` reference in the harness).

- [rtl] **(F) fix — FENCE-as-NOP decode** (commit `342adda`).
  `rtl/control.v` and `rtl/defines.v` gain an `OP_MISC_MEM`
  (`7'b0001111`) case decoding both FENCE (funct3=000) and FENCE.I
  (funct3=001) as NOP. Without this, env/p's `RVTEST_PASS` and
  `RVTEST_FAIL` macros (both begin with `fence;`) infinite-loop every
  rv32mi test at the fail trampoline: `fence` traps illegal_inst →
  env's `trap_vector` dispatches to test's `mtvec_handler` → `j fail`
  → `RVTEST_FAIL` → `fence` → repeat. The rv32ui-minimal env
  (`env/custom`) sidesteps fence in its PASS/FAIL macros, which is
  why rv32ui passed before this commit — FENCE was simply never
  executed. NOP is spec-conformant on this microarchitecture
  (single-cycle, single-hart, no I-cache, strictly sequential
  memory model). Chronologically landed as Step 3 (d) — a
  prerequisite surfaced during Step 3 smoke testing rather than via
  Step 4 triage, but applied with full Step 5 (F)-fix discipline
  (single-bug commit, full rv32ui re-run, byte-identity preserved
  because FENCE doesn't appear in compiled rv32ui `.text`).

- [rtl] **(F) fix — misa WARL semantics** (commit `ee02594`,
  Step 5 a). `rtl/csr_file.v` previously marked `CSR_MISA` as
  `is_readonly=1`, causing writes to trap illegal_inst. Per the
  privileged spec, misa is WARL: writes are accepted without trap,
  but storage is never updated; reads always return the
  implementation's fixed value. Fix uses `csr_file`'s third
  CSR-mode state (`is_readonly=0` + no `write_misa` wire → writes
  silently swallowed, storage never updates). `tb/tb_csr_file.v`
  moved the misa test from Category 3 (RO CSRs reject writes) to a
  new Category 3b (misa WARL). The other RO CSRs (mvendorid,
  mhartid, cycle, etc.) remain in Category 3 — they are genuinely
  RO per spec. Made `rv32mi/ma_fetch` PASS.

- [rtl] **(F) fix — SLLI/SRLI/SRAI funct7 validation** (commit
  `6bd91a0`, Step 5 b). `rtl/control.v` gains a `funct7` input
  (wired from `instr[31:25]` in `rtl/rv32i_core.v`). Inside
  `OP_R_TYPE` and `OP_I_ALU` cases, the decoder now asserts
  `illegal_opcode=1` when `funct3` is a shift but `funct7` doesn't
  match the spec-required pattern (`0000000` for SLL/SLLI/SRL/SRLI;
  `0100000` for SRA/SRAI). `illegal_opcode`'s semantic broadens
  from "unknown opcode" to "decode-time illegal" — comment updated.
  `tb/tb_control.v` gains 6 new check_csr expects covering legal
  SLLI/SRLI/SRAI + illegal shift encodings (including the
  rv32mi/shamt `.word 0x02051513` case). Scope deliberately limited
  to shifts; R-type non-shift funct7 validation filed in
  `docs/tech_debt.md` per single-bug-per-commit discipline. Made
  `rv32mi/shamt` PASS.

- [docs] **`docs/CHAT_HANDOFF.md` (new)** — five project-wide
  conventions accumulated across the Phase 1 trap work:
  1. `trap_pc` vs `trap_tval` masking distinction (1.2.1 closure).
  2. Module-level TB input tieoff convention (1.2.2 / 1.2.4 origin).
  3. `mscratch` handler-stack trampoline (documented, not required
     for the rv32mi suite — reserved for sp-corrupting trap tests).
  4. Phase scope principle (sub-phases land capability or coverage;
     reg-only steps fold into the next phase that lands real
     capability).
  5. csr_file three-state CSR model (RO-trap / RW-stored / WARL —
     discovered during Step 5 a misa fix).

  Previously a claude.ai-side meta-doc; now in-repo at
  `docs/CHAT_HANDOFF.md`. Sub-phase handoffs reference these
  conventions; new sub-phases add to them as patterns crystallize.

- [docs] `docs/tech_debt.md` — one new (D) entry: **R-type
  non-shift funct7 validation** (deferred from Step 5 b's shamt fix
  scope). Surfaces when a future extended-compliance or M-extension
  phase exercises invalid R-type encodings. Includes repro snippet.

### rv32mi summary

| Cat | Count | Tests |
|---|---|---|
| (P) Pass | 14 | csr, illegal, instret_overflow, lh-misaligned, lw-misaligned, ma_addr, ma_fetch, mcsr, sbreak, scall, shamt, sh-misaligned, sw-misaligned, zicntr |
| (O) Sdtrig (signed off Checkpoint 2) | 1 | breakpoint |
| (O) PMP (signed off Checkpoint 2) | 1 | pmpaddr |
| (F) / (D) / (E) / (U) remaining | 0 | — |

### rv32ui regression — byte-identical at every commit

| Stage | rv32ui | Cycle drift vs phase1.2.4-complete |
|---|---|---|
| After `cf60e7b` (csr_file integration) | 37/37 | zero |
| After `342adda` (FENCE-as-NOP) | 37/37 | zero |
| After `ee02594` (misa WARL) | 37/37 | zero |
| After `6bd91a0` (shamt funct7) | 37/37 | zero |

Per-test cycle counts identical: `add=459 addi=236 and=479 andi=192
auipc=53 beq=285 bge=303 bgeu=328 blt=285 bltu=310 bne=285 jal=49
jalr=109 lb=247 lbu=247 lh=263 lhu=272 lw=277 lui=59 or=482 ori=199
sb=448 sh=501 sw=508 sll=487 slli=235 slt=453 slti=231 sltiu=231
sltu=453 sra=506 srai=250 srl=500 srli=244 sub=451 xor=481 xori=201`.

### Verification

- `make run-rv32mi` final: 14 P / 2 F (both (O) signed off, zero
  surprises).
- `make run-all` rv32ui: 37/37, byte-identical to
  `phase1.2.4-complete` (and therefore byte-identical through six
  sub-phases of Phase 1.2 trap work).
- 19 unit testbenches PASS (`make sim MOD=<each>`). `tb_csr_file`
  gained Category 3b (2 new expects, 2 retired); `tb_control`
  gained 6 new shift-funct7 expects.
- 11 carry-forward sim-fpga tests PASS (csr / ecall / ebreak /
  illegal / misaligned / misaligned-load / misaligned-store /
  access-fault / mret / ecall-mret-roundtrip / traps).
- Verilator lint clean for `--top-module fpga_top -Irtl -Wall
  rtl/*.v`.

### Confirmed: no Phase 2 (interrupt) work

The pre-classified (O) interrupt category was not triggered by any
rv32mi test — none of the 16 tests touch `mip`/`mie` outside paths
that branch away (e.g., `illegal`'s vectored-interrupts block is
skipped via the MPP-hardwired check before reaching the interrupt
exercise). All (F) fixes targeted the synchronous trap path or
instruction-decode surfaces. Phase 2 (interrupt support) remains
fully untouched.

### Surprises worth carrying forward (recorded in CHAT_HANDOFF.md)

- **rv32mi filename → privilege classification is unreliable.**
  Every rv32mi `.S` file is a `#include` wrapper over a
  `rv64mi/*.S` or `rv64si/*.S` source; rv64si wrappers `#define
  __MACHINE_MODE` which aliases s* CSRs to m* equivalents. So the
  "S-mode-named" tests (`csr` / `sbreak` / `scall` / `ma_fetch`)
  run entirely in M-mode against our M-only impl — they do NOT
  fall into the pre-classified (O) S-mode category. Source-reading
  catches this; filename inspection misses it.

- **The four pre-declared (O) categories yielded zero pre-runtime
  classifications.** All deliberate-non-implementation tests that
  surfaced (`breakpoint`, `pmpaddr`) belonged to NEW categories
  (Sdtrig, PMP) that emerged from the inventory. The pre-class
  discipline is still load-bearing — it pre-prunes tests that
  *would* match the four categories — but the failure mode of
  "pre-class table predicts nothing useful" is real, and the
  source-reading pass is what actually generated value.

- **FENCE-not-decoded was masked by the rv32ui-minimal env.** The
  rv32ui suite passed cleanly because `env/custom`'s RVTEST_PASS/FAIL
  omit `fence;`. Switching to the upstream env/p brought the gap
  into view as the first symptom. Carrying-forward note: any future
  switch from a minimal env to a fuller env should re-run the suite
  expecting prerequisite gaps to surface.

## 2026-05-09 (Phase 1.2.4)

- [feat] Phase 1.2.4 — fifth sub-phase of the Phase 1.2 trap work.
  **First sub-phase since Phase 0.2 with no RTL changes.** The
  deliverable is test infrastructure: a C runtime extension and a
  cross-cutting end-to-end trap test exercising every M-mode
  synchronous cause source built up across 1.2.0-1.2.3 from a
  single binary, plus the FPGA-top harness wiring that runs it.
  (commits `f684326` + `8e30c55` + `b083430`)
- [sw] `sw/crt0.S` extended with an optional `_mtvec_setup` weak
  hook called immediately before `main`. Programs that take traps
  provide a strong `_mtvec_setup` override that writes their
  handler trampoline address into `mtvec` via `csrw`. Programs
  that don't take traps inherit the no-op default and `mtvec`
  stays at whatever reset put there. **mtvec setup happens in
  software, not via testbench backdoor** (PHASE1.2.4_HANDOFF.md
  Decision 5) — the same C binary runs identically on simulation
  and on real hardware.
- [sw] `sw/traps_test.c` — single C program with one dispatcher
  trap handler that decodes `mcause` and routes to per-cause
  observation logic for all eight M-mode synchronous causes:
    - 0  inst_addr_misaligned   — JAL with imm[1]=1 (.word 0x0060006F)
    - 2  illegal_instruction    — CSRRW to RO mvendorid
                                  (.word 0xF1129EF3, per Decision 8 —
                                  only path where the regfile_we gate
                                  is observable from one instruction)
    - 3  breakpoint             — EBREAK
    - 4  load_addr_misaligned   — LH at 0x00010001
    - 5  load_access_fault      — LW from 0xF0000000 (per Decision 9 —
                                  reuses 1.2.2's verified address)
    - 6  store_addr_misaligned  — SH at 0x00010025
    - 7  store_access_fault     — SW to 0xF0000000
    - 11 ecall_m                — ECALL
  Each per-cause handler asserts `mcause`, `mepc`, `mtval` and
  the `mstatus` MIE/MPIE rotation; the trigger PC is captured via
  `lla` of an inline label co-located with each trapping
  instruction so the expected `mepc` is the exact PC the trap
  path writes. **MRET round-trip is implicitly tested by the
  dispatcher pattern** (Decision 4): every cause's handler advances
  `mepc + 4` and MRETs out to continue the test, so progressing
  past cause N requires the round-trip to work. Output is "PASS\r\n"
  over UART after all eight causes verify; "FAIL\r\n" + per-cause
  hex dump otherwise. Direct UART writes — no newlib `printf` —
  to keep the binary small and avoid pulling in unrelated syscall
  stubs.
- [sw] `sw/traps_test_trampoline.S` — standard caller-saved-register
  save/restore wrapper at `mtvec`. `.balign 4` satisfies the
  `mtvec.BASE` alignment (csr_file's `mtvec.MODE` hardwired to 0,
  direct mode). Saves `t0-t6 / a0-a7 / ra` to the trapped program's
  stack, calls `trap_dispatcher` (C function), restores, `mret`s.
  Callee-saved registers (`s0-s11 / sp / gp / tp`) are preserved
  by `trap_dispatcher`'s normal ABI compliance. The trampoline uses
  the trapped program's `sp` — `traps_test.c` never traps from a
  context with `sp` invalid (crt0 sets `sp` before main), so this
  is safe.
- [build] Makefile —
  - `CFLAGS_C` bumped from `-march=rv32i` to `-march=rv32i_zicsr`
    so the C inline asm in `traps_test.c` can use `csrr`/`csrw`
    on `mcause`/`mepc`/`mtval`/`mstatus` directly. Harmless for
    `hello_c.c` — the toolchain just permits the encoding.
  - New `c-traps` target mirrors the existing `c` build pattern,
    pulls in `crt0.S` + `traps_test.c` + `traps_test_trampoline.S`,
    skips `syscalls.c` (unused — `traps_test.c` uses direct UART
    writes). Emits `sim/traps_test.hex` (IMEM, ~1.7 KB .text) and
    `sim/traps_test_dmem.hex` (DMEM, ~280 bytes .rodata + .data +
    bss reservation).
  - New `sim-fpga-traps` target mirrors `sim-fpga-c` against
    `tb/tb_fpga_top_traps.v`.
- [tb] `tb/tb_fpga_top_traps.v` — duplicate-and-rename of
  `tb/tb_fpga_top_c.v` (the existing IMEM_INIT/DMEM_INIT
  C-program TB template). IMEM depth 1024 words (4 KB) — sized
  for `traps_test.elf` .text. Captures 6 UART bytes; expects
  "PASS\r\n". On FAIL the per-cause hex dump emitted by
  `traps_test.c` shows up in the RX log preceding the FAIL banner,
  pinpointing which cause(s) misbehaved.
- [tb] `tb/tb_compliance.v`: **NO extension required for 1.2.4.**
  The harness reads its program image into the unified 16 KB
  byte-addressed memory, fetches instructions combinationally,
  and runs `_start` naturally with no fast-forward — so a
  trap-taking program's `_mtvec_setup` would run as expected,
  and PC redirects to handler addresses are not flagged as
  anomalies. The harness does NOT instantiate `csr_file` (rv32ui
  exercises no CSR ops, so trap-entry outputs are tied off in
  the dut instance), which means actual trap-taking under
  `tb_compliance` requires CSR-file integration. **That wiring
  lands in 1.2.5** alongside the rv32mi env work and is correctly
  out of scope for 1.2.4. `traps_test.c` runs via
  `sim-fpga-traps` on the FPGA-top harness (which has `csr_file`
  wired through `fpga_top` since 1.1), so the 1.2.4 deliverable
  is unblocked.
- [doc] Phase 1.2.4 closes the cross-cutting validation step for
  the synchronous trap path. The harness extensions added here —
  C runtime hook for software-driven `mtvec` setup, dispatcher /
  trampoline pattern, end-to-end FPGA-top trap-taking TB — are
  the foundation for **1.2.5's rv32mi compliance bringup**, which
  will reuse the same software-driven-mtvec idiom inside a
  custom rv32mi env and add CSR-file integration to
  `tb_compliance` so the existing harness can host trap-taking
  rv32mi programs. 1.2.4 deliberately did NOT pre-build any
  rv32mi env, expected-failures classification, or compliance
  triage scaffolding — that's 1.2.5's clean-slate job, informed
  by what the C dispatcher pattern surfaced.
- [verify] Cross-cutting validation —
  - `sim-fpga-traps` PASS, "PASS\r\n" received correctly.
  - All 10 carry-forward sim-fpga tests PASS (csr / ecall /
    ebreak / illegal / misaligned / misaligned-load /
    misaligned-store / access-fault / mret / ecall-mret-roundtrip).
  - All 19 unit testbenches PASS.
  - rv32ui regression 37/37, **byte-identical cycle counts to
    `phase1.2.3-complete`** (and therefore to `phase1.1-complete`
    through five sub-phases of trap work). The runtime change
    does not affect rv32ui — those programs link standalone
    without `crt0.S` and the `-march` bump only enables an opt-in
    instruction set the rv32ui toolchain path doesn't reach.
  - Verilator lint clean.
  - `git diff phase1.2.3-complete -- rtl/` empty: no RTL files
    modified.

## 2026-05-08 (Phase 1.2.3)

- [feat] Phase 1.2.3 — fourth and final sub-phase of the Phase 1.2
  synchronous trap work. Activates MRET. The skeleton work in 1.2.0
  (PC-mux `mepc_i` declared but trap-return-select tied `1'b0`;
  `csr_file.trap_return` declared but tied `1'b0` in fpga_top) was
  specifically designed so that activation in this sub-phase is a
  literal-tie-to-live-signal swap on the trap-return path, plus a
  small decode addition, plus a single-term carve-out chain
  extension. `csr_file.v` is byte-identical to phase1.2.2-complete —
  the trap-return interface has been correct since Phase 1.0; this
  sub-phase only drives an existing input. End-to-end consequence:
  trap round-trip works for the first time. (commits `705e05a` +
  `f88aa47` + `a15cb34`)
- [rtl] `rtl/rv32i_core.v` —
  - New inline MRET decode at the top level alongside `ecall_m` /
    `ebreak_m`:
      `mret_m = (opcode == OP_SYSTEM) && (funct3 == 3'b000)
             && (csr_addr_f == 12'h302) && (rs1_addr == 5'b0)
             && (rd_addr == 5'b0)`
    Continues the convention from 1.2.0/1.2.1: trap-instruction
    decode happens at the use site (here), not in `control.v`.
  - `illegal_inst_o` carve-out chain extended with a single
    `& ~mret_m` term:
      `illegal_inst_o = csr_illegal_i
                     | (illegal_system & ~ecall_m & ~ebreak_m & ~mret_m)
                     | illegal_opcode`
    **The carve-out chain is now COMPLETE for all M-mode SYSTEM
    funct3=0 instructions implemented in this CPU**
    (ECALL 1.2.0 / EBREAK 1.2.1 / MRET 1.2.3). Future instructions
    in this family (Zihintntl variants, hypothetical privileged
    additions) MUST extend this chain with their own explicit
    `~<inst>_m` term per the established convention. They cannot
    silently inherit "is illegal" by being unrecognized — that is
    the bug this convention prevents — and they cannot silently
    inherit "is legal" by failing to carve out. SYSTEM instructions
    with funct3 != 0 take separate decode paths and are unaffected
    by this chain. The chain comment at the carve-out site now
    documents this state.
  - PC-mux trap-return select activated. The previously dead-pathed
    `trap_return_select_dead = 1'b0` literal is replaced with `mret_m`:
      `pc_next = trap_enter_w ? mtvec_i :
                 mret_m       ? mepc_i :
                 ctrl_jump    ? jump_target :
                 branch_taken ? branch_target :
                                pc_plus4`
    Priority is structurally `trap_enter > mret > jump > branch > pc+4`.
    `trap_enter` and `mret_m` cannot both fire on the same cycle in
    M-only operation — MRET itself does not synchronously fault — but
    the priority is structurally correct anyway.
  - New top-level output port `trap_return_o`. Driven directly from
    `mret_m`. Wired through `fpga_top.v` to `csr_file.trap_return`,
    replacing the previous `1'b0` tie. csr_file's existing 1.0
    implementation handles the `MIE <- MPIE; MPIE <- 1` rotation on
    `trap_return` and enforces the
    `trap_enter > trap_return > csr_write_op` priority internally.
  - **MRET retires.** Per RISC-V spec, `minstret` counts retired
    instructions; the spec does not carve out MRET. The existing
    skeleton handles this without modification because `trap_enter`
    and `trap_return` are separate signals: on an MRET cycle,
    `trap_enter=0`, `trap_return=1`, and
    `instret_tick = !rst & ~trap_enter` pulses normally. The
    asymmetry with the trapping instruction (which does NOT retire)
    is correct — the trapping instruction was aborted into the
    handler; MRET completes and exits the handler. The new TEST 37
    in `tb_rv32i_core_csr` is the load-bearing regression-protection
    test: it asserts `instret_tick` and `trap_return` fire on the
    same cycle. If a future change mistakenly gates `instret_tick`
    on `~trap_return`, that probe goes to 0 and TEST 37 fails
    immediately.
- [rtl] `rtl/fpga_top.v` —
  - New internal wire `core_trap_return` connecting the core's new
    `trap_return_o` output to `u_csr_file.trap_return`. The previous
    `1'b0` tie on the csr_file instance is removed. No waivers added
    or removed; `mstatus_mie_i` keeps its UNUSEDSIGNAL waiver
    (Phase 2 interrupts is its consumer).
- [rtl] `rtl/csr_file.v` — **unchanged. Byte-identical to
  `phase1.2.2-complete`.** The `trap_return` interface has been
  correct since Phase 1.0 and is exercised by `tb_csr_file` Category 7
  (Trap return); this sub-phase only drives an existing input.
- [tb] `tb/tb_rv32i_core_csr.v` — 4 new directed tests (36-39),
  28 new assertions; total 153/153 (was 125/125):
  - Wired the core's new `trap_return_o` into `csr_file.trap_return`
    (replacing the prior `1'b0` tie). Added `seen_trap_return` and
    `mret_with_instret_observed` probes alongside the existing
    trap-enter probes.
  - 36: **MRET decode + carve-out + behavior** — drives MRET outside
    any trap context with mstatus.MIE=0/MPIE=1; verifies
    `illegal_inst_o` quiet, `trap_enter` never pulsed, `trap_return`
    pulsed, PC redirected to `mepc`, MIE rotated from MPIE, MPIE=1.
  - 37: **MRET retires** — load-bearing regression-protection. Asserts
    `mret_with_instret_observed=1` and that `minstret` advanced
    through the MRET cycle (reads minstret in the handler post-redirect
    via CSRRS; expected value 5 = four setup retires + the MRET).
  - 38: **End-to-end ECALL -> handler -> MRET -> resume roundtrip**.
    Architectural milestone test for Phase 1.2.3. ECALL traps to
    `mtvec`; handler reads `mepc`, advances by 4, writes back, MRETs;
    resumed program executes the post-ECALL sentinel `addi x10, x0,
    0x123`. Asserts ECALL did NOT retire, MRET DID retire, mstatus.MIE
    rotated back to 1, mepc reflects the handler's `+4` update.
  - 39: **MRET while not in a trap (mstatus rotation only)** — bare
    MRET from reset state (MIE=0, MPIE=0). mstatus rotates
    (MIE<-0, MPIE<-1) and PC redirects to mepc. rv32mi compliance
    occasionally invokes MRET in this configuration; verifying it is
    well-defined here protects future Phase 1.2.4 work.
- [tb/sw] New end-to-end FPGA-top tests:
  - `sw/mret_test.S` + `tb/tb_fpga_top_mret.v` + Makefile target
    `sim-fpga-mret`. Minimal MRET smoke test on the synthesized SoC.
    Sets mtvec to a fail handler (so any spurious trap is caught),
    sets mepc to the resume target, prearms mstatus, executes MRET,
    verifies the rotation and prints PASS over UART.
  - `sw/ecall_mret_roundtrip_test.S` +
    `tb/tb_fpga_top_ecall_mret_roundtrip.v` + Makefile target
    `sim-fpga-ecall-mret-roundtrip`. **Architectural milestone**:
    ECALL -> handler reads mepc, adds 4, writes back, MRET ->
    resumed program prints PASS. Proves the round-trip works
    end-to-end through the synthesized SoC including UART output.
- [doc] Phase 1.2.3 closes the synchronous trap work. Every M-mode
  synchronous cause source is wired and observably tested
  (inst_addr_misaligned, illegal_inst, ebreak, load_addr_misaligned,
  load_access_fault, store_addr_misaligned, store_access_fault,
  ecall_m). The trap round-trip path is end-to-end tested. The
  M-mode SYSTEM funct3=0 carve-out chain is complete. Phase 1.2.4
  is the cross-cutting validation step (rv32mi compliance setup +
  `sw/traps_test.c` C-level trap handler) — no new RTL there; just
  exercising the work landed across 1.2.0-1.2.3.

## 2026-05-07 (Phase 1.2.2)

- [feat] Phase 1.2.2 — third sub-phase of the Phase 1.2 trap work.
  Lights up the four memory-side cause sources on the encoder built
  in 1.2.0/1.2.1: `load_addr_misaligned` (cause 4),
  `load_access_fault` (cause 5), `store_addr_misaligned` (cause 6),
  `store_access_fault` (cause 7). The at-issue causes (5 / 7) drive
  the structural pre-issue/at-issue gate refactor — the most
  architecturally significant change of the sub-phase. (commits
  `c2a506a` + `dd8c9b6` + `91de608`)
- [rtl] `rtl/rv32i_core.v` —
  - LSU-side misalignment detection added at the address-compute
    stage. Combinational on `dmem_addr` + `funct3` + `mem_read` /
    `mem_write`:
      `load_addr_misaligned_w  = mem_read  & ((F3_WORD && addr[1:0]!=0)
                                            | ((F3_HALF|F3_HALFU) && addr[0]!=0))`
      `store_addr_misaligned_w = mem_write & ((F3_WORD && addr[1:0]!=0)
                                            | (F3_HALF && addr[0]!=0))`
    LB/LBU/SB cannot misalign by construction. The `mem_read` /
    `mem_write` qualifier prevents non-LSU instructions (whose
    `dmem_addr` carries arbitrary bits) from tripping detection.
    Wired into the encoder's `trap_load_addr_misaligned` and
    `trap_store_addr_misaligned` cause inputs (replacing the
    `1'b0` ties).
  - **Pre-issue / at-issue gate refactor.** New intermediate signals:
      `pre_issue_trap_w = inst_addr_misaligned | illegal_inst | ebreak
                       | load_addr_misaligned | store_addr_misaligned
                       | ecall`
      `load_access_fault_w  = bus_error_i & dmem_re & ~load_addr_misaligned_w`
      `store_access_fault_w = bus_error_i & dmem_we & ~store_addr_misaligned_w`
      `at_issue_trap_w  = load_access_fault_w | store_access_fault_w`
      `trap_enter_w     = pre_issue_trap_w | at_issue_trap_w`
    Issue-side gates (`dmem_re` / `dmem_we`) now use
    `~pre_issue_trap_w` (NOT `~trap_enter_w`); latch-side gates
    (`regfile_we`, `instret_tick`) keep using `~trap_enter_w`.
    This breaks the combinational cycle that would otherwise occur
    between `bus_error_i` and `dmem_re`/`dmem_we`: pre-issue causes
    suppress the bus access; at-issue causes catch a `bus_error_i`
    that already fired in the same cycle, before regfile / instret
    can latch.
  - `trap_enter_w` converted from a `reg` driven inside the priority
    encoder always block to a continuous assign of
    `pre_issue_trap_w | at_issue_trap_w`. The always block now drives
    only `trap_cause_code` and `trap_tval_w` from the priority chain.
    Functional behavior is identical to the prior reg-based form —
    the priority chain set `trap_enter_w=1` on any active cause; the
    OR achieves the same in fewer lines.
  - `trap_tval` mux: four `32'b0` literal ties → `dmem_addr` for
    causes 4 / 5 / 6 / 7. All four memory-side causes use the same
    underlying signal; the priority encoder selects which one becomes
    `mtval`. `csr_file` does not mask `trap_tval` (carry-forward from
    1.2.1) so the misaligned/unmapped low bits land in `mtval`
    unmodified — that is the relevant data per spec.
  - New top-level input port `bus_error_i` (1 bit). Wired from
    `wb_interconnect.bus_error_o` in `fpga_top.v`. Documented at the
    port and in the bus-outputs section as combinational + same-cycle.
  - The at-issue source composition uses the GATED `dmem_re` /
    `dmem_we` (post `~pre_issue_trap_w`), so a misaligned LW that
    would otherwise hit an unmapped address has its bus issue
    suppressed; `bus_error_i` does not even fire on that cycle.
    Mutual exclusion is enforced at the bus layer in addition to the
    encoder's priority-by-cause-code (cause 4 < cause 5). The
    `~load_addr_misaligned_w` / `~store_addr_misaligned_w` qualifiers
    in the at-issue source are defense in depth at zero hardware cost.
- [rtl] `rtl/fpga_top.v` —
  - New local wire `ic_bus_error` connecting
    `wb_interconnect.bus_error_o` to `rv32i_core.bus_error_i`.
  - The PINCONNECTEMPTY scope around the `wb_interconnect` instance
    is removed (the previously-empty `bus_error_o` pin is now
    connected). The `mstatus_mie_i` UNUSEDSIGNAL waiver on the core's
    port stays in place — Phase 2 interrupts is its consumer.
- [rtl] `rtl/csr_file.v` — unchanged. The trap interface continues to
  be correct; this sub-phase only adds new drivers feeding it.
- [tb] `tb/tb_rv32i_core_csr.v` — 11 new directed tests (25-35),
  44 new assertions; total 125/125 (was 81/81):
  - 25-28: `load_addr_misaligned` via LH at addr[0]=1 and via LW for
    each of addr[1:0]={01,10,11}. Each test verifies `mepc` / `mcause=4`
    / `mtval=addr` and asserts `seen_dmem_re=0` (pre-issue gate
    suppressed the bus access).
  - 29: `store_addr_misaligned` via SH at addr[0]=1 + observable
    dmem_we gate. Pre-loads `tb_dmem[5]=0xCAFEBABE` (sentinel at the
    aligned address); attempts an SH to addr=0x15 with would-be data
    0x1234. The TB's width-aware DMEM write path would corrupt
    `tb_dmem[5][15:0]` to `0x1234` if the gate were broken. With the
    gate intact, dmem_we never asserts and the sentinel survives —
    observable proof of the dmem_we gate.
  - 30-32: `store_addr_misaligned` via SW for each of
    addr[1:0]={01,10,11}.
  - 33: `load_access_fault` via LW to 0xF0000000. Bus-error mock
    window covers 0xF0000000-0xF000FFFF; the at-issue path catches
    the error before regfile_we latches. Verifies `x5` sentinel
    preserved (regfile_we gate observable on the at-issue path) and
    PC redirected to mtvec.
  - 34: `store_access_fault` via SW to 0xF0000000.
  - 35: **Mutual-exclusion test.** LW to 0xF0000001 — both misaligned
    AND unmapped. Pre-issue gate suppresses dmem_re; bus_error_i does
    not assert; the encoder's priority-by-cause-code would also pick
    4 over 5 in any event. Verifies `mcause=4` (NOT 5). This is the
    load-bearing verification that the pre-issue/at-issue split
    correctly enforces mutual exclusion, AND it is implicit
    confirmation that the loop-break worked: a combinational cycle
    would either oscillate or collapse `bus_error_i` to 0 and fail
    the access-fault tests above.
  - New encoders: `enc_load` (I-type) + `lh` / `lw` wrappers,
    `enc_store` (S-type) + `sh` / `sw` wrappers.
  - New TB infrastructure: `tb_dmem` model (64-word DMEM with
    width-aware SW/SH/SB write path), programmable bus-error mock
    (`bus_err_active` / `bus_err_lo` / `bus_err_hi`), `seen_dmem_we`
    / `seen_dmem_re` observability latches, `clear_dmem` task,
    `begin_test` resets all of these per-test.
- [tb] `tb/tb_rv32i_core.v`, `tb/tb_compliance.v` — `bus_error_i`
  tied to `1'b0` on the core instance (rv32ui programs only access
  mapped DMEM and never trigger an at-issue trap; deterministic
  tie-off keeps the access-fault path resolved to 0).
- [sw] `sw/misaligned_load_test.S` (new) — end-to-end LH-at-odd-half-
  word demo. Triggers cause 4; handler verifies `mepc=ld_pc`,
  `mcause=4`, `mtval=0x00010001`, MIE/MPIE rotation, prints
  `PASS\r\n` over UART.
- [sw] `sw/misaligned_store_test.S` (new) — end-to-end SH-at-odd-half-
  word demo + observable dmem_we gate. Pre-stores `0xCAFEBABE` at
  `0x00010024` via legal SW, then attempts SH at `0x00010025`
  (odd). The handler reads back the aligned location to confirm
  the sentinel survived (gate observability test through the
  synthesized SoC, not just the unit TB). Verifies `mepc`,
  `mcause=6`, `mtval=0x00010025`, MIE/MPIE.
- [sw] `sw/access_fault_test.S` (new) — end-to-end LW-from-unmapped-
  address demo. Triggers cause 5 by issuing LW from `0xF0000000`
  (well outside every wb_interconnect slave window). Pre-loads `t4
  = 0xDEADBEEF` as a sentinel; the handler verifies `t4` is
  unchanged after the trap (regfile_we gate proven on the at-issue
  path through the synthesized SoC), plus `mepc`, `mcause=5`,
  `mtval=0xF0000000`, MIE/MPIE.
- [tb] `tb/tb_fpga_top_misaligned_load.v`,
  `tb/tb_fpga_top_misaligned_store.v`,
  `tb/tb_fpga_top_access_fault.v` (new) — duplicate-and-rename of
  `tb_fpga_top_misaligned.v` for each new asm test. Each loads its
  hex image, preloads PASS/FAIL strings into DMEM, captures 6 UART
  bytes, expects `PASS\r\n`.
- [build] `Makefile` — three new targets: `sim-fpga-misaligned-load`,
  `sim-fpga-misaligned-store`, `sim-fpga-access-fault`, mirroring
  `sim-fpga-misaligned`. Added to `.PHONY`.
- [docs] `docs/tech_debt.md` — new "Phase 4 dependencies" section
  with two entries: (1) at-issue trap assumes `bus_error_i` is
  combinational; (2) at-issue trap assumes single-cycle bus
  completion (`WB_USE_STALL=0`). Filed as separate items so a
  future engineer addressing one does not assume it covers the other
  — the two assumptions can break independently. The full rationale
  + dependency chain is also pinned in-place at the bus-outputs
  comment in `rtl/rv32i_core.v`.

### Side-effect gate observability status

After 1.2.2, all four 1.2.0 side-effect gates have observable test
coverage. The "skeleton gate" framing retires after this sub-phase.

| Gate           | Status this sub-phase                                    |
|----------------|---------------------------------------------------------|
| `instret_tick` | Carry-over from 1.2.0 — `trap_with_instret_observed`    |
|                | latch in tb_rv32i_core_csr (tests 15 / 18 / 19 / 25+).  |
| `regfile_we`   | Carry-over from 1.2.1 (test 19 sentinel). 1.2.2         |
|                | adds another observability point: at-issue trap with    |
|                | rd preserved (test 33: `x5=0xCAFEB000` survives the     |
|                | LW-unmapped trap; sw/access_fault_test.S t4 sentinel    |
|                | survives end-to-end).                                   |
| `dmem_we`      | Newly observable in 1.2.2 — sentinel preservation       |
|                | through misaligned SH (test 29 + sw/misaligned_store_   |
|                | test.S). The pre-issue gate (post-refactor) is what     |
|                | suppresses the would-be write.                          |
| `dmem_re`      | Newly observable in 1.2.2 — `seen_dmem_re=0` latched    |
|                | through tests 25 / 26 / 27 / 28 / 35 (no bus access     |
|                | issued for any misaligned-load cycle).                  |

### Verification

- `verilator --lint-only -Irtl -Wall --top-module fpga_top rtl/*.v`:
  clean. The 1.2.1 `bus_error_o` PINCONNECTEMPTY scope on
  `wb_interconnect` is removed; the `mstatus_mie_i` waiver on the
  core's port stays in place (Phase 2 interrupts).
- `make sim MOD=rv32i_core_csr`: 125/125 PASS, "ALL TESTS PASSED"
  (was 81/81 in 1.2.1).
- `make sim MOD=csr_file`: 63/63 PASS (Phase 1.0 unchanged).
- All 19 unit testbenches: PASS, no regression.
- `cd tests && make run-all`: 37/37 PASS, all 37 cycle counts
  byte-identical to `phase1.2.1-complete` after each of the three
  RTL/TB commits. rv32ui programs do not contain misaligned
  loads/stores or accesses to unmapped addresses (programs are
  well-formed by design), so lighting up these four cause sources
  produces zero drift on rv32ui — the load-bearing regression check
  for this sub-phase.
- `make sim-fpga-misaligned-load`: PASS, `PASS\r\n` end-to-end.
- `make sim-fpga-misaligned-store`: PASS, `PASS\r\n` end-to-end with
  the `*(0x00010024) = 0xCAFEBABE` sentinel preserved through the
  SH-at-odd trap.
- `make sim-fpga-access-fault`: PASS, `PASS\r\n` end-to-end with
  the `t4 = 0xDEADBEEF` sentinel preserved through the LW-unmapped
  trap. Implicit combinational-cycle smoke test: a hung or
  oscillating loop would have prevented PASS from printing.
- `make sim-fpga-{ecall,ebreak,illegal,misaligned,csr}`: all PASS
  (1.2.0 + 1.2.1 + Phase 1.1 regressions — no change).

### Surprises / notes for 1.2.3

- **`trap_enter_w` reg → wire conversion.** Decided mid-refactor.
  The 1.2.0/1.2.1 priority encoder set `trap_enter_w=1` at the head
  of the always block then cleared it in the else branch — equivalent
  to OR-of-cause-inputs. With pre_issue / at_issue intermediate
  signals introduced explicitly, the OR became explicit too. The
  always block is now cleaner (drives only cause_code / tval).
  Encoder priority semantics unchanged.
- **Mock bus-error vs. real interconnect.** The unit TB
  (tb_rv32i_core_csr) uses a programmable bus-error mock + tb_dmem
  model rather than instantiating the real `wb_interconnect`. The
  end-to-end sim-fpga-access-fault test exercises the real
  interconnect path. Both layers PASS, so the at-issue model is
  validated against the real combinational `bus_error_o = unmapped`
  inside `wb_interconnect.v`.
- **Phase 4 dependency framing.** Two distinct assumptions
  (combinational `bus_error_i` AND single-cycle bus completion)
  filed as SEPARATE tech-debt entries. The handoff explicitly
  flagged them as separable, and the failure modes are different
  (one breaks regfile_we ordering; the other breaks bus protocol).
  Filed accordingly per Decision 12 in the 1.2.2 handoff.
- **Carve-out chain unchanged.** None of the four 1.2.2 cause
  sources is in the SYSTEM-funct3=0 family. `illegal_inst_o` keeps
  the 1.2.1 form (`csr_illegal | (illegal_system & ~ecall_m &
  ~ebreak_m) | illegal_opcode`). MRET extends it in 1.2.3.
- **Speculative `reg_write |= illegal_opcode` hardening NOT
  pursued.** Per Decision 13 in the 1.2.2 handoff and project
  convention "don't add code on speculation". Revisit only if a
  future cause source actually requires it.

## 2026-05-07 (Phase 1.2.1)

- [feat] Phase 1.2.1 — second sub-phase of the Phase 1.2 trap work. Lights
  up three new cause sources on the encoder skeleton built in 1.2.0:
  EBREAK (cause 3), illegal_inst (cause 2), and inst_addr_misaligned
  (cause 0). Promotes `trap_tval` from a single tied-zero wire to a
  per-cause priority mux, again as skeleton-first (four cause→tval
  pairs driven this sub-phase, four tied 0 until 1.2.2). The four
  side-effect gates from 1.2.0 carry forward unchanged — none of the
  three new causes is at-issue, so the pre-issue / at-issue gate
  refactor remains a 1.2.2 task. (commits `22dce4b` + `7e03aba` +
  `b029b61`)
- [rtl] `rtl/rv32i_core.v` —
  - EBREAK decoded inline at the core top level next to ECALL (SYSTEM,
    funct3=000, imm12=0x001, rs1=0, rd=0). Mirrors the 1.2.0 ECALL
    pattern — `control.v` stays minimal; the carve-out happens at the
    use site.
  - Carve-out chain extended to a load-bearing convention. The
    expression in `illegal_inst_o`:
    `csr_illegal_i | (illegal_system & ~ecall_m & ~ebreak_m) |
    illegal_opcode`. ECALL was carved out 1.2.0; EBREAK is carved out
    here; MRET will be carved out 1.2.3 (`& ~mret_m`). The convention
    comment in the file warns that future SYSTEM-funct3=0 instructions
    (FENCE.I, future Zicsr/Zihint encodings) must extend the chain
    explicitly — they cannot silently inherit "is legal" by being
    unrecognized, and must not silently inherit "is illegal" by
    failing to carve out.
  - Two encoder inputs lit up: `trap_illegal_inst <= illegal_inst_o`
    (was `1'b0`) and `trap_ebreak <= ebreak_m` (was `1'b0`). No
    combinational loop: `illegal_inst_o` depends only on decode-side
    signals, not on `trap_enter_w`.
  - `inst_addr_misaligned` detection added at the branch/jump target
    compute. Combinational: `(ctrl_jump && jump_target[1:0] != 0) ||
    (branch_taken && branch_target[1:0] != 0)`. Wired into the
    encoder's `inst_addr_misaligned` cause input. JALR's bit-0 mask
    (`& 32'hFFFFFFFE`) was already spec-correct in the existing core
    (no fix needed) — only `target[1]` participates in the JALR check.
    JAL's J-imm and branch's B-imm both have `imm[0]=0` by encoding,
    so `target[0]` is always 0; the `[1:0] != 0` check reduces to
    `target[1] != 0` in practice but the spec form is kept (optimizer
    folds it).
  - `trap_tval` promoted from a single tied-zero wire to a per-cause
    priority mux, co-driven by the same always block as the cause
    encoder (cause and tval always consistent). Eight cause→tval
    pairs declared (skeleton-first):
      `inst_addr_misaligned -> misaligned_target` (the would-be PC)
      `illegal_inst         -> instr` (the 32-bit instruction word)
      `ebreak               -> 0`  (per spec)
      `load_addr_misaligned -> 0`  (1.2.2: faulting load addr)
      `load_access_fault    -> 0`  (1.2.2)
      `store_addr_misaligned-> 0`  (1.2.2)
      `store_access_fault   -> 0`  (1.2.2)
      `ecall_m              -> 0`  (per spec)
    `csr_file` does not mask `trap_tval` (unlike `trap_pc`), so for
    `inst_addr_misaligned` the misaligned target's low bits reach
    `mtval` unmodified — that is the relevant data per spec.
- [rtl] `rtl/fpga_top.v` — `core_illegal_inst` UNUSEDSIGNAL waiver
  removed; the wire is deleted and the core's `illegal_inst_o` port
  left empty on the instance under the existing PINCONNECTEMPTY scope
  around `u_core`. The encoder consumes the signal internally; the
  `trap_*_o` ports already expose the resulting trap state to the
  top. `bus_error_o` UNUSEDSIGNAL waiver remains in place — 1.2.2
  consumes it.
- [rtl] `rtl/csr_file.v` — unchanged (the trap interface is correct;
  this sub-phase only adds new drivers feeding it, again).
- [tb] `tb/tb_rv32i_core_csr.v` — seven new directed tests (18-24),
  41 new assertions; total 81/81 (was 40/40):
  - 18: EBREAK trap entry — `mepc` captures EBREAK PC, `mcause=3`,
    `mtval=0`, MIE/MPIE rotation, PC redirected to `mtvec`,
    `instret_tick` gated, `illegal_inst_o` quiet (EBREAK is now legal
    by carve-out).
  - 19: illegal_inst trap entry + observable regfile_we gate. Trigger
    is CSRRW to RO `mvendorid` (the only path in the current core
    where `illegal_inst_o` pulses while the decoder also asserts
    `reg_write=1`, since `is_csr=1`). Pre-loaded sentinel `x5 =
    0xDEADBEEF` survives the trap cycle — observable proof that the
    1.2.0 `regfile_we` skeleton gate is load-bearing on this path.
    Verifies `mtval = 0xF1129EF3` (the encoded illegal instruction
    word).
  - 20: inst_addr_misaligned via JAL with imm[1]=1.
  - 21: inst_addr_misaligned via taken BEQ with imm[1]=1.
  - 22: BEQ NOT-taken with misaligned imm — must NOT trap (gating on
    `branch_taken` proven; misaligned target is never fetched).
  - 23: inst_addr_misaligned via JALR with target[1]=1 (after the
    spec bit-0 mask).
  - 24: JALR with imm[0]=1 masked → must NOT trap. Also verifies
    JALR's `pc_plus4` writeback completes.
  - New encoders: `enc_jal` (J-type), `enc_jalr` (I-type), `enc_branch`
    + `beq` (B-type). New `EBREAK` localparam.
  - `begin_test` / `expect_eq32` / `expect_bool` desc-field width
    bumped from `[8*48-1:0]` to `[8*64-1:0]` (1.2.0 closure flagged
    48 as too narrow for trap-cycle test names; 64 going forward per
    the 1.2.1 handoff).
- [sw] `sw/ebreak_test.S` (new) — end-to-end EBREAK trap-entry demo,
  duplicate-and-rename of `ecall_test.S`. Verifies `mepc`, `mcause=3`,
  `mtval=0`, MIE/MPIE inside the handler, prints `PASS\r\n` over UART.
- [sw] `sw/illegal_test.S` (new) — end-to-end illegal-instruction
  trap demo. Trigger: `csrrw t4, mvendorid, t0` (RO write attempt).
  Pre-loads `t4 = 0xDEADBEEF` as the sentinel; the handler verifies
  `t4` is unchanged after the trap (regfile_we gate proven through
  the synthesized SoC), plus `mepc`, `mcause=2`, `mtval=0xF1129EF3`,
  MIE/MPIE.
- [sw] `sw/misaligned_jump_test.S` (new) — end-to-end
  inst_addr_misaligned demo. Exercises JALR-with-bit-0-masked and
  BEQ-not-taken-misaligned inline as must-NOT-trap cases (PC
  progression past them is implicit verification), then triggers a
  JAL-misaligned trap. Handler verifies `mepc=jal_pc`, `mcause=0`,
  `mtval=jal_pc+6`. The misaligned BEQ and JAL are emitted as raw
  `.word` (GAS won't emit a B-imm or J-imm with bit 1 set against
  word-aligned labels). For the BEQ-taken / JALR-target[1]=1 trap
  variants and the JALR-imm[0]-masked no-trap variant, see
  `tb_rv32i_core_csr.v` tests 21 / 23 / 24 — the directed TB covers
  all variants with cycle-precision checks.
- [tb] `tb/tb_fpga_top_ebreak.v`, `tb/tb_fpga_top_illegal.v`,
  `tb/tb_fpga_top_misaligned.v` (new) — duplicate-and-rename of
  `tb_fpga_top_ecall.v` for each new asm test. Each loads its hex
  image, preloads PASS/FAIL strings into DMEM, captures 6 UART bytes,
  expects `PASS\r\n`.
- [build] `Makefile` — three new targets `sim-fpga-ebreak`,
  `sim-fpga-illegal`, `sim-fpga-misaligned`, mirroring
  `sim-fpga-ecall`. Added to `.PHONY`.
- [docs] No standalone doc updates this sub-phase. The carve-out
  chain convention is documented in the `illegal_inst_o` comment in
  `rv32i_core.v`. The "csr_file does not mask trap_tval" property is
  noted alongside the `trap_tval` mux in the same file.

### Side-effect gate observability status

The four 1.2.0 side-effect gates (`!trap_enter_w` masking
`regfile_we` / `dmem_we` / `dmem_re` / `instret_tick`) carry forward
unchanged in 1.2.1.

| Gate           | Status this sub-phase                                |
|----------------|-----------------------------------------------------|
| `instret_tick` | Observably tested (carry-over from 1.2.0; verified  |
|                | again in tests 18 / 19 — `trap_with_instret_observed`|
|                | latch).                                              |
| `regfile_we`   | Newly observable in 1.2.1 via the illegal_inst      |
|                | sentinel test (TB test 19, sw/illegal_test.S).      |
| `dmem_we`      | Skeleton — none of the three 1.2.1 cause sources    |
|                | exercises a memory write. 1.2.2's misaligned-store  |
|                | trap will light it up.                              |
| `dmem_re`      | Skeleton — same. 1.2.2's misaligned-load trap.       |

### Verification

- `verilator --lint-only -Irtl -Wall --top-module fpga_top rtl/*.v`:
  clean. The 1.2.0 `core_illegal_inst` UNUSEDSIGNAL waiver in
  `fpga_top.v` is removed in this sub-phase; the `bus_error_o`
  waiver on the `wb_interconnect` output stays in place (1.2.2's
  consumer).
- `make sim MOD=rv32i_core_csr`: 81/81 PASS, "ALL TESTS PASSED" (was
  40/40 in 1.2.0).
- `make sim MOD=csr_file`: 63/63 PASS (Phase 1.0 unchanged).
- All 19 unit testbenches: PASS, no regression.
- `cd tests && make run-all`: 37/37 PASS, all 37 cycle counts
  byte-identical to `phase1.2.0-complete` (and therefore to
  `phase1.1-complete`) after each of the three RTL/TB commits. No
  rv32ui test contains an illegal opcode, EBREAK, or a misaligned
  branch/jump target, so lighting up these three cause sources
  produces zero drift on rv32ui — the load-bearing regression check
  for this sub-phase.
- `make sim-fpga-ebreak`: PASS, `PASS\r\n` received end-to-end. TB
  prints `*** EBREAK FPGA TEST PASSED -- "PASS\r\n" received
  correctly ***`.
- `make sim-fpga-illegal`: PASS, `PASS\r\n` received end-to-end with
  the `t4 = 0xDEADBEEF` sentinel preserved through the trap cycle.
  TB prints `*** ILLEGAL_INST FPGA TEST PASSED -- sentinel x29
  preserved through trap ***`.
- `make sim-fpga-misaligned`: PASS, `PASS\r\n` received end-to-end.
  TB prints `*** MISALIGNED_JUMP FPGA TEST PASSED -- JAL trap +
  inline non-trap cases verified ***`.
- `make sim-fpga-ecall`: PASS (1.2.0 regression — no change).

### Surprises / notes for 1.2.2

- **JALR bit-0 masking.** Already spec-correct in the existing core
  (`(rs1 + imm) & 32'hFFFFFFFE` at the JAL/JALR target compute). No
  fix was needed for the inst_addr_misaligned detection — only
  `target[1]` participates in the JALR check. The 1.2.1 handoff
  flagged this as a potential pre-existing bug to fix; it was not.
- **Sentinel-test design tension.** The handoff specified using a
  true "illegal opcode" with non-zero `rd` to observably exercise
  the `regfile_we` gate. In the existing core, `control.v`'s default
  branch keeps `reg_write=0` for unrecognized opcodes — so a true
  unknown-opcode trigger does not exercise the gate observably. The
  CSR-illegal path (CSRRW to a RO CSR) is the only path where
  `illegal_inst_o` pulses while `reg_write` would otherwise be 1
  (since `is_csr=1` for SYSTEM funct3 != 0). Used that path in both
  the directed TB test (test 19) and the asm test
  (`sw/illegal_test.S`). A future hardening could OR
  `illegal_opcode` into the `regfile_we` suppression explicitly so
  that true unknown opcodes also carry `reg_write=1` heading into
  the gate (making the gate's protection uniform across all
  illegal-instruction paths) — out of scope for 1.2.1, candidate
  for 1.2.2 alongside the at-issue gate refactor.
- **trap_tval mux structure.** Built as a parallel cause→tval
  priority chain inside the same `always @(*)` block as the cause
  encoder — single source of truth for the priority logic, cause
  and tval always consistent. Same skeleton-first principle as the
  encoder itself: all eight pairs declared, four 1.2.2 paths tied
  `32'b0` until 1.2.2 substitutes their real drivers. Lighting up
  the 1.2.2 paths will be a literal-tie → live-signal swap on each
  pair.

## 2026-05-07 (Phase 1.2.0)

- [feat] Phase 1.2.0 — first sub-phase of the Phase 1.2 trap work. Adds
  the combinational trap-entry path inside `rv32i_core.v` with ECALL as
  the only active cause source. Cause priority encoder is built in full
  skeleton form (all eight sync-cause inputs declared, seven tied
  `1'b0`). PC-next mux extended to take `mtvec` on trap entry and `mepc`
  on (dead-pathed) trap return. `csr_file`'s trap inputs become driven
  by the encoder rather than tied 0 in `fpga_top.v`. EBREAK / illegal /
  misaligned / bus-error sources land in 1.2.1; MRET in 1.2.2.
  (commits `6129cd1` + `d37fd54` + `c8275fe`)
- [rtl] `rtl/rv32i_core.v` —
  - Inline ECALL decode at the core top level (SYSTEM, funct3=000,
    imm12=0x000, rs1=0, rd=0). `control.v` stays minimal — the funct12 /
    rs1 / rd fields are already plumbed at this level, so distinguishing
    ECALL from other SYSTEM-funct3=0 encodings happens at the use site.
  - Eight-input cause-priority encoder per Decision 3 from
    `docs/handoffs/phase1_context.md`: `inst_addr_misaligned >
    illegal_inst > ebreak > load_addr_misaligned > load_access_fault >
    store_addr_misaligned > store_access_fault > ecall_m`. Only
    `ecall_m` driven in 1.2.0; the other seven tied `1'b0` and lit up by
    1.2.1 input substitutions. Cause code 1 (instruction access fault)
    intentionally absent — IMEM is internal ROM with no bus error path.
  - PC-next mux gains two inputs: `mtvec_i` (selected on trap entry,
    highest priority over branch and jump) and `mepc_i` (dead-pathed on
    a literal `1'b0` select; 1.2.2 replaces the literal with
    `trap_return`).
  - Four new top-level outputs: `trap_enter_o`, `trap_pc_o[31:0]`,
    `trap_cause_o[31:0]`, `trap_tval_o[31:0]`. Drive `csr_file`'s
    Phase 1.0 trap interface directly at fpga_top.
  - `illegal_inst_o` refined: `csr_illegal_i | (illegal_system &
    ~ecall_m) | illegal_opcode`. ECALL is no longer illegal; EBREAK /
    MRET / unknown SYSTEM-funct3=0 still pulse it (consumed in 1.2.1 as
    a cause source).
  - Side-effect suppression on the trap-entry cycle:
    `regfile_we`, `dmem_we`, `dmem_re`, `instret_tick_o` all gated on
    `~trap_enter_w`. For ECALL the first three are structural no-ops
    (decode already drives those signals to 0 on SYSTEM-funct3=000);
    the gates are in place for 1.2.1 illegal/misaligned/access-fault
    sources where the trapping instruction can otherwise touch
    architectural state. `instret_tick` gating is the only one
    observable in 1.2.0 verification — a trapping instruction does not
    retire, so `minstret` must not advance on the trap cycle.
- [rtl] `rtl/fpga_top.v` — replaces the four tied-0 inputs to
  `u_csr_file.trap_enter` / `trap_pc` / `trap_cause` / `trap_tval` with
  the new core ports (via four new internal `core_trap_*` wires).
  `u_csr_file.trap_return` stays tied `1'b0` (Phase 1.2.2's MRET decode
  is its consumer). Existing `core_illegal_inst` UNUSEDSIGNAL waiver
  preserved — `illegal_inst_o` is not consumed in 1.2.0.
- [rtl] `rtl/csr_file.v` — unchanged (Decision #5 from the 1.2.0
  handoff: the Phase 1.0 trap interface is exactly the right shape;
  this sub-phase only drives it).
- [tb] `tb/tb_rv32i_core_csr.v` — three new directed tests (15-17), 14
  new individual checks; total 40/40 (was 26/26):
  - 15: full ECALL trap entry — `mepc` captures ECALL PC, `mcause = 11`,
    MIE 1->0, MPIE 0->1, PC redirected to `mtvec`, `trap_enter` pulsed,
    `instret_tick` gated on the trap cycle, `illegal_inst_o` quiet.
  - 16: ECALL with pre-trap MIE=0 — MPIE captures 0 (preserves prior
    MIE).
  - 17: ECALL with `mtvec=0x80` — confirms PC mux selects `mtvec_i`.
  - Two new probe regs: `seen_trap_enter` and
    `trap_with_instret_observed` (cleared on reset).
  - Mirrors `fpga_top` wiring: core trap outputs feed `csr_file` trap
    inputs (was tied 0 in 1.1).
  - New `ECALL` localparam (Verilog-2001 forbids zero-port functions).
- [tb] `tb/tb_compliance.v` + `tb/tb_rv32i_core.v` — port-list updates
  for the new core trap-entry outputs (left unconnected — neither TB's
  programs trap).
- [sw] `sw/ecall_test.S` (new) — minimal end-to-end ECALL trap-entry
  demo. Sets `mtvec` to a handler within `.text`, sets `mstatus.MIE=1`,
  executes ECALL, and from the handler verifies `mepc` /
  `mcause==11` / MIE==0 / MPIE==1 via `csrrs ..., x0`. Prints
  `PASS\r\n` (or `FAIL\r\n`) over the same UART path `csr_test.S` uses.
  Halts at the end — does NOT MRET (Phase 1.2.2).
- [tb] `tb/tb_fpga_top_ecall.v` (new) — duplicate-and-rename of
  `tb_fpga_top_csr.v` for the ecall_test program. Loads
  `sim/ecall_test.hex`, preloads PASS/FAIL strings into DMEM, captures
  6 UART bytes, expects `PASS\r\n`.
- [build] `Makefile` — new `sim-fpga-ecall` target, mirroring
  `sim-fpga-csr`.
- [ci] `.github/workflows/ci.yml` — `fpga_top_ecall` added to the
  unit-TB skip list (firmware-dependent, like `fpga_top_asm` /
  `fpga_top_c` / `fpga_top_csr`). `tb_rv32i_core_csr` is self-contained
  and remains in the auto-pickup path.

### Verification
- `verilator --lint-only -Irtl -Wall --top-module fpga_top rtl/*.v`:
  clean. No new persistent lint waivers. The Phase 1.1 UNUSEDSIGNAL
  waiver on `mtvec_i` / `mepc_i` in `rv32i_core.v` is gone (both feed
  the PC mux now); `mstatus_mie_i` keeps its waiver until Phase 2
  interrupts.
- `make sim MOD=rv32i_core_csr`: 40/40 PASS, "ALL TESTS PASSED" (was
  26/26 in 1.1).
- `make sim MOD=csr_file`: 63/63 PASS (Phase 1.0 unchanged).
- `make sim MOD=control`: 24/24 PASS.
- All 18 CI-eligible unit testbenches: PASS, no regression.
- `cd tests && make run-all`: 37/37 PASS, all 37 cycle counts
  byte-identical to `phase1.1-complete` after each of the three RTL/TB
  commits — the load-bearing check for this sub-phase, since no rv32ui
  test fires ECALL or any synchronous trap.
- `make sim-fpga-ecall` with `sw/ecall_test.S`: PASS, `PASS\r\n`
  received end-to-end through the full SoC path; the testbench prints
  `*** ECALL FPGA TEST PASSED -- "PASS\r\n" received correctly ***`.

### Phase 1.0 / 1.1 interface validation, second pass
The trap interface that Phase 1.0 baked in (`trap_enter` / `trap_pc` /
`trap_cause` / `trap_tval` / `trap_return`, with internal priority
`trap_enter > trap_return > csr_write_op` on every CSR with multiple
writers) consumed all four sync-trap-entry signals from 1.2.0's encoder
without modification. Same for the 1.1 port list on `rv32i_core` —
`mtvec_i` / `mepc_i` were already routed through, and lighting them up
in 1.2.0 was a literal-tie -> live-signal swap on the PC mux. The "design
for all consumers at module creation" principle held a second time.

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
