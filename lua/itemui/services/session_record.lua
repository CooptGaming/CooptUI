--[[
    session_record.lua — tonight's loot as a RECORD with a to-do inside it (§12, 26b).

    The whole design is the counting rule: the bar counts only what still needs a call,
    not what was looted. An item enters NEEDS A CALL only if no existing decision already
    covers it — already on the reroll list, matching a keep or always-junk rule, or
    NoDrop (not sellable) lands straight in SORTED with the reason, and never touches
    the amber count. Evaluated at the moment the item is RECORDED, not when the panel
    opens. Nothing ever leaves: a decided item moves to SORTED, so "how many augs did I
    get tonight" stays answerable at 2am — split the number, not the list.

    Source of truth: the shared inventory list. Rows whose acquiredSeq is at or above
    the session floor (the NEW-badge machinery) are this session's loot; the merge walk
    classifies augments (type "Augmentation"), mythicals (name prefix), and scripts
    (utils/script_defs), and runs on the main-loop tick — never in a render callback.

    The session does NOT end at logout (design recommendation, pending user reversal):
    the record persists per character in Chars/<name>/session_record.ini and reloads on
    start; Clear in the panel header is what starts a fresh one. A crash costs nothing.
]]

local mq = require('mq')
local scriptDefs = require('itemui.utils.script_defs')

local M = {}

local deps = nil
-- entries: array of {
--   uid, name, cat ("aug"|"mythic"|"script"), itemId, value, stack,
--   state ("call"|"sorted"), choice (nil|"keep"|"reroll"|"junk"|"auto"),
--   reason (why it sorted), at (os.time), bag, slot, departed, rowSeq
-- }
local entries = {}
local byRowSeq = {}        -- this session's acquiredSeq -> entry (in-memory only)
local startedAt = nil      -- os.time of first record (or file load)
local loadedFor = nil      -- char the record was loaded for
local dirty = false
local lastSaveAt = 0
local undoStack = {}       -- { {uid, choice} ... } newest last

local FILE_NAME = "session_record.ini"
local SAVE_DEBOUNCE_MS = 2000
local FIELD_SEP = "\t"

local MYTHICAL_PREFIX = "Mythical"

-- ---------------------------------------------------------------- char + file

local function charName()
    local ok, name = pcall(function()
        return mq.TLO and mq.TLO.Me and mq.TLO.Me.Name and mq.TLO.Me.Name()
    end)
    if ok and name and name ~= "" and name ~= "NULL" then return tostring(name) end
    return nil
end

local function filePath(char)
    if not (deps and deps.getCharStoragePath) then return nil end
    local ok, path = pcall(deps.getCharStoragePath, char, FILE_NAME)
    if ok and path and path ~= "" then return path end
    return nil
end

local function serializeEntry(e)
    return table.concat({
        tostring(e.uid), tostring(e.name or ""), tostring(e.cat or ""),
        tostring(e.itemId or 0), tostring(e.value or 0), tostring(e.stack or 1),
        tostring(e.state or "call"), tostring(e.choice or ""), tostring(e.reason or ""),
        tostring(e.at or 0),
        -- augType is persisted so the panel's why-line still works for an entry whose
        -- live row is gone. bag/slot/rowSeq deliberately are NOT: they are only
        -- meaningful against the current session's inventory, and a reloaded entry is
        -- always departed (the acquired-seq floor is re-stamped on snapshot load, so
        -- yesterday's rows sit below it and can never re-link). This one field is what
        -- lets a restored entry still say what it fits instead of saying nothing.
        tostring(e.augType or 0),
    }, FIELD_SEP)
end

local function splitFields(line)
    -- NOT gmatch("[^\t]*"): a zero-width pattern yields phantom empty matches between
    -- real fields and corrupts positions. Plain find/sub keeps empties AND order.
    local f = {}
    local pos = 1
    while true do
        local s = string.find(line, FIELD_SEP, pos, true)
        if not s then
            f[#f + 1] = line:sub(pos)
            break
        end
        f[#f + 1] = line:sub(pos, s - 1)
        pos = s + 1
    end
    return f
end

local function deserializeEntry(line)
    local f = splitFields(tostring(line))
    if not f[1] or f[1] == "" then return nil end
    return {
        uid = f[1], name = f[2] or "", cat = f[3] or "",
        itemId = tonumber(f[4]) or 0, value = tonumber(f[5]) or 0, stack = tonumber(f[6]) or 1,
        state = (f[7] == "sorted") and "sorted" or "call",
        choice = (f[8] ~= "" and f[8]) or nil, reason = (f[9] ~= "" and f[9]) or nil,
        at = tonumber(f[10]) or 0,
        -- Field 11 is absent in records written before the why-line landed; 0 reads the
        -- same as "unknown", which is the honest answer for those.
        augType = tonumber(f[11]) or 0,
        departed = true,   -- a loaded entry has no live row until the merge re-links it
    }
end

local function save(now)
    local char = loadedFor
    local path = char and filePath(char)
    if not (path and deps and deps.safeWrite) then return end
    local out = { "[Session]", "StartedAt=" .. tostring(startedAt or 0) }
    for i, e in ipairs(entries) do
        out[#out + 1] = string.format("E%d=%s", i, serializeEntry(e))
    end
    pcall(deps.safeWrite, path, table.concat(out, "\n") .. "\n")
    dirty = false
    lastSaveAt = now or 0
end

local function load(char)
    entries, byRowSeq, undoStack = {}, {}, {}
    startedAt = nil
    local path = filePath(char)
    if not (path and deps and deps.safeReadAll) then return end
    local ok, content = pcall(deps.safeReadAll, path)
    if not ok or not content or content == "" then return end
    local rows = {}
    for line in content:gmatch("[^\r\n]+") do
        local k, v = line:match("^(%w+)=(.*)$")
        if k == "StartedAt" then
            startedAt = tonumber(v)
            if startedAt == 0 then startedAt = nil end
        elseif k and k:match("^E%d+$") and v then
            local n = tonumber(k:sub(2))
            local e = deserializeEntry(v)
            if n and e then rows[n] = e end
        end
    end
    for i = 1, #rows + 64 do   -- tolerate gaps from hand edits
        if rows[i] then entries[#entries + 1] = rows[i] end
    end
end

local function ensureLoaded()
    local char = charName()
    if not char then return false end
    if loadedFor ~= char then
        load(char)
        loadedFor = char
    end
    return true
end

-- ---------------------------------------------------------------- classification

local function classify(row)
    if scriptDefs.BY_NAME[row.name or ""] then return "script" end
    local name = tostring(row.name or "")
    if name:sub(1, #MYTHICAL_PREFIX) == MYTHICAL_PREFIX then return "mythic" end
    if tostring(row.type or ""):lower() == "augmentation" then return "aug" end
    return nil
end

--- The §12 pre-emption: a call the player already made counts as made. Returns
--- (reason, choice) when an existing decision covers the item, nil to queue it.
local function preemptReason(row, cat)
    if cat == "script" then
        -- No decision exists for a script — only a turn-in. Straight to sorted.
        return "script - converts to AA", "auto"
    end
    local rs = deps and deps.rerollService
    local id = tonumber(row.id) or 0
    if rs and rs.getListStatus and id > 0 then
        local kind = (cat == "mythic") and "mythical" or "aug"
        local st = nil
        local ok, v = pcall(rs.getListStatus, kind, id)
        if ok then st = v end
        if st then return "already on the reroll list", "reroll" end
    end
    local inKeep, inJunk = false, false
    if deps and deps.getSellStatusForItem then
        local ok, _, _, k, j = pcall(deps.getSellStatusForItem, row)
        if ok then inKeep, inJunk = k == true, j == true end
    end
    if inKeep then return "matches a keep rule", "keep" end
    if inJunk then return "matches an always-junk rule", "junk" end
    if row.nodrop == true then return "NoDrop - can't be sold", "auto" end
    return nil, nil
end

-- ---------------------------------------------------------------- record merge

local uidCounter = 0
local function newUid()
    uidCounter = uidCounter + 1
    return string.format("%d.%d", os.time(), uidCounter)
end

--- The merge walk: record new session rows, re-link live rows to entries (bag/slot for
--- the menu), watch script stacks grow, and mark departures. Main-loop side only.
function M.tick(now)
    if not deps then return end
    if not ensureLoaded() then return end
    local floor = deps.getSessionStartAcquiredSeq and deps.getSessionStartAcquiredSeq() or nil
    local items = deps.inventoryItems or {}
    local seenSeq = {}
    if floor then
        for _, row in ipairs(items) do
            local seq = row.acquiredSeq
            if seq and seq >= floor then
                local e = byRowSeq[seq]
                if e then
                    seenSeq[seq] = true
                    e.bag, e.slot, e.departed = row.bag, row.slot, nil
                    -- A stack that grew is MORE loot (scripts merge into stacks).
                    local stack = tonumber(row.stackSize) or 1
                    if stack > (e.stackHigh or e.stack or 1) then
                        e.stack = (e.stack or 1) + (stack - (e.stackHigh or 1))
                        e.stackHigh = stack
                        dirty = true
                    end
                else
                    local cat = classify(row)
                    if cat then
                        local reason, choice = preemptReason(row, cat)
                        -- Read the row's augType ONCE, here, while the row is live.
                        -- It is a lazy field already resolved by buildAugmentIndex at
                        -- scan time, so this is a table hit, not a TLO read — and
                        -- capturing it now is what lets the panel answer "what does
                        -- this fit" for the rest of the record's life.
                        local augType = 0
                        if cat == "aug" then augType = tonumber(row.augType) or 0 end
                        local entry = {
                            uid = newUid(), name = row.name or "?", cat = cat,
                            augType = augType,
                            itemId = tonumber(row.id) or 0,
                            value = tonumber(row.totalValue or row.value) or 0,
                            stack = tonumber(row.stackSize) or 1,
                            stackHigh = tonumber(row.stackSize) or 1,
                            state = reason and "sorted" or "call",
                            choice = choice, reason = reason,
                            at = os.time(), bag = row.bag, slot = row.slot,
                            rowSeq = seq,
                        }
                        entries[#entries + 1] = entry
                        byRowSeq[seq] = entry
                        seenSeq[seq] = true
                        startedAt = startedAt or os.time()
                        dirty = true
                    end
                end
            end
        end
    end
    -- Departures: an entry whose live row vanished keeps its place in the record.
    for seq, e in pairs(byRowSeq) do
        if not seenSeq[seq] and not e.departed then
            e.departed = true
            e.bag, e.slot = nil, nil
        end
    end
    if dirty and (now or 0) - lastSaveAt >= SAVE_DEBOUNCE_MS then
        save(now)
    end
end

-- ---------------------------------------------------------------- decisions

local function findByUid(uid)
    for _, e in ipairs(entries) do
        if e.uid == uid then return e end
    end
    return nil
end

--- Whether a choice is possible for an entry right now. Returns (ok, reasonWhenNot).
function M.canDecide(uid, choice)
    local e = findByUid(uid)
    if not e then return false, "gone" end
    if e.state == "sorted" and choice ~= "undo" then return false, "already sorted" end
    if choice == "reroll" then
        if (e.itemId or 0) <= 0 then return false, "no item id" end
        if e.departed then return false, "not in bags" end
    elseif choice == "junk" then
        if e.reason == "NoDrop - can't be sold" then return false, "NoDrop" end
    end
    return true, nil
end

--- Apply a call. keep/junk go through the sell lists, reroll through the pending
--- reroll list — the SAME mutations the §7 menu performs, so the record can never
--- disagree with the rules it teaches.
function M.decide(uid, choice)
    local e = findByUid(uid)
    if not e or e.state == "sorted" then return false end
    local okTo = M.canDecide(uid, choice)
    if not okTo then return false end
    if choice == "keep" then
        if deps.applySellListChange then pcall(deps.applySellListChange, e.name, true, false) end
        e.reason = "kept - never sell"
    elseif choice == "junk" then
        if deps.applySellListChange then pcall(deps.applySellListChange, e.name, false, true) end
        e.reason = "always junk this kind"
    elseif choice == "reroll" then
        local rs = deps.rerollService
        local kind = (e.cat == "mythic") and "mythical" or "aug"
        if rs and rs.addToPendingList then pcall(rs.addToPendingList, kind, e.itemId, e.name) end
        e.reason = "on the reroll list"
    else
        return false
    end
    e.state = "sorted"
    e.choice = choice
    undoStack[#undoStack + 1] = { uid = uid, choice = choice }
    dirty = true
    return true
end

--- Z: revert the LAST decision — the entry returns to NEEDS A CALL and the rule
--- mutation is unwound.
function M.undo()
    local last = table.remove(undoStack)
    if not last then return false end
    local e = findByUid(last.uid)
    if not e then return false end
    if last.choice == "keep" or last.choice == "junk" then
        if deps.applySellListChange then pcall(deps.applySellListChange, e.name, false, false) end
    elseif last.choice == "reroll" then
        local rs = deps.rerollService
        local kind = (e.cat == "mythic") and "mythical" or "aug"
        if rs and rs.removeFromPending then pcall(rs.removeFromPending, kind, e.itemId) end
    end
    e.state = "call"
    e.choice = nil
    e.reason = nil
    dirty = true
    return true
end

--- Clear starts a fresh session NOW (the design's answer to "does it end at logout":
--- no — it ends here).
function M.clear()
    entries, byRowSeq, undoStack = {}, {}, {}
    startedAt = nil
    dirty = true
    save(0)
end

-- ---------------------------------------------------------------- reads

--- Cell + panel counts. Amber = needs a call; scripts have no decision and stay white.
function M.getCounts()
    local c = {
        augsCall = 0, augsTotal = 0,
        mythicsCall = 0, mythicsTotal = 0,
        scripts = 0,
        sorted = 0, looted = 0,
        startedAt = startedAt,
        canUndo = #undoStack > 0,
    }
    for _, e in ipairs(entries) do
        c.looted = c.looted + 1
        if e.state == "sorted" then c.sorted = c.sorted + 1 end
        if e.cat == "aug" then
            c.augsTotal = c.augsTotal + 1
            if e.state == "call" then c.augsCall = c.augsCall + 1 end
        elseif e.cat == "mythic" then
            c.mythicsTotal = c.mythicsTotal + 1
            if e.state == "call" then c.mythicsCall = c.mythicsCall + 1 end
        elseif e.cat == "script" then
            c.scripts = c.scripts + (e.stack or 1)
        end
    end
    return c
end

--- NEEDS A CALL, by value best first (triage only pays if the top row is worth
--- thinking about). Returns a COPY — the panel must not shift under ImGui mid-render.
function M.getCallList()
    local out = {}
    for _, e in ipairs(entries) do
        if e.state == "call" then out[#out + 1] = e end
    end
    table.sort(out, function(a, b) return (a.value or 0) > (b.value or 0) end)
    return out
end

--- SORTED, newest first, with the reason each carries.
function M.getSortedList()
    local out = {}
    for _, e in ipairs(entries) do
        if e.state == "sorted" then out[#out + 1] = e end
    end
    table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
    return out
end

-- ---------------------------------------------------------------- wiring

function M.init(d)
    deps = d
end

--- Test seam: reset in-memory state (never touches the file).
function M._resetForTests()
    entries, byRowSeq, undoStack = {}, {}, {}
    startedAt, loadedFor, dirty, lastSaveAt, uidCounter = nil, nil, false, 0, 0
end

return M
