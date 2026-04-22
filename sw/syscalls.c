/*
 * syscalls.c — newlib bare-metal syscall stubs.
 *
 * newlib's libc functions (printf, puts, etc.) assume an OS underneath.
 * On bare metal we supply that "OS" ourselves as a handful of stubs.
 *
 * What's implemented:
 *   _write  → polls UART TX-busy, sends each byte. Makes printf work.
 *   _fstat  → reports S_IFCHR for stdin/stdout/stderr so newlib-nano
 *             switches to unbuffered / line-buffered-ish behavior and
 *             printf doesn't silently buffer the output forever.
 *   _isatty → returns 1 for stdin/stdout/stderr, 0 otherwise. Also
 *             influences newlib's stream-buffering decision.
 *
 * What's deliberately stubbed:
 *   _read   → EOF always. UART-RX syscalls land in Phase 2.
 *   _sbrk   → -1 always. No heap. Programs that call malloc will fail
 *             at runtime (they'll get NULL back and most will crash).
 *             Phase 4/5 revisits memory layout; a real heap may land then.
 *   _close, _lseek, _exit, _getpid, _kill → minimal "do nothing sensible".
 *
 * UART MMIO (from rtl/wb_uart.v, matches sw/hello.S):
 *   0x80000000  TX data   — write low byte to transmit
 *   0x80000004  TX status — bit 0: TX busy (1 = busy, can't send yet)
 *
 * Address of the UART is baked in as a constant here rather than pulled
 * from a shared header because sw/ currently has no C header conventions.
 * If that changes, move these to sw/platform.h.
 */

#include <errno.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#undef errno
extern int errno;

#define UART_TX_DATA   ((volatile uint32_t *)0x80000000u)
#define UART_TX_STATUS ((volatile uint32_t *)0x80000004u)
#define UART_TX_BUSY   0x1u

static void uart_putc(char c) {
    while ((*UART_TX_STATUS) & UART_TX_BUSY) { /* spin */ }
    *UART_TX_DATA = (uint32_t)(uint8_t)c;
}

int _write(int fd, const char *buf, int len) {
    (void)fd;
    for (int i = 0; i < len; i++) {
        uart_putc(buf[i]);
    }
    return len;
}

int _read(int fd, char *buf, int len) {
    (void)fd;
    (void)buf;
    (void)len;
    return 0;  /* EOF — UART RX wiring is a Phase 2 task */
}

int _close(int fd) {
    (void)fd;
    return -1;
}

off_t _lseek(int fd, off_t offset, int whence) {
    (void)fd;
    (void)offset;
    (void)whence;
    return 0;
}

int _fstat(int fd, struct stat *st) {
    (void)fd;
    /* Marking the fd as a character device tells newlib-nano's stdio layer
     * to treat the stream as line-buffered (or unbuffered). Without this,
     * printf's buffer never flushes and the UART stays silent. */
    st->st_mode = S_IFCHR;
    return 0;
}

int _isatty(int fd) {
    if (fd == STDIN_FILENO || fd == STDOUT_FILENO || fd == STDERR_FILENO) {
        return 1;
    }
    errno = ENOTTY;
    return 0;
}

void *_sbrk(ptrdiff_t incr) {
    (void)incr;
    errno = ENOMEM;
    return (void *)-1;  /* No heap available */
}

void _exit(int status) {
    (void)status;
    for (;;) { /* spin — bare metal has nowhere to exit to */ }
}

int _getpid(void) {
    return 1;
}

int _kill(int pid, int sig) {
    (void)pid;
    (void)sig;
    errno = EINVAL;
    return -1;
}
