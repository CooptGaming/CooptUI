--[[
    test_layout_setup.lua — headless suite for the capture/reset [Defaults] round-trip
    (utils/layout_setup.lua + utils/layout.lua applyDefaultsFromParsed).

    What it proves, against the REAL layout.lua / layout_setup.lua / layout_io.lua /
    file_safe stack writing a real INI in a temp sandbox:

      1. Capture writes the bars ARRANGEMENT keys (DockSegments, ZoneAssign, WindowAttach,
         LayoutPreset, UserPlaced) into [Defaults], and keeps the PARADIGM keys (UIMode,
         DockTop, DockBottom, DockPosition, DockChat, DockBottomStyle, DockButtons) OUT —
         mirroring the bundled-revert keep-list in views/settings.lua.
      2. Reset re-reads the file (not in-memory leftovers) and restores the captured
         arrangement, while leaving the paradigm keys untouched in layoutConfig AND in the
         rewritten [Layout] section.
      3. A legacy [Defaults] section without bars keys resets arrangement to the shipped
         state.lua defaults, still without touching the paradigm keys.

    Run:  COOPT_REPO=C:/Claude/CooptUI <luajit> scripts/tests/test_layout_setup.lua
]]

local repo = os.getenv('COOPT_REPO') or 'C:/Claude/CooptUI'
package.path = repo .. '/lua/?.lua;' .. repo .. '/lua/?/init.lua;' .. package.path

local pass, fail = 0, 0
local function check(name, cond, extra)
    if cond then pass = pass + 1; print('PASS: ' .. name)
    else fail = fail + 1; print('FAIL: ' .. name .. '  -> ' .. tostring(extra)) end
end

-- Temp sandbox (COOPT_TMP if the runner provides one, else TEMP).
local tmpBase = os.getenv('COOPT_TMP') or os.getenv('TEMP') or '.'
local tmpDir = tmpBase .. '/coopt_layout_setup_test_' .. tostring(os.clock()):gsub('%.', '')
os.execute('mkdir "' .. tmpDir:gsub('/', '\\') .. '" >nul 2>&1')

-- Stubs BEFORE any itemui require. TLO nodes are indexable AND callable (return nil) so
-- core.debug's getMQRoot degrades to "no MQ root" instead of erroring.
local function tloNode()
    return setmetatable({}, { __index = function() return tloNode() end, __call = function() return nil end })
end
package.loaded['mq'] = {
    gettime = function() return 100000 end,
    cmd = function() end, cmdf = function() end, delay = function() end,
    event = function() end, TLO = tloNode(),
}
package.loaded['itemui.core.diagnostics'] = { getErrorCount = function() return 0 end, recordError = function() end }
package.loaded['itemui.config'] = {
    getConfigFile = function(name) return tmpDir .. '/' .. name end,
    readINIValue = function() return nil end,  -- core.debug probes [Debug] flags through this
}

ImGuiSortDirection = { Ascending = 0, Descending = 1 }

local constants = require('itemui.constants')
local registry = require('itemui.core.registry')
local LayoutUtils = require('itemui.utils.layout')

-- layoutDefaults seeded the way state.lua seeds it (VIEWS copy + the bars block).
local layoutDefaults = {}
for k, v in pairs(constants.VIEWS) do layoutDefaults[k] = v end
for k, v in pairs({
    BankWindowX = 0, BankWindowY = 0, AugmentsWindowX = 0, AugmentsWindowY = 0,
    MythicalsWindowX = 0, MythicalsWindowY = 0, CommandCenterWindowX = 0, CommandCenterWindowY = 0,
    FavoritesWindowX = 0, FavoritesWindowY = 0, EffectsWindowX = 0, EffectsWindowY = 0,
    ChatWindowX = 0, ChatWindowY = 0, WidthChatPanel = 560, HeightChat = 380, ShowChatWindow = 1,
    ItemDisplayWindowX = 0, ItemDisplayWindowY = 0, AugmentUtilityWindowX = 0, AugmentUtilityWindowY = 0,
    LootWindowX = 0, LootWindowY = 0, LootUIFirstTipSeen = 0,
    AAWindowX = 0, AAWindowY = 0, ShowAAWindow = 1, ShowEquipmentWindow = 1,
    ShowBankWindow = 1, ShowAugmentsWindow = 1, ShowAugmentUtilityWindow = 1,
    ShowItemDisplayWindow = 1, ShowConfigWindow = 1, ShowRerollWindow = 1,
    RerollWindowX = 0, RerollWindowY = 0, AABackupPath = "",
    AlignToContext = 1, UILocked = 1, SuppressWhenLootMac = 0,
    EnableRealTimeLoot = 0, EnableLootHistory = 0, EnableSkipHistory = 0,
    ConfirmBeforeDelete = 1, ActivationGuardEnabled = 1, ItemUIToggleKey = "shift+q",
    UIMode = "classic", DockTop = 1, DockBottom = 1, DockPosition = "top", DockChat = "collapsed",
    DockSegments = "status,bags,sell,loot,buffs,xp,session",
    DockBottomStyle = "menus",
    DockButtons = "bags,bank,equipment,augments,augmentUtility,mythicals,reroll,aa,effects",
    ZoneAssign = "", WindowAttach = "", LayoutPreset = "", UserPlaced = "",
}) do layoutDefaults[k] = v end
local SHIPPED_SEGMENTS = layoutDefaults.DockSegments

local layoutConfig = {}
local uiState = {
    alignToContext = true, uiLocked = true, suppressWhenLootMac = false,
    enableRealTimeLoot = false, enableLootHistory = false, enableSkipHistory = false,
    confirmBeforeDelete = true, nativeMerchantStrip = true, nativeHoverTooltip = true,
    nativeItemDisplayReplace = true,
}
local sortState = {}
local filterState = { configTab = 1, filterSubTab = 1 }
local columnVisibility = {}
local perfCache = {}
local function initColumnVisibility()
    columnVisibility.Inventory = { Name = true, Qty = false }
end
initColumnVisibility()

registry.init({ layoutConfig = layoutConfig, companionWindowOpenedAt = {} })
LayoutUtils.init({
    layoutDefaults = layoutDefaults, layoutConfig = layoutConfig,
    uiState = uiState, sortState = sortState, filterState = filterState,
    columnVisibility = columnVisibility, perfCache = perfCache,
    C = constants, initColumnVisibility = initColumnVisibility, availableColumns = {},
})

local iniPath = tmpDir .. '/itemui_layout.ini'
local function readFile()
    local f = io.open(iniPath, 'r'); if not f then return '' end
    local c = f:read('*all'); f:close(); return c
end
-- Section body from header to the next [header] (or EOF).
local function sectionText(content, name)
    local s = content:find('%[' .. name .. '%]')
    if not s then return nil end
    local e = content:find('%[', s + 1)
    return content:sub(s, e and e - 1 or #content)
end
local function hasKey(sect, key)
    return sect ~= nil and sect:find('\n' .. key .. '=', 1, true) ~= nil
end
local function keyValue(sect, key)
    if not sect then return nil end
    return sect:match('\n' .. key .. '=([^\n]*)')
end

-- ---------------------------------------------------------------------------
-- 1. Capture: arrangement keys enter [Defaults]; paradigm keys stay out.
-- ---------------------------------------------------------------------------

-- A bars-mode session with a hand-arranged layout.
layoutConfig.UIMode = 'bars'
layoutConfig.DockTop = true
layoutConfig.DockBottom = false
layoutConfig.DockPosition = 'bottom'
layoutConfig.DockChat = 'peek'
layoutConfig.DockBottomStyle = 'buttons'
layoutConfig.DockButtons = 'bags,bank'
layoutConfig.DockSegments = 'xp,bags'
layoutConfig.ZoneAssign = 'bank:R2,aa:L1'
layoutConfig.WindowAttach = 'itemDisplay:hub:right:top'
layoutConfig.LayoutPreset = 'Raid'
layoutConfig.UserPlaced = 'bank,aa'
layoutConfig.WidthInventory = 777

LayoutUtils.saveLayoutToFileImmediate()  -- file now has a [Layout] section to preserve
LayoutUtils.captureCurrentLayoutAsDefault()

local content = readFile()
local defaults = sectionText(content, 'Defaults')
check('capture wrote a [Defaults] section', defaults ~= nil)
check('capture: DockSegments in [Defaults]', keyValue(defaults, 'DockSegments') == 'xp,bags', keyValue(defaults, 'DockSegments'))
check('capture: ZoneAssign in [Defaults]', keyValue(defaults, 'ZoneAssign') == 'bank:R2,aa:L1', keyValue(defaults, 'ZoneAssign'))
check('capture: WindowAttach in [Defaults]', keyValue(defaults, 'WindowAttach') == 'itemDisplay:hub:right:top', keyValue(defaults, 'WindowAttach'))
check('capture: LayoutPreset in [Defaults]', keyValue(defaults, 'LayoutPreset') == 'Raid', keyValue(defaults, 'LayoutPreset'))
check('capture: UserPlaced in [Defaults]', keyValue(defaults, 'UserPlaced') == 'bank,aa', keyValue(defaults, 'UserPlaced'))
for _, k in ipairs({ 'UIMode', 'DockTop', 'DockBottom', 'DockPosition', 'DockChat', 'DockBottomStyle', 'DockButtons' }) do
    check('capture: paradigm key ' .. k .. ' NOT in [Defaults]', not hasKey(defaults, k), keyValue(defaults, k))
end
local layoutSect = sectionText(content, 'Layout')
check('capture preserved [Layout] UIMode', keyValue(layoutSect, 'UIMode') == 'bars', keyValue(layoutSect, 'UIMode'))
check('capture preserved [Layout] DockPosition', keyValue(layoutSect, 'DockPosition') == 'bottom', keyValue(layoutSect, 'DockPosition'))

-- ---------------------------------------------------------------------------
-- 2. Reset: restores the captured arrangement FROM THE FILE, paradigm untouched.
-- ---------------------------------------------------------------------------

-- Wipe the in-memory snapshot so a value that survives can only have come from the file.
layoutDefaults.DockSegments = 'WIPED'
layoutDefaults.ZoneAssign = 'WIPED'
layoutDefaults.WindowAttach = 'WIPED'
layoutDefaults.LayoutPreset = 'WIPED'
layoutDefaults.UserPlaced = 'WIPED'
-- The user then rearranged everything...
layoutConfig.DockSegments = 'status'
layoutConfig.ZoneAssign = 'aa:B1'
layoutConfig.WindowAttach = ''
layoutConfig.LayoutPreset = ''
layoutConfig.UserPlaced = ''
layoutConfig.WidthInventory = 999

LayoutUtils.resetLayoutToDefault()

check('reset: DockSegments restored', layoutConfig.DockSegments == 'xp,bags', layoutConfig.DockSegments)
check('reset: ZoneAssign restored', layoutConfig.ZoneAssign == 'bank:R2,aa:L1', layoutConfig.ZoneAssign)
check('reset: WindowAttach restored', layoutConfig.WindowAttach == 'itemDisplay:hub:right:top', layoutConfig.WindowAttach)
check('reset: LayoutPreset restored', layoutConfig.LayoutPreset == 'Raid', layoutConfig.LayoutPreset)
check('reset: UserPlaced restored', layoutConfig.UserPlaced == 'bank,aa', layoutConfig.UserPlaced)
check('reset: geometry restored too', layoutConfig.WidthInventory == 777, layoutConfig.WidthInventory)
check('reset: UIMode untouched', layoutConfig.UIMode == 'bars', layoutConfig.UIMode)
check('reset: DockTop untouched', layoutConfig.DockTop == true, tostring(layoutConfig.DockTop))
check('reset: DockBottom untouched', layoutConfig.DockBottom == false, tostring(layoutConfig.DockBottom))
check('reset: DockPosition untouched', layoutConfig.DockPosition == 'bottom', layoutConfig.DockPosition)
check('reset: DockChat untouched', layoutConfig.DockChat == 'peek', layoutConfig.DockChat)
check('reset: DockBottomStyle untouched', layoutConfig.DockBottomStyle == 'buttons', layoutConfig.DockBottomStyle)
check('reset: DockButtons untouched', layoutConfig.DockButtons == 'bags,bank', layoutConfig.DockButtons)

-- Reset ends in a save: the rewritten [Layout] must carry the restored arrangement AND the
-- preserved paradigm.
content = readFile()
layoutSect = sectionText(content, 'Layout')
check('post-reset [Layout] has restored ZoneAssign', keyValue(layoutSect, 'ZoneAssign') == 'bank:R2,aa:L1', keyValue(layoutSect, 'ZoneAssign'))
check('post-reset [Layout] has restored UserPlaced', keyValue(layoutSect, 'UserPlaced') == 'bank,aa', keyValue(layoutSect, 'UserPlaced'))
check('post-reset [Layout] kept UIMode=bars', keyValue(layoutSect, 'UIMode') == 'bars', keyValue(layoutSect, 'UIMode'))
check('post-reset [Layout] kept DockBottom=0', keyValue(layoutSect, 'DockBottom') == '0', keyValue(layoutSect, 'DockBottom'))

-- ---------------------------------------------------------------------------
-- 3. Legacy [Defaults] (no bars keys): arrangement falls back to shipped defaults,
--    paradigm still untouched.
-- ---------------------------------------------------------------------------

os.remove(iniPath)
local fh = io.open(iniPath, 'w')
fh:write('[Defaults]\nWidthInventory=555\n')
fh:close()
-- Fresh-session snapshot: state.lua shipped values.
layoutDefaults.DockSegments = SHIPPED_SEGMENTS
layoutDefaults.ZoneAssign = ''
layoutDefaults.WindowAttach = ''
layoutDefaults.LayoutPreset = ''
layoutDefaults.UserPlaced = ''
-- User's live bars arrangement, about to be reset.
layoutConfig.DockSegments = 'xp'
layoutConfig.ZoneAssign = 'bank:B2'
layoutConfig.WindowAttach = 'aa:hub:left:top'
layoutConfig.LayoutPreset = 'Solo'
layoutConfig.UserPlaced = 'aa'

LayoutUtils.resetLayoutToDefault()

check('legacy reset: WidthInventory from old [Defaults]', layoutConfig.WidthInventory == 555, layoutConfig.WidthInventory)
check('legacy reset: DockSegments -> shipped', layoutConfig.DockSegments == SHIPPED_SEGMENTS, layoutConfig.DockSegments)
check('legacy reset: ZoneAssign -> empty', layoutConfig.ZoneAssign == '', layoutConfig.ZoneAssign)
check('legacy reset: WindowAttach -> empty', layoutConfig.WindowAttach == '', layoutConfig.WindowAttach)
check('legacy reset: LayoutPreset -> empty', layoutConfig.LayoutPreset == '', layoutConfig.LayoutPreset)
check('legacy reset: UserPlaced -> empty', layoutConfig.UserPlaced == '', layoutConfig.UserPlaced)
check('legacy reset: UIMode still untouched', layoutConfig.UIMode == 'bars', layoutConfig.UIMode)

-- ---------------------------------------------------------------------------
-- 4. Capture -> reset round-trip of EMPTY arrangement values (empty is meaningful:
--    "no overrides" must come back as no overrides, not as WIPED leftovers).
-- ---------------------------------------------------------------------------

layoutConfig.ZoneAssign = ''
layoutConfig.WindowAttach = ''
layoutConfig.UserPlaced = ''
layoutConfig.LayoutPreset = ''
LayoutUtils.captureCurrentLayoutAsDefault()
layoutDefaults.ZoneAssign = 'WIPED'
layoutDefaults.UserPlaced = 'WIPED'
layoutConfig.ZoneAssign = 'bank:R1'
layoutConfig.UserPlaced = 'bank'
LayoutUtils.resetLayoutToDefault()
check('empty round-trip: ZoneAssign back to empty', layoutConfig.ZoneAssign == '', layoutConfig.ZoneAssign)
check('empty round-trip: UserPlaced back to empty', layoutConfig.UserPlaced == '', layoutConfig.UserPlaced)

os.execute('rmdir /s /q "' .. tmpDir:gsub('/', '\\') .. '" >nul 2>&1')
print(string.format('\n%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
