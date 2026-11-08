# Lemmings state inventory

What a savestate or a state dump has to carry, kept current as RTL lands (the skill's
`savestates.md`). "Skip" needs a reason: a ROM table from the `.mra`, or something re-derived
every frame.

## RAMs

| Region | RTL | Width x depth | Bytes | Save? |
|---|---|---|---|---|
| Work RAM | `lem_board.sv` `u_wram` | 16 x 32768 | 65536 | yes |
| Sprite lists, live | `lem_spr_list` `u_live`, two | 16 x 1024 | 2048 each | yes |
| Sprite lists, buffer and drawn banks | `lem_spr_list` `u_banks`, two | 16 x 2048 | 4096 each | yes |
| Palette | `lem_board.sv` `u_pal_e`, `u_pal_o` | 16 x 1024, two | 4096 | yes |
| Tilemap and 0x202000 RAM | `lem_board.sv` `u_vram` | 16 x 8192 | 16384 (12288 mapped) | yes |
| Tile pixels (pixel_1) | `lem_board.sv` `u_pix1` | 16 x 65536 | 131072 | yes |
| Pixel layer (pixel_0) | SDRAM 0x200000, `lem_sdram_top.sv` port 1 | 16 x 262144 | 524288 | yes |
| Sound RAM | `lem_sound.sv` `ram` | 8 x 2048 | 2048 | yes |
| Sound ROM copy | `lem_sound.sv` `rom_e`, `rom_o` | 8 x 16384, two | 32768 | skip: from the `.mra` |
| DECO 146 RAM | `lem_deco146.sv` `ram_hi`, `ram_lo` | 16 x 256 | 512 | yes |
| Pixel-layer line buffer | `lem_video.sv` `plb` | 4 x 1024 | 512 | skip |
| Sprite line buffers | `jtframe_obj_buffer` in `lem_sprite_line` | 9 x 1024, two | 2304 | skip |

## Registers and FSMs

| What | RTL | Bits | Save? | MAME `save_item` equivalent |
|---|---|---|---|---|
| Raster position | `lem_video.sv` `phase`, `hcount`, `vcount` | 21 | yes | screen position |
| Blink phase | `lem_board.sv` `frame_odd` | 1 | yes | `screen().frame_number() & 1` |
| Control words | `lem_board.sv` `ctl` | 16 x 8 | yes | `control_data` share |
| Sprite list banks and copy | `lem_spr_list` `bp`, `dp`, `tgt`, `dp_pend`, `act`, `idx` | 15 each | yes; `act` 0 at a frame-start restore | `m_spriteram` buffer, triple buffer |
| DECO 146 registers, sound latch | `lem_deco146.sv` `bank`, `xor_r`, `nand_r`, `latch_*`, `snd_latch`, `snd_irq` | — | yes | `deco146` device |
| 68000 | `board_cpu` state stub | — | yes | `maincpu` |
| Sound enables | `lem_sound.sv` `acc_cpu`, `eq`, `acc_ym`, `ym_half`, `acc_oki` | 52 | yes | device clocks |
| Trackball counters | `Lemmings.sv` `tb_x0`, `tb_y0`, `tb_x1`, `tb_y1` | 32 | yes | `AN0`-`AN3` |
| Sprite engines, pixel fetch | `lem_sprite_line`, `lem_video.sv` `fstate` | — | skip | none |

## Chip state

| Chip | Module | Addressable? | Tier | Note |
|---|---|---|---|---|
| 68000 | `board_cpu` | yes, its state stub | — | not yet wired to an engine |
| DECO 146 | `lem_deco146` | RAM yes, registers no | — | registers need a port |
| 6809 | `mc6809i` in `lem_sound` | registers readable (`RegData`), not writable | — | needs a load port |
| YM2151 | `jt51` | no | — | the vendored copy has no state port |
| M6295 | `jt6295` | no | — | channel state in shift registers |

## Deliberately skipped

| What | Why it need not be saved |
|---|---|
| Line buffers, sprite engine and pixel fetch state | Rewritten for every line from RAM; a restore at frame start redraws them before line 16 |
| SDRAM ports, bridges' granule caches | ROM caches refill; no request crosses a frame-start restore |

## Frame alignment

Restore point (normally `frame_start`), and anything whose phase must be saved with it: sprite or
tile double-buffer selection, snapshot ownership bits.
