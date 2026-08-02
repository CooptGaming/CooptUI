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
local theme      = require('itemui.utils.theme')

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
    check('looting: counter is 4 of 9 (not 0 of 9)', stub.drew(r, '4 of 9'), table.concat(r.text, '|'))
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
        { seg = 'lane',    needle = 'nothing running' },
        { seg = 'buffs',   needle = 'buffs' },
        { seg = 'xp',      needle = 'XP' },
        { seg = 'session', needle = 'session' },
    }) do
        check('full bar: ' .. want.seg .. ' segment rendered', stub.drew(r, want.needle),
            table.concat(r.text, '|'))
    end
    check('full bar: all eight cells captured for popover anchoring',
        (function() local n = 0; for _ in pairs(dockTop.slots) do n = n + 1 end; return n == 8 end)(),
        (function() local ids = {}; for id in pairs(dockTop.slots) do ids[#ids + 1] = id end
         return table.concat(ids, ',') end)())
    check('full bar: no dock errors surfaced',
        not (ctx.uiState.dockErrors and #ctx.uiState.dockErrors > 0),
        ctx.uiState.dockErrors and table.concat(ctx.uiState.dockErrors, ' / '))
    check('full bar: balanced', stub.balanced(r), stub.imbalance(r))

    -- A ZERO count is still a door. The strip reports what THIS SESSION turned up, so
    -- "0 augs" is a fact about the session, not a statement that Aug Utility has nothing
    -- in it -- the window lists everything you own. These read as inert (muted) and used
    -- to BE inert, which locked you out of three windows on a quiet session.
    for _, want in ipairs({
        { needle = '0 augs',    id = 'augmentUtility' },
        { needle = '0 mythics', id = 'mythicals' },
        { needle = '0 scripts', id = 'scripttracker' },
    }) do
        resetInput()
        ctx.uiState.dockActionQueue = {}
        stub.hover = { [want.needle] = true }
        stub.mouse = { [0] = true }
        stub.frame(function() dockTop.render(ctx) end)
        local q = ctx.uiState.dockActionQueue or {}
        check('session: "' .. want.needle .. '" still opens ' .. want.id,
            q[1] and q[1].kind == 'window' and q[1].id == want.id and q[1].toggle == true,
            q[1] and (tostring(q[1].kind) .. '/' .. tostring(q[1].id)) or 'nothing queued')
    end
    resetInput()
end

-- =================================================================
-- 3c. Phase 13: the fixed button pair. Loot All and Auto Sell never move; each becomes its
--     own solid-red Stop IN PLACE while its job runs, and the other greys.
-- =================================================================
do
    -- Idle: both starts offered; Loot All enqueues loot_all on click.
    resetInput()
    local uiState = {}
    local ctx = newCtx({ uiState = uiState })
    dockState.init(newDeps(ctx))
    warmState(1300000)
    local r = stub.frame(function() dockTop.render(ctx) end)
    check('pair idle: offers Loot All', stub.drew(r, 'Loot All##dockBtnLootAll'),
        table.concat(r.buttons, '|'))
    check('pair idle: offers Auto Sell in the same fixed cell', stub.drew(r, 'Auto Sell##dockBtnAutoSell'),
        table.concat(r.buttons, '|'))
    check('pair idle: still balanced with the pair drawn', stub.balanced(r), stub.imbalance(r))
    -- Field regression: the pair clipped because a sized Button under FramePadding.y=1
    -- measures lineHeight+2 inside a child that is EXACTLY lineHeight tall. The button
    -- must be sized to the line height, never taller.
    check('pair: buttons sized to exactly one text line (no vertical clip)',
        (function()
            local lh = ImGui.GetTextLineHeight()
            local seen = 0
            for _, c in ipairs(r.buttonSizes or {}) do
                if c.label:find('dockBtn', 1, true) then
                    seen = seen + 1
                    -- EXPLICIT positive height, at most one line. h=0 (auto) would pass a
                    -- naive <= check while actually measuring lineHeight+FramePadding.y*2
                    -- at runtime — the exact shape of the bug that shipped.
                    if not c.h or c.h <= 0 or c.h > lh then return false end
                end
            end
            return seen == 2
        end)(),
        (function()
            local out = {}
            for _, c in ipairs(r.buttonSizes or {}) do
                if c.label:find('dockBtn', 1, true) then
                    out[#out + 1] = c.label .. '=' .. tostring(c.h)
                end
            end
            return table.concat(out, ',') .. ' lineH=' .. tostring(ImGui.GetTextLineHeight())
        end)())

    stub.click = { ['Loot All##dockBtnLootAll'] = true }
    stub.frame(function() dockTop.render(ctx) end)
    local q = uiState.dockActionQueue
    check('pair idle: Loot All enqueues loot_all',
        q and #q >= 1 and q[#q].kind == 'loot_all',
        q and q[#q] and tostring(q[#q].kind) or 'nil')

    -- Mid-run: Loot All becomes its own Stop in place (25a) — same slot, same id root; a
    -- click enqueues loot_stop. The lane never carries a Stop.
    resetInput()
    local uiState2 = {}
    local ctx2 = newCtx({ uiState = uiState2 })
    dockState.init(newDeps(ctx2, { lootRunning = true, inventoryItems = { {}, {} } }))
    warmState(1310000)
    local r2 = stub.frame(function() dockTop.render(ctx2) end)
    check('pair mid-run: Loot All is its own Stop in place', stub.drew(r2, 'Stop##dockBtnLootAll')
        and not stub.drew(r2, 'Loot All##dockBtnLootAll'), table.concat(r2.buttons, '|'))
    check('pair mid-run: no Stop in the lane', not stub.drew(r2, 'Stop##dockLootStop'),
        table.concat(r2.buttons, '|'))
    stub.click = { ['Stop##dockBtnLootAll'] = true }
    stub.frame(function() dockTop.render(ctx2) end)
    local q2 = uiState2.dockActionQueue
    check('pair mid-run: Stop enqueues loot_stop',
        q2 and #q2 >= 1 and q2[#q2].kind == 'loot_stop',
        q2 and q2[#q2] and tostring(q2[#q2].kind) or 'nil')
end

do
    -- Auto Sell offers with a merchant open and enqueues auto_sell.
    resetInput()
    local uiState = {}
    local ctx = newCtx({ uiState = uiState })
    dockState.init(newDeps(ctx, { merchantOpen = true }))
    warmState(1320000)
    local r = stub.frame(function() dockTop.render(ctx) end)
    check('sell: offers Auto Sell with a merchant open', stub.drew(r, 'Auto Sell##dockBtnAutoSell'),
        table.concat(r.buttons, '|'))
    check('sell: still balanced with a merchant open', stub.balanced(r), stub.imbalance(r))

    stub.click = { ['Auto Sell##dockBtnAutoSell'] = true }
    stub.frame(function() dockTop.render(ctx) end)
    local q = uiState.dockActionQueue
    check('sell: Auto Sell enqueues auto_sell',
        q and #q >= 1 and q[#q].kind == 'auto_sell',
        q and q[#q] and tostring(q[#q].kind) or 'nil')

    -- No merchant: the button still draws (kit-disabled), but a click enqueues nothing.
    resetInput()
    local uiState2 = {}
    local ctx2 = newCtx({ uiState = uiState2 })
    dockState.init(newDeps(ctx2, { merchantOpen = false }))
    warmState(1330000)
    local r2 = stub.frame(function() dockTop.render(ctx2) end)
    check('sell: Auto Sell still draws without a merchant', stub.drew(r2, 'Auto Sell##dockBtnAutoSell'),
        table.concat(r2.buttons, '|'))
    check('sell: balanced without a merchant', stub.balanced(r2), stub.imbalance(r2))

    stub.click = { ['Auto Sell##dockBtnAutoSell'] = true }
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
    check('bottom: hub lists Bags and Bank as separate rows (merge rolled back)',
        stub.drew(r2, 'Bags##dockmenu_hub') and stub.drew(r2, 'Bank##dockmenu_bank'),
        table.concat(r2.buttons, '|'))
    check('bottom: hub lists the Item Display + Aug Utility pair',
        stub.drew(r2, 'Item Display + Augment Utility'), table.concat(r2.buttons, '|'))
    check('bottom: hub carries the group headers', stub.drew(r2, 'ITEMS')
        and stub.drew(r2, 'CHARACTER') and stub.drew(r2, 'LAYOUTS'), table.concat(r2.text, '|'))
    check('bottom: hub carries the layouts entries', stub.drew(r2, 'Re-tidy now'),
        table.concat(r2.buttons, '|'))
    check('bottom: the ID+AU pair is still ONE row (a real pair, unlike bags/bank)',
        stub.drew(r2, '##dockmenu_pair_idau')
        and not stub.drew(r2, '##dockmenu_itemDisplay') and not stub.drew(r2, '##dockmenu_augmentUtility'),
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
    -- 19b: the command menus and the identity group are on the bar in BOTH styles now.
    -- Actions is the only path to Stop once the launcher row is folded or off, and Hub is
    -- where the launcher LIST lives, so neither may be style-conditional.
    check('buttons: the command menus are present in this style too',
        stub.drew(r, '##dockmenubtn_actions') and stub.drew(r, '##dockmenubtn_game'),
        table.concat(r.buttons, '|'))
    check('buttons: the identity group is Hub, Layouts, Settings',
        stub.drew(r, '##dockmenubtn_hub') and stub.drew(r, '##dockmenubtn_layouts')
        and stub.drew(r, 'Settings##dockSettings'), table.concat(r.buttons, '|'))
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
    check('buttons: the Bank half toggles the Bank WINDOW (not the hub)',
        a and a.kind == 'window' and a.id == 'bank' and a.toggle == true,
        a and (tostring(a.kind) .. '/' .. tostring(a.id)))

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
    -- 19b: "counts sit in their own pill". The label stays the WINDOW'S NAME -- "Reroll 3"
    -- read as if that were what the window is called -- and the count is a separate
    -- control beside it.
    check('buttons: the pending count is its own pill, not part of the label',
        stub.drew(rBadge, 'Reroll##dockbtn_reroll') and stub.drew(rBadge, '3##dockbtn_reroll_pill')
        and not stub.drew(rBadge, 'Reroll 3##dockbtn_reroll'), table.concat(rBadge.buttons, '|'))
    check('buttons: badge frame balanced', stub.balanced(rBadge), stub.imbalance(rBadge))

    -- The pill is part of the control, not a dead decoration beside it.
    resetInput()
    badgeCtx.uiState.dockActionQueue = nil
    stub.click = { dockbtn_reroll_pill = true }
    stub.frame(function() dockBottom.render(badgeCtx) end)
    local qPill = badgeCtx.uiState.dockActionQueue
    check('buttons: clicking the pill does the chip action',
        qPill and #qPill >= 1 and qPill[#qPill].kind == 'window' and qPill[#qPill].id == 'reroll'
        and qPill[#qPill].toggle == true, qPill and #qPill)

    resetInput()
    badgeCtx.rerollService.getPendingAugList = function() return {} end
    badgeCtx.rerollService.getPendingMythicalList = function() return {} end
    local rNoBadge = stub.frame(function() dockBottom.render(badgeCtx) end)
    check('buttons: no pending entries -> plain label, no pill',
        stub.drew(rNoBadge, 'Reroll##dockbtn_reroll') and not stub.drew(rNoBadge, '##dockbtn_reroll_pill'),
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
-- 10d. Bottom bar v2 (19b): open is BLUE not green, the accent lands on the screen-facing
--      edge, unread counts are dots, and the launcher row folds itself away when the
--      viewport cannot hold it.
-- =================================================================
do
    resetInput()
    local uiState = {}
    local ctx = newCtx({ uiState = uiState })
    ctx.layoutConfig.DockBottomStyle = 'buttons'
    ctx.layoutConfig.DockButtons = 'reroll'
    dockState.init(newDeps(ctx))
    warmState(1290000)

    -- Closed: no wash, no accent.
    if registry.isOpen('reroll') then registry.toggleWindow('reroll') end
    local rOff = stub.frame(function() dockBottom.render(ctx) end)
    check('v2: a closed chip gets no open wash',
        not stub.pushedColor(rOff, theme.Kit.OpenWash))

    -- Open: OpenWash fill + the OpenBlue accent. The old code filled it with Keep.Normal,
    -- which is the GREEN this product spends on "go" -- a launcher that read as an action.
    resetInput()
    registry.toggleWindow('reroll')
    local rOn = stub.frame(function() dockBottom.render(ctx) end)
    check('v2: an open chip is washed in open-blue', stub.pushedColor(rOn, theme.Kit.OpenWash))
    check('v2: an open chip is NOT filled with go-green',
        not stub.pushedColor(rOn, theme.Colors.Keep.Normal))
    check('v2: the label on a washed chip is legible white',
        stub.pushedColor(rOn, theme.Kit.TextOnOpen))
    check('v2: the 2px accent is drawn in open-blue',
        stub.drewColor(rOn, theme.Kit.OpenBlue, 'rectFilled'))
    check('v2: still balanced with a lit chip', stub.balanced(rOn), stub.imbalance(rOn))

    -- The accent sits on the edge that FACES the screen: a bottom-docked bar accents the
    -- top of its chips, a top-docked bar the bottom. The stub's item rect is y 0..30.
    local function accentRects(r)
        local out = {}
        for _, d in ipairs(stub.draws(r, 'rectFilled')) do
            if d.col == stub.colorOf(theme.Kit.OpenBlue) then out[#out + 1] = d end
        end
        return out
    end
    local aBottom = accentRects(rOn)
    check('v2: bottom-docked bar accents the TOP of the chip',
        #aBottom > 0 and aBottom[1].y1 == 0 and aBottom[1].y2 == 2,
        #aBottom > 0 and (aBottom[1].y1 .. '..' .. aBottom[1].y2))

    -- position='bottom' puts the STATUS bar at the bottom, which pushes this bar to the top.
    resetInput()
    local topCtx = newCtx({ position = 'bottom', uiState = {} })
    topCtx.layoutConfig.DockBottomStyle = 'buttons'
    topCtx.layoutConfig.DockButtons = 'reroll'
    dockState.init(newDeps(topCtx))
    warmState(1291000)
    local rTop = stub.frame(function() dockBottom.render(topCtx) end)
    local aTop = accentRects(rTop)
    check('v2: the other edge accents the BOTTOM of the chip',
        #aTop > 0 and aTop[1].y2 == 30 and aTop[1].y1 == 28,
        #aTop > 0 and (aTop[1].y1 .. '..' .. aTop[1].y2))
    if registry.isOpen('reroll') then registry.toggleWindow('reroll') end

    -- Unread dots: one per tab, always four, coloured only where something is waiting.
    -- Four dots always drawn is the point -- the line never reflows as chat arrives.
    resetInput()
    dockState.init(newDeps(ctx))
    warmState(1292000)
    chatFeed.clearUnread()
    chatFeed._inject("Alotta tells you, 'ready when you are'")   -- -> Main
    chatFeed._inject('[Alotta] ready when you are')              -- -> Other, and newest
    local rDots = stub.frame(function() dockBottom.render(ctx) end)
    local circles = stub.draws(rDots, 'circleFilled')
    check('v2: four unread dots, one per tab', #circles == 4, #circles)
    check('v2: somebody talking to you lights the Main dot amber',
        stub.drewColor(rDots, theme.Kit.Attention, 'circleFilled'))
    check('v2: a quiet tab gets the divider grey',
        stub.drewColor(rDots, theme.Kit.Divider, 'circleFilled'))
    check('v2: the speaker bracket is drawn apart from the line',
        stub.drew(rDots, '[Alotta]') and stub.drew(rDots, 'ready when you are'),
        table.concat(rDots.text, '|'))

    -- Clicking a dot opens chat on that tab -- and must NOT also fire the whole-line click,
    -- which would toggle the window shut in the same frame.
    resetInput()
    uiState.dockActionQueue = nil
    stub.hover = { dockdot_mq = true, dockChatCollapsed = true }
    stub.mouse = { [0] = true }
    stub.frame(function() dockBottom.render(ctx) end)
    stub.mouse = {}
    local qd = uiState.dockActionQueue or {}
    check('v2: a dot click asks for chat exactly once', #qd == 1, #qd)
    check('v2: ...as an idempotent open, not a toggle',
        qd[1] and qd[1].kind == 'window' and qd[1].id == 'chat' and qd[1].toggle == nil,
        qd[1] and tostring(qd[1].toggle))
    check('v2: ...on the dot\'s own tab', uiState.chatRequestedTab == 'mq',
        tostring(uiState.chatRequestedTab))
    resetInput()

    -- 19b's fold: at a viewport too narrow to hold chat AND the launchers, the launcher row
    -- goes (the Hub menu still has every one of them) and chat survives.
    local wideCtx = newCtx({ uiState = {} })
    wideCtx.layoutConfig.DockBottomStyle = 'buttons'
    wideCtx.layoutConfig.DockButtons = 'bags,bank,reroll,effects,equipment'
    dockState.init(newDeps(wideCtx))
    warmState(1293000)
    local rWide = stub.frame(function() dockBottom.render(wideCtx) end)
    check('fold: at full width the launcher row is drawn', stub.drew(rWide, '##dockbtn_reroll'),
        table.concat(rWide.buttons, '|'))

    resetInput()
    stub.viewportSize = { 520, 1368 }
    local rNarrow = stub.frame(function() dockBottom.render(wideCtx) end)
    stub.viewportSize = nil
    check('fold: a narrow viewport folds the launcher row away',
        not stub.drew(rNarrow, '##dockbtn_reroll'), table.concat(rNarrow.buttons, '|'))
    check('fold: ...but chat and the Hub list stay',
        stub.drew(rNarrow, '##dockChatCycle') and stub.drew(rNarrow, '##dockmenubtn_hub'),
        table.concat(rNarrow.buttons, '|'))
    check('fold: narrow frame balanced', stub.balanced(rNarrow), stub.imbalance(rNarrow))

    -- Settings is a window chip: lit while open, and clicking it while lit closes it (26a).
    resetInput()
    wideCtx.uiState.dockActionQueue = nil
    stub.click = { dockSettings = true }
    stub.frame(function() dockBottom.render(wideCtx) end)
    local qs = wideCtx.uiState.dockActionQueue or {}
    check('v2: Settings toggles rather than only opening',
        qs[1] and qs[1].id == 'config' and qs[1].toggle == true,
        qs[1] and tostring(qs[1].toggle))
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
-- Phase 13 (26a/§11): fixed cells — widths IDENTICAL in every job state (acceptance 10:
-- only the lane may change width, and only with viewport/enable changes, never states) —
-- plus the job washes staying balanced.
-- =================================================================
do
    resetInput()
    local ctxIdle = newCtx()
    dockState.init(newDeps(ctxIdle))
    warmState()
    local rIdle = stub.frame(function() dockTop.render(ctxIdle) end)
    check('fixed: idle frame balanced (status wash push/pop nets zero)',
        stub.balanced(rIdle), stub.imbalance(rIdle))
    local idleWidths = {}
    for id, slot in pairs(dockTop.slots) do idleWidths[id] = slot.w end
    check('fixed: the lane exists and flexes into the remainder',
        type(idleWidths.lane) == 'number' and idleWidths.lane > 0, tostring(idleWidths.lane))
    check('fixed: buttons cell at its constant width',
        idleWidths.buttons == 240, tostring(idleWidths.buttons))
    check('fixed: idle lane names what it is for', stub.drew(rIdle, 'nothing running'),
        table.concat(rIdle.text, '|'))

    resetInput()
    local uiState = {
        lootRunCorpsesLooted = 1, lootRunTotalCorpses = 3,
        lootRunCurrentCorpse = 'a rat', lootRunLootedItems = {}, lootRunTotalValue = 0,
    }
    local ctxRun = newCtx({ uiState = uiState })
    dockState.init(newDeps(ctxRun, { lootRunning = true }))
    warmState()
    local rRun = stub.frame(function() dockTop.render(ctxRun) end)
    check('fixed: running frame balanced (running wash nets zero)',
        stub.balanced(rRun), stub.imbalance(rRun))
    local same = true
    local diffs = {}
    for id, slot in pairs(dockTop.slots) do
        if idleWidths[id] ~= slot.w then
            same = false
            diffs[#diffs + 1] = string.format('%s %s->%s', id, tostring(idleWidths[id]), tostring(slot.w))
        end
    end
    check('fixed: EVERY cell width identical idle vs mid-run (acceptance 10)',
        same, table.concat(diffs, ','))

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

    -- 25a: the hold decays — DOCK_LANE_DONE_HOLD_MS later the lane is idle again while
    -- lootRunFinished is STILL set (a new run clears the flag; the clock ends the hold).
    stub.advance(T.DOCK_LANE_DONE_HOLD_MS + 500)
    dockState.tick(stub.now)
    local rDecayed = stub.frame(function() dockTop.render(ctxDone) end)
    check('wash: the done hold decays to idle after 6s', stub.drew(rDecayed, 'nothing running'),
        table.concat(rDecayed.text, '|'))

    -- Disabling a segment hands its width to the lane (26a: "unchecked width goes to the
    -- action lane") — same total, bigger lane, and the disabled cell is gone.
    resetInput()
    local ctxLess = newCtx({ segments = 'status,bags,sell,buffs,xp' })   -- session off
    dockState.init(newDeps(ctxLess))
    warmState()
    stub.frame(function() dockTop.render(ctxLess) end)
    local lessLane = dockTop.slots.lane and dockTop.slots.lane.w
    check('fixed: disabled segment frees its width to the lane',
        dockTop.slots.session == nil and type(lessLane) == 'number'
        and lessLane > (idleWidths.lane or 0), tostring(lessLane))
end

-- =================================================================
-- 23c: the CoOpt cell opens the LAUNCHER LIST, not Bags. Bags has its own cell one over,
-- so the identity cell spending its click on the same window was a wasted control.
-- =================================================================
do
    resetInput()
    local uiState = {}
    local ctx = newCtx({ uiState = uiState })
    dockState.init(newDeps(ctx))
    warmState()

    -- Clicking CoOpt must NOT queue a hub open.
    stub.hover = { dockseg_status = true }
    stub.mouse = { [ImGuiMouseButton.Left] = true }
    stub.frame(function() dockTop.render(ctx) end)
    check('CoOpt cell: click does NOT open Bags',
        uiState.dockActionQueue == nil or #uiState.dockActionQueue == 0,
        uiState.dockActionQueue and #uiState.dockActionQueue)
    check('CoOpt cell: click pins the Hub list open', uiState.dockPinnedPopover == 'status',
        tostring(uiState.dockPinnedPopover))

    -- With it pinned the panel draws, carrying the SAME entries the command bar's Hub menu
    -- uses (one list, two surfaces - they cannot drift).
    resetInput()
    local rHub = stub.frame(function() dockTop.render(ctx) end)
    check('CoOpt panel: draws as a second window', #rHub.windows >= 2, table.concat(rHub.windows, ','))
    check('CoOpt panel: carries the grouped launcher list',
        stub.drew(rHub, 'ITEMS') and stub.drew(rHub, 'CHARACTER') and stub.drew(rHub, 'LAYOUTS'),
        table.concat(rHub.text, '|'))
    check('CoOpt panel: lists the windows themselves',
        stub.drew(rHub, 'Bags##dockmenu_hub') and stub.drew(rHub, 'Bank##dockmenu_bank'),
        table.concat(rHub.buttons, '|'))
    check('CoOpt panel: balanced', stub.balanced(rHub), stub.imbalance(rHub))

    -- Clicking again puts it away.
    resetInput()
    stub.hover = { dockseg_status = true }
    stub.mouse = { [ImGuiMouseButton.Left] = true }
    stub.frame(function() dockTop.render(ctx) end)
    check('CoOpt cell: clicking again closes the list', uiState.dockPinnedPopover == nil,
        tostring(uiState.dockPinnedPopover))
    resetInput()
end

-- =================================================================
-- 25a: the running lane draws a REAL inline progress bar between the label and the counts
-- (it used to be a 3px underline along the cell's bottom edge - a workaround from when the
-- loot cell was narrow enough that an inline bar clipped the Stop button out of the strip).
-- =================================================================
do
    resetInput()
    local uiState = {
        lootRunCorpsesLooted = 4, lootRunTotalCorpses = 11,
        lootRunCurrentCorpse = 'a rat', lootRunLootedItems = { {}, {}, {} }, lootRunTotalValue = 0,
    }
    local ctx = newCtx({ uiState = uiState })
    dockState.init(newDeps(ctx, { lootRunning = true }))
    warmState()
    local r = stub.frame(function() dockTop.render(ctx) end)
    check('lane bar: a progress bar is drawn while looting', (r.progressBars or 0) > 0,
        tostring(r.progressBars))
    check('lane bar: never taller than the one-line cell (the clipping rule)',
        (function()
            local lh = ImGui.GetTextLineHeight()
            for _, b in ipairs(r.progressBarSizes or {}) do
                if not b.h or b.h <= 0 or b.h > lh then return false end
            end
            return true
        end)(),
        (function()
            local out = {}
            for _, b in ipairs(r.progressBarSizes or {}) do out[#out + 1] = tostring(b.h) end
            return table.concat(out, ',') .. ' lineH=' .. tostring(ImGui.GetTextLineHeight())
        end)())
    check('lane bar: balanced', stub.balanced(r), stub.imbalance(r))

    -- Idle draws none: a bar at 0% reads as a stalled job.
    resetInput()
    local ctxIdle = newCtx()
    dockState.init(newDeps(ctxIdle))
    warmState()
    local rIdle = stub.frame(function() dockTop.render(ctxIdle) end)
    check('lane bar: idle draws no bar at all', (rIdle.progressBars or 0) == 0,
        tostring(rIdle.progressBars))
end

-- =================================================================
-- Phase 14 (§12 / 26b): the session strip's four values + the triage panel. The record
-- service is seeded directly (its own suite covers the pre-emption logic); this block
-- proves the CELL and PANEL read it honestly: amber only for needs-a-call, zero muted
-- and inert, value clicks are doors, and a panel chip decides.
-- =================================================================
do
    resetInput()
    local sessionRecord = require('itemui.services.session_record')
    sessionRecord._resetForTests()
    local files = {}
    local srDeps
    srDeps = {
        inventoryItems = {
            { name = 'Fresh Emerald', id = 11, type = 'Augmentation', bag = 1, slot = 1,
              value = 142000, totalValue = 142000, stackSize = 1, acquiredSeq = 500 },
            { name = 'Script of Lost Memories', id = 30, type = 'Misc', bag = 1, slot = 2,
              value = 0, totalValue = 0, stackSize = 3, acquiredSeq = 501 },
        },
        getSessionStartAcquiredSeq = function() return 500 end,
        getSellStatusForItem = function() return '-', false, false, false end,
        applySellListChange = function(name, k, j) srDeps._applied = { name = name, k = k, j = j } end,
        rerollService = {
            getListStatus = function() return nil end,
            addToPendingList = function() return true end,
            removeFromPending = function() return true end,
        },
        getCharStoragePath = function(char, file) return 'FAKE/' .. char .. '/' .. file end,
        safeWrite = function(path, content) files[path] = content return true end,
        safeReadAll = function(path) return files[path] end,
    }
    sessionRecord.init(srDeps)
    -- tick() resolves the character through mq.TLO.Me.Name; this suite's TLO is the
    -- no-render-access trap, so lend it a name JUST for the seeding tick (renders below
    -- keep the trap — the no-TLO-from-the-render-path assertions stay real).
    local mqTab = package.loaded['mq']
    local savedTLO = mqTab.TLO
    mqTab.TLO = { Me = { Name = function() return 'Testchar' end } }
    sessionRecord.tick(1000)
    mqTab.TLO = savedTLO

    local uiState = {}
    local ctx = newCtx({ uiState = uiState })
    dockState.init(newDeps(ctx))
    warmState()
    local r = stub.frame(function() dockTop.render(ctx) end)
    check('session strip: amber-eligible aug count drawn', stub.drew(r, '1 aug'),
        table.concat(r.text, '|'))
    check('session strip: scripts counted by stack', stub.drew(r, '3 scripts'),
        table.concat(r.text, '|'))
    check('session strip: zero mythics muted', stub.drew(r, '0 mythics'),
        table.concat(r.text, '|'))
    check('session strip: balanced', stub.balanced(r), stub.imbalance(r))

    -- A non-zero value is a door: clicking the aug count toggles Aug Utility.
    stub.hover = { ['1 aug'] = true }
    stub.mouse = { [ImGuiMouseButton.Left] = true }
    stub.frame(function() dockTop.render(ctx) end)
    local q = uiState.dockActionQueue
    check('session strip: the aug value is a door', q and #q >= 1
        and q[#q].kind == 'window' and q[#q].id == 'augmentUtility' and q[#q].toggle == true,
        q and q[#q] and tostring(q[#q].id) or 'nil')

    -- Hovering the cell opens the triage panel; a Keep chip decides through the record.
    resetInput()
    stub.hover = { dockseg_session = true }
    local r2 = stub.frame(function() dockTop.render(ctx) end)
    check('session panel: opens on hover', #r2.windows == 2, table.concat(r2.windows, ','))
    -- Both rows need a call now: the script is no longer auto-sorted, because scripts are
    -- keep-protected by default like the rest and the user still has to decide whether to
    -- turn one in.
    check('session panel: truth line carries the full totals', stub.drew(r2, '2 looted . 2 need a call . 0 sorted'),
        table.concat(r2.text, '|'))
    check('session panel: the call row is offered best-first', stub.drew(r2, 'Fresh Emerald'),
        table.concat(r2.text, '|'))
    check('session panel: balanced with the panel open', stub.balanced(r2), stub.imbalance(r2))

    stub.hover = { dockseg_session = true }
    stub.click = { ['Keep##sess1'] = true }
    stub.frame(function() dockTop.render(ctx) end)
    check('session panel: Keep chip decides through the record',
        srDeps._applied and srDeps._applied.name == 'Fresh Emerald' and srDeps._applied.k == true,
        srDeps._applied and srDeps._applied.name)
    local c = sessionRecord.getCounts()
    check('session panel: amber cleared, sorted grew', c.augsCall == 0 and c.sorted == 1,
        c.augsCall .. '/' .. c.sorted)

    -- 26b why-line: every row says why it deserves attention. The free, always-true half
    -- is the augment's own accepted socket types, from an augType captured at record
    -- time - so it still answers for an entry whose live row is gone.
    resetInput()
    sessionRecord._resetForTests()
    srDeps.inventoryItems = {
        { name = 'Typed Aug', id = 12, type = 'Augmentation', bag = 1, slot = 1,
          value = 1000, totalValue = 1000, stackSize = 1, acquiredSeq = 600, augType = 5 },
    }
    srDeps.getSessionStartAcquiredSeq = function() return 600 end
    sessionRecord.init(srDeps)
    local mqTab2 = package.loaded['mq']
    local savedTLO2 = mqTab2.TLO
    mqTab2.TLO = { Me = { Name = function() return 'Testchar' end } }
    sessionRecord.tick(1000)
    mqTab2.TLO = savedTLO2
    local ctxWhy = newCtx({ uiState = {} })
    dockState.init(newDeps(ctxWhy))
    warmState()
    stub.hover = { dockseg_session = true }
    local rWhy = stub.frame(function() dockTop.render(ctxWhy) end)
    -- augType 5 -> types 1, 3 AND 5: the shared getAugTypeSlotIds deliberately treats the
    -- value as EITHER a bitmask (101b = 1,3) OR a bare type id (5), because the field is
    -- genuinely ambiguous and over-listing is safer than hiding a slot that fits. The
    -- why-line inherits that, on purpose - it is the same helper the Item Display's
    -- "fits in slot types" line uses, so the two can never disagree.
    check('why-line: names the socket types the aug actually fits',
        stub.drew(rWhy, 'types 1, 3, 5 augment'), table.concat(rWhy.text, '|'))
    check('why-line: balanced', stub.balanced(rWhy), stub.imbalance(rWhy))

    -- Right-click a row: the §7 menu opens from a host OUTSIDE the panel (a popup opened
    -- inside it would kill the panel's hover grace and take itself down 250ms later), and
    -- the panel pins so the list stays put behind the menu.
    --
    -- The menu is offered ONLY for a LIVE entry, re-linked to its real inventory row by
    -- acquiredSeq. So the render ctx has to carry that row - which is the point: a
    -- departed entry (every entry after a restart) gets no menu at all rather than one
    -- full of verbs that would act on a location it no longer has.
    resetInput()
    ctxWhy.inventoryItems = srDeps.inventoryItems
    stub.hover = { dockseg_session = true, ['Typed Aug'] = true }
    stub.mouse = { [ImGuiMouseButton.Right] = true }
    local rMenu = stub.frame(function() dockTop.render(ctxWhy) end)
    check('row menu: right-click pins the panel so it survives the menu',
        ctxWhy.uiState.dockPinnedPopover == 'session',
        tostring(ctxWhy.uiState.dockPinnedPopover))
    check('row menu: frame stays balanced with the menu host up',
        stub.balanced(rMenu), stub.imbalance(rMenu))
    -- The host is its own window, drawn outside the popover.
    check('row menu: the menu gets an independent host window',
        (function()
            for _, w in ipairs(rMenu.windows) do
                if w:find('SessionMenuHost', 1, true) then return true end
            end
            return false
        end)(), table.concat(rMenu.windows, ','))

    -- A DEPARTED entry gets no menu. The builder's rows key off bag/slot, and a stand-in
    -- with neither still renders Open it / Inspect / Reroll as enabled - verbs that
    -- quietly do nothing or fire at a location that does not exist. After a restart every
    -- entry is departed, so this is the common case, not an edge.
    resetInput()
    ctxWhy.inventoryItems = {}   -- the live row is gone; the entry departs on the next tick
    stub.advance(1000)
    local mqTab3 = package.loaded['mq']
    local savedTLO3 = mqTab3.TLO
    mqTab3.TLO = { Me = { Name = function() return 'Testchar' end } }
    sessionRecord.tick(stub.now)
    mqTab3.TLO = savedTLO3
    stub.hover = { dockseg_session = true, ['Typed Aug'] = true }
    stub.mouse = { [ImGuiMouseButton.Right] = true }
    local rGone = stub.frame(function() dockTop.render(ctxWhy) end)
    check('row menu: a departed entry opens NO menu (no verbs it cannot honour)',
        (function()
            for _, w in ipairs(rGone.windows) do
                if w:find('SessionMenuHost', 1, true) then return false end
            end
            return true
        end)(), table.concat(rGone.windows, ','))
    check('row menu: departed frame still balanced', stub.balanced(rGone), stub.imbalance(rGone))

    resetInput()
    sessionRecord._resetForTests()
end

-- =================================================================
-- Phase 15 (25c): the script turn-in is the lane's third owner — progress from the
-- consume FSM's queue, and the ONE lane state that carries its own Stop (it has no
-- start button on the bar; the Scripts window starts it).
-- =================================================================
do
    resetInput()
    local uiState = {
        scriptTurninPlanTotal = 38,
        pendingScriptConsume = { bag = 1, slot = 1, source = 'inv',
            totalToConsume = 10, consumedSoFar = 4, nextClickAt = 0, itemName = 'Script of Lost Memories' },
        pendingScriptConsumeQueue = {
            { bag = 1, slot = 2, source = 'inv', totalToConsume = 20, consumedSoFar = 0, nextClickAt = 0 },
        },
    }
    local ctx = newCtx({ uiState = uiState })
    dockState.init(newDeps(ctx))
    warmState()
    local r = stub.frame(function() dockTop.render(ctx) end)
    -- remaining = (10-4) + 20 = 26; done = 38 - 26 = 12
    check('script job: lane shows turn-in progress', stub.drew(r, 'turning in scripts')
        and stub.drew(r, '12 of 38'), table.concat(r.text, '|'))
    check('script job: the lane Stop is offered', stub.drew(r, 'Stop##dockLaneScriptStop'),
        table.concat(r.buttons, '|'))
    check('script job: balanced (stop button kit push/pop nets zero)',
        stub.balanced(r), stub.imbalance(r))

    stub.click = { dockLaneScriptStop = true }
    stub.frame(function() dockTop.render(ctx) end)
    local q = uiState.dockActionQueue
    check('script job: Stop enqueues script_stop', q and #q >= 1 and q[#q].kind == 'script_stop',
        q and q[#q] and tostring(q[#q].kind) or 'nil')

    -- The job ending clears the plan through dock_state's own tick.
    resetInput()
    uiState.pendingScriptConsume = nil
    uiState.pendingScriptConsumeQueue = nil
    stub.advance(1000)
    dockState.tick(stub.now)
    local r2 = stub.frame(function() dockTop.render(ctx) end)
    check('script job: lane returns to idle when the queue drains',
        stub.drew(r2, 'nothing running'), table.concat(r2.text, '|'))
    check('script job: the plan total dissolved with the job',
        uiState.scriptTurninPlanTotal == nil, tostring(uiState.scriptTurninPlanTotal))
end

-- ---------------------------------------------------------------- summary
local missing = {}
for k, v in pairs(stub.missing) do missing[#missing + 1] = k .. 'x' .. v end
if #missing > 0 then print('\nunstubbed ImGui calls seen: ' .. table.concat(missing, ', ')) end

print(string.format('\n%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
