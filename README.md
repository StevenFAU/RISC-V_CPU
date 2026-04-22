# RV32I RISC-V CPU + SoC

[![Lint](https://github.com/StevenFAU/RISC-V_CPU/actions/workflows/ci.yml/badge.svg?branch=main&event=push&job=lint)](https://github.com/StevenFAU/RISC-V_CPU/actions/workflows/ci.yml)
[![Unit tests](https://github.com/StevenFAU/RISC-V_CPU/actions/workflows/ci.yml/badge.svg?branch=main&event=push&job=unit)](https://github.com/StevenFAU/RISC-V_CPU/actions/workflows/ci.yml)
[![Compliance](https://github.com/StevenFAU/RISC-V_CPU/actions/workflows/ci.yml/badge.svg?branch=main&event=push&job=compliance)](https://github.com/StevenFAU/RISC-V_CPU/actions/workflows/ci.yml)

A single-cycle RV32I processor with a Wishbone B4 SoC fabric, built for
FPGA (Digilent Nexys4 DDR, Artix-7 XC7A100T). Verified against the
rv32ui compliance suite (37/37 passing). Bare-metal C runtime with
`printf` over UART.

## Status

- **Phase 0 complete.** Foundation hardened — RTL bug fixes, C
  toolchain, Verilator lint, and CI. See
  [`TIER1_ROADMAP.md`](TIER1_ROADMAP.md) for the plan and
  [`docs/phase0_retrospective.md`](docs/phase0_retrospective.md) for
  what Phase 0 actually taught us.
- **Phase 1 next.** CSRs, traps, and M-mode. Picks up the
  `bus_error_o` and `timer_irq` wires Phase 0 left dangling for it.

## Architecture

Single-cycle RV32I core (`rtl/rv32i_core.v`) with external instruction
and data bus ports. The data bus runs through a Wishbone B4
interconnect to four slaves:

- `wb_dmem` — 4 KB data RAM
- `wb_uart` — 115200 8N1 TX/RX
- `wb_gpio` — 16 LEDs and 16 slide switches
- `wb_timer` — CLINT-style 64-bit `mtime`/`mtimecmp` with IRQ

Instruction fetch is a separate Harvard-style port; IMEM is BRAM-backed
with a `pc_next` pre-fetch path. The compliance testbench uses a
unified 16 KB memory model — see the header comment in
`tb/tb_compliance.v` and the split between `sw/link.ld` (synthesized
hardware) and `tests/link.ld` (testbench). Deep dive in
[`docs/datapath.md`](docs/datapath.md); bus architecture in
[`docs/phase1_wishbone.md`](docs/phase1_wishbone.md) (archived).

## Memory Map

| Region           | Address Range           | Size  | Module       | Notes                                |
|------------------|-------------------------|-------|--------------|--------------------------------------|
| IMEM             | 0x00000000 - 0x0000FFFF | 64 KB | `imem.v`     | 16K words, read-only, not on WB bus  |
| DMEM (RAM)       | 0x00010000 - 0x00010FFF | 4 KB  | `wb_dmem.v`  | Byte-addressable, R/W                |
| UART             | 0x80000000 - 0x8000000F | 16 B  | `wb_uart.v`  | TX data/status, RX data/status       |
| GPIO             | 0x80001000 - 0x80001007 | 8 B   | `wb_gpio.v`  | Output = LEDs, input = switches      |
| Timer            | 0x80002000 - 0x8000200F | 16 B  | `wb_timer.v` | `mtime_lo/hi`, `mtimecmp_lo/hi`      |

Accesses outside these ranges auto-ack with zero data and assert
`wb_interconnect.bus_error_o` (a combinational line currently
unconnected at `fpga_top` — consumed by Phase 1's load/store
access-fault trap).

## Verification

- **Compliance:** 37/37 rv32ui tests passing. Cycle counts in
  [`docs/compliance_results.md`](docs/compliance_results.md).
- **Unit tests:** 16 self-checking testbenches under `tb/`, parsed
  strictly for `ALL PASSED` in CI.
- **Lint:** `verilator --lint-only -Wall` clean with 29 documented
  waivers — see [`docs/lint_waivers.md`](docs/lint_waivers.md).
- **CI:** GitHub Actions runs lint + unit + compliance jobs in parallel
  on every push and PR.

## Synthesis

Last measured at commit `6edc15c` (2026-03-29, pre-Phase-0): ~1,969
LUTs / 275 FFs / 0.5 BRAM at 50 MHz on Artix-7 speed grade -1
(WNS +0.301 ns). Phase 0.1's RTL changes (reset-style conversions,
`stall_o` / `bus_error_o` ports, tightened peripheral decodes) are
expected to move utilisation by a handful of LUTs; synthesis will be
re-run the next time Vivado is opened. History in
[`docs/synth_results.md`](docs/synth_results.md); build procedure in
[`docs/synth_guide.md`](docs/synth_guide.md). Core is ~3% of the
XC7A100T — enormous headroom for Phase 4+ work.

## Build & Simulate

Requires [Icarus Verilog](http://iverilog.icarus.com/) and
[Verilator](https://www.veripool.org/verilator/) for lint. Assembly
flow uses `riscv64-unknown-elf-gcc`; C flow requires a purpose-built
rv32i/ilp32 toolchain with newlib-nano — see
[`docs/toolchain.md`](docs/toolchain.md) for why Ubuntu packages and
the Vivado bundle both fall short.

```bash
# Module testbench
make sim MOD=alu

# Full-core integration
make sim-top

# FPGA top-level — assembly "Hello, RISC-V!"
make sim-fpga

# FPGA top-level — C "Hello from C!"
make sim-fpga-c

# Build an assembly program (sw/link.ld → sim/<name>.hex)
make asm PROG=test_basic

# Build a C program (sw/c_link.ld → sim/<name>.hex + sim/<name>_dmem.hex)
make c PROG=hello_c

# Run all 37 rv32ui compliance tests
cd tests && make run-all

# Verilator lint
verilator --lint-only -Irtl -Wall rtl/*.v
```

### Writing C Programs

Any `sw/*.c` file builds to an IMEM+DMEM hex pair with
`make c PROG=<name>`. Constraints:

- **newlib-nano only.** `printf` works; `%f` deliberately disabled.
- **No heap.** `_sbrk` returns -1. Keep programs stack-only.
- **`.rodata` lives in DMEM, not IMEM.** Harvard-bus constraint — a
  load cannot reach IMEM BRAM. `sw/c_link.ld` enforces this. A
  unified-memory rework is deferred to Phase 4.

Canonical example: `sw/hello_c.c`. ELF sizes (rv32i/ilp32,
`-specs=nano.specs`, `-Os`): `.text` 4294 B / `.data` 92 B / `.bss`
328 B.

### FPGA Flow

Vivado 2025.2, Nexys4 DDR (Artix-7 XC7A100T), 50 MHz core clock (100
MHz input / 2). Pin assignments in `constraints/`; step-by-step in
[`docs/synth_guide.md`](docs/synth_guide.md).

## Documentation

| File                                                              | Purpose                                    |
|-------------------------------------------------------------------|--------------------------------------------|
| [`TIER1_ROADMAP.md`](TIER1_ROADMAP.md)                            | Active planning doc (Phases 0–6)           |
| [`docs/datapath.md`](docs/datapath.md)                            | Architecture reference                     |
| [`docs/phase1_wishbone.md`](docs/phase1_wishbone.md)              | Wishbone bus architecture (archived)       |
| [`docs/phase0_changelog.md`](docs/phase0_changelog.md)            | Phase 0 commit log                         |
| [`docs/phase0_retrospective.md`](docs/phase0_retrospective.md)    | Phase 0 lessons learned                    |
| [`docs/toolchain.md`](docs/toolchain.md)                          | C toolchain build-from-source              |
| [`docs/lint_waivers.md`](docs/lint_waivers.md)                    | Verilator waiver rationales                |
| [`docs/compliance_results.md`](docs/compliance_results.md)        | rv32ui cycle counts                        |
| [`docs/synth_results.md`](docs/synth_results.md)                  | Synthesis utilisation history              |
| [`docs/synth_guide.md`](docs/synth_guide.md)                      | Vivado build procedure                     |
| [`docs/tech_debt.md`](docs/tech_debt.md)                          | Tracked technical debt with triggers       |
| [`docs/rv32i_reference.md`](docs/rv32i_reference.md)              | ISA quick reference                        |

## Roadmap

After Phase 0 foundation, the work splits into:

- **Phase 1** — CSRs, traps, M-mode
- **Phase 2** — Interrupts (timer, UART-RX)
- **Phase 3** — RVFI + formal verification
- **Phase 4** — 5-stage pipeline refactor
- **Phase 5** — I$ / D$ caches
- **Phase 6** — Tier 1 wrap-up and capstone decision (ML accelerator,
  DSP/SDR, or OS/RTOS)

See [`TIER1_ROADMAP.md`](TIER1_ROADMAP.md) for phase gates and details.

## License

[MIT](LICENSE)
