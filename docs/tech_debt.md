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
