--[[
    test_layout_presets.lua — headless suite for services/layout_presets.lua.

    Disk I/O goes to a per-run temp directory via a stubbed itemui.config, so the suite
    exercises the REAL file_safe + layout_io.parseSectionsMatching round-trip. Registry and
    window_zones are the real modules (test_window_zones pattern).

    Run:  COOPT_REPO=C:/Claude/CooptUI <luajit> scripts/tests/test_layout_presets.lua
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
local tmpDir = tmpBase .. '/coopt_presets_test_' .. tostring(os.clock()):gsub('%.', '')
os.execute('mkdir "' .. tmpDir:gsub('/', '\\') .. '" >nul 2>&1')

-- Stubs BEFORE any itemui require.
package.loaded['mq'] = {
    gettime = function() return 100000 end,
    cmd = function() end, cmdf = function() end, delay = function() end,
    event = function() end, TLO = setmetatable({}, { __index = function() return function() end end }),
}
package.loaded['itemui.core.diagnostics'] = { getErrorCount = function() return 0 end, recordError = function() end }
package.loaded['itemui.config'] = {
    getConfigFile = function(name) return tmpDir .. '/' .. name end,
}

local registry = require('itemui.core.registry')
local zones = require('itemui.services.window_zones')
local presets = require('itemui.services.layout_presets')
local layoutIO = require('itemui.utils.layout_io')

registry.init({ layoutConfig = {}, companionWindowOpenedAt = {} })
local MODULE_ZONES = {
    equipment = 'L1', augments = 'L2', augmentUtility = 'L2',
    bank = 'R1', itemDisplay = 'R1',
    aa = 'R2', reroll = 'R2', mythicals = 'R2',
    effects = 'B1', favorites = 'B1', commandCenter = 'B2',
}
for id, z in pairs(MODULE_ZONES) do
    registry.register({ id = id, label = id, zone = z, render = function() end })
end

local statusMessages = {}
local setKeyCalls = {}
local hubDrawn = false
local function newDeps()
    local lc = {
        UIMode = 'bars', WidthInventory = 600, Height = 400,
        ZoneAssign = '', WindowAttach = '', UserPlaced = '', LayoutPreset = '',
        WidthBankPanel = 320, HeightBank = 220,
        WidthItemDisplayPanel = 320, HeightItemDisplay = 220,
        WidthEquipmentPanel = 300, HeightEquipment = 220,
        WidthAugmentUtilityPanel = 300, HeightAugmentUtility = 220,
    }
    local uiState = {
        dockWorkRect = { x = 0, y = 38, w = 1920, h = 1004 },
        itemUIPositionX = 660, itemUIPositionY = 140,
        lootUIOpen = false, layoutRevertedApplyFrames = 0,
    }
    return {
        layoutConfig = lc, uiState = uiState,
        scheduleLayoutSave = function() end,
        setLayoutValue = function(k, v) setKeyCalls[#setKeyCalls + 1] = { k = k, v = v }; lc[k] = v end,
        setStatusMessage = function(m) statusMessages[#statusMessages + 1] = m end,
        getShouldDraw = function() return hubDrawn end,
        setShouldDraw = function(v) hubDrawn = v end,
        setOpen = function(v) end,
        recordCompanionWindowOpened = function() end,
    }
end

-- ---------------------------------------------------------------------------
-- 1. Pure round-trip
-- ---------------------------------------------------------------------------

local data = presets.fromSection({
    Open = 'hub, bank ,itemDisplay', ZoneAssign = 'bank:R2', WindowAttach = 'itemDisplay:hub:right:top',
    BankWindowX = '1266', BankWindowY = '140', Junk = 'notanumber',
})
check('fromSection parses Open list', #data.open == 3 and data.open[2] == 'bank', table.concat(data.open, '|'))
check('fromSection keeps zone/attach strings', data.zoneAssign == 'bank:R2' and data.windowAttach == 'itemDisplay:hub:right:top')
check('fromSection keeps numeric geometry only', data.geometry.BankWindowX == 1266 and data.geometry.Junk == nil)

local lines = presets.toLines(data)
check('toLines leads with Open', lines[1] == 'Open=hub,bank,itemDisplay', lines[1])

local content = presets.serializeAll({ { name = 'Trip', data = data } })
local pth = tmpDir .. '/roundtrip.ini'
local fh = io.open(pth, 'w'); fh:write(content); fh:close()
local sections, order = layoutIO.parseSectionsMatching(pth, '^Preset:')
check('serializeAll -> parseSectionsMatching round-trips', order[1] == 'Preset:Trip'
    and sections['Preset:Trip'].Open == 'hub,bank,itemDisplay'
    and sections['Preset:Trip'].BankWindowX == '1266', tostring(order[1]))

-- ---------------------------------------------------------------------------
-- 2. Seeding
-- ---------------------------------------------------------------------------

local d = newDeps()
zones._reset(); zones.init(d); presets.init(d)

check('seedIfMissing writes the bundled five', presets.seedIfMissing() == true)
local names = presets.list()
check('five presets on disk, order preserved', #names == 5 and names[1] == 'Bag session' and names[5] == 'Raid - minimal',
    table.concat(names, '|'))
check('second seed is a no-op', presets.seedIfMissing() == false)
check('bundled preset carries no geometry', next(presets.get('Bag session').geometry) == nil)

-- ---------------------------------------------------------------------------
-- 3. Apply
-- ---------------------------------------------------------------------------

-- Arrange: equipment open (not in Bag session), bank closed, hub hidden, stale zone state.
registry.setWindowState('equipment', true, true)
registry.setWindowState('bank', false, false)
hubDrawn = false
d.layoutConfig.UserPlaced = 'equipment'
d.layoutConfig.ZoneAssign = 'bank:L1'

check('apply of unknown preset fails clean', presets.apply('No such preset') == false)
check('apply Bag session succeeds', presets.apply('Bag session') == true)
check('apply closes windows not in the preset', not registry.isOpen('equipment'))
check('apply opens the preset windows', registry.isOpen('bank') and registry.isOpen('itemDisplay'))
check('apply shows the hub', hubDrawn == true)
check('apply clears UserPlaced', d.layoutConfig.UserPlaced == '', d.layoutConfig.UserPlaced)
check('apply resets ZoneAssign to preset value', d.layoutConfig.ZoneAssign == '', d.layoutConfig.ZoneAssign)
check('apply sets LayoutPreset through setLayoutValue', d.layoutConfig.LayoutPreset == 'Bag session'
    and setKeyCalls[#setKeyCalls] and setKeyCalls[#setKeyCalls].k == 'LayoutPreset')
check('apply raises force-apply frames', (d.uiState.layoutRevertedApplyFrames or 0) >= 3,
    d.uiState.layoutRevertedApplyFrames)
local bankRect = zones.rectOf('bank')
check('opened windows got placed (no geometry in bundled preset)', bankRect ~= nil and bankRect.x ~= 0,
    bankRect and bankRect.x)

-- Pinned windows survive a preset switch.
registry.setWindowState('equipment', true, true)
registry.setPinned('equipment', true)
presets.apply('Raid - minimal')
check('pinned window survives preset switch', registry.isOpen('equipment'))
check('unpinned windows closed by Raid - minimal', not registry.isOpen('bank') and not registry.isOpen('itemDisplay'))
check('Raid - minimal hides the hub', hubDrawn == false)
registry.setPinned('equipment', false)

-- ---------------------------------------------------------------------------
-- 4. Save current as / delete
-- ---------------------------------------------------------------------------

registry.setWindowState('bank', true, true)
d.layoutConfig.BankWindowX, d.layoutConfig.BankWindowY = 1266, 140
hubDrawn = true
check('saveCurrent rejects bad names', presets.saveCurrent('has [brackets]') == false
    and presets.saveCurrent('has:colon') == false and presets.saveCurrent('  ') == false)
check('saveCurrent writes a preset', presets.saveCurrent('My arrangement') == true)
local mine = presets.get('My arrangement')
check('saved preset captured open windows', mine ~= nil and (function()
    local has = {}
    for _, id in ipairs(mine.open) do has[id] = true end
    return has.hub and has.bank and has.equipment
end)(), mine and table.concat(mine.open, '|'))
check('saved preset captured geometry', mine.geometry.BankWindowX == 1266, mine and mine.geometry.BankWindowX)
check('saveCurrent set the active preset name', d.layoutConfig.LayoutPreset == 'My arrangement')
check('saveCurrent replaces on same name', presets.saveCurrent('My arrangement') == true and #presets.list() == 6)

check('delete removes a preset', presets.delete('My arrangement') == true and presets.get('My arrangement') == nil)
check('delete of missing preset returns false', presets.delete('My arrangement') == false)
check('bundled five intact after delete', #presets.list() == 5)

-- ---------------------------------------------------------------------------
-- 5. Regression (review C1/C8/C13/C16): a preset's captured geometry must survive the
--    window_zones tick that runs LATER in the same main-loop pass — open-edge placement
--    used to re-zone every preset-opened window and discard the saved positions.
-- ---------------------------------------------------------------------------

do
    local now = 200000
    local function zonesTick(n)
        for _ = 1, (n or 1) do
            local u = d.uiState
            if (tonumber(u.layoutRevertedApplyFrames) or 0) > 0 then
                u.layoutRevertedApplyFrames = u.layoutRevertedApplyFrames - 1
            end
            now = now + 260
            zones.tick(now)
        end
    end
    zones._reset(); zones.init(d)
    zonesTick()   -- learn the current open set

    registry.setWindowState('bank', true, true)
    d.layoutConfig.BankWindowX, d.layoutConfig.BankWindowY = 900, 500
    hubDrawn = true
    check('regression setup: saved a geometry-carrying preset', presets.saveCurrent('Clobber check') == true)
    registry.setWindowState('bank', false, false)
    zonesTick()   -- see the close edge

    check('regression: apply reopens bank', presets.apply('Clobber check') == true and registry.isOpen('bank'))
    zonesTick(5)  -- the same-tick zones pass PLUS enough ticks to burn the force-apply frames
    check('regression: preset geometry survives the zones tick',
        d.layoutConfig.BankWindowX == 900 and d.layoutConfig.BankWindowY == 500,
        tostring(d.layoutConfig.BankWindowX) .. ',' .. tostring(d.layoutConfig.BankWindowY))
    check('regression: preset-opened window not marked user-placed',
        (d.layoutConfig.UserPlaced or '') == '', d.layoutConfig.UserPlaced)
    presets.delete('Clobber check')
end

-- ---------------------------------------------------------------------------
-- 6. Regression (review C10): an EXISTING presets file — even one that is empty or
--    momentarily unreadable — must never be overwritten by the bundled seed.
-- ---------------------------------------------------------------------------

do
    local path = presets.getPresetsFilePath():gsub('/', '\\')
    os.remove(presets.getPresetsFilePath())
    local fh = io.open(presets.getPresetsFilePath(), 'w'); fh:write(''); fh:close()
    check('seed refuses to touch an existing (empty) file', presets.seedIfMissing() == false)
    check('the empty file stayed empty', #presets.list() == 0, #presets.list())
    os.remove(presets.getPresetsFilePath())
    check('seed works again once the file is truly absent', presets.seedIfMissing() == true and #presets.list() == 5)
end

os.execute('rmdir /s /q "' .. tmpDir:gsub('/', '\\') .. '" >nul 2>&1')
print(string.format('\n%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
