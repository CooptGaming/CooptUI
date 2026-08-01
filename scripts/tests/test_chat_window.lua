-- Render-path suite for views/chat_window.lua -- chat v2 (mockup 19c).
--
-- The pattern is test_item_display_render.lua's: drive the WHOLE window under the recording
-- ImGui stub with a realistic ctx, then assert what it drew, what it enqueued, and that every
-- stack balances -- including on frames where a draw call is made to throw. That last part is
-- not paranoia: an unbalanced ImGui pair raises a C++ exception Lua's pcall cannot catch, and
-- MQ2Lua answers it by killing the script.
--
-- What v2 added, and therefore what this pins:
--   * the 26px band, with the filter and time toggles as icon actions
--   * tabs as kit chips, the active one lit
--   * a send-to picker, so bare text goes where you chose instead of always to /say
--   * a time column, a filter, and the "N new" catch-up pill
--   * two recovered lines of chrome (the "Esc collapses" and "bare text is /say" hints)
--
-- Run:  COOPT_REPO=C:/Claude/CooptUI <luajit> scripts/tests/test_chat_window.lua

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
mqStub.StripTextLinks = function(s) return s end
package.loaded['mq'] = mqStub
package.loaded['itemui.utils.coopui_plugin'] = {
    getPlugin = function() return nil end, getIPC = function() return nil end,
    getINI = function() return nil end, getWindow = function() return nil end,
    getCursor = function() return nil end, getItems = function() return nil end,
}
package.loaded['itemui.core.diagnostics'] = {
    getErrorCount = function() return 0 end, recordError = function() end,
}

local registry = require('itemui.core.registry')
local chatFeed = require('itemui.services.chat_feed')
local chatConsole = require('itemui.services.chat_console')
local chatWindow = require('itemui.views.chat_window')   -- registers id "chat" at require time

local layoutConfig, uiState, saved

local function newCtx(over)
    layoutConfig = {
        UIMode = 'bars',
        ChatTimestamps = 1,
        ChatSendTo = 'say',
        ChatUseZep = 0,
        WidthChatPanel = 560, HeightChat = 380,
        ChatWindowX = 400, ChatWindowY = 300,
        DockBottom = true, DockTop = true, DockPosition = 'top',
    }
    for k, v in pairs(over or {}) do layoutConfig[k] = v end
    uiState = { dockActionQueue = nil, uiLocked = false }
    saved = {}
    registry.init({ layoutConfig = layoutConfig, companionWindowOpenedAt = {} })
    return {
        layoutConfig = layoutConfig,
        uiState = uiState,
        scheduleLayoutSave = function() saved.scheduled = (saved.scheduled or 0) + 1 end,
        setLayoutValue = function(k, v) layoutConfig[k] = v; saved[k] = v end,
        renderWindowLock = function() saved.legacyLock = true end,
        theme = require('itemui.utils.theme'),
    }
end

--- Open the window the way the registry does, then draw one frame.
local function frameWith(ctx)
    registry.setWindowState('chat', true, true)
    return stub.frame(function() chatWindow.render(ctx) end)
end

-- =================================================================
-- 1. The band, the tabs, and the chrome that came back
-- =================================================================
do
    local ctx = newCtx()
    chatFeed.clearUnread()
    chatFeed._inject("Alotta tells you, 'ready when you are'")
    chatFeed._inject('Seasaranger begins to cast a spell.')

    local r = frameWith(ctx)
    check('band: drawn, with the window name', stub.drew(r, 'Chat'), table.concat(r.text, '|'))
    check('band: the stat is how much scrollback this window holds',
        stub.drew(r, string.format('%d lines', chatFeed.count())), table.concat(r.text, '|'))
    check('band: the pin replaces the legacy Lock row in bars', not saved.legacyLock)
    check('tabs: all five drawn as chips',
        stub.drew(r, 'All##chatTab_all') and stub.drew(r, 'Main##chatTab_main')
        and stub.drew(r, 'MQ##chatTab_mq') and stub.drew(r, 'Other##chatTab_other')
        and stub.drew(r, 'CoOpt##chatTab_coopt'), table.concat(r.buttons, '|'))
    check('tabs: the active one is lit with the kit open pair',
        stub.pushedColor(r, require('itemui.utils.theme').Kit.OpenWash))
    check('tabs: ...and accented in open-blue',
        stub.drewColor(r, require('itemui.utils.theme').Kit.OpenBlue, 'rectFilled'))

    -- 19c: "two lines of chrome recovered". Both hints are gone in bars -- Esc-close is free
    -- via the registry's LIFO handler, and the picker states where bare text goes.
    check('chrome: the "Esc collapses" label is gone', not stub.drew(r, 'Esc collapses'),
        table.concat(r.text, '|'))
    check('chrome: the "bare text is /say" hint is gone',
        not stub.drew(r, 'bare text is /say'), table.concat(r.text, '|'))

    check('frame: balanced', stub.balanced(r), stub.imbalance(r))
    check('frame: no errors', r.ok, r.err)
    check('frame: nothing was sent just by drawing',
        (uiState.dockActionQueue == nil) or #uiState.dockActionQueue == 0)
end

-- =================================================================
-- 2. The send-to picker: where bare text goes, and that a slash still wins
-- =================================================================
do
    local ctx = newCtx()
    local r = frameWith(ctx)
    check('picker: the current target is on the button', stub.drew(r, '/say v##chatSendTo'),
        table.concat(r.buttons, '|'))

    -- Pick /gsay from the popup, then send bare text.
    stub.openPopups = { chatSendToPopup = true }
    stub.click = { chatTo_group = true }
    frameWith(ctx)
    stub.click = {}
    check('picker: choosing a target persists it through setLayoutValue',
        layoutConfig.ChatSendTo == 'group' and saved.ChatSendTo == 'group',
        tostring(layoutConfig.ChatSendTo))

    stub.openPopups = {}
    stub.inputText = { chatInput = 'inc' }
    stub.click = { chatSend = true }
    uiState.dockActionQueue = nil
    frameWith(ctx)
    stub.click, stub.inputText = {}, {}
    local q = uiState.dockActionQueue or {}
    check('picker: bare text goes to the picked channel',
        q[1] and q[1].kind == 'cmd' and q[1].cmd == '/gsay inc',
        q[1] and tostring(q[1].cmd))

    stub.inputText = { chatInput = '/who all' }
    stub.click = { chatSend = true }
    uiState.dockActionQueue = nil
    frameWith(ctx)
    stub.click, stub.inputText = {}, {}
    local q2 = uiState.dockActionQueue or {}
    check('picker: a leading slash still runs as typed',
        q2[1] and q2[1].cmd == '/who all', q2[1] and tostring(q2[1].cmd))

    -- /tell is only offered once somebody has actually told you something -- a /tell with
    -- no name is a command that cannot work.
    local rNoTell = frameWith(ctx)
    local _ = rNoTell
    chatFeed._inject("Alotta tells you, 'hi'")
    stub.openPopups = { chatSendToPopup = true }
    local rTell = frameWith(ctx)
    stub.openPopups = {}
    check('picker: /tell names who last spoke to you', stub.drew(rTell, 'last: Alotta'),
        table.concat(rTell.text, '|'))
end

-- =================================================================
-- 3. Timestamps, the filter, and the catch-up pill
-- =================================================================
do
    local ctx = newCtx()
    chatFeed.clearUnread()
    chatFeed._inject("Bob says, 'first'")
    chatFeed._inject("Bob says, 'second'")
    local lines = chatFeed.getLines(10, 'main')
    local stamp = lines[#lines].time

    local r = frameWith(ctx)
    check('time: the column draws when ChatTimestamps is on', stub.drew(r, stamp),
        table.concat(r.text, '|'))

    -- The clock icon is the SECOND band action; the filter is the first.
    stub.click = { hdract_chat_2 = true }
    frameWith(ctx)
    stub.click = {}
    check('time: the band toggle persists the setting', layoutConfig.ChatTimestamps == 0,
        tostring(layoutConfig.ChatTimestamps))
    local rOff = frameWith(ctx)
    check('time: ...and the column stops drawing', not stub.drew(rOff, stamp),
        table.concat(rOff.text, '|'))

    -- Filter: the row only exists while it is ON, so an active filter can never be invisible.
    check('filter: no filter row until it is turned on',
        not stub.drew(rOff, 'clear##chatFilterClear'), table.concat(rOff.buttons, '|'))
    stub.click = { hdract_chat_1 = true }
    frameWith(ctx)
    stub.click = {}
    local rFilter = frameWith(ctx)
    check('filter: turning it on shows its row', stub.drew(rFilter, 'clear##chatFilterClear'),
        table.concat(rFilter.buttons, '|'))

    stub.inputText = { chatFilter = 'second' }
    local rMatch = frameWith(ctx)
    stub.inputText = {}
    check('filter: only matching lines are drawn',
        stub.drew(rMatch, "Bob says, 'second'") and not stub.drew(rMatch, "Bob says, 'first'"),
        table.concat(rMatch.text, '|'))

    stub.inputText = { chatFilter = 'nothing matches this' }
    local rNone = frameWith(ctx)
    stub.inputText = {}
    check('filter: an empty result says so rather than looking broken',
        stub.drew(rNone, 'nothing on this tab matches'), table.concat(rNone.text, '|'))
    check('filter: balanced', stub.balanced(rNone), stub.imbalance(rNone))
end

-- =================================================================
-- 4. The "N new" pill only exists when it has something to say
-- =================================================================
do
    local ctx = newCtx()
    chatFeed.clearUnread()
    chatFeed._inject("Bob says, 'a'")
    local rAtBottom = frameWith(ctx)
    check('pill: parked at the newest line -> no pill',
        not stub.drew(rAtBottom, 'new##chatJump'), table.concat(rAtBottom.buttons, '|'))

    -- Scroll away, then let two lines arrive.
    stub.scroll = { y = 0, maxY = 400 }
    frameWith(ctx)
    chatFeed._inject("Bob says, 'b'")
    chatFeed._inject("Bob says, 'c'")
    local rScrolled = frameWith(ctx)
    check('pill: scrolled away with new lines -> the pill counts them',
        stub.drew(rScrolled, '2 new##chatJump'), table.concat(rScrolled.buttons, '|'))
    check('pill: balanced', stub.balanced(rScrolled), stub.imbalance(rScrolled))

    -- Clicking it parks you back at the bottom, and the count goes away.
    stub.click = { chatJump = true }
    frameWith(ctx)
    stub.click = {}
    stub.scroll = nil
    local rBack = frameWith(ctx)
    check('pill: clicking it clears the catch-up count',
        not stub.drew(rBack, 'new##chatJump'), table.concat(rBack.buttons, '|'))
end

-- =================================================================
-- 5. A throw anywhere in the body must not leave a stack open
-- =================================================================
do
    local ctx = newCtx()
    for _, victim in ipairs({ 'Text', 'TextUnformatted', 'SmallButton', 'Selectable' }) do
        stub.throwOn = { [victim] = true }
        local r = frameWith(ctx)
        stub.throwOn = {}
        check('throw ' .. victim .. ': every stack still balances', stub.balanced(r),
            stub.imbalance(r))
    end
end

-- =================================================================
-- 6. Classic is untouched
-- =================================================================
do
    local ctx = newCtx({ UIMode = 'classic' })
    local r = frameWith(ctx)
    check('classic: no kit band', not stub.drew(r, '##winheader_chat'), table.concat(r.windows, '|'))
    check('classic: the old Esc hint is still there', stub.drew(r, 'Esc collapses'),
        table.concat(r.text, '|'))
    check('classic: the legacy Lock row still runs', saved.legacyLock == true)
    check('classic: balanced', stub.balanced(r), stub.imbalance(r))
end

local missing = {}
for k, v in pairs(stub.missing) do missing[#missing + 1] = k .. 'x' .. v end
if #missing > 0 then print('\nunstubbed ImGui calls seen: ' .. table.concat(missing, ', ')) end

print(string.format('\n%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
