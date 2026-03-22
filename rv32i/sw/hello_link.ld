/* Linker script for hello.S firmware
 * Text at 0x00000000 (IMEM), data at 0x00010000 (DMEM via bus decoder -> RAM)
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
    . = 0x00000000;
    .text : { *(.text) *(.text.*) }

    . = 0x00010000;
    .data : { *(.data) *(.data.*) *(.rodata) *(.rodata.*) }
    .bss  : { *(.bss) *(.bss.*) }
    _end = .;
}
