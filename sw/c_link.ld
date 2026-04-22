/* Linker script for RV32I C PROGRAMS built for SYNTHESIZED HARDWARE.
 *
 * Used by: top-level Makefile `make c PROG=...` target. C programs built
 * with this script run on the FPGA and on `make sim-fpga` (when the C
 * testbench is selected).
 *
 * Memory map matches the synthesized hardware (see rtl/fpga_top.v):
 *   IMEM at 0x00000000, 64 KB, read-only (instruction fetch bus only).
 *   DMEM at 0x00010000, 4 KB,  read/write (Wishbone data bus).
 *
 * HARVARD-BUS CONSTRAINT (important): the core has a split bus architecture.
 *   - IMEM sits on a dedicated instruction-fetch path and is reachable ONLY
 *     by the fetch unit. Data-side loads/stores cannot touch IMEM.
 *   - DMEM sits on the Wishbone data bus. Only data-side accesses reach it.
 * Consequence: .rodata (e.g., printf format strings read via `lbu`) MUST
 * live in DMEM, not IMEM. Placing a string literal in IMEM would look right
 * at link time but silently return 0 at runtime because the load never
 * reaches the IMEM BRAM. A unified-memory rework is deferred to Phase 4.
 *
 * Heap: NONE. The syscall stub `_sbrk` returns -1. Any call to `malloc`
 * (or anything that internally calls malloc) will fail. Keep programs
 * stack-only for now.
 *
 * Stack: top of DMEM, grows downward. 4 KB total for stack + .data + .bss.
 *
 * NOT compatible with the compliance testbench (see tests/link.ld).
 * Assembly programs continue to use sw/link.ld / sw/hello_link.ld.
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    DMEM (rwx) : ORIGIN = 0x00010000, LENGTH = 4K
}

SECTIONS
{
    /* Entry code (crt0) goes first, then the rest of .text. */
    .text : {
        KEEP(*(.text.init))
        *(.text)
        *(.text.*)
    } > IMEM

    /* .rodata in DMEM — see Harvard-bus note above. */
    .rodata : {
        *(.rodata)
        *(.rodata.*)
        *(.srodata)
        *(.srodata.*)
    } > DMEM

    .data : {
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
    } > DMEM

    .bss : {
        _bss_start = .;
        *(.sbss)
        *(.sbss.*)
        *(.bss)
        *(.bss.*)
        *(COMMON)
        _bss_end = .;
    } > DMEM

    /* _end marks the end of statically-placed data. newlib's _sbrk stub
     * uses it as a heap base — our stub returns -1 unconditionally, so
     * _end is informational only. */
    _end = .;

    /* Stack grows downward from the top of DMEM. crt0 sets sp here. */
    _stack_top = ORIGIN(DMEM) + LENGTH(DMEM);

    /* Bare-metal builds never unwind — drop exception-frame and note
     * sections that newlib / libgcc pull in by default. */
    /DISCARD/ : {
        *(.eh_frame)
        *(.eh_frame_hdr)
        *(.note)
        *(.note.*)
        *(.comment)
    }
}
