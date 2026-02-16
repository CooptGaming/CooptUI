--[[
    Layout Management Utilities
    
    Part of ItemUI Phase 7: View Extraction & Modularization
    Handles all layout persistence, loading, saving, and column visibility management
--]]

local mq = require('mq')
local config = require('itemui.config')
local file_safe = require('itemui.utils.file_safe')

local LayoutUtils = {}

-- Constants
local LAYOUT_INI = "itemui_layout.ini"
local LAYOUT_SECTION = "Layout"

-- Module interface: Initialize layout utils with dependencies
-- Params: layoutDefaults, layoutConfig, uiState, sortState, filterState, columnVisibility, perfCache, constants, availableColumns
function LayoutUtils.init(deps)
    LayoutUtils.layoutDefaults = deps.layoutDefaults
    LayoutUtils.layoutConfig = deps.layoutConfig
    LayoutUtils.uiState = deps.uiState
    LayoutUtils.sortState = deps.sortState
    LayoutUtils.filterState = deps.filterState
    LayoutUtils.columnVisibility = deps.columnVisibility
    LayoutUtils.perfCache = deps.perfCache
    LayoutUtils.C = deps.C
    LayoutUtils.initColumnVisibility = deps.initColumnVisibility
    LayoutUtils.availableColumns = deps.availableColumns or {}
    
    -- Debug: Enable to trace layout save/load
    LayoutUtils.DEBUG = false  -- Set to true to enable debug logging
end

-- Get layout file path
function LayoutUtils.getLayoutFilePath()
    return config.getConfigFile(LAYOUT_INI)
end

-- Parse entire layout INI once; returns all sections (avoids 3x file reads on loadLayoutConfig).
-- Uses safe read: on error or missing file returns empty sections so startup never throws.
function LayoutUtils.parseLayoutFileFull()
    local path = LayoutUtils.getLayoutFilePath()
    if not path then return { defaults = {}, layout = {}, columnVisibilityDefaults = {}, columnVisibility = {} } end
    local content = file_safe.safeReadAll(path)
    if not content or content == "" then return { defaults = {}, layout = {}, columnVisibilityDefaults = {}, columnVisibility = {} } end
    local sections = { defaults = {}, layout = {}, columnVisibilityDefaults = {}, columnVisibility = {} }
    local current = nil
    for line in (content .. "\n"):gmatch("(.-)\n") do
        line = line:match("^%s*(.-)%s*$")
        if line:match("^%[") then
            if line == "[Defaults]" then current = "defaults"
            elseif line == "[" .. LAYOUT_SECTION .. "]" then current = "layout"
            elseif line == "[ColumnVisibilityDefaults]" then current = "columnVisibilityDefaults"
            elseif line == "[ColumnVisibility]" then current = "columnVisibility"
            else current = nil end
        elseif current and line:find("=") then
            local k, v = line:match("^([^=]+)=(.*)$")
            if k and v then
                k = k:match("^%s*(.-)%s*$")
                v = v:match("^%s*(.-)%s*$")
                sections[current][k] = v
            end
        end
    end
    return sections
end

-- Apply defaults from parsed INI
function LayoutUtils.applyDefaultsFromParsed(parsed)
    local d = parsed.defaults or {}
    local setBool = function(v) return (v == "1" or v == "true") end
    local layoutDefaults = LayoutUtils.layoutDefaults
    local uiState = LayoutUtils.uiState
    local columnVisibility = LayoutUtils.columnVisibility
    
    if d.WidthInventory then layoutDefaults.WidthInventory = tonumber(d.WidthInventory) or layoutDefaults.WidthInventory end
    if d.Height then layoutDefaults.Height = tonumber(d.Height) or layoutDefaults.Height end
    if d.WidthSell then layoutDefaults.WidthSell = tonumber(d.WidthSell) or layoutDefaults.WidthSell end
    if d.WidthLoot then layoutDefaults.WidthLoot = tonumber(d.WidthLoot) or layoutDefaults.WidthLoot end
    if d.WidthBankPanel then layoutDefaults.WidthBankPanel = tonumber(d.WidthBankPanel) or layoutDefaults.WidthBankPanel end
    if d.HeightBank then layoutDefaults.HeightBank = tonumber(d.HeightBank) or layoutDefaults.HeightBank end
    if d.BankWindowX then layoutDefaults.BankWindowX = tonumber(d.BankWindowX) or layoutDefaults.BankWindowX end
    if d.BankWindowY then layoutDefaults.BankWindowY = tonumber(d.BankWindowY) or layoutDefaults.BankWindowY end
    if d.WidthAugmentsPanel then layoutDefaults.WidthAugmentsPanel = tonumber(d.WidthAugmentsPanel) or layoutDefaults.WidthAugmentsPanel end
    if d.HeightAugments then layoutDefaults.HeightAugments = tonumber(d.HeightAugments) or layoutDefaults.HeightAugments end
    if d.AugmentsWindowX then layoutDefaults.AugmentsWindowX = tonumber(d.AugmentsWindowX) or layoutDefaults.AugmentsWindowX end
    if d.AugmentsWindowY then layoutDefaults.AugmentsWindowY = tonumber(d.AugmentsWindowY) or layoutDefaults.AugmentsWindowY end
    if d.ItemDisplayWindowX then layoutDefaults.ItemDisplayWindowX = tonumber(d.ItemDisplayWindowX) or layoutDefaults.ItemDisplayWindowX end
    if d.ItemDisplayWindowY then layoutDefaults.ItemDisplayWindowY = tonumber(d.ItemDisplayWindowY) or layoutDefaults.ItemDisplayWindowY end
    if d.WidthItemDisplayPanel then layoutDefaults.WidthItemDisplayPanel = tonumber(d.WidthItemDisplayPanel) or layoutDefaults.WidthItemDisplayPanel end
    if d.HeightItemDisplay then layoutDefaults.HeightItemDisplay = tonumber(d.HeightItemDisplay) or layoutDefaults.HeightItemDisplay end
    if d.AugmentUtilityWindowX then layoutDefaults.AugmentUtilityWindowX = tonumber(d.AugmentUtilityWindowX) or layoutDefaults.AugmentUtilityWindowX end
    if d.AugmentUtilityWindowY then layoutDefaults.AugmentUtilityWindowY = tonumber(d.AugmentUtilityWindowY) or layoutDefaults.AugmentUtilityWindowY end
    if d.WidthAugmentUtilityPanel then layoutDefaults.WidthAugmentUtilityPanel = tonumber(d.WidthAugmentUtilityPanel) or layoutDefaults.WidthAugmentUtilityPanel end
    if d.HeightAugmentUtility then layoutDefaults.HeightAugmentUtility = tonumber(d.HeightAugmentUtility) or layoutDefaults.HeightAugmentUtility end
    if d.WidthLootPanel then layoutDefaults.WidthLootPanel = tonumber(d.WidthLootPanel) or layoutDefaults.WidthLootPanel end
    if d.HeightLoot then layoutDefaults.HeightLoot = tonumber(d.HeightLoot) or layoutDefaults.HeightLoot end
    if d.LootWindowX then layoutDefaults.LootWindowX = tonumber(d.LootWindowX) or layoutDefaults.LootWindowX end
    if d.LootWindowY then layoutDefaults.LootWindowY = tonumber(d.LootWindowY) or layoutDefaults.LootWindowY end
    if d.LootUIFirstTipSeen then layoutDefaults.LootUIFirstTipSeen = tonumber(d.LootUIFirstTipSeen) or layoutDefaults.LootUIFirstTipSeen end
    if d.WidthAAPanel then layoutDefaults.WidthAAPanel = tonumber(d.WidthAAPanel) or layoutDefaults.WidthAAPanel end
    if d.HeightAA then layoutDefaults.HeightAA = tonumber(d.HeightAA) or layoutDefaults.HeightAA end
    if d.AAWindowX then layoutDefaults.AAWindowX = tonumber(d.AAWindowX) or layoutDefaults.AAWindowX end
    if d.AAWindowY then layoutDefaults.AAWindowY = tonumber(d.AAWindowY) or layoutDefaults.AAWindowY end
    if d.ShowAAWindow then layoutDefaults.ShowAAWindow = tonumber(d.ShowAAWindow) or layoutDefaults.ShowAAWindow end
    if d.AABackupPath ~= nil then layoutDefaults.AABackupPath = (d.AABackupPath and d.AABackupPath ~= "") and d.AABackupPath or "" end
    if d.SyncBankWindow then layoutDefaults.SyncBankWindow = setBool(d.SyncBankWindow) and 1 or 0 end
    if d.SuppressWhenLootMac then layoutDefaults.SuppressWhenLootMac = setBool(d.SuppressWhenLootMac) and 1 or 0 end
    if d.ConfirmBeforeDelete ~= nil then layoutDefaults.ConfirmBeforeDelete = setBool(d.ConfirmBeforeDelete) and 1 or 0 end
    if d.AlignToContext then layoutDefaults.AlignToContext = setBool(d.AlignToContext) and 1 or 0 end
    if d.UILocked then layoutDefaults.UILocked = setBool(d.UILocked) and 1 or 0 end
    if d.SellViewLocked then uiState.sellViewLocked = setBool(d.SellViewLocked) end
    if d.InvViewLocked then uiState.invViewLocked = setBool(d.InvViewLocked) end
    if d.BankViewLocked then uiState.bankViewLocked = setBool(d.BankViewLocked) end
    local cvd = parsed.columnVisibilityDefaults or {}
    for view, v in pairs(cvd) do
        if columnVisibility[view] then
            for colKey, _ in pairs(columnVisibility[view]) do columnVisibility[view][colKey] = false end
            for colKey in (v or ""):gmatch("([^/]+)") do
                colKey = colKey:match("^%s*(.-)%s*$")
                if columnVisibility[view][colKey] ~= nil then columnVisibility[view][colKey] = true end
            end
        end
    end
end

-- Apply column visibility from parsed INI
-- For Inventory and Bank: also populate fixedColumnOrder (ordered list for fixed-display mode)
function LayoutUtils.applyColumnVisibilityFromParsed(parsed)
    local cv = parsed.columnVisibility or {}
    local columnVisibility = LayoutUtils.columnVisibility
    local layoutConfig = LayoutUtils.layoutConfig
    local availableColumns = LayoutUtils.availableColumns
    
    layoutConfig.fixedColumnOrder = layoutConfig.fixedColumnOrder or { Inventory = {}, Bank = {} }
    
    for view, v in pairs(cv) do
        if columnVisibility[view] then
            for colKey, _ in pairs(columnVisibility[view]) do columnVisibility[view][colKey] = false end
            local ordered = {}
            for colKey in (v or ""):gmatch("([^/]+)") do
                colKey = colKey:match("^%s*(.-)%s*$")
                if columnVisibility[view][colKey] ~= nil then
                    columnVisibility[view][colKey] = true
                    table.insert(ordered, colKey)
                end
            end
            -- Store ordered list for Inventory/Bank (fixed-display mode)
            if (view == "Inventory" or view == "Bank") and #ordered > 0 then
                layoutConfig.fixedColumnOrder[view] = ordered
            end
        end
    end
    
    -- Default fixed columns if not loaded or empty (Inventory and Bank only)
    for _, view in ipairs({"Inventory", "Bank"}) do
        local list = layoutConfig.fixedColumnOrder[view]
        if not list or #list == 0 then
            local defaults = {}
            for _, colDef in ipairs(availableColumns[view] or {}) do
                if colDef.default then table.insert(defaults, colDef.key) end
            end
            layoutConfig.fixedColumnOrder[view] = defaults
        end
    end
end

-- Load column visibility from INI (standalone - parses file; use applyColumnVisibilityFromParsed when already parsed)
function LayoutUtils.loadColumnVisibility()
    LayoutUtils.initColumnVisibility()
    local parsed = LayoutUtils.parseLayoutFileFull()
    LayoutUtils.applyDefaultsFromParsed(parsed)
    LayoutUtils.applyColumnVisibilityFromParsed(parsed)
end

-- Parse entire layout INI once; returns map of key->value for [Layout] section. Safe read: returns {} on error.
function LayoutUtils.parseLayoutFile()
    local path = LayoutUtils.getLayoutFilePath()
    if not path then return {} end
    local content = file_safe.safeReadAll(path)
    if not content or content == "" then return {} end
    local layout = {}
    local inLayout = false
    for line in (content .. "\n"):gmatch("(.-)\n") do
        line = line:match("^%s*(.-)%s*$")
        if line:match("^%[") then
            inLayout = (line == "[" .. LAYOUT_SECTION .. "]")
        elseif inLayout and line:find("=") then
            local k, v = line:match("^([^=]+)=(.*)$")
            if k and v then
                k = k:match("^%s*(.-)%s*$")
                v = v:match("^%s*(.-)%s*$")
                layout[k] = v
            end
        end
    end
    return layout
end

-- Load layout value from parsed layout with type conversion
function LayoutUtils.loadLayoutValue(layout, key, default)
    if not layout then return default end
    local val = layout[key]
    if not val or val == "" then return default end
    if key == "AlignToContext" or key == "UILocked" or key == "SyncBankWindow" or key == "SuppressWhenLootMac" or key == "ConfirmBeforeDelete" or key == "SellViewLocked" or key == "InvViewLocked" or key == "BankViewLocked" then
        return (val == "1" or val == "true")
    end
    if key == "InvSortColumn" or key == "SellSortColumn" or key == "BankSortColumn" then return val end  -- string (column key)
    return tonumber(val) or default
end

-- Schedule layout save (debounced) - use for sort clicks, tab switches, etc.
function LayoutUtils.scheduleLayoutSave()
    local perfCache = LayoutUtils.perfCache
    perfCache.layoutDirty = true
    perfCache.layoutSaveScheduledAt = mq.gettime()
    if LayoutUtils.DEBUG then
        print("[LayoutUtils DEBUG] scheduleLayoutSave() called - layoutDirty set to true")
    end
end

-- Consolidated: Layout + ColumnVisibility in single read/write (was 2 reads, 2 writes)
function LayoutUtils.saveLayoutToFileImmediate()
    local perfCache = LayoutUtils.perfCache
    local uiState = LayoutUtils.uiState
    local layoutConfig = LayoutUtils.layoutConfig
    local layoutDefaults = LayoutUtils.layoutDefaults
    local sortState = LayoutUtils.sortState
    local filterState = LayoutUtils.filterState
    local columnVisibility = LayoutUtils.columnVisibility
    
    if LayoutUtils.DEBUG then
        print(string.format("[LayoutUtils DEBUG] Saving layout - InvSort: %s/%d, SellSort: %s/%d, BankSort: %s/%d",
            tostring(sortState.invColumn or "nil"), sortState.invDirection or 0,
            tostring(sortState.sellColumn or "nil"), sortState.sellDirection or 0,
            tostring(sortState.bankColumn or "nil"), sortState.bankDirection or 0))
    end
    
    perfCache.layoutNeedsReload = true
    local path = LayoutUtils.getLayoutFilePath()
    if not path then return end
    local content = file_safe.safeReadAll(path) or ""

    -- Remove existing Layout AND ColumnVisibility sections in one pass
    local lines = {}
    local inLayout, inColumnVis = false, false
    for line in content:gmatch("[^\n]+") do
        if line:match("^%s*%[" .. LAYOUT_SECTION .. "%]") then
            inLayout, inColumnVis = true, false
        elseif line:match("^%s*%[ColumnVisibility%]") then
            inLayout, inColumnVis = false, true
        elseif line:match("^%s*%[") then
            inLayout, inColumnVis = false, false
            if not line:match("^%s*%[" .. LAYOUT_SECTION .. "%]") and not line:match("^%s*%[ColumnVisibility%]") then
                table.insert(lines, line)
            end
        elseif not inLayout and not inColumnVis then
            table.insert(lines, line)
        end
    end

    local ok, err = pcall(function()
        local f = io.open(path, "w")
        if not f then error("io.open write failed") end
        for _, line in ipairs(lines) do
            f:write(line .. "\n")
        end
        f:write("[" .. LAYOUT_SECTION .. "]\n")
        f:write("AlignToContext=" .. (uiState.alignToContext and "1" or "0") .. "\n")
        f:write("AlignToMerchant=" .. (uiState.alignToMerchant and "1" or "0") .. "\n")
        f:write("UILocked=" .. (uiState.uiLocked and "1" or "0") .. "\n")
        f:write("WidthInventory=" .. tostring(layoutConfig.WidthInventory or layoutDefaults.WidthInventory) .. "\n")
        f:write("Height=" .. tostring(layoutConfig.Height or layoutDefaults.Height) .. "\n")
        f:write("WidthSell=" .. tostring(layoutConfig.WidthSell or layoutDefaults.WidthSell) .. "\n")
        f:write("WidthLoot=" .. tostring(layoutConfig.WidthLoot or layoutDefaults.WidthLoot) .. "\n")
        f:write("WidthBankPanel=" .. tostring(layoutConfig.WidthBankPanel or layoutDefaults.WidthBankPanel) .. "\n")
        f:write("HeightBank=" .. tostring(layoutConfig.HeightBank or layoutDefaults.HeightBank) .. "\n")
        f:write("BankWindowX=" .. tostring(layoutConfig.BankWindowX or layoutDefaults.BankWindowX) .. "\n")
        f:write("BankWindowY=" .. tostring(layoutConfig.BankWindowY or layoutDefaults.BankWindowY) .. "\n")
        f:write("WidthAugmentsPanel=" .. tostring(layoutConfig.WidthAugmentsPanel or layoutDefaults.WidthAugmentsPanel) .. "\n")
        f:write("HeightAugments=" .. tostring(layoutConfig.HeightAugments or layoutDefaults.HeightAugments) .. "\n")
        f:write("AugmentsWindowX=" .. tostring(layoutConfig.AugmentsWindowX or layoutDefaults.AugmentsWindowX) .. "\n")
        f:write("AugmentsWindowY=" .. tostring(layoutConfig.AugmentsWindowY or layoutDefaults.AugmentsWindowY) .. "\n")
        f:write("ItemDisplayWindowX=" .. tostring(layoutConfig.ItemDisplayWindowX or layoutDefaults.ItemDisplayWindowX) .. "\n")
        f:write("ItemDisplayWindowY=" .. tostring(layoutConfig.ItemDisplayWindowY or layoutDefaults.ItemDisplayWindowY) .. "\n")
        f:write("WidthItemDisplayPanel=" .. tostring(layoutConfig.WidthItemDisplayPanel or layoutDefaults.WidthItemDisplayPanel) .. "\n")
        f:write("HeightItemDisplay=" .. tostring(layoutConfig.HeightItemDisplay or layoutDefaults.HeightItemDisplay) .. "\n")
        f:write("AugmentUtilityWindowX=" .. tostring(layoutConfig.AugmentUtilityWindowX or layoutDefaults.AugmentUtilityWindowX) .. "\n")
        f:write("AugmentUtilityWindowY=" .. tostring(layoutConfig.AugmentUtilityWindowY or layoutDefaults.AugmentUtilityWindowY) .. "\n")
        f:write("WidthAugmentUtilityPanel=" .. tostring(layoutConfig.WidthAugmentUtilityPanel or layoutDefaults.WidthAugmentUtilityPanel) .. "\n")
        f:write("HeightAugmentUtility=" .. tostring(layoutConfig.HeightAugmentUtility or layoutDefaults.HeightAugmentUtility) .. "\n")
        f:write("WidthLootPanel=" .. tostring(layoutConfig.WidthLootPanel or layoutDefaults.WidthLootPanel) .. "\n")
        f:write("HeightLoot=" .. tostring(layoutConfig.HeightLoot or layoutDefaults.HeightLoot) .. "\n")
        f:write("LootWindowX=" .. tostring(layoutConfig.LootWindowX or layoutDefaults.LootWindowX) .. "\n")
        f:write("LootWindowY=" .. tostring(layoutConfig.LootWindowY or layoutDefaults.LootWindowY) .. "\n")
        f:write("LootUIFirstTipSeen=" .. tostring(layoutConfig.LootUIFirstTipSeen or layoutDefaults.LootUIFirstTipSeen or 0) .. "\n")
        f:write("WidthAAPanel=" .. tostring(layoutConfig.WidthAAPanel or layoutDefaults.WidthAAPanel) .. "\n")
        f:write("HeightAA=" .. tostring(layoutConfig.HeightAA or layoutDefaults.HeightAA) .. "\n")
        f:write("AAWindowX=" .. tostring(layoutConfig.AAWindowX or layoutDefaults.AAWindowX) .. "\n")
        f:write("AAWindowY=" .. tostring(layoutConfig.AAWindowY or layoutDefaults.AAWindowY) .. "\n")
        f:write("ShowAAWindow=" .. tostring(layoutConfig.ShowAAWindow or layoutDefaults.ShowAAWindow) .. "\n")
        f:write("AABackupPath=" .. tostring(layoutConfig.AABackupPath or "") .. "\n")
        f:write("WidthConfig=" .. tostring(layoutConfig.WidthConfig or 520) .. "\n")
        f:write("HeightConfig=" .. tostring(layoutConfig.HeightConfig or 420) .. "\n")
        f:write("SyncBankWindow=" .. (uiState.syncBankWindow and "1" or "0") .. "\n")
        f:write("SuppressWhenLootMac=" .. (uiState.suppressWhenLootMac and "1" or "0") .. "\n")
        f:write("ConfirmBeforeDelete=" .. (uiState.confirmBeforeDelete and "1" or "0") .. "\n")
        f:write("SellViewLocked=" .. (uiState.sellViewLocked and "1" or "0") .. "\n")
        f:write("InvViewLocked=" .. (uiState.invViewLocked and "1" or "0") .. "\n")
        f:write("BankViewLocked=" .. (uiState.bankViewLocked and "1" or "0") .. "\n")
        f:write("ConfigTab=" .. tostring(filterState.configTab) .. "\n")
        f:write("FilterSubTab=" .. tostring(filterState.filterSubTab) .. "\n")
        f:write("InvSortColumn=" .. tostring(sortState.invColumn or "Name") .. "\n")
        f:write("InvSortDirection=" .. tostring(sortState.invDirection or ImGuiSortDirection.Ascending) .. "\n")
        if sortState.invColumnOrder and #sortState.invColumnOrder > 0 then
            f:write("InvColumnOrder=" .. table.concat(sortState.invColumnOrder, "/") .. "\n")
        end
        f:write("SellSortColumn=" .. tostring(sortState.sellColumn or "Name") .. "\n")
        f:write("SellSortDirection=" .. tostring(sortState.sellDirection or ImGuiSortDirection.Ascending) .. "\n")
        f:write("BankSortColumn=" .. tostring(sortState.bankColumn or "Name") .. "\n")
        f:write("BankSortDirection=" .. tostring(sortState.bankDirection or ImGuiSortDirection.Ascending) .. "\n")
        if sortState.bankColumnOrder and #sortState.bankColumnOrder > 0 then
            f:write("BankColumnOrder=" .. table.concat(sortState.bankColumnOrder, "/") .. "\n")
        end
        f:write("AASortColumn=" .. tostring(sortState.aaColumn or "Title") .. "\n")
        f:write("AASortDirection=" .. tostring(sortState.aaDirection or ImGuiSortDirection.Ascending) .. "\n")
        f:write("AALastTab=" .. tostring(sortState.aaTab or 1) .. "\n")
        f:write("\n[ColumnVisibility]\n")
        local fixedOrder = layoutConfig.fixedColumnOrder or {}
        for view, cols in pairs(columnVisibility) do
            local visibleCols = {}
            if (view == "Inventory" or view == "Bank") and fixedOrder[view] and #fixedOrder[view] > 0 then
                visibleCols = fixedOrder[view]
            else
                for colKey, visible in pairs(cols) do
                    if visible then table.insert(visibleCols, colKey) end
                end
            end
            f:write(view .. "=" .. table.concat(visibleCols, "/") .. "\n")
        end
        f:close()
    end)
    if not ok and print then
        print(string.format("\ar[ItemUI]\ax saveLayoutToFileImmediate failed: %s", tostring(err)))
    end
end

-- Flush any pending layout save (call on exit, setup save, sort change, etc.)
function LayoutUtils.flushLayoutSave()
    local perfCache = LayoutUtils.perfCache
    if LayoutUtils.DEBUG then
        print(string.format("[LayoutUtils DEBUG] flushLayoutSave() called - layoutDirty: %s", tostring(perfCache.layoutDirty)))
    end
    if perfCache.layoutDirty then
        perfCache.layoutDirty = false
        LayoutUtils.saveLayoutToFileImmediate()
    end
end

-- Save column visibility (delegates to saveLayoutToFileImmediate for consolidated save)
function LayoutUtils.saveColumnVisibility()
    LayoutUtils.saveLayoutToFileImmediate()
end

-- Toggle a column in the fixed list (Inventory/Bank). Adds if not present, removes if present.
-- Changes apply on next UI open. Returns new state (true = in list, false = removed).
function LayoutUtils.toggleFixedColumn(view, colKey)
    if view ~= "Inventory" and view ~= "Bank" then return nil end
    local layoutConfig = LayoutUtils.layoutConfig
    layoutConfig.fixedColumnOrder = layoutConfig.fixedColumnOrder or { Inventory = {}, Bank = {} }
    local list = layoutConfig.fixedColumnOrder[view] or {}
    local found = nil
    for i, k in ipairs(list) do
        if k == colKey then found = i; break end
    end
    if found then
        if #list <= 1 then return true end  -- Keep at least one column
        table.remove(list, found)
        LayoutUtils.saveLayoutToFileImmediate()
        return false
    else
        table.insert(list, colKey)
        LayoutUtils.saveLayoutToFileImmediate()
        return true
    end
end

-- Check if column is in the fixed list (Inventory/Bank)
function LayoutUtils.isColumnInFixedSet(view, colKey)
    if view ~= "Inventory" and view ~= "Bank" then return false end
    local layoutConfig = LayoutUtils.layoutConfig
    local list = layoutConfig.fixedColumnOrder and layoutConfig.fixedColumnOrder[view] or {}
    for _, k in ipairs(list) do
        if k == colKey then return true end
    end
    return false
end

-- Get fixed column list for Inventory/Bank (ordered; used for fixed-display mode with ImGui SaveSettings)
-- Returns array of colDefs. Falls back to getVisibleColumns-style default if no fixed list.
function LayoutUtils.getFixedColumns(view)
    if view ~= "Inventory" and view ~= "Bank" then return {} end
    local layoutConfig = LayoutUtils.layoutConfig
    local availableColumns = LayoutUtils.availableColumns
    local colDefByKey = {}
    for _, colDef in ipairs(availableColumns[view] or {}) do
        colDefByKey[colDef.key] = colDef
    end
    local ordered = layoutConfig.fixedColumnOrder and layoutConfig.fixedColumnOrder[view] or {}
    local result = {}
    for _, colKey in ipairs(ordered) do
        local colDef = colDefByKey[colKey]
        if colDef then table.insert(result, colDef) end
    end
    if #result == 0 then
        -- Fallback: default columns from availableColumns
        for _, colDef in ipairs(availableColumns[view] or {}) do
            if colDef.default then table.insert(result, colDef) end
        end
    end
    return result
end

-- Save layout to file (delegates to saveLayoutToFileImmediate)
function LayoutUtils.saveLayoutToFile()
    LayoutUtils.saveLayoutToFileImmediate()
end

-- Capture current layout state as snapshot (defaults)
function LayoutUtils.captureCurrentLayoutAsDefault()
    local layoutDefaults = LayoutUtils.layoutDefaults
    local layoutConfig = LayoutUtils.layoutConfig
    local uiState = LayoutUtils.uiState
    local columnVisibility = LayoutUtils.columnVisibility
    
    -- Capture current configuration values
    layoutDefaults.WidthInventory = layoutConfig.WidthInventory or layoutDefaults.WidthInventory
    layoutDefaults.Height = layoutConfig.Height or layoutDefaults.Height
    layoutDefaults.WidthSell = layoutConfig.WidthSell or layoutDefaults.WidthSell
    layoutDefaults.WidthLoot = layoutConfig.WidthLoot or layoutDefaults.WidthLoot
    layoutDefaults.WidthBankPanel = layoutConfig.WidthBankPanel or layoutDefaults.WidthBankPanel
    layoutDefaults.HeightBank = layoutConfig.HeightBank or layoutDefaults.HeightBank
    layoutDefaults.WidthLootPanel = layoutConfig.WidthLootPanel or layoutDefaults.WidthLootPanel
    layoutDefaults.HeightLoot = layoutConfig.HeightLoot or layoutDefaults.HeightLoot
    layoutDefaults.LootWindowX = layoutConfig.LootWindowX or layoutDefaults.LootWindowX
    layoutDefaults.LootWindowY = layoutConfig.LootWindowY or layoutDefaults.LootWindowY
    -- Capture bank window position if it's open
    if uiState.bankWindowOpen and uiState.bankWindowShouldDraw then
        layoutDefaults.BankWindowX = layoutConfig.BankWindowX or layoutDefaults.BankWindowX
        layoutDefaults.BankWindowY = layoutConfig.BankWindowY or layoutDefaults.BankWindowY
    else
        layoutDefaults.BankWindowX = layoutConfig.BankWindowX or layoutDefaults.BankWindowX
        layoutDefaults.BankWindowY = layoutConfig.BankWindowY or layoutDefaults.BankWindowY
    end
    layoutDefaults.WidthAugmentsPanel = layoutConfig.WidthAugmentsPanel or layoutDefaults.WidthAugmentsPanel
    layoutDefaults.HeightAugments = layoutConfig.HeightAugments or layoutDefaults.HeightAugments
    layoutDefaults.AugmentsWindowX = layoutConfig.AugmentsWindowX or layoutDefaults.AugmentsWindowX
    layoutDefaults.AugmentsWindowY = layoutConfig.AugmentsWindowY or layoutDefaults.AugmentsWindowY
    layoutDefaults.ItemDisplayWindowX = layoutConfig.ItemDisplayWindowX or layoutDefaults.ItemDisplayWindowX
    layoutDefaults.ItemDisplayWindowY = layoutConfig.ItemDisplayWindowY or layoutDefaults.ItemDisplayWindowY
    layoutDefaults.WidthItemDisplayPanel = layoutConfig.WidthItemDisplayPanel or layoutDefaults.WidthItemDisplayPanel
    layoutDefaults.HeightItemDisplay = layoutConfig.HeightItemDisplay or layoutDefaults.HeightItemDisplay
    layoutDefaults.AugmentUtilityWindowX = layoutConfig.AugmentUtilityWindowX or layoutDefaults.AugmentUtilityWindowX
    layoutDefaults.AugmentUtilityWindowY = layoutConfig.AugmentUtilityWindowY or layoutDefaults.AugmentUtilityWindowY
    layoutDefaults.WidthAugmentUtilityPanel = layoutConfig.WidthAugmentUtilityPanel or layoutDefaults.WidthAugmentUtilityPanel
    layoutDefaults.HeightAugmentUtility = layoutConfig.HeightAugmentUtility or layoutDefaults.HeightAugmentUtility
    layoutDefaults.WidthAAPanel = layoutConfig.WidthAAPanel or layoutDefaults.WidthAAPanel
    layoutDefaults.HeightAA = layoutConfig.HeightAA or layoutDefaults.HeightAA
    layoutDefaults.AAWindowX = layoutConfig.AAWindowX or layoutDefaults.AAWindowX
    layoutDefaults.AAWindowY = layoutConfig.AAWindowY or layoutDefaults.AAWindowY
    layoutDefaults.ShowAAWindow = layoutConfig.ShowAAWindow or layoutDefaults.ShowAAWindow
    layoutDefaults.AABackupPath = layoutConfig.AABackupPath or ""
    layoutDefaults.AlignToContext = uiState.alignToContext and 1 or 0
    layoutDefaults.AlignToMerchant = uiState.alignToMerchant and 1 or 0
    layoutDefaults.UILocked = uiState.uiLocked and 1 or 0
    layoutDefaults.SyncBankWindow = uiState.syncBankWindow and 1 or 0
    layoutDefaults.SuppressWhenLootMac = uiState.suppressWhenLootMac and 1 or 0
    layoutDefaults.ConfirmBeforeDelete = (uiState.confirmBeforeDelete == true) and 1 or 0
    -- Save ImGui table settings (column widths) - this captures current column widths
    if ImGui.SaveIniSettingsToDisk then ImGui.SaveIniSettingsToDisk(nil) end
    
    -- Save defaults to a separate section in the INI file (safe: pcall so write failure doesn't throw)
    local path = LayoutUtils.getLayoutFilePath()
    if path then
        local content = file_safe.safeReadAll(path) or ""
        local lines = {}
        local inDefaults = false
        local inColDefaults = false
        for line in content:gmatch("[^\n]+") do
            if line:match("^%s*%[Defaults%]") then
                inDefaults = true
            elseif line:match("^%s*%[ColumnVisibilityDefaults%]") then
                inColDefaults = true
            elseif line:match("^%s*%[") then
                inDefaults = false
                inColDefaults = false
                if not line:match("^%s*%[Defaults%]") and not line:match("^%s*%[ColumnVisibilityDefaults%]") then
                    table.insert(lines, line)
                end
            elseif not inDefaults and not inColDefaults then
                table.insert(lines, line)
            end
        end

        local ok, err = pcall(function()
            local f = io.open(path, "w")
            if not f then error("io.open write failed") end
            for _, line in ipairs(lines) do
                f:write(line .. "\n")
            end
            f:write("\n[Defaults]\n")
            f:write("AlignToContext=" .. layoutDefaults.AlignToContext .. "\n")
            f:write("UILocked=" .. layoutDefaults.UILocked .. "\n")
            f:write("WidthInventory=" .. layoutDefaults.WidthInventory .. "\n")
            f:write("Height=" .. layoutDefaults.Height .. "\n")
            f:write("WidthSell=" .. layoutDefaults.WidthSell .. "\n")
            f:write("WidthLoot=" .. layoutDefaults.WidthLoot .. "\n")
            f:write("WidthBankPanel=" .. layoutDefaults.WidthBankPanel .. "\n")
            f:write("HeightBank=" .. layoutDefaults.HeightBank .. "\n")
            f:write("BankWindowX=" .. layoutDefaults.BankWindowX .. "\n")
            f:write("BankWindowY=" .. layoutDefaults.BankWindowY .. "\n")
            f:write("WidthLootPanel=" .. tostring(layoutDefaults.WidthLootPanel or 420) .. "\n")
            f:write("HeightLoot=" .. tostring(layoutDefaults.HeightLoot or 380) .. "\n")
            f:write("LootWindowX=" .. tostring(layoutDefaults.LootWindowX or 0) .. "\n")
            f:write("LootWindowY=" .. tostring(layoutDefaults.LootWindowY or 0) .. "\n")
            f:write("WidthAugmentsPanel=" .. layoutDefaults.WidthAugmentsPanel .. "\n")
            f:write("HeightAugments=" .. layoutDefaults.HeightAugments .. "\n")
            f:write("AugmentsWindowX=" .. layoutDefaults.AugmentsWindowX .. "\n")
            f:write("AugmentsWindowY=" .. layoutDefaults.AugmentsWindowY .. "\n")
            f:write("ItemDisplayWindowX=" .. tostring(layoutDefaults.ItemDisplayWindowX or 0) .. "\n")
            f:write("ItemDisplayWindowY=" .. tostring(layoutDefaults.ItemDisplayWindowY or 0) .. "\n")
            f:write("WidthItemDisplayPanel=" .. tostring(layoutDefaults.WidthItemDisplayPanel or 760) .. "\n")
            f:write("HeightItemDisplay=" .. tostring(layoutDefaults.HeightItemDisplay or 520) .. "\n")
            f:write("AugmentUtilityWindowX=" .. tostring(layoutDefaults.AugmentUtilityWindowX or 0) .. "\n")
            f:write("AugmentUtilityWindowY=" .. tostring(layoutDefaults.AugmentUtilityWindowY or 0) .. "\n")
            f:write("WidthAugmentUtilityPanel=" .. tostring(layoutDefaults.WidthAugmentUtilityPanel or 520) .. "\n")
            f:write("HeightAugmentUtility=" .. tostring(layoutDefaults.HeightAugmentUtility or 480) .. "\n")
            f:write("WidthAAPanel=" .. layoutDefaults.WidthAAPanel .. "\n")
            f:write("HeightAA=" .. layoutDefaults.HeightAA .. "\n")
            f:write("AAWindowX=" .. layoutDefaults.AAWindowX .. "\n")
            f:write("AAWindowY=" .. layoutDefaults.AAWindowY .. "\n")
            f:write("ShowAAWindow=" .. layoutDefaults.ShowAAWindow .. "\n")
            f:write("AABackupPath=" .. tostring(layoutDefaults.AABackupPath or "") .. "\n")
            f:write("SyncBankWindow=" .. layoutDefaults.SyncBankWindow .. "\n")
            f:write("SuppressWhenLootMac=" .. layoutDefaults.SuppressWhenLootMac .. "\n")
            f:write("ConfirmBeforeDelete=" .. (layoutDefaults.ConfirmBeforeDelete or 1) .. "\n")
            f:write("SellViewLocked=" .. (uiState.sellViewLocked and "1" or "0") .. "\n")
            f:write("InvViewLocked=" .. (uiState.invViewLocked and "1" or "0") .. "\n")
            f:write("BankViewLocked=" .. (uiState.bankViewLocked and "1" or "0") .. "\n")
            f:write("\n[ColumnVisibilityDefaults]\n")
            for view, cols in pairs(columnVisibility) do
                local visibleCols = {}
                for colKey, visible in pairs(cols) do
                    if visible then table.insert(visibleCols, colKey) end
                end
                f:write(view .. "=" .. table.concat(visibleCols, "/") .. "\n")
            end
            f:close()
        end)
        if not ok and print then
            print(string.format("\ar[ItemUI]\ax captureCurrentLayoutAsDefault write failed: %s", tostring(err)))
        end
    end
    
    print("\ag[ItemUI]\ax Current layout configuration captured as default! (Window sizes, positions, column widths, column visibility, and all settings)")
end

-- Reset layout to defaults
function LayoutUtils.resetLayoutToDefault()
    local layoutConfig = LayoutUtils.layoutConfig
    local layoutDefaults = LayoutUtils.layoutDefaults
    local uiState = LayoutUtils.uiState
    
    local parsed = LayoutUtils.parseLayoutFileFull()
    LayoutUtils.initColumnVisibility()
    LayoutUtils.applyDefaultsFromParsed(parsed)
    
    -- Reset all layout values to defaults
    layoutConfig.WidthInventory = layoutDefaults.WidthInventory
    layoutConfig.Height = layoutDefaults.Height
    layoutConfig.WidthSell = layoutDefaults.WidthSell
    layoutConfig.WidthLoot = layoutDefaults.WidthLoot
    layoutConfig.WidthBankPanel = layoutDefaults.WidthBankPanel
    layoutConfig.HeightBank = layoutDefaults.HeightBank
    layoutConfig.BankWindowX = layoutDefaults.BankWindowX
    layoutConfig.BankWindowY = layoutDefaults.BankWindowY
    layoutConfig.WidthLootPanel = layoutDefaults.WidthLootPanel
    layoutConfig.HeightLoot = layoutDefaults.HeightLoot
    layoutConfig.LootWindowX = layoutDefaults.LootWindowX
    layoutConfig.LootWindowY = layoutDefaults.LootWindowY
    layoutConfig.WidthAugmentsPanel = layoutDefaults.WidthAugmentsPanel
    layoutConfig.HeightAugments = layoutDefaults.HeightAugments
    layoutConfig.AugmentsWindowX = layoutDefaults.AugmentsWindowX
    layoutConfig.AugmentsWindowY = layoutDefaults.AugmentsWindowY
    layoutConfig.ItemDisplayWindowX = layoutDefaults.ItemDisplayWindowX
    layoutConfig.ItemDisplayWindowY = layoutDefaults.ItemDisplayWindowY
    layoutConfig.WidthItemDisplayPanel = layoutDefaults.WidthItemDisplayPanel
    layoutConfig.HeightItemDisplay = layoutDefaults.HeightItemDisplay
    layoutConfig.AugmentUtilityWindowX = layoutDefaults.AugmentUtilityWindowX
    layoutConfig.AugmentUtilityWindowY = layoutDefaults.AugmentUtilityWindowY
    layoutConfig.WidthAugmentUtilityPanel = layoutDefaults.WidthAugmentUtilityPanel
    layoutConfig.HeightAugmentUtility = layoutDefaults.HeightAugmentUtility
    layoutConfig.WidthAAPanel = layoutDefaults.WidthAAPanel
    layoutConfig.HeightAA = layoutDefaults.HeightAA
    layoutConfig.AAWindowX = layoutDefaults.AAWindowX
    layoutConfig.AAWindowY = layoutDefaults.AAWindowY
    layoutConfig.ShowAAWindow = layoutDefaults.ShowAAWindow
    layoutConfig.AABackupPath = layoutDefaults.AABackupPath or ""
    local sortState = LayoutUtils.sortState
    if sortState then
        sortState.aaColumn = "Title"
        sortState.aaDirection = ImGuiSortDirection.Ascending
        sortState.aaTab = 1
    end
    uiState.alignToContext = (layoutDefaults.AlignToContext == 1)
    uiState.uiLocked = (layoutDefaults.UILocked == 1)
    uiState.syncBankWindow = (layoutDefaults.SyncBankWindow == 1)
    uiState.suppressWhenLootMac = (layoutDefaults.SuppressWhenLootMac == 1)
    uiState.confirmBeforeDelete = ((layoutDefaults.ConfirmBeforeDelete or 1) == 1)
    -- Save the reset configuration
    LayoutUtils.saveLayoutToFile()
    
    -- Force reload to apply changes immediately
    local perfCache = LayoutUtils.perfCache
    if perfCache then perfCache.layoutNeedsReload = true end
    
    print("\ag[ItemUI]\ax Layout reset to default! (Window sizes, column visibility, and settings restored)")
    print("\ay[ItemUI]\ax Note: Window sizes will apply on next reload. Close and reopen CoOpt UI Inventory Companion.")
end

-- Load layout config from INI file
function LayoutUtils.loadLayoutConfig()
    local perfCache = LayoutUtils.perfCache
    local layoutConfig = LayoutUtils.layoutConfig
    local layoutDefaults = LayoutUtils.layoutDefaults
    local uiState = LayoutUtils.uiState
    local sortState = LayoutUtils.sortState
    local filterState = LayoutUtils.filterState
    local C = LayoutUtils.C
    
    local t0 = mq.gettime()
    -- Skip parse if config unchanged (perfCache.layoutNeedsReload set when we save)
    if not perfCache.layoutNeedsReload and perfCache.layoutCached then
        if LayoutUtils.DEBUG then
            print("[LayoutUtils DEBUG] Loading layout from CACHE")
        end
        LayoutUtils.initColumnVisibility()
        LayoutUtils.applyDefaultsFromParsed(perfCache.layoutCached)
        local layout = perfCache.layoutCached.layout or {}
        uiState.alignToContext = LayoutUtils.loadLayoutValue(layout, "AlignToContext", layoutDefaults.AlignToContext == 1)
        uiState.alignToMerchant = LayoutUtils.loadLayoutValue(layout, "AlignToMerchant", false)
        uiState.uiLocked = LayoutUtils.loadLayoutValue(layout, "UILocked", layoutDefaults.UILocked == 1)
        layoutConfig.WidthInventory = LayoutUtils.loadLayoutValue(layout, "WidthInventory", layoutDefaults.WidthInventory)
        layoutConfig.Height = LayoutUtils.loadLayoutValue(layout, "Height", layoutDefaults.Height)
        layoutConfig.WidthSell = LayoutUtils.loadLayoutValue(layout, "WidthSell", layoutDefaults.WidthSell)
        layoutConfig.WidthLoot = LayoutUtils.loadLayoutValue(layout, "WidthLoot", layoutDefaults.WidthLoot)
        layoutConfig.WidthBankPanel = LayoutUtils.loadLayoutValue(layout, "WidthBankPanel", layoutDefaults.WidthBankPanel)
        layoutConfig.HeightBank = LayoutUtils.loadLayoutValue(layout, "HeightBank", layoutDefaults.HeightBank)
        layoutConfig.BankWindowX = LayoutUtils.loadLayoutValue(layout, "BankWindowX", layoutDefaults.BankWindowX)
        layoutConfig.BankWindowY = LayoutUtils.loadLayoutValue(layout, "BankWindowY", layoutDefaults.BankWindowY)
        layoutConfig.WidthAugmentsPanel = LayoutUtils.loadLayoutValue(layout, "WidthAugmentsPanel", layoutDefaults.WidthAugmentsPanel)
        layoutConfig.HeightAugments = LayoutUtils.loadLayoutValue(layout, "HeightAugments", layoutDefaults.HeightAugments)
        layoutConfig.AugmentsWindowX = LayoutUtils.loadLayoutValue(layout, "AugmentsWindowX", layoutDefaults.AugmentsWindowX)
        layoutConfig.AugmentsWindowY = LayoutUtils.loadLayoutValue(layout, "AugmentsWindowY", layoutDefaults.AugmentsWindowY)
        layoutConfig.ItemDisplayWindowX = LayoutUtils.loadLayoutValue(layout, "ItemDisplayWindowX", layoutDefaults.ItemDisplayWindowX)
        layoutConfig.ItemDisplayWindowY = LayoutUtils.loadLayoutValue(layout, "ItemDisplayWindowY", layoutDefaults.ItemDisplayWindowY)
        layoutConfig.WidthItemDisplayPanel = LayoutUtils.loadLayoutValue(layout, "WidthItemDisplayPanel", layoutDefaults.WidthItemDisplayPanel)
        layoutConfig.HeightItemDisplay = LayoutUtils.loadLayoutValue(layout, "HeightItemDisplay", layoutDefaults.HeightItemDisplay)
        layoutConfig.AugmentUtilityWindowX = LayoutUtils.loadLayoutValue(layout, "AugmentUtilityWindowX", layoutDefaults.AugmentUtilityWindowX)
        layoutConfig.AugmentUtilityWindowY = LayoutUtils.loadLayoutValue(layout, "AugmentUtilityWindowY", layoutDefaults.AugmentUtilityWindowY)
        layoutConfig.WidthAugmentUtilityPanel = LayoutUtils.loadLayoutValue(layout, "WidthAugmentUtilityPanel", layoutDefaults.WidthAugmentUtilityPanel)
        layoutConfig.HeightAugmentUtility = LayoutUtils.loadLayoutValue(layout, "HeightAugmentUtility", layoutDefaults.HeightAugmentUtility)
        layoutConfig.WidthLootPanel = LayoutUtils.loadLayoutValue(layout, "WidthLootPanel", layoutDefaults.WidthLootPanel)
        layoutConfig.HeightLoot = LayoutUtils.loadLayoutValue(layout, "HeightLoot", layoutDefaults.HeightLoot)
        layoutConfig.LootWindowX = LayoutUtils.loadLayoutValue(layout, "LootWindowX", layoutDefaults.LootWindowX)
        layoutConfig.LootWindowY = LayoutUtils.loadLayoutValue(layout, "LootWindowY", layoutDefaults.LootWindowY)
        layoutConfig.LootUIFirstTipSeen = LayoutUtils.loadLayoutValue(layout, "LootUIFirstTipSeen", layoutDefaults.LootUIFirstTipSeen or 0)
        layoutConfig.WidthAAPanel = LayoutUtils.loadLayoutValue(layout, "WidthAAPanel", layoutDefaults.WidthAAPanel)
        layoutConfig.HeightAA = LayoutUtils.loadLayoutValue(layout, "HeightAA", layoutDefaults.HeightAA)
        layoutConfig.AAWindowX = LayoutUtils.loadLayoutValue(layout, "AAWindowX", layoutDefaults.AAWindowX)
        layoutConfig.AAWindowY = LayoutUtils.loadLayoutValue(layout, "AAWindowY", layoutDefaults.AAWindowY)
        layoutConfig.ShowAAWindow = LayoutUtils.loadLayoutValue(layout, "ShowAAWindow", layoutDefaults.ShowAAWindow)
        layoutConfig.AABackupPath = (layout["AABackupPath"] and layout["AABackupPath"] ~= "") and layout["AABackupPath"] or (layoutDefaults.AABackupPath or "")
        layoutConfig.WidthConfig = LayoutUtils.loadLayoutValue(layout, "WidthConfig", 520)
        layoutConfig.HeightConfig = LayoutUtils.loadLayoutValue(layout, "HeightConfig", 420)
        uiState.syncBankWindow = LayoutUtils.loadLayoutValue(layout, "SyncBankWindow", layoutDefaults.SyncBankWindow == 1)
        uiState.suppressWhenLootMac = LayoutUtils.loadLayoutValue(layout, "SuppressWhenLootMac", layoutDefaults.SuppressWhenLootMac == 1)
        uiState.confirmBeforeDelete = LayoutUtils.loadLayoutValue(layout, "ConfirmBeforeDelete", (layoutDefaults.ConfirmBeforeDelete or 1) == 1)
        uiState.sellViewLocked = LayoutUtils.loadLayoutValue(layout, "SellViewLocked", true)
        uiState.invViewLocked = LayoutUtils.loadLayoutValue(layout, "InvViewLocked", true)
        uiState.bankViewLocked = LayoutUtils.loadLayoutValue(layout, "BankViewLocked", true)
        local ct = LayoutUtils.loadLayoutValue(layout, "ConfigTab", 1)
        -- Tabs 1-4 only; legacy 5 or 10-12 map to 1
        filterState.configTab = (type(ct) == "number" and ct >= 1 and ct <= 4) and ct or 1
        local fst = LayoutUtils.loadLayoutValue(layout, "FilterSubTab", 1)
        filterState.filterSubTab = (type(fst) == "number" and fst >= 1 and fst <= 3) and fst or 1
        local invCol = LayoutUtils.loadLayoutValue(layout, "InvSortColumn", "Name")
        sortState.invColumn = (type(invCol) == "string" and invCol ~= "") and invCol or "Name"
        local invDir = LayoutUtils.loadLayoutValue(layout, "InvSortDirection", ImGuiSortDirection.Ascending)
        sortState.invDirection = (type(invDir) == "number") and invDir or ImGuiSortDirection.Ascending
        -- Load Inventory column order (new feature)
        local invColOrder = layout["InvColumnOrder"]
        if invColOrder and invColOrder ~= "" then
            sortState.invColumnOrder = {}
            for colKey in invColOrder:gmatch("([^/]+)") do
                table.insert(sortState.invColumnOrder, colKey:match("^%s*(.-)%s*$"))
            end
        else
            sortState.invColumnOrder = nil  -- Use default ordering
        end
        local sellCol = LayoutUtils.loadLayoutValue(layout, "SellSortColumn", "Name")
        sortState.sellColumn = (type(sellCol) == "string" and sellCol ~= "") and sellCol or "Name"
        local sellDir = LayoutUtils.loadLayoutValue(layout, "SellSortDirection", ImGuiSortDirection.Ascending)
        sortState.sellDirection = (type(sellDir) == "number") and sellDir or ImGuiSortDirection.Ascending
        local bankCol = LayoutUtils.loadLayoutValue(layout, "BankSortColumn", "Name")
        sortState.bankColumn = (type(bankCol) == "string" and bankCol ~= "") and bankCol or "Name"
        local bankDir = LayoutUtils.loadLayoutValue(layout, "BankSortDirection", ImGuiSortDirection.Ascending)
        sortState.bankDirection = (type(bankDir) == "number") and bankDir or ImGuiSortDirection.Ascending
        -- Load Bank column order from cached layout
        local bankColOrder = layout["BankColumnOrder"]
        if bankColOrder and bankColOrder ~= "" then
            sortState.bankColumnOrder = {}
            for colKey in bankColOrder:gmatch("([^/]+)") do
                table.insert(sortState.bankColumnOrder, colKey:match("^%s*(.-)%s*$"))
            end
        else
            sortState.bankColumnOrder = nil  -- Use default ordering
        end
        local aaCol = LayoutUtils.loadLayoutValue(layout, "AASortColumn", "Title")
        sortState.aaColumn = (type(aaCol) == "string" and aaCol ~= "") and aaCol or "Title"
        local aaDir = LayoutUtils.loadLayoutValue(layout, "AASortDirection", ImGuiSortDirection.Ascending)
        sortState.aaDirection = (type(aaDir) == "number") and aaDir or ImGuiSortDirection.Ascending
        local aaTab = LayoutUtils.loadLayoutValue(layout, "AALastTab", 1)
        sortState.aaTab = (type(aaTab) == "number" and aaTab >= 1 and aaTab <= 4) and aaTab or 1
        LayoutUtils.applyColumnVisibilityFromParsed(perfCache.layoutCached)
        local e = mq.gettime() - t0
        if LayoutUtils.DEBUG then
            print(string.format("[LayoutUtils DEBUG] Loaded from CACHE - InvSort: %s/%d", tostring(sortState.invColumn), sortState.invDirection))
        end
        if C.PROFILE_ENABLED and e >= C.PROFILE_THRESHOLD_MS then
            print(string.format("\ag[ItemUI Profile]\ax loadLayoutConfig (cached): %d ms", e))
        end
        return
    end
    -- Single file read: parse all sections at once (avoids 3x I/O on every UI open)
    if LayoutUtils.DEBUG then
        print("[LayoutUtils DEBUG] Loading layout from FILE (cache miss or invalidated)")
    end
    local parsed = LayoutUtils.parseLayoutFileFull()
    perfCache.layoutCached = parsed
    perfCache.layoutNeedsReload = false
    LayoutUtils.initColumnVisibility()
    LayoutUtils.applyDefaultsFromParsed(parsed)
    local layout = parsed.layout or {}
    uiState.alignToContext = LayoutUtils.loadLayoutValue(layout, "AlignToContext", layoutDefaults.AlignToContext == 1)
    uiState.alignToMerchant = LayoutUtils.loadLayoutValue(layout, "AlignToMerchant", false)
    uiState.uiLocked = LayoutUtils.loadLayoutValue(layout, "UILocked", layoutDefaults.UILocked == 1)
    layoutConfig.WidthInventory = LayoutUtils.loadLayoutValue(layout, "WidthInventory", layoutDefaults.WidthInventory)
    layoutConfig.Height = LayoutUtils.loadLayoutValue(layout, "Height", layoutDefaults.Height)
    layoutConfig.WidthSell = LayoutUtils.loadLayoutValue(layout, "WidthSell", layoutDefaults.WidthSell)
    layoutConfig.WidthBankPanel = LayoutUtils.loadLayoutValue(layout, "WidthBankPanel", layoutDefaults.WidthBankPanel)
    layoutConfig.HeightBank = LayoutUtils.loadLayoutValue(layout, "HeightBank", layoutDefaults.HeightBank)
    layoutConfig.BankWindowX = LayoutUtils.loadLayoutValue(layout, "BankWindowX", layoutDefaults.BankWindowX)
    layoutConfig.BankWindowY = LayoutUtils.loadLayoutValue(layout, "BankWindowY", layoutDefaults.BankWindowY)
    layoutConfig.WidthAugmentsPanel = LayoutUtils.loadLayoutValue(layout, "WidthAugmentsPanel", layoutDefaults.WidthAugmentsPanel)
    layoutConfig.HeightAugments = LayoutUtils.loadLayoutValue(layout, "HeightAugments", layoutDefaults.HeightAugments)
    layoutConfig.AugmentsWindowX = LayoutUtils.loadLayoutValue(layout, "AugmentsWindowX", layoutDefaults.AugmentsWindowX)
    layoutConfig.AugmentsWindowY = LayoutUtils.loadLayoutValue(layout, "AugmentsWindowY", layoutDefaults.AugmentsWindowY)
    layoutConfig.ItemDisplayWindowX = LayoutUtils.loadLayoutValue(layout, "ItemDisplayWindowX", layoutDefaults.ItemDisplayWindowX)
    layoutConfig.ItemDisplayWindowY = LayoutUtils.loadLayoutValue(layout, "ItemDisplayWindowY", layoutDefaults.ItemDisplayWindowY)
    layoutConfig.WidthItemDisplayPanel = LayoutUtils.loadLayoutValue(layout, "WidthItemDisplayPanel", layoutDefaults.WidthItemDisplayPanel)
    layoutConfig.HeightItemDisplay = LayoutUtils.loadLayoutValue(layout, "HeightItemDisplay", layoutDefaults.HeightItemDisplay)
    layoutConfig.AugmentUtilityWindowX = LayoutUtils.loadLayoutValue(layout, "AugmentUtilityWindowX", layoutDefaults.AugmentUtilityWindowX)
    layoutConfig.AugmentUtilityWindowY = LayoutUtils.loadLayoutValue(layout, "AugmentUtilityWindowY", layoutDefaults.AugmentUtilityWindowY)
    layoutConfig.WidthAugmentUtilityPanel = LayoutUtils.loadLayoutValue(layout, "WidthAugmentUtilityPanel", layoutDefaults.WidthAugmentUtilityPanel)
    layoutConfig.HeightAugmentUtility = LayoutUtils.loadLayoutValue(layout, "HeightAugmentUtility", layoutDefaults.HeightAugmentUtility)
    layoutConfig.WidthLootPanel = LayoutUtils.loadLayoutValue(layout, "WidthLootPanel", layoutDefaults.WidthLootPanel)
    layoutConfig.HeightLoot = LayoutUtils.loadLayoutValue(layout, "HeightLoot", layoutDefaults.HeightLoot)
    layoutConfig.LootWindowX = LayoutUtils.loadLayoutValue(layout, "LootWindowX", layoutDefaults.LootWindowX)
    layoutConfig.LootWindowY = LayoutUtils.loadLayoutValue(layout, "LootWindowY", layoutDefaults.LootWindowY)
    layoutConfig.LootUIFirstTipSeen = LayoutUtils.loadLayoutValue(layout, "LootUIFirstTipSeen", layoutDefaults.LootUIFirstTipSeen or 0)
    layoutConfig.WidthAAPanel = LayoutUtils.loadLayoutValue(layout, "WidthAAPanel", layoutDefaults.WidthAAPanel)
    layoutConfig.HeightAA = LayoutUtils.loadLayoutValue(layout, "HeightAA", layoutDefaults.HeightAA)
    layoutConfig.AAWindowX = LayoutUtils.loadLayoutValue(layout, "AAWindowX", layoutDefaults.AAWindowX)
    layoutConfig.AAWindowY = LayoutUtils.loadLayoutValue(layout, "AAWindowY", layoutDefaults.AAWindowY)
    layoutConfig.ShowAAWindow = LayoutUtils.loadLayoutValue(layout, "ShowAAWindow", layoutDefaults.ShowAAWindow)
    layoutConfig.AABackupPath = (layout["AABackupPath"] and layout["AABackupPath"] ~= "") and layout["AABackupPath"] or (layoutDefaults.AABackupPath or "")
    layoutConfig.WidthConfig = LayoutUtils.loadLayoutValue(layout, "WidthConfig", 520)
    layoutConfig.HeightConfig = LayoutUtils.loadLayoutValue(layout, "HeightConfig", 420)
    uiState.syncBankWindow = LayoutUtils.loadLayoutValue(layout, "SyncBankWindow", layoutDefaults.SyncBankWindow == 1)
    uiState.suppressWhenLootMac = LayoutUtils.loadLayoutValue(layout, "SuppressWhenLootMac", layoutDefaults.SuppressWhenLootMac == 1)
    uiState.confirmBeforeDelete = LayoutUtils.loadLayoutValue(layout, "ConfirmBeforeDelete", (layoutDefaults.ConfirmBeforeDelete or 1) == 1)
    uiState.sellViewLocked = LayoutUtils.loadLayoutValue(layout, "SellViewLocked", true)
    uiState.invViewLocked = LayoutUtils.loadLayoutValue(layout, "InvViewLocked", true)
    uiState.bankViewLocked = LayoutUtils.loadLayoutValue(layout, "BankViewLocked", true)
    local ct = LayoutUtils.loadLayoutValue(layout, "ConfigTab", 1)
    -- Tabs 1-4 only; legacy 5 or 10-12 map to 1
    filterState.configTab = (type(ct) == "number" and ct >= 1 and ct <= 4) and ct or 1
    local fst = LayoutUtils.loadLayoutValue(layout, "FilterSubTab", 1)
    filterState.filterSubTab = (type(fst) == "number" and fst >= 1 and fst <= 3) and fst or 1
        local invCol = LayoutUtils.loadLayoutValue(layout, "InvSortColumn", "Name")
        sortState.invColumn = (type(invCol) == "string" and invCol ~= "") and invCol or "Name"
        local invDir = LayoutUtils.loadLayoutValue(layout, "InvSortDirection", ImGuiSortDirection.Ascending)
        sortState.invDirection = (type(invDir) == "number") and invDir or ImGuiSortDirection.Ascending
        -- Load Inventory column order (new feature)
        local invColOrder = layout["InvColumnOrder"]
        if invColOrder and invColOrder ~= "" then
            sortState.invColumnOrder = {}
            for colKey in invColOrder:gmatch("([^/]+)") do
                table.insert(sortState.invColumnOrder, colKey:match("^%s*(.-)%s*$"))
            end
        else
            sortState.invColumnOrder = nil  -- Use default ordering
        end
        local sellCol = LayoutUtils.loadLayoutValue(layout, "SellSortColumn", "Name")
    sortState.sellColumn = (type(sellCol) == "string" and sellCol ~= "") and sellCol or "Name"
    local sellDir = LayoutUtils.loadLayoutValue(layout, "SellSortDirection", ImGuiSortDirection.Ascending)
    sortState.sellDirection = (type(sellDir) == "number") and sellDir or ImGuiSortDirection.Ascending
    local bankCol = LayoutUtils.loadLayoutValue(layout, "BankSortColumn", "Name")
    sortState.bankColumn = (type(bankCol) == "string" and bankCol ~= "") and bankCol or "Name"
    local bankDir = LayoutUtils.loadLayoutValue(layout, "BankSortDirection", ImGuiSortDirection.Ascending)
    sortState.bankDirection = (type(bankDir) == "number") and bankDir or ImGuiSortDirection.Ascending
    -- Load Bank column order from file
    local bankColOrder = layout["BankColumnOrder"]
    if bankColOrder and bankColOrder ~= "" then
        sortState.bankColumnOrder = {}
        for colKey in bankColOrder:gmatch("([^/]+)") do
            table.insert(sortState.bankColumnOrder, colKey:match("^%s*(.-)%s*$"))
        end
    else
        sortState.bankColumnOrder = nil  -- Use default ordering
    end
    local aaCol = LayoutUtils.loadLayoutValue(layout, "AASortColumn", "Title")
    sortState.aaColumn = (type(aaCol) == "string" and aaCol ~= "") and aaCol or "Title"
    local aaDir = LayoutUtils.loadLayoutValue(layout, "AASortDirection", ImGuiSortDirection.Ascending)
    sortState.aaDirection = (type(aaDir) == "number") and aaDir or ImGuiSortDirection.Ascending
    local aaTab = LayoutUtils.loadLayoutValue(layout, "AALastTab", 1)
    sortState.aaTab = (type(aaTab) == "number" and aaTab >= 1 and aaTab <= 4) and aaTab or 1
    LayoutUtils.applyColumnVisibilityFromParsed(parsed)
    local e = mq.gettime() - t0
    if LayoutUtils.DEBUG then
        print(string.format("[LayoutUtils DEBUG] Loaded from FILE - InvSort: %s/%d", tostring(sortState.invColumn), sortState.invDirection))
    end
    if C.PROFILE_ENABLED and e >= C.PROFILE_THRESHOLD_MS then
        print(string.format("\ag[ItemUI Profile]\ax loadLayoutConfig (file read): %d ms", e))
    end
end

-- Save layout for specific view
function LayoutUtils.saveLayoutForView(view, w, h, bankPanelW)
    local layoutConfig = LayoutUtils.layoutConfig
    
    if view == "Inventory" then
        layoutConfig.WidthInventory = w
        layoutConfig.Height = h
    elseif view == "Sell" then
        layoutConfig.WidthSell = w
        layoutConfig.Height = h
    elseif view == "Loot" then
        layoutConfig.WidthLoot = w
        layoutConfig.Height = h
    -- Bank window is now separate and saves its own size when resized
    end
    LayoutUtils.saveLayoutToFile()
end

return LayoutUtils
