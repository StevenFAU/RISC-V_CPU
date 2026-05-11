# CHAT_HANDOFF.md — Working Conventions

Working conventions accumulated across the Phase 1 trap work. This
file holds project-wide patterns that emerge from individual
sub-phases but apply across all of them. Sub-phase handoffs
reference these conventions; new sub-phases add to them as patterns
crystallize.

---

## 1. `trap_pc` vs `trap_tval` masking distinction

**Convention.** `csr_file` masks `trap_pc[1:0]` to `00` internally
on the `mepc` write — instructions are word-aligned in our impl,
so the low bits carry no information. `trap_tval` is taken **as-is**:
the misaligned target's low bits reach `mtval` unmodified, which is
the spec-required data for a `CAUSE_MISALIGNED_FETCH` trap.

**Where this matters.** The encoder in `rv32i_core.v` sets
`trap_tval_w = misaligned_target` (raw, low bits included) for
cause 0 and `dmem_addr` (raw) for causes 4/5/6/7. Do not
preemptively mask either at the source. The mask lives in
`csr_file.v`'s `mepc` write block and applies only to `mepc`,
never to `mtval`. Confirmed in 1.2.1 closure.

**Trap path origin.** Phase 1.2.1 (cause 0 misaligned-fetch wiring).

---

## 2. Module-level TB input tieoff convention

**Convention.** Compliance and module-level testbenches MUST
explicitly tie off every input port on every instantiated module,
even ports the test doesn't exercise. **Never** rely on
`PINCONNECTEMPTY` for inputs. Required form:

```verilog
.bus_error_i(1'b0),
.irq_timer  (1'b0),
.irq_ext    (1'b0),
.csr_read_data_i(32'd0),  // when csr_file not in scope
```

**Why.** Floating inputs under `PINCONNECTEMPTY` propagate X values
through combinational logic. Simulators don't fault on X — they
just produce wrong results that surface as cycle-count divergence
or, worse, infinite loops in tests that depend on deterministic
branching (the propagation can land on a branch comparison and
make it non-deterministic).

**Trap path origin.** Phase 1.2.2 (`bus_error_i` tieoff in
`tb_compliance` before `wb_interconnect` integration). Phase 1.2.4
surprise (`tb_compliance` lacked `csr_file` integration — see the
trap-test infrastructure work). Phase 1.2.5 generalized when
`tb_compliance` finally integrated `csr_file` and gained the full
trap-port surface.

---

## 3. `mscratch` handler-stack trampoline pattern

**Convention.** Trap trampolines that may run with corrupted `sp`
(compliance tests deliberately exercising stack edge cases, future
OS-arc context-switch code) use `mscratch` for atomic stack swap:

```assembly
trap_entry:
    csrrw sp, mscratch, sp     # atomic swap sp <-> mscratch
                               # sp now points to handler stack
                               # mscratch now holds user sp (saved)
    addi  sp, sp, -REGS_SIZE
    sw    t0,  0(sp)
    # ... save other caller-saved regs ...
    call  trap_dispatcher
    # ... restore caller-saved regs ...
    addi  sp, sp, REGS_SIZE
    csrrw sp, mscratch, sp     # atomic swap back; sp restored
    mret
```

Env init MUST write a valid handler-stack pointer to `mscratch`
before the first trap can fire. Without that init, the first
`csrrw sp, mscratch, sp` swaps `sp` for whatever `mscratch` happens
to hold (likely 0) and the handler crashes.

**Status: documented, NOT currently required.** The Phase 1.2.5
rv32mi suite does not include any test that deliberately corrupts
`sp` before triggering a trap, and the upstream env/p's single-stack
trap_vector pattern (caller-saved register save/restore on the
trapped program's own `sp`) is sufficient. The `mscratch` pattern
is reserved for:

- Phase 6+ OS-arc work (context-switch + privilege-level traps).
- Custom Tier-2 tests that intentionally probe stack edge cases.
- Any future env where the test harness can't guarantee `sp` is
  valid at trap entry.

When that work arrives, this pattern is the spec-blessed idiom — do
not reinvent.

**Trap path origin.** Phase 1.2.4 (where `traps_test.c`'s
trampoline used the trapped program's `sp` and the discipline was
established that this is safe **only** when the trapped program
keeps `sp` valid; Phase 1.2.5 explicitly noted the
`csrrw sp, mscratch, sp` pattern as the alternative).

---

## 4. Phase scope principle

**Convention.** Phases land **capability** or **coverage**.
Sub-phases whose only deliverable would be "didn't break anything"
are step gates, not phase gates — fold them in as the first step
of the next phase that lands real capability.

**Why.** A sub-phase whose closure report is "no regressions" makes
poor commit-graph anchors: it doesn't unblock a downstream consumer
and doesn't create a meaningful bisect target. Step gates (regression
checks at each commit) are the right abstraction for that
discipline; sub-phase boundaries are not.

**Application.** Phase 1.2.5 absorbed `csr_file` integration into
`tb_compliance` as **Step 1** rather than spinning it off as a
standalone sub-phase. The Step 1 deliverable is "rv32ui 37/37
byte-identical + 19 unit TBs + 11 sim-fpga PASS after the
structural prerequisite for rv32mi" — exactly the "didn't break
anything" shape that fails the sub-phase test.

**Origin.** Phase 1.2.5 handoff Decision 1.

---

## 5. `csr_file.v` three-state CSR model

**Convention.** `csr_file.v` supports three CSR-mode configurations
along the (trap-on-write × stores) axis. Each existing and future
CSR maps to exactly one:

| State | Configuration | Behavior | Examples |
|---|---|---|---|
| **RO-trap** | `is_readonly=1` | Write attempts trap `illegal_inst`. Storage never updates. | `mvendorid`, `marchid`, `mimpid`, `mhartid`, `cycle`, `instret` (user-mode RO aliases) |
| **RW-stored** | `is_readonly=0` + per-CSR `write_<csr>` wire wired to a storage update block | Writes accepted; storage updates per the CSR's write mask. | `mstatus`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mip`, `mcycle`, `minstret` |
| **WARL (RO-accept-no-store)** | `is_readonly=0` + NO `write_<csr>` wire | Writes accepted (no trap), but storage never updates. Reads return the implementation's hardcoded value. | `misa` (added Phase 1.2.5) |

**Future read-only-but-spec-WARL CSRs use the third state — no new
mode required.** This includes any CSR where the spec says "writes
shall be ignored" or "WARL with hardwired bits" and the
implementation doesn't expose any writable field. Don't add a new
mode unless the new CSR's semantics genuinely require it.

**Application example.** Phase 1.2.5 Step 5 (a) migrated `misa`
from RO-trap to WARL by removing `is_readonly = 1'b1` from the
`CSR_MISA` case in the address-decode block. No `write_misa` wire
existed; none was added. csr_modified_value computes on misa write
attempts and goes nowhere. The architectural shape was already
present — only the flag changed.

**Origin.** Phase 1.2.5 Step 5 (a) misa WARL fix discovery.
