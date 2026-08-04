--[[
    session_record.lua — tonight's loot as a RECORD with a to-do inside it (§12, 26b).

    WHAT THE QUEUE IS FOR: augments and mythicals you just looted, so you can decide
    whether to reroll the ones you do not need. That is the entire product. Two rules fall
    straight out of it, and both were once got wrong:

    SCRIPTS ARE A TALLY, NOT A DECISION. You always keep a script — the Scripts window
    turns them in for AA. There is nothing to rule on, so a script never enters the queue
    and never enters SORTED; it only increments a count the panel shows on its own line.
    They used to sit in NEEDS A CALL offering Keep and Junk chips for a choice that does
    not exist, and three of them at the top of the list is three rows of noise over the one
    augment that actually wanted an answer.

    ONLY WHAT CAME OFF A CORPSE. The old source was the inventory delta — any row whose
    acquiredSeq reached the session floor. That is a different question: a row appears for
    every way an item can enter the bags, so an augment pulled out of a socket, a bank
    withdrawal or a trade all queued up as fresh loot. services/loot_watch.lua listens to
    the game's own "You have looted" line instead, and a new row is recorded only if it can
    claim one. See that file for why the gate fails open until it has proof it works.

    The counting rule (§12): the bar counts only what still needs a call. An item enters
    NEEDS A CALL unless a REAL decision already covers it — and after field use that means
    exactly two things: it is on the reroll list, or it carries an explicit always-junk
    rule. Both are deliberate overrides.

    A keep-rule match and NoDrop are NOT decisions, and treating them as such was a bug
    worth remembering: augments and mythics are keep-protected by default (Augmentation
    ships in sell_keep_types; Mythical in sell_keep_contains), and those ARE the categories
    this queue holds. So the pre-emption swallowed every item the feature exists to ask
    about and the queue sat permanently empty. Protected-from-sale is the resting state of
    this loot, not a call anyone made.

    Evaluated at the moment the item is RECORDED, not when the panel opens. Nothing ever
    leaves: a decided item moves to SORTED, so "how many augs did I get tonight" stays
    answerable at 2am — split the number, not the list.

    The merge walk classifies augments (type "Augmentation"), mythicals (name prefix), and
    scripts (utils/script_defs), and runs on the main-loop tick — never in a render
    callback.

    The session does NOT end at logout (design recommendation, pending user reversal):
    the record persists per character in Chars/<name>/session_record.ini and reloads on
    start; Clear in the panel header is what starts a fresh one. A crash costs nothing.
]]

local mq = require('mq')
local scriptDefs = require('itemui.utils.script_defs')
local lootWatch = require('itemui.services.loot_watch')

local M = {}

local deps = nil
-- entries: array of {
--   uid, name, cat ("aug"|"mythic"|"script"), itemId, value, stack,
--   state ("call"|"sorted"|"tally"), choice (nil|"keep"|"reroll"|"junk"),
--   reason (why it sorted), at (os.time), bag, slot, departed, rowSeq
-- }
-- "tally" is every script: counted, never queued, never sorted.
local entries = {}
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
        -- Records written before scripts became a tally carry "call"/"sorted" for them;
        -- migrateScripts() below rewrites those on the first tick after load.
        state = ((f[7] == "sorted" or f[7] == "tally") and f[7]) or "call",
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
    entries, undoStack = {}, {}
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
--- Never reached for scripts — they are a tally and there is no call to pre-empt.
---
--- ONLY TWO THINGS COUNT AS A DECISION HERE: an explicit sell (always-junk) and a reroll.
--- Everything else stays in the queue.
---
--- The reason is that augments and mythics are keep-protected by default (Augmentation is
--- in the shipped sell_keep_types; Mythical is in sell_keep_contains) — which is exactly
--- the loot this queue holds. So treating "matches a keep rule" as a decision pre-empted
--- literally every item the feature exists to ask about, and the queue sat permanently
--- empty. "Protected from being sold" is the DEFAULT STATE of this loot, not something the
--- player chose; only a deliberate override carries information.
---
--- NoDrop is out for the same reason: it is a property of the item, not a call anyone
--- made. It still blocks the Junk chip, via the entry's own nodrop flag rather than by
--- removing the row.
local function preemptReason(row, cat)
    local rs = deps and deps.rerollService
    local id = tonumber(row.id) or 0
    if rs and rs.getListStatus and id > 0 then
        local kind = (cat == "mythic") and "mythical" or "aug"
        local st = nil
        local ok, v = pcall(rs.getListStatus, kind, id)
        if ok then st = v end
        if st == "pending" then return "queued for the reroll list", "reroll" end
        if st then return "already on the reroll list", "reroll" end
    end
    local inJunk = false
    if deps and deps.getSellStatusForItem then
        local ok, _, _, _, j = pcall(deps.getSellStatusForItem, row)
        if ok then inJunk = j == true end
    end
    if inJunk then return "matches an always-junk rule", "junk" end
    return nil, nil
end

-- ---------------------------------------------------------------- record merge

local uidCounter = 0
local function newUid()
    uidCounter = uidCounter + 1
    return string.format("%d.%d", os.time(), uidCounter)
end

--- Scripts recorded before they became a tally are still carrying a queue state (and
--- possibly a keep/junk the player pressed just to clear the row). Rewrite them in place,
--- so a session already in progress fixes itself instead of needing a Clear.
local function migrateScripts()
    local scriptUids = nil
    for _, e in ipairs(entries) do
        if e.cat == "script" and e.state ~= "tally" then
            e.state, e.choice, e.reason = "tally", nil, nil
            scriptUids = scriptUids or {}
            scriptUids[e.uid] = true
        end
    end
    if not scriptUids then return end
    -- Undo walks back a DECISION. A script no longer has one, and letting Z resurrect it
    -- into the queue would undo the migration one row at a time.
    for i = #undoStack, 1, -1 do
        if scriptUids[undoStack[i].uid] then table.remove(undoStack, i) end
    end
    dirty = true
end

--- Is this live row the item this entry was recorded for?
---
--- The identity check that acquiredSeq alone cannot give. A stamp follows the SLOT before
--- it follows the item (services/scan.lua stamps bag:slot first, id second), so any bag
--- shuffle can hand an entry's seq to whatever moved into its old slot. Matching on
--- itemId + name means a stolen seq is rejected rather than believed.
local function rowIsEntry(e, row)
    if tostring(row.name or "") ~= tostring(e.name or "") then return false end
    local want = tonumber(e.itemId) or 0
    if want <= 0 then return true end       -- pre-id records: name is all there is
    return (tonumber(row.id) or 0) == want
end

--- Re-attach `e` to its live row: bag/slot for the §7 menu, and the "still in your bags"
--- the Reroll chip refuses without.
local function linkEntry(e, row)
    if e.departed then dirty = true end
    e.departed = nil
    e.bag, e.slot = row.bag, row.slot
    e.rowSeq = row.acquiredSeq
    local stack = tonumber(row.stackSize) or 1
    local high = e.stackHigh or e.stack or 1
    if stack > high then
        -- A stack that grew is MORE loot (scripts merge into an existing stack rather than
        -- making a row). One loot line proves the merge came off a corpse; the size of it
        -- is whatever the bags say, so the claim is per growth EVENT, not per unit.
        if lootWatch.claim(e.name) then
            e.stack = (e.stack or 1) + (stack - high)
        end
        e.stackHigh = stack
        dirty = true
    elseif stack < high then
        -- The high-water mark has to follow a shrink DOWN. Turning scripts in is the
        -- normal end of their life here, and a mark left at the pre-turn-in size would
        -- swallow the next several loots silently — the tally would just stop moving.
        e.stackHigh = stack
        dirty = true
    end
end

--- The merge walk: re-link entries to their live rows, record new corpse loot, and mark
--- real departures. Main-loop side only.
function M.tick(now)
    if not deps then return end
    if not ensureLoaded() then return end
    migrateScripts()
    local floor = deps.getSessionStartAcquiredSeq and deps.getSessionStartAcquiredSeq() or nil
    local items = deps.inventoryItems or {}

    -- Index the live rows once. Every entry is then O(1)-ish against them, so the walk
    -- stays linear in rows + entries rather than multiplying them every tick.
    local bySeq, byId = {}, {}
    for _, row in ipairs(items) do
        local seq = row.acquiredSeq
        if seq and bySeq[seq] == nil then bySeq[seq] = row end
        local id = tonumber(row.id) or 0
        if id > 0 then
            local list = byId[id]
            if not list then list = {}; byId[id] = list end
            list[#list + 1] = row
        end
    end
    local taken = {}    -- row -> true; a row answers for at most one entry
    local link = {}     -- entry -> row

    -- Pass 1: the seq the entry already knows, VERIFIED. Cheap, and the only link that
    -- survives more of the same item merging into this exact row.
    for _, e in ipairs(entries) do
        local row = e.rowSeq and bySeq[e.rowSeq] or nil
        if row and not taken[row] and rowIsEntry(e, row) then
            taken[row] = true
            link[e] = row
        end
    end

    -- Pass 2: identity. This is what makes "not in bags" mean it. An entry loses its seq
    -- for two ordinary reasons — the item moved slots, or the UI restarted (rowSeq is not
    -- persisted and the floor is re-stamped on snapshot load, which used to leave EVERY
    -- reloaded entry permanently departed with the item sitting right there in the bags).
    -- Neither is the item leaving, so neither should read as it. The search is the whole
    -- inventory, not just above the session floor: "is it in my bags" has nothing to do
    -- with when it arrived.
    --
    -- A row below the floor is taken outright — nothing about it can be new. Above it, the
    -- two readings are identical on paper: your augment moved, or you looted a second one
    -- just like it. The loot credit is the tiebreak. One still outstanding means a corpse
    -- has paid for a copy that nothing has recorded yet, so leave the row to the new-loot
    -- pass below and let this entry depart honestly; nothing left to pay with means this IS
    -- that copy, relocated.
    for _, e in ipairs(entries) do
        if not link[e] then
            local moved = nil
            for _, row in ipairs(byId[tonumber(e.itemId) or 0] or {}) do
                if not taken[row] and rowIsEntry(e, row) then
                    local seq = row.acquiredSeq
                    if not (floor and seq and seq >= floor) then
                        moved = row
                        break
                    elseif not moved and not lootWatch.peek(row.name) then
                        moved = row
                    end
                end
            end
            if moved then
                taken[moved] = true
                link[e] = moved
            end
        end
    end

    for _, e in ipairs(entries) do
        local row = link[e]
        if row then
            linkEntry(e, row)
        elseif not e.departed then
            -- Genuinely gone: sold, destroyed, banked, turned in.
            e.departed = true
            e.bag, e.slot = nil, nil
            -- The stack is now zero, and the high-water mark has to say so. Turning in a
            -- whole stack of scripts is the ordinary way one of these leaves, and a mark
            -- stuck at the pre-turn-in size would eat the first script looted after it.
            -- Safe against a bank round-trip because the re-link still has to claim a
            -- corpse before any of it counts.
            if e.cat == "script" then e.stackHigh = 0 end
            dirty = true
        end
    end

    -- New loot. A row nothing has claimed, above the session floor, of a category this
    -- record tracks — and able to pay for itself with a corpse. Without that last clause
    -- an augment popped out of a socket queued up as tonight's loot.
    if floor then
        for _, row in ipairs(items) do
            local seq = row.acquiredSeq
            if seq and seq >= floor and not taken[row] then
                local cat = classify(row)
                if cat and lootWatch.claim(row.name) then
                    taken[row] = true
                    local reason, choice
                    if cat ~= "script" then reason, choice = preemptReason(row, cat) end
                    -- Read the row's augType ONCE, here, while the row is live.
                    -- It is a lazy field already resolved by buildAugmentIndex at
                    -- scan time, so this is a table hit, not a TLO read — and
                    -- capturing it now is what lets the panel answer "what does
                    -- this fit" for the rest of the record's life.
                    local augType = 0
                    if cat == "aug" then augType = tonumber(row.augType) or 0 end
                    entries[#entries + 1] = {
                        uid = newUid(), name = row.name or "?", cat = cat,
                        augType = augType,
                        -- Carried as a FIELD, not inferred from the sorted reason:
                        -- NoDrop no longer pre-empts (it is a property, not a call),
                        -- but it still has to block the Junk chip.
                        nodrop = (row.nodrop == true) or nil,
                        itemId = tonumber(row.id) or 0,
                        value = tonumber(row.totalValue or row.value) or 0,
                        stack = tonumber(row.stackSize) or 1,
                        stackHigh = tonumber(row.stackSize) or 1,
                        state = (cat == "script") and "tally" or (reason and "sorted" or "call"),
                        choice = choice, reason = reason,
                        at = os.time(), bag = row.bag, slot = row.slot,
                        rowSeq = seq,
                    }
                    startedAt = startedAt or os.time()
                    dirty = true
                end
            end
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
    -- A script has no call to make: you keep it and the Scripts window turns it in. It
    -- never reaches the queue, so this guard is belt to the walk's braces.
    if e.cat == "script" then return false, "kept for turn-in" end
    if e.state == "sorted" and choice ~= "undo" then return false, "already sorted" end
    if choice == "reroll" then
        if (e.itemId or 0) <= 0 then return false, "no item id" end
        if e.departed then return false, "not in bags" end
    elseif choice == "junk" then
        if e.nodrop then return false, "NoDrop" end
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
    entries, undoStack = {}, {}
    startedAt = nil
    dirty = true
    save(0)
end

-- ---------------------------------------------------------------- reads

--- Cell + panel counts. Amber = needs a call; scripts have no decision and stay white.
---
--- `looted` is the DECISION RECORD — augs and mythics — so the panel's truth line is an
--- identity: looted = needCall + sorted, and every row it claims to be counting is a row
--- you can actually see in one of the two lists. Scripts are counted apart, in `scripts`,
--- because the panel says what they are on its own line: a tally of what you collected,
--- not a queue with anything in it.
function M.getCounts()
    local c = {
        augsCall = 0, augsTotal = 0,
        mythicsCall = 0, mythicsTotal = 0,
        scripts = 0,
        sorted = 0, looted = 0, needCall = 0,
        startedAt = startedAt,
        canUndo = #undoStack > 0,
    }
    for _, e in ipairs(entries) do
        if e.cat == "script" then
            c.scripts = c.scripts + (e.stack or 1)
        else
            c.looted = c.looted + 1
            if e.state == "sorted" then
                c.sorted = c.sorted + 1
            else
                c.needCall = c.needCall + 1
            end
            if e.cat == "aug" then
                c.augsTotal = c.augsTotal + 1
                if e.state == "call" then c.augsCall = c.augsCall + 1 end
            elseif e.cat == "mythic" then
                c.mythicsTotal = c.mythicsTotal + 1
                if e.state == "call" then c.mythicsCall = c.mythicsCall + 1 end
            end
        end
    end
    return c
end

--- NEEDS A CALL, by value best first (triage only pays if the top row is worth
--- thinking about). Returns a COPY — the panel must not shift under ImGui mid-render.
--- Scripts are in neither list: "tally" is not "call" and not "sorted".
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

--- Test seam: the raw entry list, tally rows included (getCallList/getSortedList show
--- neither, which is exactly what the tally tests need to reach past).
function M._entriesForTests() return entries end

--- Test seam: reset in-memory state (never touches the file).
function M._resetForTests()
    entries, undoStack = {}, {}
    startedAt, loadedFor, dirty, lastSaveAt, uidCounter = nil, nil, false, 0, 0
end

return M
