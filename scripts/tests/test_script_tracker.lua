-- Scripts companion suite (windows pass phase 15, mockup 25c): the shared defs module,
-- counting from the SHARED inventory list (no second bag scan — the point of the fold),
-- turn-in enqueueing through the existing script-consume FSM shapes, and the window
-- rendering balanced under the stub with the aec75c0 window-body containment.

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
local registry = require('itemui.core.registry')
local scriptDefs = require('itemui.utils.script_defs')
local ScriptTrackerView = require('itemui.views.script_tracker')

-- ---------------------------------------------------------------- 1. shared defs
do
    check('defs: 15 entries (3 families x 5 tiers)', #scriptDefs.DEFS == 15, #scriptDefs.DEFS)
    check('defs: plain name', scriptDefs.BY_NAME['Script of Lost Memories'] ~= nil)
    check('defs: tiered name', scriptDefs.BY_NAME['Legendary Script of Rebirthed Memories'] ~= nil)
    local leg = scriptDefs.BY_NAME['Legendary Script of Planar Power']
    check('defs: legendary planar worth 5', leg and leg.aa == 5 and leg.familyShort == 'Planar',
        leg and (leg.aa .. '/' .. leg.familyShort))
    check('defs: classify by item row', scriptDefs.classify({ name = 'Rare Script of Lost Memories' }) ~= nil
        and scriptDefs.classify({ name = 'Sword of Nothing' }) == nil)
end

-- ---------------------------------------------------------------- ctx factory
local function makeCtx(over)
    local ctx = {
        theme = theme,
        uiState = { tableFlags = 0, uiLocked = false },
        perfCache = { lastScanTimeInv = 123456 },
        layoutConfig = { UIMode = 'bars', ScriptTrackerWindowX = 100, ScriptTrackerWindowY = 100,
            WidthScriptTrackerPanel = 460, HeightScriptTracker = 400 },
        inventoryItems = {
            { name = 'Script of Lost Memories', bag = 1, slot = 1, stackSize = 4 },
            { name = 'Legendary Script of Planar Power', bag = 1, slot = 2, stackSize = 2 },
            { name = 'Rare Script of Rebirthed Memories', bag = 2, slot = 1, stackSize = 1 },
            { name = 'Not A Script', bag = 2, slot = 2, stackSize = 1 },
        },
        scheduleLayoutSave = function() end,
        setStatusMessage = function() end,
        renderRefreshButton = function() end,
        refreshAllScans = function() end,
        renderWindowLock = function() end,
    }
    for k, v in pairs(over or {}) do ctx[k] = v end
    return ctx
end

registry.init({ layoutConfig = { UIMode = 'bars' }, companionWindowOpenedAt = {} })
registry.setWindowState('scripttracker', true, true)

-- ---------------------------------------------------------------- 2. render + counts
do
    local ctx = makeCtx()
    local r = stub.frame(function() ScriptTrackerView.render(ctx) end)
    check('render: draws without error', r.ok, r.err)
    check('render: stacks balanced', stub.balanced(r))
    -- 4x1 + 2x5 + 1x3 = 17 AA across 7 scripts
    check('render: AA waiting is aug-total honest', stub.drew(r, '17 AA waiting'),
        table.concat(r.text, '|'))
    check('render: count line', stub.drew(r, 'across 7 scripts'), table.concat(r.text, '|'))
    check('render: header band present in bars', stub.drew(r, 'Scripts'), table.concat(r.text, '|'))
    check('render: tier rows drawn', stub.drew(r, 'Legendary') and stub.drew(r, 'Normal'),
        table.concat(r.text, '|'))
    check('render: turn-in verbs offered', stub.drew(r, 'Turn in all 7')
        and stub.drew(r, 'Turn in Legendary only'), table.concat(r.buttons, '|'))

    -- A STACK SHRINKING must move the count. The count cache was keyed on list length plus
    -- last scan time, and a consumed script decrements stackSize without removing the row --
    -- so neither term changed and the window served the pre-run figure until something forced
    -- a rescan. Reported from the field during a 12-script turn-in.
    ctx.inventoryItems[1].stackSize = 1              -- 4 -> 1, row stays
    ctx.perfCache.invMutationGen = (ctx.perfCache.invMutationGen or 0) + 1
    local r2 = stub.frame(function() ScriptTrackerView.render(ctx) end)
    check('render: a stack shrink updates the count without a rescan',
        stub.drew(r2, 'across 4 scripts'), table.concat(r2.text, '|'))
    check('render: and the AA total follows it', stub.drew(r2, '14 AA waiting'),
        table.concat(r2.text, '|'))

    -- ...and without the generation bump it would NOT, which is the bug. Same list length,
    -- same scan time, different stack.
    ctx.inventoryItems[1].stackSize = 4
    local r3 = stub.frame(function() ScriptTrackerView.render(ctx) end)
    check('render: the generation is what makes it visible (stale without a bump)',
        stub.drew(r3, 'across 4 scripts'), table.concat(r3.text, '|'))
end

-- ---------------------------------------------------------------- 3. turn-in enqueue
do
    local ctx = makeCtx()
    stub.click = { scriptTurninAll = true }
    stub.frame(function() ScriptTrackerView.render(ctx) end)
    stub.click = {}
    local ps = ctx.uiState.pendingScriptConsume
    local q = ctx.uiState.pendingScriptConsumeQueue or {}
    check('turnin all: first slot goes live, rest queue', ps ~= nil and #q == 2,
        tostring(ps) .. '/' .. #q)
    check('turnin all: FSM entry shape', ps and ps.bag == 1 and ps.slot == 1
        and ps.source == 'inv' and ps.totalToConsume == 4 and ps.consumedSoFar == 0
        and ps.nextClickAt == 0, ps and (ps.bag .. '/' .. ps.slot .. '/' .. tostring(ps.totalToConsume)))
    check('turnin all: plan total covers every stack', ctx.uiState.scriptTurninPlanTotal == 7,
        tostring(ctx.uiState.scriptTurninPlanTotal))

    -- With a run pending, the verbs disable and the reason prints beside them (kit §3.5).
    local r2 = stub.frame(function() ScriptTrackerView.render(ctx) end)
    check('turnin running: reason printed beside the verbs',
        stub.drew(r2, 'turn-in running'), table.concat(r2.text, '|'))

    -- Legendary-only on a fresh ctx queues just that tier.
    local ctx2 = makeCtx()
    stub.click = { scriptTurninLeg = true }
    stub.frame(function() ScriptTrackerView.render(ctx2) end)
    stub.click = {}
    local ps2 = ctx2.uiState.pendingScriptConsume
    local q2 = ctx2.uiState.pendingScriptConsumeQueue or {}
    check('turnin legendary: one slot, right item', ps2 ~= nil and #q2 == 0
        and ps2.itemName == 'Legendary Script of Planar Power' and ps2.totalToConsume == 2,
        ps2 and tostring(ps2.itemName))
    check('turnin legendary: plan total = 2', ctx2.uiState.scriptTurninPlanTotal == 2,
        tostring(ctx2.uiState.scriptTurninPlanTotal))
end

-- ---------------------------------------------------------------- 4. throw containment
do
    local ctx = makeCtx()
    stub.throwOn = { TableHeadersRow = true }
    local r = stub.frame(function() ScriptTrackerView.render(ctx) end)
    stub.throwOn = {}
    check('throw: contained (window closes itself)', r.ok, r.err)
    check('throw: stacks balanced after a table throw', stub.balanced(r),
        string.format('win=%d child=%d sv=%d sc=%d tbl=%d',
            r.depth.win, r.depth.child, r.depth.sv, r.depth.sc, r.depth.tbl))
end

-- ---------------------------------------------------------------- 5. empty + classic
do
    local ctx = makeCtx({ inventoryItems = {} })
    local r = stub.frame(function() ScriptTrackerView.render(ctx) end)
    -- Names the path now, matching mythicals and augments, rather than stating the absence
    -- and stopping (FIRST_RUN.md W6 rule 2).
    check('empty: no scripts states the absence AND the path',
        r.ok and stub.drew(r, 'No scripts in bags. Loot some and refresh.'), r.err)

    local ctxClassic = makeCtx()
    ctxClassic.layoutConfig.UIMode = 'classic'
    local r2 = stub.frame(function() ScriptTrackerView.render(ctxClassic) end)
    check('classic: renders without the band, balanced', r2.ok and stub.balanced(r2), r2.err)
end

-- ---------------------------------------------------------------- report
print(string.format('\n%d passed, %d failed', pass, fail))
if fail > 0 then os.exit(1) end
