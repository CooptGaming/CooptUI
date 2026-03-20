--[[
    Sound Service — CoOpt UI audio notifications.
    Uses MQ2's /beep command: /beep alone = system beep; /beep sounds/file = plays .wav from EQ sounds folder.
    Per-event enable/disable + optional filename persisted in itemui_layout.ini [Sound] section.
    Mythical alert defaults to double-beep (two /beep via /timed for non-blocking spacing).
    Zero startup cost, zero dependencies beyond mq + config.
]]

local mq = require('mq')
local config = require('itemui.config')

local M = {}

local LAYOUT_INI = "itemui_layout.ini"
local SOUND_SECTION = "Sound"

-- beeps: how many beeps for default (no custom file). 1 = single, 2 = double with /timed spacing.
local EVENT_DEFS = {
    sell_complete   = { label = "Sell Complete",  desc = "Played when sell macro finishes",                      beeps = 1 },
    loot_rare       = { label = "Rare Loot",      desc = "Played per-item when a Legendary, Script, or Mythical item is looted", beeps = 1 },
    mythical_alert  = { label = "Mythical Alert", desc = "Played when a mythical item is detected on a corpse", beeps = 2 },
}

local settings = { enabled = true, events = {} }

function M.init()
    local v = config.readINIValue(LAYOUT_INI, SOUND_SECTION, "Enabled", "1")
    settings.enabled = (v == "1" or v == "true")
    for name, _ in pairs(EVENT_DEFS) do
        local en = config.readINIValue(LAYOUT_INI, SOUND_SECTION, name .. "_Enabled", "1")
        local fi = config.readINIValue(LAYOUT_INI, SOUND_SECTION, name .. "_File", "")
        settings.events[name] = {
            enabled = (en == "1" or en == "true"),
            file    = (fi ~= "") and fi or nil,
        }
    end
end

function M.save()
    config.writeINIValue(LAYOUT_INI, SOUND_SECTION, "Enabled", settings.enabled and "1" or "0")
    for name, ev in pairs(settings.events) do
        config.writeINIValue(LAYOUT_INI, SOUND_SECTION, name .. "_Enabled", ev.enabled and "1" or "0")
        config.writeINIValue(LAYOUT_INI, SOUND_SECTION, name .. "_File",    ev.file or "")
    end
end

--- Play a sound for the named event.
-- Custom file: /beep sounds/<filename>  (single play).
-- No custom file: /beep repeated per EVENT_DEFS.beeps (default 1; mythical = 2).
-- Second beep uses /timed 3 (0.3s delay) so it's non-blocking.
function M.play(eventName)
    if not settings.enabled then return end
    local ev = settings.events[eventName]
    if not ev or not ev.enabled then return end
    local def = EVENT_DEFS[eventName]
    if ev.file and ev.file ~= "" then
        -- Custom sound file from EQ sounds/ folder
        pcall(function() mq.cmdf("/beep sounds/%s", ev.file) end)
    else
        -- System beep (with optional double-beep for mythical)
        pcall(function() mq.cmd("/beep") end)
        if def and def.beeps and def.beeps > 1 then
            pcall(function() mq.cmd("/timed 3 /beep") end)
        end
    end
end

--- Check if a filename exists in the EQ sounds folder.
-- MQ2 sets the working directory to the EQ root, so "sounds/<file>" is a relative open.
-- Also tries EverQuest TLO path and MQ path as fallbacks.
-- Returns true if found, false if not found.
function M.fileExistsInSoundsDir(filename)
    if not filename or filename == "" then return true end  -- blank = beep, always valid
    -- Helper: try to open a file, with optional .wav extension
    local function tryOpen(base)
        local p = base .. filename
        local f = io.open(p, "rb")
        if f then f:close(); return true end
        if not filename:lower():match("%.wav$") then
            f = io.open(p .. ".wav", "rb")
            if f then f:close(); return true end
        end
        return false
    end
    -- 1) CWD-relative (MQ2 sets CWD to EQ root — most reliable)
    if tryOpen("sounds\\") then return true end
    if tryOpen("sounds/") then return true end
    -- 2) EverQuest TLO path (if available)
    pcall(function()
        local p = mq.TLO.EverQuest and mq.TLO.EverQuest.Path and mq.TLO.EverQuest.Path()
        if p and p ~= "" then
            local root = p:gsub("/", "\\"):gsub("\\+$", "")
            if tryOpen(root .. "\\sounds\\") then return true end
        end
    end)
    -- 3) MacroQuest path (walk up to find sounds/ directory)
    pcall(function()
        local p = mq.TLO.MacroQuest and mq.TLO.MacroQuest.Path and mq.TLO.MacroQuest.Path()
        if p and p ~= "" then
            local path = p:gsub("/", "\\"):gsub("\\+$", "")
            for _ = 1, 4 do
                if tryOpen(path .. "\\sounds\\") then return true end
                local parent = path:match("^(.+)\\[^\\]+$")
                if not parent or parent == path then break end
                path = parent
            end
        end
    end)
    return false
end

function M.isEnabled()         return settings.enabled end
function M.setEnabled(v)       settings.enabled = v; M.save() end
function M.getEventSettings(n) return settings.events[n] end
function M.getEventDefs()      return EVENT_DEFS end

function M.setEventEnabled(eventName, v)
    if not settings.events[eventName] then settings.events[eventName] = { enabled = true, file = nil } end
    settings.events[eventName].enabled = v; M.save()
end

function M.setEventFile(eventName, file)
    if not settings.events[eventName] then settings.events[eventName] = { enabled = true, file = nil } end
    settings.events[eventName].file = (file and file ~= "") and file or nil; M.save()
end

return M
