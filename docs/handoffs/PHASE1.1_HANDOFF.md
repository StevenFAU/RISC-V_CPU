# Phase 1.1 Handoff — SYSTEM Opcode + CSR Instruction Integration

**Model/effort:** Opus 4.7, high effort.
**Before starting:** Run `/clear` in Claude Code to reset context.

---

## Context

Tier 1 Phase 1.1 — SYSTEM opcode decode + CSR instruction integration into `rv32i_core.v`. Phase 1.0 complete (commits `f6941fc` + `f4afa89`, CI run 24781679960 green). The `csr_file.v` module is standalone; Phase 1.1 wires it into the core's execute/writeback path and adds the decoder support.

---

## Critical Framing — Read This Before Anything Else

This is the first phase that modifies the datapath of `rv32i_core.v` non-trivially. Every prior Phase 0 change was additive infrastructure around the core. This phase reaches into the decoder, the control unit, and the writeback mux. The compliance gate (rv32ui 37/37) is now a *real* test, not a formality — any error in integration will break existing instructions.

**The guiding principle:** existing RV32I behavior must remain bit-identical. All 37 rv32ui tests must pass with the same cycle counts they pass with today. New behavior (CSR instructions, illegal-instruction detection for unknown SYSTEM variants) is additive. If a compliance cycle count drifts even by 1, investigate before committing.

---

## Design Decisions Already Made (don't rescope)

From the Phase 1.1 framing discussion:

- **Decision A1 — Decode all SYSTEM opcode variants in 1.1.** CSR instructions decode to full functionality. ECALL/EBREAK/MRET decode to *illegal-instruction placeholder* for now. Phase 1.2 replaces the placeholder behavior. Decoder structure lands once.
- **Decision B1 — CSR readback is a new writeback source.** The writeback mux grows from 4 sources to 5 (ALU, memory load, PC+4, immediate/LUI, CSR read data).
- **Decision C1 — End-to-end gate is an asm test program.** `sw/csr_test.S` uses CSR instructions directly and prints readback via UART. C comes in Phase 1.2.

---

## The Six CSR Instructions

All share opcode `0x73` (SYSTEM), `funct3` distinguishes them:

| Instruction | funct3 | Operation                                         |
|-------------|--------|---------------------------------------------------|
| CSRRW       | 001    | `rd = CSR[csr]; CSR[csr] = rs1`                   |
| CSRRS       | 010    | `rd = CSR[csr]; CSR[csr] \|= rs1` (if rs1 ≠ x0)   |
| CSRRC       | 011    | `rd = CSR[csr]; CSR[csr] &= ~rs1` (if rs1 ≠ x0)   |
| CSRRWI      | 101    | `rd = CSR[csr]; CSR[csr] = zimm`                  |
| CSRRSI      | 110    | `rd = CSR[csr]; CSR[csr] \|= zimm` (if zimm ≠ 0)  |
| CSRRCI      | 111    | `rd = CSR[csr]; CSR[csr] &= ~zimm` (if zimm ≠ 0)  |

Where `zimm` is the 5-bit zero-extended `rs1` field. CSR address lives in bits `[31:20]` of the instruction.

### Critical spec detail — the "no-write" optimization

CSRRS and CSRRC (and their immediate variants) MUST NOT write the CSR when `rs1 == x0` (or `zimm == 0` for immediate variants). This isn't "write zero" — it's "don't write at all, don't even trigger the side effect of a write." The CSR file's `csr_illegal` output and any write masking behavior depends on knowing whether a write actually happened.

Similarly: **CSRRW MUST NOT read the CSR when `rd == x0`.** Read/write of some CSRs has side effects; `rd == x0` means "just do the write, don't read." This is harder to implement than the rs1=x0 case because the core's regfile write is gated on `rd != x0` anyway, but the CSR *read* side effect still has to be suppressed.

Phase 1.0's `csr_file.v` already implements the `csr_write_op` semantics correctly — `csr_write_op = 000` means "no write." Phase 1.1's job is to set `csr_write_op` correctly in the decoder:

- **CSRRW / CSRRWI:** always `001` (write).
- **CSRRS / CSRRSI:** `010` (set) if rs1 ≠ x0 / zimm ≠ 0, else `000`.
- **CSRRC / CSRRCI:** `011` (clear) if rs1 ≠ x0 / zimm ≠ 0, else `000`.

And `csr_read_en`:

- All CSR instructions: asserted if `rd ≠ x0`.
- The csr_file returns read_data = 0 when csr_read_en = 0 (from Phase 1.0).

---

## The Three Non-CSR SYSTEM Instructions (Placeholders Only in Phase 1.1)

ECALL, EBREAK, MRET share opcode `0x73`, funct3 = `000`. They're distinguished by the immediate field (bits `[31:20]`):

- **ECALL:** imm = `0x000`
- **EBREAK:** imm = `0x001`
- **MRET:** imm = `0x302`

Phase 1.1 decodes these but treats them as **illegal-instruction placeholders**. Specifically:

- The decoder recognizes them as SYSTEM opcode variants.
- Control signals route them to a new `illegal_inst` signal which (in Phase 1.1) just does nothing useful — the instruction is treated as a NOP that also asserts `illegal_inst`.
- `illegal_inst` is plumbed to the core boundary as a new output port, but held unused in Phase 1.1. Phase 1.2 consumes it.
- The compliance tests don't exercise ECALL/EBREAK/MRET (those are rv32mi territory), so no compliance test should fail on this placeholder behavior.

This is Decision A1's payoff: the decoder gets its final shape now, and Phase 1.2 only adds *behavior*, not *structure*.

---

## Module Interface Changes

`rv32i_core.v` gains these new ports:

```verilog
// Outputs to CSR file (driven by decoder)
output wire [11:0]  csr_addr_o,
output wire         csr_read_en_o,
output wire [2:0]   csr_write_op_o,
output wire [31:0]  csr_write_data_o,

// Input from CSR file (routed to writeback mux)
input  wire [31:0]  csr_read_data_i,
input  wire         csr_illegal_i,

// Retirement signal (drives csr_file.instret_tick)
output wire         instret_tick_o,

// Illegal-instruction detection (unused in 1.1, wired in 1.2)
output wire         illegal_inst_o,

// Trap-related CSR outputs (brought through from csr_file, unused in 1.1, wired in 1.2)
// These can be omitted from the core's port list and wired directly
// csr_file → core in fpga_top instead, at the agent's discretion.
```

**Design choice for the agent to make:** whether the trap-related CSR outputs (`mtvec_o`, `mepc_o`, `mstatus_mie_o` from csr_file) route through the core's port list or are wired csr_file → consumers directly in fpga_top. Either works. Pick the one that reads cleaner. Document the choice in the core's header comment.

---

## What To Do

### Step 1 — Read the core carefully

Read these before editing anything:

- `rtl/rv32i_core.v` — the whole file. Understand the writeback mux, the control signal flow, where `funct3` is decoded, how `rd != x0` gating works.
- `rtl/control.v` — the main decoder. Understand the style: how opcodes are recognized, how control signals are generated.
- `rtl/alu_decoder.v` — the ALU op decode. May or may not need changes; decide based on how CSR instructions are routed.
- `rtl/immgen.v` — immediate generation. CSRRWI/CSRRSI/CSRRCI use a zero-extended 5-bit immediate. Check whether the existing immgen handles this or needs a new case.
- `rtl/csr_file.v` — the Phase 1.0 module. Confirm its interface (csr_addr, csr_read_en, csr_write_op, csr_write_data, csr_read_data, csr_illegal, instret_tick, mtvec_o, mepc_o, mstatus_mie_o).
- `rtl/regfile.v` — the write gating on rd != x0.
- `docs/csr_map.md` — Phase 1.0's authoritative CSR reference.
- `docs/datapath.md` — the architecture reference. May need updating in Phase 1.1 but read it first.
- `tb/tb_rv32i_core.v` if it exists, or existing integration testbenches. Understand the test style.
- Existing `sw/*.S` files (hello, timer_test, gpio_test) — for the asm test program style.
- `TIER1_ROADMAP.md` Phase 1 section.

### Step 2 — Plan the changes on paper first

Before touching any RTL, write down (in a comment, in a scratch file, wherever) the answer to these:

- **Decoder extension:** exactly what changes in `control.v` to recognize SYSTEM opcode? List the new control signals needed.
- **Immgen extension:** does `immgen.v` need a new case for the CSR zero-immediate? If yes, what's the format?
- **Writeback mux:** how does the mux select between ALU/memory/PC+4/immediate/CSR? Show the priority or the select encoding.
- **Illegal detection:** where does `illegal_inst` get computed? It combines:
  - `csr_illegal_i` from the CSR file (unimplemented CSR or RO write).
  - Decoder-detected SYSTEM variants that are ECALL/EBREAK/MRET (placeholder path).
  - Any existing "unknown opcode" path.
- **Retirement signal:** `instret_tick_o` is high for 1 cycle per retired instruction. On the single-cycle core, that's every cycle the core isn't stalled or resetting. Currently the core doesn't stall, so `instret_tick = !rst` to first approximation. But: should it also be low on cycles where `illegal_inst` fires? Phase 1.2's trap logic will decide this; for 1.1, the simplest correct answer is `instret_tick = !rst` and we refine in 1.2.

The point of writing this down before editing is to catch design mistakes before they're in 200 lines of RTL. If anything in this plan is unclear, *pause and report* before writing RTL.

### Step 3 — Extend `rtl/control.v`

Add SYSTEM opcode recognition. For a CSR instruction, generate:

- `is_csr = 1`
- `csr_op[2:0]` = mapped from funct3 (see table above).
- `csr_use_imm` = funct3[2] (high for CSRRWI/SI/CI).
- `illegal_system` = funct3 == 000 (the placeholder for ECALL/EBREAK/MRET).

Don't overfit the control signals — keep them minimal. The actual `csr_file.csr_write_op` mux (gated on rs1/zimm==0) can happen at the use site, not in control.v, to keep control.v clean.

### Step 4 — Extend `rtl/rv32i_core.v`

Do this incrementally, testing after each change:

1. **Add the new ports** to the module declaration. Compile — core should still work (ports are outputs driving nothing, inputs tied off).

2. **Wire csr_addr_o, csr_read_en_o, csr_write_op_o, csr_write_data_o** from the decoder and operand paths. `csr_addr_o = instruction[31:20]`. `csr_write_data_o = rs1_data` for register variants, zimm-extended for immediate variants. `csr_read_en_o = is_csr && (rd != 5'b0)`. `csr_write_op_o = the gated mapping with rs1/zimm=0 check`.

3. **Add the CSR source to the writeback mux.** When `is_csr`, `rd_wdata = csr_read_data_i`. Otherwise, existing mux behavior.

4. **Add `illegal_inst_o`** as the OR of `csr_illegal_i`, `illegal_system` (from control.v), and any existing unknown-opcode signal. Leave it as an output for now — nothing consumes it in 1.1.

5. **Add `instret_tick_o`.** = `!rst` for Phase 1.1.

Compile after each step. If compilation fails, fix before proceeding.

### Step 5 — Integrate csr_file into `rtl/fpga_top.v`

- Instantiate `csr_file` as a module alongside `rv32i_core`.
- Wire `csr_addr`, `csr_read_en`, `csr_write_op`, `csr_write_data` from core to csr_file.
- Wire `csr_read_data`, `csr_illegal` from csr_file to core.
- Wire `instret_tick` from core to csr_file.
- Hold `trap_enter = 0`, `trap_return = 0`, `trap_pc/cause/tval = 0` (unused in 1.1).
- `mtvec_o`, `mepc_o`, `mstatus_mie_o` from csr_file: either route to the core's port list or leave unconnected in fpga_top. Pick one, document it.
- `illegal_inst_o` from core: leave unconnected in fpga_top (Phase 1.2 wires it to trap logic).

### Step 6 — Write `tb/tb_rv32i_core_csr.v`

A new testbench that integrates core + csr_file and runs small directed asm programs against the integrated system. This is NOT a compliance test — it's a targeted test of the integration path.

Structure: a simple memory-backed harness similar to `tb_compliance.v` but smaller. Load a short asm program, run it for N cycles, check results.

Test programs (embed as `$readmemh` hex strings or inline memory-init):

| Test | Instruction    | Scenario                                                                 |
|------|----------------|--------------------------------------------------------------------------|
| 1    | CSRRW          | Write 0xDEADBEEF to mscratch, read it back to x5, verify.                |
| 2    | CSRRS          | Initial value 0x00FF, set 0xF000, read, verify 0xF0FF.                   |
| 3    | CSRRC          | After test 2, clear 0x00F0, verify 0xF00F.                               |
| 4    | CSRRS rs1=x0   | Should NOT write. Read current value; mscratch unchanged.                |
| 5    | CSRRW rd=x0    | Write should still happen; x0 stays zero.                                |
| 6    | CSRRWI         | Write small value via 5-bit immediate path. Verify.                      |
| 7    | Write to RO    | Write to mvendorid. Verify unchanged + illegal_inst_o pulsed.            |
| 8    | Read unimpl    | Read from 0x7C0 (unused). Verify illegal_inst_o pulsed.                  |
| 9    | minstret count | Run known number of instructions, read minstret via CSRRS, verify count. |
| 10   | mcycle count   | Same pattern, verify mcycle increments each cycle.                       |

Each test self-checks and prints pass/fail. Summary at end: `PASSED X/Y` and `ALL PASSED` if Y==X.

Target: 10 tests minimum. If you can think of clean additional tests (CSRRSI/CSRRCI, simultaneous read+write verifying the read sees the OLD value), add them.

### Step 7 — Write `sw/csr_test.S`

Self-contained asm program that:

1. Writes a known value (e.g., 0x12345678) to mscratch via CSRRW.
2. Reads mscratch back via CSRRS mscratch, x0 (read-only, no write).
3. Prints the read value over UART (reuse the UART TX pattern from `sw/hello.S`).
4. If the printed value matches the written value, also print "PASS\n"; else "FAIL\n".

Keep it simple. The goal is end-to-end integration proof on the FPGA via `sim-fpga`, not comprehensive CSR testing (that's `tb_rv32i_core_csr.v`).

Add a Makefile target (or use the existing `make asm PROG=csr_test`).

### Step 8 — Update the CI workflow

Confirm `.github/workflows/ci.yml`'s unit-TB loop picks up `tb_rv32i_core_csr.v` automatically. If the loop is the glob-iterating pattern from Phase 0.3, it should. If it needs an explicit add, do it. Include this as a check in the report.

### Step 9 — Verify

- `make sim MOD=rv32i_core_csr` — all new TB checks pass.
- `make sim MOD=csr_file` — Phase 1.0's TB still passes (63/63).
- All other unit TBs pass unchanged.
- `make sim-fpga` with `sw/csr_test.S` — prints the written value and "PASS" over UART.
- `make sim-fpga` with `sw/hello.S` — still prints "Hello, RISC-V!" (sanity check that existing asm programs still work).
- `cd tests && make run-all` — **37/37, same cycle counts as Phase 1.0's baseline.** This is the load-bearing check. If cycle counts shift, investigate before committing.
- `verilator --lint-only -Irtl -Wall rtl/*.v` — exits zero. Update `docs/lint_waivers.md` if new waivers are needed and justified.
- CI on push — all three jobs green.

### Step 10 — Documentation

- Update `docs/datapath.md` — the writeback mux diagram now has 5 sources. The decoder now recognizes SYSTEM opcode.
- Update `docs/csr_map.md` with a "Phase 1.1: integrated into core via CSR instructions" note at the top.
- Append to `docs/phase1_changelog.md`:

  ```
  - [feat] phase 1.1: SYSTEM opcode + CSR instruction integration
    - six CSR instructions (CSRRW/S/C + immediate variants) fully functional
    - ECALL/EBREAK/MRET decode to illegal-instruction placeholder (Phase 1.2 replaces behavior)
    - writeback mux extended to 5 sources
    - csr_file integrated into fpga_top; instret_tick wired to core retirement
    - illegal_inst_o exposed as core output (unused until Phase 1.2)
    - tb_rv32i_core_csr.v: [N] integration tests; all passing
    - sw/csr_test.S: end-to-end FPGA demo proving CSR instructions through UART
  ```

- Update `TIER1_ROADMAP.md` — mark Phase 1.1 complete with commit hash.

### Step 11 — Commit and push

Recommended commit structure:

1. `phase1.1: SYSTEM opcode decode + CSR instruction integration` — the RTL changes (control.v, rv32i_core.v, fpga_top.v, any immgen.v changes).
2. `phase1.1: tb_rv32i_core_csr + sw/csr_test.S` — the new testbench and asm test.
3. `phase1.1: documentation — datapath, csr_map, changelog, roadmap` (optional, fold into commit 2 if small).

Push to main. CI must be green before considering the phase closed.

---

## Do NOT

- Do not implement ECALL, EBREAK, or MRET behavior beyond the illegal-instruction placeholder. Phase 1.2.
- Do not wire `illegal_inst_o` to any trap logic. Phase 1.2.
- Do not wire `mtvec_o`, `mepc_o`, `mstatus_mie_o` to any PC redirect logic. Phase 1.2.
- Do not touch the trap_enter / trap_return paths of csr_file (they stay wired to 0 in fpga_top).
- Do not change `csr_file.v` itself. If you find yourself wanting to, stop — Phase 1.0's interface was designed for 1.1. A change means the design was wrong. Report before modifying.
- Do not change compliance test infrastructure. rv32ui 37/37 must pass unchanged.
- Do not add rv32mi tests yet. Phase 1.3.
- Do not handle interrupts. Phase 2.
- Do not merge csr_file and rv32i_core into one module. They're separate for Phase 4's pipeline refactor.
- Do not invent new CSRs. 13 is the Phase 1 set.

---

## Gate

- `tb_rv32i_core_csr.v` passes all tests.
- `tb_csr_file.v` still passes (63/63).
- All other unit TBs unchanged.
- rv32ui compliance 37/37 with cycle counts matching Phase 1.0's baseline (±0, not ±1).
- `sw/csr_test.S` runs on sim-fpga and prints PASS.
- `sw/hello.S` still runs on sim-fpga (existing asm regression).
- Verilator lint clean.
- CI green.
- All commits pushed.

---

## Report Back With

- Commit hashes.
- Compliance cycle counts vs Phase 1.0 baseline. If any drift, report it explicitly and investigate before claiming the gate passed.
- Exact count of integration tests in `tb_rv32i_core_csr.v`.
- How the csr_file's trap-related outputs (`mtvec_o`, `mepc_o`, `mstatus_mie_o`) were routed — through core port list or directly in fpga_top? Rationale for the choice.
- Any surprises. Especially:
  - Did the no-write optimization (rs1=x0 for CSRRS/C) cause any decoder complexity you didn't expect?
  - Did writeback mux changes cause any timing-path or synthesis concerns?
  - Did compliance cycle counts drift, and if so, why?
- Your read on whether Phase 1.0's interface held up under integration, or whether you discovered interface weaknesses that should be fixed before Phase 1.2. The "design for all consumers" principle's validation moment.

---

## Closing Notes

The load-bearing check is compliance cycle counts — if they drift, the integration introduced a subtle bug and we investigate before anything else.

If you pause with a design question about the decoder, the writeback mux, or CSR semantics, the answer is almost always "flag it and wait" rather than "pick one and hope." Phase 1.1 is the first phase where the core itself is being modified, and subtle bugs compound into Phase 1.2 in ways that are hard to bisect.
