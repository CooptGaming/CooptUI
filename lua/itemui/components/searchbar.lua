--[[
    ItemUI Search Bar Component
    Search input with preset selector, history, and debouncing
    
    Features:
    - Debounced text input (300ms delay before applying)
    - Clear button (X)
    - Preset dropdown
    - Save current filter as preset
    - Search history (last 5 searches)
    
    Usage:
        local searchbar = require('itemui.components.searchbar')
        
        -- In render function:
        local changed, newText = searchbar.render({
            text = currentSearchText,
            view = 'inventory',
            presets = filterService.getPresetNames(),
            onPresetSelected = function(presetName)
                -- Apply preset
            end,
            onSavePreset = function()
                -- Open save dialog
            end
        })
        
        if changed then
            currentSearchText = newText
            -- Apply filter (debounced automatically)
        end
--]]

local mq = require('mq')
local ImGui = require('ImGui')
local filterService = require('itemui.services.filter_service')
local constants = require('itemui.constants')

local SearchBar = {
    _debounceTimers = {},  -- { view = { text, timestamp } }
    _debounceDelay = constants.TIMING.SEARCH_DEBOUNCE_MS,
    _searchHistory = {},   -- { view = { searches } }
    _maxHistorySize = constants.LIMITS.SEARCH_HISTORY_MAX,
}

local addToHistory
local renderPresetTooltip

--- Render search bar with presets and history
-- @param options table { text, view, presets, width, onPresetSelected, onSavePreset }
-- @return boolean changed, string newText
function SearchBar.render(options)
    options = options or {}
    local text = options.text or ''
    local view = options.view or 'default'
    local presets = options.presets or {}
    local width = options.width or 200
    
    local changed = false
    local newText = text
    
    ImGui.PushItemWidth(width)
    
    -- Search input with clear button
    ImGui.Text("Search:")
    ImGui.SameLine()
    
    local inputChanged, inputText = ImGui.InputText("##search_" .. view, text, ImGuiInputTextFlags.None)
    if inputChanged then
        newText = inputText
        changed = true
        
        -- Update debounce timer
        SearchBar._debounceTimers[view] = {
            text = newText,
            timestamp = mq.gettime()
        }
        
        -- Add to history if not empty and different from last
        if newText ~= '' then
            addToHistory(view, newText)
        end
    end
    
    -- Clear button
    if text ~= '' then
        ImGui.SameLine()
        if ImGui.Button("X##clear_" .. view, ImVec2(20, 0)) then
            newText = ''
            changed = true
            SearchBar._debounceTimers[view] = nil
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Clear search")
        end
    end
    
    -- Preset dropdown
    if presets and #presets > 0 then
        ImGui.SameLine()
        ImGui.Text("Preset:")
        ImGui.SameLine()
        
        ImGui.PushItemWidth(150)
        if ImGui.BeginCombo("##preset_" .. view, "Select...") then
            for _, presetName in ipairs(presets) do
                local selected = false
                if ImGui.Selectable(presetName, selected) then
                    if options.onPresetSelected then
                        options.onPresetSelected(presetName)
                    end
                end
                
                -- Show preset details on hover
                if ImGui.IsItemHovered() then
                    local preset = filterService.getPreset(presetName)
                    if preset then
                        ImGui.BeginTooltip()
                        renderPresetTooltip(preset)
                        ImGui.EndTooltip()
                    end
                end
            end
            ImGui.EndCombo()
        end
        ImGui.PopItemWidth()
    end
    
    -- Save preset button
    ImGui.SameLine()
    if ImGui.Button("Save##save_preset_" .. view, ImVec2(45, 0)) then
        if options.onSavePreset then
            options.onSavePreset()
        end
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip("Save current filter as preset")
    end
    
    ImGui.PopItemWidth()
    
    return changed, newText
end

--- Check if search text should be applied (debounce timer expired)
-- @param view string View name
-- @param currentText string Current search text
-- @return boolean True if should apply filter
function SearchBar.shouldApplyFilter(view, currentText)
    local timer = SearchBar._debounceTimers[view]
    if not timer then
        return false
    end
    
    -- Check if enough time has passed
    local now = mq.gettime()
    local elapsed = now - timer.timestamp
    
    if elapsed >= SearchBar._debounceDelay then
        -- Timer expired, apply filter
        SearchBar._debounceTimers[view] = nil
        return true
    end
    
    return false
end

--- Render compact search bar (just input + clear)
-- @param options table { text, view, width }
-- @return boolean changed, string newText
function SearchBar.renderCompact(options)
    options = options or {}
    local text = options.text or ''
    local view = options.view or 'default'
    local width = options.width or 200
    
    local changed = false
    local newText = text
    
    ImGui.PushItemWidth(width)
    local inputChanged, inputText = ImGui.InputText("##search_compact_" .. view, text, ImGuiInputTextFlags.None)
    if inputChanged then
        newText = inputText
        changed = true
        
        SearchBar._debounceTimers[view] = {
            text = newText,
            timestamp = mq.gettime()
        }
    end
    
    if text ~= '' then
        ImGui.SameLine()
        if ImGui.Button("X##clear_compact_" .. view, ImVec2(20, 0)) then
            newText = ''
            changed = true
            SearchBar._debounceTimers[view] = nil
        end
    end
    
    ImGui.PopItemWidth()
    
    return changed, newText
end

--- Get search history for a view
-- @param view string View name
-- @return table Array of recent searches
function SearchBar.getHistory(view)
    return SearchBar._searchHistory[view] or {}
end

--- Clear search history for a view
-- @param view string View name
function SearchBar.clearHistory(view)
    SearchBar._searchHistory[view] = {}
end

--- Set debounce delay
-- @param delayMs number Delay in milliseconds
function SearchBar.setDebounceDelay(delayMs)
    SearchBar._debounceDelay = delayMs
end

-- ============================================================================
-- Internal Helpers
-- ============================================================================

--- Add search to history
local function addToHistory(view, search)
    if not SearchBar._searchHistory[view] then
        SearchBar._searchHistory[view] = {}
    end
    
    local history = SearchBar._searchHistory[view]
    
    -- Don't add if it's the same as the last search
    if #history > 0 and history[#history] == search then
        return
    end
    
    -- Add to end
    table.insert(history, search)
    
    -- Trim to max size
    while #history > SearchBar._maxHistorySize do
        table.remove(history, 1)
    end
end

--- Render preset details in tooltip
local function renderPresetTooltip(preset)
    if preset.text and preset.text ~= '' then
        ImGui.Text("Text: " .. preset.text)
    end
    if preset.minValue then
        ImGui.Text(string.format("Min Value: %d pp", preset.minValue))
    end
    if preset.maxValue then
        ImGui.Text(string.format("Max Value: %d pp", preset.maxValue))
    end
    if preset.types and #preset.types > 0 then
        ImGui.Text("Types: " .. table.concat(preset.types, ", "))
    end
    if preset.flags then
        local flagNames = {}
        for flag, value in pairs(preset.flags) do
            if value then
                table.insert(flagNames, flag)
            end
        end
        if #flagNames > 0 then
            ImGui.Text("Flags: " .. table.concat(flagNames, ", "))
        end
    end
    if preset.showOnlySellable then
        ImGui.Text("Show only sellable items")
    end
    if preset.showOnlyLoot then
        ImGui.Text("Show only lootable items")
    end
end

return SearchBar
