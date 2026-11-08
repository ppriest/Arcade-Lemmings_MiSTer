#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Inputs for sim/lem_boot_tb from the ROM set and MAME's boot trace.

    python sim/lem_boot_tb/gen_inputs.py <lemmings.zip>

debug/lemmings-boot/lemmings_rom.hex: the 1 MB main ROM as words (lemmings.cpp:502-510).
debug/lemmings-boot/lemmings_irq.txt: for each level 6 entry in the trace (a read of vector 0x78),
the access just before the three writes of its exception frame.
"""
import sys
import zipfile
from pathlib import Path

D = Path("debug/lemmings-boot")
z = zipfile.ZipFile(sys.argv[1])
with open(D / "lemmings_rom.hex", "w") as f:
    for h, l in ((5, 1), (6, 2), (7, 3), (8, 4)):
        hi, lo = z.read(f"lemmings.{h}"), z.read(f"lemmings.{l}")
        f.write("".join(f"{a:02x}{b:02x}\n" for a, b in zip(hi, lo)))

rows = []
for ln in open(D / "lemmings_boot.trace"):
    if ln[0] != "#" and ln.strip():
        p = ln.split("\t")
        rows.append((int(p[0]), p[1], p[2]))
out = []
for i, (s, rw, a) in enumerate(rows):
    if rw == "r" and a == "000078":
        assert [r[1] for r in rows[i - 3:i]] == ["w", "w", "w"], rows[i - 4:i + 1]
        out.append(rows[i - 4][0])
(D / "lemmings_irq.txt").write_text("".join(f"{s}\n" for s in out))
print(len(out), "interrupts, first after access", out[0])
