#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""RTL frames from sim/lem_top_tb against one MAME capture's reference.png; writes each as a PNG.

    python sim/lem_top_tb/compare.py debug/lemmings-1000 debug/lemmings-top/rtl_frame_999.txt [...]
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ref = np.array(Image.open(Path(sys.argv[1]) / "reference.png").convert("RGB"))
best = None
for arg in sys.argv[2:]:
    p = Path(arg)
    v = [int(x, 16) for x in p.read_text().split()]
    if len(v) != 320 * 224:
        print(f"{p.name}: {len(v)} pixels, expected {320 * 224}")
        continue
    a = np.array(v, dtype=np.uint32).reshape(224, 320)
    got = np.stack([(a >> 16) & 255, (a >> 8) & 255, a & 255], axis=2).astype(np.uint8)
    Image.fromarray(got).save(p.with_suffix(".png"))
    diff = (got != ref).any(axis=2)
    n = int(diff.sum())
    print(f"{p.name}: non-black {int(got.any(axis=2).sum())} (MAME {int(ref.any(axis=2).sum())}), mismatched {n}")
    if n:
        ys, xs = np.nonzero(diff)
        print(f"  lines {ys.min()}-{ys.max()}, columns {xs.min()}-{xs.max()}")
    best = n if best is None else min(best, n)
sys.exit(0 if best == 0 else 1)
