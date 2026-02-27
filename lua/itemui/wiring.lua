--[[
    ItemUI wiring (Task 6.3): module requires, inits, context assembly, main loop.
    Exposes runMain() for bootstrap. No behavior change.
--]]

local mq = require('mq')
local CoopVersion = require('coopui.version')
local config = require('itemui.config')
local config_cache = require('itemui.config_cache')
local context = require('itemui.context')
local context_builder = require('itemui.context_builder')
local rules = require('itemui.rules')
local storage = require('itemui.storage')
-- Phase 2: Core infrastructure (cache.lua used for spell caches; state/events partially integrated)
local Cache = require('itemui.core.cache')
local events = require('itemui.core.events')
local registry = require('itemui.core.registry')

-- Components
local CharacterStats = require('itemui.components.character_stats')

-- Phase 3: Filter system modules
local filterService = require('itemui.services.filter_service')
local searchbar = require('itemui.components.searchbar')
local filtersComponent = require('itemui.components.filters')
local ui_common = require('itemui.components.ui_common')

-- Phase 5: Macro integration service
local macroBridge = require('itemui.services.macro_bridge')
local scanService = require('itemui.services.scan')
local sellStatusService = require('itemui.services.sell_status')
local itemOps = require('itemui.services.item_ops')
local augmentOps = require('itemui.services.augment_ops')
local sellBatch = require('itemui.services.sell_batch')
local mainLoop = require('itemui.services.main_loop')

-- Phase 5: View modules
local InventoryView = require('itemui.views.inventory')
local SellView = require('itemui.views.sell')
local BankView = require('itemui.views.bank')
local EquipmentView = require('itemui.views.equipment')
local LootView = require('itemui.views.loot')
local ConfigView = require('itemui.views.settings')
local LootUIView = require('itemui.views.loot_ui')
local AugmentsView = require('itemui.views.augments')
local AugmentUtilityView = require('itemui.views.augment_utility')
local ItemDisplayView = require('itemui.views.item_display')
local AAView = require('itemui.views.aa')
local aa_data = require('itemui.services.aa_data')
local rerollService = require('itemui.services.reroll_service')
local MainWindow = require('itemui.views.main_window')
local ConfigFilters = require('itemui.views.config_filters')

-- Phase 7: Utility modules
local layoutUtils = require('itemui.utils.layout')
local defaultLayout = require('itemui.utils.default_layout')
local theme = require('itemui.utils.theme')
local columns = require('itemui.utils.columns')
local columnConfig = require('itemui.utils.column_config')
local sortUtils = require('itemui.utils.sort')
local tableCache = require('itemui.utils.table_cache')
local windowState = require('itemui.utils.window_state')
local itemHelpers = require('itemui.utils.item_helpers')
local icons = require('itemui.utils.icons')
local constants = require('itemui.constants')
local state = require('itemui.state')

-- Constants and state from state.lua (Task 6.3)
local C = state.C
local isOpen, shouldDraw, terminate = state.isOpen, state.shouldDraw, state.terminate
local inventoryItems, bankItems, lootItems = state.inventoryItems, state.bankItems, state.lootItems
local equipmentCache = state.equipmentCache
local transferStampPath, lastTransferStamp = state.transferStampPath, state.lastTransferStamp
local lastInventoryWindowState, lastBankWindowState, lastMerchantState, lastLootWindowState = state.lastInventoryWindowState, state.lastBankWindowState, state.lastMerchantState, state.lastLootWindowState
local statsTabPrimeState, statsTabPrimeAt = state.statsTabPrimeState, state.statsTabPrimeAt
local statsTabPrimedThisSession = state.statsTabPrimedThisSession
local perfCache = state.perfCache
local computeAndAttachSellStatus  -- forward declaration: set after willItemBeSold
local uiState = state.uiState
-- Delegate reroll and equipment state (4.2); existing uiState.* unchanged for callers
do
    local rerollKeys = { pendingRerollAdd = true, pendingRerollBankMoves = true, pendingAugRollComplete = true, pendingAugRollCompleteAt = true }
    setmetatable(uiState, {
        __index = function(t, k)
            if rerollKeys[k] then return rerollService.getState()[k] end
            if k == "equipmentWindowOpen" then return registry.isOpen("equipment") end
            if k == "equipmentWindowShouldDraw" then return registry.shouldDraw("equipment") end
            if k == "equipmentDeferredRefreshAt" then return EquipmentView.getState().equipmentDeferredRefreshAt end
            if k == "equipmentLastRefreshAt" then return EquipmentView.getState().equipmentLastRefreshAt end
            if k == "augmentsWindowOpen" then return registry.isOpen("augments") end
            if k == "augmentsWindowShouldDraw" then return registry.shouldDraw("augments") end
            if k == "searchFilterAugments" then return AugmentsView.getState().searchFilterAugments end
            if k == "augmentsSortColumn" then return AugmentsView.getState().augmentsSortColumn end
            if k == "augmentsSortDirection" then return AugmentsView.getState().augmentsSortDirection end
            if k == "augmentUtilityWindowOpen" then return registry.isOpen("augmentUtility") end
            if k == "augmentUtilityWindowShouldDraw" then return registry.shouldDraw("augmentUtility") end
            if k == "augmentUtilitySlotIndex" then return AugmentUtilityView.getState().augmentUtilitySlotIndex end
            if k == "searchFilterAugmentUtility" then return AugmentUtilityView.getState().searchFilterAugmentUtility end
            if k == "augmentUtilityOnlyShowUsable" then return AugmentUtilityView.getState().augmentUtilityOnlyShowUsable end
            if k == "itemDisplayWindowOpen" then return registry.isOpen("itemDisplay") end
            if k == "itemDisplayWindowShouldDraw" then return registry.shouldDraw("itemDisplay") end
            if k == "itemDisplayTabs" then return ItemDisplayView.getState().itemDisplayTabs end
            if k == "itemDisplayActiveTabIndex" then return ItemDisplayView.getState().itemDisplayActiveTabIndex end
            if k == "itemDisplayRecent" then return ItemDisplayView.getState().itemDisplayRecent end
            if k == "itemDisplayLocateRequest" then return ItemDisplayView.getState().itemDisplayLocateRequest end
            if k == "itemDisplayLocateRequestAt" then return ItemDisplayView.getState().itemDisplayLocateRequestAt end
            if k == "itemDisplayAugmentSlotActive" then return ItemDisplayView.getState().itemDisplayAugmentSlotActive end
            if k == "bankWindowOpen" then return registry.isOpen("bank") end
            if k == "bankWindowShouldDraw" then return registry.shouldDraw("bank") end
            if k == "configWindowOpen" then return registry.isOpen("config") end
            if k == "configNeedsLoad" then return ConfigView.getState().configNeedsLoad end
            if k == "configAdvancedMode" then return ConfigView.getState().configAdvancedMode end
            if k == "pendingLootRescan" then return LootView.getState().pendingLootRescan end
            if k == "pendingLootRemove" then return LootView.getState().pendingLootRemove end
            local lootUIKeys = {
                lootUIOpen = true, lootRunCorpsesLooted = true, lootRunTotalCorpses = true, lootRunCurrentCorpse = true,
                lootRunLootedList = true, lootRunLootedItems = true, lootHistory = true, skipHistory = true,
                lootRunFinished = true, lootMythicalAlert = true, lootMythicalDecisionStartAt = true, lootMythicalFeedback = true,
                lootRunTotalValue = true, lootRunTributeValue = true, lootRunBestItemName = true, lootRunBestItemValue = true,
                corpseLootedHidden = true,
            }
            if lootUIKeys[k] then return LootUIView.getState()[k] end
            local itemOpsKeys = {
                pendingDestroy = true, pendingDestroyAction = true, destroyQuantityValue = true, destroyQuantityMax = true,
                pendingMoveAction = true, quantityPickerValue = true, quantityPickerMax = true, quantityPickerSubmitPending = true,
                pendingQuantityPickup = true, pendingQuantityPickupTimeoutAt = true, pendingQuantityAction = true, pendingScriptConsume = true,
                lastPickup = true, lastPickupSetThisFrame = true, lastPickupClearedAt = true, activationGuardUntil = true,
                hadItemOnCursorLastFrame = true, hasItemOnCursorThisFrame = true,
            }
            if itemOpsKeys[k] then return itemOps.getState()[k] end
            local augmentOpsKeys = {
                pendingRemoveAugment = true, pendingInsertAugment = true,
                waitingForRemoveConfirmation = true, waitingForInsertConfirmation = true,
                waitingForInsertCursorClear = true, waitingForRemoveCursorPopulated = true,
                insertCursorClearTimeoutAt = true, removeCursorPopulatedTimeoutAt = true,
                insertConfirmationSetAt = true, removeConfirmationSetAt = true,
                removeAllQueue = true, optimizeQueue = true,
            }
            if augmentOpsKeys[k] then return augmentOps.getState()[k] end
            return rawget(t, k)
        end,
        __newindex = function(t, k, v)
            if rerollKeys[k] then rerollService.getState()[k] = v; return end
            if k == "equipmentWindowOpen" or k == "equipmentWindowShouldDraw" then registry.setWindowState("equipment", v, v); return end
            if k == "equipmentDeferredRefreshAt" then EquipmentView.getState().equipmentDeferredRefreshAt = v; return end
            if k == "equipmentLastRefreshAt" then EquipmentView.getState().equipmentLastRefreshAt = v; return end
            if k == "augmentsWindowOpen" or k == "augmentsWindowShouldDraw" then registry.setWindowState("augments", v, v); return end
            if k == "searchFilterAugments" then AugmentsView.getState().searchFilterAugments = v; return end
            if k == "augmentsSortColumn" then AugmentsView.getState().augmentsSortColumn = v; return end
            if k == "augmentsSortDirection" then AugmentsView.getState().augmentsSortDirection = v; return end
            if k == "augmentUtilityWindowOpen" or k == "augmentUtilityWindowShouldDraw" then registry.setWindowState("augmentUtility", v, v); return end
            if k == "augmentUtilitySlotIndex" then AugmentUtilityView.getState().augmentUtilitySlotIndex = v; return end
            if k == "searchFilterAugmentUtility" then AugmentUtilityView.getState().searchFilterAugmentUtility = v; return end
            if k == "augmentUtilityOnlyShowUsable" then AugmentUtilityView.getState().augmentUtilityOnlyShowUsable = v; return end
            if k == "itemDisplayWindowOpen" or k == "itemDisplayWindowShouldDraw" then registry.setWindowState("itemDisplay", v, v); return end
            if k == "itemDisplayTabs" then ItemDisplayView.getState().itemDisplayTabs = v; return end
            if k == "itemDisplayActiveTabIndex" then ItemDisplayView.getState().itemDisplayActiveTabIndex = v; return end
            if k == "itemDisplayRecent" then ItemDisplayView.getState().itemDisplayRecent = v; return end
            if k == "itemDisplayLocateRequest" then ItemDisplayView.getState().itemDisplayLocateRequest = v; return end
            if k == "itemDisplayLocateRequestAt" then ItemDisplayView.getState().itemDisplayLocateRequestAt = v; return end
            if k == "itemDisplayAugmentSlotActive" then ItemDisplayView.getState().itemDisplayAugmentSlotActive = v; return end
            if k == "bankWindowOpen" or k == "bankWindowShouldDraw" then registry.setWindowState("bank", v, v); return end
            if k == "configWindowOpen" then registry.setWindowState("config", v, v); return end
            if k == "configNeedsLoad" then ConfigView.getState().configNeedsLoad = v; return end
            if k == "configAdvancedMode" then ConfigView.getState().configAdvancedMode = v; return end
            if k == "pendingLootRescan" then LootView.getState().pendingLootRescan = v; return end
            if k == "pendingLootRemove" then LootView.getState().pendingLootRemove = v; return end
            local lootUIKeys = {
                lootUIOpen = true, lootRunCorpsesLooted = true, lootRunTotalCorpses = true, lootRunCurrentCorpse = true,
                lootRunLootedList = true, lootRunLootedItems = true, lootHistory = true, skipHistory = true,
                lootRunFinished = true, lootMythicalAlert = true, lootMythicalDecisionStartAt = true, lootMythicalFeedback = true,
                lootRunTotalValue = true, lootRunTributeValue = true, lootRunBestItemName = true, lootRunBestItemValue = true,
                corpseLootedHidden = true,
            }
            if lootUIKeys[k] then LootUIView.getState()[k] = v; return end
            local itemOpsKeys = {
                pendingDestroy = true, pendingDestroyAction = true, destroyQuantityValue = true, destroyQuantityMax = true,
                pendingMoveAction = true, quantityPickerValue = true, quantityPickerMax = true, quantityPickerSubmitPending = true,
                pendingQuantityPickup = true, pendingQuantityPickupTimeoutAt = true, pendingQuantityAction = true, pendingScriptConsume = true,
                lastPickup = true, lastPickupSetThisFrame = true, lastPickupClearedAt = true, activationGuardUntil = true,
                hadItemOnCursorLastFrame = true, hasItemOnCursorThisFrame = true,
            }
            if itemOpsKeys[k] then itemOps.getState()[k] = v; return end
            local augmentOpsKeys = {
                pendingRemoveAugment = true, pendingInsertAugment = true,
                waitingForRemoveConfirmation = true, waitingForInsertConfirmation = true,
                waitingForInsertCursorClear = true, waitingForRemoveCursorPopulated = true,
                insertCursorClearTimeoutAt = true, removeCursorPopulatedTimeoutAt = true,
                insertConfirmationSetAt = true, removeConfirmationSetAt = true,
                removeAllQueue = true, optimizeQueue = true,
            }
            if augmentOpsKeys[k] then augmentOps.getState()[k] = v; return end
            rawset(t, k, v)
        end,
    })
end

local layoutDefaults = state.layoutDefaults
local layoutConfig = state.layoutConfig  -- filled by loadLayoutConfig()
registry.init({ layoutConfig = layoutConfig, companionWindowOpenedAt = uiState.companionWindowOpenedAt })

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
local filterState = state.filterState
local sortState = state.sortState
-- Delegate sortState.aaTab to aa_data for 4.2 state ownership (layout and AA view still use ctx.sortState.aaTab)
setmetatable(sortState, {
    __index = function(t, k)
        if k == "aaTab" then return aa_data.getAaTab() end
        return rawget(t, k)
    end,
    __newindex = function(t, k, v)
        if k == "aaTab" then aa_data.setAaTab(v); return end
        rawset(t, k, v)
    end,
})

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
local sellItems = state.sellItems
local sellMacState = state.sellMacState
local lootMacState = state.lootMacState
local lootLoopRefs = state.lootLoopRefs
local LOOT_HISTORY_MAX = state.LOOT_HISTORY_MAX
local LOOT_HISTORY_DELIM = state.LOOT_HISTORY_DELIM
local function loadLootHistoryFromFile()
    if not config.getLootConfigFile then return end
    local path = config.getLootConfigFile("loot_history.ini")
    if not path or path == "" then return end
    local countStr = config.safeIniValueByPath(path, "History", "count", "0")
    local count = tonumber(countStr) or 0
    if count == 0 then uiState.lootHistory = {}; return end
    uiState.lootHistory = {}
    for i = 1, count do
        local raw = config.safeIniValueByPath(path, "History", tostring(i), "")
        if raw and raw ~= "" then
            local parts = {}
            for p in (raw .. LOOT_HISTORY_DELIM):gmatch("(.-)" .. LOOT_HISTORY_DELIM) do parts[#parts + 1] = p end
            table.insert(uiState.lootHistory, {
                name = parts[1] or "",
                value = tonumber(parts[2]) or 0,
                statusText = parts[3] or "—",
                willSell = (parts[4] == "1")
            })
        end
    end
    while #uiState.lootHistory > LOOT_HISTORY_MAX do table.remove(uiState.lootHistory, 1) end
end
local function saveLootHistoryToFile()
    if not uiState.lootHistory or #uiState.lootHistory == 0 then return end
    local path = config.getLootConfigFile and config.getLootConfigFile("loot_history.ini")
    if not path or path == "" then return end
    mq.cmdf('/ini "%s" History count %d', path, #uiState.lootHistory)
    for i, row in ipairs(uiState.lootHistory) do
        local val = string.format("%s%s%d%s%s%s%s", row.name or "", LOOT_HISTORY_DELIM, row.value or 0, LOOT_HISTORY_DELIM, row.statusText or "—", LOOT_HISTORY_DELIM, row.willSell and "1" or "0")
        mq.cmdf('/ini "%s" History %d "%s"', path, i, val:gsub('"', '""'))
    end
end
local function loadSkipHistoryFromFile()
    if not config.getLootConfigFile then return end
    local path = config.getLootConfigFile("skip_history.ini")
    if not path or path == "" then return end
    local countStr = config.safeIniValueByPath(path, "Skip", "count", "0")
    local count = tonumber(countStr) or 0
    if count == 0 then uiState.skipHistory = {}; return end
    uiState.skipHistory = {}
    for i = 1, count do
        local raw = config.safeIniValueByPath(path, "Skip", tostring(i), "")
        if raw and raw ~= "" then
            local pos = raw:find(LOOT_HISTORY_DELIM, 1, true)
            local name = pos and raw:sub(1, pos - 1) or raw
            local reason = pos and raw:sub(pos + 1) or ""
            table.insert(uiState.skipHistory, { name = name, reason = reason })
        end
    end
end
local function saveSkipHistoryToFile()
    if not uiState.skipHistory or #uiState.skipHistory == 0 then return end
    local path = config.getLootConfigFile and config.getLootConfigFile("skip_history.ini")
    if not path or path == "" then return end
    mq.cmdf('/ini "%s" Skip count %d', path, #uiState.skipHistory)
    for i, row in ipairs(uiState.skipHistory) do
        local val = (row.name or "") .. LOOT_HISTORY_DELIM .. (row.reason or "")
        mq.cmdf('/ini "%s" Skip %d "%s"', path, i, val:gsub('"', '""'))
    end
end
lootLoopRefs.saveLootHistory = saveLootHistoryToFile
lootLoopRefs.saveSkipHistory = saveSkipHistoryToFile
local function clearLootItems()
    for i = #lootItems, 1, -1 do lootItems[i] = nil end
end
local bankCache = state.bankCache
local scanState = state.scanState
-- Invalidate stored-inv cache when we save; pass nextAcquiredSeq so acquired order persists (must be after scanState)
do
    local _saveInv = storage.saveInventory
    storage.saveInventory = function(items) _saveInv(items, scanState.nextAcquiredSeq); perfCache.storedInvByName = nil end
end
local deferredScanNeeded = state.deferredScanNeeded

-- Item helpers: init and local aliases (delegated to utils/item_helpers.lua)
perfCache.sellConfigCache = nil
itemHelpers.init({ C = C, uiState = uiState, perfCache = perfCache })
local function setStatusMessage(msg) itemHelpers.setStatusMessage(msg) end
local function getItemSpellId(item, prop) return itemHelpers.getItemSpellId(item, prop) end
local function getSpellName(id) return itemHelpers.getSpellName(id) end

-- Companion windows: LIFO close order (record open time; Esc closes most recently opened)
local function recordCompanionWindowOpened(name)
    uiState.companionWindowOpenedAt = uiState.companionWindowOpenedAt or {}
    uiState.companionWindowOpenedAt[name] = mq.gettime()
end
local function closeCompanionWindow(name)
    if name == "config" then
        registry.setWindowState("config", false, false)
        if uiState.companionWindowOpenedAt then uiState.companionWindowOpenedAt[name] = nil end
        return
    elseif name == "equipment" then
        registry.setWindowState("equipment", false, false)
        if uiState.companionWindowOpenedAt then uiState.companionWindowOpenedAt[name] = nil end
        return
    elseif name == "bank" then
        registry.setWindowState("bank", false, false)
        if uiState.companionWindowOpenedAt then uiState.companionWindowOpenedAt[name] = nil end
        return
    elseif name == "augments" then
        registry.setWindowState("augments", false, false)
        if uiState.companionWindowOpenedAt then uiState.companionWindowOpenedAt[name] = nil end
        return
    elseif name == "augmentUtility" then
        registry.setWindowState("augmentUtility", false, false)
        if uiState.companionWindowOpenedAt then uiState.companionWindowOpenedAt[name] = nil end
        return
    elseif name == "itemDisplay" then
        registry.setWindowState("itemDisplay", false, false)
        ItemDisplayView.getState().itemDisplayTabs = {}
        ItemDisplayView.getState().itemDisplayActiveTabIndex = 1
        uiState.removeAllQueue = nil   -- Phase 1: target changed
        uiState.optimizeQueue = nil    -- Phase 2: target changed
        if uiState.companionWindowOpenedAt then uiState.companionWindowOpenedAt[name] = nil end
        return
    elseif name == "aa" then
        registry.setWindowState("aa", false, false)
        if uiState.companionWindowOpenedAt then uiState.companionWindowOpenedAt[name] = nil end
        return
    elseif name == "reroll" then
        registry.setWindowState("reroll", false, false)
        if uiState.companionWindowOpenedAt then uiState.companionWindowOpenedAt[name] = nil end
        return
    elseif name == "loot" then
        uiState.lootUIOpen = false
        uiState.lootRunLootedList = {}
        uiState.lootRunLootedItems = {}
        uiState.lootRunCorpsesLooted = 0
        uiState.lootRunTotalCorpses = 0
        uiState.lootRunCurrentCorpse = ""
        uiState.lootRunFinished = false
        uiState.lootMythicalAlert = nil
        uiState.lootMythicalDecisionStartAt = nil
        uiState.lootMythicalFeedback = nil
        uiState.lootRunTotalValue = 0
        uiState.lootRunTributeValue = 0
        uiState.lootRunBestItemName = ""
        uiState.lootRunBestItemValue = 0
    end
    if uiState.companionWindowOpenedAt then uiState.companionWindowOpenedAt[name] = nil end
end
local function getMostRecentlyOpenedCompanion()
    local at = uiState.companionWindowOpenedAt
    if not at then return nil end
    local candidates = {
        { "config", registry.isOpen("config") },
        { "equipment", registry.isOpen("equipment") },
        { "bank", registry.isOpen("bank") },
        { "augments", registry.isOpen("augments") },
        { "augmentUtility", registry.isOpen("augmentUtility") },
        { "itemDisplay", registry.isOpen("itemDisplay") },
        { "aa", registry.isOpen("aa") },
        { "reroll", registry.isOpen("reroll") },
        { "loot", uiState.lootUIOpen },
    }
    local bestName, bestT = nil, -1
    for _, c in ipairs(candidates) do
        local nam, open = c[1], c[2]
        if open and at[nam] and at[nam] > bestT then
            bestT = at[nam]
            bestName = nam
        end
    end
    return bestName
end

-- Sell status service: init and local aliases (delegated to services/sell_status.lua)
sellStatusService.init({ perfCache = perfCache, rules = rules, storage = storage, C = C, getRerollListProtection = function() return rerollService.getRerollListProtection() end })
local function loadSellConfigCache() sellStatusService.loadSellConfigCache() end

-- ============================================================================
-- Layout Management (Phase 7: Delegated to utils/layout.lua)
-- ============================================================================
local function saveLayoutToFileImmediate() layoutUtils.saveLayoutToFileImmediate() end
local function flushLayoutSave() layoutUtils.flushLayoutSave() end
local function saveLayoutToFile() layoutUtils.saveLayoutToFile() end
local function loadLayoutConfig()
    layoutUtils.loadLayoutConfig()
    registry.applyEnabledFromLayout(layoutConfig)
end
local function saveLayoutForView(view, w, h, bankPanelW) layoutUtils.saveLayoutForView(view, w, h, bankPanelW) end

-- Onboarding (first-run welcome panel): cache so we don't read INI every frame
local onboardingCompleteCache = nil -- nil = not yet read, true = complete, false = show panel
local function getOnboardingComplete()
    if onboardingCompleteCache == nil then
        local v = config.readINIValue("coopui_onboarding.ini", "Onboarding", "onboarding_complete", "FALSE")
        onboardingCompleteCache = (v == "TRUE")
    end
    return onboardingCompleteCache
end
local function setOnboardingComplete()
    config.writeINIValue("coopui_onboarding.ini", "Onboarding", "onboarding_complete", "TRUE")
    onboardingCompleteCache = true
end
local function resetOnboarding()
    config.writeINIValue("coopui_onboarding.ini", "Onboarding", "onboarding_complete", "FALSE")
    onboardingCompleteCache = false
end

-- sortOnly: when true (inv only), do not clear invTotalSlots/invTotalValue so "Items: x/y" and total value don't force recompute
-- Invalidation sets _invalid so getSortedList will recompute; we keep sorted/key/dir/etc. so incremental update can run when only one item changed.
local function invalidateSortCache(view, sortOnly)
    local c = view == "inv" and perfCache.inv or view == "sell" and perfCache.sell or view == "bank" and perfCache.bank or view == "loot" and perfCache.loot
    if c then c._invalid = true end
    if view == "inv" and not sortOnly then perfCache.invTotalSlots = nil; perfCache.invTotalValue = nil; scanState.inventoryBagsDirty = true end
end

-- Window state queries (delegated to utils/window_state.lua)
local function isBankWindowOpen() return windowState.isBankWindowOpen() end
local function isMerchantWindowOpen() return windowState.isMerchantWindowOpen() end
local function isLootWindowOpen() return windowState.isLootWindowOpen() end
local function closeGameInventoryIfOpen() windowState.closeGameInventoryIfOpen() end
local function closeGameMerchantIfOpen() windowState.closeGameMerchantIfOpen() end

-- buildItemFromMQ delegated to utils/item_helpers.lua (optional 4th arg source: "inv" | "bank")
local function buildItemFromMQ(item, bag, slot, source) return itemHelpers.buildItemFromMQ(item, bag, slot, source) end

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
        invalidateTooltipCache = function()
            local tt = require('itemui.utils.item_tooltip')
            if tt and tt.invalidateTooltipCache then tt.invalidateTooltipCache() end
        end,
        buildAugmentIndex = function() itemHelpers.buildAugmentIndex(inventoryItems, bankItems or bankCache) end,
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
        getRerollListProtection = function() return rerollService.getRerollListProtection() end,
    }
    scanService.init(scanEnv)
end
local function scanInventory() scanService.scanInventory() end
local function scanBank() scanService.scanBank() end
local function scanSellItems() scanService.scanSellItems() end
local function scanLootItems() scanService.scanLootItems() end
local function maybeScanInventory(invOpen) scanService.maybeScanInventory(invOpen) end
local function rescanInventoryBags(bagList) scanService.rescanInventoryBags(bagList) end
local function maybeScanBank(bankOpen) scanService.maybeScanBank(bankOpen) end
local function maybeScanSellItems(merchOpen) scanService.maybeScanSellItems(merchOpen) end
local function maybeScanLootItems(lootOpen) scanService.maybeScanLootItems(lootOpen) end

-- Equipment cache: refresh when Equipment Companion window is visible (Phase 2). Slots 0-22; cache index = slotIndex + 1.
local function refreshEquipmentCache()
    for slotIndex = 0, 22 do
        local it = itemHelpers.getItemTLO(0, slotIndex, "equipped")
        local ok, id = pcall(function() return it and it.ID and it.ID() end)
        if not ok or not id or id == 0 then
            equipmentCache[slotIndex + 1] = nil
        else
            equipmentCache[slotIndex + 1] = buildItemFromMQ(it, 0, slotIndex, "equipped")
        end
    end
end

-- Item operations: init and local aliases (delegated to services/item_ops.lua)
itemOps.init({
    inventoryItems = inventoryItems, bankItems = bankItems, sellItems = sellItems, lootItems = lootItems, bankCache = bankCache,
    perfCache = perfCache, uiState = uiState, scanState = scanState,
    sellStatus = sellStatusService, isBankWindowOpen = isBankWindowOpen, isMerchantWindowOpen = isMerchantWindowOpen,
    invalidateSortCache = invalidateSortCache, setStatusMessage = setStatusMessage, storage = storage,
    getItemSpellId = getItemSpellId,
    getEquipmentSlotNameForItemNotify = function(slotIndex) return itemHelpers.getEquipmentSlotNameForItemNotify(slotIndex) end,
    scanBank = function() scanService.scanBank() end,
    scanInventory = function() scanService.scanInventory() end,
    maybeScanInventory = maybeScanInventory,
    rescanInventoryBags = rescanInventoryBags,
})
rerollService.init({
    setStatusMessage = setStatusMessage,
    getRerollListStoragePath = function()
        local me = mq.TLO and mq.TLO.Me
        local name = me and me.Name and me.Name()
        if not name or name == "" then return nil end
        return config.getCharStoragePath(name, "reroll_lists.lua")
    end,
})
augmentOps.init({
    setStatusMessage = setStatusMessage,
    getItemTLO = function(bag, slot, source) return itemHelpers.getItemTLO(bag, slot, source) end,
    scanInventory = function() scanService.scanInventory() end,
    scanBank = function() scanService.scanBank() end,
    isBankWindowOpen = isBankWindowOpen,
    hasItemOnCursor = function() return itemOps.hasItemOnCursor() end,
    setWaitingForRemoveConfirmation = function(v) uiState.waitingForRemoveConfirmation = v end,
    setWaitingForInsertConfirmation = function(v) uiState.waitingForInsertConfirmation = v end,
})
local function processSellQueue() itemOps.processSellQueue() end
local function hasItemOnCursor()
    if uiState.hasItemOnCursorThisFrame ~= nil then return uiState.hasItemOnCursorThisFrame end
    return itemOps.hasItemOnCursor()
end
local function removeItemFromCursor() return itemOps.removeItemFromCursor() end
local function putCursorInBags() return itemOps.putCursorInBags() end

-- Single path for sell list changes: update INI, rows, and stored inventory so all views stay in sync
local function applySellListChange(itemName, inKeep, inJunk)
    if inKeep then addToKeepList(itemName) else removeFromKeepList(itemName) end
    if inJunk then addToJunkList(itemName) else removeFromJunkList(itemName) end
    itemOps.updateSellStatusForItemName(itemName, inKeep, inJunk)
    if storage and inventoryItems then storage.saveInventory(inventoryItems) end
end

-- Reroll list add: if cursor occupied we abort with clear message (CoOpt UI pattern: don't move user's item without consent).
-- Otherwise pickup -> send !augadd/!mythicaladd -> main_loop waits for ack or timeout -> put back; status feedback during flow.
-- Guard: only one add-in-progress at a time (avoid double-click / concurrent pickup).
local function requestAddToRerollList(list, item)
    if not item or (list ~= "aug" and list ~= "mythical") then return end
    if uiState.pendingRerollAdd then
        setStatusMessage("Add already in progress.")
        return
    end
    if hasItemOnCursor() then
        setStatusMessage("Clear cursor first.")
        return
    end
    local source = item.source or "inv"
    uiState.pendingRerollAdd = {
        list = list,
        bag = item.bag,
        slot = item.slot,
        source = source,
        itemId = item.id or item.ID,
        itemName = item.name or "",
        step = "pickup",
    }
    itemOps.pickupFromSlot(item.bag, item.slot, source)
    setStatusMessage("Adding to list...")
end

-- Reroll list remove: no pickup needed; send !augremove/!mythicalremove and update cache; invalidate sell/loot caches.
local function removeFromRerollList(list, id)
    if not id or (list ~= "aug" and list ~= "mythical") then return end
    if list == "aug" then rerollService.removeAug(id) else rerollService.removeMythical(id) end
    sellStatusService.invalidateSellConfigCache()
    sellStatusService.invalidateLootConfigCache()
    if computeAndAttachSellStatus and inventoryItems and #inventoryItems > 0 then computeAndAttachSellStatus(inventoryItems) end
    if computeAndAttachSellStatus and bankItems and #bankItems > 0 then computeAndAttachSellStatus(bankItems) end
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
    removeLootItemBySlot = itemOps.removeLootItemBySlot,
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

local function getItemStatsForTooltipRef(item, source)
    if not item or item.slot == nil then return item end
    local bag = (item.bag ~= nil) and item.bag or 0
    local it = itemHelpers.getItemTLO(bag, item.slot, source or "inv")
    if not it or not it.ID or it.ID() == 0 then return item end
    return itemHelpers.buildItemFromMQ(it, bag, item.slot, source or "inv")
end
--- Phase 0: refresh active Item Display tab's item from TLO (call after scan when augment insert/remove completes).
local function refreshActiveItemDisplayTab()
    local tabs = uiState.itemDisplayTabs
    if not tabs or #tabs == 0 then return end
    local aidx = uiState.itemDisplayActiveTabIndex or 1
    if aidx < 1 or aidx > #tabs then return end
    local tab = tabs[aidx]
    if not tab or tab.bag == nil or tab.slot == nil then return end
    local fresh = getItemStatsForTooltipRef({ bag = tab.bag, slot = tab.slot }, tab.source or "inv")
    if fresh then tab.item = fresh end
end
local function addItemDisplayTab(item, source)
    if not item or item.slot == nil then return end
    source = source or "inv"
    local showItem = getItemStatsForTooltipRef(item, source) or item
    local label = (showItem.name and showItem.name ~= "") and showItem.name:sub(1, 35) or "Item"
    if #label == 35 and (showItem.name or ""):len() > 35 then label = label .. "…" end
    -- If this item already has a tab, switch to it instead of adding a duplicate
    for idx, tab in ipairs(uiState.itemDisplayTabs) do
        if tab.bag == item.bag and tab.slot == item.slot and tab.source == source then
            tab.item = showItem
            tab.label = label
            uiState.itemDisplayActiveTabIndex = idx
            uiState.removeAllQueue = nil   -- Phase 1: tab switched
            uiState.optimizeQueue = nil    -- Phase 2: tab switched
            local recentEntry = { bag = item.bag, slot = item.slot, source = source, label = label }
            local recent = uiState.itemDisplayRecent
            for i = #recent, 1, -1 do
                if recent[i].bag == item.bag and recent[i].slot == item.slot and recent[i].source == source then
                    table.remove(recent, i)
                    break
                end
            end
            table.insert(recent, 1, recentEntry)
            while #recent > constants.LIMITS.ITEM_DISPLAY_RECENT_MAX do table.remove(recent) end
            uiState.itemDisplayWindowOpen = true
            uiState.itemDisplayWindowShouldDraw = true
            recordCompanionWindowOpened("itemDisplay")
            return
        end
    end
    uiState.itemDisplayTabs[#uiState.itemDisplayTabs + 1] = {
        bag = item.bag, slot = item.slot, source = source, item = showItem, label = label,
    }
    uiState.itemDisplayActiveTabIndex = #uiState.itemDisplayTabs
    uiState.removeAllQueue = nil   -- Phase 1: new tab added
    uiState.optimizeQueue = nil    -- Phase 2: new tab added
    -- Recent: prepend, dedupe by bag/slot/source, cap at N
    local recentEntry = { bag = item.bag, slot = item.slot, source = source, label = label }
    local recent = uiState.itemDisplayRecent
    for i = #recent, 1, -1 do
        if recent[i].bag == item.bag and recent[i].slot == item.slot and recent[i].source == source then
            table.remove(recent, i)
            break
        end
    end
    table.insert(recent, 1, recentEntry)
    while #recent > constants.LIMITS.ITEM_DISPLAY_RECENT_MAX do table.remove(recent) end
    uiState.itemDisplayWindowOpen = true
    uiState.itemDisplayWindowShouldDraw = true
    recordCompanionWindowOpened("itemDisplay")
end

context_builder.init({
    -- State tables
    uiState = uiState, sortState = sortState, filterState = filterState,
    layoutConfig = layoutConfig, perfCache = perfCache, sellMacState = sellMacState,
    -- Data tables
    inventoryItems = inventoryItems, bankItems = bankItems, lootItems = lootItems,
    sellItems = sellItems, bankCache = bankCache, equipmentCache = equipmentCache,
    -- Config
    configLootLists = configLootLists, config = config,
    columnAutofitWidths = columnAutofitWidths, availableColumns = availableColumns,
    columnVisibility = columnVisibility,
    configSellFlags = configSellFlags, configSellValues = configSellValues, configSellLists = configSellLists,
    configLootFlags = configLootFlags, configLootValues = configLootValues,
    configLootSorting = configLootSorting, configEpicClasses = configEpicClasses,
    EPIC_CLASSES = rules.EPIC_CLASSES,
    -- Window state (prefer flat API for consistency)
    windowState = windowStateAPI,
    isBankWindowOpen = isBankWindowOpen,
    isMerchantWindowOpen = isMerchantWindowOpen,
    -- Scan functions
    scanInventory = scanInventory, scanBank = scanBank,
    scanSellItems = scanSellItems, scanLootItems = scanLootItems,
    refreshAllScans = function()
        scanInventory()
        if isBankWindowOpen() then scanBank() end
        if isMerchantWindowOpen() then scanSellItems() end
        if isLootWindowOpen() then scanLootItems() end
        setStatusMessage("Refreshed")
    end,
    maybeScanInventory = maybeScanInventory, maybeScanSellItems = maybeScanSellItems,
    maybeScanLootItems = maybeScanLootItems,
    ensureBankCacheFromStorage = function() scanService.ensureBankCacheFromStorage() end,
    refreshEquipmentCache = refreshEquipmentCache,
    -- Config cache (event-driven: views emit events, sell_status subscribes)
    invalidateLootConfigCache = function() sellStatusService.invalidateLootConfigCache() end,
    invalidateSellConfigCache = function() sellStatusService.invalidateSellConfigCache() end,
    loadConfigCache = loadConfigCache,
    -- UI helpers (always present so views can call without guards)
    setStatusMessage = setStatusMessage or function() end,
    closeItemUI = closeItemUI,
    renderRefreshButton = function(ctx, id, tooltip, onRefresh, opts) return ui_common.renderRefreshButton(ctx, id, tooltip, onRefresh, opts) end,
    getSellStatusNameColor = function(ctx, item) return ui_common.getSellStatusNameColor(ctx, item) end,
    renderItemContextMenu = function(ctx, item, opts) return ui_common.renderItemContextMenu(ctx, item, opts) end,
    -- Layout (module direct)
    saveLayoutToFile = function() layoutUtils.saveLayoutToFile() end,
    scheduleLayoutSave = function() layoutUtils.scheduleLayoutSave() end, flushLayoutSave = flushLayoutSave,
    saveColumnVisibility = function() layoutUtils.saveColumnVisibility() end,
    loadLayoutConfig = loadLayoutConfig,
    captureCurrentLayoutAsDefault = function() layoutUtils.captureCurrentLayoutAsDefault() end,
    resetLayoutToDefault = function() layoutUtils.resetLayoutToDefault() end,
    revertToBundledDefaultLayoutRequest = function() uiState.revertLayoutConfirmOpen = true end,
    resetOnboarding = resetOnboarding,
    getFixedColumns = function(v) return layoutUtils.getFixedColumns(v) end,
    toggleFixedColumn = function(v, k) return layoutUtils.toggleFixedColumn(v, k) end,
    isColumnInFixedSet = function(v, k) return layoutUtils.isColumnInFixedSet(v, k) end,
    -- Item ops (module direct; always present so views can call without guards; Phase 2: use frame cache when set)
    hasItemOnCursor = function()
        if uiState.hasItemOnCursorThisFrame ~= nil then return uiState.hasItemOnCursorThisFrame end
        return itemOps.hasItemOnCursor()
    end,
    removeItemFromCursor = function() return itemOps.removeItemFromCursor() end,
    putCursorInBags = function() return itemOps.putCursorInBags() end,
    moveBankToInv = function(b, s) return itemOps.moveBankToInv(b, s) end,
    moveInvToBank = function(b, s) return itemOps.moveInvToBank(b, s) end,
    countFreeInvSlots = function() return itemOps.countFreeInvSlots() end,
    shouldHideRowForCursor = function(item, source) return itemOps.shouldHideRowForCursor(item, source) end,
    pickupFromSlot = function(bag, slot, source) return itemOps.pickupFromSlot(bag, slot, source) end,
    dropAtSlot = function(bag, slot, source) return itemOps.dropAtSlot(bag, slot, source) end,
    queueItemForSelling = function(d) return itemOps.queueItemForSelling(d) end,
    updateSellStatusForItemName = function(n, k, j) itemOps.updateSellStatusForItemName(n, k, j) end,
    applySellListChange = applySellListChange,
    setPendingDestroy = function(p)
        uiState.pendingDestroy = p
        local sz = (p and p.stackSize) and p.stackSize or 1
        uiState.destroyQuantityMax = sz
        uiState.destroyQuantityValue = tostring(sz)
    end,
    requestDestroyItem = function(bag, slot, name, stackSize)
        local qty = (stackSize and stackSize > 0) and stackSize or 1
        uiState.pendingDestroyAction = { bag = bag, slot = slot, name = name or "", qty = qty }
        uiState.pendingDestroy = nil
        uiState.destroyQuantityValue = ""
        uiState.destroyQuantityMax = 1
    end,
    getSkipConfirmDelete = function() return not uiState.confirmBeforeDelete end,
    -- Config list APIs
    addToKeepList = addToKeepList, removeFromKeepList = removeFromKeepList,
    addToJunkList = addToJunkList, removeFromJunkList = removeFromJunkList,
    augmentLists = augmentListAPI,
    requestAddToRerollList = requestAddToRerollList,
    removeFromRerollList = removeFromRerollList,
    addToLootSkipList = addToLootSkipList, removeFromLootSkipList = removeFromLootSkipList,
    isInLootSkipList = isInLootSkipList,
    -- Sort/columns (Phase 3: shared sort+cache helper)
    sortColumns = sortColumnsAPI,
    getSortedList = function(cache, filtered, sortKey, sortDir, validity, viewName, sortCols)
        return tableCache.getSortedList(cache, filtered, sortKey, sortDir, validity, viewName, sortCols or sortColumnsAPI)
    end,
    getColumnKeyByIndex = columns.getColumnKeyByIndex, autofitColumns = columns.autofitColumns,
    -- Item helpers (module direct)
    formatCurrency = function(copper) return itemHelpers.formatCurrency(copper) end,
    getSpellName = function(id) return itemHelpers.getSpellName(id) end,
    getSpellDescription = function(id) return itemHelpers.getSpellDescription(id) end,
    getSpellCastTime = function(id) return itemHelpers.getSpellCastTime(id) end,
    getSpellRecastTime = function(id) return itemHelpers.getSpellRecastTime(id) end,
    getSpellDuration = function(id) return itemHelpers.getSpellDuration(id) end,
    getSpellRecoveryTime = function(id) return itemHelpers.getSpellRecoveryTime(id) end,
    getSpellRange = function(id) return itemHelpers.getSpellRange(id) end,
    getItemSpellId = function(i, p) return itemHelpers.getItemSpellId(i, p) end,
    getItemLoreText = function(it) return itemHelpers.getItemLoreText(it) end,
    getTimerReady = function(b, s, src) return itemHelpers.getTimerReady(b, s, src) end,
    getMaxRecastForSlot = function(b, s, src) return itemHelpers.getMaxRecastForSlot(b, s, src) end,
    getItemStatsSummary = function(i) return itemHelpers.getItemStatsSummary(i) end,
    getItemStatsForTooltip = getItemStatsForTooltipRef,
    addItemDisplayTab = addItemDisplayTab,
    getItemTLO = function(bag, slot, source) return itemHelpers.getItemTLO(bag, slot, source) end,
    getAugSlotsCountFromTLO = function(it) return itemHelpers.getAugSlotsCountFromTLO(it) end,
    getStandardAugSlotsCountFromTLO = function(it) return itemHelpers.getStandardAugSlotsCountFromTLO(it) end,
    getFilledStandardAugmentSlotIndices = function(bag, slot, source)
        local it = itemHelpers.getItemTLO(bag, slot, source or "inv")
        return it and itemHelpers.getFilledStandardAugmentSlotIndices(it) or {}
    end,
    itemHasOrnamentSlot = function(it) return itemHelpers.itemHasOrnamentSlot(it) end,
    getSlotType = function(it, slotIndex) return itemHelpers.getSlotType(it, slotIndex) end,
    getParentWeaponInfo = function(it) return itemHelpers.getParentWeaponInfo(it) end,
    getEquipmentSlotLabel = function(slotIndex) return itemHelpers.getEquipmentSlotLabel(slotIndex) end,
    getEquipmentSlotNameForItemNotify = function(slotIndex) return itemHelpers.getEquipmentSlotNameForItemNotify(slotIndex) end,
    getCompatibleAugments = function(entryOrItem, slotIndex, options)
        local entry = type(entryOrItem) == "table" and entryOrItem.bag and entryOrItem.slot and entryOrItem.item and entryOrItem or nil
        local item = entry and entry.item or entryOrItem
        local bag = entry and entry.bag or (entryOrItem and entryOrItem.bag)
        local slot = entry and entry.slot or (entryOrItem and entryOrItem.slot)
        local src = entry and entry.source or (entryOrItem and entryOrItem.source) or "inv"
        if not item or not slotIndex then return {} end
        local bankList = isBankWindowOpen() and bankItems or bankCache
        local canUseFilter = (options and type(options.canUseFilter) == "function") and options.canUseFilter or nil
        return itemHelpers.getCompatibleAugments(item, bag, slot, src, slotIndex, inventoryItems, bankList, canUseFilter)
    end,
    insertAugment = function(targetItem, augmentItem, slotIndex, targetLocation)
        if not targetItem or not augmentItem then return end
        uiState.pendingInsertAugment = {
            targetItem = { id = targetItem.id or targetItem.ID, name = targetItem.name or targetItem.Name },
            targetBag = targetLocation and targetLocation.bag,
            targetSlot = targetLocation and targetLocation.slot,
            targetSource = (targetLocation and targetLocation.source) or "inv",
            augmentItem = { bag = augmentItem.bag, slot = augmentItem.slot, source = augmentItem.source or "inv", name = augmentItem.name or "augment" },
            slotIndex = (type(slotIndex) == "number" and slotIndex >= 1 and slotIndex <= 6) and slotIndex or nil,
        }
    end,
    removeAugment = function(bag, slot, source, slotIndex)
        uiState.pendingRemoveAugment = { bag = bag, slot = slot, source = source, slotIndex = slotIndex }
    end,
    getSellStatusForItem = function(i) return sellStatusService.getSellStatusForItem(i) end,
    drawItemIcon = function(id, size) icons.drawItemIcon(id, size) end,
    drawEmptySlotIcon = function() icons.drawEmptySlotIcon() end,
    rerollService = rerollService,
    -- Services
    theme = theme, macroBridge = macroBridge,
})

local defaultLayoutAppliedThisRun = false

local mainWindowRefs = {
    getShouldDraw = function() return shouldDraw end,
    setShouldDraw = function(v) shouldDraw = v end,
    getOpen = function() return isOpen end,
    setOpen = function(v) isOpen = v end,
    layoutConfig = layoutConfig,
    layoutDefaults = layoutDefaults,
    saveLayoutToFile = saveLayoutToFile,
    saveLayoutForView = saveLayoutForView,
    loadLayoutConfig = loadLayoutConfig,
    getMostRecentlyOpenedCompanion = getMostRecentlyOpenedCompanion,
    closeCompanionWindow = closeCompanionWindow,
    closeGameInventoryIfOpen = closeGameInventoryIfOpen,
    closeGameMerchantIfOpen = closeGameMerchantIfOpen,
    recordCompanionWindowOpened = recordCompanionWindowOpened,
    setStatusMessage = setStatusMessage,
    CharacterStats = CharacterStats,
    hasItemOnCursor = hasItemOnCursor,
    removeItemFromCursor = function() return itemOps.removeItemFromCursor() end,
    putCursorInBags = function() return itemOps.putCursorInBags() end,
    theme = theme,
    uiState = uiState,
    sellMacState = sellMacState,
    C = C,
    mq = mq,
    refreshEquipmentCache = refreshEquipmentCache,
    scanInventory = scanInventory,
    isMerchantWindowOpen = isMerchantWindowOpen,
    isBankWindowOpen = isBankWindowOpen,
    isLootWindowOpen = isLootWindowOpen,
    itemOps = itemOps,
    loadLootHistoryFromFile = loadLootHistoryFromFile,
    loadSkipHistoryFromFile = loadSkipHistoryFromFile,
    lootLoopRefs = lootLoopRefs,
    config = config,
    sellItems = sellItems,
    maybeScanInventory = maybeScanInventory,
    maybeScanSellItems = maybeScanSellItems,
    maybeScanBank = maybeScanBank,
    -- Onboarding (first-run welcome panel)
    getOnboardingComplete = getOnboardingComplete,
    setOnboardingComplete = setOnboardingComplete,
    resetOnboarding = resetOnboarding,
    defaultLayoutAppliedThisRun = function() return defaultLayoutAppliedThisRun end,
    -- Setup wizard (Task 5.4): config cache, epic classes, default layout
    configSellFlags = configSellFlags,
    configLootFlags = configLootFlags,
    configLootValues = configLootValues,
    configEpicClasses = configEpicClasses,
    EPIC_CLASSES = rules.EPIC_CLASSES,
    loadConfigCache = loadConfigCache,
    invalidateSellConfigCache = function() sellStatusService.invalidateSellConfigCache() end,
    invalidateLootConfigCache = function() sellStatusService.invalidateLootConfigCache() end,
    defaultLayoutHasExistingLayout = function() return defaultLayout.hasExistingLayout() end,
    applyBundledDefaultLayout = function() return defaultLayout.applyBundledDefaultLayout() end,
    scheduleLayoutSave = function() layoutUtils.scheduleLayoutSave() end,
    classLabel = function(cls) return ConfigFilters.classLabel(cls) end,
    addItemDisplayTab = addItemDisplayTab,
    equipmentCache = equipmentCache,
    inventoryItems = inventoryItems,
}


-- ============================================================================
-- Commands & main
-- ============================================================================
--- Read sell engine mode from sell_flags.ini. Returns "macro" or "lua". Default macro.
local function getSellMode()
    local v = (config.readINIValue and config.readINIValue("sell_flags.ini", "Settings", "sellMode", "macro")) or "macro"
    v = (v or ""):lower()
    if v == "lua" then return "lua" end
    return "macro"
end

--- Legacy path: write sell cache and progress, then run sell.mac (unchanged behavior).
local function runSellMacroLegacy()
    scanInventory()
    if isMerchantWindowOpen() then scanSellItems() end
    if #inventoryItems > 0 then
        if not scanState.sellStatusAttachedAt then
            computeAndAttachSellStatus(inventoryItems)
            scanState.sellStatusAttachedAt = mq.gettime()
        end
        storage.ensureCharFolderExists()
        storage.saveInventory(inventoryItems)
        storage.writeSellCache(inventoryItems)
    end
    local count = 0
    for _, it in ipairs(sellItems) do if it.willSell then count = count + 1 end end
    if count >= 0 and macroBridge.writeSellProgress then
        macroBridge.writeSellProgress(count, 0)
    end
    mq.cmd('/macro sell confirm')
end

--- Dispatch sell: by sellMode or forceMode ("macro" | "lua"). /dosell and Auto Sell use getSellMode(); /itemui sell legacy|lua overrides.
local function runSellMacro(forceMode)
    if sellBatch.isRunning() then
        setStatusMessage("Sell already in progress.")
        return
    end
    local mode = forceMode or getSellMode()
    if mode == "lua" then
        scanInventory()
        if isMerchantWindowOpen() then scanSellItems() end
        if #inventoryItems > 0 then computeAndAttachSellStatus(inventoryItems) end
        local list = {}
        for _, it in ipairs(sellItems) do
            if it.willSell then list[#list + 1] = it end
        end
        if sellBatch.startBatch(list) then
            setStatusMessage("Selling...")
        end
    else
        runSellMacroLegacy()
        setStatusMessage("Running sell macro...")
    end
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
            uiState.equipmentWindowOpen = true
            uiState.equipmentWindowShouldDraw = true
            recordCompanionWindowOpened("equipment")
        else
            closeGameInventoryIfOpen()
        end
    elseif cmd == "show" then
        shouldDraw, isOpen = true, true
        local _w = mq.TLO and mq.TLO.Window and mq.TLO.Window("InventoryWindow")
        local invO, bankO, merchO = (_w and _w.Open and _w.Open()) or false, isBankWindowOpen(), isMerchantWindowOpen()
        loadLayoutConfig()
        maybeScanInventory(invO); maybeScanBank(bankO); maybeScanSellItems(merchO)
        uiState.equipmentWindowOpen = true
        uiState.equipmentWindowShouldDraw = true
        recordCompanionWindowOpened("equipment")
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
        if uiState.setupMode then
            uiState.setupStep = 0
            loadConfigCache()
            loadLayoutConfig()
        else
            uiState.setupStep = 0
        end
        shouldDraw = true
        isOpen = true
        print(uiState.setupMode and "\ag[ItemUI]\ax Setup: Step 0 of 8 — Epic protection (optional), then layout and rules." or "\ar[ItemUI]\ax Setup off.")
    elseif cmd == "config" then
        uiState.configWindowOpen = true
        uiState.configNeedsLoad = true
        recordCompanionWindowOpened("config")
        shouldDraw = true
        isOpen = true
        print("\ag[ItemUI]\ax Config window opened.")
    elseif cmd == "onboarding" then
        resetOnboarding()
        shouldDraw = true
        isOpen = true
        mq.cmd("/keypress inventory")
        print("\ag[ItemUI]\ax Welcome panel will show in the main window.")
    elseif cmd == "reroll" then
        if not registry.isOpen("reroll") then registry.toggleWindow("reroll") end
        if registry.isOpen("reroll") then recordCompanionWindowOpened("reroll") end
        shouldDraw = true
        isOpen = true
        print("\ag[ItemUI]\ax Reroll Companion opened.")
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
    elseif cmd == "sell" or (cmd:sub(1, 5) == "sell " and #cmd > 5) then
        local args = {...}
        local sub = (cmd == "sell" and args[2]) and (tostring(args[2])):lower() or (cmd:match("^sell%s+(%S+)") or ""):lower()
        if sub == "legacy" then
            runSellMacro("macro")
        elseif sub == "lua" then
            runSellMacro("lua")
        else
            print("\ag[ItemUI]\ax /itemui sell legacy = run sell.mac  |  /itemui sell lua = run Lua sell")
        end
    elseif cmd == "help" then
        print("\ag[ItemUI]\ax /itemui or /inv or /inventoryui [toggle|show|hide|refresh|setup|config|onboarding|reroll|exit|help]")
        print("  setup = resize and save window/column layout for Inventory, Sell, and Inventory+Bank")
        print("  config = open ItemUI & Loot settings (or click Settings in the header)")
        print("  onboarding = show the first-run welcome panel again")
        print("  reroll = open Reroll Companion (augment and mythical reroll lists)")
        print("  exit  = unload ItemUI completely")
        print("  sell legacy = run sell.mac  |  sell lua = run Lua sell (see sell_flags.ini sellMode)")
        print("\ag[ItemUI]\ax /dosell = run sell (macro or Lua per sellMode)  |  /doloot = run loot.mac")
    else
        print("\ar[ItemUI]\ax Unknown: " .. cmd .. " — use /itemui help")
    end
end

local function buildMainLoopDeps()
    return {
        uiState = uiState,
        layoutConfig = layoutConfig,
        scanState = scanState,
        sellMacState = sellMacState,
        lootMacState = lootMacState,
        lootLoopRefs = lootLoopRefs,
        perfCache = perfCache,
        macroBridge = macroBridge,
        deferredScanNeeded = deferredScanNeeded,
        inventoryItems = inventoryItems,
        sellItems = sellItems,
        bankItems = bankItems,
        bankCache = bankCache,
        C = C,
        LOOT_HISTORY_MAX = constants.LIMITS.LOOT_HISTORY_MAX,
        STATS_TAB_PRIME_MS = constants.TIMING.STATS_TAB_PRIME_MS,
        Cache = Cache,
        getShouldDraw = function() return shouldDraw end,
        setShouldDraw = function(v) shouldDraw = v end,
        getOpen = function() return isOpen end,
        setOpen = function(v) isOpen = v end,
        getLastInventoryWindowState = function() return lastInventoryWindowState end,
        setLastInventoryWindowState = function(v) lastInventoryWindowState = v end,
        getLastBankWindowState = function() return lastBankWindowState end,
        setLastBankWindowState = function(v) lastBankWindowState = v end,
        getLastMerchantState = function() return lastMerchantState end,
        setLastMerchantState = function(v) lastMerchantState = v end,
        getLastLootWindowState = function() return lastLootWindowState end,
        setLastLootWindowState = function(v) lastLootWindowState = v end,
        getStatsTabPrimeState = function() return statsTabPrimeState end,
        setStatsTabPrimeState = function(v) statsTabPrimeState = v end,
        getStatsTabPrimeAt = function() return statsTabPrimeAt end,
        setStatsTabPrimeAt = function(v) statsTabPrimeAt = v end,
        getStatsTabPrimedThisSession = function() return statsTabPrimedThisSession end,
        setStatsTabPrimedThisSession = function(v) statsTabPrimedThisSession = v end,
        clearLootItems = clearLootItems,
        setStatusMessage = setStatusMessage,
        storage = storage,
        computeAndAttachSellStatus = computeAndAttachSellStatus,
        isBankWindowOpen = isBankWindowOpen,
        runSellMacro = runSellMacro,
        getSellMode = getSellMode,
        runSellMacroLegacy = runSellMacroLegacy,
        sellBatch = sellBatch,
        config = config,
        loadLootHistoryFromFile = loadLootHistoryFromFile,
        loadSkipHistoryFromFile = loadSkipHistoryFromFile,
        getSellStatusForItem = getSellStatusForItem,
        processSellQueue = processSellQueue,
        itemOps = itemOps,
        augmentOps = augmentOps,
        hasItemOnCursor = hasItemOnCursor,
        maybeScanInventory = maybeScanInventory,
        maybeScanBank = maybeScanBank,
        maybeScanSellItems = maybeScanSellItems,
        sellStatusService = sellStatusService,
        flushLayoutSave = flushLayoutSave,
        loadLayoutConfig = loadLayoutConfig,
        recordCompanionWindowOpened = recordCompanionWindowOpened,
        isMerchantWindowOpen = isMerchantWindowOpen,
        isLootWindowOpen = isLootWindowOpen,
        invalidateSortCache = invalidateSortCache,
        scanInventory = scanInventory,
        scanBank = scanBank,
        scanSellItems = scanSellItems,
        rescanInventoryBags = rescanInventoryBags,
        refreshActiveItemDisplayTab = refreshActiveItemDisplayTab,
        saveLayoutToFileImmediate = saveLayoutToFileImmediate,
        removeItemFromCursor = removeItemFromCursor,
        invalidateSellConfigCache = function() sellStatusService.invalidateSellConfigCache() end,
        invalidateLootConfigCache = function() sellStatusService.invalidateLootConfigCache() end,
        rerollService = rerollService,
    }
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
    mq.bind('/doloot', function()
        if not uiState.suppressWhenLootMac then
            uiState.lootUIOpen = true
            uiState.lootRunFinished = false
            recordCompanionWindowOpened("loot")
        end
        mq.cmd('/macro loot')
    end)
    mq.imgui.init('ItemUI', function() MainWindow.render(mainWindowRefs) end)
    do
        local p = mq.TLO.MacroQuest and mq.TLO.MacroQuest.Path and mq.TLO.MacroQuest.Path()
        if p and p ~= "" then
            transferStampPath = p .. "\\bankinv_refresh.txt"
            itemOps.setTransferStampPath(transferStampPath)
            -- Use backslashes to match sell.mac path (MacroQuest.Path may use / or \)
            perfCache.sellLogPath = (p:gsub("/", "\\")) .. "\\Macros\\logs\\item_management"
        end
    end
    macroBridge.init({
        sellLogPath = perfCache.sellLogPath,
        getLootConfigFile = config.getLootConfigFile,
        pollInterval = 500,
    })
    while not (mq.TLO and mq.TLO.Me and mq.TLO.Me.Name and mq.TLO.Me.Name()) do mq.delay(1000) end
    -- First-run: apply bundled default layout if user has no existing layout (layout only; no user data)
    if not defaultLayout.hasExistingLayout() then
        local ok, err = defaultLayout.applyBundledDefaultLayout()
        if ok then
            defaultLayoutAppliedThisRun = true
        elseif err and err ~= "" then
            if print then print("\ar[ItemUI]\ax First-run default layout: " .. tostring(err)) end
            local diag = require('itemui.core.diagnostics')
            diag.recordError("First-run layout", "Default layout apply failed", err)
        end
    end
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

    local d = buildMainLoopDeps()
    mainLoop.init(d)
    sellBatch.init(d)
    while not terminate do
        mainLoop.tick(mq.gettime())
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

return { runMain = main }
