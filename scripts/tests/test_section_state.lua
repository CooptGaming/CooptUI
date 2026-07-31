-- Section-state tests (windows pass §6): per-character collapsible memory.
--
-- Proves: defaults honoured with an empty store; only deviations persist (CSV of flipped
-- keys); round-trip through the real serializer + the real parseSectionsMatching; toggles
-- made before the char name resolves are held and win over the file once it does; and a
-- second character gets its own file.

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

-- mq stub whose Me.Name is controllable (the service resolves the char lazily).
local charName = nil
local mqStub = stub.newMq()
mqStub.TLO = { Me = { Name = function() return charName end } }
package.loaded['mq'] = mqStub

local sectionState = require('itemui.services.section_state')
local layoutIO = require('itemui.utils.layout_io')

-- In-memory "disk": path -> content, plus a real-file bridge for parseSectionsMatching
-- (it reads via io.open, so serve it from a scratch temp file).
local files = {}
local tmpBase = os.getenv('TEMP') or '.'
local function diskPath(char) return tmpBase .. '/coopt_test_sections_' .. char .. '.ini' end

local deps = {
    getCharStoragePath = function(char, file) return diskPath(char) end,
    parseSectionsMatching = layoutIO.parseSectionsMatching,
    safeWrite = function(path, content)
        files[path] = content
        local fh = io.open(path, 'w')
        if fh then fh:write(content); fh:close() end
        return true
    end,
}

local function cleanup()
    for _, c in ipairs({ 'Testchar', 'Otherchar' }) do
        os.remove(diskPath(c))
    end
end
cleanup()

-- ---------------------------------------------------------------- defaults, no store
do
    sectionState.init(deps)
    charName = 'Testchar'
    check('default open honoured', sectionState.isOpen('ItemDisplay', 'AllStats', true) == true)
    check('default closed honoured', sectionState.isOpen('ItemDisplay', 'SpellData', false) == false)
end

-- ---------------------------------------------------------------- deviations persist
do
    sectionState.set('ItemDisplay', 'AllStats', true, false)   -- close an open-default
    sectionState.set('ItemDisplay', 'SpellData', false, true)  -- open a closed-default
    check('flip reads back closed', sectionState.isOpen('ItemDisplay', 'AllStats', true) == false)
    check('flip reads back open', sectionState.isOpen('ItemDisplay', 'SpellData', false) == true)
    local content = files[diskPath('Testchar')] or ''
    check('file stores only deviations, sorted CSV',
        content:find('Collapsed=ItemDisplay.AllStats,ItemDisplay.SpellData', 1, true) ~= nil, content)

    -- Setting back to the default removes the deviation.
    sectionState.set('ItemDisplay', 'AllStats', true, true)
    local content2 = files[diskPath('Testchar')] or ''
    check('reverting removes the CSV entry',
        content2:find('AllStats', 1, true) == nil and content2:find('SpellData', 1, true) ~= nil, content2)
end

-- ---------------------------------------------------------------- reload round-trip
do
    sectionState._resetForTests()
    sectionState.init(deps)
    check('round-trip: deviation survives a restart',
        sectionState.isOpen('ItemDisplay', 'SpellData', false) == true)
    check('round-trip: reverted section back on default',
        sectionState.isOpen('ItemDisplay', 'AllStats', true) == true)
end

-- ---------------------------------------------------------------- per-character
do
    charName = 'Otherchar'
    sectionState._resetForTests()
    sectionState.init(deps)
    check('second character starts from defaults',
        sectionState.isOpen('ItemDisplay', 'SpellData', false) == false)
    sectionState.set('ItemDisplay', 'Effects', true, false)
    check('second character writes its own file',
        (files[diskPath('Otherchar')] or ''):find('Effects', 1, true) ~= nil)
    check('first character file untouched',
        (files[diskPath('Testchar')] or ''):find('Effects', 1, true) == nil)
end

-- ---------------------------------------------------------------- pre-name toggles
do
    charName = nil
    sectionState._resetForTests()
    sectionState.init(deps)
    -- No char yet: toggles must work in memory and not explode.
    sectionState.set('ItemDisplay', 'Augments', true, false)
    check('pre-name toggle readable in memory',
        sectionState.isOpen('ItemDisplay', 'Augments', true) == false)
    -- Name resolves: pending flip persists and wins.
    charName = 'Testchar'
    check('pending flip survives name resolution',
        sectionState.isOpen('ItemDisplay', 'Augments', true) == false)
    check('pending flip flushed to the char file',
        (files[diskPath('Testchar')] or ''):find('Augments', 1, true) ~= nil,
        files[diskPath('Testchar')])
    check('file state from before still respected',
        sectionState.isOpen('ItemDisplay', 'SpellData', false) == true)
end

cleanup()

print(string.format('\n%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
