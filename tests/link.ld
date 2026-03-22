/* Linker script for RV32I compliance tests */
OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
    /* Text starts at address 0 (our IMEM base) */
    . = 0x00000000;
    .text.init : { *(.text.init) }
    . = ALIGN(0x1000);
    .text : { *(.text) }

    /* tohost section — place at known address for testbench monitoring */
    . = 0x00001000;
    .tohost : { *(.tohost) }

    /* Data section */
    . = 0x00002000;
    .data : { *(.data) }
    .bss  : { *(.bss) }
    _end = .;
}
