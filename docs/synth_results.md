# Synthesis Results — RV32I Core on Nexys4 DDR

## Target
- Device: Artix-7 XC7A100T (`xc7a100tcsg324-1`)
- Clock: 50 MHz (100 MHz input, /2 divider in fpga_top)
- Top module: `fpga_top`
- Tool: Vivado 2025.2

## Resource Utilization (pre-BRAM, baseline)

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

- **IMEM BRAM migration (pending re-synthesis):** `imem.v` now uses `SYNC_READ=1`
  with `(* ram_style = "block" *)` and bounded address width. Vivado should infer
  ~14 BRAM36 blocks for IMEM (16K x 32-bit = 512 Kbit), dropping LUT-as-Memory
  from ~8,236 to ~4,100 (DMEM only). Re-run synthesis to confirm and update this table.
- DMEM (16K x 32-bit) remains as distributed RAM (LUT RAM). Combinational reads
  are required by the single-cycle core — BRAM synchronous reads would need pipeline
  changes. Explicitly marked with `(* ram_style = "distributed" *)`.
- At 100 MHz the design failed timing (WNS -8.527 ns). The /2 clock divider was
  added to meet timing at 50 MHz with comfortable margin.
- Core logic uses only ~1,475 LUTs (2.33%), leaving substantial room for the
  planned spiking neural network coprocessor.
