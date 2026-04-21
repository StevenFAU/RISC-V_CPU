> **Archived — Phase 1 complete.** This document is the planning record for the Wishbone B4 bus integration phase, completed 2026-04-21. The four-slave fabric (DMEM, UART, GPIO, timer) is implemented, FPGA-verified, and tagged. Superseded by [`TIER1_ROADMAP.md`](../TIER1_ROADMAP.md) as the active planning document.

# CLAUDE.md — Wishbone Bus Integration

## Project Overview

This project adds a **Wishbone B4 classic** bus fabric to an existing single-cycle RV32I RISC-V CPU, replacing the current point-to-point `bus_decoder.v` with a proper interconnect. The goal is an extensible SoC where future peripherals (SNN coprocessor, PCIe bridge, DSP) plug in as standard Wishbone slaves.

**Target:** Digilent Nexys4 DDR (Artix-7 XC7A100T), 50 MHz core clock, Vivado 2025.2.

**Repo:** `RISC-V_CPU/` — all work happens in this repo.

---

## Current Architecture (What Exists)

### Core Interface (`rtl/rv32i_core.v`)

The CPU exposes external bus ports — it does NOT contain internal memories:

```
Instruction fetch:  imem_addr[31:0] → imem_data[31:0]
Data bus:           dmem_addr[31:0], dmem_wdata[31:0], dmem_rdata[31:0]
                    dmem_we, dmem_re, dmem_funct3[2:0]
Debug:              debug_pc[31:0], debug_instr[31:0]
```

The data bus is active every cycle (single-cycle core, no stalls). `dmem_addr` is the ALU result. `dmem_funct3` encodes load/store width (byte/half/word, signed/unsigned per `rtl/defines.v`).

### Current Bus Decoder (`rtl/bus_decoder.v`)

Point-to-point combinational decode. Routes data bus between RAM and UART:

| Region         | Address Range             | Decode Logic                     |
|----------------|---------------------------|----------------------------------|
| DMEM (RAM)     | `0x00010000 – 0x0001FFFF` | `dmem_addr[31:16] == 16'h0001`   |
| UART TX/RX     | `0x80000000 – 0x8000000F` | `dmem_addr[31:28] == 4'h8`       |

UART has a latched RX valid with registered clear (1-cycle delay). TX send is combinational.

### Top-Level Wrapper (`rtl/fpga_top.v`)

Wires everything together: core → bus_decoder → dmem + UART TX/RX. Clock is 100 MHz divided to 50 MHz with a 2-FF reset synchronizer. IMEM is separate (combinational read, word-addressed).

### Key Files

```
rtl/rv32i_core.v     — CPU core (DO NOT MODIFY for this phase)
rtl/bus_decoder.v    — REPLACE with Wishbone interconnect
rtl/fpga_top.v       — MODIFY to wire new interconnect
rtl/dmem.v           — WRAP with Wishbone slave interface
rtl/uart_tx.v        — Existing UART TX (keep as-is, wrap)
rtl/uart_rx.v        — Existing UART RX (keep as-is, wrap)
rtl/imem.v           — Instruction memory (unchanged, not on data bus)
rtl/defines.v        — Opcode/funct macros (unchanged)
```

---

## Target Architecture (What We're Building)

### Wishbone B4 Specification

Use **Wishbone B4 classic single-cycle** (not pipelined or burst — keep it simple for a single-cycle CPU). Signals per the spec:

| Signal       | Width | Direction (master) | Description                  |
|--------------|-------|--------------------|------------------------------|
| `wb_cyc_o`   | 1     | output             | Bus cycle active             |
| `wb_stb_o`   | 1     | output             | Strobe — valid transfer      |
| `wb_we_o`    | 1     | output             | Write enable                 |
| `wb_adr_o`   | 32    | output             | Address                      |
| `wb_dat_o`   | 32    | output             | Write data (master → slave)  |
| `wb_sel_o`   | 4     | output             | Byte lane selects            |
| `wb_dat_i`   | 32    | input              | Read data (slave → master)   |
| `wb_ack_i`   | 1     | input              | Slave acknowledge            |

For classic single-cycle: `cyc` and `stb` assert together, slave responds with `ack` in the same cycle (combinational ack for SRAM-like peripherals). No wait states for phase 1.

**Known Limitation:** The current `wb_master.v` is zero-wait-state only. It accepts `wb_ack_i` for port compliance but does not use it to gate read data or stall the core. All slaves must return combinational ack. Future peripherals with latency (external SRAM, SPI flash, PCIe) will require upgrading `wb_master` to feed a stall/ready signal back into `rv32i_core`.

### New Address Map

| Region       | Address Range             | Size   | Slave Module        |
|--------------|---------------------------|--------|---------------------|
| IMEM         | `0x00000000 – 0x0000FFFF` | 64 KB  | `imem.v` (not on WB)|
| DMEM (RAM)   | `0x00010000 – 0x00010FFF` | 4 KB   | `wb_dmem.v`         |
| UART         | `0x80000000 – 0x8000000F` | 16 B   | `wb_uart.v`         |
| GPIO         | `0x80001000 – 0x80001007` | 8 B    | `wb_gpio.v`         |
| TIMER (CLINT)| `0x80002000 – 0x8000200F` | 16 B   | `wb_timer.v`        |
| *Reserved*   | `0x80003000+`             |        | Future peripherals  |

Address decode uses upper bits:

- `addr[31:16] == 0x0001` → DMEM
- `addr[31:12] == 0x80000` → UART
- `addr[31:12] == 0x80001` → GPIO
- `addr[31:12] == 0x80002` → TIMER

### New Modules to Create

```
rtl/wb_master.v       — Bridges core dmem bus → Wishbone master signals
                        Generates wb_sel_o from dmem_funct3 + dmem_addr[1:0]
                        Drives cyc/stb on any dmem_we or dmem_re

rtl/wb_interconnect.v — Address decoder + mux
                        Steers master to correct slave based on address
                        Muxes slave dat_i/ack_i back to master
                        Single-master, multiple-slave (no arbiter needed)

rtl/wb_dmem.v         — Wraps existing dmem.v with Wishbone slave interface
                        Translates wb_sel back to funct3 for dmem byte enables
                        Immediate ack (combinational)

rtl/wb_uart.v         — Wraps existing uart_tx.v + uart_rx.v with Wishbone slave
                        Replaces the UART register logic currently in bus_decoder.v
                        Same register layout: TX data @ +0x0, TX status @ +0x4,
                        RX data @ +0x8, RX status @ +0xC
                        Immediate ack

rtl/wb_gpio.v         — NEW peripheral
                        Reg 0x0: output register → drives active-high LEDs[15:0]
                        Reg 0x4: input register  ← reads slide switches SW[15:0]
                        Maps directly to Nexys4 DDR board I/O

rtl/wb_timer.v        — NEW peripheral (CLINT-style)
                        Reg 0x0: mtime_lo    (32-bit, R/W)
                        Reg 0x4: mtime_hi    (32-bit, R/W)
                        Reg 0x8: mtimecmp_lo (32-bit, R/W)
                        Reg 0xC: mtimecmp_hi (32-bit, R/W)
                        Free-running 64-bit counter at 50 MHz
                        Output: timer_irq (mtime >= mtimecmp)
                        IRQ output exposed but NOT wired to core (no CSR yet)
```

### Updated `fpga_top.v` Wiring

```
rv32i_core → wb_master → wb_interconnect ─┬→ wb_dmem  (wraps dmem.v)
                                           ├→ wb_uart  (wraps uart_tx.v + uart_rx.v)
                                           ├→ wb_gpio  (new — LEDs + switches)
                                           └→ wb_timer (new — 64-bit counter)
```

IMEM remains directly wired to `rv32i_core.imem_addr/imem_data` — NOT on the Wishbone bus.

---

## Implementation Sequence

### Phase 1: wb_master + wb_interconnect + wb_dmem

1. Create `wb_master.v` — translate core's dmem signals to Wishbone
2. Create `wb_dmem.v` — wrap `dmem.v` with Wishbone slave port
3. Create `wb_interconnect.v` — start with single slave (DMEM only)
4. Update `fpga_top.v` — replace `bus_decoder` instantiation with new modules
5. Write `tb/tb_wb_master.v` and `tb/tb_wb_interconnect.v`
6. **Gate:** All 37 compliance tests pass (`make test`). UART will be broken (expected).

### Phase 2: wb_uart

1. Create `wb_uart.v` — port UART register logic from `bus_decoder.v` lines 62–131
2. Add UART slave port to `wb_interconnect.v` address decode
3. Write `tb/tb_wb_uart.v`
4. **Gate:** `hello.S` prints "Hello, RISC-V!" over UART. Compliance tests still pass.

### Phase 3: wb_gpio

1. Create `wb_gpio.v` — output to LEDs, input from switches
2. Add GPIO slave port to `wb_interconnect.v`
3. Update `constraints/nexys4ddr.xdc` — add LED[15:0] and SW[15:0] pins
4. Write `sw/gpio_test.S` — reads switches, writes to LEDs
5. Write `tb/tb_wb_gpio.v`
6. **Gate:** Physical test — flip switches, see LEDs mirror.

### Phase 4: wb_timer

1. Create `wb_timer.v` — 64-bit free-running counter + comparator
2. Add timer slave port to `wb_interconnect.v`
3. Write `sw/timer_test.S` — polls mtime, blinks LED at ~1 Hz via GPIO
4. Write `tb/tb_wb_timer.v`
5. **Gate:** LED blinks at correct rate on hardware. Timer IRQ toggles in sim.

---

## Design Rules

### Verilog Style

- **Language:** Verilog-2001 (not SystemVerilog). Match existing codebase.
- **Naming:** `wb_` prefix for all Wishbone-related modules and signals.
- **Reset:** Synchronous active-high `rst` (already synchronized in `fpga_top.v`).
- **Headers:** Comment block at top of every module. Section separators with `// ===` bars.
- **No latches:** Every `always @(*)` must have defaults for all outputs.
- **Widths:** Explicit bit widths on all signals and constants. No bare integers.
- **Ports:** Use `input wire` / `output wire` / `output reg` — match existing style.

### Wishbone Compliance

- Follow Wishbone B4 spec naming: `cyc`, `stb`, `we`, `adr`, `dat_o`, `dat_i`, `sel`, `ack`.
- Master port suffix: `_o` for outputs, `_i` for inputs.
- Slave port suffix: `_i` for inputs, `_o` for outputs.
- All slaves must assert `ack` combinationally with `stb` for phase 1 (no wait states).
- `ack` must only assert when `cyc & stb` are both high.

### wb_sel Encoding (Byte Lane Selects)

Derived from `dmem_funct3` and `dmem_addr[1:0]` in `wb_master.v`:

| funct3 | addr[1:0] | wb_sel | Operation  |
|--------|-----------|--------|------------|
| 000/100| 00        | 0001   | LB/LBU/SB  |
| 000/100| 01        | 0010   | LB/LBU/SB  |
| 000/100| 10        | 0100   | LB/LBU/SB  |
| 000/100| 11        | 1000   | LB/LBU/SB  |
| 001/101| 00        | 0011   | LH/LHU/SH  |
| 001/101| 10        | 1100   | LH/LHU/SH  |
| 010    | 00        | 1111   | LW/SW      |

The existing `dmem.v` handles byte/half/word internally via `funct3`. The `wb_dmem` wrapper should translate `wb_sel` back to `funct3` + address offset for the inner `dmem`, preserving the verified logic. Do NOT rewrite `dmem.v` internals.

---

## Testing

- **Simulation:** Icarus Verilog (`iverilog` / `vvp`). Testbenches go in `tb/`.
- **Compliance gate:** `tests/` directory has rv32ui compliance infrastructure. `make test` must pass at every phase. These are the regression gate — never break them.
- **Hardware:** Vivado 2025.2, constraints in `constraints/nexys4ddr.xdc`.
- **New testbenches:** Each new module gets a self-checking testbench (`$display` pass/fail).

---

## Nexys4 DDR Resources

### FPGA (Artix-7 XC7A100T)

- LUTs: ~63,400 available (current core: ~2,000)
- BRAMs: 135 × 36Kb (current: 2 for IMEM + DMEM)
- Fmax target: 50 MHz — interconnect must not become critical path

### Board I/O for GPIO Peripheral

- 16 LEDs (active-high): LED[15:0]
- 16 slide switches: SW[15:0]
- See Nexys4 DDR reference manual for pin assignments

### Existing Pin Constraints (`constraints/nexys4ddr.xdc`)

Currently maps: `CLK100MHZ`, `CPU_RESETN`, `UART_TXD_IN`, `UART_RXD_OUT`, `LED0`, `LED1`.
GPIO phase will add LED[2]–LED[15] and SW[0]–SW[15].

---

## What NOT to Change

| File               | Reason                                              |
|--------------------|-----------------------------------------------------|
| `rv32i_core.v`     | Verified core — frozen for this phase               |
| `imem.v`           | Not on data bus, directly wired to core             |
| `dmem.v` internals | Wrap it with `wb_dmem.v`, don't rewrite             |
| `uart_tx.v`        | Wrap with `wb_uart.v`, don't modify                 |
| `uart_rx.v`        | Wrap with `wb_uart.v`, don't modify                 |
| `defines.v`        | Opcode/funct macros — unchanged                     |
| `tests/*`          | Compliance infrastructure — never break             |

---

## Future Work (NOT This Phase)

Planned sequence after Wishbone is complete and verified:

1. **Formal verification** — RVFI interface + riscv-formal on single-cycle core
2. **5-stage pipeline** — Refactor core internals; Wishbone interface stays stable
3. **SNN coprocessor** — Izhikevich neuron array as Wishbone slave
4. **Neural net accelerator** — INT8 inference engine as Wishbone slave
5. **PCIe bridge** — Wishbone-to-PCIe for host DMA
6. **DSP pipeline** — FIR/FFT as Wishbone slave, HackRF integration

The interconnect is designed so each future peripheral is just a new slave port + address decode line.

---

## Quick Reference

```
Simulate:         make sim
Compliance test:  make test        # All 37 rv32ui tests must pass
Synthesize:       make synth       # Vivado 2025.2
Program FPGA:     make program
UART terminal:    screen /dev/ttyUSB1 115200
```
