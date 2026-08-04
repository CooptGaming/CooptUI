--[[
    AA Data Service - Build and cache the list of Alternate Advancement abilities.
    Part of CoOpt UI Items Companion. Single responsibility: build list from MQ, cache, fingerprint, refresh.
--]]

local mq = require('mq')
local coopuiPlugin = require('itemui.utils.coopui_plugin')

local M = {}

-- Plugin AA filter: the client's own CanSeeAbility (what the native AA window
-- shows for THIS character - other classes' lines and unavailable specials
-- excluded, including this server's multi-class rules). One-shot detection.
local paCache
local function plugAA()
    if paCache ~= nil then return paCache or nil end
    local p = coopuiPlugin.getPlugin()
    paCache = (p and type(p.aa) == 'table' and type(p.aa.getVisibleAAIds) == 'function') and p.aa or false
    return paCache or nil
end

-- Cache: list of AA records, fingerprint, last refresh time
local aaList = {}
-- Tab selection (1=General, 2=Archetype, 3=Class, 4=Special); owned here per MASTER_PLAN 4.2
local aaTab = 1
local lastFingerprint = ""
local lastRefreshTime = 0
-- The AA id space on emu servers is SPARSE and class/archetype ids live far above
-- the low General block (the old 1..2000 scan with a 50-gap early break is why only
-- General AAs ever appeared). Scan the whole 16-bit id space with no gap bail,
-- chunked across main-loop ticks so a rebuild never hitches a frame.
local MAX_AA_ID = 65535
local IDS_PER_PUMP = 2500
-- Wall-clock budget per pump. The id cap alone sized the chunk for the sparse
-- full-range scan (most ids miss, cheap) - but on the plugin path EVERY id is a
-- hit with a full record build behind it, so one 2500-id chunk was thousands of
-- TLO evaluations in a single tick: the several-second freeze on window open.
-- Time is the honest budget; the id cap stays as a backstop.
local PUMP_BUDGET_MS = 8
local build = nil  -- { cursor, list, seen, ids?, truth? } while an incremental rebuild is running
-- Last truth maps fetched from the plugin (owned ranks + per-rank table ids and
-- costs). Kept for noteTrained's optimistic post-buy bump between rescans.
local lastTruth = nil

--- Fetch the plugin's truth maps in one place: owned ranks (PcProfile AAList),
--- per-rank table ids (what /alt buy actually takes - the global TLO's first
--- group match is NOT rank 1 on this server's custom table), and per-rank
--- costs. Returns nil when the plugin or its owned-ranks store is unavailable;
--- rank indexes and costs are optional extras on top of owned.
local function fetchTruth()
    local pa = plugAA()
    if not pa or type(pa.getOwnedRanks) ~= 'function' then return nil end
    local ok, owned = pcall(pa.getOwnedRanks)
    if not ok or type(owned) ~= 'table' then return nil end
    local truth = { owned = owned }
    if type(pa.getGroupRankIndexes) == 'function' then
        local okR, m = pcall(pa.getGroupRankIndexes)
        if okR and type(m) == 'table' then truth.rankIdx = m end
    end
    if type(pa.getGroupRankCosts) == 'function' then
        local okC, m = pcall(pa.getGroupRankCosts)
        if okC and type(m) == 'table' then truth.rankCosts = m end
    end
    return truth
end

--- Recompute the SPEND fields (nextIndex, cost, canTrain) from a record's rank
--- and the truth maps. This is the fix for "Train doesn't work" and "Can
--- Purchase lies": the TLO's character-side reads resolve the level-appropriate
--- entry, so on partially-trained lines its Rank/CanTrain/NextIndex describe an
--- ability the character does not own - and /alt buy with that NextIndex gets
--- the server's "Unable to train". Rank must already be the OWNED rank.
local function computeDerived(rec, truth)
    local maxR = tonumber(rec.maxRank) or 0
    local rank = tonumber(rec.rank) or 0
    if maxR > 0 and rank >= maxR then
        rec.nextIndex = 0
        rec.canTrain = false
        return
    end
    local nextR = rank + 1
    local grpIdx = truth.rankIdx and truth.rankIdx[rec.id] or nil
    local grpCosts = truth.rankCosts and truth.rankCosts[rec.id] or nil
    -- Prereq from owned truth: requiresAbility is a GROUP-ID string; the
    -- requirement is met when that group's owned rank reaches the stated rank.
    local reqGid = tonumber(rec.requiresAbility) or 0
    local prereqOk = reqGid == 0
        or ((tonumber(truth.owned[reqGid]) or 0) >= (tonumber(rec.requiresAbilityPoints) or 1))
    if grpIdx then
        local ix = tonumber(grpIdx[nextR])
        -- No table entry for the next rank = nothing buyable there (auto-granted
        -- lines land here); a canTrain without a buyable id is a lie.
        rec.nextIndex = (ix and ix > 0) and ix or 0
        rec.canTrain = prereqOk and rec.nextIndex > 0
    else
        -- Per-rank table unavailable for this group: keep the scanned nextIndex
        -- as a last resort and gate canTrain on prereqs alone.
        rec.canTrain = prereqOk
    end
    if grpCosts then
        local c = tonumber(grpCosts[nextR])
        -- else keep the flat rank-1 cost from the global entry - stated
        -- degradation, better than no number.
        if c then rec.cost = c end
    end
end

--- Build fingerprint string: changes when zone/level/AA points change
local function buildFingerprint()
    local Me = mq.TLO and mq.TLO.Me
    if not Me then return "" end
    local zone = (mq.TLO and mq.TLO.Zone and mq.TLO.Zone.ID and mq.TLO.Zone.ID()) or 0
    local spent = Me.AAPointsSpent and Me.AAPointsSpent() or 0
    local level = Me.Level and Me.Level() or 0
    return string.format("%d|%d|%d", zone, level, spent)
end

--- Build one AA record from the global AltAbility TLO entry plus the
--- character-specific rank/canTrain/nextIndex from Me.AltAbility(name).
local AA_TYPE_NAMES = { [1] = "General", [2] = "Archetype", [3] = "Class", [4] = "Special" }

local function buildRecord(aa, id, name, hasTruth)
    local Me = mq.TLO and mq.TLO.Me
    local rank, canTrain, index, nextIndex, myReuseTime = 0, false, 0, 0, 0
    -- The character-side resolve is BY NAME (a linear walk client-side) and it
    -- is also the lying read - with truth maps in hand every field it supplies
    -- gets overwritten by the completion overlay, so skip the whole call: it
    -- was the bulk of the scan's cost. (index/myReuseTime have no consumers.)
    if not hasTruth and Me and Me.AltAbility then
        local myAA = Me.AltAbility(name)
        if myAA then
            rank = (myAA.Rank and myAA.Rank()) or 0
            canTrain = (myAA.CanTrain and myAA.CanTrain()) or false
            index = (myAA.Index and myAA.Index()) or 0
            nextIndex = (myAA.NextIndex and myAA.NextIndex()) or 0
            myReuseTime = (myAA.MyReuseTime and myAA.MyReuseTime()) or 0
        end
    end
    -- Tab placement comes from the numeric Type field (1 General, 2 Archetype,
    -- 3 Class, 4 Special) - the same field the client's AA window uses. The
    -- Category STRING is a live-EQ dbstr lookup that is empty on the emu, which
    -- is why everything used to land in the General tab.
    local aatype = 0
    if aa.Type then
        local okType, t = pcall(function() return tonumber(aa.Type()) end)
        if okType and t then aatype = t end
    end
    local catStr = (aa.Category and aa.Category()) or ""
    if catStr == "" then catStr = AA_TYPE_NAMES[aatype] or "" end
    return {
        name = name,
        id = id,
        rank = rank,
        maxRank = (aa.MaxRank and aa.MaxRank()) or 0,
        cost = (aa.Cost and aa.Cost()) or 0,
        aatype = aatype,
        category = catStr,
        canTrain = canTrain,
        index = index,
        nextIndex = nextIndex,
        description = (aa.Description and aa.Description()) or "",
        passive = (aa.Passive and aa.Passive()) or false,
        requiresAbility = (aa.RequiresAbility and aa.RequiresAbility()) or nil,
        requiresAbilityPoints = (aa.RequiresAbilityPoints and aa.RequiresAbilityPoints()) or 0,
        myReuseTime = myReuseTime,
    }
end

--- Refresh: start an incremental rebuild. The old list stays served until the
--- rebuild completes (stale-while-revalidate), so the view never goes blank.
--- With the plugin, the rebuild walks only the ids the client itself would
--- show (CanSeeAbility); otherwise it falls back to the full id-space scan.
function M.refresh()
    -- Truth maps are fetched at scan START and ride the build: buildRecord
    -- skips the expensive character-side TLO resolve whenever they exist, and
    -- the completion overlay applies them. A buy always schedules a fresh
    -- rescan, so start-of-scan ranks are current for the scan they serve.
    local truth = fetchTruth()
    local pa = plugAA()
    if pa then
        local ok, ids = pcall(pa.getVisibleAAIds)
        if ok and type(ids) == 'table' and #ids > 0 then
            build = { ids = ids, cursor = 1, list = {}, seen = {}, truth = truth }
            return
        end
    end
    build = { cursor = 1, list = {}, seen = {}, truth = truth }
end

--- True while an incremental rebuild is in progress.
function M.isBuilding()
    return build ~= nil
end

--- Advance the incremental rebuild by one chunk. Called every main-loop tick;
--- no-ops when idle. Rank ids share a name, so entries dedupe by name keeping
--- the lowest id (rank 1), matching the old scan's behavior on the low block.
function M.pump()
    if not build then return end
    local AltAbility = mq.TLO and mq.TLO.AltAbility
    if not AltAbility then
        -- No TLO: record a completed-empty scan so shouldRefresh doesn't
        -- retrigger a doomed rebuild every frame the AA view is open.
        aaList = {}
        lastFingerprint = buildFingerprint()
        lastRefreshTime = mq.gettime()
        build = nil
        return
    end
    -- Two id sources: the plugin's visible-id list (client-filtered), or the
    -- full sparse range. Same record building and name-dedupe either way. The
    -- loop is TIME-BOXED (checked every 32 ids): the id cap suits the sparse
    -- scan's cheap misses, but on the visible-ids path every id builds a full
    -- record and an uncapped chunk froze the game for seconds on window open.
    local t0 = mq.gettime()
    local hasTruth = build.truth ~= nil
    local last = build.ids and #build.ids or MAX_AA_ID
    local upper = math.min(build.cursor + IDS_PER_PUMP - 1, last)
    local k = build.cursor
    while k <= upper do
        local i = build.ids and build.ids[k] or k
        local aa = i and AltAbility(i)
        if aa and aa.ID then
            local id = aa.ID()
            if id and id > 0 then
                local name = (aa.Name and aa.Name()) or ""
                if name ~= "" and not build.seen[name] then
                    build.seen[name] = true
                    build.list[#build.list + 1] = buildRecord(aa, id, name, hasTruth)
                end
            end
        end
        k = k + 1
        if k % 32 == 0 and (mq.gettime() - t0) >= PUMP_BUDGET_MS then break end
    end
    build.cursor = k
    if build.cursor > last then
        -- Overlay the truth maps fetched at scan start: TRUE trained ranks from
        -- the plugin's owned-ranks store (PcProfile AAList - the TLO Rank read
        -- resolves the level-appropriate entry and INFLATES partially-trained
        -- lines), then the spend fields derived from that rank (next-rank table
        -- id for /alt buy, next-rank cost, honest canTrain incl. prereqs).
        local truth = build.truth
        if truth then
            for _, rec in ipairs(build.list) do
                rec.rank = tonumber(truth.owned[rec.id]) or 0
                computeDerived(rec, truth)
            end
            lastTruth = truth
        end
        -- Resolve each record's requiresAbility (a GROUP-ID string as the TLO
        -- renders it) to the required ability's NAME. Name-keyed consumers
        -- (import prereq ordering, timeout diagnosis, the Requires tooltip)
        -- can't use the raw id-string.
        local byId = {}
        for _, rec in ipairs(build.list) do
            if rec.id then byId[rec.id] = rec end
        end
        for _, rec in ipairs(build.list) do
            local rid = rec.requiresAbility and tonumber(rec.requiresAbility) or nil
            local reqRec = rid and byId[rid] or nil
            rec.requiresAbilityName = reqRec and reqRec.name or nil
        end
        aaList = build.list
        lastFingerprint = buildFingerprint()
        lastRefreshTime = mq.gettime()
        build = nil
    end
end

--- Return current cached list (do not modify).
function M.getList()
    return aaList
end

--- Optimistic post-buy bump: a /alt buy schedules a full rescan, but the old
--- list keeps serving until it completes - and its nextIndex still points at
--- the rank just bought, so a repeat-click would re-fire a refused id. Bump the
--- record in place (rank +1, spend fields recomputed from the truth maps) so
--- training rank 2,3,4 is repeat-click; the rescan that follows every buy
--- corrects any drift (e.g. a buy the server refused).
function M.noteTrained(gid)
    if not gid then return end
    for _, rec in ipairs(aaList) do
        if rec.id == gid then
            local maxR = tonumber(rec.maxRank) or 0
            local newRank = (tonumber(rec.rank) or 0) + 1
            if maxR > 0 and newRank > maxR then newRank = maxR end
            rec.rank = newRank
            if lastTruth then
                -- Owned map is pre-buy; computeDerived reads rec.rank, so the
                -- bump above is the correction. Refresh the map's view of this
                -- group too, for any later bump before the rescan lands.
                lastTruth.owned[gid] = newRank
                computeDerived(rec, lastTruth)
            end
            return
        end
    end
end

--- True if we have never scanned or the fingerprint changed (caller should
--- refresh). Never true while a rebuild is already running. An EMPTY completed
--- scan is a legitimate result (low-level character, no AA data): it must wait
--- for a fingerprint change like any other, or the full id-space scan would
--- retrigger in a loop for as long as the AA view is open.
function M.shouldRefresh()
    if build then return false end
    if #aaList == 0 and lastRefreshTime == 0 then return true end
    return buildFingerprint() ~= lastFingerprint
end

--- Return points summary for right panel (thin wrapper around Me.*).
function M.getPointsSummary()
    local Me = mq.TLO and mq.TLO.Me
    if not Me then
        return { aaPoints = 0, assigned = 0, totalSpent = 0, pctAAExp = 0 }
    end
    return {
        aaPoints = (Me.AAPoints and Me.AAPoints()) or 0,
        assigned = (Me.AAPointsAssigned and Me.AAPointsAssigned()) or 0,
        totalSpent = (Me.AAPointsSpent and Me.AAPointsSpent()) or 0,
        pctAAExp = (Me.PctAAExp and Me.PctAAExp()) or 0,
    }
end

--- Return last refresh time (ms) for "Updated X ago" display.
function M.getLastRefreshTime()
    return lastRefreshTime
end

--- Get current AA tab (1=General, 2=Archetype, 3=Class, 4=Special). Per 4.2 state ownership.
function M.getAaTab()
    return aaTab
end

--- Set AA tab; clamps to 1..4.
function M.setAaTab(val)
    aaTab = (type(val) == "number" and val >= 1 and val <= 4) and val or 1
end

return M
