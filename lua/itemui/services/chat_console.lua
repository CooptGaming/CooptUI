--[[
    chat_console.lua — per-tab Zep console state for the chat window.

    Tabs: all, main, mq, other, coopt (chat_feed's TAB_OF buckets). Each tab gets its own
    lazily-created Zep.Console instance, created ONLY from a render path -- the pinned MQ
    source's in-tree example (lua/examples/console.lua) is the only place a Zep.Console gets
    built, and it does it inside its per-frame GUI() callback with a `if console == nil then`
    guard, never at require time. This module mirrors that: M.ensureConsole must be called
    from render code (chat_window.lua), never from here.

    Why M.append never creates a console itself: chat_feed's onChatLine runs from
    mq.doevents() in main_loop, which is NOT the ImGui render callback (a separate coroutine
    MQ2Lua pulses once per frame). Constructing a Zep.Console outside that callback is exactly
    the case the in-tree example never exercises, so append() only writes into consoles that
    the render path already created; a tab nobody has viewed yet just accumulates in
    chat_feed's own ring buffer, and chat_window backfills from it the first time that tab's
    console is created (see the onCreate callback on M.ensureConsole).

    No require('itemui.services.chat_feed') here, ever: chat_feed requires THIS module to
    forward captured lines (M.append), so the reverse require would be a cycle. Every function
    that needs chat_feed's data (the fallback ring, the backfill seed) takes it as an argument
    instead.

    Link clicks: AppendText parses \x12 EQ tags into real Zep hyperlinks on its own (see
    OnInsertFormattedText / MQConsoleDelegate in the pinned source), and the native delegate
    that backs every Lua console already calls eqlib::ExtractLink + ExecuteTextLink BEFORE our
    Lua eventCallback ever runs -- LuaZepConsoleDelegate::OnHyperlinkClicked tries the base
    MQConsoleDelegate first and only falls through to Lua when that returns false (an
    unrecognised tag). So in practice a real item/spell/player/achievement link already works
    with zero code here; the eventCallback below is the documented fallback path for
    non-standard link data, kept for parity with the design and the in-tree example.
]]

local mq = require('mq')
require('ImGui')
local theme = require('itemui.utils.theme')

local M = {}

-- tab id -> Zep.Console instance, created lazily by M.ensureConsole (render path only).
local consoles = {}

local zepChecked = false
local zepOk = false
local zepModule = nil

--- Opt-in gate for the Zep console (layoutConfig.ChatUseZep, default 0 = OFF).
---
--- CLIENT-CRASH MITIGATION, not a preference. `require('Zep')` registers a sol2 usertype
--- (LuaZepConsole) whose storage carries a __gc that reaches into the Lua registry. On
--- script stop LuaJIT closes the state, finalizes userdata, and that __gc runs AFTER the
--- registry is already gone -- a null-deref that takes the whole EQ client down, not just
--- the script. Confirmed from a real minidump (2026-07-31): lj_gc_finalize_udata ->
--- gc_call_finalizer -> destroy_usertype_storage<LuaZepConsole> -> luaL_unref ->
--- lua_rawgeti (lj_api.c:842), read of 0x18 off a null pointer. It only bites once Zep has
--- actually been required, which is why stopping right after a start was always safe and
--- stopping after a session of play was not.
---
--- The fallback ring-buffer renderer draws the same lines; what is lost is Zep's native
--- \x12 link execution and its scrollback widget. Flip ChatUseZep=1 once the plugin-side
--- teardown is fixed (destroy the usertype storages before lua_close, or guard that __gc).
local zepEnabled = nil  -- set by M.init from layoutConfig; nil = not yet initialised (off)

local function zepAvailable()
    if not zepEnabled then return false end
    if not zepChecked then
        zepChecked = true
        local ok, mod = pcall(require, 'Zep')
        if ok and mod then
            zepModule = mod
            zepOk = true
        end
    end
    return zepOk
end

--- Called from the chat window each frame with the live layoutConfig value, so a Settings
--- flip takes effect without a reload. Turning it OFF mid-session cannot un-require Zep
--- (the usertype is already registered for this state's lifetime) -- it stops NEW consoles
--- and falls back to the ring buffer; the crash-free guarantee needs the next script start.
function M.setZepEnabled(v)
    zepEnabled = v and true or false
end
M.zepAvailable = zepAvailable

--- Channel -> theme color table (0-1 RGBA), moved from dock_bottom's chatLineColor so both
--- the collapsed one-liner and the console share one map. Unmapped channels (say/other) draw
--- in the console/fallback default color -- same as before this file existed.
local function channelColor(channel)
    if channel == "coopt" then return theme.Colors.Header end
    if channel == "mq" then return theme.Colors.Info end
    if channel == "tell" then return theme.Colors.Highlight end
    if channel == "guild" then return theme.Colors.Success end
    if channel == "group" then return theme.Colors.RerollList end
    return nil
end
M.channelColor = channelColor

--- "link" event handler shared by every console. params.data is the raw \x12...\x12 EQ tag
--- text (InsertHyperlink's hyperlinkData -- see MQConsoleDelegate::InsertHyperlink in the
--- pinned source, which stores tagInfo.link verbatim). TextTagInfo entries hold string_views
--- into that string, so it is extracted and executed in the SAME callback and never stored.
local function onConsoleEvent(kind, params)
    if kind ~= "link" then return false end
    pcall(function()
        local data = params and params.data
        if type(data) ~= "string" or data == "" then return end
        local links = mq.ExtractLinks(data)
        if links and links[1] then
            mq.ExecuteTextLink(links[1])
        end
    end)
    return true
end

--- AppendText dispatch: the ImVec4-color overload always pushes a style color (even a
--- fully-transparent one), so a nil colorVec must go through the no-color overload instead --
--- that is the one that leaves the console's current default color alone.
local function appendOne(console, colorVec, text)
    if not console then return end
    pcall(function()
        if colorVec then
            console:AppendText(colorVec, text)
        else
            console:AppendText(text)
        end
    end)
end

local function newConsoleInstance(tab)
    local console = zepModule.Console.new("##CoOptChat_" .. tostring(tab))
    console.maxBufferLines = 500
    console.autoScroll = true
    console.eventCallback = onConsoleEvent
    return console
end

--- Ensure `tab`'s console exists, creating it lazily. MUST be called from a render path (see
--- the file header). `onCreate`, if given, is a zero-arg function called ONLY on the frame
--- this actually creates the console -- it should return a list of {text=, channel=} entries
--- (chat_feed.getLines' shape) to seed the console with, so a tab opened for the first time
--- is not empty despite chat_feed already holding history.
function M.ensureConsole(tab, onCreate)
    if not zepAvailable() then return nil end
    local existing = consoles[tab]
    if existing then return existing end

    local ok, inst = pcall(newConsoleInstance, tab)
    if not ok or not inst then return nil end
    consoles[tab] = inst

    if type(onCreate) == "function" then
        local okSeed, seed = pcall(onCreate)
        if okSeed and type(seed) == "table" then
            for i = 1, #seed do
                local e = seed[i]
                if e and type(e.text) == "string" and e.text ~= "" then
                    local col = channelColor(e.channel)
                    appendOne(inst, col and theme.ToVec4(col) or nil, e.text)
                end
            end
        end
    end
    return inst
end

--- Called by chat_feed for every captured line. Appends to the 'all' console and the entry's
--- own tab console, but ONLY those that already exist -- see the file header for why this
--- never creates one itself. entry is { text=, channel=, tab= } (chat_feed's ring shape).
function M.append(entry)
    if not entry or type(entry.text) ~= "string" or entry.text == "" then return end
    if not zepAvailable() then return end
    local col = channelColor(entry.channel)
    local vec = col and theme.ToVec4(col) or nil
    appendOne(consoles["all"], vec, entry.text)
    local tab = entry.tab
    if tab and tab ~= "all" and consoles[tab] then
        appendOne(consoles[tab], vec, entry.text)
    end
end

--- Pure: trims, empty -> nil, a leading "/" is returned as-is, anything else is prefixed with
--- "/say ". mqRef is accepted for signature parity with the design doc but unused -- this is
--- a text transform only. The caller enqueues the result onto uiState.dockActionQueue like
--- every other bar action; sendInput itself never touches mq or ImGui.
function M.sendInput(text, mqRef)
    if type(text) ~= "string" then return nil end
    local trimmed = text:match("^%s*(.-)%s*$")
    if trimmed == "" then return nil end
    if trimmed:sub(1, 1) == "/" then return trimmed end
    return "/say " .. trimmed
end

--- Fallback renderer for when Zep is unavailable (or the console for `tab` has not been
--- created yet): draws chat_feed's ring buffer directly inside a scrolling child, with
--- per-channel colors and links stripped so they at least read clean. `lines` is supplied by
--- the caller (chat_window, which already requires chat_feed) rather than fetched here -- see
--- the file header's no-cycle note. This is also the path the headless tests exercise, since
--- there is no real Zep module to require outside the game.
function M.renderFallback(tab, height, lines)
    if ImGui.BeginChild("##ChatFallback_" .. tostring(tab), ImVec2(0, height or 0), false) then
        if not lines or #lines == 0 then
            theme.TextMuted("(no chat yet)")
        else
            for i = 1, #lines do
                local e = lines[i]
                local col = channelColor(e.channel)
                local text = e.text
                local ok, stripped = pcall(mq.StripTextLinks, text)
                if ok and type(stripped) == "string" then text = stripped end
                if col then ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(col)) end
                if ImGui.TextUnformatted then
                    ImGui.TextUnformatted(text)
                else
                    ImGui.Text((tostring(text):gsub("%%", "%%%%")))
                end
                if col then ImGui.PopStyleColor() end
            end
        end
    end
    ImGui.EndChild()
end

return M
