--[[
    ItemUI Config Cache
    Cached sell/loot config from INI and list add/remove APIs.
    Reduces locals/upvalues in init.lua. Call init(opts) once from init, then getCache(), loadConfigCache(), list API.
--]]

local config = require('itemui.config')
local rules = require('itemui.rules')
local events = require('itemui.core.events')

local M = {}
local opts
local cache

local function getCache()
    return cache
end

local function loadConfigCache()
    local sellFlags, sellValues, sellLists = cache.sell.flags, cache.sell.values, cache.sell.lists
    local lootFlags, lootValues, lootSorting, lootLists = cache.loot.flags, cache.loot.values, cache.loot.sorting, cache.loot.lists
    local epicClasses = cache.epicClasses

    sellFlags.protectNoDrop = config.readINIValue("sell_flags.ini", "Settings", "protectNoDrop", "TRUE") == "TRUE"
    sellFlags.protectNoTrade = config.readINIValue("sell_flags.ini", "Settings", "protectNoTrade", "TRUE") == "TRUE"
    sellFlags.protectLore = config.readINIValue("sell_flags.ini", "Settings", "protectLore", "TRUE") == "TRUE"
    sellFlags.protectQuest = config.readINIValue("sell_flags.ini", "Settings", "protectQuest", "TRUE") == "TRUE"
    sellFlags.protectCollectible = config.readINIValue("sell_flags.ini", "Settings", "protectCollectible", "TRUE") == "TRUE"
    sellFlags.protectHeirloom = config.readINIValue("sell_flags.ini", "Settings", "protectHeirloom", "TRUE") == "TRUE"
    sellFlags.protectEpic = config.readINIValue("sell_flags.ini", "Settings", "protectEpic", "TRUE") == "TRUE"
    sellValues.minSell = tonumber(config.readINIValue("sell_value.ini", "Settings", "minSellValue", "50")) or 50
    sellValues.minStack = tonumber(config.readINIValue("sell_value.ini", "Settings", "minSellValueStack", "10")) or 10
    sellValues.maxKeep = tonumber(config.readINIValue("sell_value.ini", "Settings", "maxKeepValue", "10000")) or 10000
    sellLists.keepExact = config.parseList(config.readListValue("sell_keep_exact.ini", "Items", "exact", ""))
    sellLists.keepContains = config.parseList(config.readListValue("sell_keep_contains.ini", "Items", "contains", ""))
    sellLists.keepTypes = config.parseList(config.readListValue("sell_keep_types.ini", "Items", "types", ""))
    sellLists.junkExact = config.parseList(config.readListValue("sell_always_sell_exact.ini", "Items", "exact", ""))
    sellLists.junkContains = config.parseList(config.readListValue("sell_always_sell_contains.ini", "Items", "contains", ""))
    sellLists.protectedTypes = config.parseList(config.readListValue("sell_protected_types.ini", "Items", "types", ""))
    sellLists.augmentAlwaysSellExact = config.parseList(config.readListValue("sell_augment_always_sell_exact.ini", "Items", "exact", ""))
    lootFlags.lootClickies = config.readLootINIValue("loot_flags.ini", "Settings", "lootClickies", "TRUE") == "TRUE"
    lootFlags.lootQuest = config.readLootINIValue("loot_flags.ini", "Settings", "lootQuest", "FALSE") == "TRUE"
    lootFlags.lootCollectible = config.readLootINIValue("loot_flags.ini", "Settings", "lootCollectible", "FALSE") == "TRUE"
    lootFlags.lootHeirloom = config.readLootINIValue("loot_flags.ini", "Settings", "lootHeirloom", "FALSE") == "TRUE"
    lootFlags.lootAttuneable = config.readLootINIValue("loot_flags.ini", "Settings", "lootAttuneable", "FALSE") == "TRUE"
    lootFlags.lootAugSlots = config.readLootINIValue("loot_flags.ini", "Settings", "lootAugSlots", "FALSE") == "TRUE"
    lootFlags.alwaysLootEpic = config.readLootINIValue("loot_flags.ini", "Settings", "alwaysLootEpic", "TRUE") == "TRUE"
    lootFlags.pauseOnMythicalNoDropNoTrade = config.readLootINIValue("loot_flags.ini", "Settings", "pauseOnMythicalNoDropNoTrade", "FALSE") == "TRUE"
    lootFlags.alertMythicalGroupChat = config.readLootINIValue("loot_flags.ini", "Settings", "alertMythicalGroupChat", "TRUE") == "TRUE"
    lootValues.minLoot = tonumber(config.readLootINIValue("loot_value.ini", "Settings", "minLootValue", "999")) or 999
    lootValues.minStack = tonumber(config.readLootINIValue("loot_value.ini", "Settings", "minLootValueStack", "200")) or 200
    lootValues.tributeOverride = tonumber(config.readLootINIValue("loot_value.ini", "Settings", "tributeOverride", "1000")) or 1000
    lootSorting.enableSorting = config.readLootINIValue("loot_sorting.ini", "Settings", "enableSorting", "FALSE") == "TRUE"
    lootSorting.enableWeightSort = config.readLootINIValue("loot_sorting.ini", "Settings", "enableWeightSort", "FALSE") == "TRUE"
    lootSorting.minWeight = tonumber(config.readLootINIValue("loot_sorting.ini", "Settings", "minWeight", "40")) or 40
    for _, cls in ipairs(rules.EPIC_CLASSES) do
        epicClasses[cls] = config.readSharedINIValue("epic_classes.ini", "Classes", cls, "FALSE") == "TRUE"
    end
    lootLists.sharedExact = config.parseList(config.readSharedListValue("valuable_exact.ini", "Items", "exact", ""))
    lootLists.sharedContains = config.parseList(config.readSharedListValue("valuable_contains.ini", "Items", "contains", ""))
    lootLists.sharedTypes = config.parseList(config.readSharedListValue("valuable_types.ini", "Items", "types", ""))
    lootLists.alwaysExact = config.parseList(config.readLootListValue("loot_always_exact.ini", "Items", "exact", ""))
    lootLists.alwaysContains = config.parseList(config.readLootListValue("loot_always_contains.ini", "Items", "contains", ""))
    lootLists.alwaysTypes = config.parseList(config.readLootListValue("loot_always_types.ini", "Items", "types", ""))
    lootLists.skipExact = config.parseList(config.readLootListValue("loot_skip_exact.ini", "Items", "exact", ""))
    lootLists.skipContains = config.parseList(config.readLootListValue("loot_skip_contains.ini", "Items", "contains", ""))
    lootLists.skipTypes = config.parseList(config.readLootListValue("loot_skip_types.ini", "Items", "types", ""))
    lootLists.augmentSkipExact = config.parseList(config.readLootListValue("loot_augment_skip_exact.ini", "Items", "exact", ""))
end

-- List APIs (need isInKeepList, isInJunkList from caller for validation; we take them via opts after init)
local function addToKeepList(itemName)
    itemName = config.sanitizeItemName(itemName)
    if not itemName then opts.setStatusMessage("Invalid item name"); return false end
    if opts.isInKeepList(itemName) then opts.setStatusMessage("Already in Keep list"); return false end
    local current = config.readListValue("sell_keep_exact.ini", "Items", "exact", "")
    local junk = config.readListValue("sell_always_sell_exact.ini", "Items", "exact", "")
    local items, found = {}, false
    for item in junk:gmatch("([^/]+)") do
        local t = item:match("^%s*(.-)%s*$")
        if t ~= itemName then table.insert(items, t) else found = true end
    end
    if found then config.writeListValue("sell_always_sell_exact.ini", "Items", "exact", table.concat(items, "/")) end
    config.writeListValue("sell_keep_exact.ini", "Items", "exact", current == "" and itemName or (current .. "/" .. itemName))
    events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
    opts.setStatusMessage("Added to Keep list")
    return true
end

local function addToJunkList(itemName)
    itemName = config.sanitizeItemName(itemName)
    if not itemName then opts.setStatusMessage("Invalid item name"); return false end
    if opts.isInJunkList(itemName) then opts.setStatusMessage("Already in Always sell list"); return false end
    local current = config.readListValue("sell_always_sell_exact.ini", "Items", "exact", "")
    local keep = config.readListValue("sell_keep_exact.ini", "Items", "exact", "")
    local items, found = {}, false
    for item in keep:gmatch("([^/]+)") do
        local t = item:match("^%s*(.-)%s*$")
        if t ~= itemName then table.insert(items, t) else found = true end
    end
    if found then config.writeListValue("sell_keep_exact.ini", "Items", "exact", table.concat(items, "/")) end
    config.writeListValue("sell_always_sell_exact.ini", "Items", "exact", current == "" and itemName or (current .. "/" .. itemName))
    events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
    opts.setStatusMessage("Added to Always sell list")
    return true
end

local function removeFromKeepList(itemName)
    itemName = config.sanitizeItemName(itemName)
    if not itemName then return false end
    local current = config.readListValue("sell_keep_exact.ini", "Items", "exact", "")
    if current == "" then return false end
    local items, found = {}, false
    for item in current:gmatch("([^/]+)") do
        local t = item:match("^%s*(.-)%s*$")
        if t ~= itemName then table.insert(items, t) else found = true end
    end
    if not found then return false end
    config.writeListValue("sell_keep_exact.ini", "Items", "exact", #items == 0 and "" or table.concat(items, "/"))
    events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
    opts.setStatusMessage("Removed from Keep list")
    return true
end

local function removeFromJunkList(itemName)
    itemName = config.sanitizeItemName(itemName)
    if not itemName then return false end
    local current = config.readListValue("sell_always_sell_exact.ini", "Items", "exact", "")
    if current == "" then return false end
    local items, found = {}, false
    for item in current:gmatch("([^/]+)") do
        local t = item:match("^%s*(.-)%s*$")
        if t ~= itemName then table.insert(items, t) else found = true end
    end
    if not found then return false end
    config.writeListValue("sell_always_sell_exact.ini", "Items", "exact", #items == 0 and "" or table.concat(items, "/"))
    events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
    opts.setStatusMessage("Removed from Always sell list")
    return true
end

local function isInLootSkipList(itemName)
    if not itemName then return false end
    local list = config.parseList(config.readLootListValue("loot_skip_exact.ini", "Items", "exact", ""))
    for _, s in ipairs(list) do if s == itemName then return true end end
    return false
end

local function addToLootSkipList(itemName)
    itemName = config.sanitizeItemName(itemName)
    if not itemName then opts.setStatusMessage("Invalid item name"); return false end
    if isInLootSkipList(itemName) then opts.setStatusMessage("Already in Never loot list"); return false end
    local list = config.parseList(config.readLootListValue("loot_skip_exact.ini", "Items", "exact", ""))
    list[#list + 1] = itemName
    config.writeLootListValue("loot_skip_exact.ini", "Items", "exact", config.joinList(list))
    local lootLists = cache.loot.lists
    if lootLists and lootLists.skipExact then lootLists.skipExact = list end
    events.emit(events.EVENTS.CONFIG_LOOT_CHANGED)
    opts.setStatusMessage("Added to Never loot list")
    return true
end

local function removeFromLootSkipList(itemName)
    itemName = config.sanitizeItemName(itemName)
    if not itemName then return false end
    local list = config.parseList(config.readLootListValue("loot_skip_exact.ini", "Items", "exact", ""))
    local newList, found = {}, false
    for _, s in ipairs(list) do if s ~= itemName then newList[#newList + 1] = s else found = true end end
    if not found then return false end
    config.writeLootListValue("loot_skip_exact.ini", "Items", "exact", config.joinList(newList))
    local lootLists = cache.loot.lists
    if lootLists and lootLists.skipExact then lootLists.skipExact = newList end
    events.emit(events.EVENTS.CONFIG_LOOT_CHANGED)
    opts.setStatusMessage("Removed from Never loot list")
    return true
end

local function createAugmentListAPI()
    local sellLists = cache.sell.lists
    local lootLists = cache.loot.lists
    local api = {}
    function api.isInAugmentAlwaysSellList(itemName)
        if not itemName then return false end
        local list = sellLists and sellLists.augmentAlwaysSellExact
        if list then
            for _, s in ipairs(list) do if s == itemName then return true end end
            return false
        end
        list = config.parseList(config.readListValue("sell_augment_always_sell_exact.ini", "Items", "exact", ""))
        for _, s in ipairs(list) do if s == itemName then return true end end
        return false
    end
    function api.addToAugmentAlwaysSellList(itemName)
        itemName = config.sanitizeItemName(itemName)
        if not itemName then opts.setStatusMessage("Invalid item name"); return false end
        if api.isInAugmentAlwaysSellList(itemName) then opts.setStatusMessage("Already in Augment Always sell list"); return false end
        local list = config.parseList(config.readListValue("sell_augment_always_sell_exact.ini", "Items", "exact", ""))
        list[#list + 1] = itemName
        config.writeListValue("sell_augment_always_sell_exact.ini", "Items", "exact", config.joinList(list))
        if sellLists and sellLists.augmentAlwaysSellExact then sellLists.augmentAlwaysSellExact = list end
        events.emit(events.EVENTS.CONFIG_SELL_CHANGED); opts.setStatusMessage("Added to Augment Always sell list")
        return true
    end
    function api.removeFromAugmentAlwaysSellList(itemName)
        itemName = config.sanitizeItemName(itemName)
        if not itemName then return false end
        local list = config.parseList(config.readListValue("sell_augment_always_sell_exact.ini", "Items", "exact", ""))
        local newList, found = {}, false
        for _, s in ipairs(list) do if s ~= itemName then newList[#newList + 1] = s else found = true end end
        if not found then return false end
        config.writeListValue("sell_augment_always_sell_exact.ini", "Items", "exact", config.joinList(newList))
        if sellLists and sellLists.augmentAlwaysSellExact then sellLists.augmentAlwaysSellExact = newList end
        events.emit(events.EVENTS.CONFIG_SELL_CHANGED); opts.setStatusMessage("Removed from Augment Always sell list")
        return true
    end
    function api.isInAugmentNeverLootList(itemName)
        if not itemName then return false end
        local list = lootLists and lootLists.augmentSkipExact
        if list then
            for _, s in ipairs(list) do if s == itemName then return true end end
            return false
        end
        list = config.parseList(config.readLootListValue("loot_augment_skip_exact.ini", "Items", "exact", ""))
        for _, s in ipairs(list) do if s == itemName then return true end end
        return false
    end
    function api.addToAugmentNeverLootList(itemName)
        itemName = config.sanitizeItemName(itemName)
        if not itemName then opts.setStatusMessage("Invalid item name"); return false end
        if api.isInAugmentNeverLootList(itemName) then opts.setStatusMessage("Already in Augment Never loot list"); return false end
        local list = config.parseList(config.readLootListValue("loot_augment_skip_exact.ini", "Items", "exact", ""))
        list[#list + 1] = itemName
        config.writeLootListValue("loot_augment_skip_exact.ini", "Items", "exact", config.joinList(list))
        if lootLists and lootLists.augmentSkipExact then lootLists.augmentSkipExact = list end
        events.emit(events.EVENTS.CONFIG_LOOT_CHANGED); opts.setStatusMessage("Added to Augment Never loot list")
        return true
    end
    function api.removeFromAugmentNeverLootList(itemName)
        itemName = config.sanitizeItemName(itemName)
        if not itemName then return false end
        local list = config.parseList(config.readLootListValue("loot_augment_skip_exact.ini", "Items", "exact", ""))
        local newList, found = {}, false
        for _, s in ipairs(list) do if s ~= itemName then newList[#newList + 1] = s else found = true end end
        if not found then return false end
        config.writeLootListValue("loot_augment_skip_exact.ini", "Items", "exact", config.joinList(newList))
        if lootLists and lootLists.augmentSkipExact then lootLists.augmentSkipExact = newList end
        events.emit(events.EVENTS.CONFIG_LOOT_CHANGED); opts.setStatusMessage("Removed from Augment Never loot list")
        return true
    end
    return api
end

function M.init(o)
    opts = o
    cache = {
        sell = { flags = {}, values = {}, lists = { keepExact = {}, keepContains = {}, keepTypes = {}, junkExact = {}, junkContains = {}, protectedTypes = {}, augmentAlwaysSellExact = {} } },
        loot = { flags = {}, values = {}, sorting = {}, lists = { sharedExact = {}, sharedContains = {}, sharedTypes = {}, alwaysExact = {}, alwaysContains = {}, alwaysTypes = {}, skipExact = {}, skipContains = {}, skipTypes = {}, augmentSkipExact = {} } },
        epicClasses = {},
    }
end

M.getCache = getCache
M.loadConfigCache = loadConfigCache
M.addToKeepList = addToKeepList
M.addToJunkList = addToJunkList
M.removeFromKeepList = removeFromKeepList
M.removeFromJunkList = removeFromJunkList
M.isInLootSkipList = isInLootSkipList
M.addToLootSkipList = addToLootSkipList
M.removeFromLootSkipList = removeFromLootSkipList
M.createAugmentListAPI = createAugmentListAPI

return M
