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
local coopuiPlugin = require('itemui.utils.coopui_plugin')

local REROLL = constants.REROLL or {}

-- Optional C++ plugin: when loaded, use coopui.cursor for cursor data.
local function tryCoopUIPlugin() return coopuiPlugin.getPlugin() end

local function getCursorId()
    local coop = tryCoopUIPlugin()
    if coop and coop.cursor and coop.cursor.getItemId then
        local id = coop.cursor.getItemId()
        return (id ~= nil) and id or 0
    end
    local cur = mq.TLO and mq.TLO.Cursor
    return (cur and cur.ID and cur.ID()) or 0
end

local function getCursorName()
    local coop = tryCoopUIPlugin()
    if coop and coop.cursor and coop.cursor.getItemName then
        local name = coop.cursor.getItemName()
        return (name ~= nil) and name or ""
    end
    local cur = mq.TLO and mq.TLO.Cursor
    return (cur and cur.Name and cur.Name()) or ""
end

local function getCursorLink()
    local coop = tryCoopUIPlugin()
    if coop and coop.cursor and coop.cursor.getItemLink then
        local link = coop.cursor.getItemLink()
        return (link ~= nil) and link or ""
    end
    local cur = mq.TLO and mq.TLO.Cursor
    return (cur and (cur.Link and cur.Link() or cur.ItemLink and cur.ItemLink())) or ""
end
local LIST_PARSE_MS = REROLL.LIST_RESPONSE_PARSE_MS or 6000
-- Cap per-list size so very large server responses don't cause buffer/UI issues (chunked parsing already line-by-line).
local MAX_LIST_ENTRIES = 2000

local augList = {}       -- { { id = number, name = string }, ... }
local mythicalList = {}  -- { { id = number, name = string }, ... }
local pendingAugList = {}     -- items added from field; sync in guild hall
local pendingMythicalList = {}
-- Single parse window: accept list lines until receivingListSince + LIST_PARSE_MS. Header sets currentList (aug/mythical).
local receivingListSince = nil   -- mq.gettime() when we sent list request(s)
local currentList = nil         -- "aug" or "mythical", set by last header seen in stream
local lastListSaveAt = nil      -- throttle saveToFile during burst (persist every 200ms)
local setStatusMessageFn = function() end

-- Per 4.2 state ownership: add flow and bank-move state owned by reroll_service
local state = {
    pendingRerollAdd = nil,         -- { list, bag, slot, source, itemId, itemName, step, sentAt }
    pendingRerollBankMoves = nil,   -- { list, items, nextIndex } for main_loop to move items to bank
    pendingAugRollComplete = nil,   -- true when waiting for augment roll result on cursor
    pendingAugRollCompleteAt = nil,-- mq.gettime() for timeout
    pendingRerollSync = nil,        -- { list = "aug"|"mythical", nextIndex, entries } for Sync pending (one per cycle)
}
local getRerollListStoragePathFn = nil  -- optional: function() return path end for persistence
local onRerollListChangedFn = nil       -- optional: callback when aug/mythical/pending lists change (invalidate sell cache)
-- When adding via pickup flow: after we send !augadd/!mythicaladd, we wait for a list line containing this id then call callback (put back, update UI).
local pendingAddAckId = nil
local pendingAddAckCallback = nil

-- ---------------------------------------------------------------------------
-- Cache infrastructure: generation-based invalidation for O(1) lookups
-- ---------------------------------------------------------------------------
local _listGeneration = 0           -- incremented on every list mutation
local _augIdSet = nil               -- cached { [id] = true } for augList
local _augIdSetGen = -1
local _mythIdSet = nil              -- cached { [id] = true } for mythicalList
local _mythIdSetGen = -1
local _uniqueAugList = nil          -- cached deduplicated augList
local _uniqueAugGen = -1
local _uniqueMythList = nil         -- cached deduplicated mythicalList
local _uniqueMythGen = -1
local _locInvSet = nil              -- cached { [id] = true } for items on list AND in inventory
local _locBankSet = nil             -- cached { [id] = true } for items on list AND in bank
local _locGen = -1                  -- generation when location sets were built
local _locItemGen = 0               -- bumped when inventory/bank contents change (items move)
local _locItemGenAtBuild = -1       -- _locItemGen value when location sets were last built
local _locPaused = false            -- when true, location cache rebuilds are suppressed (during automated roll moves)

local function markListDirty()
    _listGeneration = _listGeneration + 1
end

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

-- More permissive: "ID: 123 Name: Foo", "id 123 name Foo", or leading digits then rest as name (for paste/import).
local function parseListLineFlexible(line)
    if not line or type(line) ~= "string" then return nil, nil end
    local id, name = parseIdNameLine(line)
    if id then return id, name end
    id, name = parseColonDashLine(line)
    if id then return id, name end
    -- "ID: 123", "id=123", or "id 123" with optional "name" or "Name" and value
    local idStr = line:match("[Ii][Dd]%s*[:=]%s*(%d+)") or line:match("^%s*[Ii][Dd]%s+(%d+)")
    if idStr then
        id = tonumber(idStr)
        if id and id > 0 then
            name = line:match("[Nn]ame%s*[:=]%s*(.+)") or line:match("^%s*[Ii][Dd]%s*[:=]?%s*%d+%s+[Nn]ame%s*[:=]?%s*(.+)") or line:match("^%s*%d+%s*[%-:]%s*(.+)") or line:gsub("^%s*[Ii]?[Dd]?%s*[:=]?%s*%d+%s*", ""):match("^%s*(.-)%s*$")
            return id, (name and name:match("^%s*(.-)%s*$")) or ""
        end
    end
    -- Leading digits then rest of line as name: "12345 Item Name Here"
    idStr, name = line:match("^%s*(%d+)%s+(.+)$")
    if idStr and idStr ~= "" then
        id = tonumber(idStr)
        if id and id > 0 then return id, (name and name:match("^%s*(.-)%s*$")) or "" end
    end
    return nil, nil
end

-- Detect header to know which list we're filling (optional; we also use pending* from Refresh).
-- Only treat as header if line looks like a section title (e.g. "===== Aug List =====").
-- Do NOT treat "Aug list removed: ..." or "Aug list added: ..." as headers or we clear the list on every add/remove.
--- True if current zone is a guild hall where !augadd/!mythicaladd are accepted.
local function isInGuildHall()
    local zones = REROLL.GUILD_HALL_ZONE_SHORT_NAMES
    if not zones or type(zones) ~= "table" then return false end
    local z = mq.TLO and mq.TLO.Zone
    local short = z and z.ShortName and z.ShortName()
    if not short or short == "" then return false end
    short = short:lower()
    for _, name in ipairs(zones) do
        if (name or ""):lower() == short then return true end
    end
    return false
end

-- Detect header to know which list we're filling (optional; we also use pending* from Refresh).
local function detectListHeader(line)
    if not line or type(line) ~= "string" then return nil end
    if not line:find("=====") then return nil end
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
        lines[#lines + 1] = "  },"
        lines[#lines + 1] = "  pendingAug = {"
        for _, e in ipairs(pendingAugList) do
            lines[#lines + 1] = string.format("    { id = %s, name = %q },", tostring(e.id), e.name or "")
        end
        lines[#lines + 1] = "  },"
        lines[#lines + 1] = "  pendingMythical = {"
        for _, e in ipairs(pendingMythicalList) do
            lines[#lines + 1] = string.format("    { id = %s, name = %q },", tostring(e.id), e.name or "")
        end
        lines[#lines + 1] = "  }"
        lines[#lines + 1] = "}"
        local f = io.open(path, "w")
        if f then f:write(table.concat(lines, "\n")); f:close() end
    end)
    if not ok then
        if setStatusMessageFn then setStatusMessageFn("Could not save reroll list cache") end
        local diag = require('itemui.core.diagnostics')
        diag.recordError("Reroll", "Could not save reroll list cache", err)
    else
        if onRerollListChangedFn then onRerollListChangedFn() end
    end
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
        if type(data.pendingAug) == "table" then pendingAugList = data.pendingAug end
        if type(data.pendingMythical) == "table" then pendingMythicalList = data.pendingMythical end
        markListDirty()
        if onRerollListChangedFn then onRerollListChangedFn() end
    elseif not ok then
        local diag = require('itemui.core.diagnostics')
        diag.recordError("Reroll", "Could not load reroll list cache", data)
    end
end

-- Parse "Aug list added: ... (id 75084)." or "Mythical list added: ... (id 413257)." → id or nil.
local function parseAddConfirmationLine(line)
    if not line or type(line) ~= "string" then return nil end
    local idStr = line:match("%(id%s+(%d+)%)")
    if not idStr or idStr == "" then return nil end
    return tonumber(idStr)
end

-- Chat callback: server confirms add with "Aug list added: Name (id N)." / "Mythical list added: Name (id N)."
-- Fire ack immediately so we can put the item back without waiting for a full list line.
local function onRerollAddConfirmation(line)
    local id = parseAddConfirmationLine(line)
    if not id then return end
    if pendingAddAckId and id == pendingAddAckId and pendingAddAckCallback then
        pendingAddAckCallback()
        pendingAddAckId = nil
        pendingAddAckCallback = nil
    end
end

-- Chat event callback: when server echoes a list line or header, parse and add to the appropriate list.
-- Single window (receivingListSince): headers set currentList so both aug and mythical fill in one stream (fast).
local function onRerollListLine(line)
    local now = mq.gettime()
    local header = detectListHeader(line)
    if header == "aug" then
        augList = {}
        currentList = "aug"
        markListDirty()
        return
    end
    if header == "mythical" then
        mythicalList = {}
        currentList = "mythical"
        markListDirty()
        return
    end
    if line:match("^%s*[Tt]otal") then return end
    if not receivingListSince or (now - receivingListSince) >= LIST_PARSE_MS then return end
    if not currentList then return end
    local id, name = parseListLine(line)
    if not id then id, name = parseListLineFlexible(line) end
    if not id then return end
    if pendingAddAckId and id == pendingAddAckId and pendingAddAckCallback then
        pendingAddAckCallback()
        pendingAddAckId = nil
        pendingAddAckCallback = nil
        return
    end
    local entry = { id = id, name = name }
    if currentList == "aug" then
        if #augList < MAX_LIST_ENTRIES then table.insert(augList, entry) end
    else
        if #mythicalList < MAX_LIST_ENTRIES then table.insert(mythicalList, entry) end
    end
    markListDirty()
    setStatusMessageFn("Lists updated.")
    -- No intermediate saves during burst: data is in memory, final save happens in checkListRequestTimeout().
end

local M = {}

function M.init(deps)
    setStatusMessageFn = deps.setStatusMessage or function() end
    getRerollListStoragePathFn = deps.getRerollListStoragePath
    onRerollListChangedFn = deps.onRerollListChanged
    augList = {}
    mythicalList = {}
    pendingAugList = {}
    pendingMythicalList = {}
    receivingListSince = nil
    currentList = nil
    lastListSaveAt = nil
    pendingAddAckId = nil
    pendingAddAckCallback = nil
    state.pendingRerollAdd = nil
    loadFromFile()
    -- Server list requests only: (1) explicit Refresh in UI, (2) stored list empty on load. Both lists in one stream (fast).
    if #augList == 0 and #mythicalList == 0 then
        M.requestBothLists()
    elseif #augList == 0 then
        M.requestAugList()
    elseif #mythicalList == 0 then
        M.requestMythicalList()
    end
    -- User can Refresh in Reroll Companion to re-query; other automatic triggers (post-roll, zone, bank) removed.
    -- Match server list lines: "id=123 name=..." or "123: Name" or "123 - Name". Header "===== Aug List =====" also matched.
    mq.event("ItemUIRerollListLine", "#*#id=#*#name=#*#", onRerollListLine)
    mq.event("ItemUIRerollListLineColon", "#*#:#*#", onRerollListLine)
    mq.event("ItemUIRerollListLineDash", "#*#-#*#", onRerollListLine)
    mq.event("ItemUIRerollListHeader", "#*#=#*#List#*#", onRerollListLine)
    -- Add confirmation: "Aug list added: Name (id N)." / "Mythical list added: Name (id N)." — ack immediately to clear cursor fast.
    mq.event("ItemUIRerollAugAdded", "#*#Aug list added:#*#(id #*#).#*#", onRerollAddConfirmation)
    mq.event("ItemUIRerollMythicalAdded", "#*#Mythical list added:#*#(id #*#).#*#", onRerollAddConfirmation)
end

function M.getAugList()
    return augList
end

function M.getMythicalList()
    return mythicalList
end

function M.getPendingAugList()
    return pendingAugList
end

function M.getPendingMythicalList()
    return pendingMythicalList
end

function M.isInGuildHall()
    return isInGuildHall()
end

--- Add item (by id/name) to pending list only; no cursor. Used when adding from context menu outside guild hall.
function M.addToPendingList(listKind, id, name)
    if not id or (listKind ~= "aug" and listKind ~= "mythical") then return false end
    local list = (listKind == "aug") and pendingAugList or pendingMythicalList
    for _, e in ipairs(list) do if e.id == id then return true end end
    if #list >= MAX_LIST_ENTRIES then return false end
    list[#list + 1] = { id = id, name = name or "" }
    saveToFile()
    return true
end

--- Remove one entry from pending list by id; persist. Used after successful sync.
function M.removeFromPending(listKind, id)
    if listKind == "aug" then
        for i = #pendingAugList, 1, -1 do
            if pendingAugList[i].id == id then table.remove(pendingAugList, i); saveToFile(); return end
        end
    elseif listKind == "mythical" then
        for i = #pendingMythicalList, 1, -1 do
            if pendingMythicalList[i].id == id then table.remove(pendingMythicalList, i); saveToFile(); return end
        end
    end
end

--- Request server to return augment list only.
function M.requestAugList()
    augList = {}
    currentList = "aug"
    receivingListSince = mq.gettime()
    mq.cmd("/say " .. (REROLL.COMMAND_AUG_LIST or "!auglist"))
    setStatusMessageFn("Requesting augment list...")
end

--- Request server to return mythical list only.
function M.requestMythicalList()
    mythicalList = {}
    currentList = "mythical"
    receivingListSince = mq.gettime()
    mq.cmd("/say " .. (REROLL.COMMAND_MYTHICAL_LIST or "!mythicallist"))
    setStatusMessageFn("Requesting mythical list...")
end

--- Request both lists at once; one parse window, headers switch aug/mythical. Both lists fill in 1–2 seconds.
function M.requestBothLists()
    currentList = nil
    receivingListSince = mq.gettime()
    mq.cmd("/say " .. (REROLL.COMMAND_AUG_LIST or "!auglist"))
    mq.cmd("/say " .. (REROLL.COMMAND_MYTHICAL_LIST or "!mythicallist"))
    setStatusMessageFn("Requesting lists...")
end

--- Call each tick: clear receiving window after timeout; persist once when done.
function M.checkListRequestTimeout(now)
    if receivingListSince and (now - receivingListSince) >= LIST_PARSE_MS then
        receivingListSince = nil
        currentList = nil
        lastListSaveAt = nil
        markListDirty()
        saveToFile()
        setStatusMessageFn("List request finished.")
        if onRerollListChangedFn then onRerollListChangedFn() end
    end
end

--- Return protection sets for sell/loot rules: items in these sets must never be sold and should be skipped by loot.
--- Includes server list and pending list so items queued for sync are protected until synced or removed.
--- ID-only: name-based matching was removed because same-name-different-ID items are common
--- (e.g. "Gem of Illusion: Ogre Pirate" exists with multiple IDs) and name matching
--- would incorrectly protect/block unrelated items.
function M.getRerollListProtection()
    local idSet = {}
    for _, e in ipairs(augList) do
        if e.id then idSet[e.id] = true end
    end
    for _, e in ipairs(mythicalList) do
        if e.id then idSet[e.id] = true end
    end
    for _, e in ipairs(pendingAugList) do
        if e.id then idSet[e.id] = true end
    end
    for _, e in ipairs(pendingMythicalList) do
        if e.id then idSet[e.id] = true end
    end
    return { idSet = idSet }
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
        if #augList < MAX_LIST_ENTRIES then table.insert(augList, entry); markListDirty(); saveToFile() end
    elseif listKind == "mythical" then
        for _, e in ipairs(mythicalList) do if e.id == id then return end end
        if #mythicalList < MAX_LIST_ENTRIES then table.insert(mythicalList, entry); markListDirty(); saveToFile() end
    end
end

--- Remove one entry from in-memory list only (no server command). Used to roll back optimistic add on timeout.
function M.removeEntryFromCache(listKind, id)
    if not id or (listKind ~= "aug" and listKind ~= "mythical") then return end
    if listKind == "aug" then
        for i = #augList, 1, -1 do
            if augList[i].id == id then table.remove(augList, i); markListDirty(); saveToFile(); return end
        end
    else
        for i = #mythicalList, 1, -1 do
            if mythicalList[i].id == id then table.remove(mythicalList, i); markListDirty(); saveToFile(); return end
        end
    end
end

--- Add item on cursor to augment reroll list. In guild hall: add + send command. Outside: add to pending only.
function M.addAugFromCursor()
    local id = getCursorId()
    if not id or id == 0 then
        setStatusMessageFn("No item on cursor.")
        return
    end
    local name = getCursorName()
    if isInGuildHall() then
        M.addEntryToList("aug", id, name)
        mq.cmd("/say " .. (REROLL.COMMAND_AUG_ADD or "!augadd"))
        setStatusMessageFn("Added to augment list.")
    else
        for _, e in ipairs(pendingAugList) do if e.id == id then setStatusMessageFn("Already on pending list."); return end end
        if #pendingAugList >= MAX_LIST_ENTRIES then setStatusMessageFn("Pending list full."); return end
        pendingAugList[#pendingAugList + 1] = { id = id, name = name or "" }
        saveToFile()
        setStatusMessageFn("Added to list (sync required in guild hall).")
    end
end

--- Add item on cursor to mythical reroll list. In guild hall: add + send command. Outside: add to pending only.
function M.addMythicalFromCursor()
    local id = getCursorId()
    if not id or id == 0 then
        setStatusMessageFn("No item on cursor.")
        return
    end
    local name = getCursorName()
    if isInGuildHall() then
        M.addEntryToList("mythical", id, name)
        mq.cmd("/say " .. (REROLL.COMMAND_MYTHICAL_ADD or "!mythicaladd"))
        setStatusMessageFn("Added to mythical list.")
    else
        for _, e in ipairs(pendingMythicalList) do if e.id == id then setStatusMessageFn("Already on pending list."); return end end
        if #pendingMythicalList >= MAX_LIST_ENTRIES then setStatusMessageFn("Pending list full."); return end
        pendingMythicalList[#pendingMythicalList + 1] = { id = id, name = name or "" }
        saveToFile()
        setStatusMessageFn("Added to list (sync required in guild hall).")
    end
end

--- Remove item from augment list by ID. Updates cache immediately; persist to file.
function M.removeAug(id)
    if not id then return end
    mq.cmd("/say " .. (REROLL.COMMAND_AUG_REMOVE or "!augremove") .. " " .. tostring(id))
    for i = #augList, 1, -1 do
        if augList[i].id == id then table.remove(augList, i); break end
    end
    markListDirty()
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
    markListDirty()
    saveToFile()
    setStatusMessageFn("Removed from mythical list.")
end

local ITEMS_CONSUMED_PER_ROLL = REROLL.ITEMS_REQUIRED or 10

--- Optimistically remove the last N entries from a list (after a roll the server consumes that many). Persist.
local function removeLastNFromList(listKind, n)
    if listKind == "aug" then
        local remove = math.min(n, #augList)
        for _ = 1, remove do table.remove(augList) end
        if remove > 0 then markListDirty(); saveToFile() end
    elseif listKind == "mythical" then
        local remove = math.min(n, #mythicalList)
        for _ = 1, remove do table.remove(mythicalList) end
        if remove > 0 then markListDirty(); saveToFile() end
    end
end

--- Consume 10 listed augments from inventory and grant one new augment.
--- No server list request: list only changes by add/remove; optimistically update in-memory list.
function M.augRoll()
    mq.cmd("/say " .. (REROLL.COMMAND_AUG_ROLL or "!augroll"))
    setStatusMessageFn("Augment roll executed.")
    removeLastNFromList("aug", ITEMS_CONSUMED_PER_ROLL)
end

--- Consume 10 listed mythicals, grant Book of Mythical Reroll.
--- No server list request: optimistically update in-memory list.
function M.mythicalRoll()
    mq.cmd("/say " .. (REROLL.COMMAND_MYTHICAL_ROLL or "!mythicalroll"))
    setStatusMessageFn("Mythical roll executed.")
    removeLastNFromList("mythical", ITEMS_CONSUMED_PER_ROLL)
end

--- Return cached ID set for augList (rebuilt only when list generation changes).
local function getAugIdSet()
    if _augIdSetGen == _listGeneration and _augIdSet then return _augIdSet end
    local s = {}
    for _, e in ipairs(augList) do if e.id then s[e.id] = true end end
    _augIdSet = s
    _augIdSetGen = _listGeneration
    return s
end

--- Return cached ID set for mythicalList (rebuilt only when list generation changes).
local function getMythIdSet()
    if _mythIdSetGen == _listGeneration and _mythIdSet then return _mythIdSet end
    local s = {}
    for _, e in ipairs(mythicalList) do if e.id then s[e.id] = true end end
    _mythIdSet = s
    _mythIdSetGen = _listGeneration
    return s
end

--- Count how many inventory/bank items are on the list (every instance counts).
--- Uses cached ID sets for O(1) per-item lookup.
function M.countInInventory(listEntries, inventoryItems)
    if not listEntries or not inventoryItems then return 0 end
    local listIds
    if listEntries == augList then
        listIds = getAugIdSet()
    elseif listEntries == mythicalList then
        listIds = getMythIdSet()
    else
        listIds = {}
        for _, e in ipairs(listEntries) do if e.id then listIds[e.id] = true end end
    end
    local count = 0
    for _, inv in ipairs(inventoryItems) do
        local id = inv.id or inv.ID
        if id and listIds[id] then count = count + 1 end
    end
    return count
end

--- Return whether cursor item name starts with Mythical (for mythical track).
function M.isCursorMythical()
    local name = getCursorName()
    local prefix = REROLL.MYTHICAL_NAME_PREFIX or "Mythical"
    return name:sub(1, #prefix) == prefix
end

--- Check if cursor item is already in the given list (by id). Uses cached O(1) set lookup.
function M.isCursorIdInList(listEntries)
    if not listEntries then return false end
    local cursorId = getCursorId()
    if not cursorId or cursorId == 0 then return false end
    if listEntries == augList then
        return getAugIdSet()[cursorId] == true
    elseif listEntries == mythicalList then
        return getMythIdSet()[cursorId] == true
    end
    for _, e in ipairs(listEntries) do
        if e.id == cursorId then return true end
    end
    return false
end

--- Start syncing pending list to server (one item per cycle). Call when in guild hall and pending non-empty.
function M.startPendingSync(listKind)
    if listKind ~= "aug" and listKind ~= "mythical" then return end
    local entries = (listKind == "aug") and pendingAugList or pendingMythicalList
    if #entries == 0 then return end
    local copy = {}
    for _, e in ipairs(entries) do copy[#copy + 1] = { id = e.id, name = e.name or "" } end
    state.pendingRerollSync = {
        list = listKind, entries = copy, nextIndex = 1,
        syncedCount = 0, failedCount = 0, failedItems = {},
        totalCount = #copy,
    }
end

--- Return cached deduplicated augList (rebuilt only when list generation changes).
function M.getUniqueAugList()
    if _uniqueAugGen == _listGeneration and _uniqueAugList then return _uniqueAugList end
    local seen, result = {}, {}
    for _, e in ipairs(augList) do
        if e.id and not seen[e.id] then
            seen[e.id] = true
            result[#result + 1] = e
        end
    end
    _uniqueAugList = result
    _uniqueAugGen = _listGeneration
    return result
end

--- Return cached deduplicated mythicalList (rebuilt only when list generation changes).
function M.getUniqueMythicalList()
    if _uniqueMythGen == _listGeneration and _uniqueMythList then return _uniqueMythList end
    local seen, result = {}, {}
    for _, e in ipairs(mythicalList) do
        if e.id and not seen[e.id] then
            seen[e.id] = true
            result[#result + 1] = e
        end
    end
    _uniqueMythList = result
    _uniqueMythGen = _listGeneration
    return result
end

--- Return cached location sets: which list items are in inventory vs bank.
--- Rebuilds when list generation or item generation changes (unless paused).
function M.getLocationSets(inventoryItems, bankItems)
    if _locGen == _listGeneration and _locItemGenAtBuild == _locItemGen and _locInvSet then
        return _locInvSet, _locBankSet
    end
    -- When paused (automated roll in progress), return stale cache to avoid churn
    if _locPaused and _locInvSet then
        return _locInvSet, _locBankSet
    end
    local augIds = getAugIdSet()
    local mythIds = getMythIdSet()
    local invSet, bankSet = {}, {}
    if inventoryItems then
        for _, inv in ipairs(inventoryItems) do
            local id = inv.id or inv.ID
            if id and (augIds[id] or mythIds[id]) then invSet[id] = true end
        end
    end
    if bankItems then
        for _, bn in ipairs(bankItems) do
            local id = bn.id or bn.ID
            if id and (augIds[id] or mythIds[id]) then bankSet[id] = true end
        end
    end
    _locInvSet = invSet
    _locBankSet = bankSet
    _locGen = _listGeneration
    _locItemGenAtBuild = _locItemGen
    return invSet, bankSet
end

--- Return current list generation (for external sort cache invalidation).
function M.getListGeneration()
    return _listGeneration
end

--- Bump item-location generation so getLocationSets rebuilds on next call.
--- Call when inventory or bank contents change (scan, move, sell, etc.).
function M.invalidateLocationCache()
    if not _locPaused then
        _locItemGen = _locItemGen + 1
    end
end

--- Pause location cache updates (during automated roll bank-to-inv moves).
function M.pauseLocationCache()
    _locPaused = true
end

--- Resume location cache updates and force a rebuild on next access.
function M.resumeLocationCache()
    _locPaused = false
    _locItemGen = _locItemGen + 1
end

--- Return the current item-location generation (for view-level change detection).
function M.getLocationGeneration()
    return _locItemGen
end

--- Return state table for 4.2 ownership; init wires uiState.* to this so existing code unchanged.
function M.getState()
    return state
end

return M
