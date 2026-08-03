-- Regression test for lua/itemui/services/dock_state.lua — the bars' data layer.
-- Runs on the exact LuaJIT MQ2Lua is, with a stubbed `mq` host module.
--
-- Why this file exists: dock_state is pure logic over shared state tables, so it is the one
-- part of the bars that CAN be tested without the game — and it is where the worst defect of
-- the feature landed. The loot segment read three uiState fields as numbers when two of them
-- are a string (corpse NAME) and a table (item LIST), so the whole segment reported
-- "corpse 0/0 . 0 taken" for an entire run. Nothing static caught it: it compiles, it lints,
-- and tonumber() on a table is a perfectly legal nil. Only running it catches this class.
--
-- Covers, in order: field-type correctness, the five loot states of mockup 12a, the bags-full
-- false positive, the sell aggregate, the session accumulator's finish edge, the two clocks,
-- and classic-mode inertness.

local repo = os.getenv('COOPT_REPO') or 'C:/Claude/CooptUI'
package.path = repo .. '/lua/?.lua;' .. repo .. '/lua/?/init.lua;' .. package.path

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

-- ---------------------------------------------------------------- host stubs
local now = 100000            -- mq.gettime() is MILLISECONDS
local fakeOsTime = 1700000000 -- os.time() is SECONDS; the two must never be mixed

package.loaded['mq'] = {
    gettime = function() return now end,
    cmd     = function() end,
    cmdf    = function() end,
    delay   = function() end,
    event   = function() end,
    TLO     = { Me = { Name = function() return 'Tester' end } },
}
-- Force the pluginless path so nothing tries to load a DLL.
package.loaded['itemui.utils.coopui_plugin'] = {
    getPlugin = function() return nil end, getIPC = function() return nil end,
    getINI = function() return nil end, getWindow = function() return nil end,
    getCursor = function() return nil end, getItems = function() return nil end,
}
package.loaded['itemui.core.diagnostics'] = {
    getErrorCount = function() return 0 end,
    recordError = function() end,
}

local realOsTime = os.time
os.time = function() return fakeOsTime end  -- luacheck: ignore

local dockState = require('itemui.services.dock_state')
local T = require('itemui.constants').TIMING

-- ---------------------------------------------------------------- fixtures
--- A deps table shaped like app.lua's buildMainLoopDeps, with only what dock_state reads.
local function newDeps(opts)
    opts = opts or {}
    return {
        layoutConfig = { UIMode = opts.mode or 'bars' },
        uiState = opts.uiState or {},
        sellItems = opts.sellItems or {},
        inventoryItems = opts.inventoryItems or {},
        lootMacState = { lastRunning = opts.lootRunning or false },
        sellMacState = { lastRunning = false },
        getLastMerchantState = function() return opts.merchantOpen == true end,
        -- countFreeInvSlots returns 0 (never nil) when the TLO is unreadable — that is the
        -- whole point of the bags-full test below.
        itemOps = { countFreeInvSlots = function() return opts.freeSlots or 0 end },
    }
end

--- Advance past the tick throttle and run one aggregation pass.
local function tick(n)
    for _ = 1, (n or 1) do
        now = now + T.DOCK_TICK_MS + 1
        dockState.tick(now)
    end
end

--- Raise the demand a bar segment would raise, then tick until the slow walks have run.
local function tickWithDemand(n)
    for _ = 1, (n or 4) do
        dockState.requestBags()
        dockState.requestSell()
        now = now + math.max(T.DOCK_SLOW_BAGS_MS, T.DOCK_TICK_MS) + 1
        dockState.tick(now)
    end
end

-- =================================================================
-- 1. Field types: the defect this file was written for
-- =================================================================
do
    local uiState = {
        -- These are the REAL shapes, taken from views/loot_ui.lua's state table:
        lootRunCorpsesLooted = 4,        -- number: the count
        lootRunTotalCorpses  = 9,        -- number
        lootRunCurrentCorpse = 'a decaying skeleton',  -- STRING (name), not an index
        lootRunLootedItems   = { {}, {}, {}, {}, {}, {}, {} },  -- TABLE (list of 7)
        lootRunTotalValue    = 1208000,
        lootRunSkipped       = 3,
    }
    dockState.init(newDeps({ uiState = uiState, lootRunning = true, freeSlots = 40,
                             inventoryItems = { {}, {} } }))
    tickWithDemand()
    local s = dockState.get()

    check('corpse count comes from lootRunCorpsesLooted', s.lootCorpse == 4, s.lootCorpse)
    check('total corpses read', s.lootTotalCorpses == 9, s.lootTotalCorpses)
    check('items taken is #lootRunLootedItems, not tonumber()', s.lootTaken == 7, s.lootTaken)
    check('corpse NAME is not parsed as a number',
        s.lootCorpseName == 'a decaying skeleton', tostring(s.lootCorpseName))
    check('skip count is the run-scoped field', s.lootSkipped == 3, s.lootSkipped)
end

-- =================================================================
-- 2. The five loot states of mockup 12a
-- =================================================================
do
    -- 1 - idle
    dockState.init(newDeps({ uiState = {}, freeSlots = 40, inventoryItems = { {} } }))
    tickWithDemand()
    check('state 1: idle', dockState.get().lootState == 'idle', dockState.get().lootState)

    -- 2 - looting
    dockState.init(newDeps({ lootRunning = true, freeSlots = 40, inventoryItems = { {} },
        uiState = { lootRunCorpsesLooted = 4, lootRunTotalCorpses = 9, lootRunLootedItems = {} } }))
    tickWithDemand()
    check('state 2: looting', dockState.get().lootState == 'looting', dockState.get().lootState)

    -- 3 - decision due. The alert is a TABLE with .itemName and .decision.
    dockState.init(newDeps({ lootRunning = true, freeSlots = 40, inventoryItems = { {} },
        uiState = {
            lootMythicalAlert = { itemName = 'Mythical Faceplate', decision = 'pending', slot = 5 },
            lootMythicalDecisionStartAt = fakeOsTime - 8,   -- SECONDS, 8s ago
        } }))
    tickWithDemand()
    local s = dockState.get()
    check('state 3: decision', s.lootState == 'decision', s.lootState)
    check('decision name', s.lootDecisionName == 'Mythical Faceplate', s.lootDecisionName)
    -- The countdown must be compared in the clock the value was WRITTEN in (os.time seconds).
    -- Subtracting an os.time value from mq.gettime() would be off by ~1000x.
    -- REMAINING, not elapsed. The bar counted UP until 2026-08-03 while the Loot window counted
    -- down from the same start, so one deadline rendered as two numbers running opposite ways
    -- -- and the bar's "2s" read as about-to-expire when it meant two seconds spent of five
    -- minutes. 8 seconds in, 292 left.
    check('decision timer counts DOWN from the five-minute deadline',
        s.lootDecisionSecs == T.LOOT_MYTHICAL_DECISION_SEC - 8, s.lootDecisionSecs)
    check('decision timer uses os.time seconds, not mq.gettime ms (a ms mixup would floor at 0)',
        s.lootDecisionSecs > 0 and s.lootDecisionSecs < T.LOOT_MYTHICAL_DECISION_SEC,
        s.lootDecisionSecs)
    -- The corpse slot the macro writes (loot.mac:676 "Alert slot") flows through to the
    -- snapshot, so the bar's hover tooltip can resolve a real item.
    check('decision slot flows from the alert table', s.lootDecisionSlot == 5, s.lootDecisionSlot)

    -- 3c - an alert with no slot (older INI, or plugin path) must not carry a stale slot
    -- from a previous decision forward.
    dockState.init(newDeps({ lootRunning = true, freeSlots = 40, inventoryItems = { {} },
        uiState = {
            lootMythicalAlert = { itemName = 'Mythical Faceplate', decision = 'pending' },
            lootMythicalDecisionStartAt = fakeOsTime - 8,
        } }))
    tickWithDemand()
    check('decision slot defaults to 0 when the alert has none',
        dockState.get().lootDecisionSlot == 0, dockState.get().lootDecisionSlot)

    -- 3b - a RESOLVED alert must not keep the segment alert forever.
    dockState.init(newDeps({ lootRunning = true, freeSlots = 40, inventoryItems = { {} },
        uiState = { lootMythicalAlert = { itemName = 'Mythical Faceplate', decision = 'loot' } } }))
    tickWithDemand()
    check('a decided alert leaves the decision state',
        dockState.get().lootState ~= 'decision', dockState.get().lootState)

    -- 4 - finished
    dockState.init(newDeps({ freeSlots = 40, inventoryItems = { {} },
        uiState = { lootRunFinished = true, lootRunTotalCorpses = 9, lootRunTotalValue = 1208000 } }))
    tickWithDemand()
    check('state 4: done', dockState.get().lootState == 'done', dockState.get().lootState)

    -- 5 - problem: bags genuinely full DURING a run
    dockState.init(newDeps({ lootRunning = true, freeSlots = 0,
        inventoryItems = { {}, {}, {} },
        uiState = { lootRunLootedItems = {} } }))
    tickWithDemand()
    local p = dockState.get()
    check('state 5: problem when bags really are full mid-run',
        p.lootState == 'problem' and p.lootProblem == 'bags full', p.lootState)
end

-- =================================================================
-- 3. The bags-full FALSE POSITIVE
--    countFreeInvSlots returns 0 when the inventory TLO cannot be read (zoning), so a raw
--    free == 0 is indistinguishable from a full bag. Guarded by requiring a real item count.
-- =================================================================
do
    dockState.init(newDeps({ lootRunning = true, freeSlots = 0,
        inventoryItems = {},                       -- nothing scanned == cannot read
        uiState = { lootRunLootedItems = {} } }))
    tickWithDemand()
    check('free==0 with an unreadable inventory is NOT reported as bags full',
        dockState.get().lootState ~= 'problem', dockState.get().lootProblem)

    -- And a genuinely full bag outside any loot activity must not claim the loot slot.
    dockState.init(newDeps({ lootRunning = false, freeSlots = 0,
        inventoryItems = { {}, {}, {} }, uiState = {} }))
    tickWithDemand()
    check('full bags outside a loot run do not hijack the loot slot',
        dockState.get().lootState == 'idle', dockState.get().lootState)
end

-- =================================================================
-- 4. Sell aggregate + grouping by the rule that decided each item
-- =================================================================
do
    dockState.init(newDeps({ freeSlots = 40, inventoryItems = { {} }, merchantOpen = true,
        sellItems = {
            { willSell = true,  totalValue = 100, sellReason = 'below 1p floor' },
            { willSell = true,  totalValue = 200, sellReason = 'below 1p floor' },
            { willSell = true,  totalValue = 900, sellReason = 'always-sell list', type = 'Augmentation' },
            { willSell = false, inKeep = true },
            { willSell = false, isProtected = true },
            { willSell = true,  totalValue = 50,  inKeep = true, sellReason = 'junk type' },
        } }))
    tickWithDemand()
    local s = dockState.get()
    check('sell count', s.sellCount == 4, s.sellCount)
    check('sell total', s.sellTotal == 1250, s.sellTotal)
    check('keep count', s.keepCount == 2, s.keepCount)
    check('protected count', s.protectCount == 1, s.protectCount)
    check('trust check: keep-list items still queued to sell', s.keepInSellQueue == 1, s.keepInSellQueue)
    check('augment-in-sell-queue count', s.augmentSellCount == 1, s.augmentSellCount)
    check('grouped by reason', #s.sellGroups == 3, #s.sellGroups)
    check('groups sorted by value, biggest first',
        s.sellGroups[1].reason == 'always-sell list', s.sellGroups[1] and s.sellGroups[1].reason)
    check('group counts', s.sellGroups[1].count == 1 and s.sellGroups[1].total == 900)
    check('merchant state read from the cached window flag', s.merchantOpen == true)
end

-- =================================================================
-- 5. Session accumulator — adds on the run-FINISH edge
--    lootRunTotalValue is per-run and is zeroed at run start, so sampling the live counter
--    would lose the previous run entirely.
-- =================================================================
do
    local uiState = { lootRunTotalValue = 0, lootRunLootedItems = {} }
    local deps = newDeps({ uiState = uiState, lootRunning = true, freeSlots = 40,
                           inventoryItems = { {} } })
    dockState.init(deps)
    dockState.resetSession()
    tick(2)
    check('nothing banked while the run is still going', dockState.get().sessionPlat == 0)

    -- run ends with a total on the counter
    uiState.lootRunTotalValue = 1208000
    deps.lootMacState.lastRunning = false
    tick(1)
    check('run total is banked on the finish edge',
        dockState.get().sessionLooted == 1208000, dockState.get().sessionLooted)

    -- a second run starts, which zeroes the per-run counter
    deps.lootMacState.lastRunning = true
    uiState.lootRunTotalValue = 0
    tick(2)
    check('the banked total survives the next run zeroing the counter',
        dockState.get().sessionLooted == 1208000, dockState.get().sessionLooted)

    dockState.recordSold(5000)
    tick(1)
    check('sold value joins the session total', dockState.get().sessionSold == 5000)
    check('session total is looted + sold', dockState.get().sessionPlat == 1213000,
        dockState.get().sessionPlat)
end

-- =================================================================
-- 6. Classic mode does no bar-only work, but the SHARED buffs walk still runs
--    (views/effects.lua consumes it in both modes — that sharing is why the Effects window
--    and the bar do one TLO pass between them instead of two).
-- =================================================================
do
    dockState.init(newDeps({ mode = 'classic', freeSlots = 40, inventoryItems = { {} },
        merchantOpen = true, uiState = { lootRunCorpsesLooted = 4 } }))
    tickWithDemand()
    local s = dockState.get()
    check('classic mode skips the bar-only reads', s.merchantOpen == false, tostring(s.merchantOpen))
    check('classic mode leaves the loot state alone', s.lootCorpse == 0, s.lootCorpse)

    -- getEffects reports whether the shared walk has happened, so a buff-less character is
    -- distinguishable from a cold cache (otherwise effects.lua walks forever alongside it).
    local walked = dockState.getEffects()
    check('getEffects reports walk state as its first return', type(walked) == 'boolean',
        type(walked))
end

-- =================================================================
-- 6b. Aura/song de-duplication (bug: Me.Song(n) reads the profile temp-buff array, which
--     also holds the self-effect an active aura grants, so a single aura was counted once
--     as a song AND once as an aura). Covers both an exact name match and the "<Aura>
--     Effect" suffix EQ commonly uses for the granted temp buff.
-- =================================================================
do
    local function makeAura(name)
        return setmetatable({}, { __call = function() return name end })
    end
    local function makeSongSlot(name, seconds)
        local obj = setmetatable({}, { __call = function() return true end })
        obj.Name = function() return name end
        obj.Duration = { TotalSeconds = function() return seconds end }
        obj.HitCount = function() return 0 end
        return obj
    end

    package.loaded['mq'].TLO.Me = {
        Name = function() return 'Tester' end,
        MaxBuffSlots = function() return 0 end,  -- buff loop is irrelevant to this bug; skip it
        Song = function(i)
            if i == 1 then return makeSongSlot('Aura of the Muse', 60) end        -- exact-name dupe
            if i == 2 then return makeSongSlot('Companion Spirit Effect', 60) end -- "<Aura> Effect" dupe
            if i == 3 then return makeSongSlot("Selo's Consonant Chain", 400) end -- a REAL song
            return nil
        end,
        Aura = function(i)
            if i == 1 then return makeAura('Aura of the Muse') end
            if i == 2 then return makeAura('Companion Spirit') end
            return nil
        end,
    }

    dockState.init(newDeps({ freeSlots = 40, inventoryItems = { {} } }))
    dockState.requestBuffs()
    now = now + T.DOCK_SLOW_BUFFS_MS + 1
    dockState.tick(now)
    local walked, _, songs, auras = dockState.getEffects()
    check('effects walk ran', walked == true, walked)
    check('auraCount keeps both auras', #auras == 2, #auras)
    check('songCount drops the exact-name aura dupe and the "Effect"-suffix dupe',
        #songs == 1, #songs)
    check('the one surviving song is the real one',
        songs[1] and songs[1].name == "Selo's Consonant Chain", songs[1] and songs[1].name)

    local s = dockState.get()
    check('snapshot songCount matches the filtered list', s.songCount == 1, s.songCount)
    check('snapshot auraCount is unaffected', s.auraCount == 2, s.auraCount)
end

-- =================================================================
-- 7. Sell-run surface (phase 4): the bar shows EITHER sell path, and the macro path's
--    vendor income reaches the session total (sell.mac never calls recordSold — its
--    per-item values arrive over IPC into uiState.sellRunSoldItems).
-- =================================================================
do
    -- Batch path: sellMacState.luaRunning with sell_batch's progress fields.
    local deps = newDeps({})
    deps.sellMacState = { lastRunning = false, luaRunning = true, total = 40, current = 12, smoothedFrac = 0.3 }
    dockState.init(deps)
    dockState.resetSession()
    tick()
    local s = dockState.get()
    check('batch sell run sets sellRunning', s.sellRunning == true)
    check('batch progress fields flow through', s.sellRunCurrent == 12 and s.sellRunTotal == 40, s.sellRunCurrent .. '/' .. s.sellRunTotal)
    dockState.recordSold(150)
    tick()
    s = dockState.get()
    check('batch run value is the session.sold delta', s.sellRunValue == 150, s.sellRunValue)

    -- Macro path: lastRunning + getSellProgress + sold-item value list.
    local soldList = { { name = 'A', value = 100 }, { name = 'B', value = 250 } }
    deps = newDeps({ uiState = { sellRunSoldItems = soldList } })
    deps.sellMacState = { lastRunning = true }
    deps.macroBridge = { getSellProgress = function()
        return { running = true, total = 31, current = 5, remaining = 26, smoothedFrac = 0.16 }
    end }
    dockState.init(deps)
    dockState.resetSession()
    tick()
    s = dockState.get()
    check('macro sell run sets sellRunning', s.sellRunning == true)
    check('macro progress fields flow through', s.sellRunCurrent == 5 and s.sellRunTotal == 31, s.sellRunCurrent .. '/' .. s.sellRunTotal)
    check('macro run value sums the IPC sold list', s.sellRunValue == 350, s.sellRunValue)

    -- Finish edge: macro income banks into sessionSold exactly once.
    deps.sellMacState.lastRunning = false
    tick()
    s = dockState.get()
    check('macro finish edge banks vendor income into the session', s.sessionSold == 350, s.sessionSold)
    check('run progress zeroes after the finish', s.sellRunning == false and s.sellRunTotal == 0 and s.sellRunValue == 0,
        tostring(s.sellRunTotal))
    tick()
    s = dockState.get()
    check('the banked income is not double-counted', s.sessionSold == 350, s.sessionSold)
end

-- =================================================================
-- 8. Degraded-state probe (phase 6, mockup 14d): priority order, startup gate, bank age.
-- =================================================================
do
    local T2 = T
    local function healthTick()
        now = now + (T2.DOCK_HEALTH_MS or 30000) + 1
        dockState.tick(now)
    end

    -- Controllable config cache: walkHealth reaches it via a lazy pcall(require), so a
    -- late package.loaded stub is honored. An UNLOADED cache (getCache() == nil, the real
    -- pre-loadConfigCache state) must never report "no rules".
    local testCache = nil
    package.loaded['itemui.config_cache'] = { getCache = function() return testCache end }

    -- Pluginless, unloaded cache, fresh bank: only the pluginless note shows.
    local deps = newDeps({})
    deps.perfCache = { lastBankCacheTime = 0 }
    deps.bankCache = {}
    dockState.init(deps)
    healthTick()
    local s = dockState.get()
    check('degraded: pluginless note; an unloaded cache is not "no rules"',
        s.degraded and s.degraded.id == 'no_plugin', s.degraded and s.degraded.id)

    -- A four-day-old DISK snapshot (bankCache + its persisted timestamp) outranks the
    -- pluginless note. bankCache, not bankItems: the live-scan list only ever fills
    -- alongside a fresh timestamp, so gating on it made this condition unreachable.
    deps.perfCache.lastBankCacheTime = os.time() - 4 * 86400
    deps.bankCache = { {}, {} }
    healthTick()
    s = dockState.get()
    check('degraded: stale bank outranks no-plugin', s.degraded and s.degraded.id == 'stale_bank',
        s.degraded and s.degraded.id)
    check('degraded: bank age in days', s.degraded and s.degraded.days == 4, s.degraded and s.degraded.days)

    -- A LOADED cache with every list empty is "no rules", and it outranks the stale bank.
    testCache = { sell = { lists = { keepContains = {}, protectedTypes = {}, junkContains = {} } } }
    healthTick()
    s = dockState.get()
    check('degraded: empty loaded rules outrank stale bank', s.degraded and s.degraded.id == 'no_rules',
        s.degraded and s.degraded.id)

    -- One entry anywhere clears the no-rules condition.
    testCache.sell.lists.keepContains[1] = 'Legendary'
    healthTick()
    s = dockState.get()
    check('degraded: any rule entry clears no-rules', s.degraded and s.degraded.id == 'stale_bank',
        s.degraded and s.degraded.id)

    -- ---------------------------------------------------------------------------
    -- LESSONS: the two must-know items no hint can reach, riding the same strip.
    --
    -- The property that matters is the ORDERING. Teaching must never displace a real
    -- condition -- a strip that explains the hub list while sell.mac is missing has spent the
    -- one surface that was going to tell you something is broken. So lessons sit below every
    -- degradation, and are only ever seen on a healthy install.
    -- ---------------------------------------------------------------------------
    local hintsSvc = require('itemui.services.hints')
    hintsSvc._reset()

    -- The whole suite runs pluginless, and no_plugin outranks every lesson -- which is the
    -- ordering working, but it also means the lesson branch is unreachable from the default
    -- fixture. dock_state captured this stub TABLE at load, so mutating the field reaches the
    -- upvalue where a late package.loaded swap would not.
    local pluginStub = package.loaded['itemui.utils.coopui_plugin']
    local realGetPlugin = pluginStub.getPlugin
    pluginStub.getPlugin = function() return {} end

    -- Healthy install, nothing user-placed: the hub-list lesson is what is left.
    testCache.sell.lists.keepContains[1] = 'Legendary'
    deps.perfCache.lastBankCacheTime = realOsTime()   -- fresh bank, clears stale_bank
    deps.layoutConfig.UIMode = 'bars'
    deps.layoutConfig.UserPlaced = ''
    healthTick()
    s = dockState.get()
    check('lesson: a healthy bars install teaches the hub list',
        s.degraded and s.degraded.id == 'lesson_hublist', s.degraded and s.degraded.id)
    check('lesson: it carries its lesson id for the one-time dismissal',
        s.degraded and s.degraded.lesson == 'hublist', s.degraded and s.degraded.lesson)

    -- Drag a window: re-tidy outranks the hub list, because it has a real fix attached and
    -- the user has just met the behaviour it explains.
    deps.layoutConfig.UserPlaced = 'bank'
    healthTick()
    s = dockState.get()
    check('lesson: a user-placed window teaches re-tidy first',
        s.degraded and s.degraded.id == 'lesson_retidy', s.degraded and s.degraded.id)

    -- THE ORDERING RULE. Break the install and the lesson must yield immediately. Using
    -- no_rules because it is the condition this block can actually drive -- sellMacPresent is
    -- a module-local set by a disk probe inside walkHealth, not a dep.
    testCache.sell.lists.keepContains[1] = nil
    healthTick()
    s = dockState.get()
    check('lesson: a real problem outranks any teaching',
        s.degraded and s.degraded.id == 'no_rules', s.degraded and s.degraded.id)
    testCache.sell.lists.keepContains[1] = 'Legendary'

    -- No classic-mode assertion here: in classic the aggregation does not run at all, so the
    -- snapshot keeps whatever it last held rather than clearing (the suite's classic-inertness
    -- block covers that). lessonStrip's own bars check is belt-and-braces for the same reason.

    -- The welcome screen owns the first moments; a strip under it would be a second teaching
    -- surface on one frame.
    deps.uiState.setupMode = true
    healthTick()
    s = dockState.get()
    check('lesson: suppressed while the setup wizard is up', s.degraded == nil,
        s.degraded and s.degraded.id)
    deps.uiState.setupMode = false

    -- Dismissed forever, not for the session: once marked, it never returns.
    hintsSvc.markLessonSeen('retidy')
    hintsSvc.markLessonSeen('hublist')
    healthTick()
    s = dockState.get()
    check('lesson: a dismissed lesson does not come back', s.degraded == nil,
        s.degraded and s.degraded.id)
    hintsSvc._reset()
    pluginStub.getPlugin = realGetPlugin
end

os.time = realOsTime  -- luacheck: ignore

print(string.format('\n%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
