# Synthesis Results — RV32I Core on Nexys4 DDR

## Target
- Device: Artix-7 XC7A100T (`xc7a100tcsg324-1`)
- Clock: 50 MHz (100 MHz input, /2 divider in fpga_top)
- Top module: `fpga_top`
- Tool: Vivado 2025.2

## Resource Utilization

| Resource       | Used  | Available | %      |
|----------------|-------|-----------|--------|
| Slice LUTs     | 9,711 | 63,400    | 15.32% |
| — as Logic     | 1,475 |           | 2.33%  |
| — as Memory    | 8,236 | 19,000    | 43.35% |
| Slice FFs      | 114   | 126,800   | 0.09%  |
| Block RAM      | 0     | 135       | 0.00%  |
| DSP            | 0     | 240       | 0.00%  |

## Timing

- WNS (Worst Negative Slack): +0.338 ns
- WHS (Worst Hold Slack): +0.064 ns
- Clock frequency achieved: 50 MHz (all constraints met)
- TNS: 0.000 ns
- Number of failing endpoints: 0

## Notes

- IMEM (16K x 32-bit) and DMEM (16K x 32-bit) mapped to distributed RAM (LUT RAM),
  not block RAM. This accounts for the high LUT-as-Memory usage (43.35%).
- The byte-enable read/write pattern in dmem.v prevents Vivado from inferring BRAM.
  A future optimization could use separate read/write address ports or Vivado RAM
  primitives to force BRAM inference, freeing ~8,200 LUTs.
- At 100 MHz the design failed timing (WNS -8.527 ns). The /2 clock divider was
  added to meet timing at 50 MHz with comfortable margin.
- Core logic uses only ~1,475 LUTs (2.33%), leaving substantial room for the
  planned spiking neural network coprocessor.
