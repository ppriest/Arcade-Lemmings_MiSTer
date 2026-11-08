-- Every main-CPU write to the pixel layer (0x300000-0x37ffff), in order, against
-- sim/lem_top_tb's +PIXTRACE log (sim/lem_top_tb/cmp_pix.py).
--
--   CORE_OUT     directory to write into
--   CORE_FRAMES  stop after this many frames (default 6000)
--
-- Line: frame  word address (hex, from 0x300000)  mask  data

local OUT    = os.getenv("CORE_OUT") or "."
local FRAMES = tonumber(os.getenv("CORE_FRAMES") or "6000")

local mach = manager.machine
local prog = mach.devices[":maincpu"].spaces["program"]
local scr  = mach.screens[":screen"]

local f = assert(io.open(OUT .. "/lemmings_pix.trace", "w"))
f:write("# maincpu writes to 300000-37ffff, MAME\n# frame\tword\tmask\tdata\n")
local n, done = 0, false

local function stop()
    if done then return end
    done = true
    f:write(string.format("# %d logged\n", n))
    f:close()
    print(string.format("PIXTRACE %d writes to %s/lemmings_pix.trace", n, OUT))
    mach:exit()
end

_G.__pix_tap = prog:install_write_tap(0x300000, 0x37ffff, "pix_wr", function(o, d, m)
    if not done then
        n = n + 1
        f:write(string.format("%d\t%05X\t%04X\t%04X\n", scr:frame_number(), (o - 0x300000) >> 1, m, d & m))
    end
    return d
end)
_G.__pix_notifier = emu.add_machine_frame_notifier(function()
    if scr:frame_number() >= FRAMES then stop() end
end)
