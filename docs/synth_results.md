# Synthesis Results — RV32I SoC on Nexys4 DDR

## Target
- Device: Artix-7 XC7A100T (`xc7a100tcsg324-1`)
- Clock: 50 MHz (100 MHz input, /2 divider in fpga_top)
- Top module: `fpga_top`
- Tool: Vivado 2025.2

## Resource Utilization

| Resource       | Used  | Available | %      |
|----------------|-------|-----------|--------|
| Slice LUTs     | 1,969 | 63,400    | 3.11%  |
| — as Logic     | 1,413 |           | 2.23%  |
| — as Memory    | 556   | 19,000    | 2.93%  |
| Slice FFs      | 275   | 126,800   | 0.22%  |
| Block RAM      | 0.5   | 135       | 0.37%  |
| DSP            | 0     | 240       | 0.00%  |

## Timing

- WNS (Worst Negative Slack): +0.301 ns
- WHS (Worst Hold Slack): +0.194 ns
- Clock frequency achieved: 50 MHz (all constraints met)
- TNS: 0.000 ns
- Number of failing endpoints: 0

## Notes

- IMEM uses `SYNC_READ=1` with `(* ram_style = "block" *)` and bounded address width.
  Vivado infers BRAM (0.5 tiles = 1 RAMB18E1 for the 11-word hello firmware). With a
  larger firmware, more BRAM tiles will be used automatically.
- DMEM (4KB) remains as distributed RAM (LUT RAM). Combinational reads are required by
  the single-cycle core — BRAM synchronous reads would need a pipeline stage.
  Explicitly marked with `(* ram_style = "distributed" *)`.
- DMEM was reduced from 64KB to 4KB to meet timing. At 64KB, the distributed RAM mux
  tree (8,192 RAMS64E, 18 logic levels, fanout 8,192) caused WNS -4.095 ns. At 4KB
  the mux tree is shallow enough to meet 50 MHz with margin.
- Core logic uses ~1,413 LUTs (2.23%), leaving substantial room for planned
  accelerators (SNN coprocessor, neural net inference engine).

## Revision History

| Date       | Change                                    | LUTs  | BRAM | WNS    |
|------------|-------------------------------------------|-------|------|--------|
| (baseline) | Pre-Wishbone, all distributed RAM (64KB)  | 9,711 | 0    | +0.338 |
| 2026-03-28 | Wishbone SoC, IMEM BRAM, DMEM 4KB         | 1,969 | 0.5  | +0.301 |
