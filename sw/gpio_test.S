# gpio_test.S — Reads switches, writes to LEDs
# GPIO base: 0x80001000
#   +0x0: output (LEDs)
#   +0x4: input  (switches)
# Continuously mirrors switch state to LEDs.

.text
.globl _start

_start:
    lui  x1, 0x80001       # x1 = 0x80001000 (GPIO base)

loop:
    lw   x2, 4(x1)         # Read switches
    sw   x2, 0(x1)         # Write to LEDs
    j    loop               # Repeat forever
