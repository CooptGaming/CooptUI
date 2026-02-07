--[[
    ItemUI Rules Module - Unit Tests
    Tests sell and loot rule evaluation (keep/junk/protected, skip/always-loot).
    Run in-game: /lua run itemui/test_rules
--]]

local test
do
    local ok, t = pcall(require, 'IntegrationTests.mqTest')
    if ok and t then test = t else test = require('TestSuite.mqTest') end
end
local rules = require('itemui.rules')

-- Pass through any CLI args (e.g. regex filter)
local args = { ... }
test.arguments(args)

-- ============================================================================
-- Mock caches for pure function testing (no INI/mq dependency)
-- ============================================================================

local function makeSellCache(overrides)
    local c = {
        keepSet = { ["Valuable Sword"] = true, ["Epic Item"] = true },
        junkSet = { ["Junk Dagger"] = true, ["Vendor Trash"] = true },
        keepContainsList = { "Epic", "Rare", "Valuable" },
        keepTypeSet = { ["Weapon"] = true, ["Armor"] = true, ["Quest"] = true, ["Collectible"] = true },  -- merges protectedTypes
        protectedTypeSet = { ["Quest"] = true, ["Collectible"] = true },
        protectNoDrop = true,
        protectNoTrade = true,
        protectLore = true,
        protectQuest = true,
        protectCollectible = true,
        protectHeirloom = true,
        minSell = 50,
        minStack = 10,
        maxKeep = 10000,
    }
    if overrides then
        for k, v in pairs(overrides) do c[k] = v end
    end
    return c
end

local function makeLootCache(overrides)
    local c = {
        skipExactSet = { ["Skip This"] = true },
        skipContainsList = { "junk", "trash" },
        skipTypeSet = { ["Junk"] = true },
        alwaysLootExactSet = { ["Always Loot Me"] = true },
        alwaysLootContainsList = { "valuable", "rare" },
        alwaysLootTypeSet = { ["Weapon"] = true },
        minLootValue = 999,
        minLootValueStack = 200,
        tributeOverride = 1000,
        lootClickies = false,
        lootQuest = false,
        lootCollectible = false,
        lootHeirloom = false,
        lootAttuneable = false,
        lootAugSlots = false,
    }
    if overrides then
        for k, v in pairs(overrides) do c[k] = v end
    end
    return c
end

-- ============================================================================
-- Sell rules: isInKeepList
-- ============================================================================
test.sell_isInKeepList = function()
    local cache = makeSellCache()
    test.is_true(rules.isInKeepList("Valuable Sword", cache))
    test.is_true(rules.isInKeepList("Epic Item", cache))
    test.is_false(rules.isInKeepList("Unknown Item", cache))
    test.is_false(rules.isInKeepList(nil, cache))
    test.is_false(rules.isInKeepList("Valuable Sword", nil))
end

-- ============================================================================
-- Sell rules: isInJunkList
-- ============================================================================
test.sell_isInJunkList = function()
    local cache = makeSellCache()
    test.is_true(rules.isInJunkList("Junk Dagger", cache))
    test.is_true(rules.isInJunkList("Vendor Trash", cache))
    test.is_false(rules.isInJunkList("Valuable Sword", cache))
    test.is_false(rules.isInJunkList(nil, cache))
end

-- ============================================================================
-- Sell rules: isKeptByContains
-- ============================================================================
test.sell_isKeptByContains = function()
    local cache = makeSellCache()
    test.is_true(rules.isKeptByContains("Epic Sword of Doom", cache))
    test.is_true(rules.isKeptByContains("Rare Armor", cache))
    test.is_true(rules.isKeptByContains("Valuable Gem", cache))
    test.is_false(rules.isKeptByContains("Common Dagger", cache))
    test.is_false(rules.isKeptByContains("", cache))
    test.is_false(rules.isKeptByContains(nil, cache))
end

-- ============================================================================
-- Sell rules: isKeptByType
-- ============================================================================
test.sell_isKeptByType = function()
    local cache = makeSellCache()
    test.is_true(rules.isKeptByType("Weapon", cache))
    test.is_true(rules.isKeptByType("Armor", cache))
    test.is_true(rules.isKeptByType("Quest", cache))  -- in keepTypeSet via protectedTypes
    test.is_false(rules.isKeptByType("Junk", cache))
    test.is_false(rules.isKeptByType("", cache))
    test.is_false(rules.isKeptByType(nil, cache))
end

-- ============================================================================
-- Sell rules: isProtectedType
-- ============================================================================
test.sell_isProtectedType = function()
    local cache = makeSellCache()
    test.is_true(rules.isProtectedType("Quest", cache))
    test.is_true(rules.isProtectedType("Collectible", cache))
    test.is_false(rules.isProtectedType("Weapon", cache))
    test.is_false(rules.isProtectedType("Junk", cache))
end

-- ============================================================================
-- Sell rules: willItemBeSold
-- ============================================================================
test.sell_willItemBeSold_NoDrop = function()
    local cache = makeSellCache()
    local ok, reason = rules.willItemBeSold({ nodrop = true, value = 100, stackSize = 1 }, cache)
    test.is_false(ok)
    test.equal(reason, "NoDrop")
end

test.sell_willItemBeSold_NoTrade = function()
    local cache = makeSellCache()
    local ok, reason = rules.willItemBeSold({ notrade = true, value = 100, stackSize = 1 }, cache)
    test.is_false(ok)
    test.equal(reason, "NoTrade")
end

test.sell_willItemBeSold_Keep = function()
    local cache = makeSellCache()
    local ok, reason = rules.willItemBeSold({ inKeep = true, value = 100, stackSize = 1 }, cache)
    test.is_false(ok)
    test.equal(reason, "Keep")
end

test.sell_willItemBeSold_Junk = function()
    local cache = makeSellCache()
    local ok, reason = rules.willItemBeSold({ inJunk = true, value = 1, stackSize = 1 }, cache)
    test.is_true(ok)
    test.equal(reason, "Junk")
end

test.sell_willItemBeSold_Lore = function()
    local cache = makeSellCache()
    local ok, reason = rules.willItemBeSold({ lore = true, value = 100, stackSize = 1 }, cache)
    test.is_false(ok)
    test.equal(reason, "Lore")
end

test.sell_willItemBeSold_HighValue = function()
    local cache = makeSellCache()
    local ok, reason = rules.willItemBeSold({ totalValue = 15000, value = 100, stackSize = 1 }, cache)
    test.is_false(ok)
    test.equal(reason, "HighValue")
end

test.sell_willItemBeSold_BelowSell_single = function()
    local cache = makeSellCache()
    local ok, reason = rules.willItemBeSold({ value = 10, stackSize = 1 }, cache)
    test.is_false(ok)
    test.equal(reason, "BelowSell")
end

test.sell_willItemBeSold_BelowSell_stack = function()
    local cache = makeSellCache()
    local ok, reason = rules.willItemBeSold({ value = 5, stackSize = 10 }, cache)
    test.is_false(ok)
    test.equal(reason, "BelowSell")
end

test.sell_willItemBeSold_Sell = function()
    local cache = makeSellCache()
    local ok, reason = rules.willItemBeSold({ value = 100, stackSize = 1 }, cache)
    test.is_true(ok)
    test.equal(reason, "Sell")
end

test.sell_willItemBeSold_Sell_stack = function()
    local cache = makeSellCache()
    local ok, reason = rules.willItemBeSold({ value = 50, stackSize = 20 }, cache)
    test.is_true(ok)
    test.equal(reason, "Sell")
end

-- ============================================================================
-- Loot rules: shouldItemBeLooted
-- ============================================================================
test.loot_shouldItemBeLooted_NoConfig = function()
    local ok, reason = rules.shouldItemBeLooted({ name = "Test" }, nil)
    test.is_false(ok)
    test.equal(reason, "NoConfig")
end

test.loot_shouldItemBeLooted_SkipExact = function()
    local cache = makeLootCache()
    local ok, reason = rules.shouldItemBeLooted({ name = "Skip This", value = 5000 }, cache)
    test.is_false(ok)
    test.equal(reason, "SkipExact")
end

test.loot_shouldItemBeLooted_SkipContains = function()
    local cache = makeLootCache()
    -- Keyword "junk" is lowercase; string:find is case-sensitive
    local ok, reason = rules.shouldItemBeLooted({ name = "Some junk sword", value = 5000 }, cache)
    test.is_false(ok)
    test.equal(reason, "SkipContains")
end

test.loot_shouldItemBeLooted_SkipType = function()
    local cache = makeLootCache()
    local ok, reason = rules.shouldItemBeLooted({ name = "Some Junk", type = "Junk", value = 5000 }, cache)
    test.is_false(ok)
    test.equal(reason, "SkipType")
end

test.loot_shouldItemBeLooted_Epic = function()
    local cache = makeLootCache({ alwaysLootEpic = true, epicItemSet = { ["Epic Quest Blade"] = true } })
    local ok, reason = rules.shouldItemBeLooted({ name = "Epic Quest Blade", value = 0 }, cache)
    test.is_true(ok)
    test.equal(reason, "Epic")
end

test.loot_shouldItemBeLooted_EpicOverridesSkip = function()
    -- Epic items are looted even if in skip list
    local cache = makeLootCache({ alwaysLootEpic = true, epicItemSet = { ["Epic Quest Blade"] = true }, skipExactSet = { ["Epic Quest Blade"] = true } })
    local ok, reason = rules.shouldItemBeLooted({ name = "Epic Quest Blade", value = 0 }, cache)
    test.is_true(ok)
    test.equal(reason, "Epic")
end

test.loot_shouldItemBeLooted_TributeOverride = function()
    local cache = makeLootCache()
    local ok, reason = rules.shouldItemBeLooted({ name = "Tribute Item", tribute = 1500, value = 0 }, cache)
    test.is_true(ok)
    test.equal(reason, "TributeOverride")
end

test.loot_shouldItemBeLooted_AlwaysExact = function()
    local cache = makeLootCache()
    local ok, reason = rules.shouldItemBeLooted({ name = "Always Loot Me", value = 0 }, cache)
    test.is_true(ok)
    test.equal(reason, "AlwaysExact")
end

test.loot_shouldItemBeLooted_AlwaysContains = function()
    local cache = makeLootCache()
    -- Keyword "valuable" is lowercase; string:find is case-sensitive
    local ok, reason = rules.shouldItemBeLooted({ name = "Some valuable gem", value = 0 }, cache)
    test.is_true(ok)
    test.equal(reason, "AlwaysContains")
end

test.loot_shouldItemBeLooted_AlwaysType = function()
    local cache = makeLootCache()
    local ok, reason = rules.shouldItemBeLooted({ name = "Some Weapon", type = "Weapon", value = 0 }, cache)
    test.is_true(ok)
    test.equal(reason, "AlwaysType")
end

test.loot_shouldItemBeLooted_Value = function()
    local cache = makeLootCache()
    local ok, reason = rules.shouldItemBeLooted({ name = "Random Drop", value = 1500, stackSize = 1 }, cache)
    test.is_true(ok)
    test.equal(reason, "Value")
end

test.loot_shouldItemBeLooted_NoMatch = function()
    local cache = makeLootCache()
    local ok, reason = rules.shouldItemBeLooted({ name = "Common Trash", type = "Misc", value = 10 }, cache)
    test.is_false(ok)
    test.equal(reason, "NoMatch")
end

-- ============================================================================
-- Summary
-- ============================================================================
test.summary()
