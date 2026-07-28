--[[
    dock_state.lua — everything the bars display, aggregated on the main-loop tick.

    The bars are redrawn every frame, so nothing here may be called from a render callback.
    tick(now) runs from main_loop; the views only ever read get().

    Two rules shape this file:

      * ONE COARSE CLOCK. Segments refresh at DOCK_TICK_MS (250 ms), not per frame. Timers
        read better at 4 Hz than as a blur of decimals, and it keeps the TLO cost bounded.

      * STAGGERED SUB-AGGREGATIONS. A single tick must never walk buffs + songs + auras
        (~40-70 TLO reads) AND ten packs of free slots (one read per slot) AND a full
        sellItems pass. That burst is exactly the stutter SELL_STATUS_DRAIN_PER_TICK and
        SESSION_MERGE_PER_TICK were introduced to remove. Each expensive walk has its own
        interval and only one runs per tick.

    DEMAND FLAGS. The expensive walks only run when something is actually displaying them:
    a bar segment that is enabled, or (for effects) the Effects window being open. In
    classic mode with the bars off, tick() does almost nothing. Consumers call
    M.request*() each frame they need the data; the flag is consumed by the next tick.
]]

local mq = require('mq')
local constants = require('itemui.constants')
local coopuiPlugin = require('itemui.utils.coopui_plugin')
local itemHelpers = require('itemui.utils.item_helpers')

local M = {}

local d                     -- main-loop deps table (set by init)
local T = constants.TIMING

local MAX_SONG_SLOTS = 30
local MAX_AURA_SLOTS = 8
local EXPIRING_SECS = 300   -- amber under five minutes, per mockup 12b
local EXPIRING_SHOWN = 8    -- rows the popover lists before "+N more"

-- The published snapshot. One table, replaced field-wise (never swapped) so a view holding
-- a reference across a frame cannot see a half-built state.
local snap = {
    tickedAt = 0,
    -- status
    pluginPresent = false,
    errorCount = 0,
    sellRunning = false,
    lootRunning = false,
    -- bags
    bagItems = 0, bagSlots = 0, bagFree = nil, bagPct = 0,
    weight = nil, maxWeight = nil, weightKnown = false,
    -- sell
    sellCount = 0, sellTotal = 0, keepCount = 0, protectCount = 0,
    keepInSellQueue = 0, augmentSellCount = 0, merchantOpen = false,
    sellGroups = {},          -- { {reason=, count=, total=}, ... } for the popover
    -- sell run in progress (macro sell.mac OR Lua batch — the bar shows either)
    sellRunTotal = 0, sellRunCurrent = 0, sellRunFrac = 0, sellRunValue = 0,
    -- loot
    lootState = "idle",       -- idle | looting | decision | done | problem
    lootCorpse = 0, lootTotalCorpses = 0, lootTaken = 0, lootSkipped = 0,
    lootCorpseName = nil,     -- current corpse NAME, or nil; shown in the hover tooltip
    lootRunValue = 0, lootDecisionName = nil, lootDecisionSecs = nil,
    lootProblem = nil,
    -- buffs
    buffCount = 0, songCount = 0, auraCount = 0, maxBuffs = 30,
    expiring = {},            -- { {name=, seconds=, icon=, kind=, index=}, ... } soonest first
    expiringCount = 0,
    buffs = {}, songs = {}, auras = {},
    effectsWalkedAt = 0,      -- 0 = never walked; distinguishes a cold cache from "no buffs"
    clickyBySpell = {},       -- spellId -> {bag, slot, name, ready}; drives popover Recast
    -- xp / aa / scripts
    exp = 0, aaTotal = 0, scriptAA = 0, platinum = 0,
    -- session
    sessionPlat = 0, sessionLooted = 0, sessionSold = 0,
}

-- Per-walk clocks, so each expensive aggregation keeps its own cadence.
local lastAt = { bags = 0, buffs = 0, stats = 0, sell = 0, clicky = 0 }
local demand = { bags = false, buffs = false, stats = false, sell = false, clicky = false }
local demandNext = { bags = false, buffs = false, stats = false, sell = false, clicky = false }

-- Session totals survive individual runs. uiState.lootRunTotalValue is PER-RUN and is
-- zeroed at run start (main_loop phase 5 and macro_bridge's IPC loot_start), so sampling
-- the live counter loses the previous run entirely. Accumulate on the finish edge instead.
local session = { looted = 0, sold = 0 }
local lootWasRunning = false
-- Sell-run edge trackers. The macro path (sell.mac) never calls M.recordSold — its per-item
-- values arrive over IPC into uiState.sellRunSoldItems — so vendor income from a macro sell
-- is banked here on the run's FINISH edge. The batch path banks per sale via recordSold, so
-- its run value is the session.sold delta since the run started.
local macroSellWasRunning = false
local batchSellWasRunning = false
local batchSoldBase = 0

function M.init(deps)
    d = deps
end

-- ---------------------------------------------------------------------------
-- Demand
-- ---------------------------------------------------------------------------

local function request(kind)
    demandNext[kind] = true
end

function M.requestBags()  request("bags")  end
function M.requestBuffs() request("buffs") end
function M.requestStats() request("stats") end
function M.requestSell()  request("sell")  end
--- Only the open buffs popover needs this, and only while it is open.
function M.requestClickyMap() request("clicky") end

-- ---------------------------------------------------------------------------
-- Effects (buffs / songs / auras)
--
-- Lifted out of views/effects.lua so the bar's buffs segment and the Effects window share
-- ONE TLO walk instead of doing 40-70 reads each. effects.lua now calls M.getEffects().
-- ---------------------------------------------------------------------------

local function readEffect(kind, i)
    local Me = mq.TLO and mq.TLO.Me
    if not Me then return nil end
    local b = (kind == "buff") and (Me.Buff and Me.Buff(i)) or (Me.Song and Me.Song(i))
    if not b or b() == nil then return nil end
    local e = { kind = kind, index = i, name = nil, seconds = nil, permanent = false, hitCount = 0, icon = nil, spellId = nil }
    pcall(function() e.name = b.Name() end)
    if not e.name or e.name == "" then return nil end
    pcall(function()
        local dur = b.Duration
        local secs = dur and dur.TotalSeconds and dur.TotalSeconds()
        if secs ~= nil then e.seconds = tonumber(secs) end
    end)
    if not e.seconds or e.seconds < 0 then
        e.seconds = nil
        e.permanent = true
    end
    pcall(function() e.hitCount = tonumber(b.HitCount()) or 0 end)
    pcall(function()
        local sp = b.Spell
        if sp and sp() ~= nil then
            e.spellId = tonumber(sp.ID())
            e.icon = tonumber(sp.SpellIcon())
            local desc = sp.Description and sp.Description()
            if desc and desc ~= "" and desc ~= "NULL" then e.description = desc end
        end
    end)
    pcall(function()
        local c = b.Caster and b.Caster()
        if c and c ~= "" and c ~= "NULL" then e.caster = c end
    end)
    return e
end

local function walkEffects()
    local Me = mq.TLO and mq.TLO.Me
    if not Me then return end
    local maxBuffs = 30
    pcall(function() maxBuffs = tonumber(Me.MaxBuffSlots()) or 30 end)

    local buffs, songs, auras = {}, {}, {}
    for i = 1, maxBuffs do
        local e = readEffect("buff", i)
        if e then buffs[#buffs + 1] = e end
    end
    for i = 1, MAX_SONG_SLOTS do
        local e = readEffect("song", i)
        if e then songs[#songs + 1] = e end
    end
    for i = 1, MAX_AURA_SLOTS do
        local ok, name = pcall(function()
            local a = Me.Aura and Me.Aura(i)
            return a and a()
        end)
        if ok and name and name ~= "" and name ~= "NULL" then
            auras[#auras + 1] = { kind = "aura", index = i, name = name, permanent = true, hitCount = 0 }
        end
    end

    -- Expiring list: timed effects only, soonest first. Amber appears in the view when
    -- expiringCount > 0, so a healthy character sees plain grey.
    local expiring = {}
    for _, e in ipairs(buffs) do
        if not e.permanent and e.seconds and e.seconds <= EXPIRING_SECS then expiring[#expiring + 1] = e end
    end
    for _, e in ipairs(songs) do
        if not e.permanent and e.seconds and e.seconds <= EXPIRING_SECS then expiring[#expiring + 1] = e end
    end
    table.sort(expiring, function(a, b) return (a.seconds or 0) < (b.seconds or 0) end)

    snap.buffs, snap.songs, snap.auras = buffs, songs, auras
    snap.buffCount, snap.songCount, snap.auraCount = #buffs, #songs, #auras
    snap.maxBuffs = maxBuffs
    -- Stamped so consumers can tell "walked, and the character genuinely has no buffs" from
    -- "never walked yet". Without it, a buff-less character looks identical to a cold cache
    -- and views/effects.lua would fall back to its own walk forever -- two walks, not one.
    snap.effectsWalkedAt = mq.gettime()
    snap.expiringCount = #expiring
    local shown = {}
    for i = 1, math.min(#expiring, EXPIRING_SHOWN) do shown[i] = expiring[i] end
    snap.expiring = shown
end

--- Shared effects cache for views/effects.lua. Marks demand so the walk keeps running
--- while that window is open, and returns the same tables the bar reads.
--- Returns walked, buffs, songs, auras, maxBuffs. `walked` is false until the tick has done
--- at least one pass, which is the signal a consumer needs to decide between trusting the
--- shared cache and doing its own walk.
function M.getEffects()
    request("buffs")
    return (snap.effectsWalkedAt or 0) > 0, snap.buffs, snap.songs, snap.auras, snap.maxBuffs
end

--- Force the next tick to re-walk effects (e.g. right after /removebuff, so the row goes
--- away promptly instead of lingering for up to DOCK_SLOW_BUFFS_MS).
function M.invalidateEffects()
    lastAt.buffs = 0
    demandNext.buffs = true
end

-- ---------------------------------------------------------------------------
-- Clicky map: spell id -> the inventory item that casts it
--
-- This is what makes the buffs popover's per-row Recast real rather than decorative. Match
-- is by SPELL ID, not name: readEffect already captures e.spellId, and an item's clicky
-- spell id comes from itemHelpers.getItemSpellId, so the pairing is exact.
--
-- Cost: getItemSpellId MEMOISES onto the item row (item_helpers.lua caches item[key],
-- including a 0 for "no clicky"), so only the first pass over a freshly scanned inventory
-- touches TLOs -- after that this is table reads. Still on its own slow clock, and only
-- while a buffs popover is actually open.
-- ---------------------------------------------------------------------------

local function walkClickyMap()
    local items = d and d.inventoryItems or {}
    local map = {}
    for _, it in ipairs(items) do
        if it.bag and it.slot then
            local ok, sid = pcall(itemHelpers.getItemSpellId, it, "Clicky")
            if ok and type(sid) == "number" and sid > 0 and not map[sid] then
                local ready = 0
                local okT, r = pcall(itemHelpers.getTimerReady, it.bag, it.slot, "inv")
                if okT and type(r) == "number" then ready = r end
                map[sid] = { bag = it.bag, slot = it.slot, name = it.name, ready = ready }
            end
        end
    end
    snap.clickyBySpell = map
end

-- ---------------------------------------------------------------------------
-- Bags
-- ---------------------------------------------------------------------------

local function walkBags()
    local items = d and d.inventoryItems
    snap.bagItems = items and #items or 0

    -- countFreeInvSlots walks ten packs with a TLO read per slot, so it rides the slow
    -- clock. Total slots are derived from it plus the item count, which needs no extra reads.
    local itemOps = d and d.itemOps
    local free = nil
    if itemOps and itemOps.countFreeInvSlots then
        local ok, n = pcall(itemOps.countFreeInvSlots)
        if ok and type(n) == "number" then free = n end
    end
    snap.bagFree = free
    if free then
        snap.bagSlots = snap.bagItems + free
        snap.bagPct = snap.bagSlots > 0 and (snap.bagItems / snap.bagSlots) or 0
    end
end

-- ---------------------------------------------------------------------------
-- Sell offer
--
-- The per-row inputs (willSell, totalValue, inKeep, isProtected, sellReason) are already
-- cached on sellItems rows by scan + computeAndAttachSellStatus. Only the AGGREGATE was
-- missing: views/sell.lua:175-194 recomputes it EVERY FRAME. Same single pass, moved here.
-- ---------------------------------------------------------------------------

local function walkSell()
    local items = d and d.sellItems or {}
    local keepCount, sellCount, protectCount = 0, 0, 0
    local sellTotal, keepInSellQueue, augmentSellCount = 0, 0, 0
    local groups, order = {}, {}
    for _, it in ipairs(items) do
        if it.inKeep then keepCount = keepCount + 1 end
        if it.willSell then
            sellCount = sellCount + 1
            local v = it.totalValue or 0
            sellTotal = sellTotal + v
            if it.inKeep then keepInSellQueue = keepInSellQueue + 1 end
            if it.type and it.type:lower() == "augmentation" then augmentSellCount = augmentSellCount + 1 end
            -- Group by the rule that decided it — this is what the popover shows, and it is
            -- where players learn their own rules (mockup 11d).
            local reason = (it.sellReason and it.sellReason ~= "") and it.sellReason or "no rule matched"
            local g = groups[reason]
            if not g then
                g = { reason = reason, count = 0, total = 0 }
                groups[reason] = g
                order[#order + 1] = g
            end
            g.count = g.count + 1
            g.total = g.total + v
        end
        if it.isProtected then protectCount = protectCount + 1 end
    end
    table.sort(order, function(a, b) return a.total > b.total end)
    snap.keepCount, snap.sellCount, snap.protectCount = keepCount, sellCount, protectCount
    snap.sellTotal, snap.keepInSellQueue, snap.augmentSellCount = sellTotal, keepInSellQueue, augmentSellCount
    snap.sellGroups = order
end

-- ---------------------------------------------------------------------------
-- Loot — all five states of mockup 12a, from real uiState
-- ---------------------------------------------------------------------------

local function readLoot(now)
    local uiState = d and d.uiState
    if not uiState then return end
    local running = d.lootMacState and d.lootMacState.lastRunning or false
    snap.lootRunning = running

    -- Field types matter here and two of them are not what the names suggest:
    --   lootRunCorpsesLooted is the corpse COUNT (a number)
    --   lootRunCurrentCorpse is the corpse NAME (a string, "" when idle) -- NOT an index
    --   lootRunLootedItems is the item LIST (a table) -- NOT a count
    -- Reading the last two as numbers pinned the whole segment at "corpse 0/N . 0 taken".
    -- views/loot_ui.lua:384-404 is the reference for which field means what.
    snap.lootCorpse = tonumber(uiState.lootRunCorpsesLooted) or 0
    snap.lootTotalCorpses = tonumber(uiState.lootRunTotalCorpses) or 0
    local looted = uiState.lootRunLootedItems
    snap.lootTaken = (type(looted) == "table") and #looted or 0
    local corpseName = uiState.lootRunCurrentCorpse
    snap.lootCorpseName = (type(corpseName) == "string" and corpseName ~= "") and corpseName or nil
    snap.lootRunValue = tonumber(uiState.lootRunTotalValue) or 0
    -- THIS run's skips, set by main_loop when it reads loot_skipped.ini. Deliberately not
    -- #uiState.skipHistory: that buffer accumulates across runs and is reloaded from disk,
    -- so it would report a lifetime total as if it were this run's.
    snap.lootSkipped = tonumber(uiState.lootRunSkipped) or 0

    -- 3 · decision due — a mythical is waiting on Take/Pass. The alert table PERSISTS after
    -- the decision is made (with .decision set to take/pass), so gate on pending exactly the
    -- way views/loot_ui.lua:258-259 does, or the segment would stay alert forever.
    local alert = uiState.lootMythicalAlert
    local alertName = (type(alert) == "table") and alert.itemName or nil
    if alertName and alertName ~= "" then
        local decision = (alert.decision or ""):lower()
        if decision == "" or decision == "pending" then
            snap.lootState = "decision"
            snap.lootDecisionName = alertName
            -- lootMythicalDecisionStartAt is os.time() -- SECONDS, set at main_loop.lua:247 --
            -- while `now` is mq.gettime() milliseconds. Subtracting them would be off by
            -- ~1000x, so compare in the same clock the value was written in.
            local startedAt = tonumber(uiState.lootMythicalDecisionStartAt)
            local nowSecs = os.time and os.time() or nil
            snap.lootDecisionSecs = (startedAt and startedAt > 0 and nowSecs)
                and math.max(0, nowSecs - startedAt) or nil
            snap.lootProblem = nil
            return
        end
    end
    snap.lootDecisionName, snap.lootDecisionSecs = nil, nil

    -- 5 · a problem instead of a result — stays alert until dealt with. Bags full is the case
    -- the mockup calls out, but it needs two guards it did not have:
    --
    --   * itemOps.countFreeInvSlots returns 0, NOT nil, when the inventory TLO is unreadable
    --     (item_ops.lua:595 early-returns 0, and every pack reads Container() as 0 while
    --     zoning). A raw free==0 therefore fires on every zone. Requiring a plausible slot
    --     total AND at least one known item distinguishes "really full" from "cannot read".
    --   * It is a LOOT problem, so it only belongs on the loot slot while looting is what the
    --     player is doing. Otherwise a genuinely full bag would sit there red forever, with a
    --     Stop/Sell strip, during ordinary play. Bag pressure already has its own amber in the
    --     bags segment for that.
    local plausible = (snap.bagSlots or 0) > 0 and (snap.bagItems or 0) > 0
    local lootingContext = running or uiState.lootRunFinished
    if plausible and snap.bagFree == 0 and lootingContext then
        snap.lootState = "problem"
        snap.lootProblem = "bags full"
        return
    end
    snap.lootProblem = nil

    if running then
        snap.lootState = "looting"       -- 2 · looting
    elseif uiState.lootRunFinished then
        snap.lootState = "done"          -- 4 · finished (the view fades it)
    else
        snap.lootState = "idle"          -- 1 · idle
    end
end

-- ---------------------------------------------------------------------------
-- Session accumulator
-- ---------------------------------------------------------------------------

local function accumulateSession(now)
    local uiState = d and d.uiState
    local running = d and d.lootMacState and d.lootMacState.lastRunning or false
    -- Add on the FINISH edge: the run counter is authoritative at that point and is about
    -- to be zeroed by the next run's start.
    if lootWasRunning and not running and uiState then
        session.looted = session.looted + (tonumber(uiState.lootRunTotalValue) or 0)
    end
    lootWasRunning = running
    snap.sessionLooted = session.looted
    snap.sessionSold = session.sold
    snap.sessionPlat = session.looted + session.sold
end

--- Sell-run progress + session banking for the macro path. Cheap cached reads only while
--- idle; getSellProgress (one TLO + throttled INI read) is called only while a macro sell
--- is actually running.
local function readSellRun()
    local sm = d and d.sellMacState
    local uiState = d and d.uiState
    local macroRunning = (sm and sm.lastRunning) or false
    local batchRunning = (sm and sm.luaRunning) or false
    snap.sellRunning = macroRunning or batchRunning

    if batchRunning then
        if not batchSellWasRunning then batchSoldBase = session.sold end
        snap.sellRunTotal = tonumber(sm.total) or 0
        snap.sellRunCurrent = tonumber(sm.current) or 0
        snap.sellRunFrac = tonumber(sm.smoothedFrac) or 0
        snap.sellRunValue = session.sold - batchSoldBase
    elseif macroRunning then
        local p = d.macroBridge and d.macroBridge.getSellProgress and d.macroBridge.getSellProgress()
        snap.sellRunTotal = (p and tonumber(p.total)) or 0
        snap.sellRunCurrent = (p and tonumber(p.current)) or 0
        snap.sellRunFrac = (p and tonumber(p.smoothedFrac)) or 0
        local sold = 0
        local list = uiState and uiState.sellRunSoldItems
        if type(list) == "table" then
            for _, it in ipairs(list) do sold = sold + (tonumber(it.value) or 0) end
        end
        snap.sellRunValue = sold
    else
        -- Macro finish edge: bank the run's vendor income into the session total. The batch
        -- path needs nothing here — recordSold already banked each sale as it happened.
        if macroSellWasRunning and uiState and type(uiState.sellRunSoldItems) == "table" then
            for _, it in ipairs(uiState.sellRunSoldItems) do
                session.sold = session.sold + (tonumber(it.value) or 0)
            end
        end
        snap.sellRunTotal, snap.sellRunCurrent, snap.sellRunFrac, snap.sellRunValue = 0, 0, 0, 0
    end
    macroSellWasRunning = macroRunning
    batchSellWasRunning = batchRunning
end

--- Called by sell_batch when a sale completes, so the session total covers vendor income
--- and not just loot.
function M.recordSold(value)
    local v = tonumber(value) or 0
    if v > 0 then session.sold = session.sold + v end
end

function M.resetSession()
    session.looted, session.sold = 0, 0
    snap.sessionLooted, snap.sessionSold, snap.sessionPlat = 0, 0, 0
end

-- ---------------------------------------------------------------------------
-- Tick
-- ---------------------------------------------------------------------------

--- One aggregation pass. `now` is milliseconds, threaded in from main_loop — do not call
--- mq.gettime() in here.
function M.tick(now)
    if not d then return end
    if (now - snap.tickedAt) < T.DOCK_TICK_MS then return end
    snap.tickedAt = now

    -- Consume the demand raised since the last tick.
    for k in pairs(demand) do
        demand[k] = demandNext[k]
        demandNext[k] = false
    end

    -- In classic mode the bars never render, so none of the bar-only bookkeeping below is
    -- worth doing. The demand-driven walks further down still run, because views/effects.lua
    -- consumes the shared buffs walk in BOTH modes -- that sharing is the whole reason the
    -- Effects window and the bar do one TLO pass between them instead of two.
    local lc = d.layoutConfig
    local barsOn = lc and tostring(lc.UIMode or "classic") == "bars"

    if barsOn then
        -- Cheap every-tick reads: no TLO calls, just cached state and counters.
        snap.pluginPresent = coopuiPlugin.getPlugin() ~= nil
        local diag = require('itemui.core.diagnostics')
        snap.errorCount = (diag and diag.getErrorCount and diag.getErrorCount()) or 0
        -- The cached window state main_loop already maintains, NOT isMerchantWindowOpen():
        -- that one hits a window TLO, and this runs four times a second.
        snap.merchantOpen = (d.getLastMerchantState and d.getLastMerchantState()) == true
    end

    -- Expensive walks, staggered: at most ONE per tick, longest-overdue first.
    local due = {}
    if demand.sell and (now - lastAt.sell) >= T.DOCK_TICK_MS then
        due[#due + 1] = { k = "sell", over = now - lastAt.sell, fn = walkSell }
    end
    if demand.bags and (now - lastAt.bags) >= T.DOCK_SLOW_BAGS_MS then
        due[#due + 1] = { k = "bags", over = now - lastAt.bags, fn = walkBags }
    end
    if demand.buffs and (now - lastAt.buffs) >= T.DOCK_SLOW_BUFFS_MS then
        due[#due + 1] = { k = "buffs", over = now - lastAt.buffs, fn = walkEffects }
    end
    if demand.clicky and (now - lastAt.clicky) >= T.DOCK_SLOW_CLICKY_MS then
        due[#due + 1] = { k = "clicky", over = now - lastAt.clicky, fn = walkClickyMap }
    end
    if demand.stats and (now - lastAt.stats) >= T.DOCK_SLOW_STATS_MS then
        due[#due + 1] = { k = "stats", over = now - lastAt.stats, fn = function()
            local cs = require('itemui.components.character_stats')
            local s = cs.getSnapshot and cs.getSnapshot(now)
            if s then
                snap.exp, snap.aaTotal = s.exp, s.aaPointsTotal
                snap.scriptAA, snap.platinum = s.scriptAA, s.platinum
                snap.weight, snap.maxWeight = s.weight, s.maxWeight
                snap.weightKnown = s.weightKnown
            end
        end }
    end
    if #due > 0 then
        table.sort(due, function(a, b) return a.over > b.over end)
        local pick = due[1]
        lastAt[pick.k] = now
        pcall(pick.fn)
    end

    if barsOn then
        -- Sell-run progress must precede accumulateSession so a macro run's income banked on
        -- its finish edge is published in the same tick.
        pcall(readSellRun)
        -- Loot and session are pure cached reads, so they run every tick and progress stays
        -- live. readLoot consumes snap.bagFree, so it must follow the bags walk above.
        pcall(readLoot, now)
        -- accumulateSession tracks the loot-run finish EDGE, so it must see every tick while
        -- the bars are on or a completed run's total is missed entirely.
        pcall(accumulateSession, now)
    end
end

--- The published snapshot. Read-only for callers: the bars must never mutate it.
function M.get()
    return snap
end

return M
