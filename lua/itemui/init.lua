--[[
    CoopUI - ItemUI
    Purpose: Unified Inventory / Bank / Sell / Loot Interface
    Part of CoopUI — EverQuest EMU Companion
    Author: Perky's Crew
    Version: 1.0.0-rc1
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
    Uses same config paths as SellUI for keep/junk lists.

    Usage: /lua run itemui
    Toggle: /itemui   Setup: /itemui setup

    NOTE: Lua has a 200 local variable limit per scope. To avoid hitting this limit,
    related state is consolidated into tables (filterState, sortState). When adding
    new state variables, consider adding them to an existing table or creating a
    new consolidated table rather than adding new top-level locals.
--]]

local mq = require('mq')
require('ImGui')
local config = require('itemui.config')
local config_cache = require('itemui.config_cache')
local context = require('itemui.context')
local rules = require('itemui.rules')
local storage = require('itemui.storage')
local ItemUtils = require('mq.ItemUtils')

-- Phase 2: Core infrastructure (state/events/cache unused; sort cache lives in perfCache)

-- Phase 3: Filter system modules
local filterService = require('itemui.services.filter_service')
local searchbar = require('itemui.components.searchbar')
local filtersComponent = require('itemui.components.filters')

-- Phase 5: Macro integration service
local macroBridge = require('itemui.services.macro_bridge')
local scanService = require('itemui.services.scan')

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

-- Constants (consolidated for Lua 200-local limit)
local C = {
    VERSION = "1.0.0-rc1",
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
    SPELL_CACHE_MAX = 128,
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
    configWindowOpen = false, configNeedsLoad = false,
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

--- Set in-UI status (Keep/Junk, moves, sell). Safe: trims, coerces to string, truncates.
local function setStatusMessage(msg)
    if msg == nil then return end
    msg = (type(msg) == "string" and msg:match("^%s*(.-)%s*$")) or tostring(msg)
    if msg == "" then return end
    if #msg > C.STATUS_MSG_MAX_LEN then
        msg = msg:sub(1, C.STATUS_MSG_MAX_LEN - 3) .. "..."
    end
    uiState.statusMessage = msg
    uiState.statusMessageTime = mq.gettime()
end

--- Phase 6.1: Format copper value to readable currency string
local function formatCurrency(copper)
    if not copper or copper == 0 then return "0c" end
    copper = math.floor(copper)
    
    local plat = math.floor(copper / 1000)
    local gold = math.floor((copper % 1000) / 100)
    local silver = math.floor((copper % 100) / 10)
    local c = copper % 10
    
    local parts = {}
    if plat > 0 then table.insert(parts, string.format("%dp", plat)) end
    if gold > 0 then table.insert(parts, string.format("%dg", gold)) end
    if silver > 0 then table.insert(parts, string.format("%ds", silver)) end
    if c > 0 or #parts == 0 then table.insert(parts, string.format("%dc", c)) end
    
    return table.concat(parts, " ")
end

-- Spell/spellConfig caches (in perfCache to reduce local count)
perfCache.sellConfigCache = nil
perfCache.spellNameCache = {}
perfCache.spellDescCache = {}
local function getSpellName(id)
    if not id or id <= 0 then return nil end
    local name = perfCache.spellNameCache[id]
    if name ~= nil then return name end
    local s = mq.TLO.Spell(id)
    name = s and s.Name and s.Name() or "Unknown"
    if #perfCache.spellNameCache >= C.SPELL_CACHE_MAX then
        local first = next(perfCache.spellNameCache)
        if first then perfCache.spellNameCache[first] = nil end
    end
    perfCache.spellNameCache[id] = name
    return name
end

local function getSpellDescription(id)
    if not id or id <= 0 then return nil end
    local desc = perfCache.spellDescCache[id]
    if desc ~= nil then return desc end
    local s = mq.TLO.Spell(id)
    desc = s and s.Description and s.Description() or ""
    if #perfCache.spellDescCache >= C.SPELL_CACHE_MAX then
        local first = next(perfCache.spellDescCache)
        if first then perfCache.spellDescCache[first] = nil end
    end
    perfCache.spellDescCache[id] = desc
    return desc
end

--- Build a compact stats summary string for an item (AC, HP, mana, attributes, etc.).
-- Used by Augments view to show which stats an augmentation provides.
local function getItemStatsSummary(item)
    if not item then return "" end
    local parts = {}
    if (item.ac or 0) ~= 0 then parts[#parts + 1] = string.format("%d AC", item.ac) end
    if (item.hp or 0) ~= 0 then parts[#parts + 1] = string.format("%d HP", item.hp) end
    if (item.mana or 0) ~= 0 then parts[#parts + 1] = string.format("%d Mana", item.mana) end
    if (item.endurance or 0) ~= 0 then parts[#parts + 1] = string.format("%d End", item.endurance) end
    local function addStat(abbr, val) if (val or 0) ~= 0 then parts[#parts + 1] = string.format("%d %s", val, abbr) end end
    addStat("STR", item.str); addStat("STA", item.sta); addStat("AGI", item.agi); addStat("DEX", item.dex)
    addStat("INT", item.int); addStat("WIS", item.wis); addStat("CHA", item.cha)
    if (item.attack or 0) ~= 0 then parts[#parts + 1] = string.format("%d Atk", item.attack) end
    if (item.accuracy or 0) ~= 0 then parts[#parts + 1] = string.format("%d Acc", item.accuracy) end
    if (item.avoidance or 0) ~= 0 then parts[#parts + 1] = string.format("%d Avoid", item.avoidance) end
    if (item.shielding or 0) ~= 0 then parts[#parts + 1] = string.format("%d Shield", item.shielding) end
    if (item.haste or 0) ~= 0 then parts[#parts + 1] = string.format("%d Haste", item.haste) end
    if (item.spellDamage or 0) ~= 0 then parts[#parts + 1] = string.format("%d SD", item.spellDamage) end
    if (item.strikeThrough or 0) ~= 0 then parts[#parts + 1] = string.format("%d ST", item.strikeThrough) end
    if (item.damageShield or 0) ~= 0 then parts[#parts + 1] = string.format("%d DS", item.damageShield) end
    if (item.combatEffects or 0) ~= 0 then parts[#parts + 1] = string.format("%d CE", item.combatEffects) end
    if (item.hpRegen or 0) ~= 0 then parts[#parts + 1] = string.format("%d HP Regen", item.hpRegen) end
    if (item.manaRegen or 0) ~= 0 then parts[#parts + 1] = string.format("%d Mana Regen", item.manaRegen) end
    addStat("HSTR", item.heroicSTR); addStat("HSTA", item.heroicSTA); addStat("HAGI", item.heroicAGI)
    addStat("HDEX", item.heroicDEX); addStat("HINT", item.heroicINT); addStat("HWIS", item.heroicWIS); addStat("HCHA", item.heroicCHA)
    if (item.svMagic or 0) ~= 0 then parts[#parts + 1] = string.format("%d SvM", item.svMagic) end
    if (item.svFire or 0) ~= 0 then parts[#parts + 1] = string.format("%d SvF", item.svFire) end
    if (item.svCold or 0) ~= 0 then parts[#parts + 1] = string.format("%d SvC", item.svCold) end
    if (item.svPoison or 0) ~= 0 then parts[#parts + 1] = string.format("%d SvP", item.svPoison) end
    if (item.svDisease or 0) ~= 0 then parts[#parts + 1] = string.format("%d SvD", item.svDisease) end
    if (item.svCorruption or 0) ~= 0 then parts[#parts + 1] = string.format("%d SvCorr", item.svCorruption) end
    return table.concat(parts, ", ")
end

local function loadSellConfigCache()
    perfCache.sellConfigCache = rules.loadSellConfigCache()
end

local function invalidateSellConfigCache()
    perfCache.sellConfigCache = nil
end

local function invalidateLootConfigCache()
    perfCache.lootConfigCache = nil
end

-- Lazy spell ID fetch: defers 5 TLO calls per item from scan to first display (major scan perf win)
local function getItemSpellId(item, prop)
    if not item or not prop then return 0 end
    local key = prop:lower()
    if item[key] ~= nil then return item[key] or 0 end
    local pack = mq.TLO.Me and mq.TLO.Me.Inventory and mq.TLO.Me.Inventory("pack" .. (item.bag or 0))
    if not pack then item[key] = 0; return 0 end
    local slotItem = pack.Item and pack.Item(item.slot or 0)
    if not slotItem then item[key] = 0; return 0 end
    local spellObj = slotItem[prop]
    if not spellObj then item[key] = 0; return 0 end
    local id = 0
    if spellObj.SpellID then id = spellObj.SpellID() or 0 end
    if (not id or id == 0) and spellObj.Spell and spellObj.Spell.ID then id = spellObj.Spell.ID() or 0 end
    item[key] = (id and id > 0) and id or 0
    return item[key]
end

-- TimerReady cache: TTL 1.5s (cooldowns in seconds; reduces TLO calls ~33%)
local function getTimerReady(bag, slot)
    if not bag or not slot then return 0 end
    local key = bag .. "_" .. slot
    local now = mq.gettime()
    local entry = perfCache.timerReadyCache[key]
    if entry and (now - entry.at) < C.TIMER_READY_CACHE_TTL_MS then
        return entry.ready or 0
    end
    local itemTLO = mq.TLO.Me.Inventory("pack" .. bag).Item(slot)
    local ready = (itemTLO and itemTLO.TimerReady and itemTLO.TimerReady()) or 0
    perfCache.timerReadyCache[key] = { ready = ready, at = now }
    return ready
end


-- ============================================================================
-- Layout Management (Phase 7: Delegated to utils/layout.lua)
-- ============================================================================
local function getLayoutFilePath() return layoutUtils.getLayoutFilePath() end
local function parseLayoutFileFull() return layoutUtils.parseLayoutFileFull() end
local function applyDefaultsFromParsed(parsed) layoutUtils.applyDefaultsFromParsed(parsed) end
local function applyColumnVisibilityFromParsed(parsed) layoutUtils.applyColumnVisibilityFromParsed(parsed) end
local function loadColumnVisibility() layoutUtils.loadColumnVisibility() end
local function parseLayoutFile() return layoutUtils.parseLayoutFile() end
local function loadLayoutValue(layout, key, default) return layoutUtils.loadLayoutValue(layout, key, default) end
local function scheduleLayoutSave() layoutUtils.scheduleLayoutSave() end
local function saveLayoutToFileImmediate() layoutUtils.saveLayoutToFileImmediate() end
local function flushLayoutSave() layoutUtils.flushLayoutSave() end
local function saveColumnVisibility() layoutUtils.saveColumnVisibility() end
local function getFixedColumns(view) return layoutUtils.getFixedColumns(view) end
local function toggleFixedColumn(view, colKey) return layoutUtils.toggleFixedColumn(view, colKey) end
local function isColumnInFixedSet(view, colKey) return layoutUtils.isColumnInFixedSet(view, colKey) end
local function saveLayoutToFile() layoutUtils.saveLayoutToFile() end
local function captureCurrentLayoutAsDefault() layoutUtils.captureCurrentLayoutAsDefault() end
local function resetLayoutToDefault() layoutUtils.resetLayoutToDefault() end
local function loadLayoutConfig() layoutUtils.loadLayoutConfig() end
local function saveLayoutForView(view, w, h, bankPanelW) layoutUtils.saveLayoutForView(view, w, h, bankPanelW) end

local function invalidateSortCache(view)
    local c = view == "inv" and perfCache.inv or view == "sell" and perfCache.sell or view == "bank" and perfCache.bank or view == "loot" and perfCache.loot
    if c then c.key = nil end
    if view == "inv" then perfCache.invTotalSlots = nil; perfCache.invTotalValue = nil end
end

local function invalidateTimerReadyCache()
    perfCache.timerReadyCache = {}
end

local function isBankWindowOpen()
    local w = mq.TLO.Window("BigBankWnd")
    return w and w.Open and w.Open() or false
end
local function isMerchantWindowOpen()
    local w = mq.TLO.Window("MerchantWnd")
    return w and w.Open and w.Open() or false
end
local function isLootWindowOpen()
    local w = mq.TLO.Window("LootWnd")
    return w and w.Open and w.Open() or false
end
--- Close the default EQ inventory window (and bags) if open. Call when user closes ItemUI.
local function closeGameInventoryIfOpen()
    local invWnd = mq.TLO.Window("InventoryWindow")
    if invWnd and invWnd.Open and invWnd.Open() then
        mq.cmd("/keypress inventory")
    end
end

-- ============================================================================
-- buildItemFromMQ - Extract all item properties from MQ item TLO (per iteminfo.mac)
-- Returns a table with all available properties; users can add/remove columns as desired.
-- ============================================================================
local function buildItemFromMQ(item, bag, slot)
    if not item or not item.ID or not item.ID() or item.ID() == 0 then return nil end
    local iv = item.Value and item.Value() or 0
    local ss = item.Stack and item.Stack() or 1
    if ss < 1 then ss = 1 end
    local stackSizeMax = item.StackSize and item.StackSize() or ss
    -- Spell IDs deferred to getItemSpellId (lazy fetch on first display) - saves ~5 TLO calls per item during scan
    local base = {
        bag = bag, slot = slot,
        name = item.Name and item.Name() or "",
        id = item.ID and item.ID() or 0,
        value = iv, totalValue = iv * ss, stackSize = ss, stackSizeMax = stackSizeMax,
        type = item.Type and item.Type() or "",
        weight = item.Weight and item.Weight() or 0,
        icon = item.Icon and item.Icon() or 0,
        itemLink = item.ItemLink and item.ItemLink() or "",
        tribute = item.Tribute and item.Tribute() or 0,
        size = item.Size and item.Size() or 0,
        sizeCapacity = item.SizeCapacity and item.SizeCapacity() or 0,
        container = item.Container and item.Container() or 0,
        nodrop = item.NoDrop and item.NoDrop() or false,
        notrade = item.NoTrade and item.NoTrade() or false,
        norent = item.NoRent and item.NoRent() or false,
        lore = item.Lore and item.Lore() or false,
        magic = item.Magic and item.Magic() or false,
        attuneable = item.Attuneable and item.Attuneable() or false,
        heirloom = item.Heirloom and item.Heirloom() or false,
        prestige = item.Prestige and item.Prestige() or false,
        collectible = item.Collectible and item.Collectible() or false,
        quest = item.Quest and item.Quest() or false,
        tradeskills = item.Tradeskills and item.Tradeskills() or false,
        class = item.Class and item.Class() or "",
        race = item.Race and item.Race() or "",
        wornSlots = item.WornSlots and item.WornSlots() or "",
        requiredLevel = item.RequiredLevel and item.RequiredLevel() or 0,
        recommendedLevel = item.RecommendedLevel and item.RecommendedLevel() or 0,
        augSlots = (item.AugSlot1 and item.AugSlot1() and 1 or 0) + (item.AugSlot2 and item.AugSlot2() and 1 or 0) +
                   (item.AugSlot3 and item.AugSlot3() and 1 or 0) + (item.AugSlot4 and item.AugSlot4() and 1 or 0) +
                   (item.AugSlot5 and item.AugSlot5() and 1 or 0),
        -- clicky, proc, focus, worn, spell: nil = not yet fetched; getItemSpellId fetches lazily on first use
        instrumentType = item.InstrumentType and item.InstrumentType() or "",
        instrumentMod = item.InstrumentMod and item.InstrumentMod() or 0,
        -- Item stats (AC, HP, mana, attributes, etc. - used by Augments view; MQ Item TLO has these)
        ac = (item.AC and item.AC()) or 0,
        hp = (item.HP and item.HP()) or 0,
        mana = (item.Mana and item.Mana()) or 0,
        endurance = (item.Endurance and item.Endurance()) or 0,
        str = (item.STR and item.STR()) or 0,
        sta = (item.STA and item.STA()) or 0,
        agi = (item.AGI and item.AGI()) or 0,
        dex = (item.DEX and item.DEX()) or 0,
        int = (item.INT and item.INT()) or 0,
        wis = (item.WIS and item.WIS()) or 0,
        cha = (item.CHA and item.CHA()) or 0,
        attack = (item.Attack and item.Attack()) or 0,
        accuracy = (item.Accuracy and item.Accuracy()) or 0,
        avoidance = (item.Avoidance and item.Avoidance()) or 0,
        shielding = (item.Shielding and item.Shielding()) or 0,
        haste = (item.Haste and item.Haste()) or 0,
        damage = (item.Damage and item.Damage()) or 0,
        itemDelay = (item.ItemDelay and item.ItemDelay()) or 0,
        dmgBonus = (item.DMGBonus and item.DMGBonus()) or 0,
        spellDamage = (item.SpellDamage and item.SpellDamage()) or 0,
        strikeThrough = (item.StrikeThrough and item.StrikeThrough()) or 0,
        damageShield = (item.DamShield and item.DamShield()) or 0,
        combatEffects = (item.CombatEffects and item.CombatEffects()) or 0,
        dotShielding = (item.DoTShielding and item.DoTShielding()) or 0,
        hpRegen = (item.HPRegen and item.HPRegen()) or 0,
        manaRegen = (item.ManaRegen and item.ManaRegen()) or 0,
        enduranceRegen = (item.EnduranceRegen and item.EnduranceRegen()) or 0,
        heroicSTR = (item.HeroicSTR and item.HeroicSTR()) or 0,
        heroicSTA = (item.HeroicSTA and item.HeroicSTA()) or 0,
        heroicAGI = (item.HeroicAGI and item.HeroicAGI()) or 0,
        heroicDEX = (item.HeroicDEX and item.HeroicDEX()) or 0,
        heroicINT = (item.HeroicINT and item.HeroicINT()) or 0,
        heroicWIS = (item.HeroicWIS and item.HeroicWIS()) or 0,
        heroicCHA = (item.HeroicCHA and item.HeroicCHA()) or 0,
        svMagic = (item.svMagic and item.svMagic()) or 0,
        svFire = (item.svFire and item.svFire()) or 0,
        svCold = (item.svCold and item.svCold()) or 0,
        svPoison = (item.svPoison and item.svPoison()) or 0,
        svDisease = (item.svDisease and item.svDisease()) or 0,
        svCorruption = (item.svCorruption and item.svCorruption()) or 0,
    }
    -- Spell names fetched lazily on first render (getSpellName has cache); avoids 5 TLO.Spell calls per item during scan
    return base
end

-- ============================================================================
-- Sell logic (delegates to itemui.rules; same INI files as SellUI)
-- ============================================================================
local function isInKeepList(itemName)
    if not perfCache.sellConfigCache then loadSellConfigCache() end
    return rules.isInKeepList(itemName, perfCache.sellConfigCache)
end
local function isInJunkList(itemName)
    if not perfCache.sellConfigCache then loadSellConfigCache() end
    return rules.isInJunkList(itemName, perfCache.sellConfigCache)
end
local function isProtectedType(itemType)
    if not perfCache.sellConfigCache then loadSellConfigCache() end
    return rules.isProtectedType(itemType, perfCache.sellConfigCache)
end
local function isKeptByContains(itemName)
    if not perfCache.sellConfigCache then loadSellConfigCache() end
    return rules.isKeptByContains(itemName, perfCache.sellConfigCache)
end
local function isKeptByType(itemType)
    if not perfCache.sellConfigCache then loadSellConfigCache() end
    return rules.isKeptByType(itemType, perfCache.sellConfigCache)
end
local function willItemBeSold(itemData)
    if not perfCache.sellConfigCache then loadSellConfigCache() end
    return rules.willItemBeSold(itemData, perfCache.sellConfigCache)
end
--- Refresh stored-inv-by-name cache if missing or older than C.STORED_INV_CACHE_TTL_MS (single path for computeAndAttachSellStatus and getSellStatusForItem).
local function refreshStoredInvByNameIfNeeded()
    if perfCache.storedInvByName and (mq.gettime() - (perfCache.storedInvByNameTime or 0)) <= C.STORED_INV_CACHE_TTL_MS then
        return
    end
    local stored, _ = storage.loadInventory()
    perfCache.storedInvByName = {}
    if stored and #stored > 0 then
        for _, it in ipairs(stored) do
            local n = (it.name or ""):match("^%s*(.-)%s*$")
            if n ~= "" and (it.inKeep ~= nil or it.inJunk ~= nil) then
                perfCache.storedInvByName[n] = { inKeep = it.inKeep, inJunk = it.inJunk }
            end
        end
    end
    perfCache.storedInvByNameTime = mq.gettime()
end

--- Compute and attach willSell/sellReason to each item (for cache and sell_cache.ini).
-- Uses same logic as getSellStatusForItem; call before saving inventory so macro can use sell list.
computeAndAttachSellStatus = function(items)
    if not items or #items == 0 then return end
    if not perfCache.sellConfigCache then loadSellConfigCache() end
    refreshStoredInvByNameIfNeeded()
    for _, item in ipairs(items) do
        local inKeep = isInKeepList(item.name) or isKeptByContains(item.name) or isKeptByType(item.type)
        local inJunk = isInJunkList(item.name)
        local storedItem = perfCache.storedInvByName[(item.name or ""):match("^%s*(.-)%s*$")]
        if storedItem then
            if storedItem.inKeep ~= nil then inKeep = storedItem.inKeep end
            if storedItem.inJunk ~= nil then inJunk = storedItem.inJunk end
        end
        local itemData = {
            name = item.name, type = item.type, value = item.value, totalValue = item.totalValue,
            stackSize = item.stackSize or 1, nodrop = item.nodrop, notrade = item.notrade,
            lore = item.lore, quest = item.quest, collectible = item.collectible, heirloom = item.heirloom,
            inKeep = inKeep, inJunk = inJunk
        }
        local willSell, reason = willItemBeSold(itemData)
        item.willSell = willSell
        item.sellReason = reason or ""
    end
end

--- Return sell filter status for an inventory item: reason string and whether it would be sold.
-- Uses same logic as sell view: keep list (exact + contains + type) and stored snapshot override.
local function getSellStatusForItem(item)
    if not item then return "", false end
    -- Align with scanSellItems: inKeep = exact OR contains OR type
    local inKeep = isInKeepList(item.name) or isKeptByContains(item.name) or isKeptByType(item.type)
    local inJunk = isInJunkList(item.name)
    refreshStoredInvByNameIfNeeded()
    local storedItem = perfCache.storedInvByName[(item.name or ""):match("^%s*(.-)%s*$")]
    if storedItem then
        if storedItem.inKeep ~= nil then inKeep = storedItem.inKeep end
        if storedItem.inJunk ~= nil then inJunk = storedItem.inJunk end
    end
    local itemData = {
        name = item.name, type = item.type, value = item.value, totalValue = item.totalValue,
        stackSize = item.stackSize or 1, nodrop = item.nodrop, notrade = item.notrade,
        lore = item.lore, quest = item.quest, collectible = item.collectible, heirloom = item.heirloom,
        inKeep = inKeep, inJunk = inJunk
    }
    local willSell, reason = willItemBeSold(itemData)
    return reason or "", willSell, inKeep, inJunk
end

-- Config cache init (requires isInKeepList, isInJunkList above)
config_cache.init({
    setStatusMessage = setStatusMessage,
    invalidateSellConfigCache = invalidateSellConfigCache,
    invalidateLootConfigCache = invalidateLootConfigCache,
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

-- Sell queue (like original SellUI): queueItemForSelling from UI; processSellQueue from main loop (must be defined after scanSellItems)
local sellQueue = {}
local isSelling = false
local function queueItemForSelling(itemData)
    if isSelling then
        setStatusMessage("Already selling, please wait...")
        return false
    end
    table.insert(sellQueue, { name = itemData.name, bag = itemData.bag, slot = itemData.slot, id = itemData.id })
    setStatusMessage("Queued for sell")
    return true
end

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
        invalidateSortCache = invalidateSortCache,
        invalidateTimerReadyCache = invalidateTimerReadyCache,
        computeAndAttachSellStatus = computeAndAttachSellStatus,
        isBankWindowOpen = isBankWindowOpen,
        storage = storage,
        loadSellConfigCache = loadSellConfigCache,
        isInKeepList = isInKeepList,
        isKeptByContains = isKeptByContains,
        isKeptByType = isKeptByType,
        isInJunkList = isInJunkList,
        isProtectedType = isProtectedType,
        willItemBeSold = willItemBeSold,
        rules = rules,
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
local function ensureBankCacheFromStorage() scanService.ensureBankCacheFromStorage() end
local function loadSnapshotsFromDisk() return scanService.loadSnapshotsFromDisk() end
local function startIncrementalScan() scanService.startIncrementalScan() end
local function processIncrementalScan() return scanService.processIncrementalScan() end

-- Removed all auto-adjustment functions - using snapshot/reset instead

--- Update all sellItems rows with the given itemName to inKeep/inJunk and recompute willSell/sellReason. No rescan.
local function updateSellStatusForItemName(itemName, inKeep, inJunk)
    if not itemName or itemName == "" then return end
    invalidateSortCache("sell")
    local key = (itemName or ""):match("^%s*(.-)%s*$")
    if key == "" then return end
    -- Reload cache if it was invalidated (e.g., after add/remove from list)
    if not perfCache.sellConfigCache then loadSellConfigCache() end
    for _, row in ipairs(sellItems) do
        local rn = (row.name or ""):match("^%s*(.-)%s*$")
        if rn == key then
            row.inKeep = inKeep
            row.inJunk = inJunk
            local ws, reason = willItemBeSold(row)
            row.willSell = ws
            row.sellReason = reason
        end
    end
end

--- Remove one item from inventoryItems by bag/slot. No rescan.
local function removeLootItemBySlot(slot)
    for i = #lootItems, 1, -1 do
        if lootItems[i].slot == slot then
            table.remove(lootItems, i)
            return true
        end
    end
    return false
end

local function removeItemFromInventoryBySlot(bag, slot)
    for i = #inventoryItems, 1, -1 do
        if inventoryItems[i].bag == bag and inventoryItems[i].slot == slot then
            invalidateSortCache("inv")
            table.remove(inventoryItems, i)
            return
        end
    end
end

--- Remove one item from sellItems by bag/slot. No rescan.
local function removeItemFromSellItemsBySlot(bag, slot)
    invalidateSortCache("sell")
    for i = #sellItems, 1, -1 do
        if sellItems[i].bag == bag and sellItems[i].slot == slot then
            table.remove(sellItems, i)
            return
        end
    end
end

--- Remove one item from bankItems and bankCache by bag/slot. No rescan.
local function removeItemFromBankBySlot(bag, slot)
    invalidateSortCache("bank")
    for i = #bankItems, 1, -1 do
        if bankItems[i].bag == bag and bankItems[i].slot == slot then
            table.remove(bankItems, i)
            break
        end
    end
    for i = #bankCache, 1, -1 do
        if bankCache[i].bag == bag and bankCache[i].slot == slot then
            table.remove(bankCache, i)
            return
        end
    end
end

--- Append one item to bankItems (and bankCache when bank open). No rescan. Used for inv→bank move.
local function addItemToBank(bag, slot, name, id, value, totalValue, stackSize, itemType, nodrop, notrade, lore, quest, collectible, heirloom, attuneable, augSlots, weight, clicky, container)
    weight = weight or 0
    clicky = clicky or 0
    container = container or 0
    local row = {
        bag = bag, slot = slot, name = name, id = id, value = value or 0, totalValue = totalValue or value or 0,
        stackSize = stackSize or 1, type = itemType or "", weight = weight, nodrop = nodrop or false, notrade = notrade or false,
        lore = lore or false, quest = quest or false, collectible = collectible or false, heirloom = heirloom or false,
        attuneable = attuneable or false, augSlots = augSlots or 0, clicky = clicky, container = container
    }
    invalidateSortCache("bank")
    table.insert(bankItems, row)
    if isBankWindowOpen() then
        table.insert(bankCache, { bag = row.bag, slot = row.slot, name = row.name, id = row.id, value = row.value, totalValue = row.totalValue, stackSize = row.stackSize, type = row.type, weight = row.weight })
        perfCache.lastBankCacheTime = os.time()
    end
end

--- Append one item to inventoryItems (e.g. after bank→inv move). Then refresh sellItems from inventoryItems.
local function addItemToInventory(bag, slot, name, id, value, totalValue, stackSize, itemType, nodrop, notrade, lore, quest, collectible, heirloom, attuneable, augSlots)
    invalidateSortCache("inv")
    local row = { bag = bag, slot = slot, name = name, id = id, value = value or 0, totalValue = totalValue or value or 0,
        stackSize = stackSize or 1, type = itemType or "", nodrop = nodrop or false, notrade = notrade or false,
        lore = lore or false, quest = quest or false, collectible = collectible or false, heirloom = heirloom or false,
        attuneable = attuneable or false, augSlots = augSlots or 0 }
    table.insert(inventoryItems, row)
    local dup = { bag = row.bag, slot = row.slot, name = row.name, id = row.id, value = row.value, totalValue = row.totalValue,
        stackSize = row.stackSize, type = row.type, nodrop = row.nodrop, notrade = row.notrade, lore = row.lore, quest = row.quest,
        collectible = row.collectible, heirloom = row.heirloom, attuneable = row.attuneable, augSlots = row.augSlots }
    dup.inKeep = isInKeepList(row.name) or isKeptByContains(row.name) or isKeptByType(row.type)
    dup.inJunk = isInJunkList(row.name)
    dup.isProtected = isProtectedType(row.type)
    local ws, reason = willItemBeSold(dup)
    dup.willSell, dup.sellReason = ws, reason
    invalidateSortCache("sell")
    table.insert(sellItems, dup)
end

local function processSellQueue()
    if #sellQueue == 0 or isSelling then return end
    if not isMerchantWindowOpen() then
        sellQueue = {}
        return
    end
    isSelling = true
    local itemToSell = table.remove(sellQueue, 1)
    local itemName, bagNum, slotNum = itemToSell.name, itemToSell.bag, itemToSell.slot
    local item = mq.TLO.Me.Inventory("pack" .. bagNum).Item(slotNum)
    if not item.ID() or item.ID() == 0 then
        isSelling = false
        return
    end
    mq.delay(200)
    mq.cmdf('/itemnotify in pack%d %d leftmouseup', bagNum, slotNum)
    mq.delay(300)
    local selected = false
    for i = 1, 10 do
        if mq.TLO.Window("MerchantWnd/MW_SelectedItemLabel").Text() == itemName then selected = true; break end
        mq.delay(100)
    end
    if not selected then
        isSelling = false
        return
    end
    mq.cmd('/nomodkey /shiftkey /notify MerchantWnd MW_Sell_Button leftmouseup')
    mq.delay(300)
    for i = 1, 15 do
        local sel = mq.TLO.Window("MerchantWnd/MW_SelectedItemLabel").Text()
        if sel == "" or sel ~= itemName then
            local v = mq.TLO.Me.Inventory("pack" .. bagNum).Item(slotNum)
            if not v.ID() or v.ID() == 0 then break end
        end
        mq.delay(100)
    end
    removeItemFromInventoryBySlot(bagNum, slotNum)
    removeItemFromSellItemsBySlot(bagNum, slotNum)
    isSelling = false
    setStatusMessage(string.format("Sold: %s", itemName))
end

-- ============================================================================
-- Helpers
-- ============================================================================
local function getItemFlags(d)
    local t = {}
    if d.nodrop then table.insert(t, "NoDrop") end
    if d.notrade then table.insert(t, "NoTrade") end
    if d.lore then table.insert(t, "Lore") end
    if d.quest then table.insert(t, "Quest") end
    if d.collectible then table.insert(t, "Collectible") end
    if d.heirloom then table.insert(t, "Heirloom") end
    if d.attuneable then table.insert(t, "Attuneable") end
    if d.augSlots and d.augSlots > 0 then table.insert(t, string.format("Aug(%d)", d.augSlots)) end
    if getItemSpellId(d, "Clicky") > 0 then table.insert(t, "Clicky") end
    if d.container and d.container > 0 then table.insert(t, string.format("Bag(%d)", d.container)) end
    return #t > 0 and table.concat(t, ", ") or "None"
end
local function hasItemOnCursor() return mq.TLO.Cursor() and true or false end

local function findFirstFreeBankSlot()
    for b = 1, 24 do
        local s = mq.TLO.Me.Bank(b)
        if s then
            local sz = s.Container() or 0
            if sz and sz > 0 then
                for i = 1, sz do
                    local it = s.Item(i)
                    if not it or not it.ID() or it.ID() == 0 then return b, i end
                end
            elseif not s.ID() or s.ID() == 0 then return b, 1 end
        end
    end
    return nil, nil
end
local function findFirstFreeInvSlot()
    for b = 1, 10 do
        local p = mq.TLO.Me.Inventory("pack" .. b)
        if p and p.Container() then
            for i = 1, p.Container() do
                local it = p.Item(i)
                if not it or not it.ID() or it.ID() == 0 then return b, i end
            end
        end
    end
    return nil, nil
end

local function moveInvToBank(invBag, invSlot)
    -- Find item data in our table before we remove it (update in-place, no rescan)
    local row
    for _, r in ipairs(inventoryItems) do
        if r.bag == invBag and r.slot == invSlot then row = r; break end
    end
    local bb, bs = findFirstFreeBankSlot()
    if not bb or not bs then setStatusMessage("No free bank slot"); return false end
    mq.cmdf('/itemnotify in pack%d %d leftmouseup', invBag, invSlot)
    mq.cmdf('/itemnotify in bank%d %d leftmouseup', bb, bs)
    uiState.lastPickup.bag, uiState.lastPickup.slot, uiState.lastPickup.source = nil, nil, nil
    if transferStampPath then local f = io.open(transferStampPath, "w"); if f then f:write(tostring(os.time())); f:close() end end
    removeItemFromInventoryBySlot(invBag, invSlot)
    removeItemFromSellItemsBySlot(invBag, invSlot)
    if row then
        addItemToBank(bb, bs, row.name, row.id, row.value, row.totalValue, row.stackSize, row.type, row.nodrop, row.notrade, row.lore, row.quest, row.collectible, row.heirloom, row.attuneable, row.augSlots, row.weight, getItemSpellId(row, "Clicky"), row.container)
        setStatusMessage(string.format("Moved to bank: %s", row.name or "item"))
    end
    return true
end
local function moveBankToInv(bagIdx, slotIdx)
    local row
    for _, r in ipairs(bankItems) do
        if r.bag == bagIdx and r.slot == slotIdx then row = r; break end
    end
    if not row and isBankWindowOpen() then
        scanBank()
        for _, r in ipairs(bankItems) do
            if r.bag == bagIdx and r.slot == slotIdx then row = r; break end
        end
    end
    local ib, is_ = findFirstFreeInvSlot()
    if not ib or not is_ then setStatusMessage("No free inventory slot"); return false end
    mq.cmdf('/itemnotify in bank%d %d leftmouseup', bagIdx, slotIdx)
    mq.cmdf('/itemnotify in pack%d %d leftmouseup', ib, is_)
    uiState.lastPickup.bag, uiState.lastPickup.slot, uiState.lastPickup.source = nil, nil, nil
    if transferStampPath then local f = io.open(transferStampPath, "w"); if f then f:write(tostring(os.time())); f:close() end end
    if row then
        removeItemFromBankBySlot(bagIdx, slotIdx)
        addItemToInventory(ib, is_, row.name, row.id, row.value, row.totalValue, row.stackSize, row.type, row.nodrop, row.notrade, row.lore, row.quest, row.collectible, row.heirloom, row.attuneable, row.augSlots)
        setStatusMessage(string.format("Moved to inventory: %s", row.name or "item"))
    end
    -- When row missing (stale data), tables stay as-is until user reopens or clicks Refresh.
    return true
end
local function removeItemFromCursor()
    if not hasItemOnCursor() then return false end
    if uiState.lastPickup.bag and uiState.lastPickup.slot then
        if uiState.lastPickup.source == "bank" then
            mq.cmdf('/itemnotify in bank%d %d leftmouseup', uiState.lastPickup.bag, uiState.lastPickup.slot)
        else
            mq.cmdf('/itemnotify in pack%d %d leftmouseup', uiState.lastPickup.bag, uiState.lastPickup.slot)
        end
        uiState.lastPickup.bag, uiState.lastPickup.slot, uiState.lastPickup.source = nil, nil, nil
    else
        mq.cmd('/autoinv')
    end
    return true
end

-- ============================================================================
-- Tab renderers (condensed; full table behavior from inventoryui/bankui/sellui)
-- ============================================================================
local TABLE_FLAGS = bit32.bor(ImGuiTableFlags.ScrollY, ImGuiTableFlags.RowBg, ImGuiTableFlags.BordersOuter, ImGuiTableFlags.BordersV, ImGuiTableFlags.SizingStretchProp, ImGuiTableFlags.Resizable, ImGuiTableFlags.Reorderable, ImGuiTableFlags.Sortable, (ImGuiTableFlags.SaveSettings or 0))
uiState.tableFlags = TABLE_FLAGS

-- Column/sort helpers are provided by utils modules.
columns.init({availableColumns=availableColumns, columnVisibility=columnVisibility, columnAutofitWidths=columnAutofitWidths, setStatusMessage=setStatusMessage, getItemSpellId=getItemSpellId, getSpellName=getSpellName})
-- getStatusForSort used for Inventory Status column alphabetical sort (must match displayed text, e.g. Epic -> EpicQuest)
local function getStatusForSort(item)
    if not getSellStatusForItem then return "" end
    local st, _ = getSellStatusForItem(item)
    if st == "Epic" then return "EpicQuest" end
    return (st and st ~= "") and st or "—"
end
sortUtils.init({getItemSpellId=getItemSpellId, getSpellName=getSpellName, getStatusForSort=getStatusForSort})

-- Item icon texture (EQ A_DragItem) for Icon column
local itemIconTextureAnimation = nil
local function getItemIconTextureAnimation()
    if not itemIconTextureAnimation and mq.FindTextureAnimation then
        itemIconTextureAnimation = mq.FindTextureAnimation("A_DragItem")
    end
    return itemIconTextureAnimation
end
local ITEM_ICON_OFFSET = 500
local ITEM_ICON_SIZE = 24
local function drawItemIcon(iconId)
    local anim = getItemIconTextureAnimation()
    if not anim or not iconId or iconId == 0 then return end
    anim:SetTextureCell(iconId - ITEM_ICON_OFFSET)
    ImGui.DrawTextureAnimation(anim, ITEM_ICON_SIZE, ITEM_ICON_SIZE)
end

local function closeItemUI()
    shouldDraw = false
    isOpen = false
    uiState.configWindowOpen = false
end

--- AA Script counts (Lost Memories + Planar Power) from inventory - same data as scripttracker tool
local SCRIPT_AA_RARITIES = {
    { label = "Norm", tierKey = "normal", aa = 1 },
    { label = "Enh", tierKey = "enhanced", aa = 2 },
    { label = "Rare", tierKey = "rare", aa = 3 },
    { label = "Epic", tierKey = "epic", aa = 4 },
    { label = "Leg", tierKey = "legendary", aa = 5 },
}
local SCRIPT_AA_FULL_NAMES = {
    "Script of Lost Memories", "Enhanced Script of Lost Memories", "Rare Script of Lost Memories", "Epic Script of Lost Memories", "Legendary Script of Lost Memories",
    "Script of Planar Power", "Enhanced Script of Planar Power", "Rare Script of Planar Power", "Epic Script of Planar Power", "Legendary Script of Planar Power",
}
local SCRIPT_AA_BY_NAME = {}
do
    local aaByTier = { normal = 1, enhanced = 2, rare = 3, epic = 4, legendary = 5 }
    for _, name in ipairs(SCRIPT_AA_FULL_NAMES) do
        local tier = "normal"
        if name:find("^Enhanced ") then tier = "enhanced"
        elseif name:find("^Rare ") then tier = "rare"
        elseif name:find("^Epic ") then tier = "epic"
        elseif name:find("^Legendary ") then tier = "legendary"
        end
        SCRIPT_AA_BY_NAME[name] = aaByTier[tier]
    end
end

local function getScriptCountsFromInventory(items)
    local byTier = { normal = 0, enhanced = 0, rare = 0, epic = 0, legendary = 0 }
    local totalAA = 0
    for _, it in ipairs(items or {}) do
        local name = it.name or ""
        local aa = SCRIPT_AA_BY_NAME[name]
        if aa then
            local stack = (it.stackSize and it.stackSize > 0) and it.stackSize or 1
            local tier = "normal"
            if name:find("^Enhanced ") then tier = "enhanced"
            elseif name:find("^Rare ") then tier = "rare"
            elseif name:find("^Epic ") then tier = "epic"
            elseif name:find("^Legendary ") then tier = "legendary"
            end
            byTier[tier] = byTier[tier] + stack
            totalAA = totalAA + aa * stack
        end
    end
    local rows = {}
    for _, r in ipairs(SCRIPT_AA_RARITIES) do
        local count = byTier[r.tierKey] or 0
        rows[#rows + 1] = { label = r.label, count = count, aa = r.aa * count }
    end
    return { rows = rows, totalAA = totalAA }
end

-- ============================================================================
-- Character Stats Panel (Left Header)
-- ============================================================================
local function renderCharacterStatsPanel()
    local Me = mq.TLO.Me
    
    -- Helper: read AC/Attack/Weight from game Inventory window (same as test_ac_atk.lua / ac_atk_helper.lua).
    -- Requires the game's Inventory window to be open; paths from /windows output.
    local function getWindowText(path)
        local success, text = pcall(function()
            local wnd = mq.TLO.Window(path)
            if wnd and wnd.Open and wnd.Open() then
                return wnd.Text()
            end
            return nil
        end)
        return success and text or nil
    end

    -- Get displayed values from InventoryWindow (Stats tab or main page)
    local displayedAC = getWindowText("InventoryWindow/IW_StatPage/IWS_CurrentArmorClass") or
                        getWindowText("InventoryWindow/IW_ACNumber") or "N/A"
    local displayedATK = getWindowText("InventoryWindow/IW_StatPage/IWS_CurrentAttack") or
                         getWindowText("InventoryWindow/IW_ATKNumber") or "N/A"
    local displayedWeight = getWindowText("InventoryWindow/IW_StatPage/IWS_CurrentWeight") or
                            getWindowText("InventoryWindow/IW_CurrentWeight") or "N/A"
    local displayedMaxWeight = getWindowText("InventoryWindow/IW_StatPage/IWS_MaxWeight") or 
                               getWindowText("InventoryWindow/IW_MaxWeight") or "N/A"
    
    -- Get character stats
    local hp = Me.CurrentHPs() or 0
    local maxHP = Me.MaxHPs() or 0
    local mana = Me.CurrentMana() or 0
    local maxMana = Me.MaxMana() or 0
    local endur = Me.CurrentEndurance() or 0
    local maxEndur = Me.MaxEndurance() or 0
    local exp = Me.PctExp() or 0
    local aaPointsTotal = Me.AAPointsTotal() or 0  -- Total AA points
    local haste = Me.Haste() or 0
    -- Movement speed: show 0 when not moving, rounded to nearest whole number
    local isMoving = Me.Moving() or false
    local movementSpeed = isMoving and math.floor((Me.Speed() or 0) + 0.5) or 0
    
    -- Money
    local platinum = Me.Platinum() or 0
    local gold = Me.Gold() or 0
    local silver = Me.Silver() or 0
    local copper = Me.Copper() or 0
    
    -- Stats
    local str = Me.STR() or 0
    local sta = Me.STA() or 0
    local int = Me.INT() or 0
    local wis = Me.WIS() or 0
    local dex = Me.DEX() or 0
    local cha = Me.CHA() or 0
    
    -- Resists
    local magicResist = Me.svMagic() or 0
    local fireResist = Me.svFire() or 0
    local coldResist = Me.svCold() or 0
    local diseaseResist = Me.svDisease() or 0
    local poisonResist = Me.svPoison() or 0
    local corruptionResist = Me.svCorruption() or 0
    
    -- Render stats panel
    ImGui.BeginChild("CharacterStats", ImVec2(180, -C.FOOTER_HEIGHT), true, ImGuiWindowFlags.NoScrollbar)
    
    -- Reduce font size by 5% (scale to 0.95)
    ImGui.SetWindowFontScale(0.95)
    
    ImGui.TextColored(ImVec4(0.4, 0.8, 1, 1), "Character Stats")
    ImGui.Separator()
    
    -- HP/MP/EN
    ImGui.TextColored(ImVec4(0.9, 0.3, 0.3, 1), "HP:")
    ImGui.SameLine(50)
    ImGui.Text(string.format("%d / %d", hp, maxHP))
    
    ImGui.TextColored(ImVec4(0.3, 0.5, 0.9, 1), "MP:")
    ImGui.SameLine(50)
    ImGui.Text(string.format("%d / %d", mana, maxMana))
    
    ImGui.TextColored(ImVec4(0.5, 0.7, 0.3, 1), "EN:")
    ImGui.SameLine(50)
    ImGui.Text(string.format("%d / %d", endur, maxEndur))
    
    -- AC/ATK
    ImGui.TextColored(ImVec4(0.8, 0.6, 0.2, 1), "AC:")
    ImGui.SameLine(50)
    ImGui.Text(tostring(displayedAC))
    
    ImGui.TextColored(ImVec4(0.8, 0.6, 0.2, 1), "ATK:")
    ImGui.SameLine(50)
    ImGui.Text(tostring(displayedATK))
    
    -- Haste/Speed
    ImGui.TextColored(ImVec4(0.6, 0.8, 0.6, 1), "Haste:")
    ImGui.SameLine(50)
    ImGui.Text(string.format("%d%%", haste))
    
    ImGui.TextColored(ImVec4(0.6, 0.8, 0.6, 1), "Speed:")
    ImGui.SameLine(50)
    ImGui.Text(string.format("%d%%", movementSpeed))
    
    ImGui.Separator()
    
    -- EXP/AA section
    ImGui.Text("EXP:")
    ImGui.SameLine(50)
    ImGui.Text(string.format("%.1f%%", exp))
    
    ImGui.Text("AAs:")
    ImGui.SameLine(50)
    ImGui.Text(tostring(aaPointsTotal))
    
    ImGui.Separator()
    
    -- Stats section (condensed - two stats per line)
    ImGui.TextColored(ImVec4(0.85, 0.85, 0.7, 1), "Stats:")
    ImGui.Text("STR:")
    ImGui.SameLine(50)
    ImGui.Text(tostring(str))
    ImGui.SameLine(90)
    ImGui.Text("STA:")
    ImGui.SameLine(130)
    ImGui.Text(tostring(sta))
    
    ImGui.Text("INT:")
    ImGui.SameLine(50)
    ImGui.Text(tostring(int))
    ImGui.SameLine(90)
    ImGui.Text("WIS:")
    ImGui.SameLine(130)
    ImGui.Text(tostring(wis))
    
    ImGui.Text("DEX:")
    ImGui.SameLine(50)
    ImGui.Text(tostring(dex))
    ImGui.SameLine(90)
    ImGui.Text("CHA:")
    ImGui.SameLine(130)
    ImGui.Text(tostring(cha))
    
    ImGui.Separator()
    
    -- Resists section (condensed - two resists per line, with proper column alignment)
    ImGui.TextColored(ImVec4(0.85, 0.85, 0.7, 1), "Resist:")
    -- Column positions: labels at 0, values at 65, column 2 labels at 95, column 2 values at 155
    ImGui.Text("Poison:")
    ImGui.SameLine(65)  -- Space for longest label "Corruption:"
    ImGui.Text(tostring(poisonResist))
    ImGui.SameLine(95)  -- Start of column 2 labels
    ImGui.Text("Magic:")
    ImGui.SameLine(155)  -- Column 2 values aligned
    ImGui.Text(tostring(magicResist))
    
    ImGui.Text("Fire:")
    ImGui.SameLine(65)
    ImGui.Text(tostring(fireResist))
    ImGui.SameLine(95)
    ImGui.Text("Disease:")
    ImGui.SameLine(155)
    ImGui.Text(tostring(diseaseResist))
    
    ImGui.Text("Corrupt:")
    ImGui.SameLine(65)
    ImGui.Text(tostring(corruptionResist))
    ImGui.SameLine(95)
    ImGui.Text("Cold:")
    ImGui.SameLine(155)
    ImGui.Text(tostring(coldResist))
    
    ImGui.Separator()
    
    -- Weight
    ImGui.TextColored(ImVec4(0.85, 0.85, 0.7, 1), "WEIGHT:")
    ImGui.Text(string.format("%s / %s", tostring(displayedWeight), tostring(displayedMaxWeight)))
    
    ImGui.Separator()
    
    -- Money section
    ImGui.TextColored(ImVec4(0.85, 0.85, 0.7, 1), "Money:")
    local moneyStr = ""
    if platinum > 0 then
        moneyStr = moneyStr .. string.format("%dp ", platinum)
    end
    if gold > 0 or platinum > 0 then
        moneyStr = moneyStr .. string.format("%dg ", gold)
    end
    if silver > 0 or gold > 0 or platinum > 0 then
        moneyStr = moneyStr .. string.format("%ds ", silver)
    end
    moneyStr = moneyStr .. string.format("%dc", copper)
    ImGui.Text(moneyStr)
    
    -- AA Scripts (Lost/Planar) - compact, same data as scripttracker
    ImGui.Separator()
    ImGui.TextColored(ImVec4(0.85, 0.85, 0.7, 1), "Scripts:")
    ImGui.SameLine()
    if ImGui.SmallButton("Pop-out Tracker") then mq.cmd('/scripttracker show') end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Open AA Script Tracker window (run /lua run scripttracker first if needed)"); ImGui.EndTooltip() end
    local scriptData = getScriptCountsFromInventory(inventoryItems)
    ImGui.SetWindowFontScale(0.85)
    -- Header: make it clear which column is count vs AA
    ImGui.Text("")
    ImGui.SameLine(48)
    ImGui.TextColored(ImVec4(0.6, 0.6, 0.6, 1), "Cnt")
    ImGui.SameLine(78)
    ImGui.TextColored(ImVec4(0.6, 0.6, 0.6, 1), "AA")
    for _, row in ipairs(scriptData.rows) do
        ImGui.Text(row.label .. ":")
        ImGui.SameLine(48)
        ImGui.Text(tostring(row.count))
        ImGui.SameLine(78)
        ImGui.Text(tostring(row.aa))
    end
    ImGui.TextColored(ImVec4(0.9, 0.85, 0.4, 1), "Total: " .. tostring(scriptData.totalAA) .. " AA")
    ImGui.SetWindowFontScale(0.95)
    
    -- Reset font scale
    ImGui.SetWindowFontScale(1.0)
    
    ImGui.EndChild()
end

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
    getCellDisplayText = columns.getCellDisplayText,
    isNumericColumn = columns.isNumericColumn,
    getVisibleColumns = columns.getVisibleColumns,
}

context.init({
    uiState = uiState,
    sortState = sortState,
    filterState = filterState,
    layoutConfig = layoutConfig,
    perfCache = perfCache,
    sellMacState = sellMacState,
    inventoryItems = inventoryItems,
    bankItems = bankItems,
    lootItems = lootItems,
    sellItems = sellItems,
    bankCache = bankCache,
    configLootLists = configLootLists,
    config = config,
    columnAutofitWidths = columnAutofitWidths,
    availableColumns = availableColumns,
    columnVisibility = columnVisibility,
    configSellFlags = configSellFlags,
    configSellValues = configSellValues,
    configSellLists = configSellLists,
    configLootFlags = configLootFlags,
    configLootValues = configLootValues,
    configLootSorting = configLootSorting,
    configEpicClasses = configEpicClasses,
    EPIC_CLASSES = rules.EPIC_CLASSES,
    windowState = windowStateAPI,
    scanInventory = scanInventory,
    scanBank = scanBank,
    scanSellItems = scanSellItems,
    scanLootItems = scanLootItems,
    maybeScanInventory = maybeScanInventory,
    maybeScanSellItems = maybeScanSellItems,
    maybeScanLootItems = maybeScanLootItems,
    ensureBankCacheFromStorage = ensureBankCacheFromStorage,
    invalidateLootConfigCache = invalidateLootConfigCache,
    invalidateSellConfigCache = invalidateSellConfigCache,
    setStatusMessage = setStatusMessage,
    saveLayoutToFile = saveLayoutToFile,
    scheduleLayoutSave = scheduleLayoutSave,
    flushLayoutSave = flushLayoutSave,
    saveColumnVisibility = saveColumnVisibility,
    loadLayoutConfig = loadLayoutConfig,
    captureCurrentLayoutAsDefault = captureCurrentLayoutAsDefault,
    resetLayoutToDefault = resetLayoutToDefault,
    loadConfigCache = loadConfigCache,
    closeItemUI = closeItemUI,
    hasItemOnCursor = hasItemOnCursor,
    removeItemFromCursor = removeItemFromCursor,
    moveBankToInv = moveBankToInv,
    moveInvToBank = moveInvToBank,
    queueItemForSelling = queueItemForSelling,
    addToKeepList = addToKeepList,
    removeFromKeepList = removeFromKeepList,
    addToJunkList = addToJunkList,
    removeFromJunkList = removeFromJunkList,
    augmentLists = augmentListAPI,
    updateSellStatusForItemName = updateSellStatusForItemName,
    sortColumns = sortColumnsAPI,
    getColumnKeyByIndex = columns.getColumnKeyByIndex,
    autofitColumns = columns.autofitColumns,
    getSpellName = getSpellName,
    getSpellDescription = getSpellDescription,
    getItemSpellId = getItemSpellId,
    getTimerReady = getTimerReady,
    theme = theme,
    macroBridge = macroBridge,
    getFixedColumns = getFixedColumns,
    toggleFixedColumn = toggleFixedColumn,
    isColumnInFixedSet = isColumnInFixedSet,
    drawItemIcon = drawItemIcon,
    getSellStatusForItem = getSellStatusForItem,
    getItemStatsSummary = getItemStatsSummary,
    addToLootSkipList = addToLootSkipList,
    removeFromLootSkipList = removeFromLootSkipList,
    isInLootSkipList = isInLootSkipList,
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
            local invWnd = mq.TLO.Window("InventoryWindow")
            if invWnd and invWnd.Open() then
                local x, y = tonumber(invWnd.X()) or 0, tonumber(invWnd.Y()) or 0
                local pw = tonumber(invWnd.Width()) or 0
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
                local invO, bankO, merchO = (mq.TLO.Window("InventoryWindow") and mq.TLO.Window("InventoryWindow").Open()) or false, isBankWindowOpen(), isMerchantWindowOpen()
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
    renderCharacterStatsPanel()
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
        local cn = mq.TLO.Cursor.Name() or "Item"
        local st = mq.TLO.Cursor.Stack()
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
            local invO, bankO, merchO = (mq.TLO.Window("InventoryWindow") and mq.TLO.Window("InventoryWindow").Open()) or false, isBankWindowOpen(), isMerchantWindowOpen()
            -- If inv closed, open it so /inv and I key give same behavior (inv open + fresh scan)
            if not invO then mq.cmd('/keypress inventory'); invO = true end
            isOpen = true; loadLayoutConfig(); maybeScanInventory(invO); maybeScanBank(bankO); maybeScanSellItems(merchO)
        else
            closeGameInventoryIfOpen()
        end
    elseif cmd == "show" then
        shouldDraw, isOpen = true, true
        local invO, bankO, merchO = (mq.TLO.Window("InventoryWindow") and mq.TLO.Window("InventoryWindow").Open()) or false, isBankWindowOpen(), isMerchantWindowOpen()
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
            -- Use backslashes to match sell.mac path (MacroQuest.Path may use / or \)
            perfCache.sellLogPath = (p:gsub("/", "\\")) .. "\\Macros\\logs\\item_management"
        end
    end
    while not mq.TLO.Me.Name() do mq.delay(1000) end
    loadLayoutConfig()  -- Single parse loads defaults, layout, column visibility
    do
        local path = layoutUtils.getLayoutFilePath()
        if not path or path == "" then
            print("\ar[ItemUI]\ax Warning: MacroQuest path not set; config and layout may not work.")
        end
    end
    storage.init({ profileEnabled = C.PROFILE_ENABLED, profileThresholdMs = C.PROFILE_THRESHOLD_MS })
    local invO = (mq.TLO.Window("InventoryWindow") and mq.TLO.Window("InventoryWindow").Open()) or false
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
                    local countStr = mq.TLO.Ini.File(failedPath).Section("Failed").Key("count").Value()
                    local count = tonumber(countStr) or 0
                    if count > 0 then
                        sellMacState.failedCount = count
                        for i = 1, count do
                            local item = mq.TLO.Ini.File(failedPath).Section("Failed").Key("item" .. i).Value()
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
            mq.delay(300, function() return mq.TLO.Window("QuantityWnd").Open() end)
            if mq.TLO.Window("QuantityWnd").Open() then
                mq.cmd(string.format('/notify QuantityWnd QTYW_Slider newvalue %d', action.qty))
                mq.delay(150)
                mq.cmd('/notify QuantityWnd QTYW_Accept_Button leftmouseup')
            end
        end
        -- Clear pending quantity pickup if item was picked up manually or QuantityWnd closed
        if uiState.pendingQuantityPickup then
            local qtyWnd = mq.TLO.Window("QuantityWnd")
            local qtyWndOpen = qtyWnd and qtyWnd.Open and qtyWnd.Open() or false
            local hasCursor = hasItemOnCursor()
            -- Clear if QuantityWnd closed (user cancelled manually) or item is on cursor (user picked it up manually)
            if not qtyWndOpen and not hasCursor then
                -- Check if item still exists at the location
                local itemExists = false
                if uiState.pendingQuantityPickup.source == "bank" then
                    local bn = mq.TLO.Me.Bank(uiState.pendingQuantityPickup.bag)
                    local it = (bn and bn.Container() and bn.Container()>0) and bn.Item(uiState.pendingQuantityPickup.slot) or bn
                    itemExists = it and it.ID() and it.ID() > 0
                else
                    local pack = mq.TLO.Me.Inventory("pack" .. uiState.pendingQuantityPickup.bag)
                    local it = pack and pack.Item(uiState.pendingQuantityPickup.slot)
                    itemExists = it and it.ID() and it.ID() > 0
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
        local invOpen = (mq.TLO.Window("InventoryWindow") and mq.TLO.Window("InventoryWindow").Open()) or false
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
            local confirmWnd = mq.TLO.Window("ConfirmationDialogBox")
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