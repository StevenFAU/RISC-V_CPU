# RV32I Single-Cycle RISC-V Core

## Project Overview
Single-cycle RV32I RISC-V processor in Verilog, targeting Nexys4 DDR (Artix-7 XC7A100T).
Must pass riscv-formal verification and communicate over UART.
Foundation for: custom accelerator integration, SoC buildout, formal verification.

## Conventions
- Language: Verilog (Icarus Verilog compatible, NOT SystemVerilog)
- Simulation: iverilog + GTKWave
- Synthesis: Vivado (xc7a100tcsg324-1)
- Tests: self-checking testbenches with $display pass/fail + riscv-tests compliance
- Definitions style: `define macros in rtl/defines.v

## Design Decisions

### Memory Map
| Region        | Address Range            | Size    | Notes                        |
|---------------|--------------------------|---------|------------------------------|
| IMEM          | 0x00000000 - 0x0000FFFF  | 64 KB   | 16K words, read-only         |
| DMEM (RAM)    | 0x00010000 - 0x0001FFFF  | 64 KB   | Byte-addressable, R/W        |
| UART TX Data  | 0x80000000               | 1 word  | Write byte to transmit       |
| UART TX Status| 0x80000004               | 1 word  | Bit 0: TX busy               |
| UART RX Data  | 0x80000008               | 1 word  | Read received byte           |
| UART RX Status| 0x8000000C               | 1 word  | Bit 0: valid (read clears)   |

Bus decoder address decode: bit 31 = 1 selects UART, else RAM.
RAM address masked to lower 16 bits (0x10000 → DMEM index 0).

### Reset Vector
- PC resets to 0x00000000

### ALU Opcode Encoding
| Code (4-bit) | Operation |
|-------------|-----------|
| 0000        | ADD       |
| 0001        | SUB       |
| 0010        | AND       |
| 0011        | OR        |
| 0100        | XOR       |
| 0101        | SLL       |
| 0110        | SRL       |
| 0111        | SRA       |
| 1000        | SLT       |
| 1001        | SLTU      |

### Pipeline-Readiness Notes
- Module interfaces use clean input/output ports (no internal global state)
- PC, register file, and memory interfaces designed for easy register insertion
- Control signals grouped for future pipeline register staging

### Future Hooks
- custom-0 opcode (0001011) recognized in decoder, generates default NOP-like behavior
- Bus interface between core and memories kept clean for future Wishbone conversion
- Architectural state (PC, regfile, memory) accessible from top level for RVFI trace

## Architecture Note: External Memory Ports
As of Phase 4, `rv32i_core.v` does NOT contain internal memories. It exposes:
- **Instruction fetch bus**: `imem_addr` (out), `imem_data` (in)
- **Data memory bus**: `dmem_addr`, `dmem_wdata`, `dmem_we`, `dmem_re`, `dmem_funct3` (out), `dmem_rdata` (in)

Memory (IMEM, DMEM, or unified) is instantiated by the testbench or top-level wrapper.
This is intentional — it future-proofs for SoC bus integration and allows the compliance
testbench to use unified memory.

For synthesis/FPGA, `fpga_top.v` instantiates IMEM, DMEM, bus decoder, and UART alongside the core.

## Phase 5: FPGA & UART
- `uart_tx.v` / `uart_rx.v` — 8N1, parameterized CLK_FREQ/BAUD_RATE, all tests pass (TX, RX, 24-byte loopback)
- `bus_decoder.v` — combinational address decode, routes data bus to RAM or UART (8/8 tests pass)
- `fpga_top.v` — synthesis-ready top-level for Nexys4 DDR (100MHz, 115200 baud USB-UART)
- `constraints/nexys4ddr.xdc` — CLK100MHZ (E3), CPU_RESETN (C12), UART_RXD_OUT/TX (D4), UART_TXD_IN/RX (C4), LEDs
- `sw/hello.S` — prints "Hello, RISC-V!\n" via memory-mapped UART (simulation verified)
- See `docs/synth_guide.md` for Vivado synthesis steps

### FPGA Pin Assignments
| Signal       | Pin | Direction | Notes                          |
|-------------|-----|-----------|--------------------------------|
| CLK100MHZ    | E3  | Input     | 100MHz oscillator              |
| CPU_RESETN   | C12 | Input     | Active-low reset button        |
| UART_TXD_IN  | C4  | Input     | FTDI TX → FPGA RX             |
| UART_RXD_OUT | D4  | Output    | FPGA TX → FTDI RX             |
| LED0         | H17 | Output    | UART TX busy                   |
| LED1         | K15 | Output    | UART RX valid                  |

## Phase 4 Compliance
- **37/37 rv32ui tests pass** (all RV32I user-mode integer instructions)
- No bugs found in the core — all tests passed on first run
- Custom test environment (no CSR support needed for user-mode tests)
- See `docs/compliance_results.md` for full results table

## Build
```
make sim MOD=<module>    # Run single module testbench
make sim-top             # Run full-core integration test
make wave MOD=<module>   # Open GTKWave
make asm PROG=<name>     # Assemble .S to .hex
make clean               # Remove artifacts

# Compliance tests (from tests/ directory):
make run TEST=add        # Run single compliance test
make run-all             # Run all 37 rv32ui tests

# Firmware (from rv32i/ directory):
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles \
    -T sw/hello_link.ld -o sim/hello.elf sw/hello.S
python3 sim/make_imem_hex.py sim/hello.hex sim/firmware.hex
```
