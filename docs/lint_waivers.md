# Verilator Lint Waivers

This table enumerates every `/* verilator lint_off ... */` pragma in the RTL and
the rationale behind it. Phase 0.3 established the policy: **the default is to
fix the warning**; every waiver must be justified here, and "deferred" waivers
must say so explicitly so they can be tracked to closure.

Baseline invocation:

```bash
verilator --lint-only -Irtl -Wall rtl/*.v
```

With the waivers below applied this command exits 0. Any new warning on `main`
is a CI failure; either fix it, or add a row here and justify it.

## Summary by category

| Category         | Count | Disposition                                        |
|------------------|-------|----------------------------------------------------|
| PINCONNECTEMPTY  | 3     | Deliberate placeholders for Phase 1/4              |
| UNUSEDSIGNAL     | 17    | Design-intent (WB slave patterns, deferred ports)  |
| WIDTHEXPAND      | 8     | Deferred cleanup — not a permanent design decision |
| SYNCASYNCNET     | 0     | All async-reset holdouts converted in Phase 0.3    |

## Per-site waivers

| File                 | Rule ID          | Site (approx.)           | Rationale                                                                                                                                              |
|----------------------|------------------|--------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------|
| `rtl/rv32i_core.v`   | PINCONNECTEMPTY  | `u_alu.zero()`           | ALU zero flag is unused; branch logic evaluates `alu_result` directly in the control/PC path.                                                          |
| `rtl/fpga_top.v`     | PINCONNECTEMPTY  | `u_wb_master.stall_o()`  | Reserved for Phase 4 pipeline. `WB_USE_STALL=0` on the single-cycle core; Phase 4 flips the parameter and wires the port.                              |
| `rtl/fpga_top.v`     | PINCONNECTEMPTY  | `u_wb_ic.bus_error_o()`  | Reserved for Phase 1 load/store access-fault trap (see `docs/phase0_changelog.md`). Combinational line is kept live; just not consumed at top yet.     |
| `rtl/fpga_top.v`     | UNUSEDSIGNAL     | `wire imem_addr`         | **Deferred (Phase 4).** The current-PC flavor of the fetch address is dead at the top level; `imem_addr_next` drives BRAM. Core port list cleanup is appropriate in Phase 4's pipeline refactor, not Phase 0.3's infra-only scope.                                     |
| `rtl/fpga_top.v`     | UNUSEDSIGNAL     | `wire debug_pc/debug_instr` | Consumed in Phase 3 by the RVFI formal harness. Unwired today.                                                                                     |
| `rtl/fpga_top.v`     | UNUSEDSIGNAL     | `wire timer_irq`         | Exposed by `wb_timer` but dangling until Phase 2 wires it into the core's `irq_timer` input (requires Phase 1 CSR + trap infra first).                 |
| `rtl/wb_gpio.v`      | UNUSEDSIGNAL     | ports `wb_adr_i/wb_dat_i/wb_sel_i` | Standard WB slave pattern: the interconnect fully decodes address, so the slave only uses the register-offset bits. Byte selects are ignored (word-only slave). Upper data-in bits ignored (16-bit GPIO). |
| `rtl/wb_timer.v`     | UNUSEDSIGNAL     | ports `wb_adr_i/wb_sel_i` | Same WB slave pattern as above (word-only, 32-bit register halves).                                                                                   |
| `rtl/wb_uart.v`      | UNUSEDSIGNAL     | ports `wb_adr_i/wb_dat_i/wb_sel_i` | Same WB slave pattern. Upper data-in bits ignored (8-bit UART payload).                                                                          |
| `rtl/wb_dmem.v`      | UNUSEDSIGNAL     | port `rst`               | `wb_dmem` has no state to reset — memory contents come from `$readmemh` at elaboration, writes are guarded by `valid` not `rst`. Keeping the port for interface uniformity with other WB slaves. |
| `rtl/wb_dmem.v`      | UNUSEDSIGNAL     | ports `wb_adr_i/wb_sel_i` | Same WB slave pattern — slave uses only the low 16 bits of address (4 KB DMEM window). Byte selects ignored; `dmem.v` uses the funct3 sideband for byte/half writes. |
| `rtl/imem.v`         | UNUSEDSIGNAL     | port `addr`              | Only `addr[$clog2(DEPTH)+1:2]` indexes the memory; low 2 bits are word alignment, high bits are above the IMEM window.                                 |
| `rtl/dmem.v`         | UNUSEDSIGNAL     | port `mem_read`          | Read path is always combinational; `mem_read` accepted but not gated. See inline comment — removing would touch all instantiation sites for no functional benefit. |
| `rtl/dmem.v`         | UNUSEDSIGNAL, WIDTHEXPAND | `wire [31:0] word_addr = addr[31:2]` | **Deferred (Phase 0.3+).** `word_addr` could be declared `[$clog2(WORDS)-1:0]` (10 bits for a 4 KB DMEM), eliminating both warnings. Left oversized to avoid RTL churn inside the infra-only Phase 0.3 scope. Functionally safe — unused high bits are zero-extended and not indexed into `mem[]`. |
| `rtl/uart_tx.v`      | WIDTHEXPAND      | `clk_cnt == CLKS_PER_BIT ± 1` (3 sites) | **Deferred (Phase 0.3+).** 16-bit `clk_cnt` compared against 32-bit parameter expressions. `CLKS_PER_BIT` is ≈434 at 50 MHz / 115200 baud, fits in 16 bits easily. Proper fix: cast the RHS explicitly. Not a permanent design decision. |
| `rtl/uart_rx.v`      | WIDTHEXPAND      | `clk_cnt == CLKS_PER_BIT ± 1` (3 sites) | **Deferred (Phase 0.3+).** Same reason as `uart_tx.v`.                                                                                              |

## History

- **Phase 0.3 (2026-04-21).** Initial waiver set established. `SYNCASYNCNET`
  fixed at source for `uart_tx`, `uart_rx`, and `wb_gpio` (commits `c2e3650`
  and `ab250c6`) — those three modules were the last async-reset holdouts
  from before the synchronous-reset convention was established in Phase 0.1.
  No SYNCASYNCNET warnings remain, so none are waived.

## When to revisit

Every entry marked **Deferred** should disappear as the referenced phase lands:

- UART `WIDTHEXPAND` → any future UART touch-up.
- `dmem.v:word_addr` sizing → any future DMEM rework.
- `fpga_top.v:imem_addr` → Phase 4 core port list refactor.
- `fpga_top.v:debug_pc/debug_instr` → Phase 3 RVFI harness.
- `fpga_top.v:timer_irq` → Phase 2 IRQ wiring.
- `fpga_top.v:stall_o/bus_error_o` PINCONNECTEMPTY → Phase 4 / Phase 1 respectively.

When a deferred waiver's phase completes, delete the `/* verilator lint_off */`
pragma and the row here in the same commit as the fix.
