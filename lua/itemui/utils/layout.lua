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
local registry = require('itemui.core.registry')
local diagnostics = require('itemui.core.diagnostics')
local debugModule = require('itemui.core.debug')
local dbg = debugModule.channel('Layout')

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
    
    -- Debug logging controlled via Settings > Advanced > Debug: Layout
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
    if d.ScriptTrackerWindowX then layoutDefaults.ScriptTrackerWindowX = tonumber(d.ScriptTrackerWindowX) or layoutDefaults.ScriptTrackerWindowX end
    if d.ScriptTrackerWindowY then layoutDefaults.ScriptTrackerWindowY = tonumber(d.ScriptTrackerWindowY) or layoutDefaults.ScriptTrackerWindowY end
    if d.WidthScriptTrackerPanel then layoutDefaults.WidthScriptTrackerPanel = tonumber(d.WidthScriptTrackerPanel) or layoutDefaults.WidthScriptTrackerPanel end
    if d.HeightScriptTracker then layoutDefaults.HeightScriptTracker = tonumber(d.HeightScriptTracker) or layoutDefaults.HeightScriptTracker end
    if d.WidthAugmentsPanel then layoutDefaults.WidthAugmentsPanel = tonumber(d.WidthAugmentsPanel) or layoutDefaults.WidthAugmentsPanel end
    if d.HeightAugments then layoutDefaults.HeightAugments = tonumber(d.HeightAugments) or layoutDefaults.HeightAugments end
    if d.AugmentsWindowX then layoutDefaults.AugmentsWindowX = tonumber(d.AugmentsWindowX) or layoutDefaults.AugmentsWindowX end
    if d.AugmentsWindowY then layoutDefaults.AugmentsWindowY = tonumber(d.AugmentsWindowY) or layoutDefaults.AugmentsWindowY end
    if d.WidthMythicalsPanel then layoutDefaults.WidthMythicalsPanel = tonumber(d.WidthMythicalsPanel) or layoutDefaults.WidthMythicalsPanel end
    if d.HeightMythicals then layoutDefaults.HeightMythicals = tonumber(d.HeightMythicals) or layoutDefaults.HeightMythicals end
    if d.MythicalsWindowX then layoutDefaults.MythicalsWindowX = tonumber(d.MythicalsWindowX) or layoutDefaults.MythicalsWindowX end
    if d.MythicalsWindowY then layoutDefaults.MythicalsWindowY = tonumber(d.MythicalsWindowY) or layoutDefaults.MythicalsWindowY end
    if d.CommandCenterWindowX then layoutDefaults.CommandCenterWindowX = tonumber(d.CommandCenterWindowX) or layoutDefaults.CommandCenterWindowX end
    if d.CommandCenterWindowY then layoutDefaults.CommandCenterWindowY = tonumber(d.CommandCenterWindowY) or layoutDefaults.CommandCenterWindowY end
    if d.WidthFavoritesPanel then layoutDefaults.WidthFavoritesPanel = tonumber(d.WidthFavoritesPanel) or layoutDefaults.WidthFavoritesPanel end
    if d.HeightFavorites then layoutDefaults.HeightFavorites = tonumber(d.HeightFavorites) or layoutDefaults.HeightFavorites end
    if d.FavoritesWindowX then layoutDefaults.FavoritesWindowX = tonumber(d.FavoritesWindowX) or layoutDefaults.FavoritesWindowX end
    if d.FavoritesWindowY then layoutDefaults.FavoritesWindowY = tonumber(d.FavoritesWindowY) or layoutDefaults.FavoritesWindowY end
    if d.WidthEffectsPanel then layoutDefaults.WidthEffectsPanel = tonumber(d.WidthEffectsPanel) or layoutDefaults.WidthEffectsPanel end
    if d.HeightEffects then layoutDefaults.HeightEffects = tonumber(d.HeightEffects) or layoutDefaults.HeightEffects end
    if d.EffectsWindowX then layoutDefaults.EffectsWindowX = tonumber(d.EffectsWindowX) or layoutDefaults.EffectsWindowX end
    if d.EffectsWindowY then layoutDefaults.EffectsWindowY = tonumber(d.EffectsWindowY) or layoutDefaults.EffectsWindowY end
    if d.EffectsCompact then layoutDefaults.EffectsCompact = tonumber(d.EffectsCompact) or layoutDefaults.EffectsCompact end
    if d.ChatWindowX then layoutDefaults.ChatWindowX = tonumber(d.ChatWindowX) or layoutDefaults.ChatWindowX end
    if d.ChatWindowY then layoutDefaults.ChatWindowY = tonumber(d.ChatWindowY) or layoutDefaults.ChatWindowY end
    if d.WidthChatPanel then layoutDefaults.WidthChatPanel = tonumber(d.WidthChatPanel) or layoutDefaults.WidthChatPanel end
    if d.HeightChat then layoutDefaults.HeightChat = tonumber(d.HeightChat) or layoutDefaults.HeightChat end
    if d.ShowChatWindow then layoutDefaults.ShowChatWindow = tonumber(d.ShowChatWindow) or layoutDefaults.ShowChatWindow end
    if d.ChatUseZep then layoutDefaults.ChatUseZep = tonumber(d.ChatUseZep) or layoutDefaults.ChatUseZep end
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
    if d.EquipmentWindowX then layoutDefaults.EquipmentWindowX = tonumber(d.EquipmentWindowX) or layoutDefaults.EquipmentWindowX end
    if d.EquipmentWindowY then layoutDefaults.EquipmentWindowY = tonumber(d.EquipmentWindowY) or layoutDefaults.EquipmentWindowY end
    if d.WidthEquipmentPanel then layoutDefaults.WidthEquipmentPanel = tonumber(d.WidthEquipmentPanel) or layoutDefaults.WidthEquipmentPanel end
    if d.HeightEquipment then layoutDefaults.HeightEquipment = tonumber(d.HeightEquipment) or layoutDefaults.HeightEquipment end
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
    if d.SuppressWhenLootMac then layoutDefaults.SuppressWhenLootMac = setBool(d.SuppressWhenLootMac) and 1 or 0 end
    if d.EnableRealTimeLoot ~= nil then layoutDefaults.EnableRealTimeLoot = setBool(d.EnableRealTimeLoot) and 1 or 0 end
    if d.EnableLootHistory ~= nil then layoutDefaults.EnableLootHistory = setBool(d.EnableLootHistory) and 1 or 0 end
    if d.EnableSkipHistory ~= nil then layoutDefaults.EnableSkipHistory = setBool(d.EnableSkipHistory) and 1 or 0 end
    if d.ConfirmBeforeDelete ~= nil then layoutDefaults.ConfirmBeforeDelete = setBool(d.ConfirmBeforeDelete) and 1 or 0 end
    if d.ActivationGuardEnabled ~= nil then layoutDefaults.ActivationGuardEnabled = setBool(d.ActivationGuardEnabled) and 1 or 0 end
    if d.AlignToContext then layoutDefaults.AlignToContext = setBool(d.AlignToContext) and 1 or 0 end
    if d.UILocked then layoutDefaults.UILocked = setBool(d.UILocked) and 1 or 0 end
    -- Dock / bars arrangement strings (CSV / name keys). Read verbatim with ~= nil guards:
    -- tonumber() would nil them out, and empty is meaningful (e.g. ZoneAssign= means "no
    -- overrides" was captured). Paradigm keys (UIMode, Dock toggles/style) are deliberately
    -- never in [Defaults] — see layout_setup.lua.
    if d.DockSegments ~= nil then layoutDefaults.DockSegments = d.DockSegments end
    if d.ZoneAssign ~= nil then layoutDefaults.ZoneAssign = d.ZoneAssign end
    if d.WindowAttach ~= nil then layoutDefaults.WindowAttach = d.WindowAttach end
    if d.LayoutPreset ~= nil then layoutDefaults.LayoutPreset = d.LayoutPreset end
    if d.UserPlaced ~= nil then layoutDefaults.UserPlaced = d.UserPlaced end
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

--- Set a [Layout] key that must survive until the debounced save lands.
---
--- scheduleLayoutSave() alone is not enough for anything the user can immediately act on.
--- It only sets perfCache.layoutDirty; layoutNeedsReload is set exclusively by
--- saveLayoutToFileImmediate, which phase9 defers by LAYOUT_SAVE_DEBOUNCE_MS. So during that
--- 600ms window loadLayoutConfig still takes its CACHE branch and applyLayoutSection re-reads
--- the STALE parsed value straight back over the change -- and because layoutDirty is never
--- cleared, the save that follows then persists the reverted value. A user who toggles the
--- bars in Settings and presses Shift+Q within 600ms (which reloads the layout) would watch
--- the setting undo itself.
---
--- Patching the cached parse keeps the two views of the INI agreed until the write lands.
--- Values are stored as the INI's own strings so loadLayoutValue converts them exactly as it
--- would after a real re-read.
function LayoutUtils.setLayoutValue(key, value)
    local layoutConfig = LayoutUtils.layoutConfig
    if layoutConfig then layoutConfig[key] = value end
    local cached = LayoutUtils.perfCache and LayoutUtils.perfCache.layoutCached
    local layout = cached and cached.layout
    if layout then
        if type(value) == "boolean" then
            layout[key] = value and "1" or "0"
        else
            layout[key] = tostring(value)
        end
    end
    LayoutUtils.scheduleLayoutSave()
end

-- Schedule layout save (debounced) - use for sort clicks, tab switches, etc.
function LayoutUtils.scheduleLayoutSave()
    local perfCache = LayoutUtils.perfCache
    perfCache.layoutDirty = true
    perfCache.layoutSaveScheduledAt = mq.gettime()
    dbg.log("scheduleLayoutSave() called - layoutDirty set to true")
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
    
    dbg.log(string.format("Saving layout - InvSort: %s/%d, SellSort: %s/%d, BankSort: %s/%d",
            tostring(sortState.invColumn or "nil"), sortState.invDirection or 0,
            tostring(sortState.sellColumn or "nil"), sortState.sellDirection or 0,
            tostring(sortState.bankColumn or "nil"), sortState.bankDirection or 0))

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

    local function writeLayoutFile(targetPath)
        local f = io.open(targetPath, "w")
        if not f then error("io.open write failed") end
        for _, line in ipairs(lines) do
            f:write(line .. "\n")
        end
        f:write("[" .. LAYOUT_SECTION .. "]\n")
        f:write("AlignToContext=" .. (uiState.alignToContext and "1" or "0") .. "\n")
        f:write("UILocked=" .. (uiState.uiLocked and "1" or "0") .. "\n")
        f:write("WidthInventory=" .. tostring(layoutConfig.WidthInventory or layoutDefaults.WidthInventory) .. "\n")
        f:write("Height=" .. tostring(layoutConfig.Height or layoutDefaults.Height) .. "\n")
        f:write("WidthSell=" .. tostring(layoutConfig.WidthSell or layoutDefaults.WidthSell) .. "\n")
        f:write("WidthLoot=" .. tostring(layoutConfig.WidthLoot or layoutDefaults.WidthLoot) .. "\n")
        f:write("WidthBankPanel=" .. tostring(layoutConfig.WidthBankPanel or layoutDefaults.WidthBankPanel) .. "\n")
        f:write("HeightBank=" .. tostring(layoutConfig.HeightBank or layoutDefaults.HeightBank) .. "\n")
        f:write("BankWindowX=" .. tostring(layoutConfig.BankWindowX or layoutDefaults.BankWindowX) .. "\n")
        f:write("BankWindowY=" .. tostring(layoutConfig.BankWindowY or layoutDefaults.BankWindowY) .. "\n")
        f:write("ScriptTrackerWindowX=" .. tostring(layoutConfig.ScriptTrackerWindowX or layoutDefaults.ScriptTrackerWindowX or 0) .. "\n")
        f:write("ScriptTrackerWindowY=" .. tostring(layoutConfig.ScriptTrackerWindowY or layoutDefaults.ScriptTrackerWindowY or 0) .. "\n")
        f:write("WidthScriptTrackerPanel=" .. tostring(layoutConfig.WidthScriptTrackerPanel or layoutDefaults.WidthScriptTrackerPanel or 460) .. "\n")
        f:write("HeightScriptTracker=" .. tostring(layoutConfig.HeightScriptTracker or layoutDefaults.HeightScriptTracker or 400) .. "\n")
        f:write("WidthAugmentsPanel=" .. tostring(layoutConfig.WidthAugmentsPanel or layoutDefaults.WidthAugmentsPanel) .. "\n")
        f:write("HeightAugments=" .. tostring(layoutConfig.HeightAugments or layoutDefaults.HeightAugments) .. "\n")
        f:write("AugmentsWindowX=" .. tostring(layoutConfig.AugmentsWindowX or layoutDefaults.AugmentsWindowX) .. "\n")
        f:write("AugmentsWindowY=" .. tostring(layoutConfig.AugmentsWindowY or layoutDefaults.AugmentsWindowY) .. "\n")
        f:write("WidthMythicalsPanel=" .. tostring(layoutConfig.WidthMythicalsPanel or layoutDefaults.WidthMythicalsPanel) .. "\n")
        f:write("HeightMythicals=" .. tostring(layoutConfig.HeightMythicals or layoutDefaults.HeightMythicals) .. "\n")
        f:write("MythicalsWindowX=" .. tostring(layoutConfig.MythicalsWindowX or layoutDefaults.MythicalsWindowX) .. "\n")
        f:write("MythicalsWindowY=" .. tostring(layoutConfig.MythicalsWindowY or layoutDefaults.MythicalsWindowY) .. "\n")
        f:write("CommandCenterWindowX=" .. tostring(layoutConfig.CommandCenterWindowX or layoutDefaults.CommandCenterWindowX) .. "\n")
        f:write("CommandCenterWindowY=" .. tostring(layoutConfig.CommandCenterWindowY or layoutDefaults.CommandCenterWindowY) .. "\n")
        f:write("WidthFavoritesPanel=" .. tostring(layoutConfig.WidthFavoritesPanel or layoutDefaults.WidthFavoritesPanel) .. "\n")
        f:write("HeightFavorites=" .. tostring(layoutConfig.HeightFavorites or layoutDefaults.HeightFavorites) .. "\n")
        f:write("FavoritesWindowX=" .. tostring(layoutConfig.FavoritesWindowX or layoutDefaults.FavoritesWindowX) .. "\n")
        f:write("FavoritesWindowY=" .. tostring(layoutConfig.FavoritesWindowY or layoutDefaults.FavoritesWindowY) .. "\n")
        f:write("WidthEffectsPanel=" .. tostring(layoutConfig.WidthEffectsPanel or layoutDefaults.WidthEffectsPanel) .. "\n")
        f:write("HeightEffects=" .. tostring(layoutConfig.HeightEffects or layoutDefaults.HeightEffects) .. "\n")
        f:write("EffectsWindowX=" .. tostring(layoutConfig.EffectsWindowX or layoutDefaults.EffectsWindowX) .. "\n")
        f:write("EffectsWindowY=" .. tostring(layoutConfig.EffectsWindowY or layoutDefaults.EffectsWindowY) .. "\n")
        f:write("EffectsCompact=" .. tostring(layoutConfig.EffectsCompact or 0) .. "\n")
        f:write("NativeHoverTooltip=" .. (uiState.nativeHoverTooltip ~= false and "1" or "0") .. "\n")
        f:write("NativeItemDisplayReplace=" .. (uiState.nativeItemDisplayReplace ~= false and "1" or "0") .. "\n")
        f:write("PinnedWindows=" .. registry.getPinnedCSV() .. "\n")
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
        f:write("EquipmentWindowX=" .. tostring(layoutConfig.EquipmentWindowX or layoutDefaults.EquipmentWindowX or 191) .. "\n")
        f:write("EquipmentWindowY=" .. tostring(layoutConfig.EquipmentWindowY or layoutDefaults.EquipmentWindowY or 31) .. "\n")
        f:write("WidthEquipmentPanel=" .. tostring(layoutConfig.WidthEquipmentPanel or layoutDefaults.WidthEquipmentPanel or 261) .. "\n")
        f:write("HeightEquipment=" .. tostring(layoutConfig.HeightEquipment or layoutDefaults.HeightEquipment or 497) .. "\n")
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
        f:write("SuppressWhenLootMac=" .. (uiState.suppressWhenLootMac and "1" or "0") .. "\n")
        f:write("EnableRealTimeLoot=" .. (uiState.enableRealTimeLoot and "1" or "0") .. "\n")
        f:write("EnableLootHistory=" .. (uiState.enableLootHistory and "1" or "0") .. "\n")
        f:write("EnableSkipHistory=" .. (uiState.enableSkipHistory and "1" or "0") .. "\n")
        f:write("ConfirmBeforeDelete=" .. (uiState.confirmBeforeDelete and "1" or "0") .. "\n")
        f:write("NativeMerchantStrip=" .. (uiState.nativeMerchantStrip ~= false and "1" or "0") .. "\n")
        f:write("ActivationGuardEnabled=" .. ((layoutConfig.ActivationGuardEnabled == nil or layoutConfig.ActivationGuardEnabled) and "1" or "0") .. "\n")
        f:write("ItemUIToggleKey=" .. tostring(layoutConfig.ItemUIToggleKey ~= nil and layoutConfig.ItemUIToggleKey or (layoutDefaults.ItemUIToggleKey or "shift+q")) .. "\n")
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
        -- Dock / bars mode. ZoneAssign and WindowAttach are single CSV keys rather than one
        -- key per module (ZoneAssign_bank=…): [Layout] is fully regenerated from this f:write
        -- list, so a per-module key would be erased on the next save. Same reason
        -- PinnedWindows above is one comma-joined string.
        f:write("UIMode=" .. tostring(layoutConfig.UIMode or layoutDefaults.UIMode or "classic") .. "\n")
        f:write("DockTop=" .. (layoutConfig.DockTop ~= false and "1" or "0") .. "\n")
        f:write("DockBottom=" .. (layoutConfig.DockBottom ~= false and "1" or "0") .. "\n")
        f:write("DockPosition=" .. tostring(layoutConfig.DockPosition or layoutDefaults.DockPosition or "top") .. "\n")
        f:write("DockChat=" .. tostring(layoutConfig.DockChat or layoutDefaults.DockChat or "collapsed") .. "\n")
        f:write("DockSegments=" .. tostring(layoutConfig.DockSegments or layoutDefaults.DockSegments or "") .. "\n")
        f:write("DockBottomStyle=" .. tostring(layoutConfig.DockBottomStyle or layoutDefaults.DockBottomStyle or "menus") .. "\n")
        f:write("DockButtons=" .. tostring(layoutConfig.DockButtons or layoutDefaults.DockButtons or "") .. "\n")
        f:write("ZoneAssign=" .. tostring(layoutConfig.ZoneAssign or "") .. "\n")
        f:write("WindowAttach=" .. tostring(layoutConfig.WindowAttach or "") .. "\n")
        f:write("LayoutPreset=" .. tostring(layoutConfig.LayoutPreset or "") .. "\n")
        f:write("UserPlaced=" .. tostring(layoutConfig.UserPlaced or "") .. "\n")
        -- Chat window (replaces the old peek-mode dock strip -- see docs/DOCK_UI.md).
        f:write("ChatWindowX=" .. tostring(layoutConfig.ChatWindowX or layoutDefaults.ChatWindowX) .. "\n")
        f:write("ChatWindowY=" .. tostring(layoutConfig.ChatWindowY or layoutDefaults.ChatWindowY) .. "\n")
        f:write("WidthChatPanel=" .. tostring(layoutConfig.WidthChatPanel or layoutDefaults.WidthChatPanel) .. "\n")
        f:write("HeightChat=" .. tostring(layoutConfig.HeightChat or layoutDefaults.HeightChat) .. "\n")
        f:write("ShowChatWindow=" .. tostring(layoutConfig.ShowChatWindow or layoutDefaults.ShowChatWindow) .. "\n")
        f:write("ChatUseZep=" .. tostring(layoutConfig.ChatUseZep or layoutDefaults.ChatUseZep) .. "\n")
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
    end
    -- Crash-safe write: stream to .tmp then swap in (remove + rename; os.rename does not
    -- overwrite existing files on Windows). On tmp/swap failure fall back to the direct
    -- write so behavior never regresses.
    local ok, err = pcall(function()
        local tmpPath = path .. ".tmp"
        writeLayoutFile(tmpPath)
        os.remove(path)  -- may not exist yet; result intentionally ignored
        local renamed, renameErr = os.rename(tmpPath, path)
        if not renamed then error("os.rename failed: " .. tostring(renameErr)) end
    end)
    if not ok then
        pcall(os.remove, path .. ".tmp")  -- best-effort cleanup of orphaned tmp
        ok, err = pcall(writeLayoutFile, path)
    end
    if not ok then
        if print then print(string.format("\ar[CoOpt UI]\ax saveLayoutToFileImmediate failed: %s", tostring(err))) end
        diagnostics.recordError("Layout", "Save layout to file failed", err)
    end
end

-- Flush any pending layout save (call on exit, setup save, sort change, etc.)
function LayoutUtils.flushLayoutSave()
    local perfCache = LayoutUtils.perfCache
    dbg.log(string.format("flushLayoutSave() called - layoutDirty: %s", tostring(perfCache.layoutDirty)))
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
--- Apply every [Layout] key from a parsed layout table onto layoutConfig / uiState /
--- sortState / filterState. ONE body, shared by both loadLayoutConfig paths (cache hit and
--- file re-parse). These were ~120 hand-duplicated lines that had already drifted once —
--- Equipment geometry was missing from the file branch, so any re-parse dropped the saved
--- position and the window's own move-save then wrote defaults back over it. Add a new key
--- HERE and both paths get it.
local function applyLayoutSection(parsed)
    local layoutConfig = LayoutUtils.layoutConfig
    local layoutDefaults = LayoutUtils.layoutDefaults
    local uiState = LayoutUtils.uiState
    local sortState = LayoutUtils.sortState
    local filterState = LayoutUtils.filterState
    local layout = parsed.layout or {}
    uiState.alignToContext = LayoutUtils.loadLayoutValue(layout, "AlignToContext", layoutDefaults.AlignToContext == 1)
    uiState.uiLocked = LayoutUtils.loadLayoutValue(layout, "UILocked", layoutDefaults.UILocked == 1)
    layoutConfig.WidthInventory = LayoutUtils.loadLayoutValue(layout, "WidthInventory", layoutDefaults.WidthInventory)
    layoutConfig.Height = LayoutUtils.loadLayoutValue(layout, "Height", layoutDefaults.Height)
    layoutConfig.WidthSell = LayoutUtils.loadLayoutValue(layout, "WidthSell", layoutDefaults.WidthSell)
    layoutConfig.WidthLoot = LayoutUtils.loadLayoutValue(layout, "WidthLoot", layoutDefaults.WidthLoot)
    layoutConfig.WidthBankPanel = LayoutUtils.loadLayoutValue(layout, "WidthBankPanel", layoutDefaults.WidthBankPanel)
    layoutConfig.HeightBank = LayoutUtils.loadLayoutValue(layout, "HeightBank", layoutDefaults.HeightBank)
    layoutConfig.BankWindowX = LayoutUtils.loadLayoutValue(layout, "BankWindowX", layoutDefaults.BankWindowX)
    layoutConfig.BankWindowY = LayoutUtils.loadLayoutValue(layout, "BankWindowY", layoutDefaults.BankWindowY)
    layoutConfig.ScriptTrackerWindowX = LayoutUtils.loadLayoutValue(layout, "ScriptTrackerWindowX", layoutDefaults.ScriptTrackerWindowX)
    layoutConfig.ScriptTrackerWindowY = LayoutUtils.loadLayoutValue(layout, "ScriptTrackerWindowY", layoutDefaults.ScriptTrackerWindowY)
    layoutConfig.WidthScriptTrackerPanel = LayoutUtils.loadLayoutValue(layout, "WidthScriptTrackerPanel", layoutDefaults.WidthScriptTrackerPanel)
    layoutConfig.HeightScriptTracker = LayoutUtils.loadLayoutValue(layout, "HeightScriptTracker", layoutDefaults.HeightScriptTracker)
    layoutConfig.WidthAugmentsPanel = LayoutUtils.loadLayoutValue(layout, "WidthAugmentsPanel", layoutDefaults.WidthAugmentsPanel)
    layoutConfig.HeightAugments = LayoutUtils.loadLayoutValue(layout, "HeightAugments", layoutDefaults.HeightAugments)
    layoutConfig.AugmentsWindowX = LayoutUtils.loadLayoutValue(layout, "AugmentsWindowX", layoutDefaults.AugmentsWindowX)
    layoutConfig.AugmentsWindowY = LayoutUtils.loadLayoutValue(layout, "AugmentsWindowY", layoutDefaults.AugmentsWindowY)
    layoutConfig.WidthMythicalsPanel = LayoutUtils.loadLayoutValue(layout, "WidthMythicalsPanel", layoutDefaults.WidthMythicalsPanel)
    layoutConfig.HeightMythicals = LayoutUtils.loadLayoutValue(layout, "HeightMythicals", layoutDefaults.HeightMythicals)
    layoutConfig.MythicalsWindowX = LayoutUtils.loadLayoutValue(layout, "MythicalsWindowX", layoutDefaults.MythicalsWindowX)
    layoutConfig.MythicalsWindowY = LayoutUtils.loadLayoutValue(layout, "MythicalsWindowY", layoutDefaults.MythicalsWindowY)
    layoutConfig.CommandCenterWindowX = LayoutUtils.loadLayoutValue(layout, "CommandCenterWindowX", layoutDefaults.CommandCenterWindowX)
    layoutConfig.CommandCenterWindowY = LayoutUtils.loadLayoutValue(layout, "CommandCenterWindowY", layoutDefaults.CommandCenterWindowY)
    layoutConfig.WidthFavoritesPanel = LayoutUtils.loadLayoutValue(layout, "WidthFavoritesPanel", layoutDefaults.WidthFavoritesPanel)
    layoutConfig.HeightFavorites = LayoutUtils.loadLayoutValue(layout, "HeightFavorites", layoutDefaults.HeightFavorites)
    layoutConfig.FavoritesWindowX = LayoutUtils.loadLayoutValue(layout, "FavoritesWindowX", layoutDefaults.FavoritesWindowX)
    layoutConfig.FavoritesWindowY = LayoutUtils.loadLayoutValue(layout, "FavoritesWindowY", layoutDefaults.FavoritesWindowY)
    layoutConfig.WidthEffectsPanel = LayoutUtils.loadLayoutValue(layout, "WidthEffectsPanel", layoutDefaults.WidthEffectsPanel)
    layoutConfig.HeightEffects = LayoutUtils.loadLayoutValue(layout, "HeightEffects", layoutDefaults.HeightEffects)
    layoutConfig.EffectsWindowX = LayoutUtils.loadLayoutValue(layout, "EffectsWindowX", layoutDefaults.EffectsWindowX)
    layoutConfig.EffectsWindowY = LayoutUtils.loadLayoutValue(layout, "EffectsWindowY", layoutDefaults.EffectsWindowY)
    layoutConfig.EffectsCompact = LayoutUtils.loadLayoutValue(layout, "EffectsCompact", 0)
    uiState.nativeHoverTooltip = LayoutUtils.loadLayoutValue(layout, "NativeHoverTooltip", (layoutDefaults.NativeHoverTooltip or 1) == 1)
    uiState.nativeItemDisplayReplace = LayoutUtils.loadLayoutValue(layout, "NativeItemDisplayReplace", (layoutDefaults.NativeItemDisplayReplace or 1) == 1)
    registry.setPinnedFromCSV(LayoutUtils.loadLayoutValue(layout, "PinnedWindows", ""))
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
    -- Equipment geometry: the cache branch loads these; missing them here meant any
    -- file re-parse (layoutNeedsReload) dropped the saved Equipment position and the
    -- window's own >1px move-save then overwrote the stored values with defaults.
    layoutConfig.EquipmentWindowX = LayoutUtils.loadLayoutValue(layout, "EquipmentWindowX", layoutDefaults.EquipmentWindowX or 191)
    layoutConfig.EquipmentWindowY = LayoutUtils.loadLayoutValue(layout, "EquipmentWindowY", layoutDefaults.EquipmentWindowY or 31)
    layoutConfig.WidthEquipmentPanel = LayoutUtils.loadLayoutValue(layout, "WidthEquipmentPanel", layoutDefaults.WidthEquipmentPanel or 261)
    layoutConfig.HeightEquipment = LayoutUtils.loadLayoutValue(layout, "HeightEquipment", layoutDefaults.HeightEquipment or 497)
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
    uiState.suppressWhenLootMac = LayoutUtils.loadLayoutValue(layout, "SuppressWhenLootMac", layoutDefaults.SuppressWhenLootMac == 1)
    uiState.enableRealTimeLoot = LayoutUtils.loadLayoutValue(layout, "EnableRealTimeLoot", (layoutDefaults.EnableRealTimeLoot or 0) == 1)
    uiState.enableLootHistory = LayoutUtils.loadLayoutValue(layout, "EnableLootHistory", (layoutDefaults.EnableLootHistory or 0) == 1)
    uiState.enableSkipHistory = LayoutUtils.loadLayoutValue(layout, "EnableSkipHistory", (layoutDefaults.EnableSkipHistory or 0) == 1)
    uiState.confirmBeforeDelete = LayoutUtils.loadLayoutValue(layout, "ConfirmBeforeDelete", (layoutDefaults.ConfirmBeforeDelete or 1) == 1)
    uiState.nativeMerchantStrip = LayoutUtils.loadLayoutValue(layout, "NativeMerchantStrip", (layoutDefaults.NativeMerchantStrip or 1) == 1)
    layoutConfig.ActivationGuardEnabled = LayoutUtils.loadLayoutValue(layout, "ActivationGuardEnabled", (layoutDefaults.ActivationGuardEnabled or 1) == 1)
    layoutConfig.ItemUIToggleKey = LayoutUtils.loadLayoutValue(layout, "ItemUIToggleKey", layoutDefaults.ItemUIToggleKey or "shift+q")
    local ct = LayoutUtils.loadLayoutValue(layout, "ConfigTab", 1)
    -- Tabs 1-5 (5 = Advanced); legacy 10-12 map to 1
    filterState.configTab = (type(ct) == "number" and ct >= 1 and ct <= 5) and ct or 1
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
    -- Dock / bars mode. UIMode gates the whole feature: "classic" must render exactly what
    -- master renders. Every string key here is listed in layout_io STRING_KEYS — without
    -- that it would read back as its default no matter what is in the file.
    layoutConfig.UIMode = LayoutUtils.loadLayoutValue(layout, "UIMode", layoutDefaults.UIMode or "classic")
    layoutConfig.DockTop = LayoutUtils.loadLayoutValue(layout, "DockTop", (layoutDefaults.DockTop or 1) == 1)
    layoutConfig.DockBottom = LayoutUtils.loadLayoutValue(layout, "DockBottom", (layoutDefaults.DockBottom or 1) == 1)
    layoutConfig.DockPosition = LayoutUtils.loadLayoutValue(layout, "DockPosition", layoutDefaults.DockPosition or "top")
    layoutConfig.DockChat = LayoutUtils.loadLayoutValue(layout, "DockChat", layoutDefaults.DockChat or "collapsed")
    layoutConfig.DockSegments = LayoutUtils.loadLayoutValue(layout, "DockSegments", layoutDefaults.DockSegments)
    layoutConfig.DockBottomStyle = LayoutUtils.loadLayoutValue(layout, "DockBottomStyle", layoutDefaults.DockBottomStyle or "menus")
    layoutConfig.DockButtons = LayoutUtils.loadLayoutValue(layout, "DockButtons", layoutDefaults.DockButtons)
    layoutConfig.ZoneAssign = LayoutUtils.loadLayoutValue(layout, "ZoneAssign", layoutDefaults.ZoneAssign or "")
    layoutConfig.WindowAttach = LayoutUtils.loadLayoutValue(layout, "WindowAttach", layoutDefaults.WindowAttach or "")
    layoutConfig.LayoutPreset = LayoutUtils.loadLayoutValue(layout, "LayoutPreset", layoutDefaults.LayoutPreset or "")
    layoutConfig.UserPlaced = LayoutUtils.loadLayoutValue(layout, "UserPlaced", layoutDefaults.UserPlaced or "")
    -- Chat window. Numeric geometry, so no layout_io STRING_KEYS entry needed (loadLayoutValue's
    -- numeric fallthrough handles it) -- only DockChat itself (hidden/collapsed) is a string key.
    layoutConfig.ChatWindowX = LayoutUtils.loadLayoutValue(layout, "ChatWindowX", layoutDefaults.ChatWindowX or 0)
    layoutConfig.ChatWindowY = LayoutUtils.loadLayoutValue(layout, "ChatWindowY", layoutDefaults.ChatWindowY or 0)
    layoutConfig.WidthChatPanel = LayoutUtils.loadLayoutValue(layout, "WidthChatPanel", layoutDefaults.WidthChatPanel or 560)
    layoutConfig.HeightChat = LayoutUtils.loadLayoutValue(layout, "HeightChat", layoutDefaults.HeightChat or 380)
    layoutConfig.ShowChatWindow = LayoutUtils.loadLayoutValue(layout, "ShowChatWindow", layoutDefaults.ShowChatWindow)
    layoutConfig.ChatUseZep = LayoutUtils.loadLayoutValue(layout, "ChatUseZep", layoutDefaults.ChatUseZep)
    LayoutUtils.applyColumnVisibilityFromParsed(parsed)
end

function LayoutUtils.loadLayoutConfig()
    local perfCache = LayoutUtils.perfCache
    local sortState = LayoutUtils.sortState
    local t0 = mq.gettime()
    -- Skip parse if config unchanged (perfCache.layoutNeedsReload set when we save)
    if not perfCache.layoutNeedsReload and perfCache.layoutCached then
        dbg.log("Loading layout from CACHE")
        LayoutUtils.initColumnVisibility()
        LayoutUtils.applyDefaultsFromParsed(perfCache.layoutCached)
        applyLayoutSection(perfCache.layoutCached)
        local e = mq.gettime() - t0
        dbg.log(string.format("Loaded from CACHE - InvSort: %s/%d", tostring(sortState.invColumn), sortState.invDirection))
        if debugModule.isProfileEnabled() and e >= debugModule.getProfileThresholdMs() then
            print(string.format("\ag[CoOpt UI Profile]\ax loadLayoutConfig (cached): %d ms", e))
        end
        return
    end
    -- Single file read: parse all sections at once (avoids 3x I/O on every UI open)
    dbg.log("Loading layout from FILE (cache miss or invalidated)")
    local parsed = LayoutUtils.parseLayoutFileFull()
    perfCache.layoutCached = parsed
    perfCache.layoutNeedsReload = false
    LayoutUtils.initColumnVisibility()
    LayoutUtils.applyDefaultsFromParsed(parsed)
    applyLayoutSection(parsed)
    local e = mq.gettime() - t0
    dbg.log(string.format("Loaded from FILE - InvSort: %s/%d", tostring(sortState.invColumn), sortState.invDirection))
    if debugModule.isProfileEnabled() and e >= debugModule.getProfileThresholdMs() then
        print(string.format("\ag[CoOpt UI Profile]\ax loadLayoutConfig (file read): %d ms", e))
    end
end

--- Normalize key combo for MQ2 /bind: "Shift C" -> "shift+c". MQ2 expects modifier+key with +; modifiers lowercase.
local function normalizeBindKey(input)
    if not input or type(input) ~= "string" then return "" end
    local s = input:match("^%s*(.-)%s*$")
    if s == "" then return "" end
    -- Split on spaces, +, or - to get parts
    local parts = {}
    for part in s:gmatch("[^%s+%-]+") do
        local lower = part:lower()
        if lower == "shift" or lower == "ctrl" or lower == "control" or lower == "alt" then
            parts[#parts + 1] = (lower == "control") and "ctrl" or lower
        else
            parts[#parts + 1] = part  -- preserve case for letter keys (I vs i)
        end
    end
    if #parts == 0 then return "" end
    -- Single key: return as-is (trimmed). Multi-part: join with + (modifier+key).
    return table.concat(parts, "+")
end

local ITEMUI_BIND_NAME = "itemui_inv"

--- Ensure ItemUI toggle bind exists and runs /inv. Creates the bind name with /custombind add if needed
--- (so it works even when MQ2CustomBinds.txt is missing), then sets the command. Uses /squelch to suppress echo.
--- The bind command is wrapped in "/timed 1": MQ2CustomBinds executes its command
--- directly on the keyboard-input path, and at least one MQ build in the field
--- (the stock E3 bundle's MQ 3.1.4.9) crashes in mq2lua when a Lua-bound command
--- is invoked from that context (mq2lua.DLL+1C87 on Shift+Q). /timed re-queues
--- the command onto the normal pulse path — one decisecond later, same effect,
--- crash path avoided — and is harmless on MQ builds that never had the problem.
local function ensureItemUIBindExists()
    pcall(function()
        mq.cmd("/squelch /custombind add " .. ITEMUI_BIND_NAME)  -- no-op if name already exists from MQ2CustomBinds.txt
        mq.cmd("/squelch /custombind set " .. ITEMUI_BIND_NAME .. "-down /timed 1 /inv")
    end)
end

--- Apply ItemUI toggle keybind from layoutConfig (uses /custombind + /bind). Call on startup and when user changes key in Settings.
--- Uses /squelch to suppress bind echo.
function LayoutUtils.applyItemUIToggleBind()
    local layoutConfig = LayoutUtils.layoutConfig
    if not layoutConfig then return end
    local rawKey = (layoutConfig.ItemUIToggleKey and type(layoutConfig.ItemUIToggleKey) == "string") and layoutConfig.ItemUIToggleKey:match("^%s*(.-)%s*$") or ""
    ensureItemUIBindExists()
    if rawKey == "" then
        pcall(function() mq.cmd("/squelch /bind " .. ITEMUI_BIND_NAME .. " clear") end)
    else
        local key = normalizeBindKey(rawKey)
        if key ~= "" then
            pcall(function() mq.cmd("/squelch /bind " .. ITEMUI_BIND_NAME .. " " .. key) end)
        end
    end
end

--- Return current ItemUI toggle key for display (e.g. startup message). Does not apply bind.
function LayoutUtils.getItemUIToggleKeyDisplay()
    local layoutConfig = LayoutUtils.layoutConfig
    if not layoutConfig then return "shift+q" end
    local rawKey = (layoutConfig.ItemUIToggleKey and type(layoutConfig.ItemUIToggleKey) == "string") and layoutConfig.ItemUIToggleKey:match("^%s*(.-)%s*$") or ""
    if rawKey == "" then return nil end
    local key = normalizeBindKey(rawKey)
    return (key ~= "") and key or nil
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
