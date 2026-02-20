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
local augmentOps = require('itemui.services.augment_ops')

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

-- Phase 7: Utility modules
local layoutUtils = require('itemui.utils.layout')
local theme = require('itemui.utils.theme')
local columns = require('itemui.utils.columns')
local columnConfig = require('itemui.utils.column_config')
local sortUtils = require('itemui.utils.sort')
local tableCache = require('itemui.utils.table_cache')
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
    GET_CHANGED_BAGS_THROTTLE_MS = 600,   -- Min ms between getChangedBags() calls; skip fingerprinting when within window (unless inventoryBagsDirty)
    SELL_FAILED_DISPLAY_MS = 15000,      -- How long to show failed-items notice after sell macro
    STORED_INV_CACHE_TTL_MS = 2000,      -- TTL for storedInvByName cache (getSellStatusForItem / computeAndAttachSellStatus)
    LOOP_DELAY_VISIBLE_MS = 33,          -- Main loop delay when UI visible (~30 FPS)
    LOOP_DELAY_HIDDEN_MS = 100,           -- Main loop delay when UI hidden
}

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
    syncBankWindow = true,
    suppressWhenLootMac = false,  -- when true: Loot UI does not open during looting (default false = Loot UI opens)
    itemUIPositionX = nil, itemUIPositionY = nil,
    sellViewLocked = true, invViewLocked = true, bankViewLocked = true,
    setupMode = false, setupStep = 0,
    configWindowOpen = false, configNeedsLoad = false, configAdvancedMode = false,
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
    itemDisplayLocateRequestAt = nil,     -- os.clock() when set (clear after 3s)
    itemDisplayAugmentSlotActive = nil,   -- 1-based slot index when "Choose augment" is active in Item Display
    augmentUtilityWindowOpen = false, augmentUtilityWindowShouldDraw = false,
    augmentUtilitySlotIndex = 1,          -- 1-based slot for standalone Augment Utility
    searchFilterAugmentUtility = "",     -- filter compatible augments list by name
    augmentUtilityOnlyShowUsable = true, -- when true, filter list to augments current character can use (class/race/deity/level)
    aaWindowOpen = false, aaWindowShouldDraw = false,
    companionWindowOpenedAt = {},  -- LIFO Esc: name -> mq.gettime() when opened
    statusMessage = "", statusMessageTime = 0,
    quantityPickerValue = "", quantityPickerMax = 1,
    quantityPickerSubmitPending = nil,  -- qty to submit next frame (so Enter is consumed before we clear the field)
    pendingQuantityPickup = nil, pendingQuantityPickupTimeoutAt = nil,  -- timeout: clear picker if user never completes (Phase 1 reliability)
    pendingQuantityAction = nil,
    lastPickup = { bag = nil, slot = nil, source = nil },  -- source: "inv" | "bank"
    lastPickupSetThisFrame = false,  -- true when a view set lastPickup this frame (don't clear until next frame so item hides)
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
    ItemDisplayWindowX = 0,
    ItemDisplayWindowY = 0,
    WidthItemDisplayPanel = 760,
    HeightItemDisplay = 520,
    AugmentUtilityWindowX = 0,
    AugmentUtilityWindowY = 0,
    WidthAugmentUtilityPanel = 520,
    HeightAugmentUtility = 480,
    WidthLootPanel = 420,
    HeightLoot = 380,
    LootWindowX = 0,
    LootWindowY = 0,
    LootUIFirstTipSeen = 0,
    WidthAAPanel = 640,
    HeightAA = 520,
    AAWindowX = 0,
    AAWindowY = 0,
    ShowAAWindow = 1,
    AABackupPath = "",  -- empty = use CONFIG_PATH (Macros/sell_config)
    AlignToContext = 1,  -- Enable snap to Inventory by default
    UILocked = 1,
    SyncBankWindow = 1,
    SuppressWhenLootMac = 0,  -- 0 = Loot UI opens when looting (default); 1 = suppress Loot UI during looting
    ConfirmBeforeDelete = 1, -- Show confirmation dialog before destroying an item (1 = yes, 0 = no)
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
local sellMacState = { lastRunning = false, failedItems = {}, failedCount = 0, showFailedUntil = 0, smoothedFrac = 0 }
local lootMacState = { lastRunning = false, pendingScan = false, finishedAt = 0 }  -- detect loot macro finish for background inventory scan
-- Pack loot loop state into one table to stay under Lua 60-upvalue limit for main()
local lootLoopRefs = {
    pollMs = 500,
    pollMsIdle = 1000,   -- when Loot UI open but macro not running (O9: slower poll)
    pollAt = 0,
    deferMs = 2000,
    saveHistoryAt = 0,
    saveSkipAt = 0,
    sellStatusCap = 30,
    pendingSession = false,  -- defer session table build by one frame when macro stops
}
local LOOT_HISTORY_MAX = 200
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
        uiState.aaWindowOpen = false
        uiState.aaWindowShouldDraw = false
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
        { "aa", uiState.aaWindowOpen and uiState.aaWindowShouldDraw },
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

-- sortOnly: when true (inv only), do not clear invTotalSlots/invTotalValue so "Items: x/y" and total value don't force recompute
local function invalidateSortCache(view, sortOnly)
    local c = view == "inv" and perfCache.inv or view == "sell" and perfCache.sell or view == "bank" and perfCache.bank or view == "loot" and perfCache.loot
    if c then c.key = nil end
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

local ITEM_DISPLAY_RECENT_MAX = 10
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
            while #recent > ITEM_DISPLAY_RECENT_MAX do table.remove(recent) end
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
    while #recent > ITEM_DISPLAY_RECENT_MAX do table.remove(recent) end
    uiState.itemDisplayWindowOpen = true
    uiState.itemDisplayWindowShouldDraw = true
    recordCompanionWindowOpened("itemDisplay")
end

context.init({
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
    -- Item ops (module direct; always present so views can call without guards; Phase 2: use frame cache when set)
    hasItemOnCursor = function()
        if uiState.hasItemOnCursorThisFrame ~= nil then return uiState.hasItemOnCursorThisFrame end
        return itemOps.hasItemOnCursor()
    end,
    removeItemFromCursor = function() return itemOps.removeItemFromCursor() end,
    putCursorInBags = function() return itemOps.putCursorInBags() end,
    moveBankToInv = function(b, s) return itemOps.moveBankToInv(b, s) end,
    moveInvToBank = function(b, s) return itemOps.moveInvToBank(b, s) end,
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
    addToLootSkipList = addToLootSkipList, removeFromLootSkipList = removeFromLootSkipList,
    isInLootSkipList = isInLootSkipList,
    -- Sort/columns (Phase 3: shared sort+cache helper)
    sortColumns = sortColumnsAPI,
    getSortedList = function(cache, filtered, sortKey, sortDir, validity, viewName, sortCols)
        return tableCache.getSortedList(cache, filtered, sortKey, sortDir, validity, viewName, sortCols or sortColumnsAPI)
    end,
    getColumnKeyByIndex = columns.getColumnKeyByIndex, autofitColumns = columns.autofitColumns,
    -- Item helpers (module direct)
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

-- Render equipment companion window (separate from main UI)
local function renderEquipmentWindow()
    local ctx = extendContext(buildViewContext())
    EquipmentView.render(ctx)
end

--- Augments window: pop-out like Bank (Always sell / Never loot, compact table, icon+stats on hover)
local function renderAugmentsWindow()
    local ctx = extendContext(buildViewContext())
    AugmentsView.render(ctx)
end

--- Item Display window: persistent window with same content as on-hover tooltip (stats, augments, effects, etc.)
local function renderItemDisplayWindow()
    local ctx = extendContext(buildViewContext())
    ItemDisplayView.render(ctx)
end

--- Augment Utility window: standalone insert/remove augments (target = current Item Display tab)
local function renderAugmentUtilityWindow()
    local ctx = extendContext(buildViewContext())
    AugmentUtilityView.render(ctx)
end

--- AA window: Alt Advancement (tabs, search, train, export/import)
local function renderAAWindow()
    local ctx = buildViewContext()
    ctx.refreshAA = function() aa_data.refresh() end
    ctx.getAAList = function() return aa_data.getList() end
    ctx.getAAPointsSummary = function() return aa_data.getPointsSummary() end
    ctx.shouldRefreshAA = function() return aa_data.shouldRefresh() end
    ctx.getAALastRefreshTime = function() return aa_data.getLastRefreshTime() end
    AAView.render(ctx)
end

--- Loot UI window: progress and session summary (only when lootUIOpen; close on Esc or Close)
local function renderLootWindow()
    local ctx = extendContext(buildViewContext())
    ctx.runLootCurrent = function()
        if not uiState.suppressWhenLootMac then
            uiState.lootUIOpen = true
            uiState.lootRunFinished = false
            recordCompanionWindowOpened("loot")
        end
        mq.cmd('/macro loot current')
    end
    ctx.runLootAll = function()
        if not uiState.suppressWhenLootMac then
            uiState.lootUIOpen = true
            uiState.lootRunFinished = false
            recordCompanionWindowOpened("loot")
        end
        mq.cmd('/macro loot')
    end
    ctx.clearLootUIMythicalAlert = function()
        uiState.lootMythicalAlert = nil
        uiState.lootMythicalDecisionStartAt = nil
        uiState.lootMythicalFeedback = nil
        local path = config.getLootConfigFile and config.getLootConfigFile("loot_mythical_alert.ini")
        if path and path ~= "" then
            mq.cmdf('/ini "%s" Alert decision "skip"', path)
            mq.cmdf('/ini "%s" Alert itemName ""', path)
            mq.cmdf('/ini "%s" Alert corpseName ""', path)
            mq.cmdf('/ini "%s" Alert itemLink ""', path)
        end
    end
    ctx.setMythicalDecision = function(decision)
        if decision ~= "loot" and decision ~= "skip" then return end
        local path = config.getLootConfigFile and config.getLootConfigFile("loot_mythical_alert.ini")
        if path and path ~= "" then
            mq.cmdf('/ini "%s" Alert decision "%s"', path, decision)
        end
    end
    ctx.mythicalTake = function()
        local alert = uiState.lootMythicalAlert
        if not alert then return end
        local name = alert.itemName or ""
        local link = (alert.itemLink and alert.itemLink ~= "") and alert.itemLink or nil
        if mq.TLO.Me.Grouped and (name ~= "" or link) then
            if link then mq.cmdf('/g Taking %s — looting.', link) else mq.cmdf('/g Taking %s — looting.', name) end
        end
        ctx.setMythicalDecision("loot")
        uiState.lootMythicalFeedback = { message = "You chose: Take", showUntil = (os.clock and os.clock() or 0) + 2 }
        uiState.lootMythicalAlert = nil
        local path = config.getLootConfigFile and config.getLootConfigFile("loot_mythical_alert.ini")
        if path and path ~= "" then
            mq.cmdf('/ini "%s" Alert itemName ""', path)
            mq.cmdf('/ini "%s" Alert corpseName ""', path)
            mq.cmdf('/ini "%s" Alert itemLink ""', path)
        end
    end
    ctx.mythicalPass = function()
        local alert = uiState.lootMythicalAlert
        if not alert then return end
        local name = alert.itemName or ""
        local link = (alert.itemLink and alert.itemLink ~= "") and alert.itemLink or nil
        if mq.TLO.Me.Grouped and (name ~= "" or link) then
            if link then mq.cmdf('/g Passing on %s — someone else can loot.', link) else mq.cmdf('/g Passing on %s — someone else can loot.', name) end
        end
        ctx.setMythicalDecision("skip")
        uiState.lootMythicalFeedback = { message = "Passed - left on corpse for group.", showUntil = (os.clock and os.clock() or 0) + 2 }
        uiState.lootMythicalAlert = nil
        local path = config.getLootConfigFile and config.getLootConfigFile("loot_mythical_alert.ini")
        if path and path ~= "" then
            mq.cmdf('/ini "%s" Alert itemName ""', path)
            mq.cmdf('/ini "%s" Alert corpseName ""', path)
            mq.cmdf('/ini "%s" Alert itemLink ""', path)
        end
    end
    ctx.setMythicalCopyName = function(name)
        if name and name ~= "" then print(string.format("\ay[ItemUI]\ax Mythical item name: %s", name)) end
    end
    ctx.setMythicalCopyLink = function(link)
        if not link or link == "" then return end
        if ImGui and ImGui.SetClipboardText then ImGui.SetClipboardText(link) end
        print(string.format("\ay[ItemUI]\ax Mythical item link copied to clipboard (or see console)."))
    end
    ctx.clearLootUIState = function()
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
        -- lootHistory and skipHistory are not cleared (persist across window close)
    end
    ctx.loadLootHistory = function()
        if not uiState.lootHistory then loadLootHistoryFromFile() end
        if not uiState.lootHistory then uiState.lootHistory = {} end
    end
    ctx.loadSkipHistory = function()
        if not uiState.skipHistory then loadSkipHistoryFromFile() end
        if not uiState.skipHistory then uiState.skipHistory = {} end
    end
    ctx.clearLootHistory = function()
        uiState.lootHistory = {}
        local path = config.getLootConfigFile and config.getLootConfigFile("loot_history.ini")
        if path and path ~= "" then mq.cmdf('/ini "%s" History count 0', path) end
        lootLoopRefs.saveHistoryAt = 0
    end
    ctx.clearSkipHistory = function()
        uiState.skipHistory = {}
        local path = config.getLootConfigFile and config.getLootConfigFile("skip_history.ini")
        if path and path ~= "" then mq.cmdf('/ini "%s" Skip count 0', path) end
        lootLoopRefs.saveSkipAt = 0
    end
    LootUIView.render(ctx)
end

-- ============================================================================
-- Main render
-- ============================================================================
local function renderUI()
    if not shouldDraw and not uiState.lootUIOpen then return end
    uiState.lastPickupSetThisFrame = false  -- reset each frame; views set true when they set lastPickup
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

    if shouldDraw then
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
    
    local winOpen, winVis = ImGui.Begin("CoOpt UI Inventory Companion##ItemUI", isOpen, windowFlags)
    isOpen = winOpen
    if not winOpen then
        shouldDraw = false
        uiState.configWindowOpen = false
        closeGameInventoryIfOpen()
        ImGui.End()
        return
    end
    -- Layered Esc: close pending picker, then most recently opened companion (LIFO), then main UI
    if ImGui.IsKeyPressed(ImGuiKey.Escape) then
        if uiState.pendingQuantityPickup then
            uiState.pendingQuantityPickup = nil
            uiState.pendingQuantityPickupTimeoutAt = nil
            uiState.quantityPickerValue = ""
        else
            local mostRecent = getMostRecentlyOpenedCompanion()
            if mostRecent then
                closeCompanionWindow(mostRecent)
            else
                ImGui.SetKeyboardFocusHere(-1)  -- release keyboard focus so game gets input after close
                shouldDraw = false
                isOpen = false
                uiState.configWindowOpen = false
                closeGameInventoryIfOpen()
                closeGameMerchantIfOpen()  -- clean close: also close default merchant UI when in sell view
                ImGui.End()
                return
            end
        end
    end
    if not winVis then ImGui.End(); return end

    -- Phase 2: cache cursor state once per frame so main loop and views don't call TLO.Cursor() repeatedly
    uiState.hasItemOnCursorThisFrame = itemOps.hasItemOnCursor()

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

    -- Default layout: position companions relative to hub (Inventory Companion) when they have no saved position (0,0)
    -- Bank stays as-is (synced right of hub).
    local hubX, hubY = uiState.itemUIPositionX, uiState.itemUIPositionY
    local hubW, hubH = itemUIWidth, (ImGui.GetWindowSize and select(2, ImGui.GetWindowSize())) or 450
    local defGap = 10
    local eqW = layoutConfig.WidthEquipmentPanel or 220
    local eqH = layoutConfig.HeightEquipment or 380
    if hubX and hubY and hubW then
        if uiState.equipmentWindowShouldDraw and (layoutConfig.EquipmentWindowX or 0) == 0 and (layoutConfig.EquipmentWindowY or 0) == 0 then
            layoutConfig.EquipmentWindowX = hubX - eqW - defGap
            layoutConfig.EquipmentWindowY = hubY
        end
        if uiState.itemDisplayWindowShouldDraw and (layoutConfig.ItemDisplayWindowX or 0) == 0 and (layoutConfig.ItemDisplayWindowY or 0) == 0 then
            layoutConfig.ItemDisplayWindowX = hubX + hubW + defGap
            layoutConfig.ItemDisplayWindowY = hubY
        end
        if uiState.augmentsWindowShouldDraw and (layoutConfig.AugmentsWindowX or 0) == 0 and (layoutConfig.AugmentsWindowY or 0) == 0 then
            local aw = layoutConfig.WidthAugmentsPanel or layoutDefaults.WidthAugmentsPanel or 560
            layoutConfig.AugmentsWindowX = hubX - aw - defGap
            layoutConfig.AugmentsWindowY = hubY + eqH + defGap
        end
        if uiState.augmentUtilityWindowShouldDraw and (layoutConfig.AugmentUtilityWindowX or 0) == 0 and (layoutConfig.AugmentUtilityWindowY or 0) == 0 then
            local auw = layoutConfig.WidthAugmentUtilityPanel or layoutDefaults.WidthAugmentUtilityPanel or 520
            layoutConfig.AugmentUtilityWindowX = hubX - auw - defGap
            layoutConfig.AugmentUtilityWindowY = hubY + math.floor(eqH * 0.45)
        end
        if uiState.aaWindowShouldDraw and (layoutConfig.AAWindowX or 0) == 0 and (layoutConfig.AAWindowY or 0) == 0 then
            local idH = layoutConfig.HeightItemDisplay or layoutDefaults.HeightItemDisplay or 520
            layoutConfig.AAWindowX = hubX + hubW + defGap
            layoutConfig.AAWindowY = hubY + idH + defGap
        end
    end

    -- Header: left = Equipment, AA, Augment Utility, Filter; right = Settings, Pin (Lock), Bank
    if ImGui.Button("Equipment", ImVec2(75, 0)) then
        uiState.equipmentWindowOpen = not uiState.equipmentWindowOpen
        uiState.equipmentWindowShouldDraw = uiState.equipmentWindowOpen
        if uiState.equipmentWindowOpen then recordCompanionWindowOpened("equipment"); setStatusMessage("Equipment Companion opened") end
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Open Equipment Companion (current equipped items)"); ImGui.EndTooltip() end
    ImGui.SameLine()
    if (tonumber(layoutConfig.ShowAAWindow) or 1) ~= 0 then
        if ImGui.Button("AA", ImVec2(45, 0)) then
            uiState.aaWindowOpen = not uiState.aaWindowOpen
            uiState.aaWindowShouldDraw = uiState.aaWindowOpen
            if uiState.aaWindowOpen then
                recordCompanionWindowOpened("aa")
                if aa_data.shouldRefresh() then aa_data.refresh() end
                setStatusMessage("Alt Advancement window opened")
            end
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Open Alt Advancement window (view, train, backup/restore AAs)"); ImGui.EndTooltip() end
        ImGui.SameLine()
    end
    if ImGui.Button("Augment Utility", ImVec2(100, 0)) then
        uiState.augmentUtilityWindowOpen = not uiState.augmentUtilityWindowOpen
        uiState.augmentUtilityWindowShouldDraw = uiState.augmentUtilityWindowOpen
        if uiState.augmentUtilityWindowOpen then recordCompanionWindowOpened("augmentUtility"); setStatusMessage("Augment Utility opened") end
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Insert/remove augments (use Item Display tab as target)"); ImGui.EndTooltip() end
    ImGui.SameLine()
    if ImGui.Button("Filter", ImVec2(55, 0)) then
        uiState.augmentsWindowOpen = not uiState.augmentsWindowOpen
        uiState.augmentsWindowShouldDraw = uiState.augmentsWindowOpen
        if uiState.augmentsWindowOpen then recordCompanionWindowOpened("augments"); setStatusMessage("Filter window opened") end
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Open Filter window (Always sell / Never loot, stats on hover; extended filtering later)"); ImGui.EndTooltip() end
    ImGui.SameLine(ImGui.GetWindowWidth() - 210)
    if ImGui.Button("Settings", ImVec2(70, 0)) then uiState.configWindowOpen = true; uiState.configNeedsLoad = true; recordCompanionWindowOpened("config") end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Open CoOpt UI Settings"); ImGui.EndTooltip() end
    ImGui.SameLine()
    local prevLocked = uiState.uiLocked
    uiState.uiLocked = ImGui.Checkbox("##Lock", uiState.uiLocked)
    if prevLocked ~= uiState.uiLocked then
        saveLayoutToFile()
        if uiState.uiLocked then
            local w, h = ImGui.GetWindowSize()
            if curView == "Inventory" then layoutConfig.WidthInventory = w; layoutConfig.Height = h
            elseif curView == "Sell" then layoutConfig.WidthSell = w; layoutConfig.Height = h
            elseif curView == "Loot" then layoutConfig.WidthLoot = w; layoutConfig.Height = h
            end
            saveLayoutToFile()
        end
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(uiState.uiLocked and "Pin: UI locked (click to unlock and resize)" or "Pin: UI unlocked (click to lock)"); ImGui.EndTooltip() end
    ImGui.SameLine()
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
        if uiState.bankWindowOpen then recordCompanionWindowOpened("bank"); if bankOnline then maybeScanBank(bankOnline) end end
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
                recordCompanionWindowOpened("bank")
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
                uiState.pendingQuantityPickupTimeoutAt = nil
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
                    uiState.pendingQuantityPickupTimeoutAt = nil
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
            uiState.pendingQuantityPickupTimeoutAt = nil
            uiState.quantityPickerValue = ""
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Pick up maximum quantity"); ImGui.EndTooltip() end
        ImGui.SameLine()
        if ImGui.Button("Cancel", ImVec2(60, 0)) then
            uiState.pendingQuantityPickup = nil
            uiState.pendingQuantityPickupTimeoutAt = nil
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
        if ImGui.Button("Put in bags", ImVec2(90,0)) then putCursorInBags() end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Place item in first free inventory slot"); ImGui.EndTooltip() end
        ImGui.SameLine()
        ImGui.TextColored(ImVec4(0.55,0.55,0.55,1), "Right-click to put back")
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Right-click anywhere on this window to put the item back"); ImGui.EndTooltip() end
    end
    if hasItemOnCursor() and ImGui.IsMouseReleased(ImGuiMouseButton.Right) and ImGui.IsWindowHovered() then
        removeItemFromCursor()
    end
    -- Clear lastPickup when cursor is empty so the item shows back in the list. Don't clear the same frame we set it (lastPickupSetThisFrame) or we'd clear before the game has put the item on cursor.
    -- When cursor becomes empty after having had an item (e.g. user equipped it), schedule a scan so the list updates and the row disappears instead of reappearing.
    if not hasItemOnCursor() and not uiState.lastPickupSetThisFrame then
        if uiState.lastPickup and (uiState.lastPickup.bag ~= nil or uiState.lastPickup.slot ~= nil) then
            uiState.deferredInventoryScanAt = mq.gettime() + 120
        end
        uiState.lastPickup.bag, uiState.lastPickup.slot, uiState.lastPickup.source = nil, nil, nil
    end
    if not hasItemOnCursor() then
        uiState.hadItemOnCursorLastFrame = false
    else
        uiState.hadItemOnCursorLastFrame = true
    end

    -- Footer: status messages (Keep/Junk, moves, sell), failed items notice
    ImGui.Separator()
    if uiState.pendingDestroy then
        local pd = uiState.pendingDestroy
        local name = pd.name or "item"
        if #name > 40 then name = name:sub(1, 37) .. "..." end
        local stackSize = (pd.stackSize and pd.stackSize > 0) and pd.stackSize or 1
        ImGui.Text("Destroy " .. name .. "?")
        if stackSize > 1 then
            ImGui.SameLine()
            ImGui.SetNextItemWidth(60)
            local qtyFlags = bit32.bor(ImGuiInputTextFlags.CharsDecimal, ImGuiInputTextFlags.EnterReturnsTrue)
            uiState.destroyQuantityValue, _ = ImGui.InputText("##DestroyQty", uiState.destroyQuantityValue, qtyFlags)
            ImGui.SameLine()
            ImGui.Text(string.format("(1-%d)", stackSize))
        end
        ImGui.SameLine()
        local errCol = theme and theme.ToVec4 and theme.ToVec4(theme.Colors.Error) or ImVec4(0.9, 0.25, 0.2, 1)
        ImGui.PushStyleColor(ImGuiCol.Button, errCol)
        if ImGui.Button("Confirm Delete", ImVec2(110, 0)) then
            local qty = stackSize
            if stackSize > 1 then
                local n = tonumber(uiState.destroyQuantityValue)
                if n and n >= 1 and n <= stackSize then qty = math.floor(n) else qty = stackSize end
            end
            uiState.pendingDestroyAction = { bag = pd.bag, slot = pd.slot, name = pd.name, qty = qty }
            uiState.pendingDestroy = nil
            uiState.destroyQuantityValue = ""
            uiState.destroyQuantityMax = 1
        end
        ImGui.PopStyleColor()
        ImGui.SameLine()
        if ImGui.Button("Cancel", ImVec2(60, 0)) then
            uiState.pendingDestroy = nil
            uiState.destroyQuantityValue = ""
            uiState.destroyQuantityMax = 1
        end
    end
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

    -- Phase 2: refresh equipment cache only on deferred timer or when stale (~400ms), not every frame
    if uiState.equipmentWindowShouldDraw then
        local now = mq.gettime()
        local shouldRefresh = false
        if uiState.equipmentDeferredRefreshAt and now >= uiState.equipmentDeferredRefreshAt then
            uiState.equipmentDeferredRefreshAt = nil
            shouldRefresh = true
        elseif not uiState.equipmentLastRefreshAt or (now - uiState.equipmentLastRefreshAt) > 400 then
            shouldRefresh = true
        end
        if shouldRefresh then
            refreshEquipmentCache()
            uiState.equipmentLastRefreshAt = now
        end
    else
        uiState.equipmentLastRefreshAt = nil  -- so next open we refresh
    end
    if uiState.deferredInventoryScanAt and mq.gettime() >= uiState.deferredInventoryScanAt then
        scanInventory()
        uiState.deferredInventoryScanAt = nil
    end
    renderEquipmentWindow()
    renderBankWindow()
    if uiState.augmentsWindowShouldDraw then
        renderAugmentsWindow()
    end
    if uiState.augmentUtilityWindowShouldDraw then
        renderAugmentUtilityWindow()
    end
    if uiState.itemDisplayWindowShouldDraw then
        renderItemDisplayWindow()
    end
    -- Clear Locate highlight after 3s
    if uiState.itemDisplayLocateRequest and uiState.itemDisplayLocateRequestAt then
        local now = (os and os.clock and os.clock()) or 0
        if now - uiState.itemDisplayLocateRequestAt > 3 then
            uiState.itemDisplayLocateRequest = nil
            uiState.itemDisplayLocateRequestAt = nil
        end
    end
    if (tonumber(layoutConfig.ShowAAWindow) or 1) ~= 0 and uiState.aaWindowShouldDraw then
        renderAAWindow()
    end
    end -- shouldDraw

    if uiState.lootUIOpen then
        renderLootWindow()
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
    mq.bind('/doloot', function()
        if not uiState.suppressWhenLootMac then
            uiState.lootUIOpen = true
            uiState.lootRunFinished = false
            recordCompanionWindowOpened("loot")
        end
        mq.cmd('/macro loot')
    end)
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
        -- Loot macro: progress/session INI for Loot UI; defer scan when macro finishes
        do
            local macroName = mq.TLO.Macro and mq.TLO.Macro.Name and (mq.TLO.Macro.Name() or "") or ""
            local mn = macroName:lower()
            local lootMacRunning = (mn == "loot" or mn == "loot.mac")
            -- When macro just started (was not running, now running), open Loot UI if not suppressed (list persists; updates when run finishes)
            if lootMacRunning and not lootMacState.lastRunning and not uiState.suppressWhenLootMac then
                uiState.lootUIOpen = true
                uiState.lootRunFinished = false
                recordCompanionWindowOpened("loot")
            end
            if lootMacState.lastRunning and not lootMacRunning then
                lootMacState.pendingScan = true
                lootMacState.finishedAt = now
                scanState.inventoryBagsDirty = true
                -- Defer session table build to next frame (smoother UI, no hitch on macro-stop frame)
                lootLoopRefs.pendingSession = true
                -- When macro stops, show Loot UI if Mythical alert INI was written (e.g. /macro loot test)
                local alertPath = config.getLootConfigFile and config.getLootConfigFile("loot_mythical_alert.ini")
                if alertPath and alertPath ~= "" then
                    local itemName = config.safeIniValueByPath(alertPath, "Alert", "itemName", "")
                    if itemName and itemName ~= "" then
                        local decision = config.safeIniValueByPath(alertPath, "Alert", "decision", "") or "pending"
                        local iconStr = config.safeIniValueByPath(alertPath, "Alert", "iconId", "") or "0"
                        local prevName = uiState.lootMythicalAlert and uiState.lootMythicalAlert.itemName
                        uiState.lootMythicalAlert = {
                            itemName = itemName,
                            corpseName = config.safeIniValueByPath(alertPath, "Alert", "corpseName", "") or "",
                            decision = decision,
                            itemLink = config.safeIniValueByPath(alertPath, "Alert", "itemLink", "") or "",
                            timestamp = config.safeIniValueByPath(alertPath, "Alert", "timestamp", "") or "",
                            iconId = tonumber(iconStr) or 0
                        }
                        if decision == "pending" then
                            if not prevName or prevName ~= itemName then
                                uiState.lootMythicalDecisionStartAt = os.time and os.time() or 0
                            end
                        else
                            uiState.lootMythicalDecisionStartAt = nil
                        end
                        uiState.lootUIOpen = true
                        recordCompanionWindowOpened("loot")
                    end
                end
            end
            -- Process deferred session build (one frame after macro stopped)
            if lootLoopRefs.pendingSession then
                lootLoopRefs.pendingSession = nil
                if uiState.lootUIOpen then
                    local sessionPath = config.getLootConfigFile and config.getLootConfigFile("loot_session.ini")
                    if sessionPath and sessionPath ~= "" then
                        local countStr = config.safeIniValueByPath(sessionPath, "Items", "count", "0")
                        local count = tonumber(countStr) or 0
                        if count > 0 then
                            uiState.lootRunLootedList = {}
                            uiState.lootRunLootedItems = {}
                            for i = 1, count do
                                local name = config.safeIniValueByPath(sessionPath, "Items", tostring(i), "")
                                if name and name ~= "" then
                                    table.insert(uiState.lootRunLootedList, name)
                                    local valStr = config.safeIniValueByPath(sessionPath, "ItemValues", tostring(i), "0")
                                    local tribStr = config.safeIniValueByPath(sessionPath, "ItemTributes", tostring(i), "0")
                                    local statusText, willSell = "—", false
                                    if getSellStatusForItem and i <= lootLoopRefs.sellStatusCap then
                                        statusText, willSell = getSellStatusForItem({ name = name })
                                        if statusText == "" then statusText = "—" end
                                    end
                                    table.insert(uiState.lootRunLootedItems, {
                                        name = name,
                                        value = tonumber(valStr) or 0,
                                        tribute = tonumber(tribStr) or 0,
                                        statusText = statusText,
                                        willSell = willSell
                                    })
                                end
                            end
                            local sv = config.safeIniValueByPath(sessionPath, "Summary", "totalValue", "0")
                            local tv = config.safeIniValueByPath(sessionPath, "Summary", "tributeValue", "0")
                            uiState.lootRunTotalValue = tonumber(sv) or 0
                            uiState.lootRunTributeValue = tonumber(tv) or 0
                            uiState.lootRunBestItemName = config.safeIniValueByPath(sessionPath, "Summary", "bestItemName", "") or ""
                            uiState.lootRunBestItemValue = tonumber(config.safeIniValueByPath(sessionPath, "Summary", "bestItemValue", "0")) or 0
                            if not uiState.lootHistory then loadLootHistoryFromFile() end
                            if not uiState.lootHistory then uiState.lootHistory = {} end
                            for _, row in ipairs(uiState.lootRunLootedItems) do
                                table.insert(uiState.lootHistory, { name = row.name, value = row.value, statusText = row.statusText, willSell = row.willSell })
                            end
                            while #uiState.lootHistory > LOOT_HISTORY_MAX do table.remove(uiState.lootHistory, 1) end
                            lootLoopRefs.saveHistoryAt = now + lootLoopRefs.deferMs
                        end
                    end
                    local skippedPath = config.getLootConfigFile and config.getLootConfigFile("loot_skipped.ini")
                    if skippedPath and skippedPath ~= "" then
                        local skipCountStr = config.safeIniValueByPath(skippedPath, "Skipped", "count", "0")
                        local skipCount = tonumber(skipCountStr) or 0
                        if skipCount > 0 then
                            if not uiState.skipHistory then loadSkipHistoryFromFile() end
                            if not uiState.skipHistory then uiState.skipHistory = {} end
                            for j = 1, skipCount do
                                local raw = config.safeIniValueByPath(skippedPath, "Skipped", tostring(j), "")
                                if raw and raw ~= "" then
                                    local name, reason = raw:match("^([^%^]*)%^?(.*)$")
                                    table.insert(uiState.skipHistory, { name = name or raw, reason = reason or "" })
                                end
                            end
                            while #uiState.skipHistory > LOOT_HISTORY_MAX do table.remove(uiState.skipHistory, 1) end
                            lootLoopRefs.saveSkipAt = now + lootLoopRefs.deferMs
                        end
                    end
                    uiState.lootRunFinished = true
                end
            end
            local pollInterval = lootMacRunning and lootLoopRefs.pollMs or (lootLoopRefs.pollMsIdle or 1000)
            if (lootMacRunning or uiState.lootUIOpen) and (now - lootLoopRefs.pollAt) >= pollInterval then
                lootLoopRefs.pollAt = now
                local progPath = config.getLootConfigFile and config.getLootConfigFile("loot_progress.ini")
                if progPath and progPath ~= "" and config.readLootProgressSection then
                    local corpses, total, current = config.readLootProgressSection(progPath)
                    uiState.lootRunCorpsesLooted = corpses
                    uiState.lootRunTotalCorpses = total
                    uiState.lootRunCurrentCorpse = current or ""
                end
                if lootMacRunning then
                    local alertPath = config.getLootConfigFile and config.getLootConfigFile("loot_mythical_alert.ini")
                    if alertPath and alertPath ~= "" then
                        local itemName = config.safeIniValueByPath(alertPath, "Alert", "itemName", "")
                        if itemName and itemName ~= "" then
                            local decision = config.safeIniValueByPath(alertPath, "Alert", "decision", "") or "pending"
                            local iconStr = config.safeIniValueByPath(alertPath, "Alert", "iconId", "") or "0"
                            local prevName = uiState.lootMythicalAlert and uiState.lootMythicalAlert.itemName
                            uiState.lootMythicalAlert = {
                                itemName = itemName,
                                corpseName = config.safeIniValueByPath(alertPath, "Alert", "corpseName", "") or "",
                                decision = decision,
                                itemLink = config.safeIniValueByPath(alertPath, "Alert", "itemLink", "") or "",
                                timestamp = config.safeIniValueByPath(alertPath, "Alert", "timestamp", "") or "",
                                iconId = tonumber(iconStr) or 0
                            }
                            if decision == "pending" then
                                if not prevName or prevName ~= itemName then
                                    uiState.lootMythicalDecisionStartAt = os.time and os.time() or 0
                                end
                            else
                                uiState.lootMythicalDecisionStartAt = nil
                            end
                            uiState.lootUIOpen = true
                            recordCompanionWindowOpened("loot")
                        else
                            uiState.lootMythicalAlert = nil
                            uiState.lootMythicalDecisionStartAt = nil
                        end
                    end
                end
            end
            lootMacState.lastRunning = lootMacRunning
        end
        -- Deferred loot/skip history saves (avoid blocking macro-finish frame)
        if lootLoopRefs.saveHistoryAt > 0 and now >= lootLoopRefs.saveHistoryAt then
            lootLoopRefs.saveHistoryAt = 0
            lootLoopRefs.saveLootHistory()
        end
        if lootLoopRefs.saveSkipAt > 0 and now >= lootLoopRefs.saveSkipAt then
            lootLoopRefs.saveSkipAt = 0
            lootLoopRefs.saveSkipHistory()
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
        if uiState.pendingDestroyAction then
            local pd = uiState.pendingDestroyAction
            uiState.pendingDestroyAction = nil
            uiState.pendingQuantityPickup = nil
            uiState.pendingQuantityPickupTimeoutAt = nil
            uiState.quantityPickerValue = ""
            itemOps.performDestroyItem(pd.bag, pd.slot, pd.name, pd.qty)
        end
        if uiState.pendingMoveAction then
            uiState.pendingQuantityPickup = nil
            uiState.pendingQuantityPickupTimeoutAt = nil
            uiState.quantityPickerValue = ""
            itemOps.executeMoveAction(uiState.pendingMoveAction)
            uiState.pendingMoveAction = nil
        end
        -- Phase 1: start first remove from Remove All queue when idle (no pending/waiting remove)
        if uiState.removeAllQueue and uiState.removeAllQueue.slotIndices and #uiState.removeAllQueue.slotIndices > 0
            and not uiState.pendingRemoveAugment and not uiState.waitingForRemoveConfirmation and not uiState.waitingForRemoveCursorPopulated then
            local q = uiState.removeAllQueue
            local slotIndex = table.remove(q.slotIndices, 1)
            uiState.pendingRemoveAugment = { bag = q.bag, slot = q.slot, source = q.source, slotIndex = slotIndex }
            if #q.slotIndices == 0 then uiState.removeAllQueue = nil end
        end
        if uiState.pendingRemoveAugment then
            local ra = uiState.pendingRemoveAugment
            uiState.pendingRemoveAugment = nil
            augmentOps.removeAugment(ra.bag, ra.slot, ra.source, ra.slotIndex)
            uiState.removeConfirmationSetAt = mq.gettime()
        end
        -- Phase 2: start first insert from Optimize queue when idle (no pending/waiting insert)
        if uiState.optimizeQueue and uiState.optimizeQueue.steps and #uiState.optimizeQueue.steps > 0
            and not uiState.pendingInsertAugment and not uiState.waitingForInsertConfirmation and not uiState.waitingForInsertCursorClear then
            local oq = uiState.optimizeQueue
            local step = table.remove(oq.steps, 1)
            if step and step.slotIndex and step.augmentItem then
                local tab = (uiState.itemDisplayTabs and uiState.itemDisplayActiveTabIndex and uiState.itemDisplayTabs[uiState.itemDisplayActiveTabIndex]) or nil
                local targetItem = (tab and tab.item) and { id = tab.item.id or tab.item.ID, name = tab.item.name or tab.item.Name } or { id = 0, name = "" }
                uiState.pendingInsertAugment = {
                    targetItem = targetItem,
                    targetBag = oq.targetLoc.bag,
                    targetSlot = oq.targetLoc.slot,
                    targetSource = oq.targetLoc.source or "inv",
                    augmentItem = step.augmentItem,
                    slotIndex = step.slotIndex,
                }
                uiState.insertConfirmationSetAt = mq.gettime()
            end
        end
        if uiState.pendingInsertAugment then
            local pa = uiState.pendingInsertAugment
            uiState.pendingInsertAugment = nil
            uiState.itemDisplayAugmentSlotActive = nil
            augmentOps.insertAugment(pa.targetItem, pa.augmentItem, pa.slotIndex, pa.targetBag, pa.targetSlot, pa.targetSource)
            uiState.insertConfirmationSetAt = mq.gettime()
        end
        -- Clear pending quantity pickup if item was picked up manually or QuantityWnd closed or timeout
        if uiState.pendingQuantityPickup then
            local now = mq.gettime()
            if uiState.pendingQuantityPickupTimeoutAt and now >= uiState.pendingQuantityPickupTimeoutAt then
                uiState.pendingQuantityPickup = nil
                uiState.pendingQuantityPickupTimeoutAt = nil
                uiState.quantityPickerValue = ""
                setStatusMessage("Quantity picker cancelled")
            else
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
                    uiState.pendingQuantityPickupTimeoutAt = nil
                    uiState.quantityPickerValue = ""
                end
            elseif hasCursor then
                -- Item is on cursor, clear pending (user picked it up manually)
                uiState.pendingQuantityPickup = nil
                uiState.pendingQuantityPickupTimeoutAt = nil
                uiState.quantityPickerValue = ""
            end
            end
        end
        local invWndLoop = mq.TLO and mq.TLO.Window and mq.TLO.Window("InventoryWindow")
        local invOpen = (invWndLoop and invWndLoop.Open and invWndLoop.Open()) or false
        local bankOpen = isBankWindowOpen()
        local merchOpen = isMerchantWindowOpen()
        local lootOpen = isLootWindowOpen()
        local bankJustOpened = bankOpen and not lastBankWindowState
        local lootJustClosed = lastLootWindowState and not lootOpen
        if lootOpen or lootJustClosed then scanState.inventoryBagsDirty = true end
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
        -- ItemUI never shows while looting (manual or macro). Skip opening bags when loot window open or macro running.
        if invJustOpened and invOpen and not (lootOpen or lootMacRunning) then
            mq.cmd('/keypress OPEN_INV_BAGS')
        end
        -- When looting (manual or macro): keep ItemUI hidden (suppress auto-show and force-hide if already visible)
        if (lootOpen or lootMacRunning) and shouldDraw then
            flushLayoutSave()  -- Persist sort before hiding so next open has correct sort
            shouldDraw = false
            isOpen = false
            uiState.configWindowOpen = false
            if invOpen then mq.cmd('/keypress inventory') end
        end
        -- Do not auto-show ItemUI when loot window is open (manual looting) or loot macro is running
        local shouldAutoShowInv = invJustOpened and not (lootOpen or lootMacRunning)
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
                if bankJustOpened then recordCompanionWindowOpened("bank") end
                uiState.equipmentWindowOpen = true
                uiState.equipmentWindowShouldDraw = true
                recordCompanionWindowOpened("equipment")
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
            uiState.equipmentWindowOpen = true
            uiState.equipmentWindowShouldDraw = true
            recordCompanionWindowOpened("bank")
            recordCompanionWindowOpened("equipment")
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
        -- When user manually opens loot window (no macro running), open Loot UI if not suppressed
        local lootJustOpened = lootOpenNow and not lastLootWindowState
        if lootJustOpened then
            local mn = (mq.TLO.Macro and mq.TLO.Macro.Name and (mq.TLO.Macro.Name() or "") or ""):lower()
            local lootMacRunning = (mn == "loot" or mn == "loot.mac")
            if not lootMacRunning and not uiState.suppressWhenLootMac then
                uiState.lootUIOpen = true
                recordCompanionWindowOpened("loot")
            end
        end
        -- Auto-accept no-drop valuable item confirmation when loot window open
        if lootOpenNow then
            local confirmWnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("ConfirmationDialogBox")
            if confirmWnd and confirmWnd.Open and confirmWnd.Open() then
                mq.cmd('/notify ConfirmationDialogBox CD_Yes_Button leftmouseup')
            end
        end
        -- Augment insert/remove: consistent timeouts and recovery so cursor/window don't get stuck
        local AUGMENT_CURSOR_CLEAR_TIMEOUT_MS = 5000
        local AUGMENT_CURSOR_POPULATED_TIMEOUT_MS = 5000
        local AUGMENT_INSERT_NO_CONFIRM_FALLBACK_MS = 4000
        local AUGMENT_REMOVE_NO_CONFIRM_FALLBACK_MS = 6000

        local itemDisplayOpen = augmentOps.isItemDisplayWindowOpen and augmentOps.isItemDisplayWindowOpen()
        -- If user closed Item Display while we were waiting, clear state so we don't hang
        if uiState.waitingForInsertCursorClear and not itemDisplayOpen then
            uiState.waitingForInsertCursorClear = false
            uiState.insertCursorClearTimeoutAt = nil
            uiState.insertConfirmationSetAt = nil
        end
        if uiState.waitingForRemoveCursorPopulated and not itemDisplayOpen then
            uiState.waitingForRemoveCursorPopulated = false
            uiState.removeCursorPopulatedTimeoutAt = nil
            uiState.removeConfirmationSetAt = nil
        end

        local confirmDialogOpen = false
        do
            local confirmWnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("ConfirmationDialogBox")
            confirmDialogOpen = confirmWnd and confirmWnd.Open and confirmWnd.Open()
        end
        -- Auto-accept augment-remove distiller confirmation when we triggered remove
        if uiState.waitingForRemoveConfirmation and confirmDialogOpen then
            mq.cmd('/notify ConfirmationDialogBox CD_Yes_Button leftmouseup')
            uiState.waitingForRemoveConfirmation = false
            uiState.removeConfirmationSetAt = nil
            uiState.waitingForRemoveCursorPopulated = true
            uiState.removeCursorPopulatedTimeoutAt = mq.gettime()
        end
        -- Auto-accept augment-insert confirmation (e.g. attuneable) when we triggered insert
        if uiState.waitingForInsertConfirmation and confirmDialogOpen then
            mq.cmd('/notify ConfirmationDialogBox CD_Yes_Button leftmouseup')
            uiState.waitingForInsertConfirmation = false
            uiState.insertConfirmationSetAt = nil
            uiState.waitingForInsertCursorClear = true
            uiState.insertCursorClearTimeoutAt = mq.gettime()
        end
        -- Insert: no confirmation dialog appeared (e.g. client doesn't show one) — close window and clear state
        if uiState.waitingForInsertConfirmation and not confirmDialogOpen and uiState.insertConfirmationSetAt and (now - uiState.insertConfirmationSetAt) > AUGMENT_INSERT_NO_CONFIRM_FALLBACK_MS then
            if augmentOps.closeItemDisplayWindow then augmentOps.closeItemDisplayWindow() end
            if not hasItemOnCursor() then
                -- Insert likely succeeded without confirmation
            else
                setStatusMessage("Insert may have failed; check cursor.")
            end
            uiState.waitingForInsertConfirmation = false
            uiState.insertConfirmationSetAt = nil
        end
        -- Remove: no confirmation dialog appeared — close window and clear state; if cursor has item, autoinv
        if uiState.waitingForRemoveConfirmation and not confirmDialogOpen and uiState.removeConfirmationSetAt and (now - uiState.removeConfirmationSetAt) > AUGMENT_REMOVE_NO_CONFIRM_FALLBACK_MS then
            if augmentOps.closeItemDisplayWindow then augmentOps.closeItemDisplayWindow() end
            if hasItemOnCursor() then mq.cmd('/autoinv') end
            uiState.waitingForRemoveConfirmation = false
            uiState.removeConfirmationSetAt = nil
            uiState.waitingForRemoveCursorPopulated = false
            uiState.removeCursorPopulatedTimeoutAt = nil
        end
        -- After insert confirm accepted: poll until cursor clear, then close Item Display; on timeout close window and notify
        if uiState.waitingForInsertCursorClear then
            if (uiState.insertCursorClearTimeoutAt and (now - uiState.insertCursorClearTimeoutAt) > AUGMENT_CURSOR_CLEAR_TIMEOUT_MS) then
                if augmentOps.closeItemDisplayWindow then augmentOps.closeItemDisplayWindow() end
                setStatusMessage("Insert timed out; check cursor.")
                uiState.waitingForInsertCursorClear = false
                uiState.insertCursorClearTimeoutAt = nil
                uiState.insertConfirmationSetAt = nil
                -- Phase 2: if more Optimize steps queued, pop next; else Phase 0 single scan at completion
                if uiState.optimizeQueue and uiState.optimizeQueue.steps and #uiState.optimizeQueue.steps > 0 then
                    local oq = uiState.optimizeQueue
                    local step = table.remove(oq.steps, 1)
                    if step and step.slotIndex and step.augmentItem then
                        local tab = (uiState.itemDisplayTabs and uiState.itemDisplayActiveTabIndex and uiState.itemDisplayTabs[uiState.itemDisplayActiveTabIndex]) or nil
                        local targetItem = (tab and tab.item) and { id = tab.item.id or tab.item.ID, name = tab.item.name or tab.item.Name } or { id = 0, name = "" }
                        uiState.pendingInsertAugment = {
                            targetItem = targetItem,
                            targetBag = oq.targetLoc.bag,
                            targetSlot = oq.targetLoc.slot,
                            targetSource = oq.targetLoc.source or "inv",
                            augmentItem = step.augmentItem,
                            slotIndex = step.slotIndex,
                        }
                    end
                    if #oq.steps == 0 then uiState.optimizeQueue = nil end
                else
                    local hadOptimize = (uiState.optimizeQueue ~= nil)
                    if uiState.optimizeQueue then uiState.optimizeQueue = nil end
                    scanInventory()
                    if isBankWindowOpen() then scanBank() end
                    refreshActiveItemDisplayTab()
                    if hadOptimize and setStatusMessage then setStatusMessage("Optimize complete.") end
                end
            elseif not hasItemOnCursor() then
                if augmentOps.closeItemDisplayWindow then augmentOps.closeItemDisplayWindow() end
                uiState.waitingForInsertCursorClear = false
                uiState.insertCursorClearTimeoutAt = nil
                uiState.insertConfirmationSetAt = nil
                -- Phase 2: if more Optimize steps queued, pop next; else Phase 0 single scan at completion
                if uiState.optimizeQueue and uiState.optimizeQueue.steps and #uiState.optimizeQueue.steps > 0 then
                    local oq = uiState.optimizeQueue
                    local step = table.remove(oq.steps, 1)
                    if step and step.slotIndex and step.augmentItem then
                        local tab = (uiState.itemDisplayTabs and uiState.itemDisplayActiveTabIndex and uiState.itemDisplayTabs[uiState.itemDisplayActiveTabIndex]) or nil
                        local targetItem = (tab and tab.item) and { id = tab.item.id or tab.item.ID, name = tab.item.name or tab.item.Name } or { id = 0, name = "" }
                        uiState.pendingInsertAugment = {
                            targetItem = targetItem,
                            targetBag = oq.targetLoc.bag,
                            targetSlot = oq.targetLoc.slot,
                            targetSource = oq.targetLoc.source or "inv",
                            augmentItem = step.augmentItem,
                            slotIndex = step.slotIndex,
                        }
                    end
                    if #oq.steps == 0 then uiState.optimizeQueue = nil end
                else
                    local hadOptimize = (uiState.optimizeQueue ~= nil)
                    if uiState.optimizeQueue then uiState.optimizeQueue = nil end
                    scanInventory()
                    if isBankWindowOpen() then scanBank() end
                    refreshActiveItemDisplayTab()
                    if hadOptimize and setStatusMessage then setStatusMessage("Optimize complete.") end
                end
            end
        end
        -- After remove confirm accepted: poll until cursor has item, then close Item Display and /autoinv; on timeout close window and notify
        if uiState.waitingForRemoveCursorPopulated then
            if (uiState.removeCursorPopulatedTimeoutAt and (now - uiState.removeCursorPopulatedTimeoutAt) > AUGMENT_CURSOR_POPULATED_TIMEOUT_MS) then
                if augmentOps.closeItemDisplayWindow then augmentOps.closeItemDisplayWindow() end
                setStatusMessage("Remove timed out; check cursor.")
                uiState.waitingForRemoveCursorPopulated = false
                uiState.removeCursorPopulatedTimeoutAt = nil
                uiState.removeConfirmationSetAt = nil
                -- Phase 1: if more Remove All steps queued, pop next; else Phase 0 single scan at completion
                if uiState.removeAllQueue and uiState.removeAllQueue.slotIndices and #uiState.removeAllQueue.slotIndices > 0 then
                    local q = uiState.removeAllQueue
                    local slotIndex = table.remove(q.slotIndices, 1)
                    uiState.pendingRemoveAugment = { bag = q.bag, slot = q.slot, source = q.source, slotIndex = slotIndex }
                    if #q.slotIndices == 0 then uiState.removeAllQueue = nil end
                else
                    local hadRemoveAll = (uiState.removeAllQueue ~= nil)
                    if uiState.removeAllQueue then uiState.removeAllQueue = nil end
                    scanInventory()
                    if isBankWindowOpen() then scanBank() end
                    refreshActiveItemDisplayTab()
                    if hadRemoveAll and setStatusMessage then setStatusMessage("Remove all done.") end
                end
            elseif hasItemOnCursor() then
                if augmentOps.closeItemDisplayWindow then augmentOps.closeItemDisplayWindow() end
                mq.cmd('/autoinv')
                uiState.waitingForRemoveCursorPopulated = false
                uiState.removeCursorPopulatedTimeoutAt = nil
                uiState.removeConfirmationSetAt = nil
                -- Phase 1: if more Remove All steps queued, pop next; else Phase 0 single scan at completion
                if uiState.removeAllQueue and uiState.removeAllQueue.slotIndices and #uiState.removeAllQueue.slotIndices > 0 then
                    local q = uiState.removeAllQueue
                    local slotIndex = table.remove(q.slotIndices, 1)
                    uiState.pendingRemoveAugment = { bag = q.bag, slot = q.slot, source = q.source, slotIndex = slotIndex }
                    if #q.slotIndices == 0 then uiState.removeAllQueue = nil end
                else
                    local hadRemoveAll = (uiState.removeAllQueue ~= nil)
                    if uiState.removeAllQueue then uiState.removeAllQueue = nil end
                    scanInventory()
                    if isBankWindowOpen() then scanBank() end
                    refreshActiveItemDisplayTab()
                    if hadRemoveAll and setStatusMessage then setStatusMessage("Remove all done.") end
                end
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