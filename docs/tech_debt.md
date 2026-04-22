# Tech Debt

Running ledger of known shortcomings that are real but deliberately
deferred. Each item has a clear trigger for when it becomes urgent.

## CI coverage for C builds — deferred from Phase 0.2

**What's missing:** the GitHub Actions CI workflow lints RTL, runs
Icarus Verilog unit testbenches, and runs the rv32ui compliance suite
— but does NOT exercise the `make c` flow. `make sim-fpga-c` is
similarly uncovered.

**Why deferred:** CI runners don't ship a rv32i/ilp32 newlib-nano
toolchain, and none of the Ubuntu packages or common prebuilt tarballs
match without fix-ups. Building `riscv-gnu-toolchain` inside CI takes
~30–60 min on a cold cache. A cacheable build (keyed on toolchain
commit + configure flags) is the right solution, but slots into CI
hygiene work after Phase 0.2 stabilizes rather than blocking it.

**Trigger to close:** once Phase 0.2 is landed and we have a second
C program that regressed under a refactor — at that point the cost of
manual re-verification exceeds the cost of the cache-miss CI job.

**Sketch of fix:** a new `c-build` job in `.github/workflows/ci.yml`
that (1) restores a `/opt/riscv` cache keyed on a pinned
riscv-gnu-toolchain commit hash + configure args, (2) builds the
toolchain on cache miss, (3) runs `make c PROG=hello_c` and
`make sim-fpga-c`, and (4) verifies both the captured UART output and
the `.text` size.

---

## GitHub Actions Node 20 deprecation — bump before 2026-06-02

**What's deprecated:** `actions/checkout@v4` and `actions/cache@v4`
run on Node 20, whose default runtime support is removed on
2026-06-02 per GitHub's runner-image roadmap. Workflows keep working
until the forced switch, then break.

**Why not yet:** `@v5` releases have landed but we've been prioritizing
Tier 1 RTL work over CI maintenance. Cost is a two-line diff across one
file (`.github/workflows/ci.yml`), easy to do in a quiet moment.

**Trigger to close:** 2026-05-15 at the latest (two-week buffer before
the forced switch), or sooner if any deprecation warning surfaces in a
CI run.

**Action:** bump both `actions/checkout@v4` → `actions/checkout@v5`
and `actions/cache@v4` → `actions/cache@v5` in
`.github/workflows/ci.yml`. No other changes required.

---

## `time`/`timeh` CSR aliasing — deferred from Phase 1.0

**What's missing:** Reads of CSR addresses 0xC01 (`time`) and 0xC81
(`timeh`) are not implemented. The user-mode counters spec defines
these as read-only mirrors of the memory-mapped mtime register in
the `wb_timer` slave.

**Why deferred:** Aliasing the CSR to mtime requires a cross-bus read
path from the CSR file (inside the core) to the `wb_timer` slave
(behind the Wishbone fabric). That path needs a way to issue the
read on every `rdtime`/`rdtimeh` and a timing guarantee that doesn't
stall the core or violate ack semantics. The spec-compliant
alternative — software reads mtime via MMIO from `wb_timer` directly
— is already supported and exercised by existing programs. The
Phase 1.0 CSR set is Option B' (13 registers) per
`docs/phase1_context.md`, which deliberately excludes `time`/`timeh`.

**Trigger to close:** A use case that requires reading mtime from a
context where MMIO access is undesirable (e.g., a trap handler that
must avoid memory access), or a future compliance variant that
requires the CSR alias.

**Sketch of fix:** add a side-band port from `wb_timer` carrying
`mtime_lo`/`mtime_hi` directly to the CSR file, bypassing the fabric
for the read path. The timer's writes still go over the bus; only
the periodic counter readout takes the side-band.

---

## Bus fabric lacks assertion-based regression — consider in Phase 3a/3b window

**What's missing:** The Wishbone fabric (`wb_master`,
`wb_interconnect`, slaves) has no `ifndef SYNTHESIS` assertions
verifying decode correctness or handshake invariants (`cyc` implies
eventually `ack`, `stb` only when `cyc`, no `ack` without an active
cycle). The `bus_error_o` signal is exercised by directed unit tests
but not asserted as a protocol invariant.

**Why deferred:** Assertion infrastructure has the most leverage
paired with formal verification — assertions become proof obligations
under `sby`, where they're either proved or counterexampled, not
spot-checked by directed stimulus. Adding them in isolation would
catch bugs but with weaker guarantees than they could give once the
formal harness exists.

**Trigger to close:** Phase 3a, when the formal toolchain stands up
for the core. The same `sby` infrastructure can run fabric-level
proofs with marginal additional cost.

**Sketch of fix:** add assertion blocks to each fabric module gated
on a `WB_ASSERTIONS` define. Standard patterns: liveness
(`cyc & stb |-> ##[1:$] ack`), safety (`ack |-> cyc & stb`), and
decode coverage for the address map. Wire these into the Phase 3a
`checks.cfg`.

---

## Simulation coverage metrics not collected — consider in Phase 3 window

**What's missing:** Verilator supports line, toggle, and functional
coverage. None of it is enabled. We have no objective measure of
which RTL paths the testbench suite exercises beyond "does this
test pass."

**Why deferred:** Coverage has the most leverage when there's a
specific gap to chase. Bringing it up cold tends to surface known
gaps (reset paths, error branches) as noise. The Phase 3 formal
work surfaces specific properties; coverage complements that by
showing what dynamic stimulus actually hit.

**Trigger to close:** Phase 3a or 3b if a formal counterexample
suggests stimulus-level gaps. Otherwise Phase 4 pipeline bring-up,
where hazard coverage matters and directed stimulus is hard to
design without a coverage signal.

**Sketch of fix:** add a `make coverage` target that runs Verilator
with `--coverage-line --coverage-toggle` and post-processes
`logs/coverage.dat` with `verilator_coverage --annotate`. Don't
gate CI on a coverage threshold — use it as a diagnostic tool.
