# Phase 0 Changelog — Foundation Hardening

Running log of fixes/changes landed during Phase 0 of `TIER1_ROADMAP.md`.
Newest entries at top.

## 2026-04-21
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
