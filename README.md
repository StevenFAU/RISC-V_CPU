# RV32I Single-Cycle RISC-V CPU

A single-cycle RV32I RISC-V processor implemented in Verilog, targeting the Digilent Nexys4 DDR (Artix-7 XC7A100T) FPGA.

## Features

- Full RV32I instruction set (37/37 rv32ui compliance tests pass)
- Single-cycle datapath: PC, register file, ALU, immediate generator, control unit
- External memory bus ports (SoC-ready architecture)
- Wishbone B4 classic bus fabric with 4 slave peripherals
- Byte-addressable data memory with LB/LH/LW/LBU/LHU/SB/SH/SW support
- Memory-mapped UART TX/RX (115200 baud, 8N1)
- Memory-mapped GPIO (16 LEDs + 16 slide switches)
- CLINT-style 64-bit timer with comparator and IRQ output
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
    imem_addr/data          dmem_addr/data/we/re/funct3
         │                        │
┌────────┴────────┐    ┌──────────┴──────────┐
│      IMEM       │    │    wb_master        │
│  (16K words)    │    │ (core → Wishbone)   │
└─────────────────┘    └──────────┬──────────┘
                                  │
                       ┌──────────┴──────────┐
                       │  wb_interconnect    │
                       │  (address decode)   │
                       ├──────┬──────┬───────┤
                       │      │      │       │
                  ┌────┴┐ ┌──┴──┐ ┌─┴──┐ ┌──┴───┐
                  │DMEM │ │UART │ │GPIO│ │TIMER │
                  │64KB │ │TX/RX│ │LED │ │CLINT │
                  └─────┘ └─────┘ │ SW │ └──────┘
                                  └────┘
```

The core does **not** contain internal memories — it exposes instruction fetch and data memory bus ports. Memory, peripherals, and bus routing are instantiated by the top-level wrapper (`fpga_top.v`), making the core ready for SoC integration.

The Wishbone interconnect routes the core's data bus to the correct slave based on address. Each peripheral is a standard Wishbone B4 slave — new peripherals plug in by adding a slave port and address decode line.

## Memory Map

| Region           | Address Range           | Size  | Module       | Notes                     |
|------------------|-------------------------|-------|--------------|---------------------------|
| IMEM             | 0x00000000 - 0x0000FFFF | 64 KB | `imem.v`     | 16K words, read-only, not on WB bus |
| DMEM (RAM)       | 0x00010000 - 0x0001FFFF | 64 KB | `wb_dmem.v`  | Byte-addressable, R/W     |
| UART TX Data     | 0x80000000              | 1 word| `wb_uart.v`  | Write byte to transmit    |
| UART TX Status   | 0x80000004              | 1 word|              | Bit 0: TX busy            |
| UART RX Data     | 0x80000008              | 1 word|              | Read received byte        |
| UART RX Status   | 0x8000000C              | 1 word|              | Bit 0: valid (read clears)|
| GPIO Output      | 0x80001000              | 1 word| `wb_gpio.v`  | Drives LED[15:0]          |
| GPIO Input       | 0x80001004              | 1 word|              | Reads SW[15:0]            |
| Timer mtime_lo   | 0x80002000              | 1 word| `wb_timer.v` | Free-running counter [31:0]  |
| Timer mtime_hi   | 0x80002004              | 1 word|              | Free-running counter [63:32] |
| Timer mtimecmp_lo| 0x80002008              | 1 word|              | Comparator [31:0]         |
| Timer mtimecmp_hi| 0x8000200C              | 1 word|              | Comparator [63:32]        |

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
│   ├── wb_master.v       # Wishbone master bridge (core → WB)
│   ├── wb_interconnect.v # Address decoder + return mux
│   ├── wb_dmem.v         # Data memory WB slave wrapper
│   ├── wb_uart.v         # UART TX/RX WB slave
│   ├── wb_gpio.v         # GPIO WB slave (LEDs + switches)
│   ├── wb_timer.v        # CLINT-style timer WB slave
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

# Run FPGA top-level UART test (Hello, RISC-V!)
make sim MOD=fpga_top

# Assemble firmware
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles \
    -T sw/hello_link.ld -o sim/hello.elf sw/hello.S
riscv64-unknown-elf-objcopy -O verilog sim/hello.elf sim/hello_byte.hex
python3 sim/make_imem_hex.py sim/hello_byte.hex sim/firmware.hex
```

> **Note:** Simulation may emit `$readmemh` warnings about insufficient words in hex files.
> This is expected — test programs are smaller than the full memory arrays. These warnings
> are harmless and do not affect results.

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

| Signal         | Pin(s)  | Direction | Notes                       |
|----------------|---------|-----------|------------------------------|
| CLK100MHZ      | E3      | Input     | 100 MHz oscillator           |
| CPU_RESETN     | C12     | Input     | Active-low reset             |
| UART_TXD_IN    | C4      | Input     | FTDI TX -> FPGA RX           |
| UART_RXD_OUT   | D4      | Output    | FPGA TX -> FTDI RX           |
| LED[15:0]      | H17...  | Output    | GPIO output register         |
| SW[15:0]       | J15...  | Input     | GPIO input (slide switches)  |

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

- Formal verification (riscv-formal with RVFI interface)
- Pipeline (5-stage) for higher clock frequency
- Wait-state support in `wb_master` for slower peripherals
- Custom accelerator integration (spiking neural network coprocessor)
- BRAM inference for IMEM/DMEM

## License

[MIT](LICENSE)
