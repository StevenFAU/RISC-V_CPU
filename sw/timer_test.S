# timer_test.S — Polls mtime, blinks LED via GPIO at ~1 Hz
# Timer base: 0x80002000
#   +0x0: mtime_lo    (R/W)
#   +0x4: mtime_hi    (R/W)
# GPIO base: 0x80001000
#   +0x0: output (LEDs)
#
# At 50 MHz, 25_000_000 ticks = 0.5 seconds per toggle = 1 Hz blink.

.text
.globl _start

_start:
    lui  x1, 0x80002       # x1 = 0x80002000 (Timer base)
    lui  x2, 0x80001       # x2 = 0x80001000 (GPIO base)
    li   x3, 0             # x3 = LED state (toggle)
    lui  x4, 0x17D8        # x4 = 25_000_000 (0x17D7840)
    addi x4, x4, -1984     # x4 = 0x017D7840 = 25,000,000

    # Clear mtime
    sw   x0, 0(x1)         # mtime_lo = 0
    sw   x0, 4(x1)         # mtime_hi = 0

loop:
    lw   x5, 0(x1)         # Read mtime_lo
    bltu x5, x4, loop      # Wait until mtime_lo >= 25M

    # Toggle LED[0]
    xori x3, x3, 1
    sw   x3, 0(x2)         # Write to GPIO output

    # Reset mtime
    sw   x0, 0(x1)         # mtime_lo = 0
    sw   x0, 4(x1)         # mtime_hi = 0

    j    loop
