# Phase 0 Retrospective

## Summary

Phase 0 ran from 2026-04-21 to 2026-04-22, totaling 12 commits across
three sub-phases (0.1 bug fixes, 0.2 C toolchain, 0.3 Verilator + CI).
Phase 0.4 (testbench harness upgrade) was deliberately deferred to
Phase 4; Phase 0.5 (documentation sweep) folded into this retrospective
and the accompanying README/roadmap refresh.

Two days of wall-clock time is misleading — the groundwork (repo
reorganisation, Wishbone archival, roadmap authoring in commit
`2b42150`) preceded Phase 0.1 by a day, and each sub-phase included
design discussion before the first commit landed. The commit cadence
is a fair record of *execution* time, not *thinking* time.

## What Phase 0 Accomplished

- Closed the five documented RTL bugs from the pre-phase code review:
  `wb_master` missing-ack, `wb_timer` write/increment race, unmapped
  bus-address handling, `wb_gpio` decode tightening, and the
  testbench-vs-hardware memory-map split documentation.
- Normalised reset convention across all RTL to synchronous active-high.
  Phase 0.3 lint (SYNCASYNCNET) surfaced three holdouts that Phase 0.1
  had missed: `uart_tx`, `uart_rx`, `wb_gpio`.
- Established `verilator --lint-only -Wall` as a regression gate with 29
  documented waivers (3 PINCONNECTEMPTY placeholders, 17 UNUSEDSIGNAL
  design-intent, 8 WIDTHEXPAND deferred, 0 SYNCASYNCNET remaining).
- Stood up GitHub Actions CI with three parallel jobs (lint / unit /
  compliance), green on first push.
- Delivered a working C toolchain: purpose-built `riscv-gnu-toolchain`
  at rv32i/ilp32 with newlib-nano, bare-metal crt0, newlib syscall
  stubs over UART, and a `printf`-in-C demo passing in simulation.
- Added `bus_error_o` on `wb_interconnect` — a Phase 0 wire that Phase 1
  will consume for load/store access-fault traps.

## What Phase 0 Cost

Three real surprises vs the original plan:

1. **Bug #4 (unmapped access handling) became an architectural
   decision, not a decode tightening.** The original roadmap framed it
   as "return 0 with ack, or raise a bus-error line." The right answer
   turned out to be both: auto-ack prevents deadlock once Phase 4 wires
   stall through, and `bus_error_o` gives Phase 1 the same-cycle signal
   it needs for the trap path. One extra wire on the interconnect, one
   extra pragma waiver, and a cleaner story going into Phase 1.

2. **Lint caught async-reset holdouts that code review had missed.**
   Phase 0.1's reset cleanup was incomplete. Phase 0.3's SYNCASYNCNET
   warnings named `uart_tx`, `uart_rx`, and `wb_gpio` specifically.
   Fixing them at source (commits `c2e3650`, `ab250c6`) added one extra
   RTL touch before the lint baseline could land. Tolerable — the whole
   point of lint is to catch this class of thing — but it means Phase
   0.1's "done" was premature by one commit.

3. **The C toolchain detour was the largest surprise.** Ubuntu ships no
   newlib for RV32. Vivado's bundled toolchain ships newlib-nano for
   rv32imac/rv32imafc but not rv32i/ilp32. Building
   riscv-gnu-toolchain from source cost ~7m40s wall-clock and 2.2 GB
   under `$HOME/riscv`, plus real time spent discovering the dead ends
   first. Documented in `docs/toolchain.md` so future-me (and anyone
   else cloning the repo) doesn't have to rediscover it.

## What Phase 0 Taught Us

- **Infrastructure-before-refactor is a real principle.** Doing 0.3
  (lint + CI) before 0.2 (toolchain) meant every Phase 0.2 commit
  landed against a lint-clean, compliance-verified baseline. The cost
  was a slightly awkward sequencing decision; the benefit was catching
  `uart_tx` / `uart_rx` / `wb_gpio` async-reset bugs before they
  entered the C-runtime blast radius.

- **Archived docs get read-only treatment.** The Phase 0.1 changelog
  records architectural decisions that the archived
  `docs/phase1_wishbone.md` also touches. We kept the archive frozen
  and described the deltas in `docs/phase0_changelog.md` instead.
  Archives reflect what was done *then*; letting them drift defeats
  the point of having them.

- **One variable at a time paid back in bisectability.** Every Phase
  0.1 bug got its own commit. That made `docs/compliance_results.md`'s
  uniform "+1 cycle everywhere" annotation easy to pin to commit
  `111e557` (the `wb_timer` reset-value change) instead of having to
  bisect a lump. Every time combining commits looked tempting, the
  future-retrospective cost would have been higher than the savings.

- **When the agent paused to ask, pausing was always correct.** Every
  Phase 0 pause caught a real ambiguity: the toolchain dead-end in 0.2
  (Ubuntu/Vivado both fall short — which fallback?), the SYNCASYNCNET
  scope question in 0.3 (fix in source or waive?), and the bus-error
  semantics choice in 0.1 bug #4 (ack policy). Mid-phase questions are
  cheap; unwinding a wrong choice at the end of a phase is not.

- **Strict output parsing in CI matters more than the tests themselves
  do.** Phase 0.3's CI gates are strict about the lines they look for
  (`ALL PASSED` for unit, `Pass: 37  Fail: 0  Timeout: 0` for
  compliance). The first draft used looser patterns; the tightened
  version is what catches a TB that silently exits 0 without running
  anything — which is exactly the failure mode strict parsing was
  chosen for.

- **Phase deferrals should name the phase that picks them up, or admit
  the deferral is indefinite.** The deferred waivers in
  `docs/lint_waivers.md` each name a specific future phase (0.4 → 4,
  `imem_addr` → 4, `debug_pc` → 3, `timer_irq` → 2, etc.). The tech
  debt ledger does the same with trigger conditions. "Deferred" without
  a pickup point becomes "forgotten." Naming the pickup point turns
  the deferral into a commitment future-me can honor.

- **The changelog IS the retrospective's source material.** Writing
  `docs/phase0_changelog.md` as work happened — not retroactively —
  made this retrospective a compression pass rather than an
  archaeological dig. The changelog captures mechanics; the
  retrospective captures meaning. Doing both at the end would have
  produced worse versions of each.

## Deferred Items Entering Phase 1

From `docs/tech_debt.md`:

- **CI coverage for C builds.** Needs a cached riscv-gnu-toolchain
  build in CI (~30–60 min cold). Trigger to close: once a second C
  program exists and refactors regress it.
- **GitHub Actions Node 20 deprecation.** `actions/checkout@v4` and
  `actions/cache@v4` must bump to `@v5` before 2026-06-02.
- **Hardware verification of `hello_c.hex` on the Nexys4 DDR.**
  Simulation-verified this session; no physical board available.

From Phase 0.4's deferral:

- **Bus ready/valid testbench harness.** Deferred to Phase 4. The
  harness design depends on the pipeline's bus contract, which Phase 4
  defines. Building it now would either over-fit to unknown
  requirements or under-constrain to the point of triviality.

From the Phase 0 closure pass itself:

- **Synthesis refresh.** `docs/synth_results.md` reflects commit
  `6edc15c` (2026-03-29), pre-dating all Phase 0.1 RTL changes. The
  reset-style conversions, `stall_o`/`bus_error_o` ports, and
  tightened decodes are expected to move utilisation by a few LUTs.
  No Vivado session was run in this closure pass; the README says so
  honestly. Refresh lands the next time Vivado is opened for any
  reason.

## Commit Timeline

| Hash      | Date       | Summary                                                   |
|-----------|------------|-----------------------------------------------------------|
| `e138621` | 2026-04-21 | Phase 0.1: `wb_master` stall assertion + optional `stall_o` |
| `111e557` | 2026-04-21 | Phase 0.1: `wb_timer` write/increment race, reset IRQ, reset style |
| `5291413` | 2026-04-21 | Phase 0.1: tighten `wb_interconnect` peripheral decodes    |
| `009fc9e` | 2026-04-21 | Phase 0.1: `wb_interconnect` `bus_error_o`, auto-ack unmapped |
| `a0e9bd1` | 2026-04-21 | Phase 0.1: document testbench vs hardware memory-map split |
| `c2e3650` | 2026-04-21 | Phase 0.3 prep: `uart_tx`/`uart_rx` synchronous reset      |
| `ab250c6` | 2026-04-21 | Phase 0.3 prep: `wb_gpio` synchronous reset                |
| `273b580` | 2026-04-21 | Phase 0.3: Verilator lint baseline with documented waivers |
| `2432354` | 2026-04-21 | Phase 0.3: GitHub Actions CI — lint, unit, compliance      |
| `23760a6` | 2026-04-21 | Phase 0.3: backfill CI commit hash and first-run link      |
| `8283b80` | 2026-04-22 | Phase 0.2: C toolchain — linker, crt0, newlib stubs, `make c` |
| `eaedc84` | 2026-04-22 | Phase 0.2: `hello_c.c` — `printf` over UART in simulation  |

## Closing Remarks

Phase 0 established the discipline and infrastructure Phase 1 will
depend on. The CPU is still single-cycle and still handles no traps,
but the ground it sits on is now lint-clean, CI-gated, and
C-compilable. Phase 1 adds the first real capability jump — CSRs,
traps, and M-mode — and picks up two Phase 0 wires (`bus_error_o` and
the still-dangling `timer_irq`) in the process.
