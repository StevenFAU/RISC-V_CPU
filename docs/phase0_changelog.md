# Phase 0 Changelog — Foundation Hardening

Running log of fixes/changes landed during Phase 0 of `TIER1_ROADMAP.md`.
Newest entries at top.

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
