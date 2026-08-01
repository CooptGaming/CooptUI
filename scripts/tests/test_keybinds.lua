-- Keybind suite (spec §10). The approved set is ctrl+shift+<key>, chosen because a live
-- /bind eqlist dump showed every key in the design's original proposal was already taken
-- by EQ itself. What matters here:
--
--   1. Every -down command is wrapped in /timed 1. This is not style: MQ2CustomBinds runs
--      its command on the keyboard-input path, and one field build crashes mq2lua from
--      there. A bind that skips the wrapper is a client crash, so it is asserted.
--   2. The CSV round-trips, including the UNBOUND state (empty combo), which is distinct
--      from absent (absent = take the default).
--   3. Nothing fires inline: each bind's command enqueues onto the dock action queue.
--   4. The pair toggle opens both halves or closes whichever are open.

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
local mqStub = stub.newMq()
package.loaded['mq'] = mqStub
package.loaded['itemui.core.diagnostics'] = {
    getErrorCount = function() return 0 end, recordError = function() end,
}

local keybinds = require('itemui.utils.keybinds')
local registry = require('itemui.core.registry')

-- mq.cmd only records inside stub.frame; wrap bare calls so the recorder is live.
local function commandsFrom(fn)
    local r = stub.frame(fn)
    return r.commands
end

-- ---------------------------------------------------------------- 1. the set itself
do
    check('set: eleven binds (8 windows/pair + 3 presets)', #keybinds.BINDS == 11, #keybinds.BINDS)
    local seenBind, seenId = {}, {}
    local dupBind, dupId = nil, nil
    for _, b in ipairs(keybinds.BINDS) do
        if seenBind[b.bind] then dupBind = b.bind end
        if seenId[b.id] then dupId = b.id end
        seenBind[b.bind], seenId[b.id] = true, true
    end
    check('set: MQ bind names are unique', dupBind == nil, dupBind)
    check('set: ids are unique', dupId == nil, dupId)
    check('set: defaults are all ctrl+shift (the audited scheme)', (function()
        for _, b in ipairs(keybinds.BINDS) do
            if not b.default:lower():find('^ctrl%+shift%+') then return false end
        end
        return true
    end)())
    check('set: defaults do not collide with each other', #keybinds.conflicts() == 0,
        (function()
            local out = {}
            for _, c in ipairs(keybinds.conflicts()) do out[#out + 1] = c.combo end
            return table.concat(out, ',')
        end)())
    check('set: avoids the two taken ctrl+shift combos (F and S)', (function()
        for _, b in ipairs(keybinds.BINDS) do
            local k = b.default:lower()
            if k == 'ctrl+shift+f' or k == 'ctrl+shift+s' then return false end
        end
        return true
    end)())
    check('set: every bind fires an /itemui subcommand', (function()
        for _, b in ipairs(keybinds.BINDS) do
            if not b.cmd:find('^/itemui ') then return false end
        end
        return true
    end)())
end

-- ---------------------------------------------------------------- 2. /timed 1 wrapper
do
    keybinds._resetForTests()
    local cmds = commandsFrom(function() keybinds.applyAll() end)
    local setCmds, bindCmds, unwrapped = 0, 0, {}
    for _, c in ipairs(cmds) do
        if c:find('/custombind set ', 1, true) then
            setCmds = setCmds + 1
            -- The wrapper must sit between the bind name and the command.
            if not c:find('-down /timed 1 /itemui', 1, true) then unwrapped[#unwrapped + 1] = c end
        elseif c:find('/bind ', 1, true) then
            bindCmds = bindCmds + 1
        end
    end
    check('apply: one /custombind set per bind', setCmds == #keybinds.BINDS, setCmds)
    check('apply: one /bind per bind', bindCmds == #keybinds.BINDS, bindCmds)
    check('apply: EVERY down-command is /timed 1 wrapped (mq2lua crash path)',
        #unwrapped == 0, table.concat(unwrapped, ' | '))
    check('apply: creates the bind name first (/custombind add)', (function()
        for _, c in ipairs(cmds) do
            if c:find('/custombind add coopt_', 1, true) then return true end
        end
        return false
    end)())
end

-- ---------------------------------------------------------------- 3. CSV round trip
do
    keybinds._resetForTests()
    local csv = keybinds.getCSV()
    check('csv: contains every id', (function()
        for _, b in ipairs(keybinds.BINDS) do
            if not csv:find(b.id .. ':', 1, true) then return false end
        end
        return true
    end)(), csv)

    keybinds.set('equipment', 'Ctrl Shift J')
    check('set: normalizes to canonical form', keybinds.get('equipment') == 'ctrl+shift+J',
        keybinds.get('equipment'))
    local csv2 = keybinds.getCSV()
    keybinds._resetForTests()
    check('csv: defaults restored after reset', keybinds.get('equipment') == 'ctrl+shift+E',
        keybinds.get('equipment'))
    keybinds.setFromCSV(csv2)
    check('csv: round-trips a custom combo', keybinds.get('equipment') == 'ctrl+shift+J',
        keybinds.get('equipment'))

    -- UNBOUND is a real state and must survive the trip - distinct from absent.
    keybinds.set('aa', '')
    check('unbound: empty combo stored', keybinds.get('aa') == '', keybinds.get('aa'))
    local csv3 = keybinds.getCSV()
    keybinds._resetForTests()
    keybinds.setFromCSV(csv3)
    check('unbound: empty survives the CSV (not re-defaulted)', keybinds.get('aa') == '',
        keybinds.get('aa'))
    local cmds = commandsFrom(function() keybinds.apply('aa') end)
    check('unbound: applies as an explicit clear', (function()
        for _, c in ipairs(cmds) do
            if c:find('/bind coopt_aa clear', 1, true) then return true end
        end
        return false
    end)(), table.concat(cmds, ' | '))

    -- A CSV written before a bind existed must not leave that bind nil.
    keybinds._resetForTests()
    keybinds.setFromCSV('equipment:ctrl+shift+J')
    check('csv: a bind missing from an older CSV takes its default',
        keybinds.get('preset3') == 'ctrl+shift+F3', keybinds.get('preset3'))
    check('csv: unknown ids are ignored, not stored', (function()
        keybinds.setFromCSV('bogus:ctrl+shift+Z,equipment:ctrl+shift+E')
        return keybinds.getCSV():find('bogus') == nil
    end)())

    keybinds._resetForTests()
    keybinds.set('aa', 'ctrl+shift+E')  -- same as equipment
    check('conflicts: a duplicated combo is reported', #keybinds.conflicts() == 1,
        #keybinds.conflicts())
    keybinds._resetForTests()
end

-- ---------------------------------------------------------------- 4. commands enqueue
do
    local commands = require('itemui.commands')
    local uiState = { dockPresetNames = { 'Bag session', 'Farming', 'Merchant run' } }
    registry.init({ layoutConfig = {}, companionWindowOpenedAt = {} })
    for _, id in ipairs({ 'equipment', 'effects', 'reroll', 'mythicals', 'aa', 'bank',
                          'itemDisplay', 'augmentUtility' }) do
        registry.register({ id = id, label = id, render = function() end })
    end
    commands.init({ uiState = uiState, layoutConfig = {} })

    local function lastAction()
        local q = uiState.dockActionQueue
        return q and q[#q]
    end

    uiState.dockActionQueue = nil
    commands.handleCommand('window', 'equipment')
    local a = lastAction()
    check('cmd window: enqueues a toggle, does not act inline',
        a and a.kind == 'window' and a.id == 'equipment' and a.toggle == true,
        a and (a.kind .. '/' .. tostring(a.id)))

    uiState.dockActionQueue = nil
    commands.handleCommand('window', 'nosuchwindow')
    check('cmd window: an unknown id enqueues nothing',
        uiState.dockActionQueue == nil or #uiState.dockActionQueue == 0)

    uiState.dockActionQueue = nil
    commands.handleCommand('pair', 'idau')
    a = lastAction()
    check('cmd pair: enqueues the pair action', a and a.kind == 'pair' and a.id == 'idau',
        a and a.kind)

    uiState.dockActionQueue = nil
    commands.handleCommand('preset', '2')
    a = lastAction()
    check('cmd preset: resolves position -> the NAME the drain wants',
        a and a.kind == 'preset' and a.name == 'Farming', a and tostring(a.name))

    uiState.dockActionQueue = nil
    commands.handleCommand('preset', '9')
    check('cmd preset: out of range enqueues nothing',
        uiState.dockActionQueue == nil or #uiState.dockActionQueue == 0)

    -- Every bind's command must actually dispatch. Parse the command string the way MQ
    -- will and run it - a typo in BINDS.cmd is otherwise invisible until someone presses
    -- the key in game.
    for _, b in ipairs(keybinds.BINDS) do
        uiState.dockActionQueue = nil
        local parts = {}
        for w in b.cmd:gmatch('%S+') do parts[#parts + 1] = w end
        table.remove(parts, 1)   -- drop "/itemui"
        -- NOT `table.unpack and table.unpack(parts) or unpack(parts)`: an and/or
        -- expression truncates a multi-value call to ONE value, so only the subcommand
        -- would arrive and every window/preset row would look broken.
        local unpackFn = table.unpack or unpack
        commands.handleCommand(unpackFn(parts))
        local q = uiState.dockActionQueue
        local ok = (q and #q > 0)
        -- "inventory" toggles the hub through shouldDraw rather than the queue.
        if b.id == 'inventory' then ok = true end
        check('cmd dispatch: ' .. b.id .. ' (' .. b.cmd .. ') does something', ok,
            b.cmd)
    end
end

-- ---------------------------------------------------------------- 5. pair semantics
-- The bar chip and ctrl+shift+D both queue { kind = "pair", id = "idau" }, so the drain
-- is the single definition of what "toggle the pair" means. Exercised here through the
-- registry the drain would act on.
do
    registry.init({ layoutConfig = {}, companionWindowOpenedAt = {} })
    for _, id in ipairs({ 'itemDisplay', 'augmentUtility' }) do
        if not registry.isRegistered(id) then
            registry.register({ id = id, label = id, render = function() end })
        end
        if registry.isOpen(id) then registry.toggleWindow(id) end
    end

    -- Mirror of the drain body in services/main_loop.lua.
    local function drainPair()
        local idOpen, auOpen = registry.isOpen('itemDisplay'), registry.isOpen('augmentUtility')
        if idOpen or auOpen then
            if idOpen then registry.toggleWindow('itemDisplay') end
            if auOpen then registry.toggleWindow('augmentUtility') end
        else
            for _, wid in ipairs({ 'itemDisplay', 'augmentUtility' }) do
                if not registry.isOpen(wid) then registry.toggleWindow(wid) end
            end
        end
    end

    drainPair()
    check('pair: neither open -> both open',
        registry.isOpen('itemDisplay') and registry.isOpen('augmentUtility'))
    drainPair()
    check('pair: both open -> both closed',
        not registry.isOpen('itemDisplay') and not registry.isOpen('augmentUtility'))
    registry.toggleWindow('itemDisplay')   -- half open
    drainPair()
    check('pair: one open -> that one closes (never leaves a half up)',
        not registry.isOpen('itemDisplay') and not registry.isOpen('augmentUtility'))
end

-- ---------------------------------------------------------------- report
print(string.format('\n%d passed, %d failed', pass, fail))
if fail > 0 then os.exit(1) end
