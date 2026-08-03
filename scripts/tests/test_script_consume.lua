-- The script-consume FSM: main_loop's handleScriptConsume.
--
-- WHY THIS FILE EXISTS. Turning scripts in works only with the native bags open, because
-- /itemnotify addresses a UI slot rather than an inventory slot. With them closed every command
-- silently fails -- and the FSM reported "Added 18 to Alt Currency" anyway, because it advanced
-- on `gotConfirm or timedOut` and then printed the count it had ISSUED rather than the count
-- chat had CONFIRMED. It also decremented CoOpt's cached stack at issue time, so a failed run
-- left the UI believing the character owned fewer scripts than it did.
--
-- Nothing caught it: the plan-construction test covers pendingScriptConsume being built
-- correctly, and NO suite required main_loop at all. A success path that cannot tell success
-- from silence is the exact class this file exists to pin.

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

-- ---------------------------------------------------------------- host stubs
-- main_loop pulls in the views, so the ImGui stub has to be installed even though nothing
-- here renders a frame.
local stub = require('imgui_stub')
stub.install()

local issued = {}
local STACK = 99          -- the TLO always reports stock left; that is the point of the bug

package.loaded['mq'] = {
    gettime = function() return 0 end,
    cmd = function() end,
    cmdf = function(fmt, ...) issued[#issued + 1] = string.format(fmt, ...) end,
    delay = function() end,
    event = function() end,
    TLO = {
        Me = {
            Name = function() return 'Tester' end,
            -- The guard the FSM uses reads through the TLO, which answers correctly whether
            -- or not the bag's WINDOW is open. That is precisely why it cannot catch this.
            Inventory = function() return { Item = function() return { Stack = function() return STACK end } end } end,
            Bank = function() return { Item = function() return { Stack = function() return STACK end } end } end,
        },
    },
}
package.loaded['itemui.utils.coopui_plugin'] = {
    getPlugin = function() return nil end, getIPC = function() return nil end,
    getINI = function() return nil end, getWindow = function() return nil end,
    getCursor = function() return nil end, getItems = function() return nil end,
}
package.loaded['itemui.core.diagnostics'] = {
    getErrorCount = function() return 0 end, recordError = function() end,
}

local mainLoop = require('itemui.services.main_loop')
local T = require('itemui.constants').TIMING

-- ---------------------------------------------------------------- fixtures
local statuses, decrements

--- A deps table with only what handleScriptConsume reads.
local function newDeps(uiState)
    statuses, decrements = {}, {}
    return {
        uiState = uiState,
        setStatusMessage = function(m) statuses[#statuses + 1] = m end,
        itemOps = {
            reduceStackOrRemoveBySlot = function(b, s, n) decrements[#decrements + 1] = { b, s, n } end,
            reduceStackOrRemoveBySlotBank = function(b, s, n) decrements[#decrements + 1] = { b, s, n } end,
        },
        storage = nil,      -- finishConsume guards on it; nil keeps disk out of the test
        inventoryItems = {}, sellItems = {}, bankItems = {},
    }
end

local function newPlan(total)
    return { source = 'inv', bag = 3, slot = 1, totalToConsume = total,
             consumedSoFar = 0, nextClickAt = 0, verifiedFromChat = 0 }
end

local function lastStatus() return statuses[#statuses] end

-- Advance the FSM. `now` drives the confirm timeout.
local function step(now) mainLoop._handleScriptConsumeForTests(now) end

--- Run the clock forward until the plan finishes or we give up. Stepping in fixed increments
--- rather than hand-picking timestamps: the FSM interleaves a delay (SCRIPT_CONSUME_DELAY_MS)
--- with a timeout (SCRIPT_CONSUME_CONFIRM_TIMEOUT_MS), so hand-rolled steps land between the
--- two and assert on a half-finished state, which is exactly what they did on the first run.
local function runUntilDone(uiState, startT)
    local t = startT or 0
    for _ = 1, 300 do
        if not uiState.pendingScriptConsume then return t end
        step(t)
        t = t + 60
    end
    return t
end

-- =================================================================
-- 1. THE REGRESSION. Bags closed: every command fails silently, chat confirms nothing.
-- =================================================================
do
    issued = {}
    local uiState = { pendingScriptConsume = newPlan(18) }
    mainLoop.init(newDeps(uiState))

    step(0)                                   -- issues #1, starts waiting
    check('issues the notify', #issued == 1, table.concat(issued, '|'))
    check('nothing is decremented before a confirmation', #decrements == 0, #decrements)

    -- Time passes, no "You gained 1 alternate currency" ever arrives.
    runUntilDone(uiState, 60)

    check('stops early instead of grinding the whole plan',
        uiState.pendingScriptConsume == nil, tostring(uiState.pendingScriptConsume))
    check('does not claim to have added anything',
        lastStatus() and lastStatus():find('added 0 of 18', 1, true) ~= nil, lastStatus())
    check('names the likely cause rather than just failing',
        lastStatus() and lastStatus():find('open your bags', 1, true) ~= nil, lastStatus())
    check('the cache is never touched without a confirmation', #decrements == 0, #decrements)
    check('and it stopped well short of the plan', #issued < 18, #issued)
end

-- =================================================================
-- 2. The happy path still completes and still reports the real number.
-- =================================================================
do
    issued = {}
    local uiState = { pendingScriptConsume = newPlan(3) }
    local deps = newDeps(uiState)
    mainLoop.init(deps)

    local t = 0
    for _ = 1, 3 do
        step(t)                                        -- issue
        uiState.pendingScriptConsume.verifiedFromChat =
            (uiState.pendingScriptConsume.verifiedFromChat or 0) + 1   -- chat confirms it
        t = t + 1
        step(t)                                        -- consume the confirmation
        t = t + T.SCRIPT_CONSUME_DELAY_MS + 1
    end

    check('a fully confirmed run finishes', uiState.pendingScriptConsume == nil,
        tostring(uiState.pendingScriptConsume))
    check('reports the confirmed total', lastStatus() == 'Added 3 to Alt Currency.', lastStatus())
    check('decrements once per CONFIRMED item', #decrements == 3, #decrements)
end

-- =================================================================
-- 3. Partial: some land, some do not. The report must say both numbers.
-- =================================================================
do
    issued = {}
    local uiState = { pendingScriptConsume = newPlan(4) }
    mainLoop.init(newDeps(uiState))

    -- First one confirms.
    step(0)
    uiState.pendingScriptConsume.verifiedFromChat = 1
    step(1)
    check('a confirmation resets the unconfirmed run',
        (uiState.pendingScriptConsume or {}).unconfirmedRun == 0,
        (uiState.pendingScriptConsume or {}).unconfirmedRun)
    check('one decrement so far', #decrements == 1, #decrements)

    -- Then the bags close, so to speak: nothing else is ever confirmed.
    runUntilDone(uiState, T.SCRIPT_CONSUME_DELAY_MS + 2)

    check('partial run stops', uiState.pendingScriptConsume == nil,
        tostring(uiState.pendingScriptConsume))
    check('partial run reports what actually landed',
        lastStatus() and lastStatus():find('added 1 of 4', 1, true) ~= nil, lastStatus())
    check('and decremented only the confirmed one', #decrements == 1, #decrements)
end

-- =================================================================
-- 4. The stack-ran-out exit reports confirmed, not issued.
-- =================================================================
do
    issued = {}
    local uiState = { pendingScriptConsume = newPlan(5) }
    mainLoop.init(newDeps(uiState))

    step(0)
    uiState.pendingScriptConsume.verifiedFromChat = 1
    step(1)

    STACK = 0                                   -- the item is gone from under us
    step(T.SCRIPT_CONSUME_DELAY_MS + 2)
    STACK = 99

    check('depleted exit finishes', uiState.pendingScriptConsume == nil,
        tostring(uiState.pendingScriptConsume))
    check('depleted exit reports the CONFIRMED count',
        lastStatus() and lastStatus():find('Added 1 to Alt Currency', 1, true) ~= nil, lastStatus())
end

print(string.format('\n%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
