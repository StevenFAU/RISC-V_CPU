# Phase 0 Changelog — Foundation Hardening

Running log of fixes/changes landed during Phase 0 of `TIER1_ROADMAP.md`.
Newest entries at top.

## 2026-04-22 (Phase 0.2)
- [infra] C toolchain, newlib-nano runtime, `printf` over UART
  - `sw/c_link.ld` — linker script for C programs.
    - IMEM region 0x00000000 + 64 KB (bumped from 4 KB — old cap was
      artificial; hardware has 16K words of BRAM already). DMEM region
      0x00010000 + 4 KB.
    - `.rodata` placed in DMEM, NOT IMEM. Rationale: the core is
      Harvard-bus; a `lbu` against a printf format string must route
      through the data bus, which cannot reach IMEM. Unified-memory
      rework is explicitly Phase 4 territory.
    - `.eh_frame`, `.note`, `.comment` sections discarded — bare-metal
      builds never unwind.
    - Symbols exposed for crt0: `_bss_start`, `_bss_end`, `_stack_top`,
      `_end`. Stack grows downward from `ORIGIN(DMEM)+LENGTH(DMEM)`.
  - `sw/crt0.S` — startup code. Sets `sp` to `_stack_top`, zeros the
    `.bss` region, calls `main`, spins after return. Lives in
    `.text.init` so the linker places it first in IMEM.
  - `sw/syscalls.c` — newlib stubs. `_write` polls UART TX-busy and
    sends each byte (matches the pattern in `sw/hello.S`). `_fstat`
    reports `S_IFCHR` for stdin/stdout/stderr so newlib-nano's stdio
    layer doesn't buffer indefinitely. `_isatty` returns 1 for those
    fds. `_sbrk` returns -1 (no heap). `_read`/`_close`/`_lseek` are
    minimal stubs. UART-RX syscall wiring deferred to Phase 2.
  - `sw/hello_c.c` — the demo: `printf("Hello from C!\n")`.
  - Root `Makefile` gains a `c` target. Toolchain discovery probes
    `/opt/riscv/bin/riscv32-unknown-elf-gcc`, then
    `$HOME/riscv/bin/riscv32-unknown-elf-gcc`, then PATH. Sentinel
    `TOOLCHAIN_NOT_FOUND` trips an actionable error pointing at
    `docs/toolchain.md`. Does NOT fall back to the Ubuntu
    `riscv64-unknown-elf-gcc` (no newlib) or the Vivado bundle
    (broken nano for rv32i/ilp32).
  - `sim/make_dmem_hex.py` — sibling of `make_imem_hex.py`; converts
    byte-addressed objcopy output (with `--change-section-address`
    shifts) into the word-addressed hex format `$readmemh` expects.
  - `tb/tb_fpga_top.v` split into `tb/tb_fpga_top_asm.v` (existing
    "Hello, RISC-V!" assembly path) and `tb/tb_fpga_top_c.v` (new
    "Hello from C!" path using parameter-driven IMEM/DMEM init from
    the hex files). New `make sim-fpga-c` target drives the C TB.
    CI `unit` job's integration-TB skip list updated to include both.
  - `docs/toolchain.md` — why no distro package works, what to run
    to build riscv-gnu-toolchain from source, Makefile discovery
    chain, measured wall-clock + disk cost.
  - `docs/tech_debt.md` — tracks deferred work: CI coverage for C
    builds (needs toolchain build/cache in CI; ~30-60 min cold build)
    and `actions/checkout@v4`/`actions/cache@v4` Node 20 deprecation
    (bump to `@v5` before 2026-06-02).
  - ELF size for `hello_c.elf` (rv32i/ilp32, -specs=nano.specs, -Os):
    `.text` 4294 B, `.data` 92 B, `.bss` 328 B. Well under the 16 KB
    sanity-check threshold, confirming newlib-nano linked correctly
    (full newlib would be ~40 KB).
  - Simulation (`make sim-fpga-c`): captured all 14 bytes of
    `"Hello from C!\n"` correctly. Hardware verification pending
    (no physical board this session).
  - Regressions: 16/16 unit TBs PASS, compliance 37/37 PASS,
    Verilator lint CLEAN.
  - CI coverage for C builds is deferred to a follow-up — see
    `docs/tech_debt.md`.

## 2026-04-21 (Phase 0.3)
- [infra] Verilator lint baseline + GitHub Actions CI
  - `verilator --lint-only -Irtl -Wall rtl/*.v` now exits 0. All 29 baseline
    warnings resolved — either fixed at source or waived with rationale.
  - Waiver policy: default is to fix; waivers require written justification.
    Every waiver is inlined with a one-line comment and enumerated in
    `docs/lint_waivers.md`. Deferred waivers are labeled explicitly so
    they can be tracked to closure.
  - SYNCASYNCNET surfaced three async-reset holdouts from before the
    Phase 0.1 reset-convention cleanup. All three fixed at source rather
    than waived:
      * `uart_tx`, `uart_rx` → commit `c2e3650`
      * `wb_gpio`            → commit `ab250c6`
    No SYNCASYNCNET warnings remain.
  - GitHub Actions workflow `.github/workflows/ci.yml` runs three parallel
    jobs on every push to main and every PR:
      * `lint`       — Verilator `--lint-only -Wall` on all of `rtl/`
      * `unit`       — every `tb/tb_*.v` except the three integration TBs
                        (`fpga_top`, `compliance`, `rv32i_core`); strict
                        parse for `ALL PASSED`
      * `compliance` — `cd tests && make run-all`; strict parse for
                        `Pass: 37  Fail: 0  Timeout: 0`
  - `tests/isa` is cached by the hash of `tests/setup.sh`. riscv-tests is
    fetched at a fixed version so pinning by the setup script is the
    right granularity.
  - Badges added to README for each job.
  - Unit-TB parsing is strict: a TB that exits 0 without printing
    `ALL PASSED` is treated as a failure. TB `$fatal`-on-failure hardening
    is explicitly deferred (12+ files). Deferred also: C-build CI
    coverage (lands after Phase 0.2).
  - Commits: `273b580` (lint baseline + waivers), `2432354` (workflow).

## 2026-04-21
- [docs] Testbench vs hardware memory-map split documented; compliance baseline refreshed
  - `tb/tb_compliance.v`: added a header comment block explaining that the unified 16 KB memory model differs from the synthesized hardware map (IMEM at 0x0, DMEM at 0x10000). Pointed readers at `sw/link.ld` vs `tests/link.ld` as the source of the split.
  - `sw/link.ld`: header clarifies this script targets the SYNTHESIZED hardware and is used by `make asm`. Programs built with it run on FPGA / `make sim-fpga` but NOT on the compliance testbench.
  - `tests/link.ld`: header clarifies this script targets the compliance testbench's unified 16 KB memory. Documents the latent `.text`/`.tohost` overlap: in practice `.text` is empty across all rv32ui tests (verified via objdump: `.text.init` → ALIGN(0x1000) → empty `.text` → `.tohost` at 0x1000), so nothing collides today. Flagged for any future test that adds real `.text` content.
  - `README.md`: added a one-line cross-reference in the Compliance Tests section pointing at the `tb_compliance.v` comment.
  - `docs/compliance_results.md`: refreshed all 37 cycle counts to reflect post-Phase-0.1 state. Every test is uniformly +1 vs the 0ea6dc1 baseline; the shift comes from commit 111e557's `wb_timer` reset-value change (both `mtime` and `mtimecmp` now reset to all-1s). Annotation explains the cause so future-readers don't have to bisect.
  - No RTL changed. Compliance 37/37 identical to the post-bug-#4 state (add=459, lb=247, jal=49).
  - Closes the Phase 0.1 bug list (5/5).
- [bug] `wb_interconnect`: added `bus_error_o` output; unmapped cycles now ack with zero data
  - Active cycles (`cyc & stb`) to an unmapped address auto-ack with `wbm_dat_o = 0`. Previously the master hung waiting for an ack no slave would produce — fine today because `WB_USE_STALL=0` discards stall_o, but a deadlock once Phase 4 wires the stall into the pipeline.
  - `bus_error_o` is combinational, asserted the same cycle as the bad access. Must stay combinational so the Phase 1 trap can fire on the same cycle the core sees the (zero-valued) rdata.
  - Unconnected in Phase 0 at `fpga_top`; consumed by the load/store access-fault trap in Phase 1. Writes to unmapped addresses are still discarded on the floor (no slave sees `cyc`), so the store retires without side effects.
  - Idle cycles (`cyc=0` or `stb=0`) stay quiescent: no ack, no `bus_error_o`, zero rdata.
  - Compliance: rv32ui 37/37 with no cycle-count drift vs the immediately-preceding commit (5291413). `docs/compliance_results.md` baseline is from 0ea6dc1 and predates all Phase 0.1 work; every test is uniformly +1 vs that baseline due to earlier Phase 0.1 reset-handling changes, not this commit.
- [bug] `wb_interconnect`: tightened address decode for UART/GPIO/TIMER to match documented ranges
  - UART: was `addr[31:12] == 0x80000` (4 KB); now exact 16-byte window `0x80000000..0x8000000F`.
  - GPIO: was `addr[31:12] == 0x80001` (4 KB); now exact 8-byte window `0x80001000..0x80001007`.
  - TIMER: was `addr[31:12] == 0x80002` (4 KB); now exact 16-byte window `0x80002000..0x8000200F`.
  - DMEM: unchanged (`addr[31:16] == 0x0001`, 64 KB). Intentionally broad — it's a memory region, and future DMEM sizing changes should live inside this window without touching the interconnect.
  - Out-of-range accesses inside the old peripheral pages now fall through to the existing unmapped path (return 0, no ack) instead of silently aliasing onto the real registers. Sets up cleaner access-fault semantics for the Phase 1 load/store-fault trap.
- [bug] `wb_timer`: fixed write/increment race, reset-time IRQ assertion, and async-reset inconsistency
  - `mtime` writes no longer silently drop the increment tick (write replaces the addressed half, skips that cycle's increment, untouched half is preserved).
  - `mtime` and `mtimecmp` now both reset to all-1s (was: `mtime=0`, `mtimecmp=all-1s`) for a cleaner IRQ-at-reset story — the comparator is no longer fragile against a change to `mtimecmp`'s default.
  - Converted to synchronous active-high reset (matches `pc.v`, `wb_dmem.v`, and the `fpga_top.v` reset synchronizer).
- [bug] `wb_master`: added `WB_USE_STALL` parameter + simulation assertion for missing-ack bug (was: silently ignored `wb_ack_i`). Optional `stall_o` output exposed for future pipelined core; full integration deferred to Phase 4.
