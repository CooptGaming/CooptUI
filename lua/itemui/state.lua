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
local transferStampPath = nil
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
    enableRealTimeLoot = true,
    enableLootHistory = false,
    enableSkipHistory = false,
    itemUIPositionX = nil, itemUIPositionY = nil,
    setupMode = false, setupStep = 0,
    revertLayoutConfirmOpen = false,
    diagnosticsPanelOpen = false,
    layoutRevertedApplyFrames = 0,
    resetWindowPositionsRequested = false,
    searchFilterInv = "", searchFilterBank = "",
    autoSellRequested = false, showOnlySellable = false,
    nativeMerchantStrip = true, nativePreviewRequested = false,
    nativeHoverTooltip = true,
    nativeItemDisplayReplace = true,
    companionWindowOpenedAt = {},
    statusMessage = "", statusMessageTime = 0,
    confirmBeforeDelete = true,
    deferredInventoryScanAt = nil,
    pendingStatRescanBags = nil,
    rerollPendingScan = false,
    rerollPendingScanAt = 0,
    userClosedViaKeybind = false,  -- when true, main loop won't auto-reopen until inv/bank/merchant close
}

-- Layout from setup (itemui_layout.ini)
local layoutDefaults = {}
do
    local V = constants.VIEWS
    for k, v in pairs(V) do layoutDefaults[k] = v end
    layoutDefaults.BankWindowX = 0
    layoutDefaults.BankWindowY = 0
    -- Merged Inventory (phase 10): bags-pane width in px. 0 = auto (55% of the content
    -- region); any positive value is the user's dragged splitter position.
    layoutDefaults.InventoryBankSplitX = 0
    -- Script Tracker (phase 15): 0,0 = hub-relative default on first open.
    layoutDefaults.ScriptTrackerWindowX = 0
    layoutDefaults.ScriptTrackerWindowY = 0
    layoutDefaults.AugmentsWindowX = 0
    layoutDefaults.AugmentsWindowY = 0
    layoutDefaults.MythicalsWindowX = 0
    layoutDefaults.MythicalsWindowY = 0
    layoutDefaults.CommandCenterWindowX = 0
    layoutDefaults.CommandCenterWindowY = 0
    layoutDefaults.FavoritesWindowX = 0
    layoutDefaults.FavoritesWindowY = 0
    layoutDefaults.EffectsWindowX = 0
    layoutDefaults.EffectsWindowY = 0
    layoutDefaults.ChatWindowX = 0
    layoutDefaults.ChatWindowY = 0
    layoutDefaults.WidthChatPanel = 560
    layoutDefaults.HeightChat = 380
    layoutDefaults.ShowChatWindow = 1
    -- Chat console renderer. 1 = MQ's Zep console (clickable item links, real scrollback);
    -- 0 = the built-in ring-buffer renderer.
    --
    -- Back ON as of 2026-07-31: the client-crash-on-stop was never Zep itself but WHERE it
    -- got required. sol2's usertype storage unrefs through the lua_State that registered it,
    -- and requiring from a render callback handed it the ImGui coroutine thread, which dies
    -- before finalization (dangling state -> lua_rawgeti null-deref -> client down).
    -- app.lua now prewarms it on the MAIN thread at startup and no console stores a Lua
    -- callback, so nothing outlives its state. See services/chat_console.lua for the full
    -- mechanism; set 0 here (or untick Settings > General) if a console ever misbehaves.
    layoutDefaults.ChatUseZep = 1
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
    layoutDefaults.EnableRealTimeLoot = 0
    layoutDefaults.EnableLootHistory = 0
    layoutDefaults.EnableSkipHistory = 0
    layoutDefaults.ConfirmBeforeDelete = 1
    layoutDefaults.ActivationGuardEnabled = 1
    layoutDefaults.ItemUIToggleKey = "shift+q"  -- Key to toggle ItemUI (uses MQ2CustomBinds itemui_inv); empty = no bind
    -- Dock / bars mode. UIMode stays "classic" until the first-run rework ships: classic must
    -- render exactly what master renders, so an existing install sees no change until the user
    -- opts in from Settings -> Dock. The Dock* keys below only matter once UIMode is "bars".
    layoutDefaults.UIMode = "classic"
    layoutDefaults.DockTop = 1
    layoutDefaults.DockBottom = 1
    layoutDefaults.DockPosition = "top"
    layoutDefaults.DockChat = "collapsed"
    -- Phase 13 (26a): DockSegments is an ENABLE SET now — the bar's order is canonical
    -- (identity, session, bags, sell, [buttons], [lane], buffs, xp) and never stored.
    -- The retired "loot" id in older INIs is skipped harmlessly: the action lane took
    -- over every loot state and is not disable-able.
    layoutDefaults.DockSegments = "status,session,bags,sell,buffs,xp"
    -- Bottom-bar style: hover menus (today's default, unchanged for existing installs) or a
    -- flat row of launcher buttons (mockup's second option). DockButtons is only consulted
    -- when DockBottomStyle is "buttons".
    layoutDefaults.DockBottomStyle = "menus"
    -- 23c order: the two pairs first (bags+bank collapse into the Bags|Bank chip;
    -- itemDisplay+augmentUtility into Item Display|Aug Utility), then the standalones.
    -- "augments" left out: that window folded into Aug Utility's All tab (phase 11) and
    -- the id is classicOnly-dead on the bar; saved CSVs that still carry it just skip it.
    layoutDefaults.DockButtons = "bags,bank,itemDisplay,augmentUtility,equipment,effects,mythicals,reroll,aa"
    layoutDefaults.ZoneAssign = ""
    layoutDefaults.WindowAttach = ""
    layoutDefaults.LayoutPreset = ""
    layoutDefaults.UserPlaced = ""
end

local layoutConfig = {}

local filterState = {
    configTab = 1,
    filterSubTab = 1,
    keybindDebounceAt = nil,   -- when user last edited ItemUIToggleKey (for debounce)
    keybindDebounceValue = nil,
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
    --- Session floor for the Inventory "NEW" badge: stamped once at startup (snapshot restore
    --- or after the initial scan); items with acquiredSeq >= this were acquired this session.
    sessionStartAcquiredSeq = nil,
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
