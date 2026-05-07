# Tech Debt

Running ledger of known shortcomings that are real but deliberately
deferred. Each item has a clear trigger for when it becomes urgent.

## Phase 4 dependencies

These two items were filed by Phase 1.2.2 against a pair of structural
assumptions baked into the at-issue trap source composition (cause 5
`load_access_fault` and cause 7 `store_access_fault`). They are
SEPARATE dependencies — addressing one does not cover the other.

### At-issue trap assumes `bus_error_i` is combinational

**What's the assumption:** `load_access_fault` /
`store_access_fault` fire on the same cycle as the offending
`dmem_re` / `dmem_we`, because `bus_error_i` (sourced from
`wb_interconnect.bus_error_o`) is a combinational function of the
unmapped-address decode. The latch-side gates (`regfile_we`,
`instret_tick`, gated on `~trap_enter_w`) catch the error before
writeback / retirement.

**Why deferred:** True today — Phase 1.2.2 wired this in under that
assumption, and the rv32ui regression + access-fault tests confirm
the model. Registering `bus_error_o` would buy an additional pipeline
stage of timing slack but is not currently necessary on the Artix-7
target.

**Failure mode if the assumption breaks:** if `bus_error_o` becomes
registered (e.g., for timing closure in Phase 4 or later), the at-issue
gate becomes a latched-error model. `load_access_fault` would fire ONE
CYCLE LATE, after the load's writeback has already happened — which
makes the trap path spec-noncompliant: the regfile destination would
already hold the (zero-valued) bus rdata when the trap entered.

**Trigger to close:** any Phase 4 timing-closure work that touches
`wb_interconnect.bus_error_o` or inserts a register on the path
between it and `rv32i_core.bus_error_i`. Also: any new master/slave
that decodes asynchronously and might want to register the error.

**Sketch of fix:** if registration is needed, the at-issue source
composition must move into a registered "trap pending" latch that
accumulates the pending-cause + faulting-address state alongside
the load's own pipeline stage, and the regfile_we / instret_tick
gates must move to that downstream stage. This is a pipeline-stage
restructuring, not a localized tweak. See `rtl/rv32i_core.v` at-issue
gate comment and `docs/handoffs/PHASE1.2.2_HANDOFF.md` §2.b for the
full rationale.

---

### At-issue trap assumes single-cycle bus completion (`WB_USE_STALL=0`)

**What's the assumption:** `dmem_re` and `dmem_we` are driven for
exactly one cycle, the bus completes the access (or auto-acks an
unmapped one) within that cycle, and the next cycle the core is on
to the next instruction. `wb_master.WB_USE_STALL` is defaulted off
to make this explicit.

**Why deferred:** Phase 1.2.2 wired the access-fault trap path under
this assumption, and rv32ui exercises only single-cycle-completable
addresses. Multi-cycle stall semantics are a Phase 4 pipeline concern.

**Failure mode if the assumption breaks:** if `WB_USE_STALL=1` is
enabled, the slave can hold off `wbm_ack_o` for multiple cycles. The
core would need to keep `dmem_re` / `dmem_we` asserted across those
cycles. But the pre-issue gate (`& ~pre_issue_trap_w`) suppresses
them when a trap fires — and on a multi-cycle bus, a trap detected
mid-transaction would deassert the request line before the slave
acked. The slave's protocol contract is broken; downstream behavior
is undefined.

**Trigger to close:** any Phase 4 work that sets `WB_USE_STALL=1` on
`wb_master`, or that introduces a slave that cannot complete in a
single cycle (DDR controller, off-chip flash, etc.).

**Sketch of fix:** the gate model must move from "suppress in the
trap cycle" to "freeze for the duration of the in-flight access,
then resolve". Concretely: a small bus-state FSM that holds the
core's PC and `dmem_re`/`dmem_we` constant until ack arrives,
sampling `bus_error_i` on the ack cycle. This is the same pipeline-
stage restructuring noted in the previous item — the two
dependencies share their resolution but are listed separately so a
future engineer addressing one does not mistakenly assume the other
is also covered. See `rtl/rv32i_core.v` at-issue gate comment and
`docs/handoffs/PHASE1.2.2_HANDOFF.md` §2.b.

---

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

---

## TB `$display` strings must stay ASCII-only — caught in Phase 1.1

**What's the rule:** Testbench `$display` message strings, especially
when stored in fixed-width `[8*N-1:0]` packed-string task parameters,
must contain only ASCII characters. UTF-8 multi-byte glyphs (em-dash
`—` U+2014, en-dash `–`, fancy quotes, etc.) inject non-text bytes
into the simulator's stdout that propagate through pipes and `tee`.

**Why it matters:** The CI unit-TB loop in
`.github/workflows/ci.yml` matches `ALL.*PASSED` via
`echo "$output" | grep -Eq`. When the captured output contains
non-text bytes, GNU `grep` switches to binary mode and silently
suppresses matches — so a passing TB ("ALL TESTS PASSED" appears
on stdout) is reported as a CI failure. Reproduced once during
Phase 1.1 Step 3 when `tb_control.v` had em-dashes in its message
strings: every test passed locally, but CI's regex check returned
zero matches.

**Action:** keep TB `$display` strings ASCII-only. If a unit TB needs
typographic dashes for readability, use `--` (two ASCII hyphens) or
`:` instead.

**Trigger to remove:** if the TB display infrastructure is ever
rewritten to avoid the fixed-width packed-string pattern (e.g.,
SystemVerilog `string` type), this constraint can be revisited.
