--[[
    layout_presets.lua — named window arrangements in their own file, itemui_presets.ini.
    Mockup 10c; spec §5/§8 phase 4.

    A preset is "which windows are open, in which zone, at what size" (mockup 10c). One
    [Preset:<name>] section each. The file is SEPARATE from itemui_layout.ini on purpose:
    "Revert to Default Layout" overwrites the whole layout file (default_layout.lua:107-126
    safeWrites the bundled copy over it), so presets stored there would be deleted — that is
    SPEC_CORRECTIONS §1.4, and it is why parseSectionsMatching lives in layout_io rather
    than the fixed-section layout parser.

    Section shape (geometry keys are the views' own layoutConfig keys, verbatim):
        [Preset:Bag session]
        Open=hub,bank,itemDisplay
        ZoneAssign=
        WindowAttach=
        BankWindowX=1364
        ...

    Bundled presets carry NO geometry — they only name windows, so the zone placer lays
    them out fresh for whatever resolution the client is running. A user "Save current
    as..." captures live geometry and reproduces it exactly.

    Pure parse/serialize is exposed separately from disk I/O so the headless tests can
    round-trip strings without touching files.
]]

local config = require('itemui.config')
local file_safe = require('itemui.utils.file_safe')
local layoutIO = require('itemui.utils.layout_io')
local registry = require('itemui.core.registry')
local windowZones = require('itemui.services.window_zones')

local M = {}

local d                       -- main-loop deps table (init)

M.PRESETS_INI = "itemui_presets.ini"
local SECTION_PATTERN = "^Preset:"    -- Lua pattern for parseSectionsMatching

-- The five bundled presets (mockup 10c, verbatim names). Open lists use registry ids plus
-- the two pseudo-ids "hub" and "loot".
M.BUNDLED = {
    { name = "Bag session",    open = { "hub", "bank", "itemDisplay" } },
    { name = "Farming",        open = {} },                                   -- dock only; loot panel opens itself on a run
    { name = "Merchant run",   open = { "hub", "bank" } },
    { name = "Gearing up",     open = { "equipment", "itemDisplay", "augmentUtility" } },
    { name = "Raid - minimal", open = {} },
}

function M.init(deps)
    d = deps
end

function M.getPresetsFilePath()
    return config.getConfigFile(M.PRESETS_INI)
end

-- ---------------------------------------------------------------------------
-- Pure: section table <-> preset data
-- ---------------------------------------------------------------------------

--- kv section -> preset data { open = {ids}, zoneAssign = str|nil, windowAttach = str|nil,
--- geometry = { LayoutKey = number } }.
function M.fromSection(kv)
    local data = { open = {}, geometry = {} }
    for _, id in ipairs((function(s)
        local out = {}
        for part in tostring(s or ""):gmatch("[^,]+") do
            local t = part:match("^%s*(.-)%s*$")
            if t ~= "" then out[#out + 1] = t end
        end
        return out
    end)(kv.Open)) do
        data.open[#data.open + 1] = id
    end
    if kv.ZoneAssign and kv.ZoneAssign ~= "" then data.zoneAssign = kv.ZoneAssign end
    if kv.WindowAttach and kv.WindowAttach ~= "" then data.windowAttach = kv.WindowAttach end
    for k, v in pairs(kv) do
        if k ~= "Open" and k ~= "ZoneAssign" and k ~= "WindowAttach" then
            local n = tonumber(v)
            if n then data.geometry[k] = n end
        end
    end
    return data
end

--- preset data -> INI lines (no section header). Deterministic order for stable diffs.
function M.toLines(data)
    local lines = {}
    lines[#lines + 1] = "Open=" .. table.concat(data.open or {}, ",")
    lines[#lines + 1] = "ZoneAssign=" .. tostring(data.zoneAssign or "")
    lines[#lines + 1] = "WindowAttach=" .. tostring(data.windowAttach or "")
    local keys = {}
    for k in pairs(data.geometry or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        lines[#lines + 1] = k .. "=" .. tostring(data.geometry[k])
    end
    return lines
end

--- Full-file serialize from an ordered { {name=, data=}, ... } list.
function M.serializeAll(list)
    local out = { "; CoOpt UI layout presets. One [Preset:<name>] section per preset.",
                  "; Kept out of itemui_layout.ini so Revert to Default Layout never touches it." }
    for _, p in ipairs(list) do
        out[#out + 1] = ""
        out[#out + 1] = "[Preset:" .. p.name .. "]"
        for _, line in ipairs(M.toLines(p.data)) do out[#out + 1] = line end
    end
    return table.concat(out, "\n") .. "\n"
end

-- ---------------------------------------------------------------------------
-- Disk
-- ---------------------------------------------------------------------------

--- Ordered { {name=, data=}, ... } from disk. Missing file -> {}.
function M.readAll()
    local path = M.getPresetsFilePath()
    if not path then return {} end
    local sections, order = layoutIO.parseSectionsMatching(path, SECTION_PATTERN)
    local out = {}
    for _, header in ipairs(order) do
        local name = header:match("^Preset:(.+)$")
        if name and name ~= "" then
            out[#out + 1] = { name = name, data = M.fromSection(sections[header]) }
        end
    end
    return out
end

local function writeAll(list)
    local path = M.getPresetsFilePath()
    if not path then return false end
    return file_safe.safeWrite(path, M.serializeAll(list)) and true or false
end

--- Seed the bundled five when the presets file does not exist. Never touches an existing
--- file — a user who deleted a bundled preset meant it, and a file that exists but cannot
--- be READ right now (lock, transient I/O error) must not be mistaken for empty and
--- overwritten: existence is probed directly, not inferred from a parse result.
function M.seedIfMissing()
    local path = M.getPresetsFilePath()
    if not path then return false end
    local fh = io.open(path, "r")
    if fh then fh:close(); return false end
    local existing = M.readAll()
    if #existing > 0 then return false end
    local list = {}
    for _, b in ipairs(M.BUNDLED) do
        list[#list + 1] = { name = b.name, data = { open = b.open, geometry = {} } }
    end
    return writeAll(list)
end

function M.list()
    local names = {}
    for _, p in ipairs(M.readAll()) do names[#names + 1] = p.name end
    return names
end

function M.get(name)
    for _, p in ipairs(M.readAll()) do
        if p.name == name then return p.data end
    end
    return nil
end

function M.delete(name)
    local list = M.readAll()
    local kept, removed = {}, false
    for _, p in ipairs(list) do
        if p.name == name then removed = true else kept[#kept + 1] = p end
    end
    if removed then writeAll(kept) end
    return removed
end

--- Capture the live arrangement under a name (mockup 10c "Save current as...").
function M.saveCurrent(name)
    name = tostring(name or ""):match("^%s*(.-)%s*$")
    if name == "" or name:find("[%[%]:]") then return false end   -- section-header-safe names only
    local lc = d and d.layoutConfig
    if not lc then return false end
    local data = { open = {}, geometry = {} }
    if d.getShouldDraw and d.getShouldDraw() then data.open[#data.open + 1] = "hub" end
    for id in pairs(windowZones.GEOM) do
        local open = (id == "loot") and (d.uiState and d.uiState.lootUIOpen == true) or registry.isOpen(id)
        if open then
            data.open[#data.open + 1] = id
            local g = windowZones.GEOM[id]
            for _, key in pairs({ g.x, g.y, g.w, g.h }) do
                if key and tonumber(lc[key]) then data.geometry[key] = tonumber(lc[key]) end
            end
        end
    end
    table.sort(data.open)
    if lc.ZoneAssign and lc.ZoneAssign ~= "" then data.zoneAssign = lc.ZoneAssign end
    if lc.WindowAttach and lc.WindowAttach ~= "" then data.windowAttach = lc.WindowAttach end
    local list = M.readAll()
    local replaced = false
    for _, p in ipairs(list) do
        if p.name == name then p.data = data; replaced = true; break end
    end
    if not replaced then list[#list + 1] = { name = name, data = data } end
    if not writeAll(list) then return false end
    if d.setLayoutValue then d.setLayoutValue("LayoutPreset", name)
    else lc.LayoutPreset = name; if d.scheduleLayoutSave then d.scheduleLayoutSave() end end
    return true
end

-- ---------------------------------------------------------------------------
-- Apply
-- ---------------------------------------------------------------------------

local function wantOpen(data, id)
    for _, oid in ipairs(data.open or {}) do
        if oid == id then return true end
    end
    return false
end

--- Switch to a named preset: close what is not in it (pinned windows stay — a pin is the
--- user saying "leave this alone"), open what is, install its zones/attachments/geometry,
--- then let the zone placer flow anything the preset did not position. Runs from the
--- main-loop action drain, never from inside a frame.
function M.apply(name)
    local data = M.get(name)
    local lc = d and d.layoutConfig
    if not data or not lc then return false end

    -- Close pass (registry windows + loot). The hub follows below.
    for id in pairs(windowZones.GEOM) do
        if not wantOpen(data, id) then
            if id == "loot" then
                if d.uiState then d.uiState.lootUIOpen = false end
            elseif registry.isOpen(id) and not (registry.isPinned and registry.isPinned(id)) then
                registry.setWindowState(id, false, false)
            end
        end
    end
    if d.setShouldDraw and d.setOpen then
        local hubWanted = wantOpen(data, "hub")
        d.setShouldDraw(hubWanted)
        d.setOpen(hubWanted)
    end

    -- Keys before opening, so placement on the open edge sees the preset's zones.
    lc.ZoneAssign = data.zoneAssign or ""
    lc.WindowAttach = data.windowAttach or ""
    lc.UserPlaced = ""                      -- an arrangement change unpins earlier drags
    -- Immediate re-sync: placeMissing below consults window_zones' in-memory sets, which
    -- otherwise refresh only on its next tick — a stale user-placed flag would strand a
    -- geometry-wiped window on the (0,0) sentinel.
    windowZones.syncFromConfigNow()
    for k, v in pairs(data.geometry) do lc[k] = v end

    -- Open pass. Windows the preset gives no geometry get their position wiped so
    -- placeMissing flows them into their zones fresh.
    for _, id in ipairs(data.open or {}) do
        if id ~= "hub" then
            local g = windowZones.GEOM[id]
            if g and not data.geometry[g.x] then lc[g.x], lc[g.y] = 0, 0 end
            if id == "loot" then
                if d.uiState then d.uiState.lootUIOpen = true end
            elseif registry.isRegistered and registry.isRegistered(id) then
                registry.setWindowState(id, true, true)
                if d.recordCompanionWindowOpened then d.recordCompanionWindowOpened(id) end
            end
        end
    end
    windowZones.placeMissing()
    -- Adopt the new open set NOW: windowZones.tick runs later in this same main-loop pass,
    -- and without this its open-edge detection would re-zone every window this preset just
    -- opened — discarding the exact geometry "Save current as..." captured.
    windowZones.markOpenSetCurrent()

    if d.setLayoutValue then d.setLayoutValue("LayoutPreset", name)
    else lc.LayoutPreset = name; if d.scheduleLayoutSave then d.scheduleLayoutSave() end end
    if d.uiState then
        local have = tonumber(d.uiState.layoutRevertedApplyFrames) or 0
        d.uiState.layoutRevertedApplyFrames = math.max(have, 3)
    end
    if d.setStatusMessage then d.setStatusMessage("Layout preset: " .. name) end
    return true
end

return M
