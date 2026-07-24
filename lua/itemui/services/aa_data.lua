--[[
    AA Data Service - Build and cache the list of Alternate Advancement abilities.
    Part of CoOpt UI Items Companion. Single responsibility: build list from MQ, cache, fingerprint, refresh.
--]]

local mq = require('mq')

local M = {}

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
    return {
        name = name,
        id = id,
        rank = rank,
        maxRank = (aa.MaxRank and aa.MaxRank()) or 0,
        cost = (aa.Cost and aa.Cost()) or 0,
        category = (aa.Category and aa.Category()) or "",
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
function M.refresh()
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
    if not AltAbility then build = nil; return end
    local upper = math.min(build.cursor + IDS_PER_PUMP - 1, MAX_AA_ID)
    for i = build.cursor, upper do
        local aa = AltAbility(i)
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
    if build.cursor > MAX_AA_ID then
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

--- True if cache is empty or fingerprint changed (caller should refresh).
--- Never true while a rebuild is already running.
function M.shouldRefresh()
    if build then return false end
    local fp = buildFingerprint()
    if #aaList == 0 then return true end
    return fp ~= lastFingerprint
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
