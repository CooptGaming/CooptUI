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
local MAX_AA_INDEX = 2000  -- Iterate Me.AltAbility(1)..(N); increase if server has more
local EMPTY_CONSECUTIVE_MAX = 50  -- Stop after this many consecutive invalid indices

--- Build fingerprint string: changes when zone/level/AA points change
local function buildFingerprint()
    local Me = mq.TLO and mq.TLO.Me
    if not Me then return "" end
    local zone = (mq.TLO and mq.TLO.Zone and mq.TLO.Zone.ID and mq.TLO.Zone.ID()) or 0
    local spent = Me.AAPointsSpent and Me.AAPointsSpent() or 0
    local level = Me.Level and Me.Level() or 0
    return string.format("%d|%d|%d", zone, level, spent)
end

--- Build full AA list from global AltAbility TLO (all available AAs), then fill
--- character-specific rank/canTrain/nextIndex from Me.AltAbility(name).
local function buildList()
    local list = {}
    local AltAbility = mq.TLO and mq.TLO.AltAbility
    local Me = mq.TLO and mq.TLO.Me
    if not AltAbility then return list end

    local emptyCount = 0
    for i = 1, MAX_AA_INDEX do
        local aa = AltAbility(i)
        if not aa or not aa.ID then
            emptyCount = emptyCount + 1
            if emptyCount >= EMPTY_CONSECUTIVE_MAX then break end
        else
            local id = aa.ID()
            if id and id > 0 then
                emptyCount = 0
                local name = (aa.Name and aa.Name()) or ""
                if name ~= "" then
                    -- Character-specific data (rank, canTrain, nextIndex, myReuseTime) from Me.AltAbility
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
                    list[#list + 1] = {
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
            else
                emptyCount = emptyCount + 1
                if emptyCount >= EMPTY_CONSECUTIVE_MAX then break end
            end
        end
    end
    return list
end

--- Refresh: rebuild list and update cache/fingerprint.
function M.refresh()
    aaList = buildList()
    lastFingerprint = buildFingerprint()
    lastRefreshTime = mq.gettime()
end

--- Return current cached list (do not modify).
function M.getList()
    return aaList
end

--- True if cache is empty or fingerprint changed (caller should refresh).
function M.shouldRefresh()
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
