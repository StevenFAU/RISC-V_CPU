# rv32mi Expected Failures (Phase 1.2.5)

Records every rv32mi test that fails because the failure mode lies in
a deliberate non-implementation of this CPU. Each entry is classified
as (O) — out-of-scope by design — and requires explicit user sign-off
before being added to this file. Tests that fail for any other reason
(real bugs, env issues, classification disputes) do NOT land here —
they are tracked in `docs/tech_debt.md` ((D) entries), fixed in this
sub-phase ((F) entries in the changelog), or fixed in the env ((E)
entries in the changelog).

**Status:** Step 2 inventory complete; Checkpoint 2 sign-offs recorded
below. Finalized in Step 6 after the Step 4 compliance run + any
Checkpoint 4 sign-offs.

## (O) categories — deliberate non-implementations

These are the design-deliberate non-implementations for Tier 1. Six
categories total: four declared pre-inventory, two added at Checkpoint
2 from the source-reading pass.

1. **Interrupts** — `mip` / `mie` / MTIE / MEIE / MTIP / MEIP / MSIE /
   MSIP exercise paths and the interrupt-trap edge. Phase 2 work.
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

- **Test source:** `tests/isa/rv32mi/breakpoint.S` → `rv64mi/breakpoint.S`.
- **Failure mode:** First `csrs tcontrol, a1` write traps illegal-inst.
  tcontrol/tdata1/tdata2/tselect are not in our 13-CSR set.
- **Category:** Sdtrig (debug-spec triggers not implemented).
- **Signed off:** Checkpoint 2 (Phase 1.2.5).

### pmpaddr — (O) PMP

- **Test source:** `tests/isa/rv32mi/pmpaddr.S` → `rv64mi/pmpaddr.S`.
- **Failure mode:** First `csrw pmpcfg0, zero` write traps illegal-inst.
  pmpcfg0/pmpaddr0 are not in our 13-CSR set. Test's mtvec_handler is
  `j fail` — by construction, a no-PMP impl cannot satisfy this test.
- **Category:** PMP (Physical Memory Protection not implemented).
- **Signed off:** Checkpoint 2 (Phase 1.2.5).

## (F) pre-flagged at Checkpoint 2 — confirmation pending Step 4 run

These are (F)-risk classifications based on source reading. They are
NOT yet confirmed against an actual run. Step 4 will confirm or refute
each; if confirmed, fixed in Step 5 with the single-bug-commit
discipline. Listed here only for audit traceability of the pre-flag
decisions; they do NOT count as expected failures.

- **ma_fetch** — Test does `csrsi misa, 1 << ('c' - 'a')` in the
  `__MACHINE_MODE` block. Our `csr_file.v` marks `CSR_MISA` as
  `is_readonly` → writes trap illegal. Per spec, `misa` is WARL:
  writes are accepted (and ignored for unsupported bits), reads
  return the implementation's supported-extensions bitmap. Likely
  one-line fix in `csr_file.v` to drop `is_readonly` for misa.
- **shamt** — Test asserts that `.word 0x02051513` (SLLI with
  shamt[5]=1 / funct7-bit=1) traps illegal_inst on RV32I. If
  `control.v` doesn't validate funct7 on SLLI/SRLI/SRAI (must be
  `0000000` for SLLI/SRLI, `0100000` for SRAI), it incorrectly accepts
  the encoding as legal. Likely a control-decode fix.
