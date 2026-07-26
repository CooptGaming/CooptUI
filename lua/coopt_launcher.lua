--[[ coopt_launcher.lua - tiny always-on watcher for the native Command Center.

The Command Center (the coopt skin's repurposed Tip of the Day window) has
Start/Stop buttons that must work when itemui is NOT running - so this
minimal script owns them, and nothing else. itemui starts this launcher
automatically; to have the Command Center ready at login before ever
starting CoOpt, add to your MacroQuest autoexec:  /lua run coopt_launcher

Behavior:
  - On startup, opens the Command Center window once (if the coopt skin is
    loaded; otherwise silently does nothing until it is).
  - Start CoOpt  -> /lua run itemui + /lua run scripttracker
  - Stop CoOpt   -> /lua stop scripttracker + /lua stop itemui
  - Writes the status line only while itemui is stopped (the itemui bridge
    owns it while running).

Buttons are Style_Checkbox: a click toggles Checked; any transition is one
click. The cosmetic un-latch only fires while the cursor is off the button
(sending it mid-click wedges EQ's mouse capture).
]]

local mq = require('mq')

local WND    = 'TipWindow'
local START  = 'Coopt_CCStartBtn'
local STOP   = 'Coopt_CCStopBtn'
local STATUS = 'Coopt_CCStatus'

local btnLast = {}
local lastStatusText = nil
local openTriedAt = nil

-- MQ2CoOptUI window API when present: direct SetCheck un-latch (state write,
-- no synthetic click, no capture involvement). One-shot detection; the
-- MouseOver-gated /notify path below stays as the pluginless fallback.
local plugWin = nil
do
    local ok, mod = pcall(require, 'plugin.MQ2CoOptUI')
    if ok and type(mod) == 'table' and type(mod.window) == 'table'
        and type(mod.window.setChecked) == 'function' then
        plugWin = mod.window
    end
end

local function child(name)
    local w = mq.TLO and mq.TLO.Window and mq.TLO.Window(WND)
    if not w or w() == nil then return nil end
    return w.Child and w.Child(name) or nil
end

local function readChecked(name)
    local c = child(name)
    if not c then return nil end
    local ok, v = pcall(function() return c.Checked() end)
    if not ok or type(v) ~= 'boolean' then return nil end
    return v
end

-- Same guards the itemui native_bridge uses (they are load-bearing there):
-- un-latch only after the click has settled, and swallow the echo of our own
-- synthetic /notify toggle if it lands after the next poll.
local UNLATCH_SETTLE_MS = 350
local UNLATCH_ECHO_MS = 1000
local clickAt = {}    -- [name] = ms of the last accepted click
local echoUntil = {}  -- [name] = ignore transitions until this ms (/notify echo)

-- One click = one Checked transition (either direction).
local function clicked(name, now)
    local v = readChecked(name)
    if v == nil then return false end
    local last = btnLast[name]
    btnLast[name] = v
    if last == nil then return false end
    if v == last then return false end
    if echoUntil[name] and now < echoUntil[name] then return false end
    clickAt[name] = now
    return true
end

-- Pop a latched button back out, only after the settle delay AND while the
-- cursor is off it — touching bChecked inside the click window makes the
-- release re-toggle it (phantom second click: a spurious Start, or worse, a
-- spurious Stop). The plugin only upgrades the mechanism: silent state write
-- instead of a synthetic click.
local function unlatch(name, now)
    if (now - (clickAt[name] or 0)) < UNLATCH_SETTLE_MS then return end
    local c = child(name)
    if not c then return end
    local okc, v = pcall(function() return c.Checked() end)
    if not okc or v ~= true then return end
    local oko, over = pcall(function() return c.MouseOver() end)
    if oko and over == false then
        if plugWin then
            if plugWin.setChecked(WND, name, false) then
                btnLast[name] = false -- state write; nothing echoes back
            end
        else
            mq.cmdf('/notify %s %s leftmouseup', WND, name)
            btnLast[name] = false -- swallow our own synthetic toggle
            echoUntil[name] = now + UNLATCH_ECHO_MS -- ...even if it lands after the next poll
        end
    end
end

local function luaRunning(script)
    local ok, status = pcall(function()
        local l = mq.TLO and mq.TLO.Lua
        local s = l and l.Script and l.Script(script)
        return s and s.Status and s.Status()
    end)
    if ok and type(status) == 'string' then return status:upper() == 'RUNNING' end
    return nil
end

local function setStatus(text)
    if text == lastStatusText then return end
    local c = child(STATUS)
    if not c then return end
    local ok = pcall(function() c.SetText(text)() end)
    if ok then lastStatusText = text end
end

local function windowOpen()
    local w = mq.TLO and mq.TLO.Window and mq.TLO.Window(WND)
    return (w and w() ~= nil and w.Open and w.Open()) or false
end

print('\ay[CoOpt Launcher]\ax Watching the Command Center Start/Stop buttons. (/lua stop coopt_launcher to end)')

while true do
    -- Open the Command Center once per session, as soon as the coopt skin's
    -- controls exist (children are addressable even while the window is closed).
    if not openTriedAt and readChecked(START) ~= nil then
        openTriedAt = mq.gettime()
        if not windowOpen() then
            pcall(function() mq.TLO.Window(WND).DoOpen() end)
        end
    end

    if windowOpen() then
        local now = mq.gettime()
        if clicked(START, now) then
            local itemuiUp = luaRunning('itemui')
            if itemuiUp ~= true then mq.cmd('/lua run itemui') end
            if luaRunning('scripttracker') ~= true then mq.cmd('/lua run scripttracker') end
            setStatus('Starting CoOpt...')
        end
        if clicked(STOP, now) then
            if luaRunning('scripttracker') == true then mq.cmd('/lua stop scripttracker') end
            if luaRunning('itemui') == true then mq.cmd('/lua stop itemui') end
            setStatus('CoOpt stopped - press Start')
        end
        unlatch(START, now)
        unlatch(STOP, now)
        -- Own the status line only while itemui is down.
        if luaRunning('itemui') == false then
            setStatus('CoOpt stopped - press Start')
        else
            lastStatusText = nil -- bridge owns it; forget our cache
        end
    end

    mq.delay(250)
end
