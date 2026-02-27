--[[
    Config filter targets - Builds and exposes SELL_FILTER_TARGETS, VALUABLE_FILTER_TARGET, LOOT_FILTER_TARGETS from ctx.
    Used by config_filters_actions.lua and config_filters_ui.lua. No ImGui, no events, no INI writes.
    Part of Task 6.3: config_filters split.
--]]

local M = {}

local SELL_FILTER_TARGETS
local VALUABLE_FILTER_TARGET
local LOOT_FILTER_TARGETS

function M.refresh(ctx)
    local config = ctx.config
    local writeListValue = config.writeListValue
    local writeLootListValue = config.writeLootListValue
    local writeSharedListValue = config.writeSharedListValue
    local configSellLists = ctx.configSellLists
    local configLootLists = ctx.configLootLists

    SELL_FILTER_TARGETS = {
        { id = "keep", label = "Keep (never sell)", hasExact = true, hasContains = true, hasTypes = true,
          exact = { "keepExact", "sell_keep_exact.ini", "exact", writeListValue, configSellLists },
          contains = { "keepContains", "sell_keep_contains.ini", "contains", writeListValue, configSellLists },
          types = { "keepTypes", "sell_keep_types.ini", "types", writeListValue, configSellLists } },
        { id = "junk", label = "Always sell", hasExact = true, hasContains = true, hasTypes = false,
          exact = { "junkExact", "sell_always_sell_exact.ini", "exact", writeListValue, configSellLists },
          contains = { "junkContains", "sell_always_sell_contains.ini", "contains", writeListValue, configSellLists },
          types = nil },
        { id = "protected", label = "Never sell by type", hasExact = false, hasContains = false, hasTypes = true,
          exact = nil, contains = nil,
          types = { "protectedTypes", "sell_protected_types.ini", "types", writeListValue, configSellLists } },
    }
    VALUABLE_FILTER_TARGET = {
        id = "valuable", label = "Valuable (never sell + always loot)", hasExact = true, hasContains = true, hasTypes = true,
        exact = { "sharedExact", "valuable_exact.ini", "exact", writeSharedListValue, configLootLists },
        contains = { "sharedContains", "valuable_contains.ini", "contains", writeSharedListValue, configLootLists },
        types = { "sharedTypes", "valuable_types.ini", "types", writeSharedListValue, configLootLists },
    }
    LOOT_FILTER_TARGETS = {
        { id = "always", label = "Always loot", hasExact = true, hasContains = true, hasTypes = true,
          exact = { "alwaysExact", "loot_always_exact.ini", "exact", writeLootListValue, configLootLists },
          contains = { "alwaysContains", "loot_always_contains.ini", "contains", writeLootListValue, configLootLists },
          types = { "alwaysTypes", "loot_always_types.ini", "types", writeLootListValue, configLootLists } },
        { id = "skip", label = "Skip (never loot)", hasExact = true, hasContains = true, hasTypes = true,
          exact = { "skipExact", "loot_skip_exact.ini", "exact", writeLootListValue, configLootLists },
          contains = { "skipContains", "loot_skip_contains.ini", "contains", writeLootListValue, configLootLists },
          types = { "skipTypes", "loot_skip_types.ini", "types", writeLootListValue, configLootLists } },
    }
end

function M.getSellTargetById(id)
    if not SELL_FILTER_TARGETS then return nil end
    for _, t in ipairs(SELL_FILTER_TARGETS) do if t.id == id then return t end end
    return nil
end

function M.getLootTargetById(id)
    if not LOOT_FILTER_TARGETS then return nil end
    for _, t in ipairs(LOOT_FILTER_TARGETS) do if t.id == id then return t end end
    return nil
end

function M.getSELL_FILTER_TARGETS()
    return SELL_FILTER_TARGETS or {}
end

function M.getVALUABLE_FILTER_TARGET()
    return VALUABLE_FILTER_TARGET
end

function M.getLOOT_FILTER_TARGETS()
    return LOOT_FILTER_TARGETS or {}
end

return M
