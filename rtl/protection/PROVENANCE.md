# rtl/protection provenance

`lem_deco146.sv` is `Arcade-DecoMLC_MiSTer/rtl/protection/mlc_deco146.sv` at `14cce0963d35`, with:

- input ports A, B, C read instead of `0xffff` (`deco146.cpp` `read_data_getloc`; the table already
  encoded them)
- the sound latch at 0x64 with its interrupt and acknowledge (`write_soundlatch`, `soundlatch_r`)

The latch is set on the write's clock; MAME defers it with `scheduler().synchronize()`, which adds no
emulated time.

`scripts/gen_deco146.py` and `sim/deco146_tb/` come from the same commit, with the Python model
gaining the ports and the latch. `lem_deco146_table.hex` is generated from `deco146.cpp`.

Licence: GPL-3.0-or-later, as stated in the source files.
