/*
 * hello_c.c — Phase 0.2 demo program.
 *
 * Proves the C toolchain path: newlib-nano's printf runs on the core,
 * format string lives in .rodata (DMEM), output reaches the UART via the
 * _write syscall stub in sw/syscalls.c.
 */

#include <stdio.h>

int main(void) {
    printf("Hello from C!\n");
    return 0;
}
