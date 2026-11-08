#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Software model of lemmings.cpp's screen_update over a mame_capture directory.

    python scripts/render_model.py <rom zip> <capture dir> [<capture dir> ...]

Writes model.png beside reference.png and prints the pixel match. line numbers are lemmings.cpp and
decospr.cpp in MAME_SRC.
"""
import sys
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image

W, H, TOP = 320, 224, 16  # 467: visible lines 16-239


def sprite_tiles(z, names):
    """sprite_layout, 424-433, from the 3 bpp ROMs at bytes 3, 2, 1; byte 0 is erased (515-523)."""
    n = 0x10000 // 32
    pl = [np.frombuffer(z.read(f), dtype=np.uint8) for f in names]  # names[i] = byte 3 - i
    # One dword per 8 pixels, 64 bytes per half tile, right half first.
    out = np.zeros((n, 16, 16), dtype=np.uint8)
    for t in range(n):
        for half, x0 in ((0, 8), (1, 0)):
            for r in range(16):
                i = t * 32 + half * 16 + r
                b1, b2, b3 = int(pl[2][i]), int(pl[1][i]), int(pl[0][i])
                for c in range(8):
                    s = 7 - c
                    out[t, r, x0 + c] = (((b1 >> s) & 1) << 2) | (((b2 >> s) & 1) << 1) | ((b3 >> s) & 1)
    return out


def draw_sprites(ram, tiles, frame):
    """draw_sprites_common with flip_screen true (232-233), into a raw bitmap: pen | colour << 4."""
    bm = np.zeros((256, W), dtype=np.uint16)

    def tile(code, colour, fx, fy, x, y):
        px = tiles[code & (len(tiles) - 1)]
        if fx:
            px = px[:, ::-1]
        if fy:
            px = px[::-1, :]
        for r in range(16):
            yy = y + r
            if not TOP <= yy < TOP + H:
                continue
            for c in range(16):
                xx = x + c
                if 0 <= xx < W and px[r, c]:
                    bm[yy, xx] = int(px[r, c]) | (colour << 4)

    for o in range(0, 0x400, 4):
        y0, code, x0 = int(ram[o]), int(ram[o + 1]), int(ram[o + 2])
        if (y0 >> 12) & 1 and frame & 1:
            continue
        colour = (x0 >> 9) & 0x7f
        if y0 >> 15:
            colour |= 0x80
        w = (y0 >> 11) & 1
        fx = (y0 >> 13) & 1
        fy = (y0 >> 14) & 1
        multi = (1 << ((y0 >> 9) & 3)) - 1
        x = x0 & 0x1ff
        y = y0 & 0x1ff
        if x >= 320:
            x -= 512
        if y >= 256:
            y -= 512
        y = 240 - y
        x = 304 - x
        code &= ~multi
        if fy:
            inc = -1
        else:
            code += multi
            inc = 1
        y = 240 - y
        fy ^= 1
        x = 304 - x
        fx ^= 1
        mult2 = multi + 1
        while multi >= 0:
            ypos = y + 16 * multi
            tile(code - multi * inc, colour, fx, fy, x, ypos)
            if w:
                tile(code - multi * inc - mult2, colour, fx, fy, x + 16, ypos)
            multi -= 1
    return bm


def be16(path):
    return np.frombuffer(path.read_bytes(), dtype=">u2").astype(np.uint16)


def render(z_sprites, d, frame):
    pal_w = be16(d / "palette.bin")
    pal = np.zeros((1024, 3), dtype=np.uint8)
    for i in range(1024):  # 472: xBGR_888
        hi, lo = int(pal_w[i * 2]), int(pal_w[i * 2 + 1])
        pal[i] = (lo & 0xff, lo >> 8, hi & 0xff)
    ctl = be16(d / "control.bin")
    vram = be16(d / "vram.bin")
    p0 = np.frombuffer((d / "pixel0.bin").read_bytes(), dtype=np.uint8) & 0xf  # 177-178
    p1 = np.frombuffer((d / "pixel1.bin").read_bytes(), dtype=np.uint8) & 0xf  # 193-196
    spr = [draw_sprites(be16(d / "sprdraw1.bin"), z_sprites[0], frame),  # 234
           draw_sprites(be16(d / "sprdraw0.bin"), z_sprites[1], frame)]  # 235

    out = np.zeros((256, W), dtype=np.uint16) + 0x4000  # 237, 0x4000 marks black

    def sprites(chip, pri, base):  # 238, 254, 255, 257
        m = ((spr[chip] & 0xf) != 0) & ((spr[chip] & 0x800) == pri)
        out[m] = (spr[chip][m] & 0xff) + base

    def bitmap(x_add, x_lo, x_hi):  # 206-222: the rectangle's last line and column are not drawn
        for y in range(TOP, TOP + H - 1):
            row = p0[y * 2048: y * 2048 + 2048]
            for x in range(x_lo, x_hi):
                v = row[(x + x_add) & 0x7ff]
                if v:
                    out[y, x] = int(v) | 0x100

    sprites(0, 0x800, 0x300)
    if not int(ctl[6]) & 2:  # 241
        bitmap(int(ctl[0]), 0, W - 1)
    else:
        bitmap(int(ctl[2]), 0, 159)
        bitmap(int(ctl[0]), 160, W - 1)
    sprites(1, 0x800, 0x200)
    sprites(0, 0, 0x300)
    # 118-126, 130: tilemap, 64 x 32 by columns, no scroll, pen 0 transparent
    for y in range(TOP, TOP + H):
        for x in range(W):
            e = int(vram[(x >> 3) * 32 + (y >> 3)])
            t = e & 0x7ff
            sx = (t >> 5) * 8 + (x & 7)
            sy = (t & 31) * 8 + (y & 7)
            v = p1[sy * 512 + sx]
            if v:
                out[y, x] = (e >> 12 & 0xf) << 4 | int(v)
    sprites(1, 0, 0x200)

    rgb = pal[np.minimum(out, 1023)]
    rgb[out == 0x4000] = 0
    return rgb[TOP:TOP + H]


def main():
    z = zipfile.ZipFile(sys.argv[1])
    tiles = [sprite_tiles(z, [f"lemmings.{n}" for n in (12, 13, 14)]),  # 474, 520-523
             sprite_tiles(z, [f"lemmings.{n}" for n in (9, 10, 11)])]   # 475, 515-518
    bad = 0
    for arg in sys.argv[2:]:
        d = Path(arg)
        frame = int(next(l for l in (d / "manifest.txt").read_text().splitlines() if l.startswith("frame")).split()[1])
        ref = np.array(Image.open(next(d.rglob("reference.png"))).convert("RGB"))
        got = render(tiles, d, frame)
        Image.fromarray(got).save(d / "model.png")
        diff = (got != ref).any(axis=2) if got.shape == ref.shape else np.ones(got.shape[:2], bool)
        nb = int((ref != 0).any(axis=2).sum())
        print(f"{d.name}: frame {frame}, ref {ref.shape[1]}x{ref.shape[0]}, non-black {nb}, "
              f"mismatched {int(diff.sum())}")
        if diff.any():
            ys, xs = np.nonzero(diff)
            print(f"  first y={ys[0]} x={xs[0]} model {got[ys[0], xs[0]]} MAME {ref[ys[0], xs[0]]}")
            bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
