-- A native-resolution snapshot every CORE_STEP frames up to CORE_FRAMES, no inputs (attract).
-- Run with -snapshot_directory set to CORE_OUT; files are f<frame>.png.

local STEP   = tonumber(os.getenv("CORE_STEP") or "120")
local FRAMES = tonumber(os.getenv("CORE_FRAMES") or "6000")

local mach = manager.machine
local scr  = mach.screens[":screen"]

_G.__snap_notifier = emu.add_machine_frame_notifier(function()
    local f = scr:frame_number()
    if f > 0 and f % STEP == 0 then scr:snapshot(string.format("f%05d.png", f)) end
    if f >= FRAMES then mach:exit() end
end)
