/* Linker script for env/rv32mi_p — Phase 1.2.5.
 *
 * Forked from rv32i/tests/env/p/link.ld. Only the section base addresses
 * and ordering are adjusted; the section names and contents match upstream
 * env/p/.
 *
 * Targets the unified 16 KB byte-addressed memory in `tb/tb_compliance.v`:
 *   0x00000000  .text.init  (entry code + trap_vector + reset_vector +
 *                            per-test code and handler)
 *   0x00001000  .tohost     (must match tb_compliance.TOHOST_ADDR)
 *   0x00002000  .text       (typically empty for these tests; env puts
 *                            everything in .text.init)
 *   0x00003000  .data       (test data + signature region)
 *   .bss        immediately follows .data
 *
 * ASSERTs flag the two collision modes that matter:
 *   1. .text.init overflows past 0x00001000 — would overlap .tohost.
 *   2. _end overflows past 0x00004000 — would exceed the 16 KB window.
 *
 * The .tohost address (0x00001000) is the contract with tb_compliance.v
 * for pass/fail signaling. Changing it requires updating TOHOST_ADDR in
 * tb_compliance.v.
 *
 * Differences from rv32i/tests/env/p/link.ld:
 *   - Base 0x80000000 -> 0x00000000 (our IMEM/DMEM unified-mem origin)
 *   - .tohost pinned at 0x1000 (upstream uses ALIGN(0x1000) after
 *     .text.init -- equivalent if .text.init < 0x1000; this form makes
 *     the contract with tb_compliance explicit)
 *   - .data pinned at 0x3000 (upstream uses ALIGN(0x1000) chain)
 *   - ASSERTs added to catch image overflow at link time
 */
OUTPUT_ARCH( "riscv" )
ENTRY(_start)

SECTIONS
{
  . = 0x00000000;
  .text.init : { *(.text.init) }
  ASSERT(. <= 0x00001000,
         "rv32mi .text.init overflowed 0x1000 (collides with .tohost)")

  . = 0x00001000;
  .tohost : { *(.tohost) }

  . = 0x00002000;
  .text : { *(.text) }

  . = 0x00003000;
  .data : { *(.data) }
  .bss  : { *(.bss) }
  _end = .;
  ASSERT(_end <= 0x00004000,
         "rv32mi image overflowed 0x4000 (16 KB tb_compliance window)")
}
