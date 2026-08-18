--[[
    dream_log.lua — dream wave 1: the river's memory for what no service stores.

    session_record already keeps every aug/mythic/script with a timestamp, a state,
    and the reason it sorted — the river renders those directly. What nothing stores
    is the RUN EDGES: "a loot run started/finished", "an Auto Sell finished". This
    module subscribes to macro_bridge's existing pub/sub and keeps a small capped
    ring of exactly those rows.

    Always on (not gated by the river's flag) ON PURPOSE: the cost is a handful of
    table inserts per run edge, and it means the hour you played BEFORE flipping the
    experiment on is already in the river. The observer rule holds everywhere else:
    no writes to any shared state, no file, no TLO, no ImGui; a reload starts the
    log empty (session_record is the durable record, this is the session's motion).

    Loot tallies (corpse count, value, best take) finalize a few frames after the
    complete event fires (the chunked session read), so a loot row captures lazily:
    getRows() fills it from uiState once the row is CAPTURE_SETTLE_MS old.
]]

local M = {}

local MAX_ROWS = 200
local CAPTURE_SETTLE_MS = 2500

local deps = nil          -- { macroBridge, uiState, gettime }
local rows = {}           -- newest LAST internally; getRows returns newest first
local subscribed = false

local function push(row)
    rows[#rows + 1] = row
    while #rows > MAX_ROWS do table.remove(rows, 1) end
end

local function nowMs()
    return (deps and deps.gettime and deps.gettime()) or 0
end

--- Fill a loot-complete row from the settled uiState tallies, once.
local function finalizeLootRow(r)
    local u = deps and deps.uiState
    if not u then r.pending = nil return end
    r.corpses = tonumber(u.lootRunCorpsesLooted) or 0
    r.value = tonumber(u.lootRunTotalValue) or 0
    r.items = (type(u.lootRunLootedItems) == "table" and #u.lootRunLootedItems) or 0
    r.best = tostring(u.lootRunBestItemName or "")
    r.bestValue = tonumber(u.lootRunBestItemValue) or 0
    r.skipped = tonumber(u.lootRunSkipped) or 0
    r.pending = nil
end

function M.init(d)
    deps = d
    rows = {}
    subscribed = false
    local mb = deps and deps.macroBridge
    if mb and mb.subscribe then
        -- macro_bridge.init cleared subscribers before this ran (app.lua orders it so);
        -- callbacks are pcall'd by the bridge and self-remove on error, so a bug here
        -- can never break the emitters.
        mb.subscribe('loot:started', function()
            push({ at = os.time(), atMs = nowMs(), kind = "loot_start" })
        end)
        mb.subscribe('loot:complete', function()
            push({ at = os.time(), atMs = nowMs(), kind = "loot_end", pending = true })
        end)
        mb.subscribe('sell:started', function()
            push({ at = os.time(), atMs = nowMs(), kind = "sell_start" })
        end)
        mb.subscribe('sell:complete', function(data)
            push({ at = os.time(), atMs = nowMs(), kind = "sell_end",
                   failed = (data and tonumber(data.failedCount)) or 0 })
        end)
        subscribed = true
    end
    -- MANUAL loot (field round 1: the whole test was a hand-looted corpse and the
    -- river sat empty — the bridge events above are MACRO edges and fire for nothing
    -- else). The game's own "You have looted" line is the one signal hand-looting
    -- always produces (loot_watch's insight); this registers its OWN event on the
    -- same line — no shared-code edits, both handlers fire independently. The parse
    -- mirrors loot_watch's forgiving shape: peel the chat dashes and the sentence
    -- period, keep the article.
    if deps and deps.mqEvent then
        pcall(deps.mqEvent, "CooptUIDreamLoot", "#*#You have looted#*#", function(line)
            local rest = type(line) == "string" and line:match("[Yy]ou have looted%s+(.+)$") or nil
            if not rest or rest == "" then return end
            rest = rest:gsub("%-%-%s*$", ""):gsub("%s+$", ""):gsub("%.$", "")
            if rest == "" then return end
            M.noteLooted(rest)
        end)
    end
end

--- One hand-looted item. Public so the suite (and any future feed) can push the
--- same row the chat event does.
function M.noteLooted(name, demo)
    push({ at = os.time(), atMs = nowMs(), kind = "looted",
           name = tostring(name or ""), demo = demo or nil })
end

--- Demo rows for /itemui experiments demo: the river's whole vocabulary, honestly
--- labeled, so the window is verifiable without waiting for a run.
function M.demo()
    push({ at = os.time(), atMs = nowMs(), kind = "sell_end", failed = 1, demo = true })
    push({ at = os.time(), atMs = nowMs(), kind = "loot_end", corpses = 6, items = 12,
           value = 2108, best = "Demo Take of the Day", bestValue = 2100, skipped = 2, demo = true })
    M.noteLooted("A Demo Trinket", true)
end

--- Newest-first copy. Loot rows past the settle age finalize from uiState here —
--- render-driven, so a closed river window costs nothing per frame.
function M.getRows()
    local t = nowMs()
    local out = {}
    for i = #rows, 1, -1 do
        local r = rows[i]
        if r.pending and (t - (r.atMs or 0)) >= CAPTURE_SETTLE_MS then
            finalizeLootRow(r)
        end
        out[#out + 1] = r
    end
    return out
end

function M.isSubscribed()
    return subscribed
end

function M._resetForTests()
    rows = {}
end

--- Test seam: push a raw row (the suites drive edges without a bridge).
function M._pushForTests(row)
    push(row)
end

return M
