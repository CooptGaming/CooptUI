--[[
    ItemUI Filter Service
    Centralized item-list filtering (text, value range, stack, weight, type, flags).

    Usage:
        local filterService = require('itemui.services.filter_service')

        local filtered = filterService.apply(items, {
            text = 'sword',
            minValue = 1000,
            maxValue = 10000,
            types = {'Weapon', 'Armor'},
            flags = { lore = true, nodrop = false }
        })
--]]

local FilterService = {}

--- Apply filter to item list
-- @param items table Array of item objects
-- @param filter table Filter specification
-- @return table Filtered items array
function FilterService.apply(items, filter)
    if not items or #items == 0 then
        return {}
    end

    if not filter then
        return items
    end

    local filtered = {}

    for _, item in ipairs(items) do
        if FilterService.matchesFilter(item, filter) then
            table.insert(filtered, item)
        end
    end

    return filtered
end

--- Check if single item matches filter
-- @param item table Item object
-- @param filter table Filter specification
-- @return boolean True if item matches filter
function FilterService.matchesFilter(item, filter)
    -- Text search (item name, case-insensitive); trim so "  foo  " matches "foo"
    if filter.text and filter.text ~= '' then
        local searchTrimmed = filter.text:match("^%s*(.-)%s*$") or ""
        if searchTrimmed ~= "" then
            local searchLower = searchTrimmed:lower()
            local nameTrimmed = (item.name or ""):match("^%s*(.-)%s*$") or ""
            local nameLower = nameTrimmed:lower()
            if not nameLower:find(searchLower, 1, true) then
                return false
            end
        end
    end

    -- Min value
    if filter.minValue and (item.value or 0) < filter.minValue then
        return false
    end

    -- Max value
    if filter.maxValue and (item.value or 0) > filter.maxValue then
        return false
    end

    -- Min stack size
    if filter.minStack and (item.stackSize or 1) < filter.minStack then
        return false
    end

    -- Max weight
    if filter.maxWeight and (item.weight or 0) > filter.maxWeight then
        return false
    end

    -- Item types (exact match)
    if filter.types and #filter.types > 0 then
        local typeMatch = false
        local itemType = item.type or ''
        for _, filterType in ipairs(filter.types) do
            if itemType == filterType then
                typeMatch = true
                break
            end
        end
        if not typeMatch then
            return false
        end
    end

    -- Flags (boolean properties)
    if filter.flags then
        for flagName, required in pairs(filter.flags) do
            local itemHasFlag = item[flagName] or false
            -- If required is true, item must have flag
            -- If required is false, item must NOT have flag
            if required and not itemHasFlag then
                return false
            end
            if not required and itemHasFlag then
                return false
            end
        end
    end

    -- Show only sellable (for sell view)
    if filter.showOnlySellable and not item.willSell then
        return false
    end

    -- Show only lootable (for loot view)
    if filter.showOnlyLoot and not item.willLoot then
        return false
    end

    return true
end

return FilterService
