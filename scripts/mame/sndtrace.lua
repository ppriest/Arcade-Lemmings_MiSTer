-- The sound CPU's device traffic, for sim/lem_top_tb's sound trace (rtl/sound/lem_sound.sv):
-- YM2151 and M6295 writes and latch reads. RAM and status polls are left out: their count
-- depends on timing, the writes to the chips do not.
--
--   CORE_OUT       directory to write into
--   CORE_FRAMES    stop after this many frames (default 1200)
--   CORE_TRACE_N   or after this many accesses (default 400000)
--
-- Line: frame  rw  addr  data

local OUT    = os.getenv("CORE_OUT") or "."
local FRAMES = tonumber(os.getenv("CORE_FRAMES") or "1200")
local N      = tonumber(os.getenv("CORE_TRACE_N") or "400000")

local mach = manager.machine
local prog = mach.devices[":audiocpu"].spaces["program"]
local scr  = mach.screens[":screen"]

local f = assert(io.open(OUT .. "/lemmings_snd.trace", "w"))
f:write("# audiocpu writes to 0800-1fff and reads of 1800, MAME\n# frame\trw\taddr\tdata\n")
local n, done = 0, false

local function stop()
    if done then return end
    done = true
    f:write(string.format("# %d logged\n", n))
    f:close()
    print(string.format("SNDTRACE %d accesses to %s/lemmings_snd.trace", n, OUT))
    mach:exit()
end

local function log(rw, a, d)
    if done then return end
    n = n + 1
    f:write(string.format("%d\t%s\t%04X\t%02X\n", scr:frame_number(), rw, a, d & 0xff))
    if n >= N then stop() end
end

_G.__snd_taps = {
    prog:install_read_tap(0x1800, 0x1800, "snd_rd", function(o, d, m) log("r", o, d); return d end),
    prog:install_write_tap(0x0800, 0x1fff, "snd_wr", function(o, d, m) log("w", o, d); return d end),
}
_G.__snd_notifier = emu.add_machine_frame_notifier(function()
    if scr:frame_number() >= FRAMES then stop() end
end)
