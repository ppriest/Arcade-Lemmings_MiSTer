# Lemmings: hardware notes

Source: MAME `src/mame/dataeast/lemmings.cpp`, `dataeast/deco146.cpp`, `shared/decospr.cpp`, in
`E:/mame` at `6b8abc8610f`. Those files have no diff against `mamedev/master` at `cc28a210f77`.
`-listxml` from the MAME 0.289 release binary. Everything here is MAME's model unless marked
otherwise. Line numbers are `lemmings.cpp` unless another file is named. No schematic or PCB
reference has been consulted.

## Sets

| Set | Game | Board variant | ROM loaded | MAME flags |
|---|---|---|---|---|
| `lemmings` | Lemmings (US prototype), 1991, Data East USA | DE-0357 | 1,638,400 bytes (below) | `MACHINE_SUPPORTS_SAVE`, ROT0 (534) |

The driver has one set and no clones. `lemmings.zip` is in `F:/Emulation/roms/MAME ROMs`.

| Region | Loaded | Layout | Lines |
|---|---|---|---|
| `maincpu` | 1 MB | 8 x 128 KB, 16-bit interleave | 502-510 |
| `audiocpu` | 64 KB | `lemmings.15`, 6809 sees 0x8000-0xffff of it | 512-513, 323 |
| `sprites1` | 192 KB in a 256 KB region | 3 x 64 KB at dword bytes 3, 2, 1; byte 0 reads 0 | 515-518 |
| `sprites2` | 192 KB in a 256 KB region | same layout | 520-523 |
| `oki` | 128 KB in a 256 KB region | `lemmings.16` | 525-526 |

## CPUs and chips

| Tag | Part | Clock | Role | Existing RTL |
|---|---|---|---|---|
| `maincpu` | 68000 ("Data East 59") | 14 MHz, 28 MHz XTAL / 2 (452) | main | fx68k, TG68K in siblings |
| `audiocpu` | MC68B09EP | 1.3425 MHz, 32.22 MHz / 24, "clock not verified" (456) | sound | `mc6809i` in BallySente |
| `ymsnd` | YM2151 | 3.58 MHz, 32.22 MHz / 9, "clock likely wrong" (489) | FM, stereo | jt51 |
| `oki` | M6295 | 1023924 Hz, pin 7 high, "not verified" (494) | samples | jt6295 |
| `ioprot` | DECO 75, 146-compatible (`deco146.cpp:58`) | none | I/O, protection, sound latch | `mlc_deco146.sv` in DecoMLC |
| `spritegen1/2` | 2 x DECO 52 + 71 (110) | not given | sprites | none; decospr is a software model |
| discrete | pixel layer logic (111) | not given | bitmap layer | none |

## Clocks

MAME gives no pixel clock: the screen is `set_refresh_hz(60)`, `set_size(320, 256)`,
`set_vblank_time(529 us)` (464-467), generic values rather than measured timing. The plan's 7 MHz
and 442 clocks per line are taken from other Data East 320-wide boards on a 28 MHz crystal:
`supbtime.cpp:468`, `dassault.cpp:756`, `cninja.cpp:1039` are `28 MHz / 4, 442, 0, 320, 274, 8, 248`
(57.80 Hz). That is an inference for this board, not evidence from it.

## Video

Display: visible 320 x 224, lines 16-239 (467). Aspect 4:3. The tilemap and pixel layer do not flip;
the sprite devices are permanently set to flipped (232-233), so the game's coordinates are
sprite-chip flipped relative to the layers. No flip register exists on this board.

Layers, back to front (237-257):

1. black
2. sprite chip 0 pixels with priority bit set, palette 0x300
3. pixel layer, palette 0x100-0x10f
4. sprite chip 1 pixels with priority bit set, palette 0x200
5. sprite chip 0 pixels with priority bit clear
6. tilemap, palette 0x000-0x0ff, pen 0 transparent
7. sprite chip 1 pixels with priority bit clear

Chip 0 is list `spriteram2` (0x140000), ROM `sprites2`, palette 0x300. Chip 1 is list `spriteram1`
(0x120000), ROM `sprites1`, palette 0x200 (234-235, 440-444, 474-475).

**Pixel layer.** 2048 x 256 x 4 bpp from 512 KB of RAM at 0x300000. Each word is two pixels, bits
11:8 then 3:0; a word's address is `{y[7:0], x[10:1]}` (171-178). Pen 0 transparent. X scroll only:
source x = `(x + control[0]) & 0x7ff` (216, 226). With `control[6]` bit 1 set, x 0-159 uses
`control[2]` and x 160-319 uses `control[0]` (241-252).

**Tilemap.** 64 x 32 of 8 x 8, column order, no scroll call in the driver (130). Word at 0x200000:
bits 15:12 colour, 10:0 tile (120-124). Tile pixels come from the 128 KB RAM at 0x380000, not ROM:
word offset is `{sy[7:0], sx[8:1]}`, two pixels per word as above, and tile `t` occupies
`sx = (t / 32) * 8`, `sy = (t % 32) * 8` (187-196). Only 512 x 256 pixels are addressable, so the
2048 tiles are the whole of that RAM.

**Sprites** (`decospr.cpp:215-386`, the default format as this driver uses it). 256 entries, 4 words:

| Word | Bits |
|---|---|
| 0 | 15 priority, 14 flip y, 13 flip x, 12 blink on odd frames, 11 double width, 10:9 height (1, 2, 4, 8 tiles), 8:0 y |
| 1 | tile |
| 2 | 12:9 colour used by this driver's palette mask (`0xff`, 238-257), 8:0 x |

X and y are 9 bits, wrapped to negative at 320 and 256. Earlier entries are overdrawn by later ones;
the mixing priority is the winner's. Tiles are 16 x 16, 3 bpp in the top three of four planes; each
row is one dword per 8 pixels and the right half precedes the left by 64 bytes (424-433).

**Sprite list buffering.** A write to 0x1c0000 / 0x1e0000 copies live RAM to a buffer (307-308); the
vblank rising edge copies that to a second buffer (150-158), which is what is drawn. Three copies per
chip.

**Palette.** 1024 entries, `xBGR_888`, 4 KB at 0x160000 (303, 472).

**MAME's own artefacts to follow:** `copy_bitmap` uses `<` against an inclusive bound (210, 214), so
the pixel layer never draws its last line or last column of each rectangle: line 239, x = 319, and in
windowed mode x = 159.

## Memory map

Main CPU (297-313):

| Address | Size | What |
|---|---|---|
| 0x000000-0x0fffff | 1 MB | ROM |
| 0x100000-0x10ffff | 64 KB | work RAM |
| 0x120000-0x1207ff | 2 KB | sprite list 1 |
| 0x140000-0x1407ff | 2 KB | sprite list 2 |
| 0x160000-0x160fff | 4 KB | palette |
| 0x170000-0x17000f | 16 B | control: [0], [2] scroll, [6] window; [4] not stored (262-268) |
| 0x190000-0x19000f | read | trackballs AN0-3 (270-275) |
| 0x1a0000-0x1a3fff | | DECO 146; address bits 13:11 are dropped, so a 2 KB mirror and no CS config access (279-280) |
| 0x1c0000, 0x1e0000 | write | sprite buffer triggers |
| 0x200000-0x201fff | 8 KB | tilemap RAM (4 KB of it addressed by the map) |
| 0x202000-0x202fff | 4 KB | RAM |
| 0x300000-0x37ffff | 512 KB | pixel layer |
| 0x380000-0x39ffff | 128 KB | tile pixels |

Sound CPU (317-324): RAM 0x0000-0x07ff, YM2151 0x0800-0x0801, OKI 0x1000, 146 sound latch read 0x1800,
ROM 0x8000-0xffff.

Interrupts: main, level 6 at vblank, `irq6_line_hold` (454). Sound: YM2151 to IRQ (490), the 146's
latch write to FIRQ (482).

Inputs: ports A `INPUTS`, B `SYSTEM`, C `DSW` through the 146 (478-480); the vblank line is `SYSTEM`
bit 3 (351). Trackball, 8 bits per axis per player, X reversed (398-408).

## Feasibility

Not a large board: 1.64 MB of ROM against 32 MB of SDRAM. The one size question is the 512 KB pixel
layer, which does not fit M10K alongside everything else; see the roadmap's memory plan.
