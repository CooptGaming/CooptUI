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

function M.willItemBeSold(itemData)
    if not deps.perfCache.sellConfigCache then M.loadSellConfigCache() end
    return deps.rules.willItemBeSold(itemData, deps.perfCache.sellConfigCache)
end

--- Refresh stored-inv-by-name cache if missing or older than TTL.
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

--- Compute and attach willSell/sellReason to each item.
function M.computeAndAttachSellStatus(items)
    if not items or #items == 0 then return end
    if not deps.perfCache.sellConfigCache then M.loadSellConfigCache() end
    refreshStoredInvByNameIfNeeded()
    for _, item in ipairs(items) do
        local inKeep = M.isInKeepList(item.name) or M.isKeptByContains(item.name) or M.isKeptByType(item.type)
        local inJunk = M.isInJunkList(item.name)
        local storedItem = deps.perfCache.storedInvByName[(item.name or ""):match("^%s*(.-)%s*$")]
        if storedItem then
            if storedItem.inKeep ~= nil then inKeep = storedItem.inKeep end
            if storedItem.inJunk ~= nil then inJunk = storedItem.inJunk end
        end
        local itemData = {
            name = item.name, type = item.type, value = item.value, totalValue = item.totalValue,
            stackSize = item.stackSize or 1, nodrop = item.nodrop, notrade = item.notrade,
            lore = item.lore, quest = item.quest, collectible = item.collectible, heirloom = item.heirloom,
            inKeep = inKeep, inJunk = inJunk
        }
        local willSell, reason = M.willItemBeSold(itemData)
        item.willSell = willSell
        item.sellReason = reason or ""
    end
end

--- Return sell filter status for an inventory item.
function M.getSellStatusForItem(item)
    if not item then return "", false end
    local inKeep = M.isInKeepList(item.name) or M.isKeptByContains(item.name) or M.isKeptByType(item.type)
    local inJunk = M.isInJunkList(item.name)
    refreshStoredInvByNameIfNeeded()
    local storedItem = deps.perfCache.storedInvByName[(item.name or ""):match("^%s*(.-)%s*$")]
    if storedItem then
        if storedItem.inKeep ~= nil then inKeep = storedItem.inKeep end
        if storedItem.inJunk ~= nil then inJunk = storedItem.inJunk end
    end
    local itemData = {
        name = item.name, type = item.type, value = item.value, totalValue = item.totalValue,
        stackSize = item.stackSize or 1, nodrop = item.nodrop, notrade = item.notrade,
        lore = item.lore, quest = item.quest, collectible = item.collectible, heirloom = item.heirloom,
        inKeep = inKeep, inJunk = inJunk
    }
    local willSell, reason = M.willItemBeSold(itemData)
    return reason or "", willSell, inKeep, inJunk
end

return M
