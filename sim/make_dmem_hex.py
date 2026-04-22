#!/usr/bin/env python3
"""Convert objcopy -O verilog byte hex to word-addressed hex for DMEM $readmemh.

The input is produced from a RISC-V ELF that was extracted with
    objcopy -O verilog --only-section=.rodata --only-section=.data \\
            --change-section-address .rodata-0x00010000 \\
            --change-section-address .data-0x00010000

so the byte addresses land in [0, DMEM_SIZE). We slot those bytes into a
word array in little-endian order (matching rtl/dmem.v's $readmemh layout)
and emit one 32-bit word per line, padded with zeros up to the highest
written word.

Usage: make_dmem_hex.py <input_byte_hex> <output_word_hex>

Exits 0 always, including when the input has no .rodata/.data (produces a
single-word zero file so $readmemh doesn't choke on an empty file).
"""
import sys

def main():
    if len(sys.argv) != 3:
        print("usage: make_dmem_hex.py <input_byte_hex> <output_word_hex>",
              file=sys.stderr)
        sys.exit(2)

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

    if mem:
        max_byte = max(mem)
        num_words = (max_byte // 4) + 1
    else:
        # Empty input — write a single zero word so $readmemh has something
        # to consume (a zero-length file emits a Verilog warning).
        num_words = 1

    with open(sys.argv[2], 'w') as f:
        for i in range(num_words):
            base = i * 4
            b0 = mem.get(base,     0)
            b1 = mem.get(base + 1, 0)
            b2 = mem.get(base + 2, 0)
            b3 = mem.get(base + 3, 0)
            word = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
            f.write(f"{word:08X}\n")

    print(f"Wrote {num_words} DMEM words to {sys.argv[2]}")


if __name__ == '__main__':
    main()
