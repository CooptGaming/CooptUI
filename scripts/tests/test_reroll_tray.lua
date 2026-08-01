-- 20b tray suite. The mockup's line is "the rule is 10 per roll, so the tray IS the
-- interface and Roll says why it's off", and both halves are pure functions over plain
-- tables, so they can be pinned exactly.
--
-- Worth stating what the tray is compensating for: the 10 is a CLIENT convention. The
-- service's augRoll() takes no arguments, checks nothing, /say-s the command and
-- optimistically trims its own list; the server's answer is never parsed. So the view is
-- the only place that can honestly say what a roll would consume - which is precisely
-- why showing the ten items, rather than a count, matters.

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

local RerollView = require('itemui.views.reroll')
local buildTray = RerollView._buildTray
local blocked = RerollView._rollBlockedReason

local function listOf(...)
    local t = {}
    for _, id in ipairs({ ... }) do t[#t + 1] = { id = id, name = 'Listed ' .. id } end
    return t
end
local function item(id, name, stack)
    return { id = id, name = name or ('Item ' .. id), stackSize = stack }
end

-- ---------------------------------------------------------------- 1. what it takes
do
    local list = listOf(1, 2, 3)
    local inv = { item(1, 'Aug A'), item(99, 'Not listed'), item(2, 'Aug B') }
    local tray = buildTray(nil, list, inv, nil)
    check('tray: only listed items enter', #tray == 2, #tray)
    check('tray: keeps the order it found them', tray[1].name == 'Aug A' and tray[2].name == 'Aug B',
        tray[1] and tray[1].name)
    check('tray: marks where each one is', tray[1].where == 'inv')

    -- Bags before bank, because that is the order the roll's own bank-move pre-flight
    -- consumes them in — the tray must not be a second opinion about what happens.
    local bank = { item(3, 'Aug C') }
    local tray2 = buildTray(nil, list, inv, bank)
    check('tray: bags first, then bank', #tray2 == 3 and tray2[3].name == 'Aug C'
        and tray2[3].where == 'bank', #tray2)

    -- A closed bank contributes nothing: the caller passes nil for the bank list.
    local tray3 = buildTray(nil, list, inv, nil)
    check('tray: a closed bank contributes nothing', #tray3 == 2, #tray3)
end

-- ---------------------------------------------------------------- 2. stacks and the cap
do
    -- A roll consumes ITEMS, not slots: a stack of 4 listed augs is four of the ten.
    local tray = buildTray(nil, listOf(7), { item(7, 'Stacked', 4) }, nil)
    check('tray: a stack counts per unit', #tray == 4, #tray)

    -- Never more than ten, whatever you own — the tray IS the cap.
    local big = {}
    for i = 1, 30 do big[#big + 1] = item(7, 'Stacked') end
    local trayBig = buildTray(nil, listOf(7), big, nil)
    check('tray: never exceeds ten', #trayBig == 10, #trayBig)

    -- The cap holds mid-stack too (the inner loop has its own guard).
    local trayStack = buildTray(nil, listOf(7), { item(7, 'Huge', 500) }, nil)
    check('tray: the cap holds inside a single big stack', #trayStack == 10, #trayStack)

    -- And it does not spill into the bank once full.
    local trayFull = buildTray(nil, listOf(7, 8), { item(7, 'Ten', 10) }, { item(8, 'Bank one') })
    check('tray: a full tray takes nothing from the bank', #trayFull == 10
        and trayFull[10].where == 'inv', #trayFull)
end

-- ---------------------------------------------------------------- 3. why Roll is off
do
    local function trayOf(n)
        local t = {}
        for i = 1, n do t[i] = { name = 'x', id = i, where = 'inv' } end
        return t
    end

    check('blocked: a full tray is not blocked',
        blocked(nil, trayOf(10), false, nil, true, 0) == nil)

    local r = blocked(nil, trayOf(7), false, nil, true, 0)
    check('blocked: says how many more, not just "not enough"',
        r and r:find('3 more needed', 1, true) ~= nil, r)

    -- The common cause of a short tray is a bank you have not opened, and the count alone
    -- cannot show you that. Naming the fix is the point of 20b.
    local rClosed = blocked(nil, trayOf(7), false, nil, false, 0)
    check('blocked: a closed bank names the fix, not just the shortfall',
        rClosed and rClosed:find('open your bank', 1, true) ~= nil, rClosed)

    -- A fetch in flight outranks the count: it is what is happening right now.
    local rMoving = blocked(nil, trayOf(10), true,
        { nextIndex = 3, items = { 1, 2, 3, 4, 5 } }, true, 0)
    check('blocked: an in-flight bank fetch reports its progress',
        rMoving and rMoving:find('3 of 5', 1, true) ~= nil, rMoving)
    check('blocked: the fetch outranks a full tray',
        blocked(nil, trayOf(10), true, { nextIndex = 1, items = { 1 } }, true, 0) ~= nil)

    -- Ten in hand but bank items counted with the bank shut: still honest about it.
    local rNeedBank = blocked(nil, trayOf(10), false, nil, false, 4)
    check('blocked: a shut bank with items in it is stated',
        rNeedBank and rNeedBank:find('bank has to be open', 1, true) ~= nil, rNeedBank)

    -- Every reason is lowercase prose, not a code or a shout: it prints inline beside a
    -- greyed button, where a sentence reads and a label does not.
    for _, msg in ipairs({ r, rClosed, rMoving, rNeedBank }) do
        check('blocked: "' .. tostring(msg) .. '" reads as a sentence',
            type(msg) == 'string' and msg == msg:gsub('^%u', string.lower) and #msg > 8, msg)
    end
end

-- ---------------------------------------------------------------- report
print(string.format('\n%d passed, %d failed', pass, fail))
if fail > 0 then os.exit(1) end
