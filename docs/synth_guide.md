# Vivado Synthesis Guide — RV32I Core on Nexys4 DDR

## Prerequisites
- Vivado 2023.x or later (free WebPACK edition works)
- Nexys4 DDR board connected via USB
- `firmware.hex` generated from `hello.S` (see step 0)

## Step 0: Prepare Firmware

The IMEM initialization file (`sim/firmware.hex`) is checked into the repo and ready to use.
To regenerate it from source (requires `riscv64-unknown-elf-gcc`):

```bash
# Build hello.S → word-addressed hex for IMEM
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles \
    -T sw/hello_link.ld -o sim/hello.elf sw/hello.S
riscv64-unknown-elf-objcopy -O verilog sim/hello.elf sim/hello_byte.hex
python3 sim/make_imem_hex.py sim/hello_byte.hex sim/firmware.hex
rm -f sim/hello_byte.hex
```

The data section (string bytes for "Hello, RISC-V!\r\n") must also be loaded into DMEM.
The checked-in `sim/dmem_init.hex` contains:
```
48 65 6C 6C 6F 2C 20 52 49 53 43 2D 56 21 0D 0A 00
```

## Step 1: Create Vivado Project

1. Open Vivado → Create Project → RTL Project
2. Part: `xc7a100tcsg324-1`
3. Add RTL sources from `rtl/`:
   - `rv32i_core.v`, `pc.v`, `regfile.v`, `immgen.v`, `control.v`
   - `alu_decoder.v`, `alu.v`, `imem.v`, `dmem.v`
   - `bus_decoder.v`, `uart_tx.v`, `uart_rx.v`
   - `fpga_top.v`, `defines.v`
4. Add constraints: `constraints/nexys4ddr.xdc`
5. Set `fpga_top` as top module

## Step 2: Place Hex Files

`fpga_top.v` uses parameterized `INIT_FILE` paths (default: `firmware.hex` and
`dmem_init.hex`). Vivado looks for these relative to the synthesis run directory.

Copy both files into the Vivado project root **and** the `synth_1` run directory:
```bash
cp sim/firmware.hex <vivado_project>/
cp sim/dmem_init.hex <vivado_project>/
cp sim/firmware.hex <vivado_project>/<project_name>.runs/synth_1/
cp sim/dmem_init.hex <vivado_project>/<project_name>.runs/synth_1/
```

No edits to `fpga_top.v` are needed — initialization is built in.

## Step 3: Synthesize

1. Run **Synthesis** (Flow → Run Synthesis)
2. Check Messages for warnings — watch for:
   - "Inferred latch" — should NOT appear (all logic is register or combinational)
   - "Signal X is unconnected" — normal for unused debug signals
   - "Multi-driven net" — must fix if this appears
3. Review **Utilization** in the synthesis report

## Step 4: Implement

1. Run **Implementation** (Flow → Run Implementation)
2. Check **Timing Summary**:
   - WNS must be ≥ 0. The core meets timing at 50 MHz (100 MHz board clock with /2 divider). If WNS is negative, check critical path in timing report.

## Step 5: Generate Bitstream

1. Flow → Generate Bitstream
2. Wait for completion

## Step 6: Program the FPGA

1. Open Hardware Manager
2. Auto Connect → select the Nexys4 DDR
3. Program Device → select the `.bit` file
4. Click Program

## Step 7: Test UART Output

1. Open a serial terminal:
   ```bash
   # Linux:
   minicom -D /dev/ttyUSB1 -b 115200
   # or:
   picocom -b 115200 /dev/ttyUSB1
   # or:
   screen /dev/ttyUSB1 115200
   ```
   (Port may be `/dev/ttyUSB0` or `/dev/ttyUSB1` — check `dmesg | grep tty`)

2. Settings: 115200 baud, 8 data bits, No parity, 1 stop bit (8N1)

3. Press the **CPU_RESETN** button (center button on Nexys4 DDR)

4. You should see: `Hello, RISC-V!` followed by a newline

5. LED0 will blink briefly during each character transmission

## Troubleshooting

- **No output**: Check UART pin assignment — `UART_RXD_OUT` (D4) is FPGA TX, `UART_TXD_IN` (C4) is FPGA RX. These names are from the FTDI chip's perspective.
- **Garbled output**: Verify baud rate is 115200 in both hardware (CLK_FREQ/BAUD_RATE) and terminal.
- **Timing failure at 50 MHz**: The single-cycle design meets timing at 50 MHz. At 100 MHz it fails with ~8.5 ns negative slack due to the combinational path through distributed RAM. Future BRAM migration should improve this.
- **BRAM not initialized**: Ensure hex files are in the correct Vivado project path.

## Resource Budget

After synthesis, record utilization in `docs/synth_results.md`.
The Artix-7 XC7A100T has:
- 63,400 LUTs
- 126,800 FFs
- 135 Block RAMs (36Kb each)
- 240 DSP slices

A single-cycle RV32I core typically uses <5% of LUTs on this device,
leaving substantial room for the future spiking neural network coprocessor.
