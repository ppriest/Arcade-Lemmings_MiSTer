# Hacks, approximations and workarounds in this core

Everything in this core's own RTL, scripts or `.mra` layout that is known not to be what the
hardware does: a stand-in, a shortcut, a value chosen to make something work, a workaround for a
tool. Each entry is added in the commit that introduces the hack and removed in the commit that
removes it.

This is not `MAME_KLUDGES.md`. That file lists MAME's own guesses that the core reproduces on
purpose because MAME is the reference. This file lists what is ours.

Rules:

- An entry cites `file:line` (or a module and signal name if the line moves often), and the
  evidence column says what was measured, or "unverified".
- "What would make it correct" names the work, not "fix later".
- A hack whose entry is missing is a bug. A hack whose entry is stale is worse: update it in the
  same commit as the code.
- Severity is what a player or a verifier would see: **visible** (wrong pixels, wrong sound, wrong
  timing a game can hit), **latent** (wrong only for input no in-scope set produces), **tooling**
  (affects the build or the bench, not the bitstream).

| What | Where | Why it is a hack | What would make it correct | Evidence | Severity |
|---|---|---|---|---|---|
| Sound mix 0.45 as 0.4492 | `rtl/sound/lem_sound.sv` `x045` | MAME's route gain by shifts, no multiply | none needed: 0.2% low | arithmetic | latent |
| Trackball from the mouse moves by the mouse's raw delta | `Lemmings.sv` `tb_x0`, `tb_y0` | MAME scales by `PORT_SENSITIVITY(70)`; scaling needs a multiply or a shift approximation | 0.7 as shifts and adds, or an OSD speed option | unverified | visible |
| Trackball from the stick moves 7 a frame | `Lemmings.sv` `tb_x0` ... `tb_y1` | `PORT_KEYDELTA(10)` at sensitivity 70 as read from MAME's ioport semantics, not measured | A MAME run measuring the counter per frame with a key held | unverified | visible |
| SDRAM clock phase not swept | `rtl/pll/pll_0002.v` | Pandora's lead in ns at 48 MHz carried to 49 MHz | A phase sweep on hardware | unverified | latent |
| A sprite list copy takes 1024 clocks; a CPU access to that list waits for it | `lem_board.sv` `lem_spr_list` | MAME copies at once; the copy keeps MAME's contents but stalls the 68000 up to 21 us | The board's own copy timing | trace equal to MAME's through 32052 writes (`sim/lem_top_tb`) | latent |
| The 68000 waits for SDRAM on ROM and pixel-layer accesses | `lem_board.sv` `X_ROM`, `X_PIX` | MAME's 68000 has no wait states | ROM in block RAM is not possible (1 MB) | interrupts land later in the instruction stream than MAME's (`sim/lem_top_tb`, write 32053) | latent |
| DECO 146 port B bits 15:4 read 0 | `lem_board.sv` `u_deco` `port_b` | `SYSTEM` declares bits 0-3 only | A MAME read of the undeclared bits | unverified | latent |
| Blink phase toggles at vblank start | `lem_board.sv` `frame_odd` | MAME's frame number parity, alignment to vblank not checked | A capture of a blinking sprite at two adjacent frames | unverified | visible |

<!-- Examples of the shape, from sibling cores:
| Sound mailbox is a stub that answers the power-on test | `rtl/gx_snd_stub.sv` | No sound CPU yet; the stub returns the reply the test expects and a heartbeat | Phase 3: the real sound board | The game's RAM check passes with it; nothing else is exercised | visible |
| Sound-command spin of 800 CPU clocks after a latch write | `rtl/cpu/…_bus.sv:NNN` | Copies MAME's 40 us wait; the real board's mechanism is unknown | A measurement of the latch on hardware | Without it the second byte overwrote the first (commit) | latent |
| Sound CPU reset held 1,024 clocks | `rtl/….sv:NNN` | MAME's pulse is zero-length; the T80 needs to see it | The measured reset length | A PCB measurement says about one second | latent |
| Screen timing from one game used for every game | `rtl/video/…crtc.sv` | MAME declares 60 Hz with no comment; the one PCB-verified rate is used for all | Per-game timing from PCB measurement | 0.043% from the verified rate | visible |
-->

## Removed

Entries move here when the hack is gone, with the commit that removed it, so a later reader can
tell "never had it" from "had it and fixed it". Delete a row once nothing else refers to it.

| What | Removed by | Replaced with |
|---|---|---|
| No sound: the sound board was not built | Phase 3 | `rtl/sound/lem_sound.sv`: the 6809, jt51, jt6295 |
