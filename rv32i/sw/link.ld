/* Linker script for RV32I test programs */
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
