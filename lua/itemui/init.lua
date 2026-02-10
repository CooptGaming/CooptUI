--[[
    CoopUI - ItemUI
    Purpose: Unified Inventory / Bank / Sell / Loot Interface
    Part of CoopUI — EverQuest EMU Companion
    Author: Perky's Crew
    Version: see coopui.version (ITEMUI)
    Dependencies: mq2lua, ImGui

    - Inventory: one area that switches view by context:
      * Loot window open: live loot view (corpse items with Will Loot / Will Skip; same filters as loot.mac).
      * Merchant open: sell view (Status, Keep/Junk buttons, Value, Stack, Type, Show only sellable, Auto Sell).
      * No merchant/loot: gameplay view (bag, slot, weight, flags); Shift+click to move when bank open.
    - Bank: slide-out panel (Bank button on right). When bank window open = "Online" + live list;
      when closed = "Offline" + last saved snapshot. Bank adds width to the base inventory size.
    - Layout setup: /itemui setup or click Setup. Resize the window for Inventory, Sell, and Inv+Bank
      then click the matching Save button. Sizes are stored in Macros/sell_config/itemui_layout.ini.
      Column widths are saved automatically when you resize them.
    Uses Macros/sell_config/ for keep/junk/sell config lists.

    Usage: /lua run itemui
    Toggle: /itemui   Setup: /itemui setup

    NOTE: Lua has a 200 local variable limit per scope. To avoid hitting this limit,
    related state is consolidated into tables (filterState, sortState). When adding
    new state variables, consider adding them to an existing table or creating a
    new consolidated table rather than adding new top-level locals.
--]]

local mq = require('mq')
require('ImGui')
local CoopVersion = require('coopui.version')
local config = require('itemui.config')
local config_cache = require('itemui.config_cache')
local context = require('itemui.context')
local rules = require('itemui.rules')
local storage = require('itemui.storage')
-- Phase 2: Core infrastructure (cache.lua used for spell caches; state/events partially integrated)
local Cache = require('itemui.core.cache')
local events = require('itemui.core.events')

-- Components
local CharacterStats = require('itemui.components.character_stats')

-- Phase 3: Filter system modules
local filterService = require('itemui.services.filter_service')
local searchbar = require('itemui.components.searchbar')
local filtersComponent = require('itemui.components.filters')

-- Phase 5: Macro integration service
local macroBridge = require('itemui.services.macro_bridge')
local scanService = require('itemui.services.scan')
local sellStatusService = require('itemui.services.sell_status')
local itemOps = require('itemui.services.item_ops')

-- Phase 5: View modules
local InventoryView = require('itemui.views.inventory')
local SellView = require('itemui.views.sell')
local BankView = require('itemui.views.bank')
local LootView = require('itemui.views.loot')
local ConfigView = require('itemui.views.config')
local AugmentsView = require('itemui.views.augments')

-- Phase 7: Utility modules
local layoutUtils = require('itemui.utils.layout')
local theme = require('itemui.utils.theme')
local columns = require('itemui.utils.columns')
local columnConfig = require('itemui.utils.column_config')
local sortUtils = require('itemui.utils.sort')
local windowState = require('itemui.utils.window_state')
local itemHelpers = require('itemui.utils.item_helpers')
local icons = require('itemui.utils.icons')

-- Constants (consolidated for Lua 200-local limit)
local C = {
    VERSION = CoopVersion.ITEMUI,
    MAX_BANK_SLOTS = 24,
    MAX_INVENTORY_BAGS = 10,
    LAYOUT_INI = "itemui_layout.ini",
    PROFILE_ENABLED = true,   -- Set false to disable performance logging
    PROFILE_THRESHOLD_MS = 30,  -- Only log when operation exceeds this (ms)
    UPVALUE_DEBUG = false,  -- Set true to log upvalue counts on startup
    LAYOUT_SECTION = "Layout",
    STATUS_MSG_SECS = 4,
    STATUS_MSG_MAX_LEN = 72,
    PERSIST_SAVE_INTERVAL_MS = 60000,
    FOOTER_HEIGHT = 52,
    TIMER_READY_CACHE_TTL_MS = 1500,
    LAYOUT_SAVE_DEBOUNCE_MS = 600,
    LOOT_PENDING_SCAN_DELAY_MS = 2500,   -- Delay before background scan after loot macro finish
    SELL_FAILED_DISPLAY_MS = 15000,      -- How long to show failed-items notice after sell macro
    STORED_INV_CACHE_TTL_MS = 2000,      -- TTL for storedInvByName cache (getSellStatusForItem / computeAndAttachSellStatus)
    LOOP_DELAY_VISIBLE_MS = 33,          -- Main loop delay when UI visible (~30 FPS)
    LOOP_DELAY_HIDDEN_MS = 100,           -- Main loop delay when UI hidden
}

-- State
local isOpen, shouldDraw, terminate = true, false, false
local inventoryItems, bankItems, lootItems = {}, {}, {}
local transferStampPath, lastTransferStamp = nil, 0
local lastInventoryWindowState, lastBankWindowState, lastMerchantState, lastLootWindowState = false, false, false, false
-- Stats tab priming: only on first inventory open after ItemUI start, so AC/ATK/Weight load once
local statsTabPrimeState, statsTabPrimeAt = nil, 0
local statsTabPrimedThisSession = false  -- true after we've done the one-time Stats tab prime
local STATS_TAB_PRIME_MS = 250  -- time to leave Stats tab visible so game populates values
-- Sort/layout caches (consolidated for Lua 200-local limit)
local perfCache = {
    inv = { key = "", dir = 0, filter = "", n = 0, scanTime = 0, sorted = {} },
    sell = { key = "", dir = 0, filter = "", showOnly = false, n = 0, nFiltered = 0, sorted = {} },
    bank = { key = "", dir = 0, filter = "", n = 0, nFiltered = 0, sorted = {} },
    loot = { key = "", dir = 0, filter = "", n = 0, sorted = {} },
    layoutCached = nil,
    layoutNeedsReload = true,
    layoutDirty = false,
    layoutSaveScheduledAt = 0,
    layoutSaveDebounceMs = C.LAYOUT_SAVE_DEBOUNCE_MS,
    timerReadyCache = {},  -- key "bag_slot" -> { ready = seconds, at = mq.gettime() }
    lastScanTimeInv = 0,
    lastBankCacheTime = 0,
    sellLogPath = nil,  -- Macros/logs/item_management (set in main)
    sellConfigPendingRefresh = false,  -- debounce: run at most one row refresh per frame after CONFIG_SELL_CHANGED
}
-- Invalidate stored-inv cache when we save so inventory Status column stays in sync with sell view
do
    local _saveInv = storage.saveInventory
    storage.saveInventory = function(items) _saveInv(items); perfCache.storedInvByName = nil end
end

-- Forward declaration: defined after willItemBeSold (used by scanInventory and save paths)
local computeAndAttachSellStatus
-- UI state (consolidated for Lua 200-local limit)
local uiState = {
    windowPositioned = false,
    alignToContext = false,
    alignToMerchant = false,  -- NEW: Align to merchant window when in sell view
    uiLocked = true,
    syncBankWindow = true,
    suppressWhenLootMac = true,
    itemUIPositionX = nil, itemUIPositionY = nil,
    sellViewLocked = true, invViewLocked = true, bankViewLocked = true,
    setupMode = false, setupStep = 0,
    configWindowOpen = false, configNeedsLoad = false, configAdvancedMode = false,
    searchFilterInv = "", searchFilterBank = "", searchFilterAugments = "",
    autoSellRequested = false, showOnlySellable = false,
    bankWindowOpen = false, bankWindowShouldDraw = false,
    augmentsWindowOpen = false, augmentsWindowShouldDraw = false,
    statusMessage = "", statusMessageTime = 0,
    quantityPickerValue = "", quantityPickerMax = 1,
    quantityPickerSubmitPending = nil,  -- qty to submit next frame (so Enter is consumed before we clear the field)
    pendingQuantityPickup = nil, pendingQuantityAction = nil,
    lastPickup = { bag = nil, slot = nil, source = nil },  -- source: "inv" | "bank"
}

-- Layout from setup (itemui_layout.ini): sizes per view; bank adds to base when open
local layoutDefaults = {
    WidthInventory = 600,
    Height = 450,
    WidthSell = 780,
    WidthLoot = 560,
    WidthBankPanel = 520,
    HeightBank = 600,
    BankWindowX = 0,
    BankWindowY = 0,
    WidthAugmentsPanel = 560,
    HeightAugments = 500,
    AugmentsWindowX = 0,
    AugmentsWindowY = 0,
    AlignToContext = 0,
    UILocked = 1,
    SyncBankWindow = 1,
    SuppressWhenLootMac = 1,  -- Don't auto-show ItemUI when inventory opens while loot.mac is running
}
local layoutConfig = {}  -- filled by loadLayoutConfig()

-- Column config: owned by itemui.utils.column_config (definitions, visibility, autofit widths)
local availableColumns = columnConfig.availableColumns
local columnVisibility = columnConfig.columnVisibility
local columnAutofitWidths = columnConfig.columnAutofitWidths
local function initColumnVisibility() columnConfig.initColumnVisibility() end

-- Config cache: owned by itemui.config_cache; init and aliases set after sell logic
local configCache, configSellFlags, configSellValues, configSellLists, configLootFlags, configLootValues, configLootSorting, configLootLists, configEpicClasses
local loadConfigCache, addToKeepList, removeFromKeepList, addToJunkList, removeFromJunkList
local isInLootSkipList, addToLootSkipList, removeFromLootSkipList
local augmentListAPI
-- Consolidated filter/config state (reduces local var count for Lua 200-limit; must be before loadLayoutConfig)
local filterState = {
    configTab = 1,
    filterSubTab = 1,
    configListInputs = {},
    configUnifiedMode = {},
    sellFilterTargetId = "keep",
    sellFilterTypeMode = 0,
    sellFilterInputValue = "",
    sellFilterEditTarget = nil,
    sellFilterListShow = "all",
    lootFilterTargetId = "always",
    lootFilterTypeMode = 0,
    lootFilterInputValue = "",
    lootFilterEditTarget = nil,
    lootFilterListShow = "all",
    valuableFilterTypeMode = 0,
    valuableFilterInputValue = "",
    valuableFilterEditTarget = nil,
    sellFilterSortColumn = 2,
    sellFilterSortDirection = ImGuiSortDirection.Ascending,
    valuableFilterSortColumn = 1,
    valuableFilterSortDirection = ImGuiSortDirection.Ascending,
    lootFilterSortColumn = 2,
    lootFilterSortDirection = ImGuiSortDirection.Ascending,
}
-- Sort state (must be before loadLayoutConfig which loads InvSortColumn/InvSortDirection)
local sortState = {
    sellColumn = "Name",
    sellDirection = ImGuiSortDirection.Ascending,
    invColumn = "Name",
    invDirection = ImGuiSortDirection.Ascending,
    invColumnOrder = nil,  -- Will be set from saved layout or auto-generated on first use
    bankColumn = "Name",
    bankDirection = ImGuiSortDirection.Ascending,
    bankColumnOrder = nil,  -- Will be set from saved layout or auto-generated on first use
}

-- Phase 7: Initialize layout utility module
layoutUtils.init({
    layoutDefaults = layoutDefaults,
    layoutConfig = layoutConfig,
    uiState = uiState,
    sortState = sortState,
    filterState = filterState,
    columnVisibility = columnVisibility,
    perfCache = perfCache,
    C = C,
    initColumnVisibility = initColumnVisibility,
    availableColumns = availableColumns
})
local sellItems = {}  -- inventory + sell status when merchant open
local sellMacState = { lastRunning = false, failedItems = {}, failedCount = 0, showFailedUntil = 0, smoothedFrac = 0 }
local lootMacState = { lastRunning = false, pendingScan = false, finishedAt = 0 }  -- detect loot macro finish for background inventory scan
local bankCache = {}
-- Scan state (shared with itemui.services.scan): one table to stay under local/upvalue limits
local scanState = {
    lastScanTimeBank = 0,
    lastPersistSaveTime = 0,
    lastInventoryFingerprint = "",
    lastScanState = { invOpen = false, bankOpen = false, merchOpen = false, lootOpen = false },
    lastBagFingerprints = {},
}
-- Deferred scan flags - for instant UI open (load snapshot first, scan after UI shown)
local deferredScanNeeded = { inventory = false, bank = false, sell = false }

-- Item helpers: init and local aliases (delegated to utils/item_helpers.lua)
perfCache.sellConfigCache = nil
itemHelpers.init({ C = C, uiState = uiState, perfCache = perfCache })
local function setStatusMessage(msg) itemHelpers.setStatusMessage(msg) end
local function getItemSpellId(item, prop) return itemHelpers.getItemSpellId(item, prop) end
local function getSpellName(id) return itemHelpers.getSpellName(id) end

-- Sell status service: init and local aliases (delegated to services/sell_status.lua)
sellStatusService.init({ perfCache = perfCache, rules = rules, storage = storage, C = C })
local function loadSellConfigCache() sellStatusService.loadSellConfigCache() end

-- ============================================================================
-- Layout Management (Phase 7: Delegated to utils/layout.lua)
-- ============================================================================
local function saveLayoutToFileImmediate() layoutUtils.saveLayoutToFileImmediate() end
local function flushLayoutSave() layoutUtils.flushLayoutSave() end
local function saveLayoutToFile() layoutUtils.saveLayoutToFile() end
local function loadLayoutConfig() layoutUtils.loadLayoutConfig() end
local function saveLayoutForView(view, w, h, bankPanelW) layoutUtils.saveLayoutForView(view, w, h, bankPanelW) end

local function invalidateSortCache(view)
    local c = view == "inv" and perfCache.inv or view == "sell" and perfCache.sell or view == "bank" and perfCache.bank or view == "loot" and perfCache.loot
    if c then c.key = nil end
    if view == "inv" then perfCache.invTotalSlots = nil; perfCache.invTotalValue = nil end
end

-- Window state queries (delegated to utils/window_state.lua)
local function isBankWindowOpen() return windowState.isBankWindowOpen() end
local function isMerchantWindowOpen() return windowState.isMerchantWindowOpen() end
local function isLootWindowOpen() return windowState.isLootWindowOpen() end
local function closeGameInventoryIfOpen() windowState.closeGameInventoryIfOpen() end

-- buildItemFromMQ delegated to utils/item_helpers.lua
local function buildItemFromMQ(item, bag, slot) return itemHelpers.buildItemFromMQ(item, bag, slot) end

-- Sell logic aliases (delegated to services/sell_status.lua)
local function isInKeepList(itemName) return sellStatusService.isInKeepList(itemName) end
local function isInJunkList(itemName) return sellStatusService.isInJunkList(itemName) end
local function isProtectedType(itemType) return sellStatusService.isProtectedType(itemType) end
local function isKeptByContains(itemName) return sellStatusService.isKeptByContains(itemName) end
local function isKeptByType(itemType) return sellStatusService.isKeptByType(itemType) end
local function willItemBeSold(itemData) return sellStatusService.willItemBeSold(itemData) end
computeAndAttachSellStatus = function(items) sellStatusService.computeAndAttachSellStatus(items) end
local function getSellStatusForItem(item) return sellStatusService.getSellStatusForItem(item) end

-- Config cache init (requires isInKeepList, isInJunkList above)
config_cache.init({
    setStatusMessage = setStatusMessage,
    isInKeepList = isInKeepList,
    isInJunkList = isInJunkList,
})
configCache = config_cache.getCache()
configSellFlags, configSellValues, configSellLists = configCache.sell.flags, configCache.sell.values, configCache.sell.lists
configLootFlags, configLootValues, configLootSorting, configLootLists = configCache.loot.flags, configCache.loot.values, configCache.loot.sorting, configCache.loot.lists
configEpicClasses = configCache.epicClasses
loadConfigCache = function() config_cache.loadConfigCache() end
addToKeepList = config_cache.addToKeepList
removeFromKeepList = config_cache.removeFromKeepList
addToJunkList = config_cache.addToJunkList
removeFromJunkList = config_cache.removeFromJunkList
isInLootSkipList = config_cache.isInLootSkipList
addToLootSkipList = config_cache.addToLootSkipList
removeFromLootSkipList = config_cache.removeFromLootSkipList
augmentListAPI = config_cache.createAugmentListAPI()
loadConfigCache()  -- Populate cache at startup (views/registry use configSellFlags, configLootLists, etc.)

-- Schedule one sell-status refresh next frame (debounced). When invalidateNow is true, clear sell cache so same-frame updateSellStatusForItemName sees fresh data (e.g. augment never-loot list).
local function scheduleSellStatusRefresh(invalidateNow)
    perfCache.sellConfigPendingRefresh = true
    if invalidateNow then
        sellStatusService.invalidateSellConfigCache()  -- sell cache includes augment never-loot and other loot-derived lists for Status column
    end
end
-- When sell config changes: don't invalidate here so same-frame Junk list write is visible when debounced refresh runs; Augment Always sell Status may update next frame.
events.on(events.EVENTS.CONFIG_SELL_CHANGED, function() scheduleSellStatusRefresh(false) end)
-- When loot config changes (e.g. Augment Never loot), schedule refresh and invalidate now so same-frame context-menu update shows correct Status.
events.on(events.EVENTS.CONFIG_LOOT_CHANGED, function() scheduleSellStatusRefresh(true) end)

-- Scan service: init and wrappers (scan logic lives in itemui.services.scan)
do
    local scanEnv = {
        inventoryItems = inventoryItems,
        bankItems = bankItems,
        bankCache = bankCache,
        sellItems = sellItems,
        lootItems = lootItems,
        perfCache = perfCache,
        scanState = scanState,
        C = C,
        buildItemFromMQ = buildItemFromMQ,
        getWornSlotsStringFromTLO = function(it) return itemHelpers.getWornSlotsStringFromTLO(it) end,
        getAugSlotsCountFromTLO = function(it) return itemHelpers.getAugSlotsCountFromTLO(it) end,
        invalidateSortCache = invalidateSortCache,
        invalidateTimerReadyCache = function() perfCache.timerReadyCache = {} end,
        computeAndAttachSellStatus = computeAndAttachSellStatus,
        isBankWindowOpen = isBankWindowOpen,
        storage = storage,
        loadSellConfigCache = loadSellConfigCache,
        isInKeepList = isInKeepList,
        isKeptByContains = isKeptByContains,
        isKeptByType = isKeptByType,
        isInJunkList = isInJunkList,
        isInJunkContainsList = function(n) return sellStatusService.isInJunkContainsList(n) end,
        isProtectedType = isProtectedType,
        willItemBeSold = willItemBeSold,
        attachGranularFlags = function(item, storedByName) sellStatusService.attachGranularFlags(item, storedByName) end,
        rules = rules,
        getStoredInvByName = function() return sellStatusService.refreshStoredInvByName() end,
    }
    scanService.init(scanEnv)
end
local function scanInventory() scanService.scanInventory() end
local function scanBank() scanService.scanBank() end
local function scanSellItems() scanService.scanSellItems() end
local function scanLootItems() scanService.scanLootItems() end
local function maybeScanInventory(invOpen) scanService.maybeScanInventory(invOpen) end
local function maybeScanBank(bankOpen) scanService.maybeScanBank(bankOpen) end
local function maybeScanSellItems(merchOpen) scanService.maybeScanSellItems(merchOpen) end
local function maybeScanLootItems(lootOpen) scanService.maybeScanLootItems(lootOpen) end

-- Item operations: init and local aliases (delegated to services/item_ops.lua)
itemOps.init({
    inventoryItems = inventoryItems, bankItems = bankItems, sellItems = sellItems, lootItems = lootItems, bankCache = bankCache,
    perfCache = perfCache, uiState = uiState, scanState = scanState,
    sellStatus = sellStatusService, isBankWindowOpen = isBankWindowOpen, isMerchantWindowOpen = isMerchantWindowOpen,
    invalidateSortCache = invalidateSortCache, setStatusMessage = setStatusMessage, storage = storage,
    getItemSpellId = getItemSpellId,
    scanBank = function() scanService.scanBank() end,
})
local function processSellQueue() itemOps.processSellQueue() end
local function hasItemOnCursor() return itemOps.hasItemOnCursor() end
local function removeItemFromCursor() return itemOps.removeItemFromCursor() end

-- Single path for sell list changes: update INI, rows, and stored inventory so all views stay in sync
local function applySellListChange(itemName, inKeep, inJunk)
    if inKeep then addToKeepList(itemName) else removeFromKeepList(itemName) end
    if inJunk then addToJunkList(itemName) else removeFromJunkList(itemName) end
    itemOps.updateSellStatusForItemName(itemName, inKeep, inJunk)
    if storage and inventoryItems then storage.saveInventory(inventoryItems) end
end

-- ============================================================================
-- Tab renderers (condensed; full item table behavior)
-- ============================================================================
local TABLE_FLAGS = bit32.bor(ImGuiTableFlags.ScrollY, ImGuiTableFlags.RowBg, ImGuiTableFlags.BordersOuter, ImGuiTableFlags.BordersV, ImGuiTableFlags.SizingStretchProp, ImGuiTableFlags.Resizable, ImGuiTableFlags.Reorderable, ImGuiTableFlags.Sortable, (ImGuiTableFlags.SaveSettings or 0))
uiState.tableFlags = TABLE_FLAGS

-- Column/sort helpers are provided by utils modules.
columns.init({availableColumns=availableColumns, columnVisibility=columnVisibility, columnAutofitWidths=columnAutofitWidths, setStatusMessage=setStatusMessage, getItemSpellId=getItemSpellId, getSpellName=getSpellName})
-- getStatusForSort used for Inventory Status column alphabetical sort (must match displayed text, e.g. Epic -> EpicQuest)
local function getStatusForSort(item)
    if item and item.sellReason ~= nil then
        local st = (item.sellReason and item.sellReason ~= "") and item.sellReason or "—"
        if st == "Epic" then return "EpicQuest" end
        return st
    end
    if not getSellStatusForItem then return "" end
    local st, _ = getSellStatusForItem(item)
    if st == "Epic" then return "EpicQuest" end
    return (st and st ~= "") and st or "—"
end
sortUtils.init({getItemSpellId=getItemSpellId, getSpellName=getSpellName, getStatusForSort=getStatusForSort})

local function closeItemUI()
    shouldDraw = false
    isOpen = false
    uiState.configWindowOpen = false
end

-- Character Stats Panel (delegated to components/character_stats.lua)
CharacterStats.init({ FOOTER_HEIGHT = C.FOOTER_HEIGHT, inventoryItems = inventoryItems })

-- Phase 5: Context builder for view modules (itemui.context: single refs table, build has one upvalue)
local windowStateAPI = {
    isBankWindowOpen = isBankWindowOpen,
    isMerchantWindowOpen = isMerchantWindowOpen,
    isLootWindowOpen = isLootWindowOpen,
}
local sortColumnsAPI = {
    removeLootItemBySlot = removeLootItemBySlot,
    getSortValByKey = sortUtils.getSortValByKey,
    getSellSortVal = sortUtils.getSellSortVal,
    getBankSortVal = sortUtils.getBankSortVal,
    makeComparator = sortUtils.makeComparator,
    precomputeKeys = sortUtils.precomputeKeys,
    undecorate = sortUtils.undecorate,
    getCellDisplayText = columns.getCellDisplayText,
    isNumericColumn = columns.isNumericColumn,
    getVisibleColumns = columns.getVisibleColumns,
}

context.init({
    -- State tables
    uiState = uiState, sortState = sortState, filterState = filterState,
    layoutConfig = layoutConfig, perfCache = perfCache, sellMacState = sellMacState,
    -- Data tables
    inventoryItems = inventoryItems, bankItems = bankItems, lootItems = lootItems,
    sellItems = sellItems, bankCache = bankCache,
    -- Config
    configLootLists = configLootLists, config = config,
    columnAutofitWidths = columnAutofitWidths, availableColumns = availableColumns,
    columnVisibility = columnVisibility,
    configSellFlags = configSellFlags, configSellValues = configSellValues, configSellLists = configSellLists,
    configLootFlags = configLootFlags, configLootValues = configLootValues,
    configLootSorting = configLootSorting, configEpicClasses = configEpicClasses,
    EPIC_CLASSES = rules.EPIC_CLASSES,
    -- Window state
    windowState = windowStateAPI,
    -- Scan functions
    scanInventory = scanInventory, scanBank = scanBank,
    scanSellItems = scanSellItems, scanLootItems = scanLootItems,
    maybeScanInventory = maybeScanInventory, maybeScanSellItems = maybeScanSellItems,
    maybeScanLootItems = maybeScanLootItems,
    ensureBankCacheFromStorage = function() scanService.ensureBankCacheFromStorage() end,
    -- Config cache (event-driven: views emit events, sell_status subscribes)
    invalidateLootConfigCache = function() sellStatusService.invalidateLootConfigCache() end,
    invalidateSellConfigCache = function() sellStatusService.invalidateSellConfigCache() end,
    loadConfigCache = loadConfigCache,
    -- UI helpers
    setStatusMessage = setStatusMessage, closeItemUI = closeItemUI,
    -- Layout (module direct)
    saveLayoutToFile = function() layoutUtils.saveLayoutToFile() end,
    scheduleLayoutSave = function() layoutUtils.scheduleLayoutSave() end, flushLayoutSave = flushLayoutSave,
    saveColumnVisibility = function() layoutUtils.saveColumnVisibility() end,
    loadLayoutConfig = loadLayoutConfig,
    captureCurrentLayoutAsDefault = function() layoutUtils.captureCurrentLayoutAsDefault() end,
    resetLayoutToDefault = function() layoutUtils.resetLayoutToDefault() end,
    getFixedColumns = function(v) return layoutUtils.getFixedColumns(v) end,
    toggleFixedColumn = function(v, k) return layoutUtils.toggleFixedColumn(v, k) end,
    isColumnInFixedSet = function(v, k) return layoutUtils.isColumnInFixedSet(v, k) end,
    -- Item ops (module direct)
    hasItemOnCursor = function() return itemOps.hasItemOnCursor() end,
    removeItemFromCursor = function() return itemOps.removeItemFromCursor() end,
    moveBankToInv = function(b, s) return itemOps.moveBankToInv(b, s) end,
    moveInvToBank = function(b, s) return itemOps.moveInvToBank(b, s) end,
    queueItemForSelling = function(d) return itemOps.queueItemForSelling(d) end,
    updateSellStatusForItemName = function(n, k, j) itemOps.updateSellStatusForItemName(n, k, j) end,
    applySellListChange = applySellListChange,
    -- Config list APIs
    addToKeepList = addToKeepList, removeFromKeepList = removeFromKeepList,
    addToJunkList = addToJunkList, removeFromJunkList = removeFromJunkList,
    augmentLists = augmentListAPI,
    addToLootSkipList = addToLootSkipList, removeFromLootSkipList = removeFromLootSkipList,
    isInLootSkipList = isInLootSkipList,
    -- Sort/columns
    sortColumns = sortColumnsAPI,
    getColumnKeyByIndex = columns.getColumnKeyByIndex, autofitColumns = columns.autofitColumns,
    -- Item helpers (module direct)
    getSpellName = function(id) return itemHelpers.getSpellName(id) end,
    getSpellDescription = function(id) return itemHelpers.getSpellDescription(id) end,
    getItemSpellId = function(i, p) return itemHelpers.getItemSpellId(i, p) end,
    getTimerReady = function(b, s) return itemHelpers.getTimerReady(b, s) end,
    getItemStatsSummary = function(i) return itemHelpers.getItemStatsSummary(i) end,
    getSellStatusForItem = function(i) return sellStatusService.getSellStatusForItem(i) end,
    drawItemIcon = function(id) icons.drawItemIcon(id) end,
    -- Services
    theme = theme, macroBridge = macroBridge,
})
local function buildViewContext() return context.build() end
local function extendContext(ctx) return context.extend(ctx) end
context.logUpvalueCounts(C)

local function renderInventoryContent()
    local merchOpen = isMerchantWindowOpen()
    local bankOpen = isBankWindowOpen()
    local lootOpen = isLootWindowOpen()
    -- Allow simulated sell view during setup mode step 2
    local simulateSellView = (uiState.setupMode and uiState.setupStep == 2)

    -- Loot view disabled: loot macro uses default EQ loot UI. To re-enable, change to: if lootOpen then
    if false then
        local ctx = extendContext(buildViewContext())
        LootView.render(ctx)
        return
    end

    if merchOpen or simulateSellView then
        -- Phase 5: Use SellView module
        local ctx = extendContext(buildViewContext())
        SellView.render(ctx, simulateSellView)
    else
        -- Phase 5: Use InventoryView module
        local ctx = extendContext(buildViewContext())
        InventoryView.render(ctx, bankOpen)
    end
end

--- Bank window: separate window showing live data when connected, historic cache when not.
local BANK_WINDOW_WIDTH = 520
local BANK_WINDOW_HEIGHT = 600

-- Render bank window (separate from main UI)
local function renderBankWindow()
    local ctx = extendContext(buildViewContext())
    BankView.render(ctx)
end

--- Augments window: pop-out like Bank (Always sell / Never loot, compact table, icon+stats on hover)
local function renderAugmentsWindow()
    local ctx = extendContext(buildViewContext())
    AugmentsView.render(ctx)
end

-- ============================================================================
-- Main render
-- ============================================================================
local function renderUI()
    if not shouldDraw then return end
    local merchOpen = isMerchantWindowOpen()
    -- In setup step 1–2 show inventory/sell only; step 3 show inv+bank
    local curView
    if uiState.setupMode and uiState.setupStep == 1 then
        curView = "Inventory"
    elseif uiState.setupMode and uiState.setupStep == 2 then
        curView = "Sell"  -- Always show sell view in step 2 (simulated if no merchant)
    elseif uiState.setupMode and uiState.setupStep == 3 then
        curView = "Inventory"  -- Bank is now separate window, so setup step 3 is just for inventory
    else
        -- Loot view disabled: show Inventory or Sell only (loot macro uses default EQ loot UI; ItemUI stays out of the way)
        curView = (merchOpen and "Sell") or "Inventory"
    end

    -- Window size: setup = free resize; else use saved sizes or align-to-context
    if not uiState.setupMode then
        local w, h = nil, nil
        if curView == "Inventory" then w, h = layoutConfig.WidthInventory, layoutConfig.Height
        elseif curView == "Sell" then w, h = layoutConfig.WidthSell, layoutConfig.Height
        elseif curView == "Loot" then w, h = layoutConfig.WidthLoot or layoutDefaults.WidthLoot, layoutConfig.Height
        end
        if w and h and w > 0 and h > 0 then
            if uiState.uiLocked then
                ImGui.SetNextWindowSize(ImVec2(w, h), ImGuiCond.Always)
            else
                ImGui.SetNextWindowSize(ImVec2(w, h), ImGuiCond.FirstUseEver)
            end
        end
        if uiState.alignToContext then
            local invWnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("InventoryWindow")
            if invWnd and invWnd.Open and invWnd.Open() then
                local x, y = tonumber(invWnd.X and invWnd.X()) or 0, tonumber(invWnd.Y and invWnd.Y()) or 0
                local pw = tonumber(invWnd.Width and invWnd.Width()) or 0
                if x and y and pw > 0 then 
                    local itemUIX = x + pw + 10
                    ImGui.SetNextWindowPos(ImVec2(itemUIX, y), ImGuiCond.Always)
                    -- Store ItemUI position for bank window syncing
                    uiState.itemUIPositionX = itemUIX
                    uiState.itemUIPositionY = y
                end
            end
        end
    end
    
    -- Set window flags based on lock state
    local windowFlags = 0
    if uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end
    
    local winOpen, winVis = ImGui.Begin("Item UI##ItemUI", isOpen, windowFlags)
    isOpen = winOpen
    if not winOpen then
        shouldDraw = false
        uiState.configWindowOpen = false
        closeGameInventoryIfOpen()
        ImGui.End()
        return
    end
    -- Layered Esc: close topmost overlay first, then main UI
    if ImGui.IsKeyPressed(ImGuiKey.Escape) then
        if uiState.pendingQuantityPickup then
            uiState.pendingQuantityPickup = nil
            uiState.quantityPickerValue = ""
        elseif uiState.configWindowOpen then
            uiState.configWindowOpen = false
        elseif uiState.bankWindowOpen and uiState.bankWindowShouldDraw then
            uiState.bankWindowOpen = false
            uiState.bankWindowShouldDraw = false
        elseif uiState.augmentsWindowOpen and uiState.augmentsWindowShouldDraw then
            uiState.augmentsWindowOpen = false
            uiState.augmentsWindowShouldDraw = false
        else
            ImGui.SetKeyboardFocusHere(-1)  -- release keyboard focus so game gets input after close
            shouldDraw = false
            isOpen = false
            uiState.configWindowOpen = false
            closeGameInventoryIfOpen()
            ImGui.End()
            return
        end
    end
    if not winVis then ImGui.End(); return end

    -- Track ItemUI window position and size (for bank sync and EQ item-display grid)
    if not uiState.alignToContext then
        -- Get actual ItemUI position (when not snapping)
        uiState.itemUIPositionX, uiState.itemUIPositionY = ImGui.GetWindowPos()
    end
    local itemUIWidth = ImGui.GetWindowWidth()

    -- If bank window sync is enabled and bank window is open, update its position
    if uiState.syncBankWindow and uiState.bankWindowOpen and uiState.bankWindowShouldDraw and uiState.itemUIPositionX and uiState.itemUIPositionY and itemUIWidth then
        -- Calculate bank window position relative to ItemUI
        local bankX = uiState.itemUIPositionX + itemUIWidth + 10
        local bankY = uiState.itemUIPositionY
        -- Update saved position (will be used in renderBankWindow)
        layoutConfig.BankWindowX = bankX
        layoutConfig.BankWindowY = bankY
    end

    -- Header: Lock/Unlock (top left), Refresh, Settings
    local prevLocked = uiState.uiLocked
    uiState.uiLocked = ImGui.Checkbox("##Lock", uiState.uiLocked)
    if prevLocked ~= uiState.uiLocked then 
        saveLayoutToFile()
        -- Save current window size when locking
        if uiState.uiLocked then
            local w, h = ImGui.GetWindowSize()
            if curView == "Inventory" then layoutConfig.WidthInventory = w; layoutConfig.Height = h
            elseif curView == "Sell" then layoutConfig.WidthSell = w; layoutConfig.Height = h
            elseif curView == "Loot" then layoutConfig.WidthLoot = w; layoutConfig.Height = h
            end
            saveLayoutToFile()
        end
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(uiState.uiLocked and "UI Locked - Click to unlock and allow resizing" or "UI Unlocked - Click to lock and prevent resizing"); ImGui.EndTooltip() end
    ImGui.SameLine()
    if ImGui.Button("Refresh##Header", ImVec2(80,0)) then
        scanInventory()
        if isBankWindowOpen() then scanBank() end
        if isMerchantWindowOpen() then scanSellItems() end
        if isLootWindowOpen() then scanLootItems() end
        setStatusMessage("Refreshed")
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Rescan inventory, bank (if open), and sell list"); ImGui.EndTooltip() end
    ImGui.SameLine()
    if ImGui.Button("Settings", ImVec2(70, 0)) then uiState.configWindowOpen = true; uiState.configNeedsLoad = true end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Open ItemUI & Loot settings"); ImGui.EndTooltip() end
    ImGui.SameLine()
    if ImGui.Button("Augments", ImVec2(75, 0)) then
        uiState.augmentsWindowOpen = not uiState.augmentsWindowOpen
        uiState.augmentsWindowShouldDraw = uiState.augmentsWindowOpen
        if uiState.augmentsWindowOpen then setStatusMessage("Augments window opened") end
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Open Augmentations window (Always sell / Never loot, stats on hover)"); ImGui.EndTooltip() end
    ImGui.SameLine(ImGui.GetWindowWidth() - 68)
    local bankOnline = isBankWindowOpen()
    if bankOnline then
        ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.2, 0.65, 0.2, 1))
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ImVec4(0.3, 0.75, 0.3, 1))
        ImGui.PushStyleColor(ImGuiCol.ButtonActive, ImVec4(0.15, 0.55, 0.15, 1))
    else
        ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.7, 0.2, 0.2, 1))
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ImVec4(0.8, 0.3, 0.3, 1))
        ImGui.PushStyleColor(ImGuiCol.ButtonActive, ImVec4(0.6, 0.15, 0.15, 1))
    end
    if ImGui.Button("Bank", ImVec2(60, 0)) then
        uiState.bankWindowOpen = not uiState.bankWindowOpen
        uiState.bankWindowShouldDraw = uiState.bankWindowOpen
        if uiState.bankWindowOpen and bankOnline then maybeScanBank(bankOnline) end
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(bankOnline and "Open or close the bank window. Bank is online." or "Open or close the bank window. Bank is offline."); ImGui.EndTooltip() end
    ImGui.PopStyleColor(3)
    ImGui.Separator()

    -- Setup walkthrough: Step 1 Inventory -> Step 2 Sell -> Step 3 Inv+Bank -> done
    if uiState.setupMode then
        if uiState.setupStep == 1 then
            ImGui.TextColored(ImVec4(0.95, 0.75, 0.2, 1), "Step 1 of 3: Inventory — Resize the window and columns as you like.")
            ImGui.SameLine()
            if ImGui.Button("Next", ImVec2(60, 0)) then
                local w, h = ImGui.GetWindowSize()
                if w and h and w > 0 and h > 0 then saveLayoutForView("Inventory", w, h, nil) end
                uiState.setupStep = 2
                print("\ag[ItemUI]\ax Saved Inventory layout. Step 2: Open a merchant, then resize and click Next.")
            end
        elseif uiState.setupStep == 2 then
            ImGui.TextColored(ImVec4(0.95, 0.75, 0.2, 1), "Step 2 of 3: Sell view — Resize the window and columns, then click Next.")
            if not merchOpen then
                ImGui.SameLine()
                ImGui.TextColored(ImVec4(0.6, 0.8, 0.6, 1), "(Simulated view - no merchant needed)")
            end
            -- Ensure sell items are populated for simulated view
            if #sellItems == 0 then
                local _w = mq.TLO and mq.TLO.Window and mq.TLO.Window("InventoryWindow")
                local invO, bankO, merchO = (_w and _w.Open and _w.Open()) or false, isBankWindowOpen(), isMerchantWindowOpen()
                maybeScanInventory(invO); maybeScanSellItems(merchO)
            end
            if ImGui.Button("Back", ImVec2(50, 0)) then uiState.setupStep = 1 end
            ImGui.SameLine()
            if ImGui.Button("Next", ImVec2(60, 0)) then
                local w, h = ImGui.GetWindowSize()
                if w and h and w > 0 and h > 0 then saveLayoutForView("Sell", w, h, nil) end
                uiState.setupStep = 3
                uiState.bankWindowOpen = true
                uiState.bankWindowShouldDraw = true
                print("\ag[ItemUI]\ax Saved Sell layout. Step 3: Open the bank window and resize it, then Save & finish.")
            end
        elseif uiState.setupStep == 3 then
            ImGui.TextColored(ImVec4(0.95, 0.75, 0.2, 1), "Step 3 of 3: Open and resize the Bank window, then save.")
            if ImGui.Button("Back", ImVec2(50, 0)) then uiState.setupStep = 2; uiState.bankWindowOpen = false; uiState.bankWindowShouldDraw = false end
            ImGui.SameLine()
            if ImGui.Button("Save & finish", ImVec2(100, 0)) then
                -- Bank window size is saved automatically when resized, so just finish setup
                uiState.setupMode = false
                uiState.setupStep = 0
                print("\ag[ItemUI]\ax Setup complete! Your layout is saved.")
            end
        end
        ImGui.Separator()
    end

    -- Content: Character stats panel (left) + inventory (dynamic sell/gameplay view) - bank is now separate window
    CharacterStats.render()
    ImGui.SameLine()
    
    -- Right side: Inventory content (bank is now separate window)
    ImGui.BeginChild("MainContent", ImVec2(0, -C.FOOTER_HEIGHT), true)
    renderInventoryContent()
    ImGui.EndChild()

    -- Quantity picker tool (shown when user clicks on stackable item)
    if uiState.pendingQuantityPickup then
        -- Process deferred submit from Enter key (next frame so ImGui consumes Enter before we clear the field)
        if uiState.quantityPickerSubmitPending ~= nil then
            local qty = uiState.quantityPickerSubmitPending
            uiState.quantityPickerSubmitPending = nil
            if qty and qty > 0 and qty <= uiState.pendingQuantityPickup.maxQty then
                uiState.pendingQuantityAction = {
                    action = "set",
                    qty = qty,
                    pickup = uiState.pendingQuantityPickup
                }
                uiState.pendingQuantityPickup = nil
                uiState.quantityPickerValue = ""
            else
                setStatusMessage(string.format("Invalid quantity (1-%d)", uiState.pendingQuantityPickup.maxQty))
            end
        else
            ImGui.Separator()
            ImGui.TextColored(ImVec4(0.9, 0.7, 0.2, 1), "Quantity Picker")
            ImGui.SameLine()
            ImGui.Text(string.format("(%s)", uiState.pendingQuantityPickup.itemName or "Item"))
            ImGui.Text(string.format("Max: %d", uiState.pendingQuantityPickup.maxQty))
            ImGui.SameLine()
            ImGui.Text("Quantity:")
            ImGui.SameLine()
            ImGui.SetNextItemWidth(100)
            local qtyFlags = bit32.bor(ImGuiInputTextFlags.CharsDecimal, ImGuiInputTextFlags.EnterReturnsTrue)
            local submitted
            uiState.quantityPickerValue, submitted = ImGui.InputText("##QuantityPicker", uiState.quantityPickerValue, qtyFlags)
            if submitted then
                -- Defer submit to next frame so Enter is consumed and focus doesn't leak to the game
                uiState.quantityPickerSubmitPending = tonumber(uiState.quantityPickerValue)
            end
            ImGui.SameLine()
            if ImGui.Button("Set", ImVec2(60, 0)) then
                local qty = tonumber(uiState.quantityPickerValue)
                if qty and qty > 0 and qty <= uiState.pendingQuantityPickup.maxQty then
                    uiState.pendingQuantityAction = {
                        action = "set",
                        qty = qty,
                        pickup = uiState.pendingQuantityPickup
                    }
                    uiState.pendingQuantityPickup = nil
                    uiState.quantityPickerValue = ""
                else
                    setStatusMessage(string.format("Invalid quantity (1-%d)", uiState.pendingQuantityPickup.maxQty))
                end
            end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Pick up this quantity"); ImGui.EndTooltip() end
        ImGui.SameLine()
        if ImGui.Button("Max", ImVec2(50, 0)) then
            uiState.pendingQuantityAction = {
                action = "max",
                qty = uiState.pendingQuantityPickup.maxQty,
                pickup = uiState.pendingQuantityPickup
            }
            uiState.pendingQuantityPickup = nil
            uiState.quantityPickerValue = ""
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Pick up maximum quantity"); ImGui.EndTooltip() end
        ImGui.SameLine()
        if ImGui.Button("Cancel", ImVec2(60, 0)) then
            uiState.pendingQuantityPickup = nil
            uiState.quantityPickerValue = ""
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Cancel quantity selection"); ImGui.EndTooltip() end
        end
    end

    if hasItemOnCursor() then
        ImGui.Separator()
        local cursor = mq.TLO and mq.TLO.Cursor
        local cn = (cursor and cursor.Name and cursor.Name()) or "Item"
        local st = (cursor and cursor.Stack and cursor.Stack()) or 0
        if st and st > 1 then cn = cn .. string.format(" (x%d)", st) end
        ImGui.TextColored(ImVec4(0.95,0.75,0.2,1), "Cursor: " .. cn)
        if ImGui.Button("Clear cursor", ImVec2(90,0)) then removeItemFromCursor() end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Put item back to last location or use /autoinv"); ImGui.EndTooltip() end
        ImGui.SameLine()
        ImGui.TextColored(ImVec4(0.55,0.55,0.55,1), "Right-click to put back")
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Right-click anywhere on this window to put the item back"); ImGui.EndTooltip() end
    end
    if hasItemOnCursor() and ImGui.IsMouseReleased(ImGuiMouseButton.Right) and ImGui.IsWindowHovered() then
        removeItemFromCursor()
    end

    -- Footer: status messages (Keep/Junk, moves, sell), failed items notice
    ImGui.Separator()
    -- Failed items notice (after sell.mac finishes)
    if sellMacState.failedCount > 0 and mq.gettime() < sellMacState.showFailedUntil then
        ImGui.TextColored(ImVec4(1, 0.6, 0.2, 1), string.format("Failed to sell (%d):", sellMacState.failedCount))
        ImGui.SameLine()
        local failedList = table.concat(sellMacState.failedItems, ", ")
        if #failedList > 60 then failedList = failedList:sub(1, 57) .. "..." end
        ImGui.TextColored(ImVec4(1, 0.7, 0.3, 1), failedList)
        ImGui.SameLine()
        ImGui.TextColored(ImVec4(0.8, 0.8, 0.8, 1), "— Rerun /macro sell confirm to retry.")
    end
    if uiState.statusMessage ~= "" then
        ImGui.TextColored(ImVec4(0.5, 0.85, 0.5, 1), uiState.statusMessage)
    end
    ImGui.End()
    if uiState.configWindowOpen then
        local ctx = extendContext(buildViewContext())
        ConfigView.render(ctx)
    end

    renderBankWindow()
    if uiState.augmentsWindowShouldDraw then
        renderAugmentsWindow()
    end
end

-- ============================================================================
-- Commands & main
-- ============================================================================
--- Write ItemUI's sell list and progress before running macro (sell.mac uses sell_cache.ini).
local function runSellMacro()
    -- Refresh inventory, compute sell status, save cache + sell_cache.ini so macro sees current list
    scanInventory()
    if isMerchantWindowOpen() then scanSellItems() end
    if #inventoryItems > 0 then
        computeAndAttachSellStatus(inventoryItems)
        storage.ensureCharFolderExists()
        storage.saveInventory(inventoryItems)
        storage.writeSellCache(inventoryItems)
    end
    local count = 0
    for _, it in ipairs(sellItems) do if it.willSell then count = count + 1 end end
    if perfCache.sellLogPath and count >= 0 then
        local progPath = perfCache.sellLogPath .. "\\sell_progress.ini"
        mq.cmdf('/ini "%s" Progress total %d', progPath, count)
        mq.cmdf('/ini "%s" Progress current 0', progPath)
        mq.cmdf('/ini "%s" Progress remaining %d', progPath, count)
    end
    mq.cmd('/macro sell confirm')
end

local function handleCommand(...)
    local cmd = (({...})[1] or ""):lower()
    if cmd == "" or cmd == "toggle" then
        shouldDraw = not shouldDraw
        if shouldDraw then
            local _w = mq.TLO and mq.TLO.Window and mq.TLO.Window("InventoryWindow")
            local invO, bankO, merchO = (_w and _w.Open and _w.Open()) or false, isBankWindowOpen(), isMerchantWindowOpen()
            -- If inv closed, open it so /inv and I key give same behavior (inv open + fresh scan)
            if not invO then mq.cmd('/keypress inventory'); invO = true end
            isOpen = true; loadLayoutConfig(); maybeScanInventory(invO); maybeScanBank(bankO); maybeScanSellItems(merchO)
        else
            closeGameInventoryIfOpen()
        end
    elseif cmd == "show" then
        shouldDraw, isOpen = true, true
        local _w = mq.TLO and mq.TLO.Window and mq.TLO.Window("InventoryWindow")
        local invO, bankO, merchO = (_w and _w.Open and _w.Open()) or false, isBankWindowOpen(), isMerchantWindowOpen()
        loadLayoutConfig()
        maybeScanInventory(invO); maybeScanBank(bankO); maybeScanSellItems(merchO)
    elseif cmd == "hide" then
        shouldDraw, isOpen = false, false
        closeGameInventoryIfOpen()
    elseif cmd == "refresh" then
        scanInventory()
        if isBankWindowOpen() then scanBank() end
        if isMerchantWindowOpen() then scanSellItems() end
        print("\ag[ItemUI]\ax Refreshed")
    elseif cmd == "setup" then
        uiState.setupMode = not uiState.setupMode
        if uiState.setupMode then uiState.setupStep = 1; loadLayoutConfig() else uiState.setupStep = 0 end
        shouldDraw = true
        isOpen = true
        print(uiState.setupMode and "\ag[ItemUI]\ax Setup: Step 1 of 3 — Resize the Inventory view, then click Next." or "\ar[ItemUI]\ax Setup off.")
    elseif cmd == "config" then
        uiState.configWindowOpen = true
        uiState.configNeedsLoad = true
        shouldDraw = true
        isOpen = true
        print("\ag[ItemUI]\ax Config window opened.")
    elseif cmd == "exit" or cmd == "quit" or cmd == "unload" then
        storage.ensureCharFolderExists()
        if #sellItems > 0 then
            storage.saveInventory(sellItems)
            storage.writeSellCache(sellItems)
        elseif #inventoryItems > 0 then
            computeAndAttachSellStatus(inventoryItems)
            storage.saveInventory(inventoryItems)
            storage.writeSellCache(inventoryItems)
        end
        if (bankItems and #bankItems > 0) or (bankCache and #bankCache > 0) then
            storage.saveBank(bankItems and #bankItems > 0 and bankItems or bankCache)
        end
        terminate = true
        shouldDraw = false
        isOpen = false
        uiState.configWindowOpen = false
        print("\ag[ItemUI]\ax Unloading...")
    elseif cmd == "help" then
        print("\ag[ItemUI]\ax /itemui or /inv or /inventoryui [toggle|show|hide|refresh|setup|exit|help]")
        print("  setup = resize and save window/column layout for Inventory, Sell, and Inventory+Bank")
        print("  Config = open ItemUI & Loot settings (or click Config in the header)")
        print("  exit  = unload ItemUI completely")
        print("\ag[ItemUI]\ax /dosell = run sell.mac (sell marked items)  |  /doloot = run loot.mac")
    else
        print("\ar[ItemUI]\ax Unknown: " .. cmd .. " — use /itemui help")
    end
end

local function main()
    -- Startup order: 1) Unbind 2) Bind + imgui.init 3) Paths 4) Wait for Me 5) loadLayoutConfig 6) maybeScan* 7) Initial persist 8) Main loop
    print(string.format("\ag[ItemUI]\ax Item UI v%s loaded. /itemui or /inv to toggle. /dosell, /doloot for macros.", C.VERSION))
    -- Unbind first so reload or leftover bindings don't cause "already bound" errors
    pcall(function() mq.unbind('/inventoryui') end)
    pcall(function() mq.unbind('/inv') end)
    pcall(function() mq.unbind('/itemui') end)
    pcall(function() mq.unbind('/bankui') end)
    pcall(function() mq.unbind('/dosell') end)
    pcall(function() mq.unbind('/doloot') end)
    mq.bind('/itemui', handleCommand)
    mq.bind('/inv', handleCommand)           -- Short alias (avoids MQ built-in /items)
    mq.bind('/inventoryui', handleCommand)  -- Alias for users migrating from old InventoryUI
    mq.bind('/bankui', handleCommand)       -- Alias for users migrating from old BankUI
    mq.bind('/dosell', runSellMacro)
    mq.bind('/doloot', function() mq.cmd('/macro loot') end)
    mq.imgui.init('ItemUI', renderUI)
    do
        local p = mq.TLO.MacroQuest and mq.TLO.MacroQuest.Path and mq.TLO.MacroQuest.Path()
        if p and p ~= "" then
            transferStampPath = p .. "\\bankinv_refresh.txt"
            itemOps.setTransferStampPath(transferStampPath)
            -- Use backslashes to match sell.mac path (MacroQuest.Path may use / or \)
            perfCache.sellLogPath = (p:gsub("/", "\\")) .. "\\Macros\\logs\\item_management"
        end
    end
    while not (mq.TLO and mq.TLO.Me and mq.TLO.Me.Name and mq.TLO.Me.Name()) do mq.delay(1000) end
    loadLayoutConfig()  -- Single parse loads defaults, layout, column visibility
    do
        local path = layoutUtils.getLayoutFilePath()
        if not path or path == "" then
            print("\ar[ItemUI]\ax Warning: MacroQuest path not set; config and layout may not work.")
        end
    end
    storage.init({ profileEnabled = C.PROFILE_ENABLED, profileThresholdMs = C.PROFILE_THRESHOLD_MS })
    local invWnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("InventoryWindow")
    local invO = (invWnd and invWnd.Open and invWnd.Open()) or false
    local bankO, merchO = isBankWindowOpen(), isMerchantWindowOpen()
    maybeScanInventory(invO); maybeScanBank(bankO); maybeScanSellItems(merchO)
    -- Initial persist save so data survives if game closes before first periodic save.
    -- Skip inventory save when scanInventory() already persisted (lastPersistSaveTime set) to avoid double save on startup.
    local charName = mq.TLO.Me and mq.TLO.Me.Name and mq.TLO.Me.Name() or ""
    if charName ~= "" then
        storage.ensureCharFolderExists()
        if scanState.lastPersistSaveTime == 0 then
            if #sellItems > 0 then
                storage.saveInventory(sellItems)
                storage.writeSellCache(sellItems)
            elseif #inventoryItems > 0 then
                computeAndAttachSellStatus(inventoryItems)
                storage.saveInventory(inventoryItems)
                storage.writeSellCache(inventoryItems)
            end
        end
        local bankInit = (bankO and bankItems and #bankItems > 0) and bankItems or bankCache
        if bankInit and #bankInit > 0 then storage.saveBank(bankInit) end
        if scanState.lastPersistSaveTime == 0 then scanState.lastPersistSaveTime = mq.gettime() end
    end

    -- Main loop phases: 1) Status expiry 2) Periodic persist 3) Auto-sell 4) Sell macro done 5) Loot macro 6) Process queue 7) Pending scans 8) Auto-show/hide 9) Layout save 10) Delay. Hot path: no file I/O in render; sort/config from cache.
    while not terminate do
        local now = mq.gettime()
        -- Clear expired status message (keeps render path free of gettime)
        if uiState.statusMessage ~= "" and (now - uiState.statusMessageTime) > (C.STATUS_MSG_SECS * 1000) then
            uiState.statusMessage = ""
        end
        -- Periodic persist: save inventory/bank so data survives game close/crash
        if (now - scanState.lastPersistSaveTime) >= C.PERSIST_SAVE_INTERVAL_MS then
            local charName = mq.TLO.Me and mq.TLO.Me.Name and mq.TLO.Me.Name() or ""
            if charName ~= "" then
                storage.ensureCharFolderExists()
                if #sellItems > 0 then
                    storage.saveInventory(sellItems)
                    storage.writeSellCache(sellItems)
                elseif #inventoryItems > 0 then
                    computeAndAttachSellStatus(inventoryItems)
                    storage.saveInventory(inventoryItems)
                    storage.writeSellCache(inventoryItems)
                end
                local bankToSave = (isBankWindowOpen() and bankItems and #bankItems > 0) and bankItems or bankCache
                if bankToSave and #bankToSave > 0 then
                    storage.saveBank(bankToSave)
                end
                scanState.lastPersistSaveTime = now
            end
        end
        -- Rescans happen only on reopen or Refresh; moves update tables in-place (like Keep/Junk).
        if uiState.autoSellRequested then
            uiState.autoSellRequested = false
            runSellMacro()
            setStatusMessage("Running sell macro...")
        end
        -- Detect sell.mac finish: force inventory refresh and read failed items
        do
            local macroName = mq.TLO.Macro and mq.TLO.Macro.Name and (mq.TLO.Macro.Name() or "") or ""
            local mn = macroName:lower()
            local sellMacRunning = (mn == "sell" or mn == "sell.mac")
            if sellMacState.lastRunning and not sellMacRunning then
                -- Sell macro just finished
                sellMacState.smoothedFrac = 0  -- reset for next run
                mq.delay(300)
                scanInventory()
                if isMerchantWindowOpen() then scanSellItems() end
                invalidateSortCache("inv"); invalidateSortCache("sell")
                -- Read failed items from sell_failed.ini
                sellMacState.failedItems = {}
                sellMacState.failedCount = 0
                if perfCache.sellLogPath then
                    local failedPath = perfCache.sellLogPath .. "\\sell_failed.ini"
                    local countStr = config.safeIniValueByPath(failedPath, "Failed", "count", "0")
                    local count = tonumber(countStr) or 0
                    if count > 0 then
                        sellMacState.failedCount = count
                        for i = 1, count do
                            local item = config.safeIniValueByPath(failedPath, "Failed", "item" .. i, "")
                            if item and item ~= "" then table.insert(sellMacState.failedItems, item) end
                        end
                        sellMacState.showFailedUntil = now + C.SELL_FAILED_DISPLAY_MS
                        uiState.statusMessage = ""  -- failed list in footer shows the notice
                    else
                        setStatusMessage("Sell complete. Inventory refreshed.")
                    end
                else
                    setStatusMessage("Sell complete. Inventory refreshed.")
                end
                print("\ag[ItemUI]\ax Sell macro finished - inventory refreshed")
            end
            sellMacState.lastRunning = sellMacRunning
        end
        -- Loot macro just finished: defer scan to next iteration (gives /inv or I-key a chance to run first)
        do
            local macroName = mq.TLO.Macro and mq.TLO.Macro.Name and (mq.TLO.Macro.Name() or "") or ""
            local mn = macroName:lower()
            local lootMacRunning = (mn == "loot" or mn == "loot.mac")
            if lootMacState.lastRunning and not lootMacRunning then
                lootMacState.pendingScan = true
            end
            lootMacState.lastRunning = lootMacRunning
        end
        processSellQueue()
        -- Handle pending quantity pickup action (non-blocking, runs in main loop)
        if uiState.pendingQuantityAction then
            local action = uiState.pendingQuantityAction
            uiState.pendingQuantityAction = nil  -- Clear immediately to prevent re-processing
            -- Pick up the item (this will open QuantityWnd)
            if action.pickup.source == "bank" then
                mq.cmdf('/itemnotify in bank%d %d leftmouseup', action.pickup.bag, action.pickup.slot)
            else
                mq.cmdf('/itemnotify in pack%d %d leftmouseup', action.pickup.bag, action.pickup.slot)
            end
            -- Wait for QuantityWnd to open, then set quantity and accept
            mq.delay(300, function()
                local w = mq.TLO and mq.TLO.Window and mq.TLO.Window("QuantityWnd")
                return w and w.Open and w.Open()
            end)
            local qtyWndOpen = (function()
                local w = mq.TLO and mq.TLO.Window and mq.TLO.Window("QuantityWnd")
                return w and w.Open and w.Open()
            end)()
            if qtyWndOpen then
                mq.cmd(string.format('/notify QuantityWnd QTYW_Slider newvalue %d', action.qty))
                mq.delay(150)
                mq.cmd('/notify QuantityWnd QTYW_Accept_Button leftmouseup')
            end
        end
        -- Clear pending quantity pickup if item was picked up manually or QuantityWnd closed
        if uiState.pendingQuantityPickup then
            local qtyWnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("QuantityWnd")
            local qtyWndOpen = qtyWnd and qtyWnd.Open and qtyWnd.Open() or false
            local hasCursor = hasItemOnCursor()
            -- Clear if QuantityWnd closed (user cancelled manually) or item is on cursor (user picked it up manually)
            if not qtyWndOpen and not hasCursor then
                -- Check if item still exists at the location
                local itemExists = false
                local Me = mq.TLO and mq.TLO.Me
                if uiState.pendingQuantityPickup.source == "bank" then
                    local bn = Me and Me.Bank and Me.Bank(uiState.pendingQuantityPickup.bag)
                    local sz = bn and bn.Container and bn.Container()
                    local it = (bn and sz and sz > 0) and (bn.Item and bn.Item(uiState.pendingQuantityPickup.slot)) or bn
                    itemExists = it and it.ID and it.ID() and it.ID() > 0
                else
                    local pack = Me and Me.Inventory and Me.Inventory("pack" .. uiState.pendingQuantityPickup.bag)
                    local it = pack and pack.Item and pack.Item(uiState.pendingQuantityPickup.slot)
                    itemExists = it and it.ID and it.ID() and it.ID() > 0
                end
                if not itemExists then
                    -- Item was picked up, clear pending
                    uiState.pendingQuantityPickup = nil
                    uiState.quantityPickerValue = ""
                end
            elseif hasCursor then
                -- Item is on cursor, clear pending (user picked it up manually)
                uiState.pendingQuantityPickup = nil
                uiState.quantityPickerValue = ""
            end
        end
        local invWndLoop = mq.TLO and mq.TLO.Window and mq.TLO.Window("InventoryWindow")
        local invOpen = (invWndLoop and invWndLoop.Open and invWndLoop.Open()) or false
        local bankOpen = isBankWindowOpen()
        local merchOpen = isMerchantWindowOpen()
        local lootOpen = isLootWindowOpen()
        local bankJustOpened = bankOpen and not lastBankWindowState
        local lootJustClosed = lastLootWindowState and not lootOpen
        local shouldDrawBefore = shouldDraw  -- capture before any auto-show
        -- Run deferred scans from previous frame (one scan per first-paint; rest run here)
        if deferredScanNeeded.inventory then maybeScanInventory(invOpen); deferredScanNeeded.inventory = false end
        if deferredScanNeeded.bank then maybeScanBank(bankOpen); deferredScanNeeded.bank = false end
        if deferredScanNeeded.sell then maybeScanSellItems(merchOpen); deferredScanNeeded.sell = false end
        if perfCache.sellConfigPendingRefresh then
            -- Force fresh config load so we see INI changes (e.g. addToJunkList) that may not have been visible when cache was last loaded
            if perfCache.sellConfigCache then sellStatusService.invalidateSellConfigCache() end
            computeAndAttachSellStatus(inventoryItems)
            if sellItems and #sellItems > 0 then computeAndAttachSellStatus(sellItems) end
            if bankItems and #bankItems > 0 then computeAndAttachSellStatus(bankItems) end
            perfCache.sellConfigPendingRefresh = false
        end
        -- Auto-show when inventory, bank, or merchant just opened (loot view disabled - loot macro uses default EQ loot UI)
        local invJustOpened = invOpen and not lastInventoryWindowState
        -- Prime Stats tab only the first time inventory is opened this ItemUI session (so AC/ATK/Weight load once)
        if invJustOpened and invOpen and not statsTabPrimedThisSession then
            mq.cmd('/notify InventoryWindow IW_Subwindows tabselect 2')
            statsTabPrimeState = 'shown'
            statsTabPrimeAt = now
            statsTabPrimedThisSession = true
        end
        -- After priming delay, switch back to Inventory tab (tab 1)
        if statsTabPrimeState == 'shown' and invOpen and (now - statsTabPrimeAt) >= STATS_TAB_PRIME_MS then
            mq.cmd('/notify InventoryWindow IW_Subwindows tabselect 1')
            statsTabPrimeState = nil
        end
        if lastInventoryWindowState and not invOpen then statsTabPrimeState = nil end
        -- Macro.Name may return "loot" or "loot.mac" depending on MQ version (needed before bag-open and ItemUI suppress)
        local lootMacName = (mq.TLO.Macro and mq.TLO.Macro.Name and (mq.TLO.Macro.Name() or ""):lower()) or ""
        local lootMacRunning = (lootMacName == "loot" or lootMacName == "loot.mac")
        -- Open all bags when inventory is opened (OPEN_INV_BAGS is the EQ keybind to open/toggle bags)
        -- Skip opening bags when loot macro is running with SuppressWhenLootMac (keep EQ bag state unchanged)
        if invJustOpened and invOpen and not (lootMacRunning and uiState.suppressWhenLootMac) then
            mq.cmd('/keypress OPEN_INV_BAGS')
        end
        -- When loot macro running: keep ItemUI hidden (suppress auto-show and force-hide if already visible)
        if lootMacRunning and shouldDraw then
            flushLayoutSave()  -- Persist sort before hiding so next open has correct sort
            shouldDraw = false
            isOpen = false
            uiState.configWindowOpen = false
            if invOpen then mq.cmd('/keypress inventory') end
        end
        local invOpenedFromLoot = invJustOpened and uiState.suppressWhenLootMac and lootMacRunning
        local shouldAutoShowInv = invJustOpened and not invOpenedFromLoot
        -- Run pending background scan (from loot macro finish) only when user isn't opening and enough time has passed
        -- Delay 2.5s so user opening right after looting always wins (avoids double-scan, preserves sort)
        if lootMacState.pendingScan then
            local userOpening = shouldAutoShowInv or bankJustOpened or (merchOpen and not lastMerchantState) or shouldDraw
            local elapsed = now - (lootMacState.finishedAt or 0)
            if not userOpening and elapsed >= C.LOOT_PENDING_SCAN_DELAY_MS then
                scanInventory()
                invalidateSortCache("inv")
            end
            lootMacState.pendingScan = false
        end
        if shouldAutoShowInv or bankJustOpened or (merchOpen and not lastMerchantState) then
            if not shouldDraw then
                shouldDraw = true
                isOpen = true
                loadLayoutConfig()
                uiState.bankWindowOpen = bankJustOpened
                uiState.bankWindowShouldDraw = uiState.bankWindowOpen
                -- Run only the scan that triggered show; defer others to next frame for faster first paint
                if bankJustOpened then
                    maybeScanBank(bankOpen)
                    deferredScanNeeded.inventory = invOpen
                    deferredScanNeeded.sell = merchOpen
                elseif merchOpen and not lastMerchantState then
                    maybeScanInventory(invOpen)
                    deferredScanNeeded.sell = true
                    deferredScanNeeded.bank = bankOpen
                else
                    maybeScanInventory(invOpen)
                    deferredScanNeeded.bank = bankOpen
                    deferredScanNeeded.sell = merchOpen
                end
            end
        end
        -- When bank window is open but ItemUI is hidden, show it and open bank window (e.g. right-click banker with bank already open)
        if bankOpen and not shouldDraw then
            shouldDraw = true
            isOpen = true
            loadLayoutConfig()
            uiState.bankWindowOpen = true
            uiState.bankWindowShouldDraw = true
            maybeScanBank(bankOpen)
            deferredScanNeeded.inventory = invOpen
            deferredScanNeeded.sell = merchOpen
        end
        -- When loot macro running and loot window closes: hide ItemUI and close inventory
        if lootMacRunning and lootJustClosed then
            shouldDraw = false
            isOpen = false
            uiState.configWindowOpen = false
            if invOpen then
                mq.cmd('/keypress inventory')
            end
        end
        -- Auto-close when inventory window closes: close all bags (toggle) and save character snapshot
        if lastInventoryWindowState and not invOpen then
            mq.cmd('/keypress CLOSE_INV_BAGS')
            storage.ensureCharFolderExists()
            if #sellItems > 0 then
                storage.saveInventory(sellItems)
                storage.writeSellCache(sellItems)
            else
                computeAndAttachSellStatus(inventoryItems)
                storage.saveInventory(inventoryItems)
                storage.writeSellCache(inventoryItems)
            end
            local bankToSave = bankOpen and bankItems or bankCache
            if bankToSave and #bankToSave > 0 then
                storage.saveBank(bankToSave)
            end
            flushLayoutSave()  -- Persist sort/layout immediately so next open shows correct sort
            shouldDraw = false
            isOpen = false
            uiState.configWindowOpen = false
        end
        -- When bank just opened and ItemUI was already showing: open bank panel and refresh (avoid duplicate scan if we auto-showed above)
        if bankJustOpened and shouldDrawBefore then
            uiState.bankWindowOpen = true
            uiState.bankWindowShouldDraw = true
            maybeScanBank(bankOpen)
        elseif bankJustOpened then
            uiState.bankWindowOpen = true
            uiState.bankWindowShouldDraw = true
        end
        -- Update lastScanState when windows close (so we'll scan when they reopen)
        if lastInventoryWindowState and not invOpen then scanState.lastScanState.invOpen = false end
        if lastBankWindowState and not bankOpen then scanState.lastScanState.bankOpen = false end
        if lastMerchantState and not merchOpen then scanState.lastScanState.merchOpen = false end
        local lootOpenNow = isLootWindowOpen()
        -- Auto-accept no-drop valuable item confirmation when loot window open
        if lootOpenNow then
            local confirmWnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("ConfirmationDialogBox")
            if confirmWnd and confirmWnd.Open and confirmWnd.Open() then
                mq.cmd('/notify ConfirmationDialogBox CD_Yes_Button leftmouseup')
            end
        end
        if lastLootWindowState and not lootOpenNow then scanState.lastScanState.lootOpen = false; lootItems = {} end
        lastInventoryWindowState = invOpen
        lastBankWindowState = bankOpen
        lastMerchantState = merchOpen
        lastLootWindowState = lootOpenNow
        -- Debounced layout save: batch rapid changes (sort, tab switch) into one file write
        if perfCache.layoutDirty and (now - perfCache.layoutSaveScheduledAt) >= perfCache.layoutSaveDebounceMs then
            perfCache.layoutDirty = false
            saveLayoutToFileImmediate()
        end
        -- Periodic cache cleanup: evict expired spell cache entries (every 30s)
        if not perfCache.lastCacheCleanup or (now - perfCache.lastCacheCleanup) >= 30000 then
            perfCache.lastCacheCleanup = now
            Cache.cleanup()
        end
        mq.delay(shouldDraw and C.LOOP_DELAY_VISIBLE_MS or C.LOOP_DELAY_HIDDEN_MS)
        mq.doevents()
    end
    flushLayoutSave()  -- Persist any pending layout changes before unload
    mq.imgui.destroy('ItemUI')
    mq.unbind('/itemui')
    mq.unbind('/inv')
    mq.unbind('/inventoryui')
    mq.unbind('/bankui')
    mq.unbind('/dosell')
    mq.unbind('/doloot')
    print("\ag[ItemUI]\ax Unloaded.")
end

main()