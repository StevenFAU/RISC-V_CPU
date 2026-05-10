# rv32mi Expected Failures (Phase 1.2.5)

Records every rv32mi test that fails because the failure mode lies in a
deliberate non-implementation of this CPU. Each entry is classified as
(O) — out-of-scope by design — and requires explicit user sign-off
before being added to this file. Tests that fail for any other reason
(real bugs, env issues, classification disputes) do NOT land here —
they are tracked in `docs/tech_debt.md` ((D) entries), fixed in this
sub-phase ((F) entries in the changelog), or fixed in the env ((E)
entries in the changelog).

**Status:** initial draft (Phase 1.2.5 Step 2). Finalized in Step 6
after the first compliance run + user sign-off pass.

## Pre-classified (O) categories — design-deliberate non-implementations

These categories were declared before any test ran, based on Tier 1
design decisions:

1. **Interrupts** — `mip` / `mie` / MTIE / MEIE / MTIP / MEIP / MSIE /
   MSIP exercise paths and the interrupt-trap edge. Phase 2 work.
2. **Vectored mtvec** — `mtvec.MODE != 0`. Direct mode only.
3. **S-mode CSRs** — `sstatus` / `sie` / `sip` / `stvec` / `sepc` /
   `scause` / `stval` / `satp` (as actual S-mode CSRs, not the
   `__MACHINE_MODE` macro aliases). M-only implementation.
4. **`time` / `timeh` CSR reads** — Memory-mapped timer only; CSR
   reads of these addresses trap as illegal.

After source inventory (Step 2), NONE of the 16 rv32mi tests falls
cleanly into the above four categories. The S-mode-named tests
(`csr` / `sbreak` / `scall` / `ma_fetch`) are M-mode wrappers via
`__MACHINE_MODE` and alias s* CSRs to m* equivalents. The `illegal`
test reaches S-mode and vectored-mtvec code paths but branches to
`pass` at the MPP-hardwired check before exercising them.

## Proposed (O) classifications — AWAIT USER SIGN-OFF

The Step 2 inventory surfaces two tests that fail for design-deliberate
non-implementations not covered by the four pre-classified categories.
These are flagged here as proposed (O); the Step 4 run will confirm
the failure mode matches the rationale below, and the Checkpoint 4
report will request sign-off before they become recorded (O).

### breakpoint — proposed (O): Debug-spec triggers (Sdtrig) not implemented

- **Test source:** `rv32i/tests/isa/rv64mi/breakpoint.S` (via
  `rv32i/tests/isa/rv32mi/breakpoint.S` wrapper).
- **What it tests:** RISC-V Debug-spec hardware triggers (Sdtrig
  extension) via `tcontrol`, `tdata1`, `tdata2`, `tselect` CSRs.
- **Why it fails:** None of those CSRs are in our 13-CSR set
  (`docs/csr_map.md`). The first `csrs tcontrol, a1` write traps
  illegal-inst before any breakpoint can be set up.
- **Rationale for (O):** Sdtrig is an optional extension; Tier 1 does
  not implement Debug-spec triggers. The test contains a fallback
  path (`csrw tselect, x0; csrr a1, tselect; bne x0, a1, pass`) for
  implementations where tselect is hardwired non-zero, but our CSR
  write to an unimplemented address traps before that path is taken.
- **Sign-off status:** pending Checkpoint 4 user sign-off.

### pmpaddr — proposed (O): Physical Memory Protection (PMP) not implemented

- **Test source:** `rv32i/tests/isa/rv64mi/pmpaddr.S` (via
  `rv32i/tests/isa/rv32mi/pmpaddr.S` wrapper).
- **What it tests:** PMP granularity bit (pmpaddr[G-1]) semantics —
  writes to `pmpcfg0` / `pmpaddr0` and verifies read-back behavior in
  NAPOT / OFF modes.
- **Why it fails:** `pmpcfg0` and `pmpaddr0` are not in our 13-CSR
  set. The first `csrw pmpcfg0, zero` write traps illegal-inst. The
  test comment explicitly notes "There's no way to probe for PMP
  support so we can't just pass in this case" and the handler is
  `j fail` — a no-PMP implementation cannot satisfy this test by
  construction.
- **Rationale for (O):** PMP is an optional extension; Tier 1 does
  not implement memory protection.
- **Sign-off status:** pending Checkpoint 4 user sign-off.

## Recorded (O) classifications — signed off

(none yet — populated after Checkpoint 4 user sign-off)
