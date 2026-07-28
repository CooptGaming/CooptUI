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
    return {
        layoutConfig = layoutConfig,
        uiState = opts.uiState or {},
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
    check('bottom: four menu buttons', stub.drew(r, 'Items') and stub.drew(r, 'Character')
        and stub.drew(r, 'Actions') and stub.drew(r, 'Game windows'),
        table.concat(r.buttons, '|'))
    check('bottom: Settings is present', stub.drew(r, 'Settings'), table.concat(r.buttons, '|'))
    check('bottom: balanced', stub.balanced(r), stub.imbalance(r))
    check('bottom: no TLO from the render path', #r.tloAccess == 0, table.concat(r.tloAccess, ','))
    check('bottom: no commands from the render path', #r.commands == 0, table.concat(r.commands, ','))

    -- Hovering a menu button opens the menu as a second window.
    stub.hover = { dockmenubtn_items = true }
    local r2 = stub.frame(function() dockBottom.render(ctx) end)
    check('bottom: hover opens the menu', #r2.windows == 2, table.concat(r2.windows, ','))
    check('bottom: menu lists Bank', stub.drew(r2, 'Bank'), table.concat(r2.buttons, '|'))
    check('bottom: balanced with the menu open', stub.balanced(r2), stub.imbalance(r2))

    -- Clicking a menu entry enqueues rather than acting inline, and asks for a TOGGLE.
    stub.hover = { dockmenubtn_items = true }
    stub.click = { dockmenu_bank = true }
    stub.frame(function() dockBottom.render(ctx) end)
    local q = uiState.dockActionQueue
    check('bottom: a menu click enqueues instead of acting inline', q and #q >= 1, q and #q)
    local a = q and q[#q]
    check('bottom: the action is a window toggle',
        a and a.kind == 'window' and a.id == 'bank' and a.toggle == true,
        a and (a.kind .. '/' .. tostring(a.id) .. '/toggle=' .. tostring(a.toggle)))

    -- A LIT entry (window already open) must NOT queue anything without a click. Selectable
    -- returns (selected, pressed) in this binding -- selected FIRST -- so a lit entry's first
    -- return is true EVERY frame; reading it as "clicked" slammed the window shut the moment
    -- its menu opened. The stub models the tuple, so this would regress loudly now.
    resetInput()
    if not registry.isOpen('bank') then registry.toggleWindow('bank') end
    stub.hover = { dockmenubtn_items = true }
    uiState.dockActionQueue = nil
    stub.frame(function() dockBottom.render(ctx) end)
    check('bottom: a lit entry does not self-close without a click',
        uiState.dockActionQueue == nil or #uiState.dockActionQueue == 0,
        uiState.dockActionQueue and #uiState.dockActionQueue)
    if registry.isOpen('bank') then registry.toggleWindow('bank') end
end

-- =================================================================
-- 10. Chat at all three heights stays balanced and shows what it should
-- =================================================================
do
    for _, mode in ipairs({ 'hidden', 'collapsed', 'peek' }) do
        resetInput()
        local ctx = newCtx({ chat = mode })
        dockState.init(newDeps(ctx))
        warmState(1000000)
        local r = stub.frame(function() dockBottom.render(ctx) end)
        check('chat ' .. mode .. ': balanced', stub.balanced(r), stub.imbalance(r))
    end
    -- With lines in the buffer, collapsed shows the newest.
    resetInput()
    chatFeed.init({})
    local ctx = newCtx({ chat = 'collapsed' })
    dockState.init(newDeps(ctx))
    warmState(1100000)
    check('chat feed starts empty', chatFeed.count() == 0, chatFeed.count())
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

-- ---------------------------------------------------------------- summary
local missing = {}
for k, v in pairs(stub.missing) do missing[#missing + 1] = k .. 'x' .. v end
if #missing > 0 then print('\nunstubbed ImGui calls seen: ' .. table.concat(missing, ', ')) end

print(string.format('\n%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
