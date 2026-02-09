--[[
    ItemUI - Sell Status Service
    Sell/loot rule wrappers, config cache management, and sell status computation.
    Part of CoopUI — EverQuest EMU Companion
--]]

local mq = require('mq')
local events = require('itemui.core.events')

local M = {}
local deps  -- set by init()

function M.init(d)
    deps = d
    -- Subscribe to config change events (emitted by config_cache.lua list APIs)
    events.on(events.EVENTS.CONFIG_SELL_CHANGED, function() M.invalidateSellConfigCache() end)
    events.on(events.EVENTS.CONFIG_LOOT_CHANGED, function() M.invalidateLootConfigCache() end)
end

function M.loadSellConfigCache()
    deps.perfCache.sellConfigCache = deps.rules.loadSellConfigCache()
end

function M.invalidateSellConfigCache()
    deps.perfCache.sellConfigCache = nil
end

function M.invalidateLootConfigCache()
    deps.perfCache.lootConfigCache = nil
end

function M.isInKeepList(itemName)
    if not deps.perfCache.sellConfigCache then M.loadSellConfigCache() end
    return deps.rules.isInKeepList(itemName, deps.perfCache.sellConfigCache)
end

function M.isInJunkList(itemName)
    if not deps.perfCache.sellConfigCache then M.loadSellConfigCache() end
    return deps.rules.isInJunkList(itemName, deps.perfCache.sellConfigCache)
end

function M.isProtectedType(itemType)
    if not deps.perfCache.sellConfigCache then M.loadSellConfigCache() end
    return deps.rules.isProtectedType(itemType, deps.perfCache.sellConfigCache)
end

function M.isKeptByContains(itemName)
    if not deps.perfCache.sellConfigCache then M.loadSellConfigCache() end
    return deps.rules.isKeptByContains(itemName, deps.perfCache.sellConfigCache)
end

function M.isKeptByType(itemType)
    if not deps.perfCache.sellConfigCache then M.loadSellConfigCache() end
    return deps.rules.isKeptByType(itemType, deps.perfCache.sellConfigCache)
end

function M.isInJunkContainsList(itemName)
    if not deps.perfCache.sellConfigCache then M.loadSellConfigCache() end
    return deps.rules.isInJunkContainsList(itemName, deps.perfCache.sellConfigCache)
end

function M.willItemBeSold(itemData)
    if not deps.perfCache.sellConfigCache then M.loadSellConfigCache() end
    return deps.rules.willItemBeSold(itemData, deps.perfCache.sellConfigCache)
end

--- Refresh stored-inv-by-name cache if missing or older than TTL.
--- Also exposed as M.refreshStoredInvByName() for scan.lua to reuse cached lookup.
local function refreshStoredInvByNameIfNeeded()
    if deps.perfCache.storedInvByName and (mq.gettime() - (deps.perfCache.storedInvByNameTime or 0)) <= deps.C.STORED_INV_CACHE_TTL_MS then
        return
    end
    local stored, _ = deps.storage.loadInventory()
    deps.perfCache.storedInvByName = {}
    if stored and #stored > 0 then
        for _, it in ipairs(stored) do
            local n = (it.name or ""):match("^%s*(.-)%s*$")
            if n ~= "" and (it.inKeep ~= nil or it.inJunk ~= nil) then
                deps.perfCache.storedInvByName[n] = { inKeep = it.inKeep, inJunk = it.inJunk }
            end
        end
    end
    deps.perfCache.storedInvByNameTime = mq.gettime()
end

--- Public: refresh and return the storedInvByName cache (for scan.lua to reuse)
function M.refreshStoredInvByName()
    refreshStoredInvByNameIfNeeded()
    return deps.perfCache.storedInvByName
end

--- Single source of truth for granular flag computation.
--- Call this to set all granular + summary flags on an item from current config lists.
--- Uses normalized name key (trimmed) so Keep/Junk list lookups match INI/stored keys after rescans.
function M.attachGranularFlags(item, storedByName)
    local nameKey = (item.name or ""):match("^%s*(.-)%s*$")
    item.inKeepExact = M.isInKeepList(nameKey)
    item.inJunkExact = M.isInJunkList(nameKey)
    item.inKeepContains = M.isKeptByContains(nameKey)
    item.inJunkContains = M.isInJunkContainsList(nameKey)
    item.inKeepType = M.isKeptByType(item.type)
    item.isProtectedType = M.isProtectedType(item.type)
    -- Apply stored overrides only when item is in neither exact list (config list always wins).
    -- This keeps Keep/Junk button decisions persistent across rescans and stored-inv refresh.
    if storedByName and not item.inKeepExact and not item.inJunkExact then
        local storedItem = storedByName[nameKey]
        if storedItem then
            if storedItem.inKeep ~= nil then item.inKeepExact = storedItem.inKeep end
            if storedItem.inJunk ~= nil then item.inJunkExact = storedItem.inJunk end
        end
    end
    item.inKeep = item.inKeepExact or item.inKeepContains or item.inKeepType
    item.inJunk = item.inJunkExact or item.inJunkContains
    item.isProtected = item.isProtectedType
end

--- Compute and attach willSell/sellReason to each item using granular flags.
function M.computeAndAttachSellStatus(items)
    if not items or #items == 0 then return end
    if not deps.perfCache.sellConfigCache then M.loadSellConfigCache() end
    refreshStoredInvByNameIfNeeded()
    for _, item in ipairs(items) do
        M.attachGranularFlags(item, deps.perfCache.storedInvByName)
        local willSell, reason = M.willItemBeSold(item)
        item.willSell = willSell
        item.sellReason = reason or ""
    end
end

--- Return sell filter status for an inventory item (shallow-copy, no side effects).
function M.getSellStatusForItem(item)
    if not item then return "", false end
    local tmp = {}
    for k, v in pairs(item) do tmp[k] = v end
    refreshStoredInvByNameIfNeeded()
    M.attachGranularFlags(tmp, deps.perfCache.storedInvByName)
    local ws, reason = M.willItemBeSold(tmp)
    return reason or "", ws, tmp.inKeep, tmp.inJunk
end

return M
