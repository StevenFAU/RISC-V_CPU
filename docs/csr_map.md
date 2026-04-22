# CSR Map — Phase 1.0

Reference for the M-mode CSR set implemented in `rtl/csr_file.v`. The
file is a standalone module in Phase 1.0 — wiring into `rv32i_core.v`
lands in Phase 1.1, and the trap FSM (`trap_enter` / `trap_return`)
lands in Phase 1.2. All CSR addresses below match the RISC-V Privileged
Architecture spec v1.12.

## Address Map

| Address | Name        | Access | Width | Reset       | Notes                                          |
|---------|-------------|--------|-------|-------------|------------------------------------------------|
| 0x300   | `mstatus`   | R/W    | 32    | 0x0000_1800 | MIE bit 3, MPIE bit 7 writable; MPP=11 hardwired |
| 0x301   | `misa`      | RO     | 32    | 0x4000_0100 | MXL=32 (bits 31:30), I-bit (bit 8)             |
| 0x304   | `mie`       | R/W    | 32    | 0x0000_0000 | MEIE bit 11, MTIE bit 7, MSIE bit 3 writable   |
| 0x305   | `mtvec`     | R/W    | 32    | 0x0000_0000 | BASE bits [31:2] writable; MODE [1:0]=00       |
| 0x340   | `mscratch`  | R/W    | 32    | 0x0000_0000 | Full 32-bit, no mask                           |
| 0x341   | `mepc`      | R/W    | 32    | 0x0000_0000 | Bits [31:2] writable; bits [1:0]=00 hardwired  |
| 0x342   | `mcause`    | R/W    | 32    | 0x0000_0000 | Full 32-bit, no mask                           |
| 0x343   | `mtval`     | R/W    | 32    | 0x0000_0000 | Full 32-bit, no mask                           |
| 0x344   | `mip`       | R/W    | 32    | 0x0000_0000 | MSIP bit 3 software-writable; MTIP/MEIP RO=0 (Phase 2) |
| 0xF11   | `mvendorid` | RO     | 32    | 0x0000_0000 | Hardwired 0                                    |
| 0xF12   | `marchid`   | RO     | 32    | 0x0000_0000 | Hardwired 0                                    |
| 0xF13   | `mimpid`    | RO     | 32    | 0x0000_0000 | Hardwired 0                                    |
| 0xF14   | `mhartid`   | RO     | 32    | 0x0000_0000 | Hardwired 0 — single-hart core                 |
| 0xB00   | `mcycle`    | R/W    | 64    | 0           | Low 32 bits of free-running cycle counter      |
| 0xB80   | `mcycleh`   | R/W    | 64    | 0           | High 32 bits of mcycle                         |
| 0xB02   | `minstret`  | R/W    | 64    | 0           | Low 32 bits of retired-instruction counter     |
| 0xB82   | `minstreth` | R/W    | 64    | 0           | High 32 bits of minstret                       |
| 0xC00   | `cycle`     | RO     | 64    | 0           | User-mode alias of `mcycle` low                |
| 0xC80   | `cycleh`    | RO     | 64    | 0           | User-mode alias of `mcycle` high               |
| 0xC02   | `instret`   | RO     | 64    | 0           | User-mode alias of `minstret` low              |
| 0xC82   | `instreth`  | RO     | 64    | 0           | User-mode alias of `minstret` high             |

## Field Layouts

### `mstatus` (0x300)

```
 31                              13 12 11 10  9  8  7      4  3      0
+----------------------------------+-----+--+--+--+--+------+--+------+
|              0                   | MPP |  |  |  | MPIE | 0| MIE  | 0|
+----------------------------------+-----+--+--+--+--+------+--+------+
                                    11 (hw)       7         3
```

- Bit 3 (MIE): writable. Global M-mode interrupt enable.
- Bit 7 (MPIE): writable. Saved MIE on trap entry; restored on MRET.
- Bits 12:11 (MPP): hardwired to `11` (M-mode) — no U/S mode in Phase 1.
- All other bits read 0 and writes are dropped.

### `mie` (0x304) and `mip` (0x344)

```
 31      12 11 10  9  8  7      4  3      0
+----------+--+--+--+--+--+------+--+------+
|    0     |XEIE|  |  |  |XTIE|  | XSIE |  |
+----------+--+--+--+--+--+------+--+------+
            11               7    3
```

- `mie`: bits 11 (MEIE), 7 (MTIE), 3 (MSIE) are writable.
- `mip`: bit 3 (MSIP) is software-writable. Bits 11 (MEIP) and 7
  (MTIP) read as 0 in Phase 1.0 — they will be driven by hardware
  inputs (`irq_external` / `irq_timer`) in Phase 2.

### `mtvec` (0x305)

```
 31                                 2  1  0
+-------------------------------------+----+
|             BASE                    |MODE|
+-------------------------------------+----+
```

MODE is hardwired to `00` (direct trap mode). Vectored mode is out of
scope for Tier 1.

### `mepc` (0x341)

Bits [1:0] are hardwired to `00`. Phase 1.2's trap FSM also masks
them when capturing the trap PC, which is always word-aligned for
RV32I.

## Write-source Priority

For any CSR with multiple potential writers in the same cycle, the
implemented priority is:

```
trap_enter  >  trap_return  >  csr_write_op
```

This affects:

| CSR        | Writers                                  |
|------------|------------------------------------------|
| `mstatus`  | trap_enter, trap_return, csr_write_op    |
| `mepc`     | trap_enter, csr_write_op                 |
| `mcause`   | trap_enter, csr_write_op                 |
| `mtval`    | trap_enter, csr_write_op                 |
| `mtvec`    | csr_write_op only                        |
| `mscratch` | csr_write_op only                        |
| `mie`      | csr_write_op only                        |
| `mip`      | csr_write_op (MSIP only); HW (Phase 2)   |
| `mcycle*`  | csr_write_op > free-running tick         |
| `minstret*`| csr_write_op > `instret_tick`            |

In Phase 1.0 the trap inputs are tied low by the testbench. The
priority order is in place so the Phase 1.2 trap FSM can wire in
without restructuring `csr_file.v`.

A simulation-only assertion in `csr_file.v` (gated by `\`ifndef
SYNTHESIS`) checks that `trap_enter` and `trap_return` are never
asserted in the same cycle — that combination is structurally
impossible for the Phase 1.2 FSM and a counterexample would indicate
a wiring bug.

## CSR-instruction semantics

`csr_write_op[2:0]` follows the encoding the Phase 1.1 decoder will
emit:

| Encoding | Operation | Storage update                        |
|----------|-----------|---------------------------------------|
| `000`    | none      | unchanged                             |
| `001`    | CSRRW     | `value <- write_data`                 |
| `010`    | CSRRS     | `value <- value | write_data`         |
| `011`    | CSRRC     | `value <- value & ~write_data`        |

For CSRRS/CSRRC the `value` used by the RMW is the storage view
regardless of `csr_read_en` — matching the spec, where the RMW
semantics are independent of whether the destination register is `x0`.

`csr_illegal` asserts in any of these cases:
- A read of an unimplemented address (`csr_read_en && !is_valid`).
- A non-zero `csr_write_op` to an unimplemented address.
- A non-zero `csr_write_op` to a read-only CSR (any of `misa`,
  `mvendorid`/`marchid`/`mimpid`/`mhartid`, or the user-mode counter
  aliases).

The signal feeds into the Phase 1.3 illegal-instruction trap path.

## Counter behavior

- `mcycle` increments every clock.
- `minstret` increments only when `instret_tick` is asserted. In
  Phase 1.1 this hooks to the core's retirement signal (1/cycle on
  the single-cycle core).
- A write to either half of a counter replaces that half and skips
  that cycle's increment, matching the `wb_timer` mtime pattern. The
  unwritten half is preserved.

## What's not implemented

| Item                          | Why                                        | Where it lands |
|-------------------------------|--------------------------------------------|----------------|
| `time` / `timeh` (0xC01/0xC81) | Requires a side-band read path from `wb_timer` to `csr_file`. The MMIO read of `mtime_lo/hi` from software is the spec-compliant alternative and is already supported. | Tracked in `docs/tech_debt.md` |
| `mcounteren` (0x306)          | No U-mode in Tier 1.                       | Out of scope   |
| MTIP/MEIP driven from HW      | Phase 2 brings up the IRQ pins.            | Phase 2        |
| Vectored trap mode            | `mtvec.MODE` hardwired to 0 (direct).      | Out of scope   |
| `MPP` other than `11`         | Single-mode (M-only) core in Tier 1.       | Out of scope (Tier 2) |

## See also

- `rtl/csr_file.v` — the implementation.
- `tb/tb_csr_file.v` — directed testbench (8 categories, 63 checks).
- `docs/phase1_context.md` — Phase 1 design decisions and phasing
  rationale.
- `TIER1_ROADMAP.md` Phase 1 — the broader Phase 1 plan.
