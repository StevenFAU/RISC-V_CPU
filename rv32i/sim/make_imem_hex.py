#!/usr/bin/env python3
"""Convert objcopy -O verilog byte hex to word-addressed hex for IMEM $readmemh"""
import sys

mem = {}
addr = 0

with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('//'):
            continue
        if line.startswith('@'):
            addr = int(line[1:], 16)
            continue
        for byte_str in line.split():
            mem[addr] = int(byte_str, 16)
            addr += 1

# Find max text address (before data section at 0x10000)
max_text_addr = max(a for a in mem if a < 0x10000)
num_words = (max_text_addr // 4) + 1

with open(sys.argv[2], 'w') as f:
    for i in range(num_words):
        base = i * 4
        b0 = mem.get(base, 0)
        b1 = mem.get(base+1, 0)
        b2 = mem.get(base+2, 0)
        b3 = mem.get(base+3, 0)
        word = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
        f.write(f"{word:08X}\n")
    print(f"Wrote {num_words} words to {sys.argv[2]}")

