# Vendored modules in this core

| Path here | Copied from | Source commit | Own provenance | Licence |
|---|---|---|---|---|
| `cpu/fx68k/` | Arcade-Cischeat `rtl/cpu/fx68k/` | `fac56790e5b2` | `cpu/fx68k/PROVENANCE.md` | GPLv3 |
| `cpu/fx68k_bus.sv`, `cpu/board_cpu.sv` | Arcade-Cischeat `rtl/cpu/` | `fac56790e5b2` | see below | GPL-3.0-or-later |
| `cpu/mc6809/` | Arcade-BallySente `rtl/cpu/mc6809/` | `9d040eed1bba` | `cpu/mc6809/PROVENANCE.md` | BSD-3-Clause |
| `sound/jt51/` | Arcade-Cischeat `rtl/sound/jt51/` | `fac56790e5b2` | `sound/jt51/PROVENANCE.md` | GPL-3.0 |
| `sound/jt6295/` | Arcade-Cischeat `rtl/sound/jt6295/` | `fac56790e5b2` | `sound/jt6295/PROVENANCE.md` | GPL-3.0 |
| `jtframe/` | Arcade-LethalEnforcers `rtl/jtframe/` | `fdaae77c10b4` | jtcores `f64dbe2fd4a9`, verbatim | GPL-3.0-or-later |
| `hiscore/` | Arcade-Cischeat `rtl/hiscore/` | `fac56790e5b2` | `hiscore/PROVENANCE.md` | GPLv3 |
| `protection/` | Arcade-DecoMLC, modified | `14cce0963d35` | `protection/PROVENANCE.md` | GPL-3.0-or-later |

The `PROVENANCE.md` files inside copied directories describe their use in the source core (Cisco Heat
clocks, Bally Sente's 6809) as well as the upstream history. The upstream history applies here; the use
in this core is in `docs/ROADMAP.md`.

`jtframe/` holds only the sprite draw closure: `jtframe_objdraw`, `_objdraw_gate`, `_draw`,
`_obj_buffer`, `_dual_ram`, `_sh`.

`fx68k_bus.sv` is unmodified. `board_cpu.sv` is unmodified; its state stub uses IPL 7, which this board
does not use either (`lemmings.cpp:454`, level 6 only).

Phase 2, from Arcade-Pandora_MiSTer at `d0ff7e7`:

| Path here | Copied from | Changes | Licence |
|---|---|---|---|
| `memory/sdram/`, `sdram_phy.sv`, `sdram_arbiter6.sv`, `sdram_narrow_bridge.sv`, `sdram_download.sv`, `sample_cache.sv`, `rom_loader.sv`, `ddram_phy.sv` | `rtl/memory/` | `sdram.sv` refresh interval 420 -> 380 cycles for 49 MHz; otherwise none. Pandora's own provenance: Arcade-DreamWorld `233d1f299192`, the Psikyo lineage, `sdram.sv` with the `dq_in` fix (`memory/sdram/PROVENANCE.md`) | GPL-3.0-or-later as adapted |
| `memory/lem_dl_xform.sv`, `memory/lem_sdram_top.sv` | `dl_xform.sv`, `snowbros_sdram_top.sv` | written for this core on their structure | GPL-3.0-or-later |
| `video/crt_adjust.sv`, `video/crt_vsize.sv`, `video/crt_chain.sv` | `rtl/video/` | none | GPL-3.0-or-later |
| `video/screen_rotate_two.sv` | `rtl/video/` | none; Sorgelig's rotator | GPL-2.0-or-later |
| `pll.v`, `pll.qip`, `pll/` | `rtl/` | `pll_0002.v` retuned to 49 MHz, SDRAM clock 17857 ps behind | Intel-generated |
| `mame_keys.sv` | `rtl/` | buttons 3 and 4 decoded only when `BUTTONS` allows | GPL-3.0-or-later |
| `sound/oki_rom_bridge.sv` | `rtl/sound/` at `b381440` | none | GPL-3.0-or-later |
