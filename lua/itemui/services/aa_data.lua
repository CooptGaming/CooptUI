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
local build = nil  -- { cursor, list, seen } while an incremental rebuild is running

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

local function buildRecord(aa, id, name)
    local Me = mq.TLO and mq.TLO.Me
    local rank, canTrain, index, nextIndex, myReuseTime = 0, false, 0, 0, 0
    if Me and Me.AltAbility then
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
    local pa = plugAA()
    if pa then
        local ok, ids = pcall(pa.getVisibleAAIds)
        if ok and type(ids) == 'table' and #ids > 0 then
            build = { ids = ids, cursor = 1, list = {}, seen = {} }
            return
        end
    end
    build = { cursor = 1, list = {}, seen = {} }
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
    -- full sparse range. Same record building and name-dedupe either way.
    local last = build.ids and #build.ids or MAX_AA_ID
    local upper = math.min(build.cursor + IDS_PER_PUMP - 1, last)
    for k = build.cursor, upper do
        local i = build.ids and build.ids[k] or k
        local aa = i and AltAbility(i)
        if aa and aa.ID then
            local id = aa.ID()
            if id and id > 0 then
                local name = (aa.Name and aa.Name()) or ""
                if name ~= "" and not build.seen[name] then
                    build.seen[name] = true
                    build.list[#build.list + 1] = buildRecord(aa, id, name)
                end
            end
        end
    end
    build.cursor = upper + 1
    if build.cursor > last then
        -- Overlay TRUE trained ranks from the plugin's owned-ranks store
        -- (PcProfile AAList). The TLO Rank read above resolves the
        -- level-appropriate entry and INFLATES partially-trained lines -
        -- exports and the Cur/Max column must show what is actually owned.
        local pa = plugAA()
        if pa and type(pa.getOwnedRanks) == 'function' then
            local ok, owned = pcall(pa.getOwnedRanks)
            if ok and type(owned) == 'table' then
                for _, rec in ipairs(build.list) do
                    rec.rank = tonumber(owned[rec.id]) or 0
                end
            end
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
