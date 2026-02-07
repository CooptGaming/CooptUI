--[[
    ItemUI Filter Service
    Centralized filtering logic with persistence and presets
    
    Features:
    - Apply filters to item lists
    - Save/load filter presets
    - Persist last used filters per view
    - Multi-column filtering (text, value range, type, flags)
    - Debounced filter application
    
    Usage:
        local filterService = require('itemui.services.filter_service')
        
        -- Apply filter
        local filtered = filterService.apply(items, {
            text = 'sword',
            minValue = 1000,
            maxValue = 10000,
            types = {'Weapon', 'Armor'},
            flags = { lore = true, nodrop = false }
        })
        
        -- Save preset
        filterService.savePreset('expensive_weapons', {
            text = '',
            minValue = 5000,
            types = {'Weapon'}
        })
        
        -- Load presets
        local presets = filterService.loadPresets()
        
        -- Apply preset by name
        local filtered = filterService.applyPreset(items, 'expensive_weapons')
--]]

local config = require('itemui.config')

local FilterService = {
    _presetsFile = 'itemui_filter_presets.ini',
    _lastFiltersFile = 'itemui_last_filters.ini',
    _presets = {},  -- Loaded presets cache
    _lastFilters = {},  -- Last used filters per view
}

--- Initialize filter service (loads presets and last filters)
function FilterService.init()
    FilterService._presets = FilterService.loadPresets()
    FilterService._lastFilters = FilterService.loadLastFilters()
end

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
    -- Text search (item name, case-insensitive)
    if filter.text and filter.text ~= '' then
        local searchLower = filter.text:lower()
        local nameLower = (item.name or ''):lower()
        if not nameLower:find(searchLower, 1, true) then
            return false
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

--- Save filter preset
-- @param name string Preset name
-- @param filter table Filter specification
function FilterService.savePreset(name, filter)
    if not name or name == '' then
        error('FilterService.savePreset: name is required')
    end
    
    FilterService._presets[name] = filter
    
    -- Persist to INI
    local path = config.getConfigFile(FilterService._presetsFile)
    
    -- Serialize filter to INI format
    config.writeINIValue(path, 'Presets', name .. '_text', filter.text or '')
    config.writeINIValue(path, 'Presets', name .. '_minValue', tostring(filter.minValue or ''))
    config.writeINIValue(path, 'Presets', name .. '_maxValue', tostring(filter.maxValue or ''))
    config.writeINIValue(path, 'Presets', name .. '_minStack', tostring(filter.minStack or ''))
    config.writeINIValue(path, 'Presets', name .. '_maxWeight', tostring(filter.maxWeight or ''))
    
    -- Serialize types array
    if filter.types then
        config.writeINIValue(path, 'Presets', name .. '_types', table.concat(filter.types, ','))
    end
    
    -- Serialize flags
    if filter.flags then
        local flagsStr = {}
        for flagName, value in pairs(filter.flags) do
            table.insert(flagsStr, flagName .. '=' .. tostring(value))
        end
        config.writeINIValue(path, 'Presets', name .. '_flags', table.concat(flagsStr, ','))
    end
    
    config.writeINIValue(path, 'Presets', name .. '_showOnlySellable', tostring(filter.showOnlySellable or false))
    config.writeINIValue(path, 'Presets', name .. '_showOnlyLoot', tostring(filter.showOnlyLoot or false))
end

--- Load all filter presets from disk
-- @return table { presetName = filterSpec, ... }
function FilterService.loadPresets()
    local presets = {}
    local path = config.getConfigFile(FilterService._presetsFile)
    
    -- Get all preset names from INI (keys ending with _text)
    -- This is a simplified loader - could be improved with proper INI enumeration
    local builtInPresets = {
        'sellable_items',
        'expensive_items',
        'quest_items',
        'lore_items',
        'tradeskill_items'
    }
    
    for _, name in ipairs(builtInPresets) do
        local filter = {}
        filter.text = config.readINIValue(path, 'Presets', name .. '_text', '')
        
        local minVal = config.readINIValue(path, 'Presets', name .. '_minValue', '')
        if minVal ~= '' then filter.minValue = tonumber(minVal) end
        
        local maxVal = config.readINIValue(path, 'Presets', name .. '_maxValue', '')
        if maxVal ~= '' then filter.maxValue = tonumber(maxVal) end
        
        local minStack = config.readINIValue(path, 'Presets', name .. '_minStack', '')
        if minStack ~= '' then filter.minStack = tonumber(minStack) end
        
        local maxWeight = config.readINIValue(path, 'Presets', name .. '_maxWeight', '')
        if maxWeight ~= '' then filter.maxWeight = tonumber(maxWeight) end
        
        local typesStr = config.readINIValue(path, 'Presets', name .. '_types', '')
        if typesStr ~= '' then
            filter.types = {}
            for t in typesStr:gmatch('[^,]+') do
                table.insert(filter.types, t:match('^%s*(.-)%s*$'))  -- trim
            end
        end
        
        local flagsStr = config.readINIValue(path, 'Presets', name .. '_flags', '')
        if flagsStr ~= '' then
            filter.flags = {}
            for pair in flagsStr:gmatch('[^,]+') do
                local flagName, value = pair:match('([^=]+)=([^=]+)')
                if flagName and value then
                    filter.flags[flagName:match('^%s*(.-)%s*$')] = (value:match('^%s*(.-)%s*$') == 'true')
                end
            end
        end
        
        local showSellable = config.readINIValue(path, 'Presets', name .. '_showOnlySellable', 'false')
        filter.showOnlySellable = (showSellable == 'true')
        
        local showLoot = config.readINIValue(path, 'Presets', name .. '_showOnlyLoot', 'false')
        filter.showOnlyLoot = (showLoot == 'true')
        
        -- Only add preset if it has at least one filter criterion
        if filter.text ~= '' or filter.minValue or filter.maxValue or filter.types or filter.flags then
            presets[name] = filter
        end
    end
    
    return presets
end

--- Delete a filter preset
-- @param name string Preset name to delete
function FilterService.deletePreset(name)
    FilterService._presets[name] = nil
    
    -- Remove from INI
    local path = config.getConfigFile(FilterService._presetsFile)
    config.writeINIValue(path, 'Presets', name .. '_text', '')
    config.writeINIValue(path, 'Presets', name .. '_minValue', '')
    config.writeINIValue(path, 'Presets', name .. '_maxValue', '')
    config.writeINIValue(path, 'Presets', name .. '_types', '')
    config.writeINIValue(path, 'Presets', name .. '_flags', '')
    config.writeINIValue(path, 'Presets', name .. '_showOnlySellable', '')
    config.writeINIValue(path, 'Presets', name .. '_showOnlyLoot', '')
end

--- Apply preset by name
-- @param items table Items array
-- @param presetName string Name of preset to apply
-- @return table Filtered items, or original items if preset not found
function FilterService.applyPreset(items, presetName)
    local preset = FilterService._presets[presetName]
    if not preset then
        return items
    end
    return FilterService.apply(items, preset)
end

--- Save last used filter for a view
-- @param view string View name ('inventory', 'sell', 'bank', 'loot')
-- @param filter table Filter specification
function FilterService.saveLastFilter(view, filter)
    FilterService._lastFilters[view] = filter
    
    -- Persist to INI
    local path = config.getConfigFile(FilterService._lastFiltersFile)
    config.writeINIValue(path, 'LastFilters', view .. '_text', filter.text or '')
    config.writeINIValue(path, 'LastFilters', view .. '_minValue', tostring(filter.minValue or ''))
    config.writeINIValue(path, 'LastFilters', view .. '_maxValue', tostring(filter.maxValue or ''))
    config.writeINIValue(path, 'LastFilters', view .. '_showOnlySellable', tostring(filter.showOnlySellable or false))
end

--- Load last used filter for a view
-- @param view string View name
-- @return table Filter specification, or empty filter if none saved
function FilterService.getLastFilter(view)
    if FilterService._lastFilters[view] then
        return FilterService._lastFilters[view]
    end
    
    -- Load from INI
    local path = config.getConfigFile(FilterService._lastFiltersFile)
    local filter = {}
    
    filter.text = config.readINIValue(path, 'LastFilters', view .. '_text', '')
    
    local minVal = config.readINIValue(path, 'LastFilters', view .. '_minValue', '')
    if minVal ~= '' then filter.minValue = tonumber(minVal) end
    
    local maxVal = config.readINIValue(path, 'LastFilters', view .. '_maxValue', '')
    if maxVal ~= '' then filter.maxValue = tonumber(maxVal) end
    
    local showSellable = config.readINIValue(path, 'LastFilters', view .. '_showOnlySellable', 'false')
    filter.showOnlySellable = (showSellable == 'true')
    
    FilterService._lastFilters[view] = filter
    return filter
end

--- Load all last filters from disk
-- @return table { view = filterSpec, ... }
function FilterService.loadLastFilters()
    local filters = {}
    local views = {'inventory', 'sell', 'bank', 'loot'}
    
    for _, view in ipairs(views) do
        filters[view] = FilterService.getLastFilter(view)
    end
    
    return filters
end

--- Get list of preset names
-- @return table Array of preset names
function FilterService.getPresetNames()
    local names = {}
    for name, _ in pairs(FilterService._presets) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

--- Get preset by name
-- @param name string Preset name
-- @return table Filter specification, or nil if not found
function FilterService.getPreset(name)
    return FilterService._presets[name]
end

--- Create default presets if none exist
function FilterService.createDefaultPresets()
    -- Sellable items over 1000pp
    FilterService.savePreset('sellable_items', {
        text = '',
        minValue = 1000,
        showOnlySellable = true
    })
    
    -- Expensive items (5000pp+)
    FilterService.savePreset('expensive_items', {
        text = '',
        minValue = 5000
    })
    
    -- Quest items
    FilterService.savePreset('quest_items', {
        text = '',
        flags = { quest = true }
    })
    
    -- Lore items
    FilterService.savePreset('lore_items', {
        text = '',
        flags = { lore = true }
    })
    
    -- Tradeskill items
    FilterService.savePreset('tradeskill_items', {
        text = '',
        flags = { tradeskills = true }
    })
end

return FilterService
