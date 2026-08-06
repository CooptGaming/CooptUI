-- Full-window render test for views/item_display.lua (windows pass v2), driven through the
-- recording ImGui stub. This suite exists because two in-game failures shipped in paths no
-- suite touched: formatSize(item.size) threw between BeginChild/EndChild (the overlay-pause
-- crash), and the augment rows rendered but had dead hitboxes. Every frame here asserts the
-- one invariant MQ2Lua enforces with a script-kill: the ImGui stacks end balanced.
--
-- The stub is not a layout engine: nothing here asserts pixels, columns or right-alignment.
-- What it proves: the window renders every section for plain/augmented/weapon/equipped
-- items without error or imbalance, the remembered sections toggle through section_state,
-- an empty socket click routes to Aug Utility, RULES shows on equipped tabs, and injected
-- throws anywhere in content cost one frame, never the stacks.

local repo = os.getenv('COOPT_REPO') or 'C:/Claude/CooptUI'
package.path = repo .. '/lua/?.lua;' .. repo .. '/lua/?/init.lua;'
    .. repo .. '/scripts/tests/?.lua;' .. package.path

local pass, fail = 0, 0
local function check(name, cond, extra)
    if cond then
        pass = pass + 1
        print('PASS: ' .. name)
    else
        fail = fail + 1
        print('FAIL: ' .. name .. (extra and ('  -> ' .. tostring(extra)) or ''))
    end
end

local stub = require('imgui_stub')
stub.install()
package.loaded['mq'] = stub.newMq()
package.loaded['itemui.utils.coopui_plugin'] = {
    getPlugin = function() return nil end, getIPC = function() return nil end,
    getINI = function() return nil end, getWindow = function() return nil end,
    getCursor = function() return nil end, getItems = function() return nil end,
}
package.loaded['itemui.core.diagnostics'] = {
    getErrorCount = function() return 0 end, recordError = function() end,
}

local theme = require('itemui.utils.theme')
local fonts = require('itemui.utils.fonts')
local registry = require('itemui.core.registry')
local uiState = require('itemui.state').uiState
local sectionState = require('itemui.services.section_state')
local TooltipData = require('itemui.utils.tooltip_data')
local ItemDisplayView = require('itemui.views.item_display')

registry.init({ layoutConfig = { UIMode = 'bars' }, companionWindowOpenedAt = {} })
registry.setWindowState('itemDisplay', true, true)
sectionState.init({
    getCharStoragePath = nil,  -- persistence is test_section_state's job; defaults suffice
    parseSectionsMatching = nil,
    safeWrite = function() return true end,
})

-- ---------------------------------------------------------------- fake ctx
local recorded = { tabsOpened = {}, layoutSaves = 0 }
local ctx = {
    theme = theme,
    layoutConfig = {},
    uiState = uiState,
    drawItemIcon = function() end,
    drawEmptySlotIcon = function() end,
    getItemTLO = nil,             -- no live TLO in headless frames: verdict runs "none" path
    equipmentCache = nil,
    getItemStatsForTooltip = function() return nil end,
    getSellStatusForItem = function() return 'vendor trash', true, false, false end,
    formatSellStatus = function(reason, willSell) return tostring(reason), ImVec4(1, 1, 1, 1) end,
    applySellListChange = function() end,
    resolveRerollList = nil,
    requestAddToRerollList = nil,
    rerollService = nil,
    getSpellDuration = function() return 600 end,
    getSpellRecoveryTime = function() return 0 end,
    getSpellRecastTime = function() return 12 end,
    getSpellRange = function() return 100 end,
    getItemSpellId = function() return nil end,
    getSpellName = function() return nil end,
    addItemDisplayTab = function(item, source) recorded.tabsOpened[#recorded.tabsOpened + 1] = { item = item, source = source } end,
    removeAugment = function() end,
    scheduleLayoutSave = function() recorded.layoutSaves = recorded.layoutSaves + 1 end,
    getStandardAugSlotsCountFromTLO = nil,
    getFilledStandardAugmentSlotIndices = nil,
    getWornSlotIndicesFromTLO = nil,
}

local viewState = ItemDisplayView.getState()

local function setTab(entry)
    viewState.itemDisplayTabs = { entry }
    viewState.itemDisplayActiveTabIndex = 1
    viewState.itemDisplayRecent = {}
end

local function frame()
    fonts._resetForTests()
    return stub.frame(function() ItemDisplayView.render(ctx) end)
end

-- ---------------------------------------------------------------- plain item
do
    setTab({ bag = 1, slot = 2, source = 'inv', label = 'Plain Ring', item = {
        id = 101, name = 'Plain Ring', type = 'Jewelry', icon = 0, value = 12345,
        hp = 100, ac = 10, size = 2, weight = 3, reqLevel = 35, tribute = 120, stackSize = 1,
        augSlots = 0,
    } })
    local r = frame()
    check('plain: frame ok', r.ok, r.err)
    check('plain: balanced', stub.balanced(r), stub.imbalance(r))
    check('plain: identity card drew the name', stub.drew(r, 'Plain Ring'))
    check('plain: locator line drew', stub.drew(r, 'bag 1, slot 2'))
    check('plain: rules section offered on inv tab', stub.drew(r, 'RULES'))
    check('plain: keep/junk buttons offered', stub.drew(r, 'Keep##ItemDisplayRules')
        and stub.drew(r, 'Junk##ItemDisplayRules'))
    check('plain: all stats section absent with no listed stats', not stub.drew(r, 'ALL STATS'))
end

-- ---------------------------------------------------------------- augmented item
local augEntry
do
    local augItem = {
        id = 202, name = 'Mythical Earring of Dispersion', type = 'Jewelry', icon = 500,
        hp = 1493, ac = 102, mana = 896, value = 250000, size = 1, weight = 3,
        str = 23, heroicSTR = 6, svMagic = 32, accuracy = 15, augSlots = 3,
    }
    augEntry = { bag = 2, slot = 3, source = 'inv', label = 'Mythical Earring', item = augItem }
    -- The cache entry the TLO socket walk would have produced in game.
    TooltipData._seedTooltipCacheForTests(augItem, { source = 'inv', bag = 2, slot = 3 }, {
        augStats = { hp = 271, ac = 21, mana = 181 },
        augLines = {
            { iconId = 0, prefix = 'Slot 1, type 7 (General: Group): ', augName = 'Ruby Aug of Power', slotIndex = 1,
              text = 'Slot 1, type 7 (General: Group): Ruby Aug of Power' },
            { iconId = 0, prefix = 'Slot 2, type 7 (General: Group): ', augName = 'empty', slotIndex = 2,
              text = 'Slot 2, type 7 (General: Group): empty' },
        },
        ornamentLine = { iconId = 0, augName = 'Shiny Ornament', slotIndex = 5, typ = 20 },
        effects = {
            { key = 'Clicky', spellName = 'Might of Stone IV', spellId = 21903, castTime = 1.5, recastTime = 600 },
            { key = 'Worn', spellName = 'Sharpshooting VII', spellId = 9616 },
        },
        width = 400, height = 300,
    })
    setTab(augEntry)
    local r = frame()
    check('aug: frame ok', r.ok, r.err)
    check('aug: balanced', stub.balanced(r), stub.imbalance(r))
    check('aug: effects section with count', stub.drew(r, 'EFFECTS (2)'))
    check('aug: effect row drawn', stub.drew(r, 'Might of Stone IV'))
    check('aug: all stats section counts the listed stats', stub.drew(r, 'ALL STATS'))
    check('aug: augments section with filled/total', stub.drew(r, 'AUGMENTS (2/3)'))
    -- The sockets are icon CELLS now (field ruling 08-04): names live on the cell
    -- hover, not in always-visible rows. Hover the cell child (the EndChild;
    -- IsItemHovered pattern the stub models for dock slots) and expect the name.
    stub.hover = { IDaugcell_1 = true }
    local rH = frame()
    stub.hover = {}
    check('aug: filled socket name on cell hover', stub.drew(rH, 'Ruby Aug of Power'))
    stub.hover = { IDaugcell_5_orn = true }
    local rO = frame()
    stub.hover = {}
    check('aug: ornament name on cell hover', stub.drew(rO, 'Shiny Ornament'))
    check('aug: spell data closed by default (rows not drawn)',
        not stub.drew(r, 'id 21903'))
end

-- ---------------------------------------------------------------- socket clicks
do
    uiState.augmentUtilitySlotIndex = nil
    -- Cells click via hover + left mouse (no Selectable label anymore): hover the
    -- empty slot-2 cell and press.
    stub.hover = { IDaugcell_2 = true }
    stub.mouse = { [ImGuiMouseButton.Left] = true }
    local r = frame()
    stub.hover = {}
    stub.mouse = {}
    check('aug: socket cell click frame ok', r.ok and stub.balanced(r),
        (r.err or '') .. ' ' .. stub.imbalance(r))
    check('aug: socket cell click routes to Aug Utility at slot 2',
        uiState.augmentUtilitySlotIndex == 2, uiState.augmentUtilitySlotIndex)
end

-- ---------------------------------------------------------------- section memory
do
    check('sections: spell data default closed',
        sectionState.isOpen('ItemDisplay', 'SpellData', false) == false)
    stub.click = { ['SPELL DATA & IDS##IDsecSpellData'] = true }
    local r = frame()
    stub.click = {}
    check('sections: toggle frame ok', r.ok and stub.balanced(r), (r.err or '') .. ' ' .. stub.imbalance(r))
    check('sections: spell data remembered open',
        sectionState.isOpen('ItemDisplay', 'SpellData', false) == true)
    local r2 = frame()
    check('sections: reopened section draws its rows now', stub.drew(r2, 'id 21903'))
    -- Put it back so later frames stay deterministic.
    stub.click = { ['SPELL DATA & IDS##IDsecSpellData'] = true }
    frame()
    stub.click = {}
end

-- ---------------------------------------------------------------- weapon strip
do
    setTab({ bag = 3, slot = 1, source = 'inv', label = 'Big Axe', item = {
        id = 303, name = 'Big Axe of Testing', type = '2H Slashing', icon = 600,
        damage = 512, itemDelay = 45, attack = 62, hp = 2140, value = 90000,
        stackSize = 1, augSlots = 0,
    } })
    local r = frame()
    check('weapon: frame ok', r.ok, r.err)
    check('weapon: balanced', stub.balanced(r), stub.imbalance(r))
    check('weapon: strip cells drawn', stub.drew(r, 'DMG') and stub.drew(r, 'DELAY')
        and stub.drew(r, 'RATIO') and stub.drew(r, 'DPS'))
end

-- ---------------------------------------------------------------- equipped tab
do
    setTab({ bag = 0, slot = 4, source = 'equipped', label = 'Worn Earring', item = {
        id = 404, name = 'Worn Earring of Rules', type = 'Jewelry', icon = 0,
        hp = 700, ac = 48, value = 5000, stackSize = 1, augSlots = 0,
    } })
    local r = frame()
    check('equipped: frame ok', r.ok, r.err)
    check('equipped: balanced', stub.balanced(r), stub.imbalance(r))
    check('equipped: locator says equipped', stub.drew(r, 'equipped'))
    check('equipped: RULES offered (the smoke-test gap)', stub.drew(r, 'RULES'))
    check('equipped: keep/junk buttons offered', stub.drew(r, 'Keep##ItemDisplayRules')
        and stub.drew(r, 'Junk##ItemDisplayRules'))
end

-- ---------------------------------------------------------------- injected throws
do
    setTab(augEntry)
    for _, victim in ipairs({ 'TextColored', 'Selectable', 'CollapsingHeader', 'Text' }) do
        stub.throwOn = { [victim] = true }
        local r = frame()
        stub.throwOn = {}
        check('throw in ' .. victim .. ': frame survives balanced',
            r.ok and stub.balanced(r), (r.err or '') .. ' ' .. stub.imbalance(r))
    end
end

-- ---------------------------------------------------------------- summary
local missing = {}
for k, v in pairs(stub.missing) do missing[#missing + 1] = k .. 'x' .. v end
if #missing > 0 then print('\nunstubbed ImGui calls seen: ' .. table.concat(missing, ', ')) end

print(string.format('\n%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
