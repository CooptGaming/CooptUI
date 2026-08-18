-- Dream wave 1 suite - stagecraft (pure math), dream_log (run-edge ring), and the
-- River window (stub-rendered frames, balanced stacks). The experiments contract is
-- pinned here too: the registry treats an experimental module's absent enable key as
-- OFF, which is the whole "does not exist until switched on" guarantee.

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

-- ---------------------------------------------------------------- stagecraft (pure)
do
    local sc = require('itemui.services.stagecraft')
    sc._resetForTests()

    check('quiet start: no ding', sc.dingStrip(0) == nil and not sc.hasDing())

    -- AA: first observation is a baseline, never an event.
    sc.observeAA(1000, 2751)
    check('first AA observation never dings', not sc.hasDing())
    sc.observeAA(2000, 2752)
    check('AA increase dings', sc.hasDing())
    local t, tAlpha, color = sc.dingStrip(2000)
    check('ding starts at t=0, eased dark', t ~= nil and t < 0.01 and tAlpha < 0.01, t)
    check('AA ding is blue', color == sc.DING_BLUE)
    local t2, a2 = sc.dingStrip(2000 + sc.DING_MS / 2)
    check('mid-pass: t=0.5, full alpha', t2 and math.abs(t2 - 0.5) < 0.01 and a2 == 1.0, t2)
    check('pass ends: strip gone', sc.dingStrip(2000 + sc.DING_MS + 1) == nil)
    check('queue drained', not sc.hasDing())

    -- AA decrease moves the baseline silently.
    sc.observeAA(3000, 2000)
    check('AA decrease never dings', not sc.hasDing())

    -- Loot falling edge dings green; rising edge does not.
    sc.observeLootRunning(4000, false)
    sc.observeLootRunning(4100, true)
    check('loot start never dings', not sc.hasDing())
    sc.observeLootRunning(5000, false)
    local _, _, c2 = sc.dingStrip(5000)
    check('loot finish dings green', c2 == sc.DING_GREEN)
    sc._resetForTests()

    -- Chaining: the second ding starts when the first ends.
    sc.noteDing(1000, sc.DING_BLUE)
    sc.noteDing(1100, sc.DING_GREEN)
    local tEnd = 1000 + sc.DING_MS
    local tb = sc.dingStrip(tEnd - 1)
    check('first ding still playing at its end-1', tb ~= nil)
    local tc, _, cc = sc.dingStrip(tEnd + 1)
    check('second ding took over after the first', tc ~= nil and cc == sc.DING_GREEN, tc)
    sc._resetForTests()

    -- Breathing: phase 0 = base, phase half = the target mix; problem is slower.
    local base = { 0.1, 0.2, 0.3, 0.9 }
    local at0 = sc.breathColor(0, base, 'decision')
    check('breath phase 0 is the base', math.abs(at0[1] - 0.1) < 0.001 and at0[4] == 0.9)
    local atHalf = sc.breathColor(1200, base, 'decision')
    check('breath phase half reaches the target', math.abs(atHalf[1] - 0.15) < 0.001, atHalf[1])
    local pHalf = sc.breathColor(1800, base, 'problem')
    check('problem breathes on its own period', math.abs(pHalf[1] - 0.38) < 0.001, pHalf[1])
end

-- ---------------------------------------------------------------- dream_log
do
    local log = require('itemui.services.dream_log')
    local subs = {}
    local fakeBridge = {
        subscribe = function(ev, cb) subs[ev] = cb end,
    }
    local clock = 0
    local fakeUi = {
        lootRunCorpsesLooted = 6, lootRunTotalValue = 2108,
        lootRunLootedItems = { {}, {}, {} }, lootRunBestItemName = "Voice of Cognizance Rk. II",
        lootRunBestItemValue = 2100, lootRunSkipped = 2,
    }
    log.init({ macroBridge = fakeBridge, uiState = fakeUi, gettime = function() return clock end })
    check('log subscribed to the bridge', log.isSubscribed()
        and subs['loot:started'] ~= nil and subs['loot:complete'] ~= nil
        and subs['sell:started'] ~= nil and subs['sell:complete'] ~= nil)

    clock = 1000
    subs['loot:started']()
    clock = 2000
    subs['loot:complete']()
    local rows = log.getRows()
    check('two rows, newest first', #rows == 2 and rows[1].kind == 'loot_end' and rows[2].kind == 'loot_start')
    check('fresh loot row still pending', rows[1].pending == true)

    clock = 6000  -- past the settle window: getRows finalizes from uiState
    rows = log.getRows()
    check('settled loot row captured tallies', rows[1].pending == nil
        and rows[1].corpses == 6 and rows[1].items == 3
        and rows[1].best == "Voice of Cognizance Rk. II" and rows[1].skipped == 2,
        tostring(rows[1].corpses) .. '/' .. tostring(rows[1].items))

    subs['sell:complete']({ failedCount = 3 })
    rows = log.getRows()
    check('sell row carries the payload', rows[1].kind == 'sell_end' and rows[1].failed == 3)
    log._resetForTests()
    check('reset empties the ring', #log.getRows() == 0)

    -- Manual loot: the log registers its OWN "You have looted" event (field round 1 -
    -- the bridge events are macro edges and a hand-looted corpse produced nothing).
    local lootHandlers = {}
    log.init({ macroBridge = fakeBridge, uiState = fakeUi, gettime = function() return clock end,
        mqEvent = function(name, pattern, cb) lootHandlers[#lootHandlers + 1] = { name = name, pattern = pattern, cb = cb } end })
    check('loot-line event registered', #lootHandlers == 1
        and lootHandlers[1].pattern:find('You have looted', 1, true) ~= nil)
    lootHandlers[1].cb('--You have looted a Rusty Dagger.--')
    rows = log.getRows()
    check('hand-looted row parsed (article kept)', rows[1].kind == 'looted'
        and rows[1].name == 'a Rusty Dagger', rows[1].name)
    lootHandlers[1].cb('no such line')
    check('non-matching line ignored', #log.getRows() == 1)

    -- Demo rows are honestly labeled.
    log.demo()
    rows = log.getRows()
    local sawDemo = false
    for _, r in ipairs(rows) do if r.demo then sawDemo = true end end
    check('demo rows carry the demo flag', sawDemo and #rows == 4, #rows)
    log._resetForTests()
end

-- ---------------------------------------------------------------- stagecraft demo
do
    local sc = require('itemui.services.stagecraft')
    sc._resetForTests()
    sc.demoStart(1000)
    check('demo queues dings', sc.hasDing())
    -- Field round 2: the dings had played before the eye left the chat line. The
    -- first pass now waits a beat, and the pair repeats.
    check('demo dings wait a beat', sc.dingStrip(1000) == nil and sc.dingStrip(1800) == nil)
    local t1, _, c1 = sc.dingStrip(2000)
    check('first pass playing blue after the beat', t1 ~= nil and c1 == sc.DING_BLUE)
    local t2, _, c2 = sc.dingStrip(5400)
    check('second pass replays blue later', t2 ~= nil and c2 == sc.DING_BLUE, t2)
    check('demo breathes while fresh', sc.demoBreathing(2000))
    check('demo breath expires', not sc.demoBreathing(9001))
    check('expired demo stays off', not sc.demoBreathing(5000))
    sc._resetForTests()
end

-- ---------------------------------------------------------------- registry contract
do
    local registry = require('itemui.core.registry')
    registry.init({ layoutConfig = { UIMode = 'bars' }, companionWindowOpenedAt = {} })
    registry.register({ id = 'expProbe', label = 'Probe', experimental = true,
                        enableKey = 'ShowExpProbe', render = function() end })
    local listed = {}
    for _, m in ipairs(registry.getEnabledModules()) do listed[m.id] = true end
    check('experimental module with absent key is NOT offered', not listed.expProbe)
    registry.init({ layoutConfig = { UIMode = 'bars', ShowExpProbe = 1 }, companionWindowOpenedAt = {} })
    listed = {}
    for _, m in ipairs(registry.getEnabledModules()) do listed[m.id] = true end
    check('experimental module with key=1 is offered', listed.expProbe == true)
end

-- ---------------------------------------------------------------- the River window
do
    local theme = require('itemui.utils.theme')
    local registry = require('itemui.core.registry')
    local uiState = require('itemui.state').uiState
    local sessionRecord = require('itemui.services.session_record')
    local dreamLog = require('itemui.services.dream_log')
    local RiverView = require('itemui.views.dream_river')

    registry.init({ layoutConfig = { UIMode = 'bars', ShowDreamRiver = 1 }, companionWindowOpenedAt = {} })
    registry.setWindowState('dreamRiver', true, true)

    sessionRecord._resetForTests()
    local entries = sessionRecord._entriesForTests()
    entries[#entries + 1] = { uid = 1, name = "Gem of Pious Shielding", cat = "aug",
        state = "sorted", choice = "reroll", reason = "on the reroll list", at = 100, value = 50 }
    entries[#entries + 1] = { uid = 2, name = "Mythical Earring of Dispersion", cat = "mythic",
        state = "call", at = 200, value = 9000 }
    dreamLog._resetForTests()
    dreamLog._pushForTests({ at = 150, kind = "loot_end", corpses = 6, items = 12,
        best = "Voice of Cognizance Rk. II", skipped = 0 })

    local taken = 0
    uiState.lootMythicalAlert = { itemName = "Mythical Suffersphere", decision = "pending" }
    local ctx = {
        theme = theme,
        layoutConfig = { UIMode = 'bars', ShowDreamRiver = 1 },
        uiState = uiState,
        scheduleLayoutSave = function() end,
        mythicalTake = function() taken = taken + 1 end,
        mythicalPass = function() end,
    }

    local function frame()
        return stub.frame(function() RiverView.render(ctx) end)
    end

    local r = frame()
    check('river frame renders balanced', r.ok, r.err)
    check('pending mythical row drawn', stub.drew(r, 'Mythical Suffersphere'))
    check('call-list row drawn', stub.drew(r, 'Mythical Earring of Dispersion'))
    check('run header drawn with tallies', stub.drew(r, '6 corpses'))
    check('best-of-run line drawn', stub.drew(r, 'Voice of Cognizance Rk. II'))
    check('sorted entry drawn with its reason', stub.drew(r, 'Gem of Pious Shielding'))

    -- The Take chip routes to the existing handler.
    stub.click['Take##RiverMythTake'] = true
    r = frame()
    stub.click['Take##RiverMythTake'] = nil
    check('river Take frame balanced', r.ok, r.err)
    check('Take routed to ctx.mythicalTake', taken == 1, taken)

    -- Day card toggles on and renders the record's numbers.
    stub.click['day card##RiverDayCard'] = true
    r = frame()
    stub.click['day card##RiverDayCard'] = nil
    check('day card frame balanced', r.ok, r.err)
    check('day card shows best take', stub.drew(r, 'best take'))

    -- Throw injection: a poisoned theme call costs the frame, never the stacks.
    local savedMuted = theme.TextMuted
    theme.TextMuted = function() error('boom') end
    r = frame()
    theme.TextMuted = savedMuted
    check('injected throw stays contained', r.ok, r.err)

    uiState.lootMythicalAlert = nil
    sessionRecord._resetForTests()
    dreamLog._resetForTests()
end

print(string.format('%d passed, %d failed', pass, fail))
if fail > 0 then os.exit(1) end
