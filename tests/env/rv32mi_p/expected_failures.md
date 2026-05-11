# rv32mi Expected Failures (Phase 1.2.5)

Records every rv32mi test that fails because the failure mode lies
in a deliberate non-implementation of this CPU. Each entry is
classified as (O) — out-of-scope by design — and requires explicit
user sign-off before being added to this file. Tests that fail for
any other reason (real bugs, env issues, classification disputes)
do NOT land here — they are tracked in `docs/tech_debt.md` ((D)
entries), fixed in this sub-phase ((F) entries in the changelog),
or fixed in the env ((E) entries in the changelog).

**Status:** Finalized at Phase 1.2.5 closure (Step 6). All
classifications complete. (F) pre-flagged risks both confirmed and
fixed in Step 5; their resolution is logged below for audit
traceability.

## (O) categories — deliberate non-implementations

These are the design-deliberate non-implementations for Tier 1. Six
categories total: four declared pre-inventory, two added at
Checkpoint 2 from the source-reading pass.

1. **Interrupts** — `mip` / `mie` / MTIE / MEIE / MTIP / MEIP /
   MSIE / MSIP exercise paths and the interrupt-trap edge. Phase 2
   work.
2. **Vectored mtvec** — `mtvec.MODE != 0`. Direct mode only.
3. **S-mode CSRs** — `sstatus` / `sie` / `sip` / `stvec` / `sepc` /
   `scause` / `stval` / `satp` (as actual S-mode CSRs, not the
   `__MACHINE_MODE` macro aliases). M-only implementation.
4. **`time` / `timeh` CSR reads** — Memory-mapped timer only; CSR
   reads of these addresses trap as illegal.
5. **Sdtrig (Debug-spec triggers)** — `tcontrol` / `tdata1` /
   `tdata2` / `tselect`. Debug-spec extension, not on the Tier 1
   roadmap; no consumers in our architecture. Added Checkpoint 2.
6. **PMP (Physical Memory Protection)** — `pmpcfg*` / `pmpaddr*`.
   M-only architecture has no lower privilege levels for PMP to
   restrict; no consumers. Added Checkpoint 2.

## Recorded (O) classifications — signed off

### breakpoint — (O) Sdtrig

- **Test source:** `tests/isa/rv32mi/breakpoint.S` →
  `rv64mi/breakpoint.S`.
- **Failure mode:** first `csrs tcontrol, a1` write traps
  illegal-inst. `tcontrol` / `tdata1` / `tdata2` / `tselect` are
  not in our 13-CSR set.
- **Final run:** `FAIL: test 2 (tohost=0x00000005, cycles: 108)` —
  signature unchanged across Step 4 → Step 5 (fix commits did not
  perturb).
- **Category:** Sdtrig (Debug-spec triggers not implemented).
- **Signed off:** Checkpoint 2 (Phase 1.2.5), 2026-05-10.

### pmpaddr — (O) PMP

- **Test source:** `tests/isa/rv32mi/pmpaddr.S` →
  `rv64mi/pmpaddr.S`.
- **Failure mode:** first `csrw pmpcfg0, zero` write traps
  illegal-inst. `pmpcfg0` / `pmpaddr0` are not in our 13-CSR set.
  Test's `mtvec_handler` is `j fail` — by construction, a no-PMP
  impl cannot satisfy this test.
- **Final run:** `FAIL: test 1 (tohost=0x00000003, cycles: 97)` —
  signature unchanged across Step 4 → Step 5.
- **Category:** PMP (Physical Memory Protection not implemented).
- **Signed off:** Checkpoint 2 (Phase 1.2.5), 2026-05-10.

## (F) pre-flagged at Checkpoint 2 — resolved in Step 5

These were (F)-risk classifications based on the Step 2 source-
reading pass. Step 4's full compliance run confirmed both; Step 5
fixed both with single-bug commits. Recorded here for audit
traceability — they do NOT count as expected failures.

- **ma_fetch — RESOLVED** by commit `ee02594` (Step 5 a). Fix:
  `rtl/csr_file.v` `CSR_MISA` flipped from `is_readonly=1` (RO-trap)
  to WARL (writes silently accepted via the file's third CSR-mode
  state — `is_readonly=0` with no `write_misa` wire). `tb/tb_csr_file.v`
  updated: misa moved from Category 3 (RO CSRs reject writes) to
  new Category 3b (misa WARL). After fix: `ma_fetch PASS (233 cycles)`.

- **shamt — RESOLVED** by commit `6bd91a0` (Step 5 b). Fix:
  `rtl/control.v` gains a `funct7` input (wired from `instr[31:25]`
  in `rtl/rv32i_core.v`); `OP_R_TYPE` and `OP_I_ALU` cases assert
  `illegal_opcode=1` when `funct3` is a shift but `funct7` doesn't
  match the spec-required pattern (`0000000` for SLL/SLLI/SRL/SRLI;
  `0100000` for SRA/SRAI). `tb/tb_control.v` gains 6 new check_csr
  expects covering legal/illegal shift encodings. After fix:
  `shamt PASS (105 cycles)`. R-type non-shift funct7 validation
  (ADD/SUB/SLT/SLTU/XOR/OR/AND) is deferred per single-bug-per-
  commit discipline and filed in `docs/tech_debt.md`.

## Final summary

| Cat | Count |
|---|---|
| (P) Pass | 14 |
| (O) Sdtrig (signed off) | 1 — breakpoint |
| (O) PMP (signed off) | 1 — pmpaddr |
| (F) / (D) / (E) / (U) remaining | 0 |
| **Total** | **16** |
