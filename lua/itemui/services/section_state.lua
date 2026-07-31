--[[
    Section state (windows pass §6): collapsibles remember open/closed per window,
    PER CHARACTER, and survive /lua restart and relogs.

    Storage: one tiny INI per character at Chars/<name>/sections.ini (the same
    per-character folder storage.lua uses), NOT inside itemui_layout.ini — the layout
    file is shared by every character on the install, and revert-to-default overwrites
    it wholesale (the same reason presets live in their own file; see layout_presets.lua
    header). Zero [Layout] loader sites are touched by this module.

    Format, deliberately one dynamic CSV key (the PinnedWindows precedent) instead of
    one key per section:

        [Sections]
        Collapsed=ItemDisplay.SpellData,Inventory.Filters

    Only DEVIATIONS from each section's declared default are stored — the CSV lists
    sections whose state differs from `defaultOpen`, so new sections adopt their
    default on old files and the file stays tiny.

    Char resolution is lazy (mq.TLO.Me.Name, the storage.lua pattern): before a name
    resolves, toggles are held in memory and flushed to disk once it does. Writes are
    write-through per toggle (a section click is rare and the file is 2 lines — same
    posture as the sort-click layout saves that already ship).
]]

local mq = require('mq')

local M = {}

local deps = nil          -- { getCharStoragePath(char, file), parseSectionsMatching(path, pat), safeWrite(path, content) }
local flipped = {}        -- ["Win.Section"] = true where state ~= declared default
local loadedFor = nil     -- char name the current `flipped` table came from (nil = not loaded)
local pendingDirty = false -- a toggle happened before the char name resolved

local FILE_NAME = "sections.ini"

local function charName()
    local ok, name = pcall(function()
        return mq.TLO and mq.TLO.Me and mq.TLO.Me.Name and mq.TLO.Me.Name()
    end)
    if ok and name and name ~= "" and name ~= "NULL" then return tostring(name) end
    return nil
end

local function keyOf(windowId, sectionId)
    return tostring(windowId) .. "." .. tostring(sectionId)
end

local function filePath(char)
    if not (deps and deps.getCharStoragePath) then return nil end
    local ok, path = pcall(deps.getCharStoragePath, char, FILE_NAME)
    if ok and path and path ~= "" then return path end
    return nil
end

local function loadFor(char)
    flipped = {}
    loadedFor = char
    local path = filePath(char)
    if not (path and deps and deps.parseSectionsMatching) then return end
    local ok, parsed = pcall(deps.parseSectionsMatching, path, "^Sections$")
    if not ok or type(parsed) ~= "table" then return end
    local kv = parsed.Sections or (parsed[1] and parsed[parsed[1]]) or nil
    -- parseSectionsMatching returns { [header] = {k=v}, order = {...} }; be liberal.
    if not kv then
        for header, t in pairs(parsed) do
            if header ~= "order" and type(t) == "table" then kv = t; break end
        end
    end
    local csv = kv and kv.Collapsed or nil
    if type(csv) ~= "string" or csv == "" then return end
    for entry in csv:gmatch("[^,]+") do
        local trimmed = entry:match("^%s*(.-)%s*$")
        if trimmed ~= "" then flipped[trimmed] = true end
    end
end

local function ensureLoaded()
    local char = charName()
    if char and loadedFor ~= char then
        local hadPending = pendingDirty and loadedFor == nil
        local pendingFlips = hadPending and flipped or nil
        loadFor(char)
        if pendingFlips then
            -- Toggles made before the name resolved win over the file's stale state.
            for k, v in pairs(pendingFlips) do flipped[k] = v or nil end
            M.flush()
        end
        pendingDirty = false
    end
end

function M.init(d)
    deps = d
    flipped = {}
    loadedFor = nil
    pendingDirty = false
end

--- Current open/closed for a section. `defaultOpen` is the section's declared default;
--- the store keeps only deviations from it.
function M.isOpen(windowId, sectionId, defaultOpen)
    ensureLoaded()
    if flipped[keyOf(windowId, sectionId)] then return not defaultOpen end
    return defaultOpen and true or false
end

--- Record a new state for a section (no-op when it already matches). Write-through.
function M.set(windowId, sectionId, defaultOpen, open)
    ensureLoaded()
    local k = keyOf(windowId, sectionId)
    local wantFlipped = (open and true or false) ~= (defaultOpen and true or false)
    local isFlipped = flipped[k] == true
    if wantFlipped == isFlipped then return end
    flipped[k] = wantFlipped or nil
    if loadedFor == nil then
        pendingDirty = true  -- held in memory; flushed when the char name resolves
        return
    end
    M.flush()
end

--- Serialize and write the per-char file. Safe to call with nothing loaded.
function M.flush()
    if loadedFor == nil then return false end
    local path = filePath(loadedFor)
    if not (path and deps and deps.safeWrite) then return false end
    local keys = {}
    for k in pairs(flipped) do keys[#keys + 1] = k end
    table.sort(keys)
    local content = "[Sections]\nCollapsed=" .. table.concat(keys, ",") .. "\n"
    local ok, wrote = pcall(deps.safeWrite, path, content)
    return (ok and wrote) and true or false
end

--- Test hook: forget everything (including the resolved char).
function M._resetForTests()
    flipped = {}
    loadedFor = nil
    pendingDirty = false
end

return M
