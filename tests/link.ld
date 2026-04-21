/* Linker script for RV32I COMPLIANCE TESTS.
 *
 * Targets the unified 16 KB memory in `tb/tb_compliance.v`:
 *   .text.init at 0x00000000 (riscv-tests put the entry code here)
 *   .text      nominally at 0x00001000 after ALIGN(0x1000)
 *   .tohost    at 0x00001000 (monitored by testbench for pass/fail)
 *   .data      at 0x00002000
 *   .bss       follows .data
 *
 * Note on .text vs .tohost: riscv-tests' rv32ui sources place entry code in
 * `.text.init` and leave `.text` empty — so in practice the location
 * counter hits 0x1000 via ALIGN, the empty `.text` consumes no space, and
 * `. = 0x00001000` lands `.tohost` at exactly 0x1000 with no collision.
 * If a future test adds real `.text` content, it WOULD silently collide
 * with `.tohost`. Verified empty via objdump on current test binaries.
 *
 * Used by: tests/Makefile (via `-T link.ld`). All rv32ui compliance tests
 * are linked with this script.
 *
 * NOT compatible with the synthesized hardware memory map — use
 * `sw/link.ld` for programs intended to run on the FPGA.
 */
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
