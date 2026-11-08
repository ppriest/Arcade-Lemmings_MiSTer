#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The bench's frame against MAME's reference.png, and with +FLIP=1 against it rotated 180 degrees.

    python sim/lem_video_tb/compare.py <capture dir> [...]
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

bad = 0
for arg in sys.argv[1:]:
    d = Path(arg)
    ref = np.array(Image.open(next(d.rglob("reference.png"))).convert("RGB"))
    for name, want in (("rtl_frame.txt", ref), ("rtl_flip.txt", ref[::-1, ::-1])):
        p = d / name
        if not p.exists():
            continue
        v = [int(x, 16) for x in p.read_text().split()]
        if len(v) != 320 * 224:
            print(f"{d.name}/{name}: {len(v)} pixels, expected {320 * 224}")
            bad += 1
            continue
        a = np.array(v, dtype=np.uint32).reshape(224, 320)
        got = np.stack([(a >> 16) & 255, (a >> 8) & 255, a & 255], axis=2).astype(np.uint8)
        Image.fromarray(got).save(d / name.replace(".txt", ".png"))
        diff = (got != want).any(axis=2)
        nb = int((want != 0).any(axis=2).sum())
        print(f"{d.name}/{name}: non-black {nb}, mismatched {int(diff.sum())}")
        if diff.any():
            ys, xs = np.nonzero(diff)
            bad += 1
            print(f"  first y={ys[0]} x={xs[0]} RTL {got[ys[0], xs[0]]} MAME {want[ys[0], xs[0]]}, "
                  f"lines {ys.min()}-{ys.max()}, columns {xs.min()}-{xs.max()}")
sys.exit(1 if bad else 0)
