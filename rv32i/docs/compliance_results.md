# RV32UI Compliance Test Results

All 37 rv32ui (user-mode integer) tests from riscv-software-src/riscv-tests pass.

| Test   | Status | Cycles | Notes |
|--------|--------|--------|-------|
| add    | PASS   | 458    |       |
| addi   | PASS   | 235    |       |
| and    | PASS   | 478    |       |
| andi   | PASS   | 191    |       |
| auipc  | PASS   | 52     |       |
| beq    | PASS   | 284    |       |
| bge    | PASS   | 302    |       |
| bgeu   | PASS   | 327    |       |
| blt    | PASS   | 284    |       |
| bltu   | PASS   | 309    |       |
| bne    | PASS   | 284    |       |
| jal    | PASS   | 48     |       |
| jalr   | PASS   | 108    |       |
| lb     | PASS   | 246    |       |
| lbu    | PASS   | 246    |       |
| lh     | PASS   | 262    |       |
| lhu    | PASS   | 271    |       |
| lw     | PASS   | 276    |       |
| lui    | PASS   | 58     |       |
| or     | PASS   | 481    |       |
| ori    | PASS   | 198    |       |
| sb     | PASS   | 447    |       |
| sh     | PASS   | 500    |       |
| sw     | PASS   | 507    |       |
| sll    | PASS   | 486    |       |
| slli   | PASS   | 234    |       |
| slt    | PASS   | 452    |       |
| slti   | PASS   | 230    |       |
| sltiu  | PASS   | 230    |       |
| sltu   | PASS   | 452    |       |
| sra    | PASS   | 505    |       |
| srai   | PASS   | 249    |       |
| srl    | PASS   | 499    |       |
| srli   | PASS   | 243    |       |
| sub    | PASS   | 450    |       |
| xor    | PASS   | 480    |       |
| xori   | PASS   | 200    |       |

**Total: 37 | Pass: 37 | Fail: 0 | Timeout: 0**

## Test Infrastructure
- Custom test environment (`tests/env/custom/riscv_test.h`) — no CSR support needed
- Unified byte-addressed memory in testbench via core's external bus ports
- Linker script places text at 0x0, tohost at 0x1000, data at 0x2000
- Testbench monitors tohost for pass (1) or fail (test_num << 1 | 1)

## Excluded Tests
- `fence_i` — requires instruction cache (not applicable to single-cycle)
- `ld_st` — RV64 only
