--[[
    Reroll Service — Server reroll list state and chat parsing.
    Integrates with the server's Reroll System: !auglist / !mythicallist return item lists
    that we parse from chat. Uses mq.event (same pattern as ScriptTracker) so doevents()
    in main_loop processes responses.
    Supports server format: "id=92314  name=Blessed Sleeve Symbol of Terror" and optional
    header "===== Aug List =====" / "===== Mythical List =====" to auto-detect list type.
    Cache persists across UI reloads via char-specific reroll_lists.lua (same pattern as storage).
    Large lists: we append line-by-line; cap at MAX_LIST_ENTRIES per list to avoid UI freeze.
]]

local mq = require('mq')
local constants = require('itemui.constants')

local REROLL = constants.REROLL or {}
local LIST_PARSE_MS = REROLL.LIST_RESPONSE_PARSE_MS or 3000
-- Cap per-list size so very large server responses don't cause buffer/UI issues (chunked parsing already line-by-line).
local MAX_LIST_ENTRIES = 2000

local augList = {}       -- { { id = number, name = string }, ... }
local mythicalList = {}  -- { { id = number, name = string }, ... }
local pendingAugListAt = nil      -- mq.gettime() when we sent !auglist; accept lines until this + LIST_PARSE_MS
local pendingMythicalListAt = nil  -- same for !mythicallist
local setStatusMessageFn = function() end
local getRerollListStoragePathFn = nil  -- optional: function() return path end for persistence
-- When adding via pickup flow: after we send !augadd/!mythicaladd, we wait for a list line containing this id then call callback (put back, update UI).
local pendingAddAckId = nil
local pendingAddAckCallback = nil

-- Parse server line: "id=92314  name=Blessed Sleeve Symbol of Terror". Returns id, name or nil.
local function parseIdNameLine(line)
    if not line or type(line) ~= "string" then return nil, nil end
    local idStr, name = line:match("id=(%d+)%s+name=(.+)")
    if not idStr or idStr == "" then return nil, nil end
    local id = tonumber(idStr)
    if not id or id < 0 then return nil, nil end
    name = (name and name:match("^%s*(.-)%s*$")) or ""
    return id, name
end

-- Legacy: "12345: Item Name" or "12345 - Item Name"
local function parseColonDashLine(line)
    if not line or type(line) ~= "string" then return nil, nil end
    local idStr, name = line:match("(%d+)%s*[%-:]%s*(.*)")
    if not idStr or idStr == "" then return nil, nil end
    local id = tonumber(idStr)
    if not id or id < 0 then return nil, nil end
    name = (name and name:match("^%s*(.-)%s*$")) or ""
    return id, name
end

local function parseListLine(line)
    local id, name = parseIdNameLine(line)
    if id then return id, name end
    return parseColonDashLine(line)
end

-- Detect header to know which list we're filling (optional; we also use pending* from Refresh).
local function detectListHeader(line)
    if not line or type(line) ~= "string" then return nil end
    local lower = line:lower()
    if lower:find("aug") and lower:find("list") then return "aug" end
    if lower:find("mythical") and lower:find("list") then return "mythical" end
    return nil
end

-- Persist cache to char storage (same path pattern as inventory.lua / bank.lua).
local function saveToFile()
    if not getRerollListStoragePathFn then return end
    local path = getRerollListStoragePathFn()
    if not path or path == "" then return end
    local ok, err = pcall(function()
        local lines = { "-- CoOpt UI Reroll list cache. Do not edit manually.", "return {" }
        lines[#lines + 1] = "  aug = {"
        for _, e in ipairs(augList) do
            lines[#lines + 1] = string.format("    { id = %s, name = %q },", tostring(e.id), e.name or "")
        end
        lines[#lines + 1] = "  },"
        lines[#lines + 1] = "  mythical = {"
        for _, e in ipairs(mythicalList) do
            lines[#lines + 1] = string.format("    { id = %s, name = %q },", tostring(e.id), e.name or "")
        end
        lines[#lines + 1] = "  }"
        lines[#lines + 1] = "}"
        local f = io.open(path, "w")
        if f then f:write(table.concat(lines, "\n")); f:close() end
    end)
    if not ok and setStatusMessageFn then setStatusMessageFn("Could not save reroll list cache") end
end

-- Load cache from char storage on init so lists persist across UI reloads.
local function loadFromFile()
    if not getRerollListStoragePathFn then return end
    local path = getRerollListStoragePathFn()
    if not path or path == "" then return end
    local ok, data = pcall(function()
        local f = io.open(path, "r")
        if not f then return nil end
        local content = f:read("*a")
        f:close()
        if not content or content == "" then return nil end
        local fn, err = load(content, path, "t", {})
        if not fn then return nil end
        return fn()
    end)
    if ok and data and type(data) == "table" then
        if type(data.aug) == "table" then augList = data.aug end
        if type(data.mythical) == "table" then mythicalList = data.mythical end
    end
end

-- Chat event callback: when server echoes a list line or header, parse and add to the appropriate list.
-- Large-list handling: append line-by-line (no single huge string); cap at MAX_LIST_ENTRIES per list.
local function onRerollListLine(line)
    local now = mq.gettime()
    local header = detectListHeader(line)
    if header == "aug" then
        augList = {}
        pendingAugListAt = now
        pendingMythicalListAt = nil
        return
    end
    if header == "mythical" then
        mythicalList = {}
        pendingMythicalListAt = now
        pendingAugListAt = nil
        return
    end
    -- Skip "Total: N" and similar
    if line:match("^%s*[Tt]otal") then return end
    local id, name = parseListLine(line)
    if not id then return end
    -- If we're waiting for this id as add-ack (pickup→add→put-back flow), notify and clear.
    if pendingAddAckId and id == pendingAddAckId and pendingAddAckCallback then
        pendingAddAckCallback()
        pendingAddAckId = nil
        pendingAddAckCallback = nil
    end
    local entry = { id = id, name = name }
    if pendingAugListAt and (now - pendingAugListAt) < LIST_PARSE_MS then
        if #augList < MAX_LIST_ENTRIES then table.insert(augList, entry) end
    elseif pendingMythicalListAt and (now - pendingMythicalListAt) < LIST_PARSE_MS then
        if #mythicalList < MAX_LIST_ENTRIES then table.insert(mythicalList, entry) end
    end
    saveToFile()
end

local M = {}

function M.init(deps)
    setStatusMessageFn = deps.setStatusMessage or function() end
    getRerollListStoragePathFn = deps.getRerollListStoragePath
    augList = {}
    mythicalList = {}
    pendingAugListAt = nil
    pendingMythicalListAt = nil
    pendingAddAckId = nil
    pendingAddAckCallback = nil
    loadFromFile()
    -- User can Refresh in Reroll Companion to request !auglist/!mythicallist; requesting both on init could mix responses.
    -- Match server list lines: "id=123 name=..." or "123: Name" or "123 - Name". Header "===== Aug List =====" also matched.
    mq.event("ItemUIRerollListLine", "#*#id=#*#name=#*#", onRerollListLine)
    mq.event("ItemUIRerollListLineColon", "#*#:#*#", onRerollListLine)
    mq.event("ItemUIRerollListLineDash", "#*#-#*#", onRerollListLine)
    mq.event("ItemUIRerollListHeader", "#*#=#*#List#*#", onRerollListLine)
end

function M.getAugList()
    return augList
end

function M.getMythicalList()
    return mythicalList
end

--- Request server to return augment list; clears current list and sets pending so chat lines are parsed.
function M.requestAugList()
    augList = {}
    pendingAugListAt = mq.gettime()
    pendingMythicalListAt = nil
    mq.cmd("/say " .. (REROLL.COMMAND_AUG_LIST or "!auglist"))
    setStatusMessageFn("Requesting augment list...")
end

--- Request server to return mythical list.
function M.requestMythicalList()
    mythicalList = {}
    pendingMythicalListAt = mq.gettime()
    pendingAugListAt = nil
    mq.cmd("/say " .. (REROLL.COMMAND_MYTHICAL_LIST or "!mythicallist"))
    setStatusMessageFn("Requesting mythical list...")
end

--- Return protection sets for sell/loot rules: items in these sets must never be sold and should be skipped by loot.
--- Used by sell_status and rules to integrate Reroll List protection.
function M.getRerollListProtection()
    local idSet = {}
    local nameSet = {}
    for _, e in ipairs(augList) do
        if e.id then idSet[e.id] = true end
        if e.name and e.name ~= "" then nameSet[(e.name):match("^%s*(.-)%s*$")] = true end
    end
    for _, e in ipairs(mythicalList) do
        if e.id then idSet[e.id] = true end
        if e.name and e.name ~= "" then nameSet[(e.name):match("^%s*(.-)%s*$")] = true end
    end
    return { idSet = idSet, nameSet = nameSet }
end

--- Register callback for add-ack: when a list line with this id is parsed, callback is invoked (put back, update UI).
function M.setPendingAddAck(itemId, callback)
    pendingAddAckId = itemId
    pendingAddAckCallback = callback
end

--- Clear add-ack wait (e.g. on timeout).
function M.clearPendingAddAck()
    pendingAddAckId = nil
    pendingAddAckCallback = nil
end

--- Optimistically add one entry to in-memory list and persist (for add-from-cursor flow before server echo).
function M.addEntryToList(listKind, id, name)
    local entry = { id = id, name = name or "" }
    if listKind == "aug" then
        for _, e in ipairs(augList) do if e.id == id then return end end
        if #augList < MAX_LIST_ENTRIES then table.insert(augList, entry); saveToFile() end
    elseif listKind == "mythical" then
        for _, e in ipairs(mythicalList) do if e.id == id then return end end
        if #mythicalList < MAX_LIST_ENTRIES then table.insert(mythicalList, entry); saveToFile() end
    end
end

--- Add item on cursor to augment reroll list. Call when cursor has an augment.
function M.addAugFromCursor()
    mq.cmd("/say " .. (REROLL.COMMAND_AUG_ADD or "!augadd"))
    setStatusMessageFn("Added from cursor to augment list; refresh to see.")
    M.requestAugList()
end

--- Add item on cursor to mythical reroll list. Call when cursor has a mythical item.
function M.addMythicalFromCursor()
    mq.cmd("/say " .. (REROLL.COMMAND_MYTHICAL_ADD or "!mythicaladd"))
    setStatusMessageFn("Added from cursor to mythical list; refresh to see.")
    M.requestMythicalList()
end

--- Remove item from augment list by ID. Updates cache immediately; persist to file.
function M.removeAug(id)
    if not id then return end
    mq.cmd("/say " .. (REROLL.COMMAND_AUG_REMOVE or "!augremove") .. " " .. tostring(id))
    for i = #augList, 1, -1 do
        if augList[i].id == id then table.remove(augList, i); break end
    end
    saveToFile()
    setStatusMessageFn("Removed from augment list.")
end

--- Remove item from mythical list by ID. Updates cache immediately; persist to file.
function M.removeMythical(id)
    if not id then return end
    mq.cmd("/say " .. (REROLL.COMMAND_MYTHICAL_REMOVE or "!mythicalremove") .. " " .. tostring(id))
    for i = #mythicalList, 1, -1 do
        if mythicalList[i].id == id then table.remove(mythicalList, i); break end
    end
    saveToFile()
    setStatusMessageFn("Removed from mythical list.")
end

--- Consume 10 listed augments from inventory and grant one new augment.
function M.augRoll()
    mq.cmd("/say " .. (REROLL.COMMAND_AUG_ROLL or "!augroll"))
    setStatusMessageFn("Augment roll executed.")
    M.requestAugList()
end

--- Consume 10 listed mythicals, grant Book of Mythical Reroll.
function M.mythicalRoll()
    mq.cmd("/say " .. (REROLL.COMMAND_MYTHICAL_ROLL or "!mythicalroll"))
    setStatusMessageFn("Mythical roll executed.")
    M.requestMythicalList()
end

--- Count how many of the given list entries are present in inventory (by item id).
function M.countInInventory(listEntries, inventoryItems)
    if not listEntries or not inventoryItems then return 0 end
    local count = 0
    local seen = {}
    for _, entry in ipairs(listEntries) do
        local id = entry.id
        if id and not seen[id] then
            for _, inv in ipairs(inventoryItems) do
                if (inv.id or inv.ID) == id then
                    count = count + 1
                    seen[id] = true
                    break
                end
            end
        end
    end
    return count
end

--- Return whether cursor item name starts with Mythical (for mythical track).
function M.isCursorMythical()
    local cur = mq.TLO and mq.TLO.Cursor
    if not cur or not cur.Name then return false end
    local name = cur.Name() or ""
    local prefix = REROLL.MYTHICAL_NAME_PREFIX or "Mythical"
    return name:sub(1, #prefix) == prefix
end

--- Check if cursor item is already in the given list (by id).
function M.isCursorIdInList(listEntries)
    if not listEntries then return false end
    local cur = mq.TLO and mq.TLO.Cursor
    if not cur or not cur.ID then return false end
    local cursorId = cur.ID()
    if not cursorId or cursorId == 0 then return false end
    for _, e in ipairs(listEntries) do
        if e.id == cursorId then return true end
    end
    return false
end

return M
