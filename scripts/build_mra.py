#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Write the .mra and prove it byte for byte. Adapted from Arcade-Pandora_MiSTer's build_mra.py.

    python scripts/build_mra.py                    # -> releases/_dev/
    python scripts/build_mra.py --check            # verify only, write nothing
    python scripts/build_mra.py --image out.bin    # the download image, for the benches
    python scripts/build_mra.py --release          # -> releases/

The image is the SDRAM layout of rtl/memory/lem_sdram_top.sv, whose *_BASE localparams are read
here, before the download's sprite reorder (rtl/memory/lem_dl_xform.sv). The sprite regions go as
four 64 KB planes, not in MAME's layout (PLANAR). Each region is built twice: from the driver's
ROM_START records (scripts/extract_romstart.py) and by re-reading the written .mra with
scripts/mra.py; the two must be identical. Interleave maps are not reasoned about: each
candidate is tried against the ROM_START image. The pixel layer's 512 KB of zeros is in the image so
the core starts it as MAME does.
"""
import argparse
import itertools
import re
import subprocess
import sys
from pathlib import Path
from xml.sax.saxutils import escape

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_dips as edips       # noqa: E402
import extract_romstart as ers     # noqa: E402
import mra as mra_lib              # noqa: E402
from coretools import setting      # noqa: E402

REPO = Path(__file__).resolve().parent.parent
DRIVER = Path(setting("MAME_SRC") or "")
ROMDIRS = [Path(p) for p in (setting("MAME_ROMPATH") or "").split(";") if p]
SETNAME = "lemmings"
# region, base localparam, size in the image
REGIONS = (("maincpu", "MAIN_BASE", 0x100000), ("sprites1", "SPR1_BASE", 0x40000),
           ("sprites2", "SPR2_BASE", 0x40000), ("audiocpu", "SOUND_BASE", 0x10000),
           ("oki", "OKI_BASE", 0x40000))
PIX_SIZE = 0x80000
PLANAR = ("sprites1", "sprites2")
# lemmings.cpp PORT_NAMEs: button 1 Select, button 2 Hurry
BUTTONS = ["Select", "Hurry"]


def sdram_map():
    text = (REPO / "rtl" / "memory" / "lem_sdram_top.sv").read_text(encoding="utf-8")
    return {m.group(1): int(m.group(2), 16)
            for m in re.finditer(r"localparam logic \[24:0\] (\w+_BASE)\s*=\s*25'h([0-9a-fA-F]+)", text)}


def game_info(text):
    m = re.search(r"GAME\(\s*(\d+)\s*,\s*" + SETNAME + r"\s*,[^\n]*", text)
    f = [x.strip() for x in m.group(0).split("(", 1)[1].split(",")]
    q = re.findall(r'"([^"]*)"', m.group(0))
    return {"year": f[0], "ports": f[4], "manufacturer": q[0], "title": q[1]}


def find_zip():
    for d in [REPO / "roms"] + ROMDIRS:
        if (d / f"{SETNAME}.zip").exists():
            return d / f"{SETNAME}.zip"
    sys.exit(f"{SETNAME}.zip not found in roms/ or MAME_ROMPATH")


def load_region(zs, records, size):
    """MAME's region as ROM_START fills it; unloaded bytes are 0 (ROMREGION_ERASE00 here)."""
    out = bytearray(size)
    step = {"load": 1, "load16_byte": 2, "load32_byte": 4}
    for kind, name, dest, length, crc, *_ in records:
        if kind not in step:
            sys.exit(f"record kind {kind} not handled")
        data = mra_lib._zip_read(zs, name, crc)[:length]
        assert len(data) == length, (name, len(data), length)
        out[dest:dest + step[kind] * length:step[kind]] = data
    return bytes(out)


def region_xml(zs, records, want):
    """<part>/<interleave> lines reproducing `want`, with maps found by trying them."""
    kinds = {r[0] for r in records}
    if kinds == {"load"}:
        return [f'        <part crc="{crc:08x}" name="{name}"/>' for _, name, _, _, crc, *_ in records]
    width = {"load16_byte": 2, "load32_byte": 4}[kinds.pop()]
    lines = []
    # one interleave per group of records sharing a dest block
    groups = {}
    for r in records:
        groups.setdefault(r[2] // width, []).append(r)
    for _, grp in sorted(groups.items()):
        datas = {r[1]: mra_lib._zip_read(zs, r[1], r[4])[:r[3]] for r in grp}
        base = grp[0][2] - grp[0][2] % width
        target = want[base:base + width * grp[0][3]]
        for m in itertools.permutations(range(width), len(grp)):
            maps = []
            for (r, pos) in zip(grp, m):
                s = ["0"] * width
                s[width - 1 - pos] = "1"
                maps.append("".join(s))
            got = mra_lib.interleave([(datas[r[1]], mp) for r, mp in zip(grp, maps)], 8 * width)
            if got == target:
                break
        else:
            sys.exit(f"no interleave map reproduces {[r[1] for r in grp]} at 0x{base:x}")
        lines.append(f'        <interleave output="{8 * width}">')
        lines += [f'            <part crc="{r[4]:08x}" name="{r[1]}" map="{mp}"/>' for r, mp in zip(grp, maps)]
        lines.append("        </interleave>")
    return lines


def switches(ports):
    """<dip> lines from the 16-bit DSW port: bits 0-15."""
    edips.SRC = str(DRIVER)
    blocks = edips.load()
    missing = set()
    parsed = edips.parse_ports(blocks[ports], blocks, missing)
    if missing:
        sys.exit(f"DEF_STR missing: {', '.join(sorted(missing))}")
    # bits with no declared default (PORT_DIPUNKNOWN parses to none) read high, as in MAME
    default, out = 0xFFFF, []
    q = {chr(34): "&quot;"}
    for name, mask, dflt, settings in parsed["DSW"]:
        default = (default & ~mask) | dflt
        pos = [i for i in range(16) if mask & (1 << i)]
        if settings is None:
            continue
        ids = []
        for idx in range(1 << len(pos)):
            v = sum(1 << b for j, b in enumerate(pos) if idx & (1 << j))
            lab = settings.get(v, "-")
            if "," in lab:
                sys.exit(f"dip {name!r}: label {lab!r} contains a comma")
            ids.append(lab)
        out.append(f'        <dip name="{escape(name, q)}" bits="{pos[0]},{pos[-1]}" '
                   f'ids="{escape(",".join(ids), q)}"/>')
    return out, default


def mame_version():
    exe = Path(setting("MAME_DIR") or "") / (setting("MAME_EXE") or "mame.exe")
    out = subprocess.run([str(exe), "-version"], capture_output=True, text=True, timeout=30).stdout
    m = re.match(r"\s*0\.(\d+)", out)
    if not m:
        sys.exit(f"cannot read the MAME version from {exe}")
    return "%04d" % int(m.group(1))


def build(out_root, write=True):
    sm = sdram_map()
    text = DRIVER.read_text(encoding="utf-8", errors="replace")
    body = ers.blocks(text)[SETNAME]
    info = game_info(text)
    zpath = find_zip()
    import zipfile
    zs = [zipfile.ZipFile(zpath)]

    img = bytearray()
    L = []
    for region, key, size in REGIONS:
        base = sm[key]
        if len(img) < base:
            pad = base - len(img)
            L.append(f'        <part repeat="0x{pad:X}">00</part>')
            img += bytes(pad)
        assert len(img) == base, (region, hex(len(img)), hex(base))
        records, unknown = ers.region_records(body, region)
        if unknown:
            sys.exit(f"{region}: records not understood: {unknown}")
        want = load_region(zs, records, size)
        if region in PLANAR:
            # MiSTer Main sizes an <interleave> by its byte-0 part alone; these regions have none
            # (byte 0 erased), so send planes and let lem_dl_xform.sv interleave
            L.append(f"        <!-- {region} at 0x{base:06X}: planes of MAME bytes 3, 2, 1, 0 -->")
            assert size == 0x40000 and all(r[0] == "load32_byte" and r[3] == 0x10000 for r in records)
            by_lane = {r[2] % 4: r for r in records}
            assert 0 not in by_lane
            for lane in (3, 2, 1):
                _, name, _, _, crc, *_ = by_lane[lane]
                L.append(f'        <part crc="{crc:08x}" name="{name}"/>')
            L.append('        <part repeat="0x10000">00</part>')
            img += b"".join(want[lane::4] for lane in (3, 2, 1, 0))
            continue
        L.append(f"        <!-- {region} at 0x{base:06X} -->")
        L += region_xml(zs, records, want)
        img += want
        # the region may be larger than its files: the rest is the zeros MAME starts it with
        step = {"load": 1, "load16_byte": 2, "load32_byte": 4}
        filled = max(r[2] - r[2] % step[r[0]] + step[r[0]] * r[3] for r in records)
        if filled < size:
            L.append(f'        <part repeat="0x{size - filled:X}">00</part>')
    pad = sm["PIX_BASE"] - len(img)
    L.append(f'        <part repeat="0x{pad:X}">00</part>')
    L.append(f"        <!-- pixel layer at 0x{sm['PIX_BASE']:06X}, zeroed -->")
    L.append(f'        <part repeat="0x{PIX_SIZE:X}">00</part>')
    img += bytes(pad + PIX_SIZE)

    sw, sw_def = switches(info["ports"])
    q = {chr(34): "&quot;"}
    btn_names = ",".join(BUTTONS + ["Start", "Coin", "Pause"])
    btn_default = "A,B,Start,Select,R"
    xml = [
        "<misterromdescription>",
        "    <!-- Generated by scripts/build_mra.py from MAME lemmings.cpp; the layout is",
        "         rtl/memory/lem_sdram_top.sv. Do not edit by hand. -->",
        '    <about author="Paul Priest" webpage="" source="MAME lemmings.cpp"/>',
        f"    <name>{escape(info['title'])}</name>",
        f"    <setname>{SETNAME}</setname>",
        "    <rbf>Lemmings</rbf>",
        f"    <mameversion>{mame_version()}</mameversion>",
        f"    <year>{info['year']}</year>",
        f"    <manufacturer>{escape(info['manufacturer'])}</manufacturer>",
        "    <category>Puzzle</category>",
        "    <rotation>horizontal</rotation>",
        "    <players>2</players>",
        "    <joystick>8-way</joystick>",
        f'    <buttons names="{escape(btn_names, q)}" default="{btn_default}" count="{len(BUTTONS)}"/>',
        "",
        "    <!-- address: the HPS puts the image in DDR3 and the core copies it to SDRAM (rtl/memory/rom_loader.sv) -->",
        f'    <rom index="0" zip="{SETNAME}.zip" md5="none" address="0x30000000">',
        *L,
        "    </rom>",
        "",
        f'    <switches default="{sw_def & 0xff:02X},{sw_def >> 8:02X}">',
        *sw,
        "    </switches>",
        "</misterromdescription>",
        "",
    ]
    out_root.mkdir(parents=True, exist_ok=True)
    fname = out_root / (re.sub(r'[\\/:*?"<>|]', "-", info["title"]) + ".mra")
    tmp = fname.with_suffix(".mra.tmp")
    tmp.write_text("\n".join(xml), encoding="utf-8", newline="\n")
    got = mra_lib.build_image(str(tmp), [str(zpath)])
    for z in zs:
        z.close()
    if got != bytes(img):
        diff = next((i for i in range(min(len(got), len(img))) if got[i] != img[i]), min(len(got), len(img)))
        tmp.unlink()
        sys.exit(f"the .mra image differs from the ROM_START image at 0x{diff:x} ({len(got)} vs {len(img)} bytes)")
    if write:
        tmp.replace(fname)
        print(f"{fname.relative_to(REPO)}: image {len(img)} bytes, identical to ROM_START")
    else:
        tmp.unlink()
        print(f"image {len(img)} bytes, identical to ROM_START (not written)")
    return bytes(img)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--release", action="store_true")
    ap.add_argument("--image", metavar="OUT")
    a = ap.parse_args()
    out_root = REPO / "releases" / ("" if a.release else "_dev")
    img = build(out_root, write=not (a.check or a.image))
    if a.image:
        Path(a.image).write_bytes(img)
        print(f"wrote {a.image}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
