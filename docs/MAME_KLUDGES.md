# MAME kludges this core reproduces

This project follows MAME, including where MAME is wrong (ROADMAP, "Design decisions"), so the
software model and the RTL reproduce MAME's guesses on purpose. This file lists each one that
touches an in-scope set: where it is in MAME, what the core does, and what would settle the real
behaviour.

It also records where a vendored, silicon-derived module disagrees with MAME and the module was
kept (ROADMAP, "Where a vendored module and MAME disagree").

This core's own approximations are not here; they are in `HACKS.md`.

Source references are to `src/mame/dataeast/lemmings.cpp` unless named. MAME commit:
`c7f70a6ec10`.

**Core column:** *copies* MAME; *differs* (and why); *n/a* (not in the core's scope);
*not checked*.

`lemmings` carries `MACHINE_SUPPORTS_SAVE` only.

## Video

| Kludge | MAME | Core | Would settle it |
|---|---|---|---|
| Pixel layer drops each rectangle's last column and the screen's last line | `copy_bitmap`, 210 and 214: `y < bottom()`, `x < right()`, so line 239, x 319 and, windowed, x 159 are never drawn | copies, `lem_video.sv` `fskip` | A PCB frame of a level reaching that edge |
| Vblank status bit high for 529 us from vblank start | `set_vblank_time(ATTOSECONDS_IN_USEC(529))` (465), with no raw timing | copies: `lem_board.sv` `vbl_cnt`, 25921 clk; the display blanks 40 lines | A PCB measurement of the status bit |
| Frame shape: 264 lines, 442 clocks at 7 MHz | `set_refresh_hz(60)`, `set_size(320, 256)` (464-467); no raw timing | differs: MAME gives none; 264 lines by user decision, `lem_video.sv` | A PCB measurement of line and frame rate |
| Whole frame drawn at vblank start from RAM as it stands then | `screen_update`, 224-258 | differs: the tilemap, tile pixels, palette and pixel layer are read as each line is scanned or fetched, so a mid-frame CPU write shows from that line on | — |

## Vendored modules that disagree with MAME

| Module | MAME says | The module does | Kept because | Would settle it |
|---|---|---|---|---|
| `{{module}}` | {{MAME behaviour, file:line}} | {{module behaviour, file:line}} | {{silicon-derived / upstream bench / measured}} | {{what would show which describes the chip}} |
