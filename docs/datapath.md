# RV32I Single-Cycle Datapath

```
                    +-------+
        +---------->| IMEM  |----instr[31:0]---+-----------+----------+--------+
        |           +-------+                  |           |          |        |
        |                                      v           v          v        |
   +----+----+                            +---------+  +--------+ +-------+   |
   |   PC    |<---pc_next---[MUX]         | IMMGEN  |  | CONTROL| |ALU_DEC|   |
   +---------+               |            +---------+  +--------+ +-------+   |
        |                    |                 |            |          |        |
        +--pc_current--+     |                 |            |          |        |
        |              |     |                 v            v          v        |
        v              |     |            +----------+  ctrl sigs  alu_ctrl    |
   [PC + 4]            |     |            |          |                         |
        |              |     |            |  [MUX B] |---alu_b                 |
        |              |     |            | imm/rs2  |                         |
        |              |     |            +----------+                         |
        |              |     |                                                 |
        v              v     |           rs1_addr  rs2_addr  rd_addr           |
   pc_plus4       pc_current |              |         |        |               |
        |              |     |              v         v        v               |
        |              |     |          +----------------------------+         |
        |              |     |          |        REGISTER FILE       |         |
        |              |     |          |  rs1_data    rs2_data      |         |
        |              |     |          +----------------------------+         |
        |              |     |               |            |                    |
        |              |     |               v            |                    |
        |              |     |          +----------+      |                    |
        |         [MUX A]    |          |   ALU    |      |                    |
        |         AUIPC:pc   |          | a     b  |      |                    |
        |         else:rs1   |          +----------+      |                    |
        |              |     |               |            |                    |
        |              |     |          alu_result        |                    |
        |              |     |               |            |                    |
        |              |     |               v            v                    |
        |              |     |          +----------------------------+         |
        |              |     |          |       DATA MEMORY          |         |
        |              |     |          |  addr    write_data        |         |
        |              |     |          +----------------------------+         |
        |              |     |               |                                 |
        |              |     |          dmem_read_data                         |
        |              |     |               |                                 |
        |              |     |               v                                 |
        |              |     |          [WRITEBACK MUX]                        |
        |              |     |           LUI:   imm                            |
        |              |     |           JAL/R: pc+4                           |
        |              |     |           Load:  dmem_data                      |
        |              |     |           else:  alu_result                     |
        |              |     |               |                                 |
        |              |     |               +----> rd_data (to regfile)       |
        |              |     |                                                 |
        |              +-----+----[PC-NEXT MUX]                                |
        |                    |     jump:    jump_target                         |
        +--------------------+     branch:  branch_target                      |
                                   else:    pc+4                               |

Branch target  = pc + imm
Jump target    = JAL:  pc + imm
                 JALR: (rs1 + imm) & ~1
```

## Signal Summary

| Signal         | Source           | Description                          |
|----------------|-----------------|--------------------------------------|
| pc_current     | PC register      | Current program counter              |
| pc_plus4       | pc + 4           | Next sequential address              |
| instr          | IMEM             | Current instruction                  |
| imm            | ImmGen           | Sign-extended immediate              |
| rs1_data       | RegFile port 1   | Source register 1 value              |
| rs2_data       | RegFile port 2   | Source register 2 value              |
| alu_result     | ALU output       | Computation result / memory address  |
| dmem_read_data | DMEM read port   | Loaded data from memory              |
| rd_data        | Writeback mux    | Data written to destination register |
| pc_next        | PC-next mux      | Next PC value                        |
