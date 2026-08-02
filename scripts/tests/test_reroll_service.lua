-- Regression test for lua/itemui/services/reroll_service.lua
-- Runs on the exact LuaJIT MQ links against, with a stubbed `mq` host module.
--
-- Covers two data-loss defects fixed in the first-pass review. The reroll id lists are a
-- sell/loot PROTECTION set, so losing them silently un-protects the user's items:
--
--   1. init() runs in app.lua's MODULE BODY, before main() waits for Me.Name(). Starting
--      CoOpt at character select or mid-zone left the per-character storage path unresolvable,
--      so the lists stayed empty, !auglist/!mythicallist went into the void, and ~6s later
--      checkListRequestTimeout persisted those empty lists over the user's real cache.
--   2. onRerollListLine cleared a whole list on any chat line that looked like a list header,
--      even outside a request window - so typing !auglist directly in chat (a documented
--      server command) wiped the cached list and rejected the replacement lines.

local repo = assert(os.getenv('COOPT_REPO'), 'set COOPT_REPO')
local tmp  = assert(os.getenv('COOPT_TMP'), 'set COOPT_TMP')

package.path = repo .. '\\lua\\?.lua;' .. repo .. '\\lua\\?\\init.lua;' .. package.path

local pass, fail = 0, 0
local function check(name, cond, extra)
    if cond then pass = pass + 1; print('PASS: ' .. name)
    else fail = fail + 1; print('FAIL: ' .. name .. (extra and ('  -> ' .. tostring(extra)) or '')) end
end

-- ---------------------------------------------------------------- mq host stub
local now = 100000
local sentCommands = {}
local handlers = {}
package.loaded['mq'] = {
    gettime = function() return now end,
    cmd     = function(c) sentCommands[#sentCommands + 1] = c end,
    cmdf    = function(f, ...) sentCommands[#sentCommands + 1] = string.format(f, ...) end,
    delay   = function() end,
    event   = function(name, _pattern, fn) handlers[name] = fn end,
    TLO     = { Me = { Name = function() return "Tester" end } },
}
-- The plugin is optional; force the Lua fallback path.
package.loaded['itemui.utils.coopui_plugin'] = {
    getPlugin = function() return nil end, getIPC = function() return nil end,
    getINI = function() return nil end, getWindow = function() return nil end,
    getCursor = function() return nil end, getItems = function() return nil end,
}

local reroll = require('itemui.services.reroll_service')

-- ---------------------------------------------------------------- fixtures
local cachePath = tmp .. '\\reroll_lists.lua'
local function writeCache()
    local f = assert(io.open(cachePath, 'w'))
    f:write([[
return {
  aug = { { id = 1001, name = "Aug One" }, { id = 1002, name = "Aug Two" } },
  mythical = { { id = 2001, name = "Myth One" } },
  pendingAug = { { id = 3001, name = "Pending Aug" } },
  pendingMythical = {},
}
]])
    f:close()
end
local function readCache()
    local f = io.open(cachePath, 'r'); if not f then return nil end
    local c = f:read('*a'); f:close(); return c
end

-- Character is UNKNOWN at first: the storage-path getter returns nil, exactly as
-- app.lua's getRerollListStoragePath does when mq.TLO.Me.Name() is empty.
local characterKnown = false
local function initService()
    reroll.init({
        setStatusMessage = function() end,
        getRerollListStoragePath = function()
            if not characterKnown then return nil end
            return cachePath
        end,
        onRerollListChanged = function() end,
    })
end

-- ================================================================ 1. deferred init
writeCache()
local original = readCache()
characterKnown = false
initService()

check('no list request is sent while the character is unknown', #sentCommands == 0,
      table.concat(sentCommands, ' | '))
check('lists read as empty while unknown', #reroll.getAugList() == 0)

-- Real timeline: app.lua's main() blocks on "wait for Me.Name()" BEFORE the tick loop starts,
-- so the character resolves first and the very first tick is already past the 6s list-request
-- window. That first tick is where the old code called saveToFile() with a now-valid path and
-- wrote four empty tables over the user's cache.
characterKnown = true
now = now + 7000
reroll.checkListRequestTimeout(now)
check('user cache is NOT overwritten by the first tick after the character resolves',
      readCache() == original)
check('aug list loaded once the character resolves', #reroll.getAugList() == 2,
      #reroll.getAugList())
check('mythical list loaded', #reroll.getMythicalList() == 1)
check('pending aug list survived', #reroll.getPendingAugList() == 1)
check('cache file still intact after the deferred load', readCache() == original)
check('no list request sent - the cache was not empty', #sentCommands == 0,
      table.concat(sentCommands, ' | '))

-- ================================================================ 2. header outside a window
-- Nothing has opened a parse window, so a stray header must not clear anything.
local headerHandler = handlers['ItemUIRerollListHeader']
check('header handler is registered', type(headerHandler) == 'function')
if headerHandler then
    headerHandler('===== Aug List =====')
    check('stray "Aug List" header does NOT wipe the cached aug list',
          #reroll.getAugList() == 2, #reroll.getAugList())
    headerHandler('===== Mythical List =====')
    check('stray "Mythical List" header does NOT wipe the mythical list',
          #reroll.getMythicalList() == 1, #reroll.getMythicalList())
end

-- ================================================================ 3. normal refresh still works
-- Refresh opens a window; inside it the header SHOULD reset the list and lines fill it.
sentCommands = {}
reroll.requestBothLists()
check('refresh sends the server list commands', #sentCommands >= 1,
      table.concat(sentCommands, ' | '))
local lineHandler = handlers['ItemUIRerollListLine']
headerHandler('===== Aug List =====')
check('header inside the parse window DOES reset the list', #reroll.getAugList() == 0,
      #reroll.getAugList())
lineHandler('id=5001 name=Fresh Aug')
lineHandler('id=5002 name=Second Aug')
check('list lines inside the window are accepted', #reroll.getAugList() == 2,
      #reroll.getAugList())

-- Closing the window persists the freshly parsed list.
now = now + 7000
reroll.checkListRequestTimeout(now)
local after = readCache()
check('refreshed list is persisted', after ~= nil and after:find('5001') ~= nil)
check('persisted file is not the original', after ~= original)

print(('\n%d passed, %d failed'):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
