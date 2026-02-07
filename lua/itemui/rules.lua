--[[
    ItemUI Rules Module
    Sell and loot rule evaluation. Shared logic for keep/junk/protected (sell)
    and skip/always-loot (loot). Mirrors sell.mac and loot.mac evaluation order.
--]]

local config = require('itemui.config')
local readINIValue = config.readINIValue
local readSharedINIValue = config.readSharedINIValue
local readSharedListValue = config.readSharedListValue
local readLootINIValue = config.readLootINIValue
local readLootListValue = config.readLootListValue
local readListValue = config.readListValue

--- Filter out null/nil placeholders that shouldn't be in filter lists
local function isValidFilterEntry(t)
    if not t or t == "" then return false end
    local lower = t:lower()
    if lower == "null" or lower == "nil" then return false end
    return true
end

--- Normalize item name for epic list lookup: trim and collapse multiple spaces so INI list matches game names.
local function normalizeItemName(s)
    if not s or type(s) ~= "string" then return "" end
    local t = s:match("^%s*(.-)%s*$") or ""
    return (t:gsub("%s+", " "))
end

-- ============================================================================
-- Epic items by class (used by both sell and loot)
-- ============================================================================

local EPIC_CLASSES = { "bard", "beastlord", "berserker", "cleric", "druid", "enchanter", "magician", "monk", "necromancer", "paladin", "ranger", "rogue", "shadow_knight", "shaman", "warrior", "wizard" }

--- Parse epic list string (slash-separated) into a set keyed by normalized name.
local function parseEpicListIntoSet(epicStr, set)
    if not set then set = {} end
    for item in (epicStr or ""):gmatch("([^/]+)") do
        local t = item:match("^%s*(.-)%s*$")
        if isValidFilterEntry(t) then
            local key = normalizeItemName(t)
            if key ~= "" then set[key] = true end
        end
    end
    return set
end

--- Load epic items from selected classes (epic_classes.ini). Each class has its own file epic_items_<class>.ini.
--- If no classes are selected, uses epic_items_exact.ini (all epic items).
--- If classes are selected but no per-class files exist (empty set), falls back to epic_items_exact.ini so protection still works.
local function loadEpicItemSetByClass()
    local set = {}
    local anySelected = false
    for _, cls in ipairs(EPIC_CLASSES) do
        if readSharedINIValue("epic_classes.ini", "Classes", cls, "FALSE") == "TRUE" then
            anySelected = true
            local epicStr = readSharedListValue("epic_items_" .. cls .. ".ini", "Items", "exact", "")
            parseEpicListIntoSet(epicStr, set)
        end
    end
    if not anySelected then
        local epicStr = readSharedListValue("epic_items_exact.ini", "Items", "exact", "")
        parseEpicListIntoSet(epicStr, set)
    elseif next(set) == nil then
        -- Classes selected but no per-class INI files (or all empty): fall back to full list so epic protection still works
        local epicStr = readSharedListValue("epic_items_exact.ini", "Items", "exact", "")
        parseEpicListIntoSet(epicStr, set)
    end
    return set
end

-- ============================================================================
-- Sell rules (mirrors sell.mac EvaluateItem order)
-- ============================================================================

--- Build sell config cache from INI. Call once per scan.
--- @return table|nil Cache with keepSet, junkSet, keepContainsList, keepTypeSet, protectedTypeSet, flags, values
local function loadSellConfigCache()
    local sharedValuableExact = readSharedINIValue("valuable_exact.ini", "Items", "exact", "")
    local sharedValuableContains = readSharedINIValue("valuable_contains.ini", "Items", "contains", "")
    local sharedValuableTypes = readSharedINIValue("valuable_types.ini", "Items", "types", "")
    local keepExact = readINIValue("sell_keep_exact.ini", "Items", "exact", "")
    local keepContains = readINIValue("sell_keep_contains.ini", "Items", "contains", "")
    local keepTypes = readINIValue("sell_keep_types.ini", "Items", "types", "")
    local junkExact = readINIValue("sell_always_sell_exact.ini", "Items", "exact", "")
    local protectedTypes = readINIValue("sell_protected_types.ini", "Items", "types", "")
    local augmentAlwaysSellExact = readINIValue("sell_augment_always_sell_exact.ini", "Items", "exact", "")
    local skipExact = readLootListValue("loot_skip_exact.ini", "Items", "exact", "")
    local augmentSkipExact = readLootListValue("loot_augment_skip_exact.ini", "Items", "exact", "")

    local cache = {
        protectNoDrop = readINIValue("sell_flags.ini", "Settings", "protectNoDrop", "TRUE") == "TRUE",
        protectNoTrade = readINIValue("sell_flags.ini", "Settings", "protectNoTrade", "TRUE") == "TRUE",
        protectLore = readINIValue("sell_flags.ini", "Settings", "protectLore", "TRUE") == "TRUE",
        protectQuest = readINIValue("sell_flags.ini", "Settings", "protectQuest", "TRUE") == "TRUE",
        protectCollectible = readINIValue("sell_flags.ini", "Settings", "protectCollectible", "TRUE") == "TRUE",
        protectHeirloom = readINIValue("sell_flags.ini", "Settings", "protectHeirloom", "TRUE") == "TRUE",
        protectEpic = readINIValue("sell_flags.ini", "Settings", "protectEpic", "TRUE") == "TRUE",
        minSell = tonumber(readINIValue("sell_value.ini", "Settings", "minSellValue", "50")) or 50,
        minStack = tonumber(readINIValue("sell_value.ini", "Settings", "minSellValueStack", "10")) or 10,
        maxKeep = tonumber(readINIValue("sell_value.ini", "Settings", "maxKeepValue", "10000")) or 10000,
    }

    cache.keepSet = {}
    for item in (sharedValuableExact or ""):gmatch("([^/]+)") do
        local t = item:match("^%s*(.-)%s*$")
        if isValidFilterEntry(t) then cache.keepSet[t] = true end
    end
    for item in (keepExact or ""):gmatch("([^/]+)") do
        local t = item:match("^%s*(.-)%s*$")
        if isValidFilterEntry(t) then cache.keepSet[t] = true end
    end

    cache.junkSet = {}
    for item in (junkExact or ""):gmatch("([^/]+)") do
        local t = item:match("^%s*(.-)%s*$")
        if isValidFilterEntry(t) then cache.junkSet[t] = true end
    end

    -- Augment-only list: overrides all other sell rules when item is Augmentation
    cache.augmentAlwaysSellSet = {}
    for item in (augmentAlwaysSellExact or ""):gmatch("([^/]+)") do
        local t = item:match("^%s*(.-)%s*$")
        if isValidFilterEntry(t) then cache.augmentAlwaysSellSet[t] = true end
    end

    -- Never-loot lists: sell these items to clear them from inventory (then won't loot again)
    cache.neverLootSellSet = {}
    for item in (skipExact or ""):gmatch("([^/]+)") do
        local t = item:match("^%s*(.-)%s*$")
        if isValidFilterEntry(t) then cache.neverLootSellSet[t] = true end
    end
    cache.augmentNeverLootSellSet = {}
    for item in (augmentSkipExact or ""):gmatch("([^/]+)") do
        local t = item:match("^%s*(.-)%s*$")
        if isValidFilterEntry(t) then cache.augmentNeverLootSellSet[t] = true end
    end

    cache.protectedTypeSet = {}
    for pt in (protectedTypes or ""):gmatch("([^/]+)") do
        local t = pt:match("^%s*(.-)%s*$")
        if isValidFilterEntry(t) then cache.protectedTypeSet[t] = true end
    end

    cache.keepContainsList = {}
    for _, str in ipairs({ sharedValuableContains, keepContains }) do
        for s in (str or ""):gmatch("([^/]+)") do
            local x = s:match("^%s*(.-)%s*$")
            if isValidFilterEntry(x) then cache.keepContainsList[#cache.keepContainsList + 1] = x end
        end
    end

    cache.keepTypeSet = {}
    for _, str in ipairs({ sharedValuableTypes, keepTypes, protectedTypes }) do
        for pt in (str or ""):gmatch("([^/]+)") do
            local t = pt:match("^%s*(.-)%s*$")
            if isValidFilterEntry(t) then cache.keepTypeSet[t] = true end
        end
    end

    -- Epic quest items - protect from selling when protectEpic (class-filtered via epic_classes.ini)
    cache.epicItemSet = {}
    if cache.protectEpic then
        cache.epicItemSet = loadEpicItemSetByClass()
    end

    return cache
end

--- Check if item name is in keep list (exact match). Uses cache.
local function isInKeepList(itemName, cache)
    if not itemName then return false end
    if cache and cache.keepSet then
        return cache.keepSet[itemName] or false
    end
    return false
end

--- Check if item name is in junk/always-sell list (exact match). Uses cache.
local function isInJunkList(itemName, cache)
    if not itemName then return false end
    if cache and cache.junkSet then
        return cache.junkSet[itemName] or false
    end
    return false
end

--- Check if item name contains any keep keyword. Uses cache.
local function isKeptByContains(itemName, cache)
    if not itemName or itemName == "" then return false end
    if cache and cache.keepContainsList then
        for _, kw in ipairs(cache.keepContainsList) do
            if itemName:find(kw, 1, true) then return true end
        end
    end
    return false
end

--- Check if item type is in keep/protected types. Uses cache.
local function isKeptByType(itemType, cache)
    if not itemType or itemType == "" then return false end
    local t = itemType:match("^%s*(.-)%s*$")
    if cache and cache.keepTypeSet then
        return cache.keepTypeSet[t] or false
    end
    return false
end

--- Check if item type is in protected types list. Uses cache.
local function isProtectedType(itemType, cache)
    if not itemType or itemType == "" then return false end
    local t = itemType:match("^%s*(.-)%s*$")
    if cache and cache.protectedTypeSet then
        return cache.protectedTypeSet[t] or false
    end
    return false
end

--- Determine if item will be sold. Mirrors sell.mac EvaluateItem.
--- @param itemData table { name, type, value, totalValue, stackSize, nodrop, notrade, lore, quest, collectible, heirloom, inKeep, inJunk }
--- @param cache table|nil Sell config cache from loadSellConfigCache()
--- @return boolean willSell, string reason
local function willItemBeSold(itemData, cache)
    local cfg = cache or {}
    -- Augment-only list overrides all other sell/keep rules
    local itemType = (itemData.type or ""):match("^%s*(.-)%s*$")
    if itemType == "Augmentation" and cfg.augmentAlwaysSellSet and itemData.name and cfg.augmentAlwaysSellSet[itemData.name] then
        return true, "AugmentAlwaysSell"
    end
    -- Never-loot list: sell to clear from inventory (then won't loot again)
    if itemType == "Augmentation" and cfg.augmentNeverLootSellSet and itemData.name and cfg.augmentNeverLootSellSet[itemData.name] then
        return true, "AugmentNeverLoot"
    end
    if cfg.neverLootSellSet and itemData.name and cfg.neverLootSellSet[itemData.name] then
        return true, "NeverLoot"
    end
    local protectNoDrop = cfg.protectNoDrop ~= false
    local protectNoTrade = cfg.protectNoTrade ~= false
    local protectLore = cfg.protectLore ~= false
    local protectQuest = cfg.protectQuest ~= false
    local protectCollectible = cfg.protectCollectible ~= false
    local protectHeirloom = cfg.protectHeirloom ~= false
    local minSell = cfg.minSell or 50
    local minStack = cfg.minStack or 10
    local maxKeep = cfg.maxKeep or 10000

    if protectNoDrop and itemData.nodrop then return false, "NoDrop" end
    if protectNoTrade and itemData.notrade then return false, "NoTrade" end
    local epicKey = itemData.name and normalizeItemName(itemData.name) or ""
    if cfg.epicItemSet and epicKey ~= "" and cfg.epicItemSet[epicKey] then return false, "Epic" end
    if itemData.inKeep then return false, "Keep" end
    if itemData.inJunk then return true, "Junk" end
    if protectLore and itemData.lore then return false, "Lore" end
    if protectQuest and itemData.quest then return false, "Quest" end
    if protectCollectible and itemData.collectible then return false, "Collectible" end
    if protectHeirloom and itemData.heirloom then return false, "Heirloom" end
    if maxKeep > 0 and itemData.totalValue and itemData.totalValue >= maxKeep then return false, "HighValue" end
    local isStack = (itemData.stackSize or 1) > 1
    local val = itemData.value or 0
    if isStack and val < minStack then return false, "BelowSell" end
    if not isStack and val < minSell then return false, "BelowSell" end
    return true, "Sell"
end

-- ============================================================================
-- Loot rules (mirrors loot.mac EvaluateItem order)
-- Used when ItemUI adds live Loot view (Phase 3)
-- ============================================================================

--- Build loot config cache from INI.
local function loadLootConfigCache()
    local sharedExact = readSharedListValue("valuable_exact.ini", "Items", "exact", "")
    local sharedContains = readSharedListValue("valuable_contains.ini", "Items", "contains", "")
    local sharedTypes = readSharedListValue("valuable_types.ini", "Items", "types", "")
    local alwaysExact = readLootListValue("loot_always_exact.ini", "Items", "exact", "")
    local alwaysContains = readLootListValue("loot_always_contains.ini", "Items", "contains", "")
    local alwaysTypes = readLootListValue("loot_always_types.ini", "Items", "types", "")
    local skipExact = readLootListValue("loot_skip_exact.ini", "Items", "exact", "")
    local skipContains = readLootListValue("loot_skip_contains.ini", "Items", "contains", "")
    local skipTypes = readLootListValue("loot_skip_types.ini", "Items", "types", "")
    local augmentSkipExact = readLootListValue("loot_augment_skip_exact.ini", "Items", "exact", "")

    local cache = {
        minLootValue = tonumber(readLootINIValue("loot_value.ini", "Settings", "minLootValue", "999")) or 999,
        minLootValueStack = tonumber(readLootINIValue("loot_value.ini", "Settings", "minLootValueStack", "200")) or 200,
        tributeOverride = tonumber(readLootINIValue("loot_value.ini", "Settings", "tributeOverride", "0")) or 0,
        lootClickies = readLootINIValue("loot_flags.ini", "Settings", "lootClickies", "FALSE") == "TRUE",
        lootQuest = readLootINIValue("loot_flags.ini", "Settings", "lootQuest", "FALSE") == "TRUE",
        lootCollectible = readLootINIValue("loot_flags.ini", "Settings", "lootCollectible", "FALSE") == "TRUE",
        lootHeirloom = readLootINIValue("loot_flags.ini", "Settings", "lootHeirloom", "FALSE") == "TRUE",
        lootAttuneable = readLootINIValue("loot_flags.ini", "Settings", "lootAttuneable", "FALSE") == "TRUE",
        lootAugSlots = readLootINIValue("loot_flags.ini", "Settings", "lootAugSlots", "FALSE") == "TRUE",
        alwaysLootEpic = readLootINIValue("loot_flags.ini", "Settings", "alwaysLootEpic", "TRUE") == "TRUE",
    }

    local function isValidEntry(t)
        if not t or t == "" then return false end
        local lower = t:lower()
        if lower == "null" or lower == "nil" then return false end
        return true
    end
    local function buildSet(str)
        local s = {}
        for item in (str or ""):gmatch("([^/]+)") do
            local t = item:match("^%s*(.-)%s*$")
            if isValidFilterEntry(t) then s[t] = true end
        end
        return s
    end

    local function mergeExact(a, b)
        if not a or a == "" then return b or "" end
        if not b or b == "" then return a end
        return a .. "/" .. b
    end

    cache.skipExactSet = buildSet(skipExact)
    -- Augment-only list: overrides all other loot rules when item is Augmentation
    cache.augmentSkipExactSet = buildSet(augmentSkipExact)
    cache.skipContainsList = {}
    for s in (skipContains or ""):gmatch("([^/]+)") do
        local x = s:match("^%s*(.-)%s*$")
        if isValidEntry(x) then cache.skipContainsList[#cache.skipContainsList + 1] = x end
    end
    cache.skipTypeSet = buildSet(skipTypes)

    cache.alwaysLootExactSet = buildSet(mergeExact(sharedExact, alwaysExact))
    cache.alwaysLootContainsList = {}
    for _, str in ipairs({ sharedContains, alwaysContains }) do
        for s in (str or ""):gmatch("([^/]+)") do
            local x = s:match("^%s*(.-)%s*$")
            if isValidFilterEntry(x) then cache.alwaysLootContainsList[#cache.alwaysLootContainsList + 1] = x end
        end
    end
    cache.alwaysLootTypeSet = buildSet(mergeExact(sharedTypes, alwaysTypes))

    -- Epic quest items - always loot when alwaysLootEpic (class-filtered via epic_classes.ini)
    cache.epicItemSet = {}
    if cache.alwaysLootEpic then
        cache.epicItemSet = loadEpicItemSetByClass()
    end

    return cache
end

--- Determine if item should be looted. Mirrors loot.mac EvaluateItem.
--- @param itemData table { name, type, value, tribute, stackSize, lore, clicky, quest, collectible, heirloom, attuneable, augSlots }
--- @param cache table|nil Loot config cache from loadLootConfigCache()
--- @return boolean shouldLoot, string reason
local function shouldItemBeLooted(itemData, cache)
    if not cache then return false, "NoConfig" end

    local name = itemData.name or ""
    local itemType = (itemData.type or ""):match("^%s*(.-)%s*$")
    local epicKey = normalizeItemName(name)

    -- Augment-only list overrides all other loot rules (never loot)
    if itemType == "Augmentation" and cache.augmentSkipExactSet and cache.augmentSkipExactSet[name] then
        return false, "AugmentNeverLoot"
    end
    -- Epic quest items: always loot (highest priority, before skip lists)
    if cache.alwaysLootEpic and cache.epicItemSet and epicKey ~= "" and cache.epicItemSet[epicKey] then
        return true, "Epic"
    end
    local value = itemData.value or 0
    local tribute = itemData.tribute or 0
    local isStackable = (itemData.stackSize or 1) > 1

    -- Skip lists (highest priority)
    if cache.skipExactSet and cache.skipExactSet[name] then return false, "SkipExact" end
    if cache.skipContainsList then
        for _, kw in ipairs(cache.skipContainsList) do
            if name:find(kw, 1, true) then return false, "SkipContains" end
        end
    end
    if cache.skipTypeSet and cache.skipTypeSet[itemType] then return false, "SkipType" end

    -- Tribute override
    if cache.tributeOverride and cache.tributeOverride > 0 and tribute >= cache.tributeOverride then
        return true, "TributeOverride"
    end

    -- Always loot exact
    if cache.alwaysLootExactSet and cache.alwaysLootExactSet[name] then return true, "AlwaysExact" end

    -- Always loot contains
    if cache.alwaysLootContainsList then
        for _, kw in ipairs(cache.alwaysLootContainsList) do
            if name:find(kw, 1, true) then return true, "AlwaysContains" end
        end
    end

    -- Always loot type
    if cache.alwaysLootTypeSet and cache.alwaysLootTypeSet[itemType] then return true, "AlwaysType" end

    -- Value checks
    local minVal = isStackable and cache.minLootValueStack or cache.minLootValue
    if value >= minVal then return true, "Value" end

    -- Flag checks
    if cache.lootClickies and itemData.clicky and itemData.wornSlots then return true, "Clicky" end
    if cache.lootQuest and itemData.quest then return true, "Quest" end
    if cache.lootCollectible and itemData.collectible then return true, "Collectible" end
    if cache.lootHeirloom and itemData.heirloom then return true, "Heirloom" end
    if cache.lootAttuneable and itemData.attuneable then return true, "Attuneable" end
    if cache.lootAugSlots and itemData.augSlots and itemData.augSlots > 0 then return true, "AugSlots" end

    return false, "NoMatch"
end

return {
    -- Sell
    loadSellConfigCache = loadSellConfigCache,
    EPIC_CLASSES = EPIC_CLASSES,
    isInKeepList = isInKeepList,
    isInJunkList = isInJunkList,
    isKeptByContains = isKeptByContains,
    isKeptByType = isKeptByType,
    isProtectedType = isProtectedType,
    willItemBeSold = willItemBeSold,
    -- Loot (for Phase 3 Loot view)
    loadLootConfigCache = loadLootConfigCache,
    shouldItemBeLooted = shouldItemBeLooted,
}
