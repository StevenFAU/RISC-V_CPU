# CLAUDE.md — Tier 1 Roadmap: Foundation for a Verified, Pipelined RV32I SoC

## What This Document Is

This is the planning document for the **foundation phase** of the project — the work that turns the current single-cycle RV32I core with a Wishbone fabric into an interrupt-capable, pipelined, formally-verified SoC. When Tier 1 is complete, the repo will be ready to commit to a capstone direction (ML accelerator, DSP/SDR, or OS/RTOS — see final section).

The previous phase (adding a Wishbone B4 bus fabric with four slave peripherals) is complete and archived at `docs/phase1_wishbone.md` (formerly `CLAUDE.md` in the root). That document is the authoritative record of the existing bus architecture; this document picks up where it left off.

**Repo:** `RISC-V_CPU/`
**Target:** Digilent Nexys4 DDR (Artix-7 XC7A100T), 50 MHz core clock, Vivado 2025.2.
**Scope of this doc:** Phases 0–6. Capstone (Phase 7+) is deferred.

---

## Current State (as of Tier 1 kickoff)

### What Works
- Single-cycle RV32I core (`rtl/rv32i_core.v`) with external bus ports.
- 37/37 rv32ui compliance tests passing.
- Wishbone B4 fabric: `wb_master` + `wb_interconnect` + 4 slaves (DMEM, UART, GPIO, timer).
- FPGA-verified on Nexys4 DDR: "Hello, RISC-V!" over USB-UART, LEDs/switches, blinky via timer poll.
- Per-module self-checking testbenches under `tb/`.
- Synthesis numbers: ~2000 LUTs / 275 FFs / 0.5 BRAM at 50 MHz. ~3% of the Artix-7 — enormous headroom for everything downstream.

### Known Limitations (carried into this phase)
- `wb_master` is zero-wait-state only. `wb_ack_i` is ignored; any non-combinational slave silently corrupts reads. (Fixed in Phase 0/4.)
- `timer_irq` is exposed but dangling — the core has no way to receive it. (Fixed in Phase 2.)
- Write/increment race in `wb_timer` (cosmetic). (Fixed in Phase 0.1 — see `docs/phase0_changelog.md`.)
- `mtime` resets to 0 with `mtimecmp` at max — correct only because of defaults, fragile. (Fixed in Phase 0.1 — both now reset to all-1s; see `docs/phase0_changelog.md`.)
- Compliance testbench's memory map differs from synthesized memory map. Works, but worth noting.
- No CI. No Verilator lint. No C toolchain / libc. Every program is hand-written assembly.

### What Does Not Get Touched in Tier 1
- `rtl/rv32i_core.v` is refactored as needed — it is no longer frozen. The external bus contract evolves in Phase 4.
- The Wishbone fabric layout is preserved. New peripherals (if any) are added as standard WB slaves.
- The instruction set stays pure RV32I through Tier 1. No `M`, `A`, `C`, `F`, or custom extensions yet.

---

## Design Principles (apply to every phase)

1. **Compliance never regresses.** rv32ui 37/37 is the floor. Every PR must pass. Once rv32mi is added (Phase 1), that's also the floor.
2. **One variable at a time.** CSRs on the single-cycle core. Then pipeline on top of CSRs. Then caches on top of pipeline. Don't compound refactors.
3. **Prove before polish.** RVFI + formal stands up in Phase 3, before the pipeline refactor. Every downstream phase must keep formal green.
4. **Verilog-2001, explicit widths, no latches.** Matches existing style. No SystemVerilog in RTL (testbenches may use it if iverilog accepts it).
5. **External bus contract is the stable interface.** Changes to the core's port list happen in planned phases only (Phase 1 adds IRQ pin; Phase 4 adds stall/ready). Slaves don't care about pipeline internals.
6. **Phase gates are real.** A phase is not done until the gate passes. No partial merges.

---

## Phase 0 — Foundation Hardening

**Goal:** Build the infrastructure every later phase depends on. Fix the known bugs. Make refactors safe.

**Duration estimate:** 2–3 weeks.

### 0.1 Bug Fixes (from review)
- `wb_master`: either propagate `wb_ack_i` as a stall/ready into the core, or add a simulation-only assertion that fires if `cyc & stb & !ack` for a cycle. Minimum: the assertion. Preferred: the stall wire, gated behind a parameter so it's off until Phase 4 actually uses it.
- `wb_timer`: fix the write/increment race by gating the increment when a write to `mtime_lo/hi` is in flight. Add an explicit enable bit or require `mtimecmp != 0` for IRQ assertion, so the default doesn't silently guarantee safety.
- `wb_interconnect`: decide behavior for unmapped addresses. Options: (a) return 0 with ack, (b) raise a bus-error line that a future trap path consumes. Recommend (b) with the line landing on the floor for now — the wire exists, Phase 1 uses it for the load/store access fault trap.
- `wb_gpio`: tighten address decode to the actual register range, or update docs to match the decode.
- `tb_compliance.v` vs linker script address discrepancy: document the split. Not a bug, but worth a one-paragraph comment.

### 0.2 C Toolchain + Minimal Runtime
- Crt0 (`sw/crt0.S`): zero bss, set up sp, jump to `main`.
- Linker script for C programs (`sw/c_link.ld`): `.text` at 0x00000000 (IMEM), `.rodata/.data/.bss` at 0x00010000 (DMEM), stack at top of DMEM.
- Syscall stub: `_write()` → UART TX poll-and-send. Enough to make `printf` work (via newlib-nano, `-specs=nano.specs`).
- Makefile target: `make c PROG=hello_c` → hex files ready for `sim/` and Vivado.
- Demo program: `sw/hello_c.c` — `printf("Hello from C!\n")` running on the FPGA.

### 0.3 Verilator Lint + CI
- `verilator --lint-only` clean on all `rtl/*.v`. Fix any real warnings; waive the rest explicitly with `/* verilator lint_off ... */` + a comment explaining why.
- GitHub Actions workflow (`.github/workflows/ci.yml`):
  - `lint` job: Verilator lint-only on all RTL.
  - `unit` job: run every `tb/tb_*.v` testbench with iverilog, parse output for `PASS/FAIL`.
  - `compliance` job: run the full 37-test rv32ui suite. Fail the build if any test fails.
- Badge in README.

### 0.4 Testbench Architecture Upgrade
- New testbench harness (`tb/tb_core_harness.v`) that wraps the core behind a bus ready/valid interface. Currently equivalent to same-cycle ack; ready to extend for multi-cycle memory in Phase 4.
- Port existing `tb_compliance.v` to use the new harness. Gate: 37/37 still pass.

### 0.5 Documentation
- Rename current `CLAUDE.md` → `docs/phase1_wishbone.md`. Add a 1-paragraph header explaining it's archived.
- `TIER1_ROADMAP.md` (this file) becomes the active planning doc.
- Update `README.md` "Future Work" section to point at this roadmap.

### Phase 0 Gate
- All rv32ui tests pass under the new harness.
- Verilator lint clean, CI green on a fresh clone.
- `make c PROG=hello_c` produces a hex that, when flashed, prints `Hello from C!` over UART.
- `docs/phase1_wishbone.md` exists; `TIER1_ROADMAP.md` (this document) is the new active planning doc.

---

## Phase 1 — CSRs, Traps, and M-Mode (on the single-cycle core)

**Goal:** The core can take traps and execute the six CSR instructions. Still single-cycle, still no interrupts yet.

**Duration estimate:** 2–3 weeks.

### 1.1 New Module: `rtl/csr_file.v`
- Read/write interface for CSR addresses (12-bit).
- Implements the M-mode CSRs required by rv32mi: `mstatus`, `mie`, `mip`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `misa` (read-only reporting RV32I/M-mode), `mhartid` (hardwired 0), `mvendorid`/`marchid`/`mimpid` (hardwired 0).
- Also: `cycle`, `cycleh`, `instret`, `instreth`, `time`, `timeh` (the U-mode counters are useful even without U-mode).
- Partial-write masks per CSR (some bits are WARL, some WLRL, some read-only).

### 1.2 Control Path Additions
- `SYSTEM` opcode (0x73) decode in `control.v` and `alu_decoder.v`.
- Six CSR instructions: CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI.
- `ECALL`, `EBREAK`, `MRET` handling.
- Writeback path: CSR reads become a new source for `rd_data`.

### 1.3 Trap Logic
- Trap detection:
  - Illegal instruction (any opcode the decoder doesn't recognize).
  - Misaligned load/store (per RV spec — LH/LW/SH/SW with non-aligned address).
  - ECALL from M-mode.
  - EBREAK.
- Trap entry (1-cycle transition since the core is still single-cycle):
  - Save PC → mepc.
  - Encode cause → mcause.
  - Save trap value → mtval (faulting address for misaligned access, instruction bits for illegal inst).
  - Update mstatus.MPIE ← mstatus.MIE; mstatus.MIE ← 0.
  - Jump to mtvec (direct mode for now — vectored mode is future work).
- `MRET`: restore PC ← mepc; mstatus.MIE ← mstatus.MPIE; mstatus.MPIE ← 1.

### 1.4 Tests
- `sw/traps_test.c` — triggers each trap cause, verifies mcause/mepc/mtval, returns via mret.
- Stand up rv32mi compliance tests. Set up a custom environment under `tests/env/custom/` that supports M-mode traps (the `p/` variant from riscv-tests is a reasonable reference).

### Phase 1 Gate
- rv32ui 37/37 still passes.
- rv32mi subset relevant to synchronous traps passes (csr, illegal, ma_addr, ma_fetch if alignment applies, sbreak, scall).
- `traps_test.c` passes on hardware (trap handler in C, prints "trap: cause=N pc=0x..." then `mret`s back).
- Wishbone `wb_timer.mtime_lo/hi` readable via `rdtime`/`rdtimeh` through the CSR file (`time` CSR aliases to the mtime slave — this is the MMIO-backed-CSR pattern).

---

## Phase 2 — Interrupts (on the single-cycle core)

**Goal:** Asynchronous events actually interrupt the CPU. Timer and UART-RX become interrupt sources.

**Duration estimate:** 1–2 weeks.

### 2.1 Core IRQ Port
- Add `irq_timer`, `irq_external`, `irq_software` inputs to `rv32i_core.v`. (Three lines — matches the M-mode spec: MTI, MEI, MSI bits in mip/mie.)
- Interrupt check happens at instruction-retirement boundary. If `mstatus.MIE && (mip & mie & 0xAAA)` is nonzero, take the highest-priority pending interrupt at the next instruction boundary instead of advancing to pc_next.
- mcause gets the async-bit (bit 31) set for interrupts.

### 2.2 Wire Up Sources
- `wb_timer.timer_irq` → `irq_timer`.
- New WB slave `wb_uart` RX-ready → `irq_external` (optional for this phase; gates on interest).
- For Phase 2 it's fine to leave the external line to a single source. A PLIC/aggregator comes later if a capstone needs it.

### 2.3 Tests
- `sw/timer_isr.c` — main loop blinks LED0 at 1 Hz via polling; ISR blinks LED1 at 5 Hz via timer interrupt. Demonstrates both paths work and don't interfere.
- Unit test: `tb_csr_file.v`, `tb_trap.v` — check that an asserted IRQ with MIE=1 causes a trap entry on the next instruction boundary, and that MIE=0 gates it.

### Phase 2 Gate
- rv32ui + rv32mi tests all pass (the rv32mi interrupt tests `mi-illegal`, `mi-timer-interrupt`, etc. are the specific ones to watch).
- `timer_isr.c` runs on hardware with both LEDs blinking at the claimed rates.
- Running `wfi` (treat as nop for now) doesn't hang when an interrupt is pending.

---

## Phase 3 — RVFI Instrumentation + Formal Verification

**Goal:** Mathematically prove the single-cycle core is spec-compliant. Establish formal as a regression gate for all downstream work.

**Duration estimate:** 2–3 weeks.

### 3.1 RVFI Interface
- Add RVFI output ports to `rv32i_core.v`:
  - `rvfi_valid`, `rvfi_order`, `rvfi_insn`, `rvfi_trap`, `rvfi_halt`, `rvfi_intr`
  - `rvfi_rs1_addr/data`, `rvfi_rs2_addr/data`, `rvfi_rd_addr/data`
  - `rvfi_pc_rdata`, `rvfi_pc_wdata`
  - `rvfi_mem_addr`, `rvfi_mem_rmask`, `rvfi_mem_wmask`, `rvfi_mem_rdata`, `rvfi_mem_wdata`
- Full spec: https://github.com/YosysHQ/riscv-formal/blob/main/docs/rvfi.md
- On a single-cycle core, every one of these is trivially derived — it's a trace of what just happened.

### 3.2 riscv-formal Harness
- Clone `riscv-formal` under `tests/formal/` (similar to how `riscv-tests` is cloned).
- Write `tests/formal/cores/rv32i_core/checks.cfg` — declares which properties to prove, what ISA subset, bounded depth (start at 8–12 cycles).
- Properties to prove:
  - Instruction-level correctness (`insn_*` checks for every RV32I instruction).
  - Register file integrity (`reg`, `pc_fwd`, `pc_bwd`).
  - CSR behavior (`csr_*`).
  - Trap consistency (`causal`, `liveness`).

### 3.3 CI Integration
- Formal job in `.github/workflows/ci.yml` runs the bounded proofs on every push.
- Phase 3 adds this as a gate alongside unit tests and compliance tests.

### 3.4 Documentation
- `docs/formal_proofs.md` — table of which properties prove at what depth, known waivers.

### Phase 3 Gate
- All riscv-formal properties prove at depth ≥ 12 cycles on the single-cycle core.
- CI runs formal on every push and blocks merge if any property fails.
- Docs explain the proof scope and any intentional waivers.

---

## Phase 4 — 5-Stage Pipeline Refactor

**Goal:** Classic IF/ID/EX/MEM/WB pipeline with forwarding, hazard detection, and proper bus handshaking. Higher Fmax, higher throughput, formal still green.

**Duration estimate:** 4–6 weeks. Biggest phase in Tier 1.

### 4.1 Refactor Strategy
- Do not rewrite `rv32i_core.v` from scratch. Refactor in place by introducing pipeline registers at the stage boundaries, one boundary at a time, with tests after each.
  1. Insert IF/ID register only — functionally equivalent to a 2-cycle-per-instruction core, but every signal is labeled with its stage. Compliance must pass here.
  2. Insert ID/EX register. Still purely serial. Compliance must pass.
  3. Insert EX/MEM and MEM/WB registers. Now you have bubbles but no hazards resolved yet.
  4. Add forwarding (EX→EX, MEM→EX).
  5. Add load-use stall (ID detects it, freezes IF/ID, inserts a bubble in ID/EX).
  6. Add branch flush (flush IF/ID on taken branch or jump).
- Each step compiles, simulates, and passes compliance before moving to the next. This is slow but the only sane way to debug a pipeline.

### 4.2 External Bus Contract Evolution
- `rv32i_core.v` gains `dmem_stall` / `dmem_ready` inputs. Load data is valid when `dmem_ready` asserts; the core stalls the pipeline until then.
- `wb_master` now properly propagates `wb_ack_i`. This closes the zero-wait-state bug from Phase 0.
- `imem` becomes synchronous (BRAM-backed). `imem_addr_next` (already in the core) drives the BRAM address so the 1-cycle read aligns with IF. This is what that signal was built for.

### 4.3 Branch Prediction
- v1: always-not-taken (flush on mispredict). 2-cycle penalty per taken branch. Simple, correct, bad CPI on branch-heavy code.
- v2 (optional, if time permits): static backward-taken / forward-not-taken. Decoded in IF from the sign of the branch immediate.
- v3: left to a future phase.

### 4.4 Tests
- All existing compliance tests must pass (rv32ui + rv32mi).
- RVFI must still verify — this is where the formal proof really earns its keep. Every pipeline bug that would corrupt an instruction trace is caught here.
- New hazard-specific directed tests in `sw/`: load-use, branch-in-delay-slot, RAW through EX/MEM, etc.
- Throughput benchmark: run a fixed program, measure cycles. Should be roughly 1.2–1.5 CPI for mixed workloads (vs 1.0 on single-cycle but with much lower Fmax).

### 4.5 Synthesis Target
- Fmax target: ≥ 80 MHz on Artix-7 speed grade -1. 100 MHz is a stretch goal.
- Re-run synth, record utilization in `docs/synth_results.md`. Expect ~3000–4000 LUTs (2x single-cycle is typical).

### Phase 4 Gate
- rv32ui 37/37 + rv32mi tests pass on the pipelined core.
- RVFI formal proof still passes at depth ≥ 12.
- Fmax ≥ 80 MHz after implementation.
- `wb_master` zero-wait-state bug is closed.
- Benchmark shows realistic pipeline CPI on a mixed test program.

---

## Phase 5 — Caches (I$ + D$)

**Goal:** Small, direct-mapped caches in front of memory. Makes the pipeline feel real and sets up a future move to DDR-backed main memory.

**Duration estimate:** 3–4 weeks.

### 5.1 I-Cache
- Direct-mapped, 4 KB, 32-byte lines (8 words per line). One valid bit per line.
- Miss: fetch a whole line from main memory (currently `wb_dmem` backing, but treat it as "main memory" for this purpose). Pipeline stalls during fill.
- Lives between the core's `imem_addr` output and the backing memory. Looks like the old IMEM from the core's perspective, but with stalls on miss.

### 5.2 D-Cache
- Direct-mapped, 4 KB, 32-byte lines. Write-through, no-write-allocate (simplest that works).
- Miss handling: stall pipeline in MEM stage while line fetches.
- Placed as a master on the Wishbone interconnect (upstream of the peripherals that must remain uncached). Uncached region bit in address decode: any address ≥ 0x80000000 bypasses the D-cache (memory-mapped I/O semantics).

### 5.3 Memory Reorg
- Add a `wb_main_memory` slave that's the actual backing store (rename current `wb_dmem` or wrap it). Cached region: 0x00010000–0x0001FFFF. Uncached region: 0x80000000+.
- This is when the Artix-7 Memory Interface Generator (MIG) becomes tempting. Deferred — it's a capstone or inter-phase project.

### 5.4 Tests
- New directed tests: cache-line crossing loads/stores, uncached access to peripherals (prove MMIO still bypasses), cold-cache vs warm-cache cycle counts on the same loop.
- RVFI must still prove.
- Compliance must still pass (ideally faster).

### Phase 5 Gate
- Compliance + formal still green.
- A simple benchmark (e.g., 1000 iterations of a small loop) shows measurable speedup vs uncached pipeline (expect 2–4× on cache-friendly code).
- Peripheral access (UART, GPIO, timer) still works — the uncached region is respected.

---

## Phase 6 — Tier 1 Wrap-Up and Capstone Decision

**Goal:** Package what Tier 1 produced, document it properly, decide where to go next.

**Duration estimate:** 1–2 weeks.

### 6.1 Documentation Sweep
- Update `README.md` to reflect the new architecture: pipelined, formally-verified, cached, interrupt-capable.
- Update `docs/datapath.md` with the new pipeline diagram.
- Write `docs/csr_map.md` with all implemented CSRs.
- Write `docs/formal_proofs.md` final version.
- Update `docs/compliance_results.md` with rv32ui + rv32mi cycle counts.
- Record final synthesis numbers in `docs/synth_results.md`.

### 6.2 Demo Program Suite
- A small collection in `sw/demo/` that shows off the SoC end-to-end:
  - `uart_echo.c` — interrupt-driven UART echo.
  - `timer_blink.c` — ISR-driven LED blink.
  - `mandelbrot.c` — CPU-bound compute, prints ASCII fractal over UART. Good benchmark.
  - `stress.c` — misaligned accesses, illegal instructions, hammered interrupts. Everything should be handled gracefully.

### 6.3 Portfolio Deliverables
- A clean GitHub README with badges, screenshots of the LED/UART demos, block diagram.
- A short writeup (`docs/design_notes.md`) that explains design choices, tradeoffs, and lessons learned. This is what a reviewer actually reads.
- A demo video link (optional but high-leverage for portfolio).

### 6.4 Capstone Decision
Review the three arcs from `docs/capstones.md` (to be written):

- **Arc A — ML Inference Accelerator.** INT8 systolic array as a WB slave. Hot industry, high job-market ceiling, moderate demo wow.
- **Arc B — DSP/SDR with HackRF.** FIR/FFT blocks, real RF demo (FM radio out of the FPGA). Defense/aerospace appeal, vivid demo.
- **Arc C — OS/RTOS.** MMU, xv6 or FreeRTOS port. Educationally deep, strong "my CPU runs an OS" resume line.

By end of Phase 6 the repo state plus your own interest tells you which one to commit to. A fresh planning doc gets written then.

### Phase 6 Gate
- All phases 0–5 documented.
- All demos run on hardware.
- A `docs/tier1_retrospective.md` exists, explaining what went well, what didn't, what to do differently in Tier 2.
- A capstone is chosen (or explicitly deferred with a reason).

---

## Cross-Cutting Concerns

### Regression Gates (cumulative across phases)
After each phase, the full gate looks like this:

| Phase | Unit TBs | rv32ui | rv32mi | RVFI formal | Fmax target | New requirements                  |
|-------|----------|--------|--------|-------------|-------------|-----------------------------------|
| 0     | ✓        | 37/37  | —      | —           | 50 MHz      | CI green, `printf` in C works     |
| 1     | ✓        | 37/37  | sync   | —           | 50 MHz      | traps + CSRs work                 |
| 2     | ✓        | 37/37  | full   | —           | 50 MHz      | interrupts work                   |
| 3     | ✓        | 37/37  | full   | proves      | 50 MHz      | formal in CI                      |
| 4     | ✓        | 37/37  | full   | proves      | ≥ 80 MHz    | pipeline CPI measured             |
| 5     | ✓        | 37/37  | full   | proves      | ≥ 80 MHz    | cache speedup measured, MMIO safe |
| 6     | ✓        | 37/37  | full   | proves      | ≥ 80 MHz    | portfolio deliverables exist      |

### Bus Protocol
- Wishbone B4 classic stays the bus protocol through Tier 1.
- AXI4-Lite migration is a possible Tier 2 project if a capstone pulls that way (e.g., using Xilinx ML or DSP IP). For now: deliberate decision to stay on Wishbone.

### FPGA Board
- Nexys4 DDR through Tier 1.
- Migration to a larger board (Arty A7-100T for accessibility, or Genesys 2 / Kria for DDR and PCIe) is a Tier 2 decision driven by capstone needs.

### What Goes in Which File
| File                       | Purpose                                              |
|----------------------------|------------------------------------------------------|
| `TIER1_ROADMAP.md`         | Active planning doc (this file)                      |
| `README.md`                | Public-facing overview                               |
| `docs/phase1_wishbone.md`  | Archive of the completed Wishbone phase              |
| `docs/datapath.md`         | Architecture reference (kept current)                |
| `docs/csr_map.md`          | New in Phase 1 — CSR reference                       |
| `docs/formal_proofs.md`    | New in Phase 3 — proof scope and waivers             |
| `docs/synth_results.md`    | Updated each phase — utilization + timing            |
| `docs/compliance_results.md` | Updated each phase                                 |
| `docs/design_notes.md`     | New in Phase 6 — the writeup for reviewers           |
| `docs/tier1_retrospective.md` | New in Phase 6 — honest lessons learned           |
| `docs/capstones.md`        | New in Phase 6 — A/B/C deep dive                     |

---

## Quick Reference

```
Simulate module:    make sim MOD=<name>
Compliance suite:   cd tests && make run-all
Verilator lint:     verilator --lint-only -Irtl rtl/*.v
Formal proof:       cd tests/formal && sby -f checks.sby  (Phase 3+)
Synthesize:         Vivado 2025.2, per docs/synth_guide.md
UART terminal:      screen /dev/ttyUSB1 115200
Run C program:      make c PROG=<name>  (Phase 0+)
```

## When to Update This Document
- At the start of a new phase: confirm the plan still matches reality before executing.
- At the end of a phase: check off the gate, note any surprises in a brief post-mortem section.
- If a phase is abandoned or significantly reshaped: update here first, don't let code and docs drift.
