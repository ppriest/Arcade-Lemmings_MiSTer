#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""DECO 146 operations and MAME's answers (scripts/gen_deco146.py Deco146) for tb_deco146.

    python sim/deco146_tb/gen_ops.py [n] -> obj_iverilog/deco146_ops.txt

One line per operation, hex: kind addr data mask expected port_a port_b port_c snd_irq.
kind: 0 read, 1 write, 2 the 6809's read of the sound latch.
First every read address once, with new port values each time, then n random operations.
"""
import random
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts"))
import gen_deco146 as g   # noqa: E402


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 200000
    rows = g.table()
    m = g.Deco146(rows)
    rnd = random.Random(1146)
    bank_reads = [(i << 1) ^ 0x44A for i, r in enumerate(rows) if r[0] == 0 and r[1] == 0x78]
    port_reads = [(i << 1) ^ 0x44A for i, r in enumerate(rows) if r[0] != 0]
    out = []

    def rec(kind, a, d, mask, e):
        pa, pb, pc = m.ports
        out.append(f"{kind} {a:03x} {d:04x} {mask:04x} {e:04x} {pa:04x} {pb:04x} {pc:04x} {int(m.pending)}")

    # every address, with the bank word's swap and the port sources included
    for a in range(0, 0x800, 2):
        m.ports = [rnd.getrandbits(16) for _ in range(3)]
        rec(0, a, 0, 0, m.read(a))

    last_w = 0
    for _ in range(n):
        k = rnd.random()
        if rnd.random() < 0.2:
            m.ports = [rnd.getrandbits(16) for _ in range(3)]
        if k < 0.30:
            a = rnd.choice([0x2C, 0x36, 0x64, rnd.randrange(0, 0x800, 2), rnd.randrange(0, 0x800, 2) | 0x100])
            d = rnd.getrandbits(16)
            mask = rnd.choice([0xFFFF, 0xFFFF, 0xFF00, 0x00FF])
            m.write(a, d, mask)
            last_w = a
            rec(1, a, d, mask, 0)
        elif k < 0.35:
            rec(2, 0, 0, 0, m.soundlatch_r())
        else:
            a = rnd.choice([last_w, rnd.choice(bank_reads), rnd.choice(port_reads), rnd.randrange(0, 0x800, 2)])
            rec(0, a, 0, 0, m.read(a))
    (REPO / "obj_iverilog").mkdir(exist_ok=True)
    (REPO / "obj_iverilog" / "deco146_ops.txt").write_text("\n".join(out) + "\n")
    print(f"{len(out)} operations, {sum(1 for o in out if o[0] == '0')} reads")


if __name__ == "__main__":
    main()
