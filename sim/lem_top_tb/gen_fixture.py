#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fixtures for sim/lem_top_tb from the .mra's image (scripts/build_mra.py --image).

    python sim/lem_top_tb/gen_fixture.py        # from the repository root
    -> debug/lemmings-top/image.hex    the download image, a byte a line
       debug/lemmings-top/segs.txt     "start length" of each ROM region the bench downloads
       debug/lemmings-top/expect.hex   the SDRAM after the download, 16-bit words, with the sprite
                                       reorder (rtl/memory/lem_dl_xform.sv) applied here
                                       independently: the image holds each region as four 64 KB
                                       planes (MAME byte 3, 2, 1, 0 of each dword); row {tile, row}
                                       goes to granule {tile, row}, the left half high, each dword
                                       reversed
"""
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
out = REPO / "debug" / "lemmings-top"
out.mkdir(parents=True, exist_ok=True)
subprocess.run([sys.executable, str(REPO / "scripts" / "build_mra.py"), "--image", str(out / "image.bin")],
               check=True)
img = (out / "image.bin").read_bytes()

sdram = bytearray(img)
for base in (0x100000, 0x140000):
    for t in range(0x40000 // 128):
        for h in range(2):
            for r in range(16):
                for b in range(4):
                    m = t * 128 + h * 64 + r * 4 + b             # MAME's region offset
                    src = base + (3 - b) * 0x10000 + m // 4
                    dst = base + t * 128 + r * 8 + h * 4 + (3 - b)
                    sdram[dst] = img[src]

segs = [(0x000000, 0x100000), (0x100000, 0x80000), (0x180000, 0x10000), (0x190000, 0x20000)]
(out / "image.hex").write_text("".join(f"{x:02x}\n" for x in img))
(out / "expect.hex").write_text("".join(f"{sdram[i] | sdram[i + 1] << 8:04x}\n" for i in range(0, len(sdram), 2)))
(out / "segs.txt").write_text("".join(f"{a:x} {n:x}\n" for a, n in segs))
print(f"{out}: image {len(img)} bytes, {len(segs)} segments")
