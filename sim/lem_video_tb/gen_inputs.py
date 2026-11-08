#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Hex for sim/lem_video_tb from the ROM set and mame_capture directories.

    python sim/lem_video_tb/gen_inputs.py <lemmings.zip> <capture dir> [...]
"""
import sys
import zipfile
from pathlib import Path


def words(path):
    b = Path(path).read_bytes()
    return [(b[i] << 8) | b[i + 1] for i in range(0, len(b), 2)]


def hexfile(path, vals, w):
    Path(path).write_text("".join(f"{v:0{w}x}\n" for v in vals))


z = zipfile.ZipFile(sys.argv[1])
out = Path("debug/lemmings-video")
out.mkdir(parents=True, exist_ok=True)
# lemmings.cpp:515-523, byte 3, 2, 1 of each dword; byte 0 is erased.
for name, files in (("rom0", (12, 13, 14)), ("rom1", (9, 10, 11))):
    b3, b2, b1 = (z.read(f"lemmings.{n}") for n in files)
    dw = [(b1[i] << 16) | (b2[i] << 8) | b3[i] for i in range(0x10000)]
    # lem_sprite_line's row: {left half (+64 bytes), right half}, addressed {code, row}
    hexfile(out / f"{name}.hex", [(dw[t * 32 + 16 + r] << 32) | dw[t * 32 + r]
                                  for t in range(2048) for r in range(16)], 16)

for arg in sys.argv[2:]:
    d = Path(arg)
    # chip 0 draws the second list, chip 1 the first (lemmings.cpp:234-235)
    hexfile(d / "rtl_list0.hex", words(d / "sprdraw1.bin"), 4)
    hexfile(d / "rtl_list1.hex", words(d / "sprdraw0.bin"), 4)
    pw = words(d / "pixel0.bin")
    hexfile(d / "rtl_pix.hex", [(pw[i + 3] << 48) | (pw[i + 2] << 32) | (pw[i + 1] << 16) | pw[i]
                                for i in range(0, len(pw), 4)], 16)
    hexfile(d / "rtl_tpix.hex", words(d / "pixel1.bin"), 4)
    hexfile(d / "rtl_vram.hex", words(d / "vram.bin")[:2048], 4)
    hexfile(d / "rtl_ctl.hex", words(d / "control.bin"), 4)
    p = words(d / "palette.bin")
    hexfile(d / "rtl_pal.hex",
            [((p[i * 2 + 1] & 0xff) << 16) | (p[i * 2 + 1] & 0xff00) | (p[i * 2] & 0xff) for i in range(1024)], 6)
    frame = int(next(l for l in (d / "manifest.txt").read_text().splitlines() if l.startswith("frame")).split()[1])
    hexfile(d / "rtl_odd.hex", [frame & 1], 4)
    print(d, "frame", frame)
