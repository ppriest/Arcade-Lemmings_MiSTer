# Third-party code and licences

This project is GPL-3.0-or-later (`LICENSE`), forced by the GPL-3 modules it vendors. `rtl/PROVENANCE.md`
says where each copy came from in the sibling cores; each directory's own `PROVENANCE.md` carries the
upstream commit and local changes.

| Component | Path | Author | Licence | Modified here |
|---|---|---|---|---|
| [fx68k](https://github.com/ijor/fx68k) (68000) | `rtl/cpu/fx68k/` | Jorge Cwik | GPLv3 | no |
| mc6809i (6809E) | `rtl/cpu/mc6809/` | Greg Miller's cavnex/mc6809, jotego's clock-enable fork | BSD-3-Clause; jotego's changes GPL-3.0 if jtcores' licence is read as covering them | no |
| [jt51](https://github.com/jotego/jt51) (YM2151) | `rtl/sound/jt51/` | Jose Tejada Gomez | GPL-3.0 | no |
| [jt6295](https://github.com/jotego/jt6295) (M6295) | `rtl/sound/jt6295/` | Jose Tejada Gomez | GPL-3.0 | no |
| [jtframe](https://github.com/jotego/jtframe) sprite draw | `rtl/jtframe/` | Jose Tejada Gomez | GPL-3.0-or-later | no |
| SDRAM controller and memory stack | `rtl/memory/sdram/`, `rtl/memory/sdram_*.sv`, `rom_loader.sv`, `sample_cache.sv`, `ddram_phy.sv`, `rtl/sound/oki_rom_bridge.sv` | Sorgelig's `sdram.v`, adapted through the Psikyo, DreamWorld and Pandora cores | GPL-3.0-or-later | yes: burst-4 reads, refresh interval, `rtl/memory/sdram/PROVENANCE.md` and `rtl/PROVENANCE.md` |
| hiscore | `rtl/hiscore/` | see its `PROVENANCE.md` | GPLv3 | no |
| DECO 146 | `rtl/protection/` | Arcade-DecoMLC, after MAME's `deco146` | GPL-3.0-or-later | yes: ports, sound latch, `rtl/protection/PROVENANCE.md` |
| Template_MiSTer `sys/` | `sys/` | MiSTer-devel | as its files state | never |

## Release checklist

- [x] Every vendored directory has a current `PROVENANCE.md` and its upstream `LICENSE`, or carries
  the licence in each file's header (`hiscore/`, `memory/sdram/`, `protection/`).
- [x] The README's third-party credits match this table.
