--[[
    ItemUI - Sell Status Service
    Sell/loot rule wrappers, config cache management, and sell status computation.
    Part of CoOpt UI — EverQuest EMU Companion
--]]

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
    -- Reroll List protection: merge aug/mythical list IDs so willItemBeSold never sells listed items.
    if deps.perfCache.sellConfigCache and deps.getRerollListProtection then
        local r = deps.getRerollListProtection()
        if r then
            deps.perfCache.sellConfigCache.rerollListIdSet = r.idSet
        end
    end
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

--- Deprecated no-op. The stored-inv-by-name override cache was removed: it stored entries only
--- when the item was in the exact Keep/Junk list but applied them only when the item was NOT in
--- that list (self-canceling), and its refresh cost a full storage.loadInventory() disk parse
--- every 2s. Kept as a stub because app.lua wires getStoredInvByName to this function.
function M.refreshStoredInvByName()
    return nil
end

--- Single source of truth for granular flag computation.
--- Call this to set all granular + summary flags on an item from current config lists.
--- Uses normalized name key (trimmed) so Keep/Junk list lookups match INI/stored keys after rescans.
function M.attachGranularFlags(item)
    local nameKey = (item.name or ""):match("^%s*(.-)%s*$")
    item.inKeepExact = M.isInKeepList(nameKey)
    item.inJunkExact = M.isInJunkList(nameKey)
    item.inKeepContains = M.isKeptByContains(nameKey)
    item.inJunkContains = M.isInJunkContainsList(nameKey)
    item.inKeepType = M.isKeptByType(item.type)
    item.isProtectedType = M.isProtectedType(item.type)
    item.inKeep = item.inKeepExact or item.inKeepContains or item.inKeepType
    item.inJunk = item.inJunkExact or item.inJunkContains
    item.isProtected = item.isProtectedType
end

--- Compute and attach willSell/sellReason to each item using granular flags.
function M.computeAndAttachSellStatus(items)
    if not items or #items == 0 then return end
    if not deps.perfCache.sellConfigCache then M.loadSellConfigCache() end
    for _, item in ipairs(items) do
        M.attachGranularFlags(item)
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
    M.attachGranularFlags(tmp)
    local ws, reason = M.willItemBeSold(tmp)
    return reason or "", ws, tmp.inKeep, tmp.inJunk
end

return M
