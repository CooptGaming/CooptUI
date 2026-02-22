--[[
    ItemUI Constants
    Named constants for timing (delays, timeouts, debounce), UI dimensions (widths, heights, gaps),
    and limits (max items, cache sizes). Use these instead of inline magic numbers in views and services.
    Part of CoOpt UI — Task 03 (P1-05).
--]]

local M = {}

-- ---------------------------------------------------------------------------
-- TIMING — Delays, timeouts, debounce (all in milliseconds unless noted)
-- ---------------------------------------------------------------------------
M.TIMING = {
    -- Layout and persistence
    LAYOUT_SAVE_DEBOUNCE_MS = 600,
    PERSIST_SAVE_INTERVAL_MS = 60000,
    CACHE_CLEANUP_INTERVAL_MS = 30000,

    -- Status and caches
    STATUS_MSG_SECS = 4,
    TIMER_READY_CACHE_TTL_MS = 1500,
    STORED_INV_CACHE_TTL_MS = 2000,
    GET_CHANGED_BAGS_THROTTLE_MS = 600,

    -- Macro finish / scan
    LOOT_PENDING_SCAN_DELAY_MS = 2500,
    SELL_PENDING_SCAN_DELAY_MS = 500,
    SELL_FAILED_DISPLAY_MS = 15000,

    -- Main loop
    LOOP_DELAY_VISIBLE_MS = 33,   -- ~30 FPS when UI visible
    LOOP_DELAY_HIDDEN_MS = 100,

    -- UI refresh throttles
    EQUIPMENT_REFRESH_THROTTLE_MS = 400,
    DEFERRED_SCAN_DELAY_MS = 120,   -- After put in bags / drop
    STATS_TAB_PRIME_MS = 250,

    -- Character stats panel
    STATS_CACHE_TTL_MS = 500,

    -- Search / AA
    SEARCH_DEBOUNCE_MS = 300,
    AA_SEARCH_DEBOUNCE_MS = 180,
    AA_IMPORT_DELAY_MS = 250,

    -- Augment operations
    AUGMENT_CURSOR_CLEAR_TIMEOUT_MS = 5000,
    AUGMENT_CURSOR_POPULATED_TIMEOUT_MS = 5000,
    AUGMENT_INSERT_NO_CONFIRM_FALLBACK_MS = 4000,
    AUGMENT_REMOVE_NO_CONFIRM_FALLBACK_MS = 6000,
    AUGMENT_REMOVE_OPEN_DELAY_MS = 400,
    AUGMENT_INSERT_DELAY_MS = 250,

    -- Item Display locate highlight
    ITEM_DISPLAY_LOCATE_CLEAR_SEC = 3,

    -- Loot
    LOOT_POLL_MS = 500,
    LOOT_POLL_MS_IDLE = 1000,
    LOOT_DEFER_MS = 2000,
    LOOT_MYTHICAL_DECISION_SEC = 300,

    -- Quantity picker / item ops
    QUANTITY_PICKUP_TIMEOUT_MS = 60000,
    ITEM_OPS_DELAY_MS = 300,
    -- Click-through protection: after detecting item on cursor we didn't initiate (e.g. focus click-through), block new pickups this long
    ACTIVATION_GUARD_MS = 450,
    -- Grace period after we clear lastPickup before treating "item on cursor" as unexpected (allows game to process drop)
    UNEXPECTED_CURSOR_GRACE_MS = 200,
    ITEM_OPS_DELAY_SHORT_MS = 100,
    ITEM_OPS_DELAY_MEDIUM_MS = 150,
    ITEM_OPS_DELAY_INITIAL_MS = 200,
}

-- ---------------------------------------------------------------------------
-- UI — Widths, heights, gaps (pixels)
-- ---------------------------------------------------------------------------
M.UI = {
    FOOTER_HEIGHT = 52,
    WINDOW_GAP = 10,
    BANK_WINDOW_WIDTH = 520,
    BANK_WINDOW_HEIGHT = 600,
    EQUIPMENT_PANEL_WIDTH = 220,
    EQUIPMENT_PANEL_HEIGHT = 380,
    -- Config filter tables
    FILTER_BADGE_WIDTH = 85,
    FILTER_LIST_WIDTH = 200,
    FILTER_X_BUTTON_WIDTH = 32,
    FILTER_CONTENT_MIN_HEIGHT = 240,
    -- Character stats
    CHARACTER_STATS_PANEL_WIDTH = 180,
    CHARACTER_STATS_SAMELINE_FIRST = 130,
    CHARACTER_STATS_SAMELINE_SECOND = 155,
    -- Quantity picker / dialogs
    QUANTITY_INPUT_WIDTH = 100,
    DESTROY_CONFIRM_BUTTON_WIDTH = 110,
    -- Loot UI
    LOOT_FEEDBACK_CARD_HEIGHT = 52,
    LOOT_MYTHICAL_CARD_HEIGHT = 152,
    LOOT_MYTHICAL_CARD_HEIGHT_PENDING = 172,
    LOOT_TABLE_COL_NUM_WIDTH = 28,
    LOOT_TABLE_COL_VALUE_WIDTH = 72,
    LOOT_TABLE_COL_STATUS_WIDTH = 90,
    LOOT_TABLE_COL_REASON_WIDTH = 120,
    LOOT_CURRENT_TABLE_FOOTER = 40,
    LOOT_HISTORY_FOOTER_HEIGHT = 50,
    -- Item tooltip
    TOOLTIP_MIN_WIDTH = 400,
    TOOLTIP_MIN_HEIGHT = 300,
    TOOLTIP_CHARS_PER_LINE_DESC = 52,
    -- Item Display
    ITEM_DISPLAY_AVAIL_X = 400,
    ITEM_DISPLAY_TAB_LABEL_WIDTH = 120,
    -- AA view column hints
    AA_COL_CURMAX_WIDTH = 60,
    AA_COL_COST_WIDTH = 45,
    AA_COL_CATEGORY_WIDTH = 120,
    -- Truncation
    ITEM_NAME_DISPLAY_MAX = 40,
    ITEM_NAME_TRUNCATE_LEN = 37,
    FAILED_LIST_TRUNCATE_LEN = 60,
    FAILED_LIST_DISPLAY_MAX = 57,
}

-- ---------------------------------------------------------------------------
-- LIMITS — Max items, cache sizes, array caps
-- ---------------------------------------------------------------------------
M.LIMITS = {
    MAX_BANK_SLOTS = 24,
    MAX_INVENTORY_BAGS = 10,
    STATUS_MSG_MAX_LEN = 72,
    LOOT_HISTORY_MAX = 200,
    ITEM_DISPLAY_RECENT_MAX = 10,
    SEARCH_HISTORY_MAX = 5,
    LOOT_SELL_STATUS_CAP = 30,
    MAX_AA_INDEX = 2000,
}

-- ---------------------------------------------------------------------------
-- VIEWS — Per-view default dimensions (layoutDefaults); keys match layout INI
-- ---------------------------------------------------------------------------
M.VIEWS = {
    WidthInventory = 600,
    Height = 450,
    WidthSell = 780,
    WidthLoot = 560,
    WidthBankPanel = 520,
    HeightBank = 600,
    WidthAugmentsPanel = 560,
    HeightAugments = 500,
    WidthItemDisplayPanel = 760,
    HeightItemDisplay = 520,
    WidthAugmentUtilityPanel = 520,
    HeightAugmentUtility = 480,
    WidthLootPanel = 420,
    HeightLoot = 380,
    WidthAAPanel = 640,
    HeightAA = 520,
    WidthConfig = 520,
    -- Reroll Companion (Augment / Mythical server reroll lists)
    WidthRerollPanel = 520,
    HeightReroll = 480,
}

-- ---------------------------------------------------------------------------
-- REROLL — Server reroll system (augments and mythical items)
-- ---------------------------------------------------------------------------
M.REROLL = {
    ITEMS_REQUIRED = 10,
    COMMAND_AUG_ADD = "!augadd",
    COMMAND_AUG_REMOVE = "!augremove",
    COMMAND_AUG_LIST = "!auglist",
    COMMAND_AUG_ROLL = "!augroll",
    COMMAND_MYTHICAL_ADD = "!mythicaladd",
    COMMAND_MYTHICAL_REMOVE = "!mythicalremove",
    COMMAND_MYTHICAL_LIST = "!mythicallist",
    COMMAND_MYTHICAL_ROLL = "!mythicalroll",
    MYTHICAL_NAME_PREFIX = "Mythical",
    -- Chat list response: assume server sends lines like "12345: Item Name" or "12345 - Item Name"
    LIST_RESPONSE_PARSE_MS = 3000,
}

-- Layout INI file and section names (shared with utils/layout.lua)
M.LAYOUT_INI = "itemui_layout.ini"
M.LAYOUT_SECTION = "Layout"

-- ---------------------------------------------------------------------------
-- Build a flat C-style table for init.lua compatibility (C table)
-- Call: local C = constants.buildC(CoopVersion.ITEMUI) or use constants.* directly
-- ---------------------------------------------------------------------------
function M.buildC(version)
    local T = M.TIMING
    local U = M.UI
    local L = M.LIMITS
    local V = M.VIEWS
    return {
        VERSION = version,
        MAX_BANK_SLOTS = L.MAX_BANK_SLOTS,
        MAX_INVENTORY_BAGS = L.MAX_INVENTORY_BAGS,
        LAYOUT_INI = M.LAYOUT_INI,
        LAYOUT_SECTION = M.LAYOUT_SECTION,
        PROFILE_ENABLED = true,
        PROFILE_THRESHOLD_MS = 30,
        UPVALUE_DEBUG = false,
        STATUS_MSG_SECS = T.STATUS_MSG_SECS,
        STATUS_MSG_MAX_LEN = L.STATUS_MSG_MAX_LEN,
        PERSIST_SAVE_INTERVAL_MS = T.PERSIST_SAVE_INTERVAL_MS,
        FOOTER_HEIGHT = U.FOOTER_HEIGHT,
        TIMER_READY_CACHE_TTL_MS = T.TIMER_READY_CACHE_TTL_MS,
        LAYOUT_SAVE_DEBOUNCE_MS = T.LAYOUT_SAVE_DEBOUNCE_MS,
        LOOT_PENDING_SCAN_DELAY_MS = T.LOOT_PENDING_SCAN_DELAY_MS,
        GET_CHANGED_BAGS_THROTTLE_MS = T.GET_CHANGED_BAGS_THROTTLE_MS,
        SELL_FAILED_DISPLAY_MS = T.SELL_FAILED_DISPLAY_MS,
        SELL_PENDING_SCAN_DELAY_MS = T.SELL_PENDING_SCAN_DELAY_MS,
        STORED_INV_CACHE_TTL_MS = T.STORED_INV_CACHE_TTL_MS,
        LOOP_DELAY_VISIBLE_MS = T.LOOP_DELAY_VISIBLE_MS,
        LOOP_DELAY_HIDDEN_MS = T.LOOP_DELAY_HIDDEN_MS,
    }
end

return M
