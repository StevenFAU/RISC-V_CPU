# RV32UI Compliance Test Results

All 37 rv32ui (user-mode integer) tests from riscv-software-src/riscv-tests pass.

| Test   | Status | Cycles | Notes |
|--------|--------|--------|-------|
| add    | PASS   | 459    |       |
| addi   | PASS   | 236    |       |
| and    | PASS   | 479    |       |
| andi   | PASS   | 192    |       |
| auipc  | PASS   | 53     |       |
| beq    | PASS   | 285    |       |
| bge    | PASS   | 303    |       |
| bgeu   | PASS   | 328    |       |
| blt    | PASS   | 285    |       |
| bltu   | PASS   | 310    |       |
| bne    | PASS   | 285    |       |
| jal    | PASS   | 49     |       |
| jalr   | PASS   | 109    |       |
| lb     | PASS   | 247    |       |
| lbu    | PASS   | 247    |       |
| lh     | PASS   | 263    |       |
| lhu    | PASS   | 272    |       |
| lw     | PASS   | 277    |       |
| lui    | PASS   | 59     |       |
| or     | PASS   | 482    |       |
| ori    | PASS   | 199    |       |
| sb     | PASS   | 448    |       |
| sh     | PASS   | 501    |       |
| sw     | PASS   | 508    |       |
| sll    | PASS   | 487    |       |
| slli   | PASS   | 235    |       |
| slt    | PASS   | 453    |       |
| slti   | PASS   | 231    |       |
| sltiu  | PASS   | 231    |       |
| sltu   | PASS   | 453    |       |
| sra    | PASS   | 506    |       |
| srai   | PASS   | 250    |       |
| srl    | PASS   | 500    |       |
| srli   | PASS   | 244    |       |
| sub    | PASS   | 451    |       |
| xor    | PASS   | 481    |       |
| xori   | PASS   | 201    |       |

**Total: 37 | Pass: 37 | Fail: 0 | Timeout: 0**

*Last refreshed after Phase 0.1 bug fixes. Every test is +1 cycle vs the
pre-Phase-0 baseline (commit 0ea6dc1). The shift comes from commit 111e557
(`wb_timer` reset-value change): `mtime` and `mtimecmp` both now reset to
all-1s, which costs one uniform boot-cycle before the wrap. Compliance
tests don't touch the timer, so the 1-cycle delta is purely from the
reset-synchronizer timeline and is not load-bearing for correctness.*

## Test Infrastructure
- Custom test environment (`tests/env/custom/riscv_test.h`) — no CSR support needed
- Unified byte-addressed memory in testbench via core's external bus ports
- Linker script places text at 0x0, tohost at 0x1000, data at 0x2000
- Testbench monitors tohost for pass (1) or fail (test_num << 1 | 1)

## Excluded Tests
- `fence_i` — requires instruction cache (not applicable to single-cycle)
- `ld_st` — RV64 only
