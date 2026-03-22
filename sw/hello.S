# hello.S — Prints "Hello, RISC-V!\n" over memory-mapped UART
# UART TX data:   0x80000000
# UART TX status: 0x80000004 (bit 0 = busy)
# String stored in .data section at 0x00010000

.text
.globl _start

_start:
    # Build UART base address: 0x80000000
    lui   a0, 0x80000       # a0 = 0x80000000 (UART base)

    # Build string pointer: 0x00010000 (.data section)
    lui   a1, 0x10          # a1 = 0x00010000 (string base)

print_loop:
    # Load next character
    lbu   a2, 0(a1)         # a2 = *str (unsigned byte load)
    beqz  a2, done          # If null terminator, stop

poll_busy:
    # Poll UART TX status until not busy
    lw    a3, 4(a0)         # a3 = UART_TX_STATUS
    andi  a3, a3, 1         # Isolate busy bit
    bnez  a3, poll_busy     # Loop while busy

    # Send character
    sw    a2, 0(a0)         # Write char to UART TX data

    # Advance to next character
    addi  a1, a1, 1
    j     print_loop

done:
    # Halt — infinite loop
    j     done

.data
.globl hello_str
hello_str:
    .ascii "Hello, RISC-V!\n\0"
