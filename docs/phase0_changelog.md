# Phase 0 Changelog — Foundation Hardening

Running log of fixes/changes landed during Phase 0 of `TIER1_ROADMAP.md`.
Newest entries at top.

## 2026-04-21
- [bug] `wb_timer`: fixed write/increment race, reset-time IRQ assertion, and async-reset inconsistency
  - `mtime` writes no longer silently drop the increment tick (write replaces the addressed half, skips that cycle's increment, untouched half is preserved).
  - `mtime` and `mtimecmp` now both reset to all-1s (was: `mtime=0`, `mtimecmp=all-1s`) for a cleaner IRQ-at-reset story — the comparator is no longer fragile against a change to `mtimecmp`'s default.
  - Converted to synchronous active-high reset (matches `pc.v`, `wb_dmem.v`, and the `fpga_top.v` reset synchronizer).
- [bug] `wb_master`: added `WB_USE_STALL` parameter + simulation assertion for missing-ack bug (was: silently ignored `wb_ack_i`). Optional `stall_o` output exposed for future pipelined core; full integration deferred to Phase 4.
