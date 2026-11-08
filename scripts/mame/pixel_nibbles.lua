-- Pixel RAM use over a run: reads by the CPU, and writes whose high nibbles are set
-- (bits 15:12 and 7:4; the driver displays only 11:8 and 3:0, lemmings.cpp:177-178, 193-196).
--   PN_COIN frame to coin up and start (0 attract), PN_FRAMES frames to run.
local FRAMES = tonumber(os.getenv("PN_FRAMES") or "3600")
local COIN   = tonumber(os.getenv("PN_COIN") or "0")
local OUT    = os.getenv("CORE_OUT") or "."
local mach = manager.machine
local cpu  = mach.devices[":maincpu"]
local prog = cpu.spaces["program"]
local c = { r0 = 0, r1 = 0, w0 = 0, w1 = 0, hi0 = 0, hi1 = 0 }
local first = {}
local function note(k, off)
  if not first[k] then first[k] = string.format("%06x pc %06x", off, cpu.state["CURPC"].value) end
end
_G.__pn = {
  prog:install_read_tap(0x300000, 0x37ffff, "pn_r0", function(o, d, m) c.r0 = c.r0 + 1; note("r0", o); return d end),
  prog:install_read_tap(0x380000, 0x39ffff, "pn_r1", function(o, d, m) c.r1 = c.r1 + 1; note("r1", o); return d end),
  prog:install_write_tap(0x300000, 0x37ffff, "pn_w0", function(o, d, m)
    c.w0 = c.w0 + 1
    if (d & m & 0xf0f0) ~= 0 then c.hi0 = c.hi0 + 1; note("hi0", o) end
    return d
  end),
  prog:install_write_tap(0x380000, 0x39ffff, "pn_w1", function(o, d, m)
    c.w1 = c.w1 + 1
    if (d & m & 0xf0f0) ~= 0 then c.hi1 = c.hi1 + 1; note("hi1", o) end
    return d
  end),
}
local function field(name)
  for _, port in pairs(mach.ioport.ports) do
    local f = port.fields[name]
    if f then return f end
  end
end
local coin, start, sel = field("Coin 1"), field("1 Player Start"), field("P1 Select")
local n = 0
emu.register_frame_done(function()
  n = n + 1
  if COIN > 0 then
    coin:set_value((n >= COIN and n < COIN + 6) and 1 or 0)
    start:set_value((n >= COIN + 90 and n < COIN + 96) and 1 or 0)
    if n >= COIN + 96 then sel:set_value((n % 20) < 4 and 1 or 0) end
  end
  if n == FRAMES then
    local f = assert(io.open(OUT .. "/pixel_nibbles.txt", "w"))
    f:write(string.format("frames %d\nreads pixel0 %d pixel1 %d\nwrites pixel0 %d pixel1 %d\nhigh-nibble writes pixel0 %d pixel1 %d\n",
      n, c.r0, c.r1, c.w0, c.w1, c.hi0, c.hi1))
    for k, v in pairs(first) do f:write("first " .. k .. " " .. v .. "\n") end
    f:close()
    mach:exit()
  end
end)
