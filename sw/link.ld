/* Linker script for RV32I test programs built for SYNTHESIZED HARDWARE.
 *
 * Targets the hardware memory map:
 *   IMEM at 0x00000000 (64 KB BRAM, read-only — sized at 4 KB here)
 *   DMEM at 0x00010000 (4 KB, R/W)
 *
 * Used by: top-level Makefile `make asm PROG=...` target. Programs built
 * with this script run on the FPGA and on `make sim-fpga`.
 *
 * NOT compatible with `tb/tb_compliance.v` — that testbench uses a
 * unified 16 KB memory and a different linker script at `tests/link.ld`.
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    DMEM (rwx) : ORIGIN = 0x00010000, LENGTH = 4K
}

SECTIONS
{
    .text : {
        *(.text)
        *(.text.*)
    } > IMEM

    .data : {
        *(.data)
        *(.data.*)
        *(.rodata)
        *(.rodata.*)
    } > DMEM

    .bss : {
        *(.bss)
        *(.bss.*)
    } > DMEM
}
