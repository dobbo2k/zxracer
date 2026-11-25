-- Headless test runner for the Amstrad CPC port (tools/cpc_harness.py), from
-- the Wonder Boy port's. Reads commands.txt in the folder CPC_RUN names, one
-- command a line, and runs them frame by frame in MAME cpc6128; writes
-- results.txt there ("name=value" lines). Commands:
--   frames N            run N frames
--   hold K1,K2          keys held from now: letters, digits, SPACE, ENTER,
--                       UP/DOWN/LEFT/RIGHT (cursor keys), JOY_UP/DOWN/LEFT/RIGHT,
--                       JOY_FIRE1, JOY_FIRE2, KP_ENTER
--   release             no keys held
--   peek8 NAME ADDR     results NAME=byte at ADDR (as mapped now)
--   peek16 NAME ADDR    results NAME=word
--   peekn NAME ADDR N   results NAME=hex bytes
--   reg NAME REG        results NAME=a Z80 register (PC, SP, AF ...)
--   frame NAME          results NAME=frames run since the machine started
--   poke8 ADDR V        write a byte
--   poke16 ADDR V       write a word
--   shot                a screenshot (into the snapshot directory)
--   until ADDR V N      run until the byte at ADDR is V, N frames at most
--   untilw ADDR V N     run until the word at ADDR is V or more, N frames at most
--   disk eject|insert   the first drive's disc out, or the one ejected back in
--   ram V               the Gate Array's RAM configuration set to V ($C0-$C7)
--   ay on|NAME          from "on" (as the machine starts, if the first command):
--                       each AY register write (through the PPI) as
--                       frame.register.value; "ay NAME": results NAME=those
--   watch ADDR          from now, the byte at ADDR at each frame's end, as
--                       "frame:value" (frames from the machine's start)
--   watched NAME        results NAME=those, comma-separated
--   save NAME           a MAME state (in -state_directory)
--   load NAME           a MAME state loaded (MAME's -state hangs here)
--   debug COMMAND...    a MAME debugger command (run MAME with -debug)
--   quit
local commands, index, wait = {}, 1, 0
local wait_byte = nil      -- {address, value, frames left}
local wait_word = nil      -- {address, value, frames left}
local ejected = nil        -- the disk taken out (disk eject)
local watch_address, watched, frame_no = nil, {}, 0
local folder = os.getenv("CPC_RUN") or "build/cpc/run"
local results = assert(io.open(folder .. "/results.txt", "w"))
for line in io.lines(folder .. "/commands.txt") do
    local words = {}
    for word in string.gmatch(line, "%S+") do words[#words + 1] = word end
    if #words > 0 then commands[#commands + 1] = words end
end
local SPECIAL = {["↑"] = "UP", ["↓"] = "DOWN", ["←"] = "LEFT", ["→"] = "RIGHT",
                 ["P1 Up"] = "JOY_UP", ["P1 Down"] = "JOY_DOWN", ["P1 Left"] = "JOY_LEFT",
                 ["P1 Right"] = "JOY_RIGHT", ["P1 Button 1"] = "JOY_FIRE1", ["P1 Button 2"] = "JOY_FIRE2",
                 ["Keypad Enter"] = "KP_ENTER"}
local keys = {}           -- name -> ioport field
local function find_keys()
    for tag, port in pairs(manager.machine.ioport.ports) do
        if string.match(tag, "kbrow%.%d$") then
            for name, field in pairs(port.fields) do
                if SPECIAL[name] then keys[SPECIAL[name]] = field
                else
                    local first = string.match(name, "^(%S+)")
                    if first then keys[string.upper(first)] = field end
                end
            end
        end
    end
end
local held = {}
local ay_tap, ay_lines, ay_latch, ay_register, ay_frame = nil, {}, 0, 0, 0
local function watch_ay()
    local io = manager.machine.devices[":maincpu"].spaces["io"]
    if ay_tap then ay_tap:remove() end
    ay_tap = io:install_write_tap(0x0000, 0xFFFF, "ay", function(offset, data, mask)
        local high = offset >> 8
        if high == 0xF4 then ay_latch = data                    -- PPI port A: the AY's bus
        elseif high == 0xF6 then                                 -- PPI port C: its function
            local f = data & 0xC0
            if f == 0xC0 then ay_register = ay_latch
            elseif f == 0x80 then
                ay_lines[#ay_lines + 1] = string.format("%d.%d.%d", ay_frame, ay_register, ay_latch)
            end
        end
    end)
end
local function hold(list)
    for _, field in pairs(held) do field:clear_value() end
    held = {}
    for name in string.gmatch(list or "", "[^,]+") do
        local field = keys[string.upper(name)]
        if field then field:set_value(1); held[#held + 1] = field
        else results:write("error=unknown key " .. name .. "\n") end
    end
end
if commands[1] and commands[1][1] == "ay" and commands[1][2] == "on" then
    watch_ay()                -- before the machine's first instruction
    index = 2
end
local function number(text) return math.tointeger(tonumber(text)) end
emu.register_frame_done(function()
    if next(keys) == nil then find_keys() end
    if ay_tap then ay_frame = ay_frame + 1 end
    frame_no = frame_no + 1
    if watch_address then
        local sp = manager.machine.devices[":maincpu"].spaces["program"]
        watched[#watched + 1] = frame_no .. ":" .. sp:read_u8(watch_address)
    end
    if wait > 0 then wait = wait - 1; return end
    local space = manager.machine.devices[":maincpu"].spaces["program"]
    if wait_byte then
        if space:read_u8(wait_byte[1]) ~= wait_byte[2] and wait_byte[3] > 0 then wait_byte[3] = wait_byte[3] - 1; return end
        wait_byte = nil
    end
    if wait_word then
        local a = wait_word[1]
        if (space:read_u8(a) | (space:read_u8(a + 1) << 8)) < wait_word[2] and wait_word[3] > 0 then
            wait_word[3] = wait_word[3] - 1; return
        end
        wait_word = nil
    end
    while index <= #commands do
        local c = commands[index]
        index = index + 1
        local op = c[1]
        if op == "frames" then wait = number(c[2]) - 1; return
        elseif op == "until" then wait_byte = {number(c[2]), number(c[3]), number(c[4])}; return
        elseif op == "untilw" then wait_word = {number(c[2]), number(c[3]), number(c[4])}; return
        elseif op == "hold" then hold(c[2])
        elseif op == "release" then hold(nil)
        elseif op == "peek8" then results:write(string.format("%s=%d\n", c[2], space:read_u8(number(c[3]))))
        elseif op == "peek16" then
            local a = number(c[3])
            results:write(string.format("%s=%d\n", c[2], space:read_u8(a) | (space:read_u8(a + 1) << 8)))
        elseif op == "peekn" then
            local a, t = number(c[3]), {}
            for k = 0, number(c[4]) - 1 do t[#t + 1] = string.format("%02X", space:read_u8(a + k)) end
            results:write(string.format("%s=%s\n", c[2], table.concat(t)))
        elseif op == "frame" then results:write(string.format("%s=%d\n", c[2], frame_no))
        elseif op == "reg" then                                 -- reg NAME REGISTER: results NAME=its value
            results:write(string.format("%s=%d\n", c[2], manager.machine.devices[":maincpu"].state[c[3]].value))
        elseif op == "poke8" then space:write_u8(number(c[2]), number(c[3]))
        elseif op == "poke16" then
            local a, v = number(c[2]), number(c[3])
            space:write_u8(a, v & 0xFF); space:write_u8(a + 1, v >> 8)
        elseif op == "shot" then manager.machine.video:snapshot()
        elseif op == "ay" then
            if c[2] == "on" then watch_ay()
            else results:write(string.format("%s=%s\n", c[2], table.concat(ay_lines, ","))) end
        elseif op == "ram" then
            manager.machine.devices[":maincpu"].spaces["io"]:write_u8(0x7F00, number(c[2]))
        elseif op == "disk" then
            local drive
            for _, device in pairs(manager.machine.images) do
                if device.instance_name == "floppydisk1" or (not drive and device.instance_name == "floppydisk") then
                    drive = device
                end
            end
            if c[2] == "eject" then ejected = drive.filename; drive:unload()
            elseif c[2] == "insert" then drive:load(ejected) end
        elseif op == "watch" then watch_address = number(c[2])
        elseif op == "watched" then results:write(string.format("%s=%s\n", c[2], table.concat(watched, ",")))
        elseif op == "load" then manager.machine:load(c[2])   -- a MAME state, from the next frame
        elseif op == "save" then manager.machine:save(c[2])
        elseif op == "mark" then                                -- NAME=the screen's frame number (to cut a recording at)
            results:write(string.format("%s=%d\n", c[2], manager.machine.screens:at(1):frame_number()))
        elseif op == "debug" then
            manager.machine.debugger:command(table.concat(c, " ", 2))
        elseif op == "quit" then break
        end
    end
    results:close()
    manager.machine:exit()
end, "frame")
