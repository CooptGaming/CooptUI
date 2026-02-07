--[[
    ItemUI Advanced Filters Component
    UI panel for multi-criterion filtering
    
    Features:
    - Value range sliders
    - Type dropdown (multi-select)
    - Flag checkboxes
    - Show only sellable/lootable toggles
    - Collapsible panel
    
    Usage:
        local filters = require('itemui.components.filters')
        
        -- In render function:
        local changed, newFilter = filters.render({
            filter = currentFilter,
            view = 'inventory',
            collapsed = filtersCollapsed
        })
        
        if changed then
            currentFilter = newFilter
            -- Apply filter
        end
--]]

local ImGui = require('ImGui')

local Filters = {
    _collapsed = {},  -- { view = boolean }
    _itemTypes = {    -- Common EQ item types
        'Weapon', 'Armor', 'Shield', 'Container', 'Food', 'Drink',
        'Potion', 'Scroll', 'Spell', 'Augment', 'Jewelry', 'Instrument',
        'Book', 'Key', 'Tradeskill', 'Quest', 'Collectible'
    },
}

local hasType
local removeType

--- Render advanced filters panel
-- @param options table { filter, view, collapsed }
-- @return boolean changed, table newFilter
function Filters.render(options)
    options = options or {}
    local filter = options.filter or {}
    local view = options.view or 'default'
    local collapsed = options.collapsed
    if collapsed == nil then
        collapsed = Filters._collapsed[view] or false
    end
    
    local changed = false
    local newFilter = {}
    -- Copy existing filter
    for k, v in pairs(filter) do
        if type(v) == 'table' then
            newFilter[k] = {}
            for k2, v2 in pairs(v) do
                newFilter[k][k2] = v2
            end
        else
            newFilter[k] = v
        end
    end
    
    -- Collapsible header
    local headerText = "Advanced Filters"
    if collapsed then
        headerText = "Advanced Filters ▶"
    else
        headerText = "Advanced Filters ▼"
    end
    
    if ImGui.CollapsingHeader(headerText, collapsed and 0 or ImGuiTreeNodeFlags.DefaultOpen) then
        Filters._collapsed[view] = false
        
        ImGui.Indent(10)
        
        -- Value range
        ImGui.Text("Value Range (pp):")
        ImGui.PushItemWidth(120)
        
        local minVal = filter.minValue or 0
        local minChanged, newMinVal = ImGui.InputInt("Min##minval_" .. view, minVal, 100, 1000)
        if minChanged then
            newFilter.minValue = math.max(0, newMinVal)
            changed = true
        end
        
        ImGui.SameLine()
        local maxVal = filter.maxValue or 0
        local maxChanged, newMaxVal = ImGui.InputInt("Max##maxval_" .. view, maxVal, 100, 1000)
        if maxChanged then
            newFilter.maxValue = math.max(0, newMaxVal)
            changed = true
        end
        
        ImGui.PopItemWidth()
        
        -- Quick value presets
        ImGui.SameLine()
        if ImGui.SmallButton("1k+##val1k") then
            newFilter.minValue = 1000
            newFilter.maxValue = nil
            changed = true
        end
        if ImGui.IsItemHovered() then ImGui.SetTooltip("Items worth 1000pp or more") end
        
        ImGui.SameLine()
        if ImGui.SmallButton("5k+##val5k") then
            newFilter.minValue = 5000
            newFilter.maxValue = nil
            changed = true
        end
        if ImGui.IsItemHovered() then ImGui.SetTooltip("Items worth 5000pp or more") end
        
        ImGui.SameLine()
        if ImGui.SmallButton("Clear##valclear") then
            newFilter.minValue = nil
            newFilter.maxValue = nil
            changed = true
        end
        
        ImGui.Spacing()
        
        -- Stack size
        ImGui.Text("Stack Size:")
        ImGui.PushItemWidth(120)
        local minStack = filter.minStack or 0
        local stackChanged, newMinStack = ImGui.InputInt("Min##minstack_" .. view, minStack, 1, 10)
        if stackChanged then
            newFilter.minStack = math.max(0, newMinStack)
            changed = true
        end
        ImGui.PopItemWidth()
        
        ImGui.SameLine()
        if ImGui.SmallButton("Stacks Only##stackonly") then
            newFilter.minStack = 2
            changed = true
        end
        if ImGui.IsItemHovered() then ImGui.SetTooltip("Only show stackable items (2+)") end
        
        ImGui.Spacing()
        
        -- Weight
        ImGui.Text("Max Weight:")
        ImGui.PushItemWidth(120)
        local maxWeight = filter.maxWeight or 0
        local weightChanged, newMaxWeight = ImGui.InputInt("##maxweight_" .. view, maxWeight, 1, 10)
        if weightChanged then
            newFilter.maxWeight = math.max(0, newMaxWeight)
            changed = true
        end
        ImGui.PopItemWidth()
        
        ImGui.SameLine()
        if ImGui.SmallButton("Light (<10)##light") then
            newFilter.maxWeight = 10
            changed = true
        end
        if ImGui.IsItemHovered() then ImGui.SetTooltip("Items weighing 10 or less") end
        
        ImGui.Spacing()
        
        -- Item types
        if ImGui.TreeNode("Item Types##types_" .. view) then
            newFilter.types = newFilter.types or {}
            
            local cols = 3
            local colWidth = ImGui.GetContentRegionAvail() / cols
            
            for i, itemType in ipairs(Filters._itemTypes) do
                local isSelected = hasType(newFilter.types, itemType)
                local typeChanged, newSelected = ImGui.Checkbox(itemType .. "##type_" .. i, isSelected)
                if typeChanged then
                    if newSelected then
                        table.insert(newFilter.types, itemType)
                    else
                        removeType(newFilter.types, itemType)
                    end
                    changed = true
                end
                
                -- Column layout
                if i % cols ~= 0 then
                    ImGui.SameLine()
                end
            end
            
            -- Clear types button
            if #newFilter.types > 0 then
                ImGui.Spacing()
                if ImGui.SmallButton("Clear Types##cleartypes") then
                    newFilter.types = {}
                    changed = true
                end
            end
            
            ImGui.TreePop()
        end
        
        -- Flags
        if ImGui.TreeNode("Item Flags##flags_" .. view) then
            newFilter.flags = newFilter.flags or {}
            
            local flagDefs = {
                { id = 'lore', label = 'Lore', tooltip = 'Lore items (unique)' },
                { id = 'nodrop', label = 'No Drop', tooltip = 'Cannot drop' },
                { id = 'notrade', label = 'No Trade', tooltip = 'Cannot trade' },
                { id = 'quest', label = 'Quest', tooltip = 'Quest items' },
                { id = 'magic', label = 'Magic', tooltip = 'Magic items' },
                { id = 'collectible', label = 'Collectible', tooltip = 'Collectible items' },
                { id = 'tradeskills', label = 'Tradeskill', tooltip = 'Tradeskill items' },
                { id = 'heirloom', label = 'Heirloom', tooltip = 'Heirloom (account-bound)' },
                { id = 'attuneable', label = 'Attuneable', tooltip = 'Attuneable items' },
            }
            
            for _, flagDef in ipairs(flagDefs) do
                -- Tri-state: nil = don't filter, true = must have, false = must not have
                local currentState = newFilter.flags[flagDef.id]
                local stateText = currentState == nil and '?' or (currentState and '✓' or '✗')
                
                if ImGui.SmallButton(stateText .. "##flag_" .. flagDef.id) then
                    if currentState == nil then
                        newFilter.flags[flagDef.id] = true  -- Must have
                    elseif currentState == true then
                        newFilter.flags[flagDef.id] = false  -- Must not have
                    else
                        newFilter.flags[flagDef.id] = nil  -- Don't filter
                    end
                    changed = true
                end
                if ImGui.IsItemHovered() then
                    ImGui.BeginTooltip()
                    ImGui.Text(flagDef.tooltip)
                    ImGui.Text("? = Any  ✓ = Must have  ✗ = Must not have")
                    ImGui.EndTooltip()
                end
                
                ImGui.SameLine()
                ImGui.Text(flagDef.label)
            end
            
            -- Clear flags button
            local hasFlags = false
            for _, v in pairs(newFilter.flags) do
                if v ~= nil then
                    hasFlags = true
                    break
                end
            end
            
            if hasFlags then
                ImGui.Spacing()
                if ImGui.SmallButton("Clear Flags##clearflags") then
                    newFilter.flags = {}
                    changed = true
                end
            end
            
            ImGui.TreePop()
        end
        
        ImGui.Spacing()
        
        -- Show only toggles (for specific views)
        if view == 'sell' then
            local showSellable = newFilter.showOnlySellable or false
            local sellChanged, newShowSellable = ImGui.Checkbox("Show only sellable items##showsellable", showSellable)
            if sellChanged then
                newFilter.showOnlySellable = newShowSellable
                changed = true
            end
        end
        
        if view == 'loot' then
            local showLoot = newFilter.showOnlyLoot or false
            local lootChanged, newShowLoot = ImGui.Checkbox("Show only lootable items##showloot", showLoot)
            if lootChanged then
                newFilter.showOnlyLoot = newShowLoot
                changed = true
            end
        end
        
        -- Clear all filters button
        ImGui.Spacing()
        ImGui.Separator()
        if ImGui.Button("Clear All Filters##clearall_" .. view) then
            newFilter = {}
            changed = true
        end
        
        ImGui.Unindent(10)
    else
        Filters._collapsed[view] = true
    end
    
    return changed, newFilter
end

--- Render compact filter summary (shows active filters)
-- @param filter table Current filter
-- @return void
function Filters.renderSummary(filter)
    if not filter then return end
    
    local parts = {}
    
    if filter.text and filter.text ~= '' then
        table.insert(parts, string.format('Text: "%s"', filter.text))
    end
    if filter.minValue then
        table.insert(parts, string.format('Min: %dpp', filter.minValue))
    end
    if filter.maxValue then
        table.insert(parts, string.format('Max: %dpp', filter.maxValue))
    end
    if filter.types and #filter.types > 0 then
        table.insert(parts, 'Types: ' .. #filter.types)
    end
    if filter.flags then
        local flagCount = 0
        for _, v in pairs(filter.flags) do
            if v ~= nil then flagCount = flagCount + 1 end
        end
        if flagCount > 0 then
            table.insert(parts, 'Flags: ' .. flagCount)
        end
    end
    
    if #parts > 0 then
        ImGui.TextColored(ImVec4(0.5, 0.85, 0.95, 1), "Active: " .. table.concat(parts, " | "))
    end
end

-- ============================================================================
-- Internal Helpers
-- ============================================================================

--- Check if type array contains a type
local function hasType(types, typeToFind)
    if not types then return false end
    for _, t in ipairs(types) do
        if t == typeToFind then return true end
    end
    return false
end

--- Remove type from array
local function removeType(types, typeToRemove)
    if not types then return end
    for i = #types, 1, -1 do
        if types[i] == typeToRemove then
            table.remove(types, i)
        end
    end
end

return Filters
