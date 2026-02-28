--[[
    Layout Management Utilities
    
    Part of ItemUI Phase 7: View Extraction & Modularization
    Handles all layout persistence, loading, saving, and column visibility management
--]]

local mq = require('mq')
local config = require('itemui.config')
local file_safe = require('itemui.utils.file_safe')
local constants = require('itemui.constants')
local layout_io = require('itemui.utils.layout_io')
local layout_columns = require('itemui.utils.layout_columns')
local layout_setup = require('itemui.utils.layout_setup')
local diagnostics = require('itemui.core.diagnostics')

local LayoutUtils = {}

local LAYOUT_SECTION = constants.LAYOUT_SECTION

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
    
    layout_columns.init({
        columnVisibility = deps.columnVisibility,
        layoutConfig = deps.layoutConfig,
        availableColumns = deps.availableColumns or {},
        saveLayoutToFileImmediate = function() LayoutUtils.saveLayoutToFileImmediate() end,
    })
    layout_setup.init({
        layoutDefaults = LayoutUtils.layoutDefaults,
        layoutConfig = LayoutUtils.layoutConfig,
        uiState = LayoutUtils.uiState,
        columnVisibility = LayoutUtils.columnVisibility,
        sortState = LayoutUtils.sortState,
        perfCache = LayoutUtils.perfCache,
        getLayoutFilePath = function() return LayoutUtils.getLayoutFilePath() end,
        parseLayoutFileFull = function() return LayoutUtils.parseLayoutFileFull() end,
        initColumnVisibility = function() LayoutUtils.initColumnVisibility() end,
        applyDefaultsFromParsed = function(p) LayoutUtils.applyDefaultsFromParsed(p) end,
        saveLayoutToFile = function() LayoutUtils.saveLayoutToFile() end,
    })
    
    -- Debug: Enable to trace layout save/load
    LayoutUtils.DEBUG = false  -- Set to true to enable debug logging
end

-- Delegate INI path and parse to layout_io (Phase D extraction 8)
function LayoutUtils.getLayoutFilePath()
    return layout_io.getLayoutFilePath()
end

function LayoutUtils.parseLayoutFileFull()
    return layout_io.parseLayoutFileFull()
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
    if d.ShowEquipmentWindow then layoutDefaults.ShowEquipmentWindow = tonumber(d.ShowEquipmentWindow) or layoutDefaults.ShowEquipmentWindow end
    if d.ShowBankWindow then layoutDefaults.ShowBankWindow = tonumber(d.ShowBankWindow) or layoutDefaults.ShowBankWindow end
    if d.ShowAugmentsWindow then layoutDefaults.ShowAugmentsWindow = tonumber(d.ShowAugmentsWindow) or layoutDefaults.ShowAugmentsWindow end
    if d.ShowAugmentUtilityWindow then layoutDefaults.ShowAugmentUtilityWindow = tonumber(d.ShowAugmentUtilityWindow) or layoutDefaults.ShowAugmentUtilityWindow end
    if d.ShowItemDisplayWindow then layoutDefaults.ShowItemDisplayWindow = tonumber(d.ShowItemDisplayWindow) or layoutDefaults.ShowItemDisplayWindow end
    if d.ShowConfigWindow then layoutDefaults.ShowConfigWindow = tonumber(d.ShowConfigWindow) or layoutDefaults.ShowConfigWindow end
    if d.ShowRerollWindow then layoutDefaults.ShowRerollWindow = tonumber(d.ShowRerollWindow) or layoutDefaults.ShowRerollWindow end
    if d.AABackupPath ~= nil then layoutDefaults.AABackupPath = (d.AABackupPath and d.AABackupPath ~= "") and d.AABackupPath or "" end
    if d.WidthRerollPanel then layoutDefaults.WidthRerollPanel = tonumber(d.WidthRerollPanel) or layoutDefaults.WidthRerollPanel end
    if d.HeightReroll then layoutDefaults.HeightReroll = tonumber(d.HeightReroll) or layoutDefaults.HeightReroll end
    if d.RerollWindowX then layoutDefaults.RerollWindowX = tonumber(d.RerollWindowX) or layoutDefaults.RerollWindowX end
    if d.RerollWindowY then layoutDefaults.RerollWindowY = tonumber(d.RerollWindowY) or layoutDefaults.RerollWindowY end
    if d.SyncBankWindow then layoutDefaults.SyncBankWindow = setBool(d.SyncBankWindow) and 1 or 0 end
    if d.SuppressWhenLootMac then layoutDefaults.SuppressWhenLootMac = setBool(d.SuppressWhenLootMac) and 1 or 0 end
    if d.ConfirmBeforeDelete ~= nil then layoutDefaults.ConfirmBeforeDelete = setBool(d.ConfirmBeforeDelete) and 1 or 0 end
    if d.ActivationGuardEnabled ~= nil then layoutDefaults.ActivationGuardEnabled = setBool(d.ActivationGuardEnabled) and 1 or 0 end
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

-- Delegate column visibility and fixed-column logic to layout_columns (Phase D extraction 9)
function LayoutUtils.applyColumnVisibilityFromParsed(parsed)
    layout_columns.applyColumnVisibilityFromParsed(parsed)
end

-- Load column visibility from INI (standalone - parses file; use applyColumnVisibilityFromParsed when already parsed)
function LayoutUtils.loadColumnVisibility()
    LayoutUtils.initColumnVisibility()
    local parsed = LayoutUtils.parseLayoutFileFull()
    LayoutUtils.applyDefaultsFromParsed(parsed)
    LayoutUtils.applyColumnVisibilityFromParsed(parsed)
end

function LayoutUtils.parseLayoutFile()
    return layout_io.parseLayoutFile()
end

function LayoutUtils.loadLayoutValue(layout, key, default)
    return layout_io.loadLayoutValue(layout, key, default)
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
        f:write("ShowEquipmentWindow=" .. tostring(layoutConfig.ShowEquipmentWindow or layoutDefaults.ShowEquipmentWindow) .. "\n")
        f:write("ShowBankWindow=" .. tostring(layoutConfig.ShowBankWindow or layoutDefaults.ShowBankWindow) .. "\n")
        f:write("ShowAugmentsWindow=" .. tostring(layoutConfig.ShowAugmentsWindow or layoutDefaults.ShowAugmentsWindow) .. "\n")
        f:write("ShowAugmentUtilityWindow=" .. tostring(layoutConfig.ShowAugmentUtilityWindow or layoutDefaults.ShowAugmentUtilityWindow) .. "\n")
        f:write("ShowItemDisplayWindow=" .. tostring(layoutConfig.ShowItemDisplayWindow or layoutDefaults.ShowItemDisplayWindow) .. "\n")
        f:write("ShowConfigWindow=" .. tostring(layoutConfig.ShowConfigWindow or layoutDefaults.ShowConfigWindow) .. "\n")
        f:write("ShowRerollWindow=" .. tostring(layoutConfig.ShowRerollWindow or layoutDefaults.ShowRerollWindow) .. "\n")
        f:write("AABackupPath=" .. tostring(layoutConfig.AABackupPath or "") .. "\n")
        f:write("WidthRerollPanel=" .. tostring(layoutConfig.WidthRerollPanel or layoutDefaults.WidthRerollPanel) .. "\n")
        f:write("HeightReroll=" .. tostring(layoutConfig.HeightReroll or layoutDefaults.HeightReroll) .. "\n")
        f:write("RerollWindowX=" .. tostring(layoutConfig.RerollWindowX or layoutDefaults.RerollWindowX or 0) .. "\n")
        f:write("RerollWindowY=" .. tostring(layoutConfig.RerollWindowY or layoutDefaults.RerollWindowY or 0) .. "\n")
        f:write("WidthConfig=" .. tostring(layoutConfig.WidthConfig or constants.VIEWS.WidthConfig) .. "\n")
        f:write("HeightConfig=" .. tostring(layoutConfig.HeightConfig or 420) .. "\n")
        f:write("SyncBankWindow=" .. (uiState.syncBankWindow and "1" or "0") .. "\n")
        f:write("SuppressWhenLootMac=" .. (uiState.suppressWhenLootMac and "1" or "0") .. "\n")
        f:write("ConfirmBeforeDelete=" .. (uiState.confirmBeforeDelete and "1" or "0") .. "\n")
        f:write("ActivationGuardEnabled=" .. ((layoutConfig.ActivationGuardEnabled == nil or layoutConfig.ActivationGuardEnabled) and "1" or "0") .. "\n")
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
    if not ok then
        if print then print(string.format("\ar[CoOpt UI]\ax saveLayoutToFileImmediate failed: %s", tostring(err))) end
        diagnostics.recordError("Layout", "Save layout to file failed", err)
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

function LayoutUtils.saveColumnVisibility()
    layout_columns.saveColumnVisibility()
end

function LayoutUtils.toggleFixedColumn(view, colKey)
    return layout_columns.toggleFixedColumn(view, colKey)
end

function LayoutUtils.isColumnInFixedSet(view, colKey)
    return layout_columns.isColumnInFixedSet(view, colKey)
end

function LayoutUtils.getFixedColumns(view)
    return layout_columns.getFixedColumns(view)
end

-- Save layout to file (delegates to saveLayoutToFileImmediate)
function LayoutUtils.saveLayoutToFile()
    LayoutUtils.saveLayoutToFileImmediate()
end

-- Capture current layout state as snapshot (defaults); reset layout to defaults (Phase D extraction 10: layout_setup)
function LayoutUtils.captureCurrentLayoutAsDefault()
    layout_setup.captureCurrentLayoutAsDefault()
end

function LayoutUtils.resetLayoutToDefault()
    layout_setup.resetLayoutToDefault()
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
        layoutConfig.ShowEquipmentWindow = LayoutUtils.loadLayoutValue(layout, "ShowEquipmentWindow", layoutDefaults.ShowEquipmentWindow)
        layoutConfig.ShowBankWindow = LayoutUtils.loadLayoutValue(layout, "ShowBankWindow", layoutDefaults.ShowBankWindow)
        layoutConfig.ShowAugmentsWindow = LayoutUtils.loadLayoutValue(layout, "ShowAugmentsWindow", layoutDefaults.ShowAugmentsWindow)
        layoutConfig.ShowAugmentUtilityWindow = LayoutUtils.loadLayoutValue(layout, "ShowAugmentUtilityWindow", layoutDefaults.ShowAugmentUtilityWindow)
        layoutConfig.ShowItemDisplayWindow = LayoutUtils.loadLayoutValue(layout, "ShowItemDisplayWindow", layoutDefaults.ShowItemDisplayWindow)
        layoutConfig.ShowConfigWindow = LayoutUtils.loadLayoutValue(layout, "ShowConfigWindow", layoutDefaults.ShowConfigWindow)
        layoutConfig.ShowRerollWindow = LayoutUtils.loadLayoutValue(layout, "ShowRerollWindow", layoutDefaults.ShowRerollWindow)
        layoutConfig.AABackupPath = (layout["AABackupPath"] and layout["AABackupPath"] ~= "") and layout["AABackupPath"] or (layoutDefaults.AABackupPath or "")
        layoutConfig.WidthRerollPanel = LayoutUtils.loadLayoutValue(layout, "WidthRerollPanel", layoutDefaults.WidthRerollPanel)
        layoutConfig.HeightReroll = LayoutUtils.loadLayoutValue(layout, "HeightReroll", layoutDefaults.HeightReroll)
        layoutConfig.RerollWindowX = LayoutUtils.loadLayoutValue(layout, "RerollWindowX", layoutDefaults.RerollWindowX or 0)
        layoutConfig.RerollWindowY = LayoutUtils.loadLayoutValue(layout, "RerollWindowY", layoutDefaults.RerollWindowY or 0)
        layoutConfig.WidthConfig = LayoutUtils.loadLayoutValue(layout, "WidthConfig", constants.VIEWS.WidthConfig)
        layoutConfig.HeightConfig = LayoutUtils.loadLayoutValue(layout, "HeightConfig", 420)
        uiState.syncBankWindow = LayoutUtils.loadLayoutValue(layout, "SyncBankWindow", layoutDefaults.SyncBankWindow == 1)
        uiState.suppressWhenLootMac = LayoutUtils.loadLayoutValue(layout, "SuppressWhenLootMac", layoutDefaults.SuppressWhenLootMac == 1)
        uiState.confirmBeforeDelete = LayoutUtils.loadLayoutValue(layout, "ConfirmBeforeDelete", (layoutDefaults.ConfirmBeforeDelete or 1) == 1)
        layoutConfig.ActivationGuardEnabled = LayoutUtils.loadLayoutValue(layout, "ActivationGuardEnabled", (layoutDefaults.ActivationGuardEnabled or 1) == 1)
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
            print(string.format("\ag[CoOpt UI Profile]\ax loadLayoutConfig (cached): %d ms", e))
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
    layoutConfig.ShowEquipmentWindow = LayoutUtils.loadLayoutValue(layout, "ShowEquipmentWindow", layoutDefaults.ShowEquipmentWindow)
    layoutConfig.ShowBankWindow = LayoutUtils.loadLayoutValue(layout, "ShowBankWindow", layoutDefaults.ShowBankWindow)
    layoutConfig.ShowAugmentsWindow = LayoutUtils.loadLayoutValue(layout, "ShowAugmentsWindow", layoutDefaults.ShowAugmentsWindow)
    layoutConfig.ShowAugmentUtilityWindow = LayoutUtils.loadLayoutValue(layout, "ShowAugmentUtilityWindow", layoutDefaults.ShowAugmentUtilityWindow)
    layoutConfig.ShowItemDisplayWindow = LayoutUtils.loadLayoutValue(layout, "ShowItemDisplayWindow", layoutDefaults.ShowItemDisplayWindow)
    layoutConfig.ShowConfigWindow = LayoutUtils.loadLayoutValue(layout, "ShowConfigWindow", layoutDefaults.ShowConfigWindow)
    layoutConfig.ShowRerollWindow = LayoutUtils.loadLayoutValue(layout, "ShowRerollWindow", layoutDefaults.ShowRerollWindow)
    layoutConfig.AABackupPath = (layout["AABackupPath"] and layout["AABackupPath"] ~= "") and layout["AABackupPath"] or (layoutDefaults.AABackupPath or "")
    layoutConfig.WidthRerollPanel = LayoutUtils.loadLayoutValue(layout, "WidthRerollPanel", layoutDefaults.WidthRerollPanel)
    layoutConfig.HeightReroll = LayoutUtils.loadLayoutValue(layout, "HeightReroll", layoutDefaults.HeightReroll)
    layoutConfig.RerollWindowX = LayoutUtils.loadLayoutValue(layout, "RerollWindowX", layoutDefaults.RerollWindowX or 0)
    layoutConfig.RerollWindowY = LayoutUtils.loadLayoutValue(layout, "RerollWindowY", layoutDefaults.RerollWindowY or 0)
    layoutConfig.WidthConfig = LayoutUtils.loadLayoutValue(layout, "WidthConfig", constants.VIEWS.WidthConfig)
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
        print(string.format("\ag[CoOpt UI Profile]\ax loadLayoutConfig (file read): %d ms", e))
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
