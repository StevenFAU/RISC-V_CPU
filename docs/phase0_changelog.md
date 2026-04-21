# Phase 0 Changelog — Foundation Hardening

Running log of fixes/changes landed during Phase 0 of `TIER1_ROADMAP.md`.
Newest entries at top.

## 2026-04-21
- [bug] `wb_master`: added `WB_USE_STALL` parameter + simulation assertion for missing-ack bug (was: silently ignored `wb_ack_i`). Optional `stall_o` output exposed for future pipelined core; full integration deferred to Phase 4.
