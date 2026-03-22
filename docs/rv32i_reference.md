# RV32I Instruction Set Reference

## Instruction Formats

```
R-type:  [  funct7  |  rs2  |  rs1  | funct3 |   rd   | opcode ]
          31     25  24  20  19  15   14   12  11    7   6     0

I-type:  [       imm[11:0]  |  rs1  | funct3 |   rd   | opcode ]
          31             20  19  15   14   12  11    7   6     0

S-type:  [ imm[11:5] |  rs2  |  rs1  | funct3 | imm[4:0]| opcode ]
          31      25  24  20  19  15   14   12  11     7   6     0

B-type:  [imm[12|10:5]| rs2  |  rs1  | funct3 |imm[4:1|11]| opcode ]
          31       25  24  20  19  15   14   12  11      7   6     0

U-type:  [           imm[31:12]                |   rd   | opcode ]
          31                              12    11    7   6     0

J-type:  [  imm[20|10:1|11|19:12]              |   rd   | opcode ]
          31                              12    11    7   6     0
```

## Complete RV32I Instruction List

### R-Type Arithmetic (opcode 0110011)
| Instruction | funct7  | funct3 | Operation              |
|-------------|---------|--------|------------------------|
| ADD         | 0000000 | 000    | rd = rs1 + rs2         |
| SUB         | 0100000 | 000    | rd = rs1 - rs2         |
| SLL         | 0000000 | 001    | rd = rs1 << rs2[4:0]   |
| SLT         | 0000000 | 010    | rd = (rs1 < rs2) ? 1:0 (signed)  |
| SLTU        | 0000000 | 011    | rd = (rs1 < rs2) ? 1:0 (unsigned)|
| XOR         | 0000000 | 100    | rd = rs1 ^ rs2         |
| SRL         | 0000000 | 101    | rd = rs1 >> rs2[4:0]   |
| SRA         | 0100000 | 101    | rd = rs1 >>> rs2[4:0]  |
| OR          | 0000000 | 110    | rd = rs1 | rs2         |
| AND         | 0000000 | 111    | rd = rs1 & rs2         |

### I-Type Arithmetic (opcode 0010011)
| Instruction | imm[11:0]     | funct3 | Operation              |
|-------------|---------------|--------|------------------------|
| ADDI        | imm           | 000    | rd = rs1 + sext(imm)   |
| SLTI        | imm           | 010    | rd = (rs1 < sext(imm)) ? 1:0 (signed)  |
| SLTIU       | imm           | 011    | rd = (rs1 < sext(imm)) ? 1:0 (unsigned)|
| XORI        | imm           | 100    | rd = rs1 ^ sext(imm)   |
| ORI         | imm           | 110    | rd = rs1 | sext(imm)   |
| ANDI        | imm           | 111    | rd = rs1 & sext(imm)   |
| SLLI        | 0000000|shamt | 001    | rd = rs1 << shamt      |
| SRLI        | 0000000|shamt | 101    | rd = rs1 >> shamt      |
| SRAI        | 0100000|shamt | 101    | rd = rs1 >>> shamt     |

### Load (opcode 0000011)
| Instruction | funct3 | Operation                          |
|-------------|--------|------------------------------------|
| LB          | 000    | rd = sext(mem[rs1+imm][7:0])       |
| LH          | 001    | rd = sext(mem[rs1+imm][15:0])      |
| LW          | 010    | rd = mem[rs1+imm][31:0]            |
| LBU         | 100    | rd = zext(mem[rs1+imm][7:0])       |
| LHU         | 101    | rd = zext(mem[rs1+imm][15:0])      |

### Store (opcode 0100011)
| Instruction | funct3 | Operation                          |
|-------------|--------|------------------------------------|
| SB          | 000    | mem[rs1+imm][7:0] = rs2[7:0]      |
| SH          | 001    | mem[rs1+imm][15:0] = rs2[15:0]    |
| SW          | 010    | mem[rs1+imm][31:0] = rs2[31:0]    |

### Branch (opcode 1100011)
| Instruction | funct3 | Condition                |
|-------------|--------|--------------------------|
| BEQ         | 000    | if (rs1 == rs2) PC += imm|
| BNE         | 001    | if (rs1 != rs2) PC += imm|
| BLT         | 100    | if (rs1 < rs2)  PC += imm (signed)  |
| BGE         | 101    | if (rs1 >= rs2) PC += imm (signed)  |
| BLTU        | 110    | if (rs1 < rs2)  PC += imm (unsigned)|
| BGEU        | 111    | if (rs1 >= rs2) PC += imm (unsigned)|

### Jump (opcodes 1101111, 1100111)
| Instruction | Opcode  | Operation                        |
|-------------|---------|----------------------------------|
| JAL         | 1101111 | rd = PC+4; PC += sext(imm)       |
| JALR        | 1100111 | rd = PC+4; PC = (rs1+sext(imm)) & ~1 |

### Upper Immediate (opcodes 0110111, 0010111)
| Instruction | Opcode  | Operation                        |
|-------------|---------|----------------------------------|
| LUI         | 0110111 | rd = imm << 12                   |
| AUIPC       | 0010111 | rd = PC + (imm << 12)            |

## Notes
- x0 is hardwired to 0 (writes are ignored)
- All immediates are sign-extended to 32 bits
- Branch offsets are relative to the branch instruction's PC
- JALR clears the least-significant bit of the computed target address
- NOP is encoded as ADDI x0, x0, 0
