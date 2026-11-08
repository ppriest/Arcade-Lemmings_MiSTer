#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The 6809's chip writes and latch reads, RTL against MAME, in order; frames are reported, not
compared (the RTL's 264-line frame drifts from MAME's).

    python sim/lem_top_tb/cmp_snd.py debug/lemmings-snd/lemmings_snd.trace debug/lemmings-top/rtl_snd.trace
"""
import sys


def load(path):
    out = []
    for line in open(path):
        f = line.split()
        if line.startswith("#") or len(f) != 4:      # a run still writing ends mid-line
            continue
        fr, rw, a, d = f
        out.append((int(fr), rw, a.upper(), d.upper()))
    return out


mame, rtl = load(sys.argv[1]), load(sys.argv[2])
n = min(len(mame), len(rtl))
for i in range(n):
    if mame[i][1:] != rtl[i][1:]:
        print(f"first difference at access {i}: MAME {mame[i]} RTL {rtl[i]}")
        for j in range(max(0, i - 3), min(n, i + 4)):
            print(f"  {j}: MAME {mame[j]}  RTL {rtl[j]}")
        sys.exit(1)
print(f"{n} accesses identical (MAME {len(mame)}, RTL {len(rtl)}); "
      f"last compared: MAME frame {mame[n - 1][0]}, RTL frame {rtl[n - 1][0]}")
sys.exit(0)
