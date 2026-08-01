--[[
    test_window_zones.lua — headless suite for services/window_zones.lua.

    Pure-logic service, so no ImGui stub: fake deps in, layoutConfig writes out — the
    test_dock_state pattern. Uses the REAL registry (as test_dock_render does), registering
    the production module ids + zones so zone resolution runs the real path.

    Run:  COOPT_REPO=C:/Claude/CooptUI <luajit> scripts/tests/test_window_zones.lua
]]

local repo = os.getenv('COOPT_REPO') or 'C:/Claude/CooptUI'
package.path = repo .. '/lua/?.lua;' .. repo .. '/lua/?/init.lua;' .. package.path

local pass, fail = 0, 0
local function check(name, cond, extra)
    if cond then pass = pass + 1; print('PASS: ' .. name)
    else fail = fail + 1; print('FAIL: ' .. name .. '  -> ' .. tostring(extra)) end
end

-- Stubs before any itemui require.
package.loaded['mq'] = {
    gettime = function() return 100000 end,
    cmd = function() end, cmdf = function() end, delay = function() end,
    event = function() end, TLO = setmetatable({}, { __index = function() return function() end end }),
}
package.loaded['itemui.core.diagnostics'] = { getErrorCount = function() return 0 end, recordError = function() end }

local registry = require('itemui.core.registry')
local zones = require('itemui.services.window_zones')

-- Production zone map (mirrors the view register() calls).
local MODULE_ZONES = {
    equipment = 'L1', augments = 'L2', augmentUtility = 'L2',
    bank = 'R1', itemDisplay = 'R1',
    aa = 'R2', reroll = 'R2', mythicals = 'R2',
    effects = 'B1', favorites = 'B1', commandCenter = 'B2',
}

registry.init({ layoutConfig = {}, companionWindowOpenedAt = {} })
for id, z in pairs(MODULE_ZONES) do
    registry.register({ id = id, label = id, zone = z, render = function() end })
end
registry.register({ id = 'config', label = 'config', render = function() end })  -- no zone: never auto-placed

-- Window sizes for the acceptance runs: modest, so a full fit IS geometrically possible —
-- the test then demands the algorithm finds it.
local SIZES = {
    equipment      = { w = 300, h = 220 }, augments  = { w = 300, h = 220 },
    augmentUtility = { w = 300, h = 220 }, bank      = { w = 320, h = 220 },
    itemDisplay    = { w = 320, h = 220 }, aa        = { w = 300, h = 220 },
    reroll         = { w = 300, h = 220 }, mythicals = { w = 300, h = 220 },
    effects        = { w = 300, h = 200 }, favorites = { w = 300, h = 200 },
    -- commandCenter and loot have no size keys; the service uses its 420x360 nominal.
}

local scheduleCount = 0
local function newDeps(opts)
    opts = opts or {}
    local lc = {
        UIMode = opts.uiMode or 'bars',
        WidthInventory = opts.hubW or 600, Height = opts.hubH or 400,
        ZoneAssign = '', WindowAttach = '', UserPlaced = '',
    }
    for id, s in pairs(SIZES) do
        local g = zones.GEOM[id]
        if g.w then lc[g.w] = s.w end
        if g.h then lc[g.h] = s.h end
    end
    local uiState = {
        dockWorkRect = opts.work or { x = 0, y = 38, w = 1920, h = 1004 },
        itemUIPositionX = opts.hubX or 660, itemUIPositionY = opts.hubY or 140,
        lootUIOpen = false,
        layoutRevertedApplyFrames = 0,
    }
    return {
        layoutConfig = lc, uiState = uiState,
        scheduleLayoutSave = function() scheduleCount = scheduleCount + 1 end,
        getShouldDraw = function() return opts.hubClosed ~= true end,
    }
end

local function closeAll()
    for id in pairs(MODULE_ZONES) do registry.setWindowState(id, false, false) end
end

local now = 100000
--- Advance like main_loop does: the force-apply frame counter decrements BEFORE the zones
--- pass each tick (main_loop.lua trackWindowStateChanges runs first). While frames > 0 the
--- service treats geometry changes as programmatic, so drag simulations must burn them off
--- with plain ticks first — exactly as 500 ms of real time would.
local function tick(d, n)
    for _ = 1, (n or 1) do
        local u = d and d.uiState
        if u and (tonumber(u.layoutRevertedApplyFrames) or 0) > 0 then
            u.layoutRevertedApplyFrames = u.layoutRevertedApplyFrames - 1
        end
        now = now + 260
        zones.tick(now)
    end
end

-- ---------------------------------------------------------------------------
-- 1. Pure geometry
-- ---------------------------------------------------------------------------

check('rects overlap', zones.rectsOverlap({x=0,y=0,w=100,h=100},{x=50,y=50,w=100,h=100}))
check('gutter-adjacent rects do not overlap', not zones.rectsOverlap({x=0,y=0,w=100,h=100},{x=100,y=0,w=100,h=100}))
local cx, cy = zones.clampToWork(-50, 2000, 200, 100, {x=0,y=38,w=1920,h=1004})
check('clamp pulls into work rect', cx == 0 and cy == 38 + 1004 - 100, cx .. ',' .. cy)
local ox, oy = zones.clampToWork(100, 100, 3000, 100, {x=0,y=38,w=1920,h=1004})
check('oversized window pins to work origin', ox == 0, ox)

local hub = { x = 660, y = 140, w = 600, h = 400 }
local work = { x = 0, y = 38, w = 1920, h = 1004 }
local cands = zones.candidatesFor('L', 1, 300, 220, hub, {}, work)
check('L column right-aligns to hub left edge', cands[1].x == 660 - 300 - zones.GAP and cands[1].y == 140,
    cands[1].x .. ',' .. cands[1].y)
local candsR2 = zones.candidatesFor('R', 2, 300, 220, hub, { { x = 1266, y = 140, w = 300, h = 220 } }, work)
check('rank 2 prefers the slot below the occupant', candsR2[1].y == 140 + 220 + zones.GAP, candsR2[1].y)

local sx, sy, clean = zones.firstFreeSlot(
    { { x = 354, y = 140 } }, 300, 220, { { x = 354, y = 140, w = 300, h = 220 } }, work, 0)
check('occupied slot falls through to cascade', clean == false, tostring(clean))

local snap = zones.magnetFor({ x = 1271, y = 145, w = 300, h = 220 }, { hub = hub }, 6, 12)
check('magnet snaps right-of hub with top align',
    snap and snap.edge == 'right' and snap.align == 'top' and snap.x == 660 + 600 + 6 and snap.y == 140,
    snap and (snap.edge .. '/' .. tostring(snap.x)))
check('magnet ignores beyond threshold', zones.magnetFor({ x = 1300, y = 600, w = 300, h = 220 }, { hub = hub }, 6, 12) == nil)

local upSet = zones.parseUserPlaced('bank, itemDisplay')
check('UserPlaced CSV parses', upSet.bank and upSet.itemDisplay)
check('UserPlaced CSV round-trips sorted', zones.serializeUserPlaced(upSet) == 'bank,itemDisplay')
local at = zones.parseAttachments('itemDisplay:hub:right:top,bank:itemDisplay:bottom:left')
check('WindowAttach CSV parses', at.itemDisplay and at.itemDisplay.target == 'hub' and at.bank.edge == 'bottom')
check('WindowAttach round-trips', zones.serializeAttachments(at) == 'bank:itemDisplay:bottom:left,itemDisplay:hub:right:top')

-- ---------------------------------------------------------------------------
-- 2. Acceptance: all 12 windows, no overlap, nothing off-screen — both resolutions
-- ---------------------------------------------------------------------------

local function openAllAndCollect(work, hubX, hubY)
    closeAll()
    zones._reset()
    local d = newDeps({ work = work, hubX = hubX, hubY = hubY })
    zones.init(d)
    tick(d)                                   -- baseline tick: learn the closed open-set
    local ids = {}
    for id in pairs(MODULE_ZONES) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        registry.setWindowState(id, true, true)
        tick(d)                               -- open edge -> placement
    end
    d.uiState.lootUIOpen = true
    tick(d)
    local rects, missing = {}, {}
    for id in pairs(zones.GEOM) do
        local isOpenNow = (id == 'loot') and d.uiState.lootUIOpen or registry.isOpen(id)
        if isOpenNow then
            local r = zones.rectOf(id)
            if r then rects[id] = r else missing[#missing + 1] = id end
        end
    end
    return d, rects, missing
end

local function acceptance(label, work, hubX, hubY)
    local d, rects, missing = openAllAndCollect(work, hubX, hubY)
    check(label .. ': every open window got a position', #missing == 0, table.concat(missing, ','))
    local names = {}
    for id in pairs(rects) do names[#names + 1] = id end
    table.sort(names)
    check(label .. ': 12 windows placed', #names == 12, #names)
    local offenders = {}
    for _, id in ipairs(names) do
        local r = rects[id]
        if r.x < work.x - 1 or r.y < work.y - 1
            or r.x + r.w > work.x + work.w + 1 or r.y + r.h > work.y + work.h + 1 then
            offenders[#offenders + 1] = id
        end
    end
    check(label .. ': nothing off-screen', #offenders == 0, table.concat(offenders, ','))
    local overlaps = {}
    for i = 1, #names do
        for j = i + 1, #names do
            if zones.rectsOverlap(rects[names[i]], rects[names[j]]) then
                overlaps[#overlaps + 1] = names[i] .. '+' .. names[j]
            end
        end
    end
    check(label .. ': no pairwise overlap', #overlaps == 0, table.concat(overlaps, ','))
    local hubR = { x = d.uiState.itemUIPositionX, y = d.uiState.itemUIPositionY,
                   w = d.layoutConfig.WidthInventory, h = d.layoutConfig.Height }
    local overHub = {}
    for _, id in ipairs(names) do
        if zones.rectsOverlap(rects[id], hubR) then overHub[#overHub + 1] = id end
    end
    check(label .. ': nothing covers the hub', #overHub == 0, table.concat(overHub, ','))
end

acceptance('1920x1080', { x = 0, y = 38, w = 1920, h = 1004 }, 660, 140)
acceptance('2560x1440', { x = 0, y = 38, w = 2560, h = 1364 }, 980, 200)

-- ---------------------------------------------------------------------------
-- 3. User-placed: a dragged window stops auto-slotting until Re-tidy
-- ---------------------------------------------------------------------------

closeAll(); zones._reset()
local d = newDeps({})
zones.init(d)
tick(d)
registry.setWindowState('bank', true, true)
tick(d)
local g = zones.GEOM.bank
local placedX = d.layoutConfig[g.x]
check('bank got placed on open', placedX ~= nil and placedX ~= 0, tostring(placedX))

-- The merge rollback's ALIGNMENT contract: bank (zone R1) lands flush against the hub's
-- right edge at the same Y, and placement records the hub attachment itself so the pair
-- survives the first hub drag. Without the auto-attach the alignment is a one-shot the
-- user has to re-earn through the magnet.
do
    local hx = d.uiState.itemUIPositionX + d.layoutConfig.WidthInventory + zones.GAP
    check('bank aligns flush beside the hub, same Y',
        d.layoutConfig[g.x] == hx and d.layoutConfig[g.y] == d.uiState.itemUIPositionY,
        d.layoutConfig[g.x] .. ',' .. d.layoutConfig[g.y] .. ' want ' .. hx .. ',' .. d.uiState.itemUIPositionY)
    check('placement records the hub attachment so the pair travels together',
        (d.layoutConfig.WindowAttach or ''):find('bank:hub:right:top', 1, true) ~= nil,
        d.layoutConfig.WindowAttach)
end

tick(d, 2)           -- burn the placement's force-apply frames

-- Regression (review C3/C18): while force-apply frames are up, geometry writes are
-- programmatic — they must be adopted, not read as drags.
d.uiState.layoutRevertedApplyFrames = 3
d.layoutConfig[g.x] = 450; d.layoutConfig[g.y] = 650
tick(d); tick(d)
check('programmatic move during force-apply is not a drag', zones._state().userPlaced.bank == nil,
    zones.serializeUserPlaced(zones._state().userPlaced))
tick(d, 2)           -- frames reach 0

-- Regression (review C5): a stationary window with the mouse button still down is a
-- PAUSED drag; settling it would snap the window out from under the cursor.
d.uiState.dockMouseHeld = true
d.layoutConfig[g.x] = 480; d.layoutConfig[g.y] = 680
tick(d); tick(d); tick(d)
check('no settle while the mouse button is held', zones._state().userPlaced.bank == nil,
    zones.serializeUserPlaced(zones._state().userPlaced))
d.uiState.dockMouseHeld = false

-- Simulate a drag: position moves for a tick, then holds still (far from any magnet).
d.layoutConfig[g.x] = 500; d.layoutConfig[g.y] = 700
tick(d)              -- observed moving
tick(d)              -- settled -> marked user-placed
check('drag marks bank user-placed', zones._state().userPlaced.bank == true,
    zones.serializeUserPlaced(zones._state().userPlaced))
check('UserPlaced persisted to layoutConfig', (d.layoutConfig.UserPlaced or ''):find('bank') ~= nil,
    d.layoutConfig.UserPlaced)

registry.setWindowState('bank', false, false)
tick(d)
registry.setWindowState('bank', true, true)
tick(d)
check('user-placed bank is NOT re-placed on reopen', d.layoutConfig[g.x] == 500 and d.layoutConfig[g.y] == 700,
    d.layoutConfig[g.x] .. ',' .. d.layoutConfig[g.y])

local n = zones.retidy()
check('retidy re-places open windows', n >= 1, n)
check('retidy clears user-placed', zones._state().userPlaced.bank == nil)
check('retidy raises force-apply frames', (d.uiState.layoutRevertedApplyFrames or 0) >= 2,
    d.uiState.layoutRevertedApplyFrames)

-- ---------------------------------------------------------------------------
-- 4. Magnets + hub-follow through the tick loop
-- ---------------------------------------------------------------------------

closeAll(); zones._reset()
d = newDeps({})
zones.init(d)
tick(d)
registry.setWindowState('itemDisplay', true, true)
tick(d)
tick(d, 2)           -- burn placement force-apply frames
local gi = zones.GEOM.itemDisplay
-- Drag to 9px right of the hub's right edge, tops within threshold.
local hx, hy = d.uiState.itemUIPositionX, d.uiState.itemUIPositionY
local hw = d.layoutConfig.WidthInventory
d.layoutConfig[gi.x] = hx + hw + 9; d.layoutConfig[gi.y] = hy + 5
tick(d)              -- moving
tick(d)              -- settled -> snap
check('settled drag snapped flush to hub', d.layoutConfig[gi.x] == hx + hw + zones.GAP and d.layoutConfig[gi.y] == hy,
    d.layoutConfig[gi.x] .. ',' .. d.layoutConfig[gi.y])
check('attachment recorded in layoutConfig', (d.layoutConfig.WindowAttach or ''):find('itemDisplay:hub:right') ~= nil,
    d.layoutConfig.WindowAttach)

-- Hub drag: move, then settle; the attached window travels by the same delta.
tick(d, 2)           -- burn the snap's force-apply frames first
local beforeX = d.layoutConfig[gi.x]
d.uiState.itemUIPositionX = hx + 80; d.uiState.itemUIPositionY = hy + 40
tick(d)              -- hub moving
tick(d)              -- hub settled -> follow
check('hub-follow translated the attached window', d.layoutConfig[gi.x] == beforeX + 80 and d.layoutConfig[gi.y] == hy + 40,
    d.layoutConfig[gi.x] .. ',' .. d.layoutConfig[gi.y])

-- Alt bypass: dragging with Alt held must neither snap nor attach.
closeAll(); zones._reset()
d = newDeps({})
zones.init(d)
tick(d)
registry.setWindowState('bank', true, true)
tick(d)
tick(d, 2)           -- burn placement force-apply frames
local gb = zones.GEOM.bank
d.uiState.dockAltHeld = true
d.layoutConfig[gb.x] = d.uiState.itemUIPositionX + d.layoutConfig.WidthInventory + 9
d.layoutConfig[gb.y] = d.uiState.itemUIPositionY + 3
tick(d); tick(d)
check('Alt-drag does not snap', d.layoutConfig[gb.x] == d.uiState.itemUIPositionX + d.layoutConfig.WidthInventory + 9,
    d.layoutConfig[gb.x])
check('Alt-drag does not attach', (d.layoutConfig.WindowAttach or '') == '', d.layoutConfig.WindowAttach)

-- ---------------------------------------------------------------------------
-- 5. Close-edge slide-up + classic-mode inertness
-- ---------------------------------------------------------------------------

closeAll(); zones._reset()
d = newDeps({})
zones.init(d)
tick(d)
registry.setWindowState('itemDisplay', true, true); tick(d)
registry.setWindowState('bank', true, true); tick(d)
-- Attach bank below itemDisplay by hand (the CSV is authoritative; sync picks it up).
d.layoutConfig.WindowAttach = 'bank:itemDisplay:bottom:left'
local idRect = zones.rectOf('itemDisplay')
registry.setWindowState('itemDisplay', false, false)
tick(d)
local bankRect = zones.rectOf('bank')
check('closing the target slides the attached window into its place',
    bankRect and math.abs(bankRect.x - idRect.x) <= 1 and math.abs(bankRect.y - idRect.y) <= 1,
    bankRect and (bankRect.x .. ',' .. bankRect.y) .. ' vs ' .. idRect.x .. ',' .. idRect.y)
check('attachment to a closed window is dropped', (d.layoutConfig.WindowAttach or '') == '',
    d.layoutConfig.WindowAttach)

closeAll(); zones._reset()
d = newDeps({ uiMode = 'classic' })
zones.init(d)
tick(d)
registry.setWindowState('equipment', true, true)
local ge = zones.GEOM.equipment
local beforeClassic = d.layoutConfig[ge.x]
tick(d, 3)
check('classic mode never places', d.layoutConfig[ge.x] == beforeClassic, tostring(d.layoutConfig[ge.x]))

-- Switching to bars later must not treat long-open windows as newly opened.
d.layoutConfig.UIMode = 'bars'
tick(d)
check('bars flip does not rearrange already-open windows', d.layoutConfig[ge.x] == beforeClassic,
    tostring(d.layoutConfig[ge.x]))

print(string.format('\n%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
