# RV32I Single-Cycle RISC-V CPU

A single-cycle RV32I RISC-V processor implemented in Verilog, targeting the Digilent Nexys4 DDR (Artix-7 XC7A100T) FPGA.

## Features

- Full RV32I instruction set (37/37 rv32ui compliance tests pass)
- Single-cycle datapath: PC, register file, ALU, immediate generator, control unit
- External memory bus ports (SoC-ready architecture)
- Byte-addressable data memory with LB/LH/LW/LBU/LHU/SB/SH/SW support
- Memory-mapped UART TX/RX (115200 baud, 8N1)
- Bus decoder for RAM/UART address space routing
- FPGA-verified: prints "Hello, RISC-V!" over USB-UART

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ rv32i_core                                          │
│  ┌────┐  ┌──────┐  ┌────────┐  ┌─────┐  ┌───────┐ │
│  │ PC │→│ IMEM  │→│ Control │→│ ALU  │→│ WB Mux│ │
│  └────┘  │ Bus   │  │ Decode  │  └─────┘  └───────┘ │
│          └──────┘  └────────┘                       │
│  ┌────────┐  ┌────────┐  ┌──────┐                   │
│  │Regfile │  │ImmGen  │  │ DMEM │                   │
│  └────────┘  └────────┘  │ Bus  │                   │
│                          └──────┘                   │
└─────────────────────────────────────────────────────┘
         │                        │
    imem_addr/data          dmem_addr/data/we/re
         │                        │
┌────────┴────────┐    ┌──────────┴──────────┐
│      IMEM       │    │    Bus Decoder      │
│  (16K words)    │    │  ┌──────┐ ┌──────┐  │
└─────────────────┘    │  │ DMEM │ │ UART │  │
                       │  │(64KB)│ │TX/RX │  │
                       │  └──────┘ └──────┘  │
                       └─────────────────────┘
```

The core does **not** contain internal memories — it exposes instruction fetch and data memory bus ports. Memory, peripherals, and bus routing are instantiated by the top-level wrapper (`fpga_top.v`), making the core ready for SoC integration.

## Memory Map

| Region         | Address Range           | Size  | Notes                     |
|----------------|-------------------------|-------|---------------------------|
| IMEM           | 0x00000000 - 0x0000FFFF | 64 KB | 16K words, read-only      |
| DMEM (RAM)     | 0x00010000 - 0x0001FFFF | 64 KB | Byte-addressable, R/W     |
| UART TX Data   | 0x80000000              | 1 word| Write byte to transmit    |
| UART TX Status | 0x80000004              | 1 word| Bit 0: TX busy            |
| UART RX Data   | 0x80000008              | 1 word| Read received byte        |
| UART RX Status | 0x8000000C              | 1 word| Bit 0: valid (read clears)|

## Directory Structure

```
├── rtl/                  # Synthesizable Verilog
│   ├── rv32i_core.v      # CPU core (datapath + control)
│   ├── pc.v              # Program counter
│   ├── regfile.v         # 32x32 register file
│   ├── alu.v             # 10-operation ALU
│   ├── alu_decoder.v     # ALU control decoder
│   ├── control.v         # Main control decoder
│   ├── immgen.v          # Immediate generator (R/I/S/B/U/J)
│   ├── imem.v            # Instruction memory (word-addressed)
│   ├── dmem.v            # Data memory (word-based, byte enables)
│   ├── bus_decoder.v     # Address decoder (RAM/UART routing)
│   ├── uart_tx.v         # UART transmitter (8N1)
│   ├── uart_rx.v         # UART receiver (8N1)
│   ├── fpga_top.v        # FPGA top-level wrapper
│   └── defines.v         # Opcode/funct macros
├── tb/                   # Testbenches
├── sim/                  # Simulation hex files and scripts
├── sw/                   # Assembly programs and linker scripts
├── tests/                # Compliance test infrastructure
├── constraints/          # Vivado XDC constraints
└── docs/                 # Documentation and reference
```

## Build & Simulate

Requires [Icarus Verilog](http://iverilog.icarus.com/) and the RISC-V toolchain (`riscv64-unknown-elf-gcc`).

```bash
# Run a single module testbench
make sim MOD=alu

# Run full-core integration test
make sim-top

# Assemble firmware
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles \
    -T sw/hello_link.ld -o sim/hello.elf sw/hello.S
python3 sim/make_imem_hex.py sim/hello.hex sim/firmware.hex
```

### Compliance Tests

The compliance tests require the [riscv-tests](https://github.com/riscv-software-src/riscv-tests) repo. To set up:

```bash
# One-time setup: download test sources
cd tests
./setup.sh

# Run all 37 rv32ui tests
make run-all

# Run a single test
make run TEST=add
```

## FPGA Synthesis

Requires Vivado 2023.x+ (free WebPACK edition). See [docs/synth_guide.md](docs/synth_guide.md) for step-by-step instructions.

**Target:** Nexys4 DDR (Artix-7 XC7A100T)
**Core clock:** 50 MHz (100 MHz / 2 divider)
**Timing:** WNS +0.338 ns (met)

### Resource Utilization

| Resource       | Used  | Available | %      |
|----------------|-------|-----------|--------|
| Slice LUTs     | 9,711 | 63,400    | 15.32% |
| — as Logic     | 1,475 |           | 2.33%  |
| — as Memory    | 8,236 | 19,000    | 43.35% |
| Slice FFs      | 114   | 126,800   | 0.09%  |
| Block RAM      | 0     | 135       | 0.00%  |
| DSP            | 0     | 240       | 0.00%  |

Note: IMEM and DMEM are currently mapped to distributed RAM (LUT RAM) rather than block RAM. This uses more LUTs but meets timing. A future optimization would restructure the memory interfaces for BRAM inference.

### Pin Assignments

| Signal       | Pin | Direction | Notes                  |
|-------------|-----|-----------|------------------------|
| CLK100MHZ    | E3  | Input     | 100 MHz oscillator     |
| CPU_RESETN   | C12 | Input     | Active-low reset       |
| UART_TXD_IN  | C4  | Input     | FTDI TX -> FPGA RX     |
| UART_RXD_OUT | D4  | Output    | FPGA TX -> FTDI RX     |
| LED0         | H17 | Output    | UART TX busy           |
| LED1         | K15 | Output    | UART RX valid          |

## Compliance

All 37 RV32I user-mode integer instruction tests pass:

```
add addi and andi auipc beq bge bgeu blt bltu bne
jal jalr lb lbu lh lhu lui lw or ori
sb sh sll slli slt slti sltiu sltu sra srai
srl srli sub sw xor xori
```

(fence_i excluded — requires instruction cache, not applicable to single-cycle)

## Future Work

- Custom accelerator integration (spiking neural network coprocessor)
- SoC buildout (Wishbone bus, more peripherals)
- Formal verification (riscv-formal)
- Pipeline (5-stage) for higher clock frequency

## License

[MIT](LICENSE)
