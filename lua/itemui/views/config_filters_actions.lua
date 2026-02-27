--[[
    Config filter actions - Conflict checks and list add/remove; INI writes, cache invalidation, event emission.
    Used by config_filters_ui.lua. Requires config_filters_targets. No ImGui.
    Part of Task 6.3: config_filters split.
--]]

local targets = require('itemui.views.config_filters_targets')
local events = require('itemui.core.events')

local M = {}

function M.checkSellFilterConflicts(ctx, targetId, typeKey, value)
    local conflicts = {}
    if targetId == "keep" or targetId == "junk" then
        local otherId = (targetId == "keep") and "junk" or "keep"
        local other = targets.getSellTargetById(otherId)
        if other and other[typeKey] then
            local def = other[typeKey]
            local listKey, _, _, _, lists = def[1], def[2], def[3], def[4], def[5]
            local list = lists[listKey]
            for _, s in ipairs(list) do
                if s == value then
                    conflicts[#conflicts + 1] = { targetId = otherId, label = other.label }
                    break
                end
            end
        end
    end
    if targetId == "junk" then
        local v = targets.getVALUABLE_FILTER_TARGET()
        if v and v[typeKey] then
            local def = v[typeKey]
            local listKey, _, _, _, lists = def[1], def[2], def[3], def[4], def[5]
            local list = lists[listKey]
            for _, s in ipairs(list) do
                if s == value then
                    conflicts[#conflicts + 1] = { targetId = "valuable", label = v.label }
                    break
                end
            end
        end
    end
    return conflicts
end

function M.checkValuableFilterConflicts(ctx, typeKey, value)
    local conflicts = {}
    local junk = targets.getSellTargetById("junk")
    if junk and junk[typeKey] then
        local def = junk[typeKey]
        local listKey, _, _, _, lists = def[1], def[2], def[3], def[4], def[5]
        local list = lists[listKey]
        for _, s in ipairs(list) do
            if s == value then
                conflicts[#conflicts + 1] = { targetId = "junk", label = junk.label }
                break
            end
        end
    end
    local skip = targets.getLootTargetById("skip")
    if skip and skip[typeKey] then
        local def = skip[typeKey]
        local listKey, _, _, _, lists = def[1], def[2], def[3], def[4], def[5]
        local list = lists[listKey]
        for _, s in ipairs(list) do
            if s == value then
                conflicts[#conflicts + 1] = { targetId = "skip", label = skip.label }
                break
            end
        end
    end
    return conflicts
end

function M.checkLootFilterConflicts(ctx, targetId, typeKey, value)
    local conflicts = {}
    if targetId == "always" then
        local skip = targets.getLootTargetById("skip")
        if skip and skip[typeKey] then
            local def = skip[typeKey]
            local listKey, _, _, _, lists = def[1], def[2], def[3], def[4], def[5]
            local list = lists[listKey]
            for _, s in ipairs(list) do
                if s == value then
                    conflicts[#conflicts + 1] = { targetId = "skip", label = skip.label }
                    break
                end
            end
        end
    elseif targetId == "skip" then
        local always = targets.getLootTargetById("always")
        if always then
            local function inList(def)
                if not def then return false end
                local listKey, _, _, _, lists = def[1], def[2], def[3], def[4], def[5]
                local list = lists[listKey]
                for _, s in ipairs(list) do if s == value then return true end end
                return false
            end
            if inList(always[typeKey]) then
                conflicts[#conflicts + 1] = { targetId = "always", label = always.label }
            end
            local v = targets.getVALUABLE_FILTER_TARGET()
            if v and inList(v[typeKey]) then
                conflicts[#conflicts + 1] = { targetId = "valuable", label = v.label }
            end
        end
    end
    return conflicts
end

function M.performSellFilterAdd(ctx, targetId, typeKey, value)
    local target = targets.getSellTargetById(targetId)
    if not target then return false end
    local def = target[typeKey]
    if not def then return false end
    local listKey, iniFile, iniKey, writeFn, lists = def[1], def[2], def[3], def[4], def[5]
    local list = lists[listKey]
    for _, s in ipairs(list) do if s == value then return false end end
    list[#list + 1] = value
    writeFn(iniFile, "Items", iniKey, ctx.config.joinList(list))
    ctx.invalidateSellConfigCache()
    events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
    return true
end

function M.performValuableFilterAdd(ctx, typeKey, value)
    local v = targets.getVALUABLE_FILTER_TARGET()
    if not v or not v[typeKey] then return false end
    local def = v[typeKey]
    local listKey, iniFile, iniKey, writeFn, lists = def[1], def[2], def[3], def[4], def[5]
    local list = lists[listKey]
    for _, s in ipairs(list) do if s == value then return false end end
    list[#list + 1] = value
    writeFn(iniFile, "Items", iniKey, ctx.config.joinList(list))
    ctx.invalidateSellConfigCache()
    events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
    events.emit(events.EVENTS.CONFIG_LOOT_CHANGED)
    return true
end

function M.performLootFilterAdd(ctx, targetId, typeKey, value)
    local target = targets.getLootTargetById(targetId)
    if not target then return false end
    local def = target[typeKey]
    if not def then return false end
    local listKey, iniFile, iniKey, writeFn, lists = def[1], def[2], def[3], def[4], def[5]
    local list = lists[listKey]
    for _, s in ipairs(list) do if s == value then return false end end
    list[#list + 1] = value
    writeFn(iniFile, "Items", iniKey, ctx.config.joinList(list))
    ctx.invalidateSellConfigCache()
    ctx.invalidateLootConfigCache()
    events.emit(events.EVENTS.CONFIG_LOOT_CHANGED)
    return true
end

function M.removeFromSellFilterList(ctx, targetId, typeKey, value)
    local target = targets.getSellTargetById(targetId)
    if not target or not target[typeKey] then return false end
    local def = target[typeKey]
    local listKey, iniFile, iniKey, writeFn, lists = def[1], def[2], def[3], def[4], def[5]
    local list = lists[listKey]
    for i = #list, 1, -1 do
        if list[i] == value then
            table.remove(list, i)
            writeFn(iniFile, "Items", iniKey, ctx.config.joinList(list))
            ctx.invalidateSellConfigCache()
            events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
            return true
        end
    end
    return false
end

function M.removeFromLootFilterList(ctx, targetId, typeKey, value)
    local target = targets.getLootTargetById(targetId)
    if not target or not target[typeKey] then return false end
    local def = target[typeKey]
    local listKey, iniFile, iniKey, writeFn, lists = def[1], def[2], def[3], def[4], def[5]
    local list = lists[listKey]
    for i = #list, 1, -1 do
        if list[i] == value then
            table.remove(list, i)
            writeFn(iniFile, "Items", iniKey, ctx.config.joinList(list))
            ctx.invalidateSellConfigCache()
            ctx.invalidateLootConfigCache()
            events.emit(events.EVENTS.CONFIG_LOOT_CHANGED)
            return true
        end
    end
    return false
end

function M.removeFromValuableFilterList(ctx, typeKey, value)
    local v = targets.getVALUABLE_FILTER_TARGET()
    if not v or not v[typeKey] then return false end
    local def = v[typeKey]
    local listKey, iniFile, iniKey, writeFn, lists = def[1], def[2], def[3], def[4], def[5]
    local list = lists[listKey]
    for i = #list, 1, -1 do
        if list[i] == value then
            table.remove(list, i)
            writeFn(iniFile, "Items", iniKey, ctx.config.joinList(list))
            ctx.invalidateSellConfigCache()
            events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
            events.emit(events.EVENTS.CONFIG_LOOT_CHANGED)
            return true
        end
    end
    return false
end

return M
