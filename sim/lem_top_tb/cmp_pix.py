#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The 68000's pixel-layer writes, RTL against MAME, in order (frames reported, not compared).

    python sim/lem_top_tb/cmp_pix.py debug/lemmings-pixtrace/lemmings_pix.trace debug/lemmings-top/pix/rtl_pix.trace
"""
import sys


def load(path):
    out = []
    for line in open(path):
        f = line.split()
        if line.startswith("#") or len(f) != 4:      # a run still writing ends mid-line
            continue
        out.append((int(f[0]), f[1].upper(), f[2].upper(), f[3].upper()))
    return out


mame, rtl = load(sys.argv[1]), load(sys.argv[2])[:-1]   # the last line may still be being written
n = min(len(mame), len(rtl))
if n == 0:
    sys.exit(f"nothing to compare (MAME {len(mame)}, RTL {len(rtl)})")
for i in range(n):
    if mame[i][1:] != rtl[i][1:]:
        print(f"first difference at write {i}: MAME {mame[i]} RTL {rtl[i]}")
        for j in range(max(0, i - 4), min(n, i + 6)):
            print(f"  {j}: MAME {mame[j]}  RTL {rtl[j]}")
        sys.exit(1)
print(f"{n} writes identical (MAME {len(mame)}, RTL {len(rtl)}); "
      f"last compared: MAME frame {mame[n - 1][0]}, RTL frame {rtl[n - 1][0]}")
