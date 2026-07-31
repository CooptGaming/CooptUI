-- Render-path test for the bars: views/dock_top.lua and views/dock_bottom.lua, driven through
-- the recording ImGui stub in scripts/tests/imgui_stub.lua.
--
-- The stub is not a layout engine, so nothing here asserts pixels. What it does prove:
--
--   1. ImGui stack balance per frame, in every state (including a segment that throws).
--      A leaked style var per frame is unbounded growth ending in an ImGui assert; this is a
--      count, not a regex over the source.
--   2. What the bars actually DRAW -- so the loot slot saying "corpse 4/9 . 7 taken" is
--      asserted rather than inferred from the fields behind it.
--   3. No TLO access from the render path. mq.TLO is a trap that records any touch, which
--      turns the project's central rule into a test instead of a review checklist.
--   4. Classic mode draws nothing at all.
--   5. The popover/menu open-hover-pin-Esc logic, including that Esc stakes its claim on
--      dockEscConsumed (the hub clears escConsumedThisFrame after the bars run, so writing
--      that directly is a no-op and would close a companion window off the same keypress).

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

local dockTop    = require('itemui.views.dock_top')
local dockBottom = require('itemui.views.dock_bottom')
local dockState  = require('itemui.services.dock_state')
local chatFeed   = require('itemui.services.chat_feed')
local T          = require('itemui.constants').TIMING
local registry   = require('itemui.core.registry')

-- The launcher menus are registry-driven, and the real registrations live in the view modules
-- (bank.lua etc.) which this test does not load. Register the ids the menus reference so the
-- menu contents are actually exercised; without this every entry is correctly skipped and the
-- menu tests would pass on an empty list.
registry.init({ layoutConfig = {}, companionWindowOpenedAt = {} })
for _, m in ipairs({
    { id = 'bank',           label = 'Bank' },
    { id = 'itemDisplay',    label = 'Item Display' },
    { id = 'augments',       label = 'Augments' },
    { id = 'augmentUtility', label = 'Augment Utility' },
    { id = 'mythicals',      label = 'Mythics' },
    { id = 'reroll',         label = 'Reroll' },
    { id = 'equipment',      label = 'Equipment' },
    { id = 'effects',        label = 'Effects' },
    { id = 'favorites',      label = 'Clickies' },
    { id = 'aa',             label = 'AA' },
    { id = 'commandCenter',  label = 'Cmd' },
    { id = 'config',         label = 'Settings' },
    { id = 'chat',           label = 'Chat' },
}) do
    registry.register({ id = m.id, label = m.label, render = function() end })
end

-- ---------------------------------------------------------------- fixtures
local function newCtx(opts)
    opts = opts or {}
    local layoutConfig = {
        UIMode = opts.mode or 'bars',
        DockTop = opts.top ~= false,
        DockBottom = opts.bottom ~= false,
        DockPosition = opts.position or 'top',
        DockChat = opts.chat or 'collapsed',
        DockSegments = opts.segments or 'status,bags,sell,loot,buffs,xp,session',
    }
    local uiState = opts.uiState or {}
    -- This suite runs pluginless, so the real health probe eventually raises the 14d
    -- strip and would skew every window-count assertion below. Default-dismiss all four
    -- conditions; the strip block re-enables them explicitly.
    if uiState.dockStripDismissed == nil then
        uiState.dockStripDismissed = {
            no_plugin = true, no_rules = true, stale_bank = true, sellmac_missing = true,
        }
    end
    return {
        layoutConfig = layoutConfig,
        uiState = uiState,
        scheduleLayoutSave = function() end,
    }
end

local function newDeps(ctx, opts)
    opts = opts or {}
    return {
        layoutConfig = ctx.layoutConfig,
        uiState = ctx.uiState,
        sellItems = opts.sellItems or {},
        inventoryItems = opts.inventoryItems or { {}, {} },
        lootMacState = { lastRunning = opts.lootRunning or false },
        sellMacState = { lastRunning = false },
        getLastMerchantState = function() return opts.merchantOpen == true end,
        itemOps = { countFreeInvSlots = function() return opts.freeSlots or 40 end },
    }
end

--- Aggregate until the slow walks have run, so the render has real data to draw.
local function warmState()
    for _ = 1, 5 do
        dockTop.render(newCtx())            -- raises demand for the enabled segments
        stub.advance(T.DOCK_SLOW_BAGS_MS + 1)
        dockState.tick(stub.now)
    end
    return stub.now
end

local function resetInput()
    stub.hover, stub.click, stub.keys, stub.mouse = {}, {}, {}, {}
    stub.windowHovered = false
    -- Advance well past the popover/menu mouse-out grace so no stray window survives from the
    -- previous block. dock_top and dock_bottom keep hover state in module locals keyed on
    -- mq.gettime(), so a frozen clock would leave whatever was last hovered open forever.
    stub.advance(T.DOCK_POPOVER_GRACE_MS * 4)
end

-- =================================================================
-- 1. Classic mode draws nothing
-- =================================================================
do
    resetInput()
    local ctx = newCtx({ mode = 'classic' })
    dockState.init(newDeps(ctx))
    local r = stub.frame(function()
        dockTop.render(ctx)
        dockBottom.render(ctx)
    end)
    check('classic: no windows opened', #r.windows == 0, #r.windows)
    check('classic: nothing drawn', #r.text == 0 and #r.buttons == 0,
        #r.text .. ' text / ' .. #r.buttons .. ' widgets')
    check('classic: stacks balanced', stub.balanced(r), stub.imbalance(r))
end

-- =================================================================
-- 2. Looting state: what the slot actually says, and stack balance
-- =================================================================
do
    resetInput()
    local uiState = {
        lootRunCorpsesLooted = 4,
        lootRunTotalCorpses  = 9,
        lootRunCurrentCorpse = 'a decaying skeleton',
        lootRunLootedItems   = { {}, {}, {}, {}, {}, {}, {} },
        lootRunTotalValue    = 1208000,
    }
    local ctx = newCtx({ uiState = uiState })
    dockState.init(newDeps(ctx, { lootRunning = true, inventoryItems = { {}, {} } }))
    local now = warmState(100000)

    local r = stub.frame(function() dockTop.render(ctx) end)
    check('looting: drew the corpse counter', stub.drew(r, 'corpse'), table.concat(r.text, '|'))
    check('looting: counter is 4/9 (not 0/9)', stub.drew(r, '4/9'), table.concat(r.text, '|'))
    check('looting: item count is 7 (not 0)', stub.drew(r, '7 taken'), table.concat(r.text, '|'))
    check('looting: offers Stop', stub.drew(r, 'Stop'), table.concat(r.buttons, '|'))
    check('looting: stacks balanced', stub.balanced(r), stub.imbalance(r))

    -- THE central rule: nothing in the render path may touch a TLO.
    check('looting: zero TLO access from the render path', #r.tloAccess == 0,
        table.concat(r.tloAccess, ','))
    check('looting: zero game commands from the render path', #r.commands == 0,
        table.concat(r.commands, ','))
    _ = now
end

-- =================================================================
-- 3. Every loot state keeps the stacks balanced
-- =================================================================
do
    local states = {
        { name = 'idle',     uiState = {} },
        { name = 'decision', uiState = { lootMythicalAlert = { itemName = 'Mythical Faceplate of Blinding Fury', decision = 'pending' },
                                         lootMythicalDecisionStartAt = os.time() - 8 } },
        { name = 'done',     uiState = { lootRunFinished = true, lootRunTotalCorpses = 9,
                                         lootRunTotalValue = 1208000, lootRunSkipped = 3 } },
        { name = 'problem',  uiState = { lootRunLootedItems = {} }, freeSlots = 0, lootRunning = true },
    }
    for _, st in ipairs(states) do
        resetInput()
        local ctx = newCtx({ uiState = st.uiState })
        dockState.init(newDeps(ctx, { lootRunning = st.lootRunning,
            freeSlots = st.freeSlots or 40, inventoryItems = { {}, {}, {} } }))
        warmState(200000)
        local r = stub.frame(function() dockTop.render(ctx) end)
        check('loot state ' .. st.name .. ': balanced', stub.balanced(r), stub.imbalance(r))
        check('loot state ' .. st.name .. ': no TLO in render', #r.tloAccess == 0,
            table.concat(r.tloAccess, ','))
    end
    -- The decision state's two verbs must be on the bar, not only in the Loot window.
    resetInput()
    local ctx = newCtx({ uiState = { lootMythicalAlert = { itemName = 'Mythical Faceplate', decision = 'pending' },
                                     lootMythicalDecisionStartAt = os.time() - 8 } })
    dockState.init(newDeps(ctx, { lootRunning = true }))
    warmState(300000)
    local r = stub.frame(function() dockTop.render(ctx) end)
    check('decision: Take and Pass are on the bar',
        stub.drew(r, 'Take##dockLootTake') and stub.drew(r, 'Pass##dockLootPass'), table.concat(r.buttons, '|'))
    check('decision: no phantom F1/F2 key hints on the labels',
        not stub.drew(r, 'Take F1') and not stub.drew(r, 'Pass F2'), table.concat(r.buttons, '|'))
    -- Reroll is the third verb: Take AND queue the taken item for the mythical reroll list.
    check('decision: Reroll is on the bar', stub.drew(r, 'Reroll##dockLootReroll'),
        table.concat(r.buttons, '|'))
    -- No TLO from this frame -- the name was never hovered, so the tooltip's hover-gated
    -- getItemStatsForTooltip lookup must not have fired.
    check('decision: still zero TLO with the Reroll button present', #r.tloAccess == 0,
        table.concat(r.tloAccess, ','))

    -- Clicking Reroll enqueues the deferred action (main_loop phase0b drains it into a
    -- mythicalTake call + a name-latch), never a direct command from the render path.
    stub.click = { ['Reroll##dockLootReroll'] = true }
    stub.frame(function() dockTop.render(ctx) end)
    local q = ctx.uiState.dockActionQueue
    check('decision: Reroll enqueues loot_take_reroll',
        q and #q >= 1 and q[#q].kind == 'loot_take_reroll',
        q and q[#q] and tostring(q[#q].kind) or 'nil')
end

-- Degraded strip (phase 6, mockup 14d): drawn under the bar, dismissible, balanced.
do
    resetInput()
    local ctx = newCtx()
    ctx.uiState.dockStripDismissed = {}    -- re-enable: this block is ABOUT the strip
    dockState.get().degraded = { id = 'no_plugin' }
    local r = stub.frame(function() dockTop.render(ctx) end)
    check('strip: pluginless message drawn', stub.drew(r, 'running without the plugin'), table.concat(r.text, '|'))
    check('strip: dismiss button offered', stub.drew(r, 'Hide for this session'), table.concat(r.buttons, '|'))
    check('strip: balanced', stub.balanced(r), stub.imbalance(r))

    stub.click['Hide for this session'] = true
    r = stub.frame(function() dockTop.render(ctx) end)
    check('strip: hide click dismisses for the session', ctx.uiState.dockStripDismissed
        and ctx.uiState.dockStripDismissed.no_plugin == true)
    stub.click = {}
    r = stub.frame(function() dockTop.render(ctx) end)
    check('strip: dismissed strip stays gone', not stub.drew(r, 'running without the plugin'),
        table.concat(r.text, '|'))
    check('strip: balanced after dismissal', stub.balanced(r), stub.imbalance(r))

    dockState.get().degraded = { id = 'stale_bank', days = 3 }
    r = stub.frame(function() dockTop.render(ctx) end)
    check('strip: a different condition still shows', stub.drew(r, 'snapshot taken 3 days ago'),
        table.concat(r.text, '|'))
    dockState.get().degraded = nil
end

-- =================================================================
-- 3b. EVERY default segment renders. This is the regression net for the whole class of bug
--     where the loop dies part-way and a pcall eats the evidence -- GetItemRectMin's
--     two-number return did exactly that: ONE segment drew, six vanished, log stayed empty.
-- =================================================================
do
    resetInput()
    local ctx = newCtx()
    dockState.init(newDeps(ctx))
    warmState()
    local r = stub.frame(function() dockTop.render(ctx) end)
    for _, want in ipairs({
        { seg = 'status',  needle = 'CoOpt' },
        { seg = 'bags',    needle = 'bags' },
        { seg = 'sell',    needle = 'sell' },
        { seg = 'loot',    needle = 'loot' },
        { seg = 'buffs',   needle = 'buffs' },
        { seg = 'xp',      needle = 'XP' },
        { seg = 'session', needle = 'session' },
    }) do
        check('full bar: ' .. want.seg .. ' segment rendered', stub.drew(r, want.needle),
            table.concat(r.text, '|'))
    end
    check('full bar: all seven slots captured for popover anchoring',
        (function() local n = 0; for _ in pairs(dockTop.slots) do n = n + 1 end; return n == 7 end)(),
        'slots missing')
    check('full bar: no dock errors surfaced',
        not (ctx.uiState.dockErrors and #ctx.uiState.dockErrors > 0),
        ctx.uiState.dockErrors and table.concat(ctx.uiState.dockErrors, ' / '))
    check('full bar: balanced', stub.balanced(r), stub.imbalance(r))
end

-- =================================================================
-- 3c. Top-bar restyle: Loot All (idle-only) and Auto Sell (merchant-gated click, always drawn)
-- =================================================================
do
    -- Idle loot state offers Loot All and enqueues loot_all on click.
    resetInput()
    local uiState = {}
    local ctx = newCtx({ uiState = uiState })
    dockState.init(newDeps(ctx))
    warmState(1300000)
    local r = stub.frame(function() dockTop.render(ctx) end)
    check('loot idle: offers Loot All', stub.drew(r, 'Loot All##dockLootAll'),
        table.concat(r.buttons, '|'))
    check('loot idle: still balanced with the button drawn', stub.balanced(r), stub.imbalance(r))

    stub.click = { ['Loot All##dockLootAll'] = true }
    stub.frame(function() dockTop.render(ctx) end)
    local q = uiState.dockActionQueue
    check('loot idle: Loot All enqueues loot_all',
        q and #q >= 1 and q[#q].kind == 'loot_all',
        q and q[#q] and tostring(q[#q].kind) or 'nil')

    -- The looting (running) state must NOT offer Loot All -- the button belongs to idle only;
    -- Stop is still the only verb mid-run.
    resetInput()
    local uiState2 = {}
    local ctx2 = newCtx({ uiState = uiState2 })
    dockState.init(newDeps(ctx2, { lootRunning = true, inventoryItems = { {}, {} } }))
    warmState(1310000)
    local r2 = stub.frame(function() dockTop.render(ctx2) end)
    check('looting: Loot All is not offered mid-run', not stub.drew(r2, 'Loot All##dockLootAll'),
        table.concat(r2.buttons, '|'))
    check('looting: Stop is still offered (unchanged)', stub.drew(r2, 'Stop##dockLootStop'),
        table.concat(r2.buttons, '|'))
end

do
    -- Auto Sell offers with a merchant open and enqueues auto_sell.
    resetInput()
    local uiState = {}
    local ctx = newCtx({ uiState = uiState })
    dockState.init(newDeps(ctx, { merchantOpen = true }))
    warmState(1320000)
    local r = stub.frame(function() dockTop.render(ctx) end)
    check('sell: offers Auto Sell with a merchant open', stub.drew(r, 'Auto Sell##dockSellAuto'),
        table.concat(r.buttons, '|'))
    check('sell: still balanced with a merchant open', stub.balanced(r), stub.imbalance(r))

    stub.click = { ['Auto Sell##dockSellAuto'] = true }
    stub.frame(function() dockTop.render(ctx) end)
    local q = uiState.dockActionQueue
    check('sell: Auto Sell enqueues auto_sell',
        q and #q >= 1 and q[#q].kind == 'auto_sell',
        q and q[#q] and tostring(q[#q].kind) or 'nil')

    -- No merchant: the button still draws (grey/disabled-styled per theme.PushKeepButton), but
    -- a click enqueues nothing.
    resetInput()
    local uiState2 = {}
    local ctx2 = newCtx({ uiState = uiState2 })
    dockState.init(newDeps(ctx2, { merchantOpen = false }))
    warmState(1330000)
    local r2 = stub.frame(function() dockTop.render(ctx2) end)
    check('sell: Auto Sell still draws without a merchant', stub.drew(r2, 'Auto Sell##dockSellAuto'),
        table.concat(r2.buttons, '|'))
    check('sell: balanced without a merchant', stub.balanced(r2), stub.imbalance(r2))

    stub.click = { ['Auto Sell##dockSellAuto'] = true }
    local r3 = stub.frame(function() dockTop.render(ctx2) end)
    check('sell: Auto Sell click enqueues nothing without a merchant',
        uiState2.dockActionQueue == nil or #uiState2.dockActionQueue == 0,
        uiState2.dockActionQueue and #uiState2.dockActionQueue)
    check('sell: still balanced after the inert click', stub.balanced(r3), stub.imbalance(r3))
end

-- =================================================================
-- 4. A segment that throws must not unbalance the frame, must not take the other segments
--    with it, and must SURFACE the error (a bare pcall here once hid a per-frame crash).
--    (app.lua's outer pcall sits outside the PushStyleVar calls, so containment has to be
--     inside dock_top -- this is that containment, verified rather than assumed.)
-- =================================================================
do
    resetInput()
    local ctx = newCtx()
    dockState.init(newDeps(ctx))
    warmState(400000)
    -- Poison one segment's data so its draw genuinely throws: buffCount is fed straight to
    -- tostring, and this metatable makes tostring raise. (sessionPlat, the old victim here,
    -- is laundered through tonumber-or-0 and never actually threw -- that test was green
    -- without testing anything.)
    local snap = dockState.get()
    local saved = snap.buffCount
    snap.buffCount = setmetatable({}, { __tostring = function() error('boom') end })
    local r = stub.frame(function() dockTop.render(ctx) end)
    snap.buffCount = saved
    check('a throwing segment still leaves the frame balanced', stub.balanced(r), stub.imbalance(r))
    check('a throwing segment does not abort the whole bar', r.ok == true, tostring(r.err))
    check('the other segments still draw around the bad one',
        stub.drew(r, 'CoOpt') and stub.drew(r, 'XP'), table.concat(r.text, '|'))
    local errs = ctx.uiState.dockErrors
    check('the swallowed error is surfaced for main_loop to print',
        errs ~= nil and #errs >= 1 and tostring(errs[1]):find('boom', 1, true) ~= nil,
        errs and table.concat(errs, ' / ') or 'nil')
end

-- =================================================================
-- 5. Popover: hover opens it, and it is a SECOND window
-- =================================================================
do
    resetInput()
    local ctx = newCtx({ segments = 'buffs' })
    dockState.init(newDeps(ctx))
    warmState(500000)

    -- Frame 1: nothing hovered -> one window (the bar itself).
    stub.advance(T.DOCK_POPOVER_GRACE_MS * 4)
    local r1 = stub.frame(function() dockTop.render(ctx) end)
    check('popover: closed when nothing is hovered', #r1.windows == 1, #r1.windows)

    -- Frame 2: hover the buffs slot. The slot child is named dockseg_buffs.
    stub.hover = { dockseg_buffs = true }
    local r2 = stub.frame(function() dockTop.render(ctx) end)
    check('popover: hover opens a second window', #r2.windows == 2,
        table.concat(r2.windows, ','))
    check('popover: it is the popover window',
        r2.windows[2] == '##CoOptDockPopover', tostring(r2.windows[2]))
    check('popover: balanced with the popover open', stub.balanced(r2), stub.imbalance(r2))
    check('popover: no TLO from inside the popover', #r2.tloAccess == 0,
        table.concat(r2.tloAccess, ','))
    check('popover: drew the expiring header', stub.drew(r2, 'Expiring soon'),
        table.concat(r2.text, '|'))

    -- Bug: the popover showed NOTHING below "Expiring soon" when nothing was under five
    -- minutes, even though snap.buffs was fully populated. The stub never stubs
    -- DrawTextureAnimation/FindTextureAnimation, so the icon grid is unreachable here and the
    -- comma-joined name fallback is what must actually render.
    local snap = dockState.get()
    local savedBuffs, savedSongs, savedAuras = snap.buffs, snap.songs, snap.auras
    local savedExpiring, savedExpiringCount = snap.expiring, snap.expiringCount
    snap.buffs = { { name = 'Spirit of Wolf', permanent = true, icon = 999 },
                   { name = 'Skin like Diamond', permanent = true, icon = 998 } }
    snap.songs = { { name = 'Hymn of the Last Stand', permanent = false, seconds = 900 } }
    snap.auras = { { name = 'Aura of the Muse', permanent = true } }
    snap.expiring, snap.expiringCount = {}, 0
    local r3 = stub.frame(function() dockTop.render(ctx) end)
    check('popover: nothing expiring still lists the buff names (fallback path)',
        stub.drew(r3, 'Spirit of Wolf') and stub.drew(r3, 'Skin like Diamond'),
        table.concat(r3.text, '|'))
    check('popover: songs line drawn', stub.drew(r3, 'Hymn of the Last Stand'),
        table.concat(r3.text, '|'))
    check('popover: aura line drawn', stub.drew(r3, 'Aura of the Muse'),
        table.concat(r3.text, '|'))
    check('popover: still says nothing under five minutes',
        stub.drew(r3, 'Nothing under five minutes'), table.concat(r3.text, '|'))
    check('popover: balanced with a populated, non-expiring buff/song/aura list',
        stub.balanced(r3), stub.imbalance(r3))
    check('popover: still no TLO from inside the popover', #r3.tloAccess == 0,
        table.concat(r3.tloAccess, ','))
    snap.buffs, snap.songs, snap.auras = savedBuffs, savedSongs, savedAuras
    snap.expiring, snap.expiringCount = savedExpiring, savedExpiringCount
end

-- =================================================================
-- 6. Popover suppression during a mythical decision
-- =================================================================
do
    resetInput()
    local ctx = newCtx({ segments = 'buffs,loot',
        uiState = { lootMythicalAlert = { itemName = 'Mythical Faceplate', decision = 'pending' },
                    lootMythicalDecisionStartAt = os.time() } })
    dockState.init(newDeps(ctx, { lootRunning = true }))
    warmState(600000)
    stub.hover = { dockseg_buffs = true }
    local r = stub.frame(function() dockTop.render(ctx) end)
    check('no popover opens while a mythical decision is on screen', #r.windows == 1,
        table.concat(r.windows, ','))
end

-- =================================================================
-- 7. Esc on a pinned popover claims dockEscConsumed, NOT escConsumedThisFrame
-- =================================================================
do
    resetInput()
    local uiState = { dockPinnedPopover = 'buffs' }
    local ctx = newCtx({ segments = 'buffs', uiState = uiState })
    dockState.init(newDeps(ctx))
    warmState(700000)

    stub.keys = { [ImGuiKey.Escape] = true }
    local r = stub.frame(function() dockTop.render(ctx) end)
    check('Esc unpins the popover', uiState.dockPinnedPopover == nil,
        tostring(uiState.dockPinnedPopover))
    check('Esc claims dockEscConsumed', uiState.dockEscConsumed == true,
        tostring(uiState.dockEscConsumed))
    -- Writing escConsumedThisFrame here would be erased by main_window's own reset, which runs
    -- after the bars -- so the bars must NOT rely on it.
    check('Esc does not write the flag the hub is about to clear',
        uiState.escConsumedThisFrame == nil, tostring(uiState.escConsumedThisFrame))
    check('Esc frame balanced', stub.balanced(r), stub.imbalance(r))
end

-- =================================================================
-- 8. Middle-click pins a popover
-- =================================================================
do
    resetInput()
    local uiState = {}
    local ctx = newCtx({ segments = 'buffs', uiState = uiState })
    dockState.init(newDeps(ctx))
    warmState(800000)
    stub.hover = { dockseg_buffs = true }
    stub.mouse = { [ImGuiMouseButton.Middle] = true }
    stub.frame(function() dockTop.render(ctx) end)
    check('middle-click pins the popover', uiState.dockPinnedPopover == 'buffs',
        tostring(uiState.dockPinnedPopover))
end

-- =================================================================
-- 9. Bottom bar: menus, chat, and the toggle action
-- =================================================================
do
    resetInput()
    local uiState = {}
    local ctx = newCtx({ uiState = uiState, position = 'top' })
    dockState.init(newDeps(ctx))
    warmState(900000)

    local r = stub.frame(function() dockBottom.render(ctx) end)
    check('bottom: three menu buttons (23c: Items/Character/Layouts folded into Hub)',
        stub.drew(r, 'Hub') and stub.drew(r, 'Actions') and stub.drew(r, 'Game windows')
        and not stub.drew(r, '##dockmenubtn_items') and not stub.drew(r, '##dockmenubtn_character'),
        table.concat(r.buttons, '|'))
    check('bottom: Settings is present', stub.drew(r, 'Settings'), table.concat(r.buttons, '|'))
    check('bottom: balanced', stub.balanced(r), stub.imbalance(r))
    check('bottom: no TLO from the render path', #r.tloAccess == 0, table.concat(r.tloAccess, ','))
    check('bottom: no commands from the render path', #r.commands == 0, table.concat(r.commands, ','))

    -- Hovering the Hub button opens the grouped launcher list as a second window.
    stub.hover = { dockmenubtn_hub = true }
    local r2 = stub.frame(function() dockBottom.render(ctx) end)
    check('bottom: hover opens the menu', #r2.windows == 2, table.concat(r2.windows, ','))
    check('bottom: hub lists the merged Inventory', stub.drew(r2, 'Inventory (bags + bank)'),
        table.concat(r2.buttons, '|'))
    check('bottom: hub lists the Item Display + Aug Utility pair',
        stub.drew(r2, 'Item Display + Augment Utility'), table.concat(r2.buttons, '|'))
    check('bottom: hub carries the group headers', stub.drew(r2, 'ITEMS')
        and stub.drew(r2, 'CHARACTER') and stub.drew(r2, 'LAYOUTS'), table.concat(r2.text, '|'))
    check('bottom: hub carries the layouts entries', stub.drew(r2, 'Re-tidy now'),
        table.concat(r2.buttons, '|'))
    check('bottom: hub does NOT list bank as its own row', not stub.drew(r2, '##dockmenu_bank'),
        table.concat(r2.buttons, '|'))
    check('bottom: balanced with the menu open', stub.balanced(r2), stub.imbalance(r2))

    -- Clicking a menu entry enqueues rather than acting inline, and asks for a TOGGLE.
    stub.hover = { dockmenubtn_hub = true }
    stub.click = { dockmenu_mythicals = true }
    stub.frame(function() dockBottom.render(ctx) end)
    local q = uiState.dockActionQueue
    check('bottom: a menu click enqueues instead of acting inline', q and #q >= 1, q and #q)
    local a = q and q[#q]
    check('bottom: the action is a window toggle',
        a and a.kind == 'window' and a.id == 'mythicals' and a.toggle == true,
        a and (a.kind .. '/' .. tostring(a.id) .. '/toggle=' .. tostring(a.toggle)))

    -- Clicking the pair row opens BOTH halves (non-toggle idempotent opens).
    resetInput()
    stub.hover = { dockmenubtn_hub = true }
    stub.click = { dockmenu_pair_idau = true }
    uiState.dockActionQueue = nil
    stub.frame(function() dockBottom.render(ctx) end)
    q = uiState.dockActionQueue
    check('bottom: pair row queues both halves', q and #q == 2
        and q[1].kind == 'window' and q[1].id == 'itemDisplay' and not q[1].toggle
        and q[2].kind == 'window' and q[2].id == 'augmentUtility' and not q[2].toggle,
        q and #q)

    -- With the pair open, the same row closes both (toggle only the open halves).
    resetInput()
    if not registry.isOpen('itemDisplay') then registry.toggleWindow('itemDisplay') end
    if not registry.isOpen('augmentUtility') then registry.toggleWindow('augmentUtility') end
    stub.hover = { dockmenubtn_hub = true }
    stub.click = { dockmenu_pair_idau = true }
    uiState.dockActionQueue = nil
    stub.frame(function() dockBottom.render(ctx) end)
    q = uiState.dockActionQueue
    check('bottom: open pair row queues both closes', q and #q == 2
        and q[1].id == 'itemDisplay' and q[1].toggle == true
        and q[2].id == 'augmentUtility' and q[2].toggle == true, q and #q)
    if registry.isOpen('itemDisplay') then registry.toggleWindow('itemDisplay') end
    if registry.isOpen('augmentUtility') then registry.toggleWindow('augmentUtility') end

    -- A LIT entry (window already open) must NOT queue anything without a click. Selectable
    -- returns (selected, pressed) in this binding -- selected FIRST -- so a lit entry's first
    -- return is true EVERY frame; reading it as "clicked" slammed the window shut the moment
    -- its menu opened. The stub models the tuple, so this would regress loudly now.
    resetInput()
    if not registry.isOpen('mythicals') then registry.toggleWindow('mythicals') end
    stub.hover = { dockmenubtn_hub = true }
    uiState.dockActionQueue = nil
    stub.frame(function() dockBottom.render(ctx) end)
    check('bottom: a lit entry does not self-close without a click',
        uiState.dockActionQueue == nil or #uiState.dockActionQueue == 0,
        uiState.dockActionQueue and #uiState.dockActionQueue)
    if registry.isOpen('mythicals') then registry.toggleWindow('mythicals') end
end

-- =================================================================
-- 10. Chat: hidden/collapsed stay balanced; clicking the line opens the window via the queue
-- =================================================================
-- Peek (the old five-row tab-plus-lines mode) is retired: the strip is a launcher only now
-- (hidden, or one collapsed line), and everything else lives in the chat window
-- (views/chat_window.lua), opened through the same action queue every bar control uses.
do
    for _, mode in ipairs({ 'hidden', 'collapsed' }) do
        resetInput()
        local ctx = newCtx({ chat = mode })
        dockState.init(newDeps(ctx))
        warmState(1000000)
        local r = stub.frame(function() dockBottom.render(ctx) end)
        check('chat ' .. mode .. ': balanced', stub.balanced(r), stub.imbalance(r))
        check('chat ' .. mode .. ': no TLO from the render path', #r.tloAccess == 0, table.concat(r.tloAccess, ','))
    end

    -- A legacy "peek" value (a session's INI predates this retirement) must not crash and
    -- must not resurrect the old tab row -- it reads as collapsed at the point dock_bottom
    -- consumes DockChat.
    resetInput()
    local peekCtx = newCtx({ chat = 'peek' })
    dockState.init(newDeps(peekCtx))
    warmState(1000000)
    local rPeek = stub.frame(function() dockBottom.render(peekCtx) end)
    check('chat: legacy "peek" stays balanced', stub.balanced(rPeek), stub.imbalance(rPeek))
    check('chat: legacy "peek" does not draw the retired tab row',
        not stub.drew(rPeek, '##dockTab'), table.concat(rPeek.buttons, '|'))

    -- With lines in the buffer, collapsed shows the newest.
    resetInput()
    chatFeed.init({})
    local ctx = newCtx({ chat = 'collapsed' })
    dockState.init(newDeps(ctx))
    warmState(1100000)
    check('chat feed starts empty', chatFeed.count() == 0, chatFeed.count())

    -- Clicking the collapsed line (hover + left-click on its child) enqueues opening the chat
    -- window, exactly like a menu entry -- never a direct registry write from the render path.
    resetInput()
    local uiState = {}
    local clickCtx = newCtx({ uiState = uiState, chat = 'collapsed' })
    dockState.init(newDeps(clickCtx))
    warmState(1200000)
    stub.hover = { dockChatCollapsed = true }
    stub.mouse = { [ImGuiMouseButton.Left] = true }
    stub.frame(function() dockBottom.render(clickCtx) end)
    local q = uiState.dockActionQueue
    check('chat: clicking the line enqueues an action', q and #q >= 1, q and #q)
    local a = q and q[#q]
    check('chat: the action opens the chat window via the queue',
        a and a.kind == 'window' and a.id == 'chat' and a.toggle == true,
        a and (a.kind .. '/' .. tostring(a.id) .. '/toggle=' .. tostring(a.toggle)))
end

-- =================================================================
-- 10b. Menus no longer pin on click: a click on the menu button behaves like hover (opens/
--      keeps it open, nothing more), and once the mouse leaves both the button and the menu
--      it closes DOCK_POPOVER_GRACE_MS later -- there is no pinned state left to fight that.
-- =================================================================
do
    resetInput()
    local uiState = {}
    local ctx = newCtx({ uiState = uiState })
    dockState.init(newDeps(ctx))
    warmState(1250000)

    -- Hover the Hub button AND click it: still just open, same as hover alone would give.
    stub.hover = { dockmenubtn_hub = true }
    stub.mouse = { [ImGuiMouseButton.Left] = true }
    local r1 = stub.frame(function() dockBottom.render(ctx) end)
    check('menu click: opens the menu (click behaves like hover)', #r1.windows == 2,
        table.concat(r1.windows, ','))
    check('menu click: balanced', stub.balanced(r1), stub.imbalance(r1))

    -- Mouse leaves both the button and the menu window on the very next frame: still inside
    -- the grace window, so it survives one more frame rather than vanishing instantly.
    stub.hover = {}
    stub.mouse = {}
    stub.windowHovered = false
    local r2 = stub.frame(function() dockBottom.render(ctx) end)
    check('menu click: still shown just after the mouse leaves (inside the grace window)',
        #r2.windows == 2, table.concat(r2.windows, ','))

    -- Advance past the grace window: with no pin, nothing keeps it open any longer.
    stub.advance(T.DOCK_POPOVER_GRACE_MS * 4)
    local r3 = stub.frame(function() dockBottom.render(ctx) end)
    check('menu click: closes after the mouse-out grace elapses', #r3.windows == 1,
        table.concat(r3.windows, ','))
    check('menu click: balanced once closed', stub.balanced(r3), stub.imbalance(r3))

    -- Esc has nothing pinned to release anymore, and must stay harmless (dock_top's popover
    -- Esc handling is the one still allowed to claim dockEscConsumed, for the thing that can
    -- still be pinned).
    resetInput()
    stub.hover = { dockmenubtn_hub = true }
    stub.keys = { [ImGuiKey.Escape] = true }
    stub.frame(function() dockBottom.render(ctx) end)
    check('menu click: Esc no longer claims dockEscConsumed (nothing left to unpin)',
        uiState.dockEscConsumed == nil, tostring(uiState.dockEscConsumed))
end

-- =================================================================
-- 10c. Launcher-buttons style (DockBottomStyle = "buttons"): the row itself (registered test
--      modules), lit-while-open, the {kind="window", toggle=true} enqueue, the reroll
--      pending-count badge, and that "menus" stays the unaffected default.
-- =================================================================
do
    resetInput()
    local uiState = {}
    local ctx = newCtx({ uiState = uiState })
    ctx.layoutConfig.DockBottomStyle = 'buttons'
    ctx.layoutConfig.DockButtons = 'bags,bank,reroll'
    dockState.init(newDeps(ctx))
    warmState(1260000)

    local r = stub.frame(function() dockBottom.render(ctx) end)
    check('buttons: Bags|Bank pair chip drawn (23c: one chip, two halves)',
        stub.drew(r, 'Bags##dockbtn_bagsbank_1') and stub.drew(r, 'Bank##dockbtn_bagsbank_2')
        and stub.drew(r, 'Reroll##dockbtn_reroll'), table.concat(r.buttons, '|'))
    check('buttons: the bank id is absorbed into the pair (no standalone chip)',
        not stub.drew(r, 'Bank##dockbtn_bank'), table.concat(r.buttons, '|'))
    check('buttons: no hover-menu buttons in this style',
        not stub.drew(r, '##dockmenubtn_hub'), table.concat(r.buttons, '|'))
    check('buttons: Settings still present (right anchor unchanged)',
        stub.drew(r, 'Settings'), table.concat(r.buttons, '|'))
    check('buttons: balanced', stub.balanced(r), stub.imbalance(r))
    check('buttons: no TLO from the render path', #r.tloAccess == 0, table.concat(r.tloAccess, ','))
    check('buttons: no commands from the render path', #r.commands == 0, table.concat(r.commands, ','))

    -- Both halves of Bags|Bank route to the merged hub (phase 10: the hub IS Inventory).
    resetInput()
    stub.click = { dockbtn_bagsbank_2 = true }
    stub.frame(function() dockBottom.render(ctx) end)
    local q = uiState.dockActionQueue
    check('buttons: the Bank half enqueues instead of acting inline', q and #q >= 1, q and #q)
    local a = q and q[#q]
    check('buttons: the Bank half routes to the merged hub',
        a and a.kind == 'hub', a and tostring(a.kind))

    resetInput()
    stub.click = { dockbtn_bagsbank_1 = true }
    uiState.dockActionQueue = nil
    stub.frame(function() dockBottom.render(ctx) end)
    q = uiState.dockActionQueue
    check('buttons: the Bags half queues the hub too', q and #q >= 1 and q[#q].kind == 'hub',
        q and q[#q] and tostring(q[#q].kind) or 'nil')

    -- A stray open bank companion lights the whole pair chip (defensive OR), and the
    -- push/pop pairing around both halves is what the balance check proves.
    resetInput()
    if not registry.isOpen('bank') then registry.toggleWindow('bank') end
    uiState.dockActionQueue = nil
    local rLit = stub.frame(function() dockBottom.render(ctx) end)
    check('buttons: pair chip halves still draw while lit',
        stub.drew(rLit, 'Bags##dockbtn_bagsbank_1') and stub.drew(rLit, 'Bank##dockbtn_bagsbank_2'),
        table.concat(rLit.buttons, '|'))
    check('buttons: balanced with a lit pair chip', stub.balanced(rLit), stub.imbalance(rLit))
    if registry.isOpen('bank') then registry.toggleWindow('bank') end

    -- A plain companion still lights alone (push/pop pairing on the single-chip path).
    resetInput()
    if not registry.isOpen('reroll') then registry.toggleWindow('reroll') end
    local rLit2 = stub.frame(function() dockBottom.render(ctx) end)
    check('buttons: an open (lit) standalone chip still draws', stub.drew(rLit2, 'Reroll##dockbtn_reroll'),
        table.concat(rLit2.buttons, '|'))
    check('buttons: balanced with a lit standalone chip', stub.balanced(rLit2), stub.imbalance(rLit2))
    if registry.isOpen('reroll') then registry.toggleWindow('reroll') end

    -- The Item Display|Aug Utility pair: both ids in the CSV collapse into one chip at the
    -- first id's slot, halves toggling their own windows.
    resetInput()
    local pairCtx = newCtx({})
    pairCtx.layoutConfig.DockBottomStyle = 'buttons'
    pairCtx.layoutConfig.DockButtons = 'itemDisplay,augmentUtility,reroll'
    dockState.init(newDeps(pairCtx))
    warmState(1265000)
    local rPair = stub.frame(function() dockBottom.render(pairCtx) end)
    check('buttons: ID|AU pair chip drawn, second id absorbed',
        stub.drew(rPair, 'Item Display##dockbtn_idau_1') and stub.drew(rPair, 'Augment Utility##dockbtn_idau_2')
        and not stub.drew(rPair, '##dockbtn_itemDisplay') and not stub.drew(rPair, '##dockbtn_augmentUtility'),
        table.concat(rPair.buttons, '|'))
    local pairUi = pairCtx.uiState
    stub.click = { dockbtn_idau_2 = true }
    stub.frame(function() dockBottom.render(pairCtx) end)
    local qp = pairUi.dockActionQueue
    check('buttons: the AU half toggles its own window',
        qp and #qp >= 1 and qp[#qp].kind == 'window' and qp[#qp].id == 'augmentUtility'
        and qp[#qp].toggle == true, qp and #qp)

    -- Reroll's pending count comes from getPendingAugList/getPendingMythicalList (not
    -- getState(), which holds in-flight add/sync bookkeeping, not the pending lists).
    resetInput()
    local badgeCtx = newCtx({})
    badgeCtx.layoutConfig.DockBottomStyle = 'buttons'
    badgeCtx.layoutConfig.DockButtons = 'reroll'
    badgeCtx.rerollService = {
        getPendingAugList = function() return { { id = 1 }, { id = 2 } } end,
        getPendingMythicalList = function() return { { id = 3 } } end,
    }
    dockState.init(newDeps(badgeCtx))
    warmState(1270000)
    local rBadge = stub.frame(function() dockBottom.render(badgeCtx) end)
    check('buttons: reroll shows a pending-count badge (2 aug + 1 mythical)',
        stub.drew(rBadge, 'Reroll 3##dockbtn_reroll'), table.concat(rBadge.buttons, '|'))
    check('buttons: badge frame balanced', stub.balanced(rBadge), stub.imbalance(rBadge))

    resetInput()
    badgeCtx.rerollService.getPendingAugList = function() return {} end
    badgeCtx.rerollService.getPendingMythicalList = function() return {} end
    local rNoBadge = stub.frame(function() dockBottom.render(badgeCtx) end)
    check('buttons: no pending entries -> plain label, no badge',
        stub.drew(rNoBadge, 'Reroll##dockbtn_reroll') and not stub.drew(rNoBadge, 'Reroll 3##dockbtn_reroll'),
        table.concat(rNoBadge.buttons, '|'))

    -- "menus" (explicit, and the unset default) draws the hover menus exactly as before --
    -- unaffected by the buttons-style code path.
    resetInput()
    local menusCtx = newCtx({})
    menusCtx.layoutConfig.DockBottomStyle = 'menus'
    dockState.init(newDeps(menusCtx))
    warmState(1280000)
    local rMenus = stub.frame(function() dockBottom.render(menusCtx) end)
    check('menus (explicit): the three menu buttons still drawn', stub.drew(rMenus, 'Hub')
        and stub.drew(rMenus, 'Actions')
        and stub.drew(rMenus, 'Game windows'), table.concat(rMenus.buttons, '|'))
    check('menus (explicit): no launcher buttons drawn', not stub.drew(rMenus, '##dockbtn_'),
        table.concat(rMenus.buttons, '|'))
    check('menus (explicit): balanced', stub.balanced(rMenus), stub.imbalance(rMenus))
end

-- =================================================================
-- 11. Both bars in one frame, both edges, nothing overlaps into an imbalance
-- =================================================================
do
    for _, pos in ipairs({ 'top', 'bottom' }) do
        resetInput()
        local ctx = newCtx({ position = pos })
        dockState.init(newDeps(ctx))
        warmState(1200000)
        local r = stub.frame(function()
            dockTop.render(ctx)
            dockBottom.render(ctx)
        end)
        check('both bars, status on ' .. pos .. ': balanced', stub.balanced(r), stub.imbalance(r))
        check('both bars, status on ' .. pos .. ': two strips drawn', #r.windows == 2,
            table.concat(r.windows, ','))
    end
end

-- =================================================================
-- 12. Nothing may escape between Begin and End
--
--     This is the failure the first in-game run actually hit: something threw inside the bar
--     body, app.lua's pcall (which sits OUTSIDE the Begin) swallowed it, End() never ran, and
--     ImGui reported "Missing End()" with no Lua error to go on. The original stub could not
--     see it because nothing in it ever threw and BeginChild always claimed success.
-- =================================================================
do
    -- Deliberately excludes End, EndChild, EndGroup and the Pop* calls: those ARE the
    -- balancing primitives, so "what if the thing that closes the stack fails" has no
    -- recoverable answer and asserting on it would only encode an impossible requirement.
    -- Everything a segment or the bar body can realistically reach IS covered.
    local victims = { 'CalcTextSize', 'SameLine', 'BeginChild', 'GetItemRectMin',
                      'AlignTextToFramePadding', 'SmallButton', 'Selectable', 'BeginGroup',
                      'Text', 'TextColored', 'TextUnformatted', 'Begin', 'IsItemHovered' }
    for _, victim in ipairs(victims) do
        resetInput()
        local ctx = newCtx()
        dockState.init(newDeps(ctx))
        warmState()
        stub.throwOn = { [victim] = true }
        local r = stub.frame(function()
            dockTop.render(ctx)
            dockBottom.render(ctx)
        end)
        stub.throwOn = {}
        -- The frame may draw nothing useful, but the window stack MUST come back to zero or
        -- the overlay dies.
        check('throw in ImGui.' .. victim .. ': window stack still balanced',
            r.depth.win == 0 and r.depth.child == 0 and r.depth.group == 0,
            stub.imbalance(r))
        -- Style-colour balance is asserted for everything EXCEPT Text. theme's text helpers
        -- are Push -> ImGui.Text -> Pop (coopui/utils/theme.lua:71-132), so a Text that raises
        -- strands the colour -- in shared code every view in the product depends on, not in
        -- the bars. The realistic trigger for that is a '%' in game-supplied text, and the
        -- bars now route every such string through safeText (dock_top.lua:91). Injecting a
        -- throw into EVERY Text call is strictly harsher than anything reachable.
        local styleOk = (r.depth.sv == 0) and (victim == 'Text' or r.depth.sc == 0)
        check('throw in ImGui.' .. victim .. ': style stacks still balanced',
            styleOk, stub.imbalance(r))
    end
end

-- =================================================================
-- 13. A clipped child (BeginChild returning false) must still be Ended
-- =================================================================
do
    resetInput()
    local ctx = newCtx()
    dockState.init(newDeps(ctx))
    warmState()
    stub.childInvisible = true
    local r = stub.frame(function()
        dockTop.render(ctx)
        dockBottom.render(ctx)
    end)
    stub.childInvisible = false
    check('clipped children: stacks balanced', stub.balanced(r), stub.imbalance(r))
    check('clipped children: both strips still opened and closed', #r.windows == 2,
        table.concat(r.windows, ','))
end

-- =================================================================
-- Phase 13: job-state washes + the loot cell flex (mockups 21c / 22a)
-- =================================================================
do
    resetInput()
    local ctxIdle = newCtx()
    dockState.init(newDeps(ctxIdle))
    warmState()
    local rIdle = stub.frame(function() dockTop.render(ctxIdle) end)
    check('flex: idle frame balanced (status wash push/pop nets zero)',
        stub.balanced(rIdle), stub.imbalance(rIdle))
    local idleW = dockTop.slots and dockTop.slots.loot and dockTop.slots.loot.w
    check('flex: idle loot slot measured', type(idleW) == 'number' and idleW > 0, idleW)
    check('flex: idle still offers Loot All', stub.drew(rIdle, 'Loot All'),
        table.concat(rIdle.buttons, '|'))

    resetInput()
    local uiState = {
        lootRunCorpsesLooted = 1, lootRunTotalCorpses = 3,
        lootRunCurrentCorpse = 'a rat', lootRunLootedItems = {}, lootRunTotalValue = 0,
    }
    local ctxRun = newCtx({ uiState = uiState })
    dockState.init(newDeps(ctxRun, { lootRunning = true }))
    warmState()
    local rRun = stub.frame(function() dockTop.render(ctxRun) end)
    check('flex: running frame balanced (running wash nets zero)',
        stub.balanced(rRun), stub.imbalance(rRun))
    local runW = dockTop.slots and dockTop.slots.loot and dockTop.slots.loot.w
    check('flex: the loot cell grows for a run (22a)',
        type(runW) == 'number' and type(idleW) == 'number' and runW > idleW,
        tostring(idleW) .. ' -> ' .. tostring(runW))

    resetInput()
    local ctxDone = newCtx({ uiState = {
        lootRunFinished = true, lootRunTotalCorpses = 3,
        lootRunLootedItems = {}, lootRunTotalValue = 500000,
    } })
    dockState.init(newDeps(ctxDone))
    warmState()
    local rDone = stub.frame(function() dockTop.render(ctxDone) end)
    check('wash: done frame balanced (done wash nets zero)',
        stub.balanced(rDone), stub.imbalance(rDone))
    check('wash: done frame keeps the full-width summary', stub.drew(rDone, 'looted'),
        table.concat(rDone.text, '|'))
end

-- ---------------------------------------------------------------- summary
local missing = {}
for k, v in pairs(stub.missing) do missing[#missing + 1] = k .. 'x' .. v end
if #missing > 0 then print('\nunstubbed ImGui calls seen: ' .. table.concat(missing, ', ')) end

print(string.format('\n%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
