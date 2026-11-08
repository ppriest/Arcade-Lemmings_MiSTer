# Lemmings — MiSTer Core Roadmap

**This roadmap is a proposal until the user approves it. No phase executes before that approval,
and a phase whose scope changes goes back for approval.**

## Context

Goal: a DE10-nano MiSTer core for Lemmings (Data East, DE-0357), emulated by MAME's
`dataeast/lemmings.cpp` and the devices it instantiates — a Quartus 17.0.2 Verilog/SystemVerilog
project producing one `.rbf` and one `.mra`.

CPUs, sound chips and the protection chip all exist in sibling cores. New work:

1. The DECO 52/71 sprite pair, twice, on a standard line engine (no RTL found).
2. The pixel layer: 512 KB of CPU-written bitmap in SDRAM, read per line.
3. The RAM-defined tilemap.
4. Trackball input from mouse, analog stick and d-pad.

Cross-cutting findings from the previous cores are in **[`LESSONS_LEARNED.md`](LESSONS_LEARNED.md)**.
Working practice is in **[`WORKFLOW.md`](WORKFLOW.md)**.

## Progress

**Phases 0 and 1 complete; Phase 2 in progress.** Every number below is from the driver or arithmetic on it unless
marked measured.

## Game scope

| Set | Board | Machine config | Loaded | MAME flags |
|---|---|---|---|---|
| `lemmings` | DE-0357 | `lemmings` | 1,638,400 bytes: 1 MB main, 64 KB sound, 192 KB x 2 sprites, 128 KB samples | `MACHINE_SUPPORTS_SAVE` |

### Scope decision

- **In scope:** `lemmings`, the driver's only set.
- **Out of scope:** none exists.
- **First target:** `lemmings`.

## Hardware reality (from the driver, not assumption)

Details with line numbers are in [`HARDWARE_NOTES.md`](HARDWARE_NOTES.md).

### Chips

68000 14 MHz; MC68B09EP 1.3425 MHz; YM2151 3.58 MHz; M6295 1023924 Hz pin 7 high; DECO 75
(146-compatible) with the magic read xor; two DECO 52/71 sprite sets. MAME marks the 6809, YM2151 and
OKI clocks as unverified.

### Clocks

Board clocks: 28 MHz XTAL (`lemmings.cpp:452`), 32.22 MHz XTAL (456, 489).

Pixel clock: **7 MHz, 442 clocks per line, inferred** from `supbtime.cpp:468`, `dassault.cpp:756`,
`cninja.cpp:1039`. MAME gives only `set_refresh_hz(60)` (464). **264 lines per frame, 59.99 Hz**, by
user decision (open item 1).

| `clk_sys` | Multiple of 7 MHz | Note |
|---|---|---|
| 42 MHz | 6x | Lower than 48; leaves less for SDRAM clients |
| **49 MHz** | **7x** | **Chosen: nearest to 48 MHz with an exact pixel clock** |
| 56 MHz | 8x | 68000 divides exactly, but no measured shortfall justifies it |

SDRAM on `clk_sys`, multiple 1.

| Enable | Rate | Ratio of 49 MHz |
|---|---|---|
| `ce_pix` | 7 MHz | 1/7 |
| 68000 phases (fx68k needs two per cycle) | 28 MHz | 4/7 |
| 6809E (E and Q generated from it) | 1.3425 MHz | 537/19600 |
| YM2151 | 3.58 MHz | 179/2450 |
| M6295 | 1023924 Hz | 255981/12250000 |

Fractional enables from accumulators are exact in rate. The 68000's stalls are not repaid: measured
cost in Phase 0, criterion 4.

### Interrupts

68000 level 6 at vblank, held until acknowledged (`irq6_line_hold`, 454). Autovector at 0x78, ISR 0x1AC (read
from ROM, Phase 0). 6809 IRQ from YM2151 (490), FIRQ from the 146's sound latch (482).

### Memory map

[`HARDWARE_NOTES.md`](HARDWARE_NOTES.md), "Memory map".

### Video

[`HARDWARE_NOTES.md`](HARDWARE_NOTES.md), "Video". 320 x 224 visible, seven-step mix, three sprite list
copies per chip.

### Sound

6809 with 64 KB ROM (32 KB mapped) and 2 KB RAM, YM2151 stereo at 0.45, M6295 at 0.50 on both channels
(491-496). No sample banking.

### Protection

DECO 146-compatible: 2 KB mirror, no address scramble, magic read xor on (481). The input ports are
read through its table, so the protection chip is also the I/O path.

### Per-game configuration

None. One set: the `.mra` carries DIPs and button names only.

## Component reuse map

| block | plan | source |
|---|---|---|
| 68000 | fx68k, kernel with own bus interface; TG68K only if 49 MHz does not close | `Arcade-KonamiGX_MiSTer/rtl/cpu/fx68k/` (GPLv3) |
| 6809 | Sibling's `mc6809i` | `Arcade-BallySente_MiSTer/rtl/cpu/mc6809/` (MC6809E in that core) |
| YM2151 | jt51 | `Arcade-Pandora_MiSTer/rtl/sound/jt51/` (GPL-3.0) |
| M6295 | jt6295 | `Arcade-Pandora_MiSTer/rtl/sound/jt6295/` (GPL-3.0) |
| DECO 146 | Port `mlc_deco146.sv`: add ports A/B/C and the sound latch with FIRQ; regenerate the table with `gen_deco146.py` with port entries kept | `Arcade-DecoMLC_MiSTer/rtl/protection/` (from the same MAME device, same magic xor) |
| Sprite draw and buffer | `jtframe_objdraw`, `jtframe_obj_buffer` with the 52/71's format on top | `Arcade-LethalEnforcers_MiSTer/rtl/jtframe/`, Pandora |
| DECO 52/71 | Written from `decospr.cpp`; no RTL in siblings or `E:/jtcores` (its Data East cores are the older chips: `cop`, `midres`, `slyspy`, `karnov`, `ninja`; no 52/71 found by a search of file names and 146 references, not a read of each) | new |
| Pixel layer, tilemap | Written from the driver | new |
| SDRAM, arbiter, ROM loader | Sibling's stack at ~48 MHz on `clk_sys` | `Arcade-Pandora_MiSTer/rtl/memory/` |
| Hiscore | `hiscore.v` | `Arcade-Cischeat_MiSTer/rtl/hiscore/` |
| Keys, CRT Adjust, pause, debug probe | Per the skill's references | sibling copies, located at vendoring |

## On-chip RAM budget

Estimated, not a fit report. M10K: 553 blocks. Pandora, a comparable sibling, fits at 217 blocks
including its framework (`Arcade-Pandora_MiSTer/docs/ROADMAP.md:32`).

| Memory | Size | Blocks |
|---|---|---|
| Work RAM | 64 KB | 64 |
| Tile pixels (0x380000) | 128 KB | 103 |
| Sprite lists, 3 copies x 2 chips | 12 KB | 12 |
| Tilemap and extra RAM | 12 KB | 12 |
| Palette | 4 KB | 4 |
| Sprite line buffers, 2 x 2, 9 bits | | 4 |
| Pixel layer line buffer, double | 320 x 4 bits x 2 | 2 |
| 146 table and RAM | | 6 |
| Sound RAM | 2 KB | 2 |
| fx68k microcode, jt51, jt6295 | | ~20 |
| **Core** | | **~230** |
| Framework, CRT Adjust, hiscore | | measured at first build |

To watch: the 103-block tile pixel RAM. It moves to SDRAM if the framework leaves under ~10% free.

## Memory plan

No DDR3 during play. DDR3 at load time per the standard loader.

**BRAM:** work RAM, sprite lists, palette, tilemap, tile pixels, line buffers. Tile pixels are in BRAM
because the display reads a word per tile-row step and the CPU writes it directly, with no SDRAM client
added.

**SDRAM (32 MB module; only ~2.1 MB used):** main ROM, sound ROM, samples, sprite ROMs, pixel layer.
Each in its own bank so a video burst does not close the CPU's row.

The loader reorders sprite ROMs so one sprite row, 16 pixels, is one burst of 4 words.

Budget per line: 442 x 7 = 3094 clocks. Assuming 10 clocks per 4-word burst, not yet measured:

| Client | Per line | Clocks |
|---|---|---|
| Pixel layer | 161 words, 41 bursts (42 windowed) | ~420 |
| Refresh | ~8 | ~50 |
| Sprite scan | 256 entries x 2 chips, BRAM, in parallel | no SDRAM |
| Sprites | 1 burst per row, fetched while the previous row draws | 10 each |
| 68000 ROM and pixel access, worst case | every 14 clocks | ~1770 |
| Sound CPU, samples | ~1-2 per line combined | ~30 |

Sprite rows per line: ~80 with the CPU at its worst case, ~260 if the CPU waits. 256 per chip on one
line does not fit. Measured in Phase 1: at most 70 visible rows on one line of one chip (title screen),
which fits in simulation at 16 clocks of latency with each row's draw (16 clocks) overlapping the
next row's fetch. Overrun counters for both engines and the pixel fetch go on the debug page. Video
has priority; the CPU stalls by DTACK.

## Design decisions

**Follow MAME, including where MAME is wrong, and write down every place that is.** There is no PCB
here. Known entries for `docs/MAME_KLUDGES.md`: the `copy_bitmap` off-by-one (line 239, x = 319, x = 159),
the generic screen timing, the unverified sound clocks.

**Where a vendored module and MAME disagree, record it and keep the module.**

**Every approximation of this core's own goes in `docs/HACKS.md`** in the commit it lands.

**Transcribe the reference literally first, then look for the chip.**

**One `.rbf`.** Two Quartus revisions, `Lemmings_stp` and `Lemmings`, differing only by `DEBUG_ISSP`.

**Licence: GPL-3.0-or-later**, following fx68k, jt51 and jt6295. `THIRD-PARTY.md` is written with the
first vendored module. `sys/` is never edited.

**Per-scanline rendering from buffered sprite RAM; no frame buffer.** The driver's `m_bitmap0` and the
pixel RAM hold the same pixels, and the driver describes the layer as discrete logic over that RAM (111),
so reading it at display time is the inferred shape; nothing shows a separate frame buffer. Latch points come from the write sweep, in attract and in play.

**The pixel layer is read a line ahead into a line buffer.** A CPU write to the current line after its
fetch appears a line late; the sweep and frame comparisons will show whether that is visible. If it
is, it goes in `HACKS.md` or the fetch moves closer to scanout.

**No multiplies or divides in 2D pipelines.** The tile address arithmetic is shifts, since 32, 8 and 64
are powers of two.

**The standard feature set is part of done:** DIPs with MAME's keys, CRT Adjust, hiscore, fast DDR ROM
loading, HDMI scaling, crop and rotation, audio mix, Pause. The board has no flip: flip is a fake DIP
and OSD option through one path, verified against the unflipped frame rotated 180 degrees.

**Trackball on every input a MiSTer has.** Mouse assignable to P1 or P2 from the OSD, analog stick and
d-pad for both players, each feeding an 8-bit counter per axis with MAME's reversed X. Select and Hurry
on buttons, named in the `.mra`. MAME's keyboard keys too. Checked with a d-pad-only pad.

## Pitfalls that already bind decisions here

| Entry | What it binds here |
|---|---|
| "Sprite lists, line buffers and snapshots" | Sweep before wiring the three-copy list; later entries overdraw earlier, so the drop order matters |
| "Memory transport", "MiSTer integration" | Taking Pandora's SDRAM stack rather than a new one |
| "CPU cores" | fx68k kernel instantiated directly, own bus interface |
| "Reading MAME" | Sprite coordinates through the permanent flip in `decospr.cpp` |
| "Sound" | Judge sound by ear; MAME is not the oracle for sound timing |

## Phased roadmap

**Phase 0 — Vendoring spike and the measurements. The gate.**

Vendor every reused module with a `PROVENANCE.md`; run upstream testbenches unchanged. Stand up the
68000, ROM, work RAM and 146 in `rtl/synth_check/`. Exit criteria:

1. Every vendored module's own tests pass unchanged, on arrival.
   — Partly met. `jt51_tb`: 4462 of 4462 samples equal `expected_con7.txt`. jt6295's copy has no
   upstream bench and is byte-identical to Cischeat's. mc6809i has none either; its bench is a MAME
   trace in Phase 3, before it is wired to anything. fx68k: criterion 2. `objdraw` has no bench here;
   Phase 1's frame compare covers it.
2. The 68000 boots `lemmings` and matches MAME's bus trace access by access, peripherals stubbed.
   — Met: `sim/lem_boot_tb`, 500,000 accesses identical in order, direction, address, lanes and data,
   9 level 6 interrupts included. The bench raises each interrupt from MAME's trace.
3. The 146 bench matches MAME reads over its full 1024-address table with all three ports driven.
   — Met: `sim/deco146_tb`, 201,024 operations, 131,141 reads and 9,941 latch reads equal to a Python
   port of MAME's device.
4. Measured CPI on game code against 14 MHz, split between execution and SDRAM stall.
   — Met, on boot and attract code, `lem_boot_tb`. Time is the run against the same CPU clocks at
   14 MHz unstalled:

   | LAT (clk) | Icache | Accesses | CPU clocks per access | Stall clk per access | Slowdown |
   |---|---|---|---|---|---|
   | 2 | on | 500,000 | 4.529 | 0.424 | 2.7% |
   | 2 | off | 200,000 | 4.459 | 0.513 | 3.3% |
   | 8 | on | 200,000 | 4.459 | 2.444 | 15.7% |
   | 8 | off | 200,000 | 4.459 | 6.513 | 41.7% |

   Work RAM in BRAM and icache on keep the core near the LAT 2 row; the board stress in Phase 4
   measures the rest.
5. Standalone Fmax and area for fx68k at 49 MHz, deciding fx68k against TG68K.
   — Met: `rtl/synth_check/fx68k`, setup slack +11.385 ns (slow 100C), hold +0.320, Fmax 110.83 MHz,
   2,231 ALMs, 13 RAM blocks. **fx68k chosen.**
6. Write sweep in attract and in play, 1800 frames or more, recorded in `docs/write_timing_mame.txt`.
   — Met. Palette writes all fall in vblank +0..23. Sprite lists, tilemap and pixel RAM are written
   throughout the frame, so pixel and tilemap are read live per line and sprite lists copied as MAME
   does.
7. Whether the game ever reads back the high nibbles of pixel RAM, by MAME trace. If never, the layer
   can be stored at half size; otherwise full bytes stay.
   — Met: `scripts/mame/pixel_nibbles.lua`, 7200 frames with a coin. 3,216 high-nibble writes to
   pixel1, first at 38120C from PC 0003B2 in boot code. **Full bytes stay**; the run is not exhaustive.

**Phase 1 — Video, against a software model.**

`mame_capture` plus `render_model.py` reproducing `screen_update`, pixel-exact on captured frames, then
RTL layer by layer, in Verilator: tilemap, pixel layer with both window modes, both sprite chips, the
mix. Scenes: attract, one-player play, two-player split. Per-line sprite occupancy measured. Exit: RTL
frames pixel-identical to MAME's for that set, silent, in simulation.
— Met. `scripts/render_model.py` and `sim/lem_video_tb` (`rtl/video/lem_video.sv`) both match MAME's
`reference.png` with 0 mismatched pixels on four captures: `lemmings-attract` (frame 2400),
`lemmings-play` (title, 3000), `lemmings-1p` (level 1, 3000), `lemmings-2p` (split window, 3200).
The RTL also matches each rotated 180 degrees with `+FLIP=1`, at 10 and 16 clocks of memory latency,
with no line overrun. Most visible sprite rows on one line of one chip: 70 on the title (its logo is
drawn three times), 21 in two-player play, 6 in one-player.

**Phase 2 — Hardware bring-up.**

SDRAM with all clients, ROM download, `.mra` generation, inputs, DIPs, trackball, ISSP probe, OSD debug
page, Pause, then the standard feature set. Exit: `lemmings` boots and plays on a DE10-nano, silent, one
and two players, with screenshots compared to MAME natively.
— In progress. `rtl/lem_top.sv` (board, SDRAM stack, download) in `sim/lem_top_tb`: the download's
sprite reorder matches an independent Python reorder (0 words differ); the 68000's writes equal MAME's
boot trace for the first 32052, where the RTL's interrupt arrives earlier in the instruction stream;
RTL frames 999-1001 equal MAME's frame 1000 (Data East logo), 0 mismatched pixels. `.mra` from
`scripts/build_mra.py`, image identical to ROM_START. Built at 77df399: clk_sys setup +6.374 ns,
hold +0.247 ns, 458/553 M10K, 33% ALMs. RTL frames 1399-1401 equal MAME frame 1400 ("Credits: 00",
a sprite), 0 mismatched pixels. On the board at 17d5f82 (sprite ROMs sent as planes, 25cc5b9): attract
runs, sprites draw; the credits text has MAME's exact pixel mask but grey 136 where MAME and the RTL
bench give 144 (`/media/fat/screenshots/lemmings/20261107_150605-screen.png`), not yet explained.
Black word-pair columns in terrain (`debug/hw/shot-20261107-182359.png` against MAME frame 7260)
were 68000 pixel reads taking the wrong lane of an unaligned burst; fixed in b562f9f, gone on the
board by the user's eye.

**Phase 3 — Sound.**

6809, 146 latch, jt51, jt6295 on the arbiter. Exit: register traces from MAME reproduce correct audio,
by ear and by a decoded capture against MAME's output.

Status: bench (6f028cf) — through frame 1500 the 6809's M6295 writes and latch reads equal MAME's,
and its YM2151 register writes equal MAME's as a multiset, excluding register 0x14 (the ordering
differs at one tick, frame 489). On the board at b575647
(`Lemmings_30000004.rbf`): music and effects judged right by ear by the user. The decoded capture
against MAME's output is not done.

**Phase 4 — Accuracy and finish.**

Worst-case stress in play: full lemming count and two-player windowed mode, overrun counter read on the
board. `docs/MAME_KLUDGES.md`, `docs/HACKS.md`, README, floorplan, release per `RELEASE_PROCESS.md`.

**Phase 5 — Savestates, state dumps and cheats.** Optional. RTL is written for it from Phase 1 with
`docs/STATE.md`; the state dump comes first because it makes board bugs reproducible in a bench.

## Verification strategy

- MAME is a reference generator driven from scripts: boot traces, RAM and register dumps at known frames.
- The software model is checked against MAME first, the RTL against the model.
- Every vendored module is verified against MAME before it is wired to anything.
- Sprite and tile layouts get the "every bit of a tile exactly once" check before ROMs are involved.
- `.mra` is generated and re-read byte for byte against an image built from `ROM_START`.
- Worst cases are measured in the RTL with saturating counters.

## Repository setup

Seeded from **MiSTer-devel/Template_MiSTer**, `Template.*` renamed to `Lemmings.*` and split into the
`Lemmings_stp` and `Lemmings` revisions. Quartus **17.0.2**.

## Open items

1. ~~**Lines per frame.**~~ Closed by the user: **264 lines, 59.99 Hz.** 442 x 264 at 7 MHz matches
   MAME's 60 Hz to 0.02%. The sibling boards' 274 lines (57.80 Hz) was not taken; there is no evidence
   for this board either way, so the choice goes in `docs/MAME_KLUDGES.md` with the first video RTL.
2. ~~**MAME binary.**~~ Closed by the user: `E:/MAME-Checkouts/mame-master`, `lemmings.exe`.
   `mame_version`: 0 behind and 0 ahead of master.
3. ~~**Vblank status bit.**~~ Status bit and IRQ follow MAME: the bit is high 529 us from vblank start
   (`lem_board.sv` `vbl_cnt`), the display blanks 40 lines.
4. **Sound clocks.** Taken from MAME, marked unverified there; no PCB reference consulted. Going with
   MAME's unless a PCB recording turns up.

## Next steps

1. Phase 2: find where 144 becomes 136 between the core's RGB and the native screenshot; compare
   more screens (title, play) natively.
2. ISSP probe set in `Lemmings_stp`, OSD debug page.
