--[[
    CoOpt UI Inventory Companion
    Purpose: Unified Inventory / Bank / Sell / Loot Interface
    Part of CoOpt UI — EverQuest EMU Companion
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
local mainLoop = require('itemui.services.main_loop')

-- Phase 5: View modules
local InventoryView = require('itemui.views.inventory')
local SellView = require('itemui.views.sell')
local BankView = require('itemui.views.bank')
local EquipmentView = require('itemui.views.equipment')
local LootView = require('itemui.views.loot')
local ConfigView = require('itemui.views.config')
local LootUIView = require('itemui.views.loot_ui')
local AugmentsView = require('itemui.views.augments')
local AugmentUtilityView = require('itemui.views.augment_utility')
local ItemDisplayView = require('itemui.views.item_display')
local AAView = require('itemui.views.aa')
local aa_data = require('itemui.services.aa_data')
local rerollService = require('itemui.services.reroll_service')
local MainWindow = require('itemui.views.main_window')

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

-- Constants: built from constants module (timing, UI, limits); C table kept for init/layout/main_loop compatibility
local C = constants.buildC(CoopVersion.ITEMUI)

-- State
local isOpen, shouldDraw, terminate = true, false, false
local inventoryItems, bankItems, lootItems = {}, {}, {}
-- Equipment cache: index 1..23 maps to slot 0..22; each entry nil or item table from buildItemFromMQ(..., 0, slotIndex, "equipped")
local equipmentCache = {}
local transferStampPath, lastTransferStamp = nil, 0
local lastInventoryWindowState, lastBankWindowState, lastMerchantState, lastLootWindowState = false, false, false, false
-- Stats tab priming: only on first inventory open after ItemUI start, so AC/ATK/Weight load once
local statsTabPrimeState, statsTabPrimeAt = nil, 0
local statsTabPrimedThisSession = false  -- true after we've done the one-time Stats tab prime
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
    timerReadyMaxCache = {},  -- key "source_bag_slot" -> max seconds seen (recast delay = countdown start)
    lastScanTimeInv = 0,
    lastBankCacheTime = 0,
    sellLogPath = nil,  -- Macros/logs/item_management (set in main)
    sellConfigPendingRefresh = false,  -- debounce: run at most one row refresh per frame after CONFIG_SELL_CHANGED
    loreHaveCache = {},  -- lore item names we've confirmed we have (skip FindItem); cleared on inventory scan
}

-- Forward declaration: defined after willItemBeSold (used by scanInventory and save paths)
local computeAndAttachSellStatus
-- UI state (consolidated for Lua 200-local limit)
local uiState = {
    windowPositioned = false,
    alignToContext = true,  -- Enable snap to Inventory by default
    alignToMerchant = false,  -- NEW: Align to merchant window when in sell view
    uiLocked = true,
    syncBankWindow = false,
    suppressWhenLootMac = false,  -- when true: Loot UI does not open during looting (default false = Loot UI opens)
    itemUIPositionX = nil, itemUIPositionY = nil,
    sellViewLocked = true, invViewLocked = true, bankViewLocked = true,
    setupMode = false, setupStep = 0,
    configWindowOpen = false, configNeedsLoad = false, configAdvancedMode = false,
    revertLayoutConfirmOpen = false,
    layoutRevertedApplyFrames = 0,  -- When > 0, views use ImGuiCond.Always so positions/sizes from layoutConfig re-apply
    resetWindowPositionsRequested = false,  -- When true, main_window re-applies hub-relative positions for all companions
    searchFilterInv = "", searchFilterBank = "", searchFilterAugments = "",
    autoSellRequested = false, showOnlySellable = false,
    bankWindowOpen = false, bankWindowShouldDraw = false,
    equipmentWindowOpen = false, equipmentWindowShouldDraw = false,
    augmentsWindowOpen = false, augmentsWindowShouldDraw = false,
    itemDisplayWindowOpen = false, itemDisplayWindowShouldDraw = false,
    itemDisplayTabs = {},           -- array of { bag, slot, source, item, label }
    itemDisplayActiveTabIndex = 1,  -- 1-based index into itemDisplayTabs
    itemDisplayRecent = {},        -- last N (e.g. 10) of { bag, slot, source, label } for Recent dropdown
    itemDisplayLocateRequest = nil,      -- { source, bag, slot } when Locate clicked
    itemDisplayLocateRequestAt = nil,     -- mq.gettime() ms when set (clear after 3s)
    itemDisplayAugmentSlotActive = nil,   -- 1-based slot index when "Choose augment" is active in Item Display
    augmentUtilityWindowOpen = false, augmentUtilityWindowShouldDraw = false,
    augmentUtilitySlotIndex = 1,          -- 1-based slot for standalone Augment Utility
    searchFilterAugmentUtility = "",     -- filter compatible augments list by name
    augmentUtilityOnlyShowUsable = true, -- when true, filter list to augments current character can use (class/race/deity/level)
    companionWindowOpenedAt = {},  -- LIFO Esc: name -> mq.gettime() when opened
    statusMessage = "", statusMessageTime = 0,
    quantityPickerValue = "", quantityPickerMax = 1,
    quantityPickerSubmitPending = nil,  -- qty to submit next frame (so Enter is consumed before we clear the field)
    pendingQuantityPickup = nil, pendingQuantityPickupTimeoutAt = nil,  -- timeout: clear picker if user never completes (Phase 1 reliability)
    pendingQuantityAction = nil,
    pendingScriptConsume = nil,  -- { bag, slot, source, totalToConsume, consumedSoFar, nextClickAt, itemName } for sequential right-click (Script items)
    lastPickup = { bag = nil, slot = nil, source = nil },  -- source: "inv" | "bank"
    lastPickupSetThisFrame = false,  -- true when a view set lastPickup this frame (don't clear until next frame so item hides)
    lastPickupClearedAt = 0,         -- mq.gettime() when lastPickup was last cleared (avoids treating our own drop as "unexpected cursor")
    activationGuardUntil = 0,       -- mq.gettime() until which pickupFromSlot is blocked (click-through protection)
    hadItemOnCursorLastFrame = false,
    hasItemOnCursorThisFrame = nil,  -- Phase 2: set once per frame to avoid repeated TLO.Cursor() calls
    pendingDestroy = nil,       -- { bag, slot, name, stackSize } when Delete clicked and confirm required
    pendingDestroyAction = nil, -- { bag, slot, name, qty } for main loop to call performDestroyItem (qty = whole stack when confirm skipped)
    destroyQuantityValue = "",  -- quantity input for destroy dialog (1..stackSize)
    destroyQuantityMax = 1,     -- max allowed (stack size) while pendingDestroy is set
    confirmBeforeDelete = true, -- when true, show confirmation dialog before destroying an item (persisted in layout)
    pendingMoveAction = nil,    -- { source = "inv"|"bank", bag, slot, destBag, destSlot, qty, row } for main loop (shift+click stack move)
    pendingRemoveAugment = nil,   -- { bag, slot, source, slotIndex } for main loop (defer remove so ImGui frame completes)
    waitingForRemoveConfirmation = false,  -- true after removeAugment started; main loop auto-clicks Yes on ConfirmationDialogBox
    waitingForInsertConfirmation = false,  -- true after insertAugment started; main loop auto-clicks Yes on insert confirmation
    waitingForInsertCursorClear = false,   -- after insert confirm accepted: poll until cursor clear, then close Item Display
    waitingForRemoveCursorPopulated = false, -- after remove confirm accepted: poll until cursor has item, then close Item Display and /autoinv
    insertCursorClearTimeoutAt = nil,      -- mq.gettime() when we started polling; 5s timeout
    removeCursorPopulatedTimeoutAt = nil,
    insertConfirmationSetAt = nil,         -- mq.gettime() when we started waiting for insert confirmation; used for no-dialog fallback
    removeConfirmationSetAt = nil,         -- mq.gettime() when we started waiting for remove confirmation; used for no-dialog fallback
    pendingInsertAugment = nil,   -- { targetItem, targetBag, targetSlot, targetSource, augmentItem, slotIndex } for main loop; slotIndex = which socket (1-based)
    removeAllQueue = nil,         -- Phase 1: { bag, slot, source, slotIndices } when Remove All active; one scan when queue empty
    optimizeQueue = nil,          -- Phase 2: { targetLoc, steps = { { slotIndex, augmentItem }, ... } }; one scan when steps empty
    equipmentDeferredRefreshAt = nil,      -- mq.gettime() ms when to run refreshEquipmentCache again (after swap/pickup so icon updates)
    equipmentLastRefreshAt = nil,          -- Phase 2: last time we refreshed equipment cache (throttle to ~every 400ms instead of every frame)
    deferredInventoryScanAt = nil,         -- mq.gettime() ms when to run scanInventory again (after put in bags / drop so list updates)
    pendingStatRescanBags = nil,            -- set of bag numbers to rescan (when _statsPending items seen); main_loop drains and calls rescanInventoryBags (MASTER_PLAN 2.6)
    -- Loot UI (separate window; open only on Esc or Close)
    lootUIOpen = false,
    lootRunCorpsesLooted = 0,
    lootRunTotalCorpses = 0,
    lootRunCurrentCorpse = "",
    lootRunLootedList = {},     -- array of item names (kept for compatibility)
    lootRunLootedItems = {},    -- array of { name, value, statusText, willSell } for table display
    lootHistory = nil,          -- array of { name, value, statusText, willSell } for History tab (loaded from file, appended when run has items)
    skipHistory = nil,          -- array of { name, reason } for Skip History tab (loaded from file, appended when run has skips)
    lootRunFinished = false,
    lootMythicalAlert = nil,   -- { itemName, corpseName, decision, itemLink, timestamp, iconId } or nil
    lootMythicalDecisionStartAt = nil, -- os.time() when pending alert first seen (for countdown)
    lootMythicalFeedback = nil, -- { message, showUntil } after Take/Pass for 2s confirmation
    lootRunTotalValue = 0,     -- copper (run receipt)
    lootRunTributeValue = 0,
    lootRunBestItemName = "",
    lootRunBestItemValue = 0,
    corpseLootedHidden = true,  -- toggle for Show/Hide looted corpses (troubleshooting)
}

-- Layout from setup (itemui_layout.ini): sizes per view; dimensions from constants.VIEWS
local layoutDefaults = {}
do
    local V = constants.VIEWS
    for k, v in pairs(V) do layoutDefaults[k] = v end
    layoutDefaults.BankWindowX = 0
    layoutDefaults.BankWindowY = 0
    layoutDefaults.AugmentsWindowX = 0
    layoutDefaults.AugmentsWindowY = 0
    layoutDefaults.ItemDisplayWindowX = 0
    layoutDefaults.ItemDisplayWindowY = 0
    layoutDefaults.AugmentUtilityWindowX = 0
    layoutDefaults.AugmentUtilityWindowY = 0
    layoutDefaults.LootWindowX = 0
    layoutDefaults.LootWindowY = 0
    layoutDefaults.LootUIFirstTipSeen = 0
    layoutDefaults.AAWindowX = 0
    layoutDefaults.AAWindowY = 0
    layoutDefaults.ShowAAWindow = 1
    layoutDefaults.WidthRerollPanel = (constants.VIEWS and constants.VIEWS.WidthRerollPanel) or 520
    layoutDefaults.HeightReroll = (constants.VIEWS and constants.VIEWS.HeightReroll) or 480
    layoutDefaults.RerollWindowX = 0
    layoutDefaults.RerollWindowY = 0
    layoutDefaults.AABackupPath = ""
    layoutDefaults.AlignToContext = 1
    layoutDefaults.UILocked = 1
    layoutDefaults.SyncBankWindow = 1
    layoutDefaults.SuppressWhenLootMac = 0
    layoutDefaults.ConfirmBeforeDelete = 1
end
local layoutConfig = {}  -- filled by loadLayoutConfig()
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
    aaColumn = "Title",
    aaDirection = ImGuiSortDirection.Ascending,
    aaTab = 1,  -- 1=General, 2=Archetype, 3=Class, 4=Special
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
local sellMacState = { lastRunning = false, pendingScan = false, finishedAt = 0, failedItems = {}, failedCount = 0, showFailedUntil = 0, smoothedFrac = 0 }
local lootMacState = { lastRunning = false, pendingScan = false, finishedAt = 0 }  -- detect loot macro finish for background inventory scan
-- Pack loot loop state into one table to stay under Lua 60-upvalue limit for main()
local lootLoopRefs = {
    pollMs = constants.TIMING.LOOT_POLL_MS,
    pollMsIdle = constants.TIMING.LOOT_POLL_MS_IDLE,
    pollAt = 0,
    deferMs = constants.TIMING.LOOT_DEFER_MS,
    saveHistoryAt = 0,
    saveSkipAt = 0,
    sellStatusCap = constants.LIMITS.LOOT_SELL_STATUS_CAP,
    pendingSession = false,
    pendingSessionAt = 0,  -- when we set pendingSession, so we can defer read until macro finished writing
}
local LOOT_HISTORY_MAX = constants.LIMITS.LOOT_HISTORY_MAX
local LOOT_HISTORY_DELIM = "\1"  -- ASCII 1 (safe in INI values; avoids | or tab in item names)
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
local bankCache = {}
-- Scan state (shared with itemui.services.scan): one table to stay under local/upvalue limits
local scanState = {
    lastScanTimeBank = 0,
    lastPersistSaveTime = 0,
    lastInventoryFingerprint = "",
    lastScanState = { invOpen = false, bankOpen = false, merchOpen = false, lootOpen = false },
    lastBagFingerprints = {},
    nextAcquiredSeq = 1,  -- static order for Acquired column (no per-frame time math)
    lastGetChangedBagsTime = 0,   -- throttle: skip getChangedBags() when (now - this) < GET_CHANGED_BAGS_THROTTLE_MS
    inventoryBagsDirty = false,  -- when true, skip throttle so next maybeScanInventory runs getChangedBags (set on loot open/close, item op, loot macro finish)
}
-- Invalidate stored-inv cache when we save; pass nextAcquiredSeq so acquired order persists (must be after scanState)
do
    local _saveInv = storage.saveInventory
    storage.saveInventory = function(items) _saveInv(items, scanState.nextAcquiredSeq); perfCache.storedInvByName = nil end
end
-- Deferred scan flags - for instant UI open (load snapshot first, scan after UI shown)
local deferredScanNeeded = { inventory = false, bank = false, sell = false }

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
        uiState.configWindowOpen = false
    elseif name == "equipment" then
        uiState.equipmentWindowOpen = false
        uiState.equipmentWindowShouldDraw = false
    elseif name == "bank" then
        uiState.bankWindowOpen = false
        uiState.bankWindowShouldDraw = false
    elseif name == "augments" then
        uiState.augmentsWindowOpen = false
        uiState.augmentsWindowShouldDraw = false
    elseif name == "augmentUtility" then
        uiState.augmentUtilityWindowOpen = false
        uiState.augmentUtilityWindowShouldDraw = false
    elseif name == "itemDisplay" then
        uiState.itemDisplayWindowOpen = false
        uiState.itemDisplayWindowShouldDraw = false
        uiState.itemDisplayTabs = {}
        uiState.itemDisplayActiveTabIndex = 1
        uiState.removeAllQueue = nil   -- Phase 1: target changed
        uiState.optimizeQueue = nil    -- Phase 2: target changed
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
        { "config", uiState.configWindowOpen },
        { "equipment", uiState.equipmentWindowOpen and uiState.equipmentWindowShouldDraw },
        { "bank", uiState.bankWindowOpen and uiState.bankWindowShouldDraw },
        { "augments", uiState.augmentsWindowOpen and uiState.augmentsWindowShouldDraw },
        { "augmentUtility", uiState.augmentUtilityWindowOpen and uiState.augmentUtilityWindowShouldDraw },
        { "itemDisplay", uiState.itemDisplayWindowOpen and uiState.itemDisplayWindowShouldDraw },
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
local function loadLayoutConfig() layoutUtils.loadLayoutConfig() end
local function saveLayoutForView(view, w, h, bankPanelW) layoutUtils.saveLayoutForView(view, w, h, bankPanelW) end

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
context.logUpvalueCounts(C)

local mainWindowRefs = {
    getShouldDraw = function() return shouldDraw end,
    setShouldDraw = function(v) shouldDraw = v end,
    getOpen = function() return isOpen end,
    setOpen = function(v) isOpen = v end,
    layoutConfig = layoutConfig,
    layoutDefaults = layoutDefaults,
    saveLayoutToFile = saveLayoutToFile,
    saveLayoutForView = saveLayoutForView,
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
}


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
        if uiState.setupMode then uiState.setupStep = 1; loadLayoutConfig() else uiState.setupStep = 0 end
        shouldDraw = true
        isOpen = true
        print(uiState.setupMode and "\ag[ItemUI]\ax Setup: Step 1 of 3 — Resize the Inventory view, then click Next." or "\ar[ItemUI]\ax Setup off.")
    elseif cmd == "config" then
        uiState.configWindowOpen = true
        uiState.configNeedsLoad = true
        recordCompanionWindowOpened("config")
        shouldDraw = true
        isOpen = true
        print("\ag[ItemUI]\ax Config window opened.")
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
    elseif cmd == "help" then
        print("\ag[ItemUI]\ax /itemui or /inv or /inventoryui [toggle|show|hide|refresh|setup|config|reroll|exit|help]")
        print("  setup = resize and save window/column layout for Inventory, Sell, and Inventory+Bank")
        print("  config = open ItemUI & Loot settings (or click Settings in the header)")
        print("  reroll = open Reroll Companion (augment and mythical reroll lists)")
        print("  exit  = unload ItemUI completely")
        print("\ag[ItemUI]\ax /dosell = run sell.mac (sell marked items)  |  /doloot = run loot.mac")
    else
        print("\ar[ItemUI]\ax Unknown: " .. cmd .. " — use /itemui help")
    end
end

local function buildMainLoopDeps()
    return {
        uiState = uiState,
        scanState = scanState,
        sellMacState = sellMacState,
        lootMacState = lootMacState,
        lootLoopRefs = lootLoopRefs,
        perfCache = perfCache,
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
    while not (mq.TLO and mq.TLO.Me and mq.TLO.Me.Name and mq.TLO.Me.Name()) do mq.delay(1000) end
    -- First-run: apply bundled default layout if user has no existing layout (layout only; no user data)
    if not defaultLayout.hasExistingLayout() then
        local ok, err = defaultLayout.applyBundledDefaultLayout()
        if ok then
            -- loadLayoutConfig() below will load the newly applied default
        elseif err and err ~= "" then
            if print then print("\ar[ItemUI]\ax First-run default layout: " .. tostring(err)) end
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

    mainLoop.init(buildMainLoopDeps())
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

main()
