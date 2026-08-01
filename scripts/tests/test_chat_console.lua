-- Headless suite for services/chat_console.lua and the chat_feed classification it depends on.
--
-- No real Zep module exists outside the game, so this suite can only exercise the parts that
-- do not need one: the pure sendInput transform, chat_feed's classify() regression (including
-- the social needles this feature added), and chat_console's fallback ring-buffer renderer --
-- which is also the exact path a headless/pluginless run takes in the real UI, since
-- M.zepAvailable() memoizes a failed `pcall(require, 'Zep')` to false.
--
-- Run:  COOPT_REPO=C:/Claude/CooptUI <luajit> scripts/tests/test_chat_console.lua

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

-- A local mq stub, not the shared imgui_stub.newMq() singleton shape: this suite needs
-- StripTextLinks (which chat_console's fallback renderer calls), and imgui_stub.lua is shared
-- by every other suite -- extending it there risks changing what they exercise. Each call to
-- stub.newMq() already returns a fresh table, so adding a field here cannot leak anywhere.
local mqStub = stub.newMq()
mqStub.StripTextLinks = function(s)
    if type(s) ~= 'string' then return s end
    -- Mirrors the real eqlib::CleanItemTags job for this test: strip \x12...\x12 spans.
    return (s:gsub('\x12[^\x12]*\x12', ''))
end
mqStub.ExtractLinks = function() return {} end
mqStub.ExecuteTextLink = function() end
package.loaded['mq'] = mqStub

package.loaded['itemui.core.diagnostics'] = {
    getErrorCount = function() return 0 end, recordError = function() end,
}

local chatFeed = require('itemui.services.chat_feed')
local chatConsole = require('itemui.services.chat_console')

-- =================================================================
-- 1. sendInput: pure text transform, no mq/ImGui side effects
-- =================================================================
do
    check('sendInput: empty -> nil', chatConsole.sendInput('') == nil)
    check('sendInput: whitespace-only -> nil', chatConsole.sendInput('   ') == nil)
    check('sendInput: nil input -> nil', chatConsole.sendInput(nil) == nil)
    check('sendInput: leading slash returned as-is',
        chatConsole.sendInput('/say hello') == '/say hello',
        chatConsole.sendInput('/say hello'))
    check('sendInput: slash command with surrounding whitespace is trimmed',
        chatConsole.sendInput('  /who all  ') == '/who all',
        chatConsole.sendInput('  /who all  '))
    check('sendInput: bare text gets /say prefix',
        chatConsole.sendInput('hello there') == '/say hello there',
        chatConsole.sendInput('hello there'))
    check('sendInput: bare text with surrounding whitespace trims before prefixing',
        chatConsole.sendInput('  gg  ') == '/say gg',
        chatConsole.sendInput('  gg  '))

    -- 19c: the picker decides where BARE text goes. Everything above is the default
    -- target's behaviour and must not change.
    check('sendInput: the picked target prefixes bare text',
        chatConsole.sendInput('inc', nil, 'group') == '/gsay inc',
        chatConsole.sendInput('inc', nil, 'group'))
    check('sendInput: guild target', chatConsole.sendInput('hi', nil, 'guild') == '/gu hi')
    check('sendInput: box target', chatConsole.sendInput('follow', nil, 'bca') == '/bca follow')
    check('sendInput: an unknown target id falls back to /say, never to nothing',
        chatConsole.sendInput('hi', nil, 'nonsense') == '/say hi',
        chatConsole.sendInput('hi', nil, 'nonsense'))
    -- The one rule the input has always had outranks the picker.
    check('sendInput: a leading slash still wins over the picker',
        chatConsole.sendInput('/who all', nil, 'guild') == '/who all')
    -- /tell needs somebody to tell. Emitting "/tell  hi" would be a command that cannot work.
    check('sendInput: /tell with a name aims at them',
        chatConsole.sendInput('omw', nil, 'tell', 'Alotta') == '/tell Alotta omw',
        chatConsole.sendInput('omw', nil, 'tell', 'Alotta'))
    check('sendInput: /tell with nobody to tell degrades to /say, not a broken command',
        chatConsole.sendInput('omw', nil, 'tell', nil) == '/say omw',
        chatConsole.sendInput('omw', nil, 'tell', nil))
    check('sendInput: six targets offered', #chatConsole.SEND_TARGETS == 6, #chatConsole.SEND_TARGETS)
end

-- =================================================================
-- 2. classify(): regression, including the new social needles
-- =================================================================
do
    check('classify: tell -> tell/main', chatFeed.classify("Bob tells you, 'hi'") == 'tell'
        and chatFeed.tabFor("Bob tells you, 'hi'") == 'main')
    check('classify: guild -> guild/main', chatFeed.classify("Bob tells the guild, 'hi'") == 'guild'
        and chatFeed.tabFor("Bob tells the guild, 'hi'") == 'main')
    check('classify: mq bracket -> mq/mq', chatFeed.classify('[MQ2Foo] something happened') == 'mq'
        and chatFeed.tabFor('[MQ2Foo] something happened') == 'mq')
    check('classify: coopt bracket -> coopt/coopt', chatFeed.classify('[CoOpt] sold 3 items') == 'coopt'
        and chatFeed.tabFor('[CoOpt] sold 3 items') == 'coopt')
    check('classify: unmatched line -> other', chatFeed.classify('Random narrative text.') == 'other'
        and chatFeed.tabFor('Random narrative text.') == 'other')

    -- The needles this feature added.
    check('classify: raid tell (them) -> group/main',
        chatFeed.classify("Bob tells the raid, 'inc'") == 'group'
        and chatFeed.tabFor("Bob tells the raid, 'inc'") == 'main')
    check('classify: raid tell (you) -> group/main',
        chatFeed.classify("You tell your raid, 'inc'") == 'group'
        and chatFeed.tabFor("You tell your raid, 'inc'") == 'main')
    check('classify: out of character (them) -> say/main',
        chatFeed.classify("Bob says out of character, 'lol'") == 'say'
        and chatFeed.tabFor("Bob says out of character, 'lol'") == 'main')
    check('classify: out of character (you) -> say/main',
        chatFeed.classify("You say out of character, 'lol'") == 'say'
        and chatFeed.tabFor("You say out of character, 'lol'") == 'main')
    check('classify: auction (them) -> say/main',
        chatFeed.classify("Bob auctions, 'WTS stuff'") == 'say'
        and chatFeed.tabFor("Bob auctions, 'WTS stuff'") == 'main')
    check('classify: auction (you) -> say/main',
        chatFeed.classify("You auction, 'WTS stuff'") == 'say'
        and chatFeed.tabFor("You auction, 'WTS stuff'") == 'main')

    -- Ordering: the new "out of character" / "auction" needles must not be shadowed by (or
    -- shadow) the generic say/shout needles they sit next to.
    check('classify: plain say still say/main', chatFeed.classify("Bob says, 'hi'") == 'say'
        and chatFeed.tabFor("Bob says, 'hi'") == 'main')
    check('classify: plain shout still say/main', chatFeed.classify("Bob shouts, 'hi'") == 'say'
        and chatFeed.tabFor("Bob shouts, 'hi'") == 'main')
end

-- =================================================================
-- 3. Fallback renderer: balanced, draws lines, strips links to plain text
-- =================================================================
do
    -- Zep is never available in a headless run (no real Zep module to require), so this is
    -- also the exact path the real UI takes without the plugin's console widget.
    check('zepAvailable() is false headlessly', chatConsole.zepAvailable() == false)

    -- Feed a line carrying a fake \x12-delimited link through chat_feed's REAL pipeline
    -- (classify -> ring append -> chat_console.append), via the test-only _inject hook --
    -- mirrors window_zones.lua's _state/_reset convention.
    local fakeLink = '\x120123456789ABCDEFTestItem\x12'
    local line = "Bob says, 'check this out " .. fakeLink .. "'"
    chatFeed._inject(line)

    local mainLines = chatFeed.getLines(200, 'main')
    check('fallback: the injected line landed on main', #mainLines >= 1 and mainLines[#mainLines].text == line,
        #mainLines)

    local r = stub.frame(function()
        chatConsole.renderFallback('main', 150, mainLines)
    end)
    check('fallback: balanced', stub.balanced(r), stub.imbalance(r))
    check('fallback: drew the visible text', stub.drew(r, 'check this out'), table.concat(r.text, '|'))
    check('fallback: raw \\x12 payload is stripped from the rendered text',
        not stub.drew(r, '\x12'), table.concat(r.text, '|'))

    -- Empty-state smoke: still balanced, still says something.
    local r2 = stub.frame(function()
        chatConsole.renderFallback('coopt', 150, chatFeed.getLines(200, 'coopt'))
    end)
    check('fallback: balanced with no lines', stub.balanced(r2), stub.imbalance(r2))
    check('fallback: empty state message shown', stub.drew(r2, 'no chat yet'), table.concat(r2.text, '|'))

    -- 19c's time column. Stamped at CAPTURE, so a line the window has not drawn for
    -- minutes still reports when it was SAID.
    check('feed: every captured line carries the time it arrived',
        type(mainLines[#mainLines].time) == 'string'
        and mainLines[#mainLines].time:match('^%d%d:%d%d$') ~= nil,
        tostring(mainLines[#mainLines].time))
    local r3 = stub.frame(function()
        chatConsole.renderFallback('main', 150, mainLines, { timestamps = true })
    end)
    check('fallback: the time column draws when asked',
        stub.drew(r3, mainLines[#mainLines].time), table.concat(r3.text, '|'))
    check('fallback: balanced with timestamps', stub.balanced(r3), stub.imbalance(r3))
    check('fallback: no time column by default',
        not stub.drew(r2, mainLines[#mainLines].time))

    -- The pill needs to know whether the view is parked at the newest line.
    check('fallback: reports whether it is parked at the bottom',
        chatConsole.renderFallback ~= nil and (function()
            local at
            stub.frame(function() at = chatConsole.renderFallback('main', 150, mainLines) end)
            return at == true
        end)())

    -- /tell last: <name> comes from the line the classifier already matched.
    chatFeed._inject("Alotta tells you, 'ready when you are'")
    check('feed: remembers who last sent you a tell', chatFeed.lastTellFrom() == 'Alotta',
        tostring(chatFeed.lastTellFrom()))
    chatFeed._inject("Bob says, 'not a tell'")
    check('feed: a non-tell does not overwrite it', chatFeed.lastTellFrom() == 'Alotta',
        tostring(chatFeed.lastTellFrom()))
end

-- =================================================================
-- Where Zep gets required (client-crash fix, 2026-07-31)
--
-- MQ binds the Zep module against whichever lua_State called require, and sol2's usertype
-- storage unrefs through that stored pointer when the state closes. Requiring from a RENDER
-- callback captures the ImGui coroutine thread, which LuaJIT frees before finalization --
-- dangling state, null-deref, dead EQ client. So the contract this suite defends is:
-- the require happens ONLY in prewarm (called from the main thread at startup), and the
-- render-path query never requires anything, whatever the setting says. A require trap is
-- the only thing that can prove that; "did the fallback draw" never could.
-- =================================================================
do
    local requiredZep = false
    local realRequire = require
    _G.require = function(name, ...)
        if name == 'Zep' then requiredZep = true end
        return realRequire(name, ...)
    end

    -- 1. The render-path query must never require, even when the setting is on and no
    --    prewarm has run. This is the exact shape of the crash we are preventing.
    chatConsole.setZepEnabled(true)
    local ok, avail = pcall(chatConsole.zepAvailable)
    check('zep: render-path query never throws', ok, avail)
    check('zep: render-path query never requires Zep (the crash is armed by WHERE it is required)',
        requiredZep == false)
    check('zep: no prewarm -> unavailable, so the fallback renderer draws', avail == false)

    -- 2. prewarm(false) honours the setting without touching the module.
    check('zep: prewarm(false) reports unavailable', chatConsole.prewarm(false) == false)
    check('zep: prewarm(false) does not require Zep', requiredZep == false)

    -- 3. prewarm(true) is the one place that requires. Headless there is no Zep module, so
    --    the pcall fails and we degrade to the ring buffer -- the same shape as an in-game
    --    MQ build without Zep support, and it must not throw.
    local okPre, availPre = pcall(chatConsole.prewarm, true)
    check('zep: prewarm(true) is contained, never throws', okPre, availPre)
    check('zep: prewarm(true) is where the require happens', requiredZep == true)
    check('zep: prewarm(true) with no Zep present -> still unavailable', availPre == false)
    check('zep: after a failed prewarm the render query stays false',
        chatConsole.zepAvailable() == false)

    _G.require = realRequire
    chatConsole.prewarm(false)
end

print(string.format('\n%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
