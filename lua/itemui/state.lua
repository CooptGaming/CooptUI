--[[
    ItemUI state table definitions (Task 6.3 extraction from init.lua).
    Pure state only; no requires of views/registry/ops. Metatables for uiState/sortState
    are applied in init.lua where those module refs exist.
--]]

require('ImGui')  -- state.lua uses ImGuiSortDirection.*; explicit require avoids load-order dependency
local CoopVersion = require('coopui.version')
local constants = require('itemui.constants')

local C = constants.buildC(CoopVersion.ITEMUI)

-- Scalars
local isOpen, shouldDraw, terminate = true, false, false
local transferStampPath, lastTransferStamp = nil, 0
local lastInventoryWindowState, lastBankWindowState, lastMerchantState, lastLootWindowState = false, false, false, false
local statsTabPrimeState, statsTabPrimeAt = nil, 0
local statsTabPrimedThisSession = false

-- Data tables
local inventoryItems, bankItems, lootItems = {}, {}, {}
local equipmentCache = {}
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
    timerReadyCache = {},
    timerReadyMaxCache = {},
    lastScanTimeInv = 0,
    lastBankCacheTime = 0,
    sellLogPath = nil,
    sellConfigPendingRefresh = false,
    loreHaveCache = {},
}

local uiState = {
    windowPositioned = false,
    alignToContext = true,
    uiLocked = true,
    suppressWhenLootMac = false,
    itemUIPositionX = nil, itemUIPositionY = nil,
    setupMode = false, setupStep = 0,
    revertLayoutConfirmOpen = false,
    diagnosticsPanelOpen = false,
    layoutRevertedApplyFrames = 0,
    resetWindowPositionsRequested = false,
    searchFilterInv = "", searchFilterBank = "",
    autoSellRequested = false, showOnlySellable = false,
    companionWindowOpenedAt = {},
    statusMessage = "", statusMessageTime = 0,
    confirmBeforeDelete = true,
    deferredInventoryScanAt = nil,
    pendingStatRescanBags = nil,
}

-- Layout from setup (itemui_layout.ini)
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
    layoutDefaults.ShowEquipmentWindow = 1
    layoutDefaults.ShowBankWindow = 1
    layoutDefaults.ShowAugmentsWindow = 1
    layoutDefaults.ShowAugmentUtilityWindow = 1
    layoutDefaults.ShowItemDisplayWindow = 1
    layoutDefaults.ShowConfigWindow = 1
    layoutDefaults.ShowRerollWindow = 1
    layoutDefaults.WidthRerollPanel = (constants.VIEWS and constants.VIEWS.WidthRerollPanel) or 520
    layoutDefaults.HeightReroll = (constants.VIEWS and constants.VIEWS.HeightReroll) or 480
    layoutDefaults.RerollWindowX = 0
    layoutDefaults.RerollWindowY = 0
    layoutDefaults.AABackupPath = ""
    layoutDefaults.AlignToContext = 1
    layoutDefaults.UILocked = 1
    layoutDefaults.SuppressWhenLootMac = 0
    layoutDefaults.ConfirmBeforeDelete = 1
    layoutDefaults.ActivationGuardEnabled = 1
end

local layoutConfig = {}

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

local sortState = {
    sellColumn = "Name",
    sellDirection = ImGuiSortDirection.Ascending,
    invColumn = "Name",
    invDirection = ImGuiSortDirection.Ascending,
    invColumnOrder = nil,
    bankColumn = "Name",
    bankDirection = ImGuiSortDirection.Ascending,
    bankColumnOrder = nil,
    aaColumn = "Title",
    aaDirection = ImGuiSortDirection.Ascending,
}

local sellItems = {}
local sellMacState = { lastRunning = false, pendingScan = false, finishedAt = 0, failedItems = {}, failedCount = 0, showFailedUntil = 0, smoothedFrac = 0 }
local lootMacState = { lastRunning = false, pendingScan = false, finishedAt = 0 }
local lootLoopRefs = {
    pollMs = constants.TIMING.LOOT_POLL_MS,
    pollMsIdle = constants.TIMING.LOOT_POLL_MS_IDLE,
    pollAt = 0,
    deferMs = constants.TIMING.LOOT_DEFER_MS,
    saveHistoryAt = 0,
    saveSkipAt = 0,
    sellStatusCap = constants.LIMITS.LOOT_SELL_STATUS_CAP,
    pendingSession = false,
    pendingSessionAt = 0,
}
local LOOT_HISTORY_MAX = constants.LIMITS.LOOT_HISTORY_MAX
local LOOT_HISTORY_DELIM = "\1"

local bankCache = {}
local scanState = {
    lastScanTimeBank = 0,
    lastPersistSaveTime = 0,
    lastInventoryFingerprint = "",
    lastScanState = { invOpen = false, bankOpen = false, merchOpen = false, lootOpen = false },
    lastBagFingerprints = {},
    nextAcquiredSeq = 1,
    lastGetChangedBagsTime = 0,
    inventoryBagsDirty = false,
    --- Task 6.3: set when computeAndAttachSellStatus runs; cleared when a scan updates item lists. Used to skip redundant status computation.
    sellStatusAttachedAt = nil,
}
local deferredScanNeeded = { inventory = false, bank = false, sell = false }

return {
    C = C,
    isOpen = isOpen,
    shouldDraw = shouldDraw,
    terminate = terminate,
    transferStampPath = transferStampPath,
    lastTransferStamp = lastTransferStamp,
    lastInventoryWindowState = lastInventoryWindowState,
    lastBankWindowState = lastBankWindowState,
    lastMerchantState = lastMerchantState,
    lastLootWindowState = lastLootWindowState,
    statsTabPrimeState = statsTabPrimeState,
    statsTabPrimeAt = statsTabPrimeAt,
    statsTabPrimedThisSession = statsTabPrimedThisSession,
    inventoryItems = inventoryItems,
    bankItems = bankItems,
    lootItems = lootItems,
    equipmentCache = equipmentCache,
    perfCache = perfCache,
    uiState = uiState,
    layoutDefaults = layoutDefaults,
    layoutConfig = layoutConfig,
    filterState = filterState,
    sortState = sortState,
    sellItems = sellItems,
    sellMacState = sellMacState,
    lootMacState = lootMacState,
    lootLoopRefs = lootLoopRefs,
    LOOT_HISTORY_MAX = LOOT_HISTORY_MAX,
    LOOT_HISTORY_DELIM = LOOT_HISTORY_DELIM,
    bankCache = bankCache,
    scanState = scanState,
    deferredScanNeeded = deferredScanNeeded,
}
