#!/usr/bin/env python3
# Original: https://github.com/mcejp/fixed-point-math/blob/main/sin_table.py

import math

FRAC_BITS = 6
ENTRIES_PER_LINE = 10

for table_bits in [6]:
    table_size = 2**table_bits + 1

    print(f"static const int8_t sin_table[{table_size}] = {{")

    for i in range(table_size):
        if i % ENTRIES_PER_LINE == 0:
            print("    ", end="")
        else:
            print(" ", end="")

        sin = math.sin(i / (table_size - 1) * math.pi * 0.5)
        print(f"0x{int(round(sin * 2**FRAC_BITS)):02x},", end="")

        if (i + 1) % ENTRIES_PER_LINE == 0 or i + 1 == table_size:
            print("\n", end="")

    print("};")
    print()
