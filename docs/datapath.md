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
        |              |     |     ┌─────────────────────────────────┐         |
        |              |     |     │         wb_master               │         |
        |              |     |     │  addr  wdata  we  re  funct3   │         |
        |              |     |     │  → cyc/stb/we/adr/dat/sel      │         |
        |              |     |     └──────────────┬──────────────────┘         |
        |              |     |                    │                            |
        |              |     |     ┌──────────────┴──────────────────┐         |
        |              |     |     │       wb_interconnect           │         |
        |              |     |     │      (address decoder)          │         |
        |              |     |     ├───────┬───────┬───────┬────────┤         |
        |              |     |     │       │       │       │        │         |
        |              |     |   DMEM    UART    GPIO    TIMER      |         |
        |              |     |  (64KB)  (TX/RX) (LED/SW) (CLINT)    |         |
        |              |     |               |                                 |
        |              |     |          dmem_read_data (via wb_dat)            |
        |              |     |               |                                 |
        |              |     |               v                                 |
        |              |     |          [WRITEBACK MUX — 5 sources]            |
        |              |     |           is_csr: csr_read_data  (Phase 1.1)    |
        |              |     |           LUI:    imm                           |
        |              |     |           JAL/R:  pc+4                          |
        |              |     |           Load:   dmem_data                     |
        |              |     |           else:   alu_result                    |
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

## Bus Architecture

The core's data memory bus (addr, wdata, rdata, we, re, funct3) connects to the
Wishbone master bridge, which translates to standard Wishbone B4 classic signals
(cyc, stb, we, adr, dat, sel, ack). The interconnect decodes the address and
routes to the appropriate slave:

| Address Range           | Slave        | Module           |
|-------------------------|--------------|------------------|
| 0x00010000 - 0x0001FFFF | DMEM (RAM)   | `wb_dmem.v`      |
| 0x80000000 - 0x8000000F | UART TX/RX   | `wb_uart.v`      |
| 0x80001000 - 0x80001007 | GPIO (LEDs/SW)| `wb_gpio.v`     |
| 0x80002000 - 0x8000200F | Timer (CLINT) | `wb_timer.v`    |

A `funct3` sideband signal is passed through the bus alongside standard Wishbone
signals. This preserves the sign/unsigned distinction (LB vs LBU) that `wb_sel`
alone cannot encode, allowing `wb_dmem` to perform correct sign-extension.

**Note:** The current Wishbone master is zero-wait-state only — all slaves must
return `ack` combinationally in the same cycle. See `wb_master.v` for details.

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
| dmem_read_data | WB bus return    | Loaded data from memory/peripheral   |
| csr_read_data  | csr_file         | CSR readback (Phase 1.1)             |
| rd_data        | Writeback mux    | Data written to destination register |
| pc_next        | PC-next mux      | Next PC value                        |

## SYSTEM-Opcode Decode (Phase 1.1)

The `control.v` decoder recognizes opcode `0x73` (SYSTEM) and emits five
control outputs from the `funct3` field:

| Decoder output    | Meaning                                                      |
|-------------------|--------------------------------------------------------------|
| `is_csr`          | high for funct3 != 0 (CSRRW/CSRRS/CSRRC + immediate variants) |
| `csr_op[2:0]`     | `{1'b0, funct3[1:0]}` — 001 write / 010 set / 011 clear      |
| `csr_use_imm`     | `funct3[2]` — high for the `*I` immediate variants           |
| `illegal_system`  | high for funct3 == 0 (ECALL/EBREAK/MRET/WFI placeholder)     |
| `illegal_opcode`  | pulses on the case-statement default branch                  |

The core consumes these to drive `csr_addr_o = instr[31:20]`,
`csr_read_en_o = is_csr & (rd_addr != 0)`, and the gated `csr_write_op_o`
(CSRRW always writes; CSRRS/CSRRC and their immediate forms suppress the
write when the source operand is zero). `csr_write_data_o` selects between
`rs1_data` and the zero-extended 5-bit immediate (`{27'b0, rs1_addr}`)
based on `csr_use_imm`.

`illegal_inst_o` from the core is the OR of `csr_illegal_i`,
`illegal_system`, and `illegal_opcode`. It is unconnected at `fpga_top`
in Phase 1.1 — Phase 1.2's trap FSM consumes it.

`mtvec_i` / `mepc_i` / `mstatus_mie_i` enter the core from `csr_file` and
are unused in Phase 1.1; Phase 1.2's PC-redirect mux consumes them.

`instret_tick_o = !rst` drives the `csr_file.minstret` counter — the
single-cycle core retires every non-reset cycle.

See `docs/csr_map.md` for the CSR storage details, and
`tb/tb_rv32i_core_csr.v` for the directed integration coverage.
