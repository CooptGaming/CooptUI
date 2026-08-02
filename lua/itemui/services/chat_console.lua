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

--- WHICH LUA STATE REQUIRES ZEP DECIDES WHETHER STOPPING THE SCRIPT KILLS THE CLIENT.
---
--- MQ registers the Zep bindings against whatever state called `require` (MQ2Lua.cpp's
--- register_builtin hands the module factory `sol::this_state s`), and sol2's usertype
--- storage keeps that `lua_State*` in `m_L` to unref its registry entries from its own
--- destructor (usertype_storage.hpp:288/309, ~usertype_storage_base at :597).
---
--- Requiring Zep from a RENDER path captures the ImGui **coroutine thread**, not the main
--- state: mq.imgui callbacks run on `sol::thread::create(...)` (LuaImGui.cpp:136). At
--- script stop LuaJIT frees that thread before it finalizes the usertype-storage userdata,
--- so `m_L` dangles, `G(L)` reads NULL, and `luaL_unref -> lua_rawgeti` faults reading
--- 0x18 -- taking the whole EQ client down, not just the script. That is exactly the
--- minidump from 2026-07-31 (lj_gc_finalize_udata -> gc_call_finalizer ->
--- destroy_usertype_storage<LuaZepConsole> -> luaL_unref -> lua_rawgeti, lj_api.c:842),
--- and it explains the timing tell: stop right after a start was always safe (Zep never
--- required), stop after any session that drew chat was not.
---
--- So the require happens ONCE, from the MAIN thread, at init -- M.prewarm below. The main
--- state stays valid for the whole of lua_close, so the same destructor is harmless.
--- ImGui itself never had this problem for exactly this reason: app.lua requires it at the
--- top of the script body, on the main state.
---
--- Console INSTANCES still must be constructed from a render path (see the header note);
--- that is unrelated -- their __gc receives a live state from Lua rather than storing one.
local zepEnabled = false   -- mirrors layoutConfig.ChatUseZep
local zepPrewarmed = false -- true once M.prewarm has run on the main thread

--- Call ONCE from the main thread during startup (app.lua), never from a render callback.
--- `enabled` is layoutConfig.ChatUseZep. Returns true when the Zep module is usable.
function M.prewarm(enabled)
    zepEnabled = enabled and true or false
    zepPrewarmed = true
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

--- Render-path query. Never requires anything: if the main-thread prewarm did not run (or
--- ran with the setting off), the fallback ring buffer draws instead. A Settings flip to ON
--- therefore takes effect on the next script start, which is the point -- enabling it live
--- would mean requiring Zep from a render path, the very thing that crashes the client.
local function zepAvailable()
    return zepEnabled and zepOk
end

--- Live OFF switch only (Settings unticked mid-session): stops new consoles and falls back.
--- It cannot un-require Zep -- the usertype is registered for this state's lifetime -- but
--- with the require done on the main thread that is no longer a crash, just a renderer swap.
function M.setZepEnabled(v)
    zepEnabled = (v and true or false) and zepPrewarmed and zepOk or false
end

-- The time column used to be OURS, which meant turning it on forced the plain renderer and
-- silently cost you clickable links -- and since both default to on, that was every
-- install. Baked into the text handed to AppendText instead: Zep parses the \x12 EQ tags
-- into hyperlinks itself and does not care what precedes them, so times and links now
-- coexist and neither is a mode. The fallback renderer still draws its own time column
-- (it owns its layout), so both paths show times and only this one needs the prefix.
local timestampsOn = false
--- Mirrors layoutConfig.ChatTimestamps, pushed each frame like setZepEnabled.
--- Toggling mid-session applies to NEW lines only: Zep owns its buffer and rebuilding it
--- would mean destroying and recreating console instances, which is precisely the object
--- lifetime that used to take the client down. A rare cosmetic seam beats that risk.
function M.setTimestamps(v)
    timestampsOn = (v and true or false)
end

--- The exact string Zep receives. Kept in one place so the seed path and the live-append
--- path cannot drift into two formats.
local function zepText(entry)
    if timestampsOn and entry.time and entry.time ~= "" then
        return entry.time .. "  " .. entry.text
    end
    return entry.text
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

-- (Removed 2026-07-31) The Lua "link" event handler that used to be assigned to every
-- console's eventCallback lived here. Assigning it stored a sol::safe_function bound to the
-- ImGui coroutine thread, whose teardown crashes the client -- see newConsoleInstance. The
-- native delegate already executes real links before Lua is consulted, so the handler was
-- only ever a fallback for unrecognised tag data. If a future MQ makes the callback safe to
-- hold, restore it from git history (it was ~12 lines around mq.ExtractLinks/ExecuteTextLink).

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
    -- NO eventCallback. LuaZepConsole stores it as a sol::safe_function (lua_Zep.cpp:142),
    -- which is a registry reference bound to the state that ASSIGNED it -- and consoles are
    -- constructed from a render path, i.e. the ImGui coroutine thread. That thread dies
    -- before the instance is finalized at script stop, so the reference's destructor would
    -- unref through a dangling state: the same client-killing fault as the usertype storage
    -- (see the zepAvailable comment above), just from the instance side.
    --
    -- Nothing is lost. The native delegate handles real links first and only falls through
    -- to Lua for unrecognised tag data: LuaZepConsoleDelegate::OnHyperlinkClicked calls the
    -- base MQConsoleDelegate (eqlib::ExtractLink + ExecuteTextLink) and consults the Lua
    -- callback only when that returns false. Item/spell/player/achievement links therefore
    -- still click through with zero Lua involvement -- see this file's header note.
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
                    appendOne(inst, col and theme.ToVec4(col) or nil, zepText(e))
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
    local text = zepText(entry)
    appendOne(consoles["all"], vec, text)
    local tab = entry.tab
    if tab and tab ~= "all" and consoles[tab] then
        appendOne(consoles[tab], vec, text)
    end
end

--- 19c: "a channel picker instead of typing prefixes". Six targets, in the order a player
--- reaches for them. `needsName` marks the one that has to be aimed at somebody -- it is
--- offered only when chat_feed knows who last spoke to you, because a /tell with no name is
--- a command that cannot work.
M.SEND_TARGETS = {
    { id = "say",   cmd = "/say",  label = "/say",  where = "nearby" },
    { id = "group", cmd = "/gsay", label = "/gsay", where = "group" },
    { id = "raid",  cmd = "/rsay", label = "/rsay", where = "raid" },
    { id = "guild", cmd = "/gu",   label = "/gu",   where = "guild" },
    { id = "tell",  cmd = "/tell", label = "/tell", where = "last", needsName = true },
    { id = "bca",   cmd = "/bca",  label = "/bca",  where = "all boxes" },
}

function M.targetById(id)
    for _, t in ipairs(M.SEND_TARGETS) do
        if t.id == id then return t end
    end
    return M.SEND_TARGETS[1]
end

--- Pure: trims, empty -> nil, a leading "/" is returned as-is, anything else is prefixed
--- with the picked target's command (default /say, which is what typing bare text has
--- always meant here). `targetId` is the picker's choice and `name` the /tell recipient;
--- a /tell with no name falls back to /say rather than emitting a broken command.
--- mqRef is accepted for signature parity with the design doc but unused -- this is a text
--- transform only. The caller enqueues the result onto uiState.dockActionQueue like every
--- other bar action; sendInput itself never touches mq or ImGui.
function M.sendInput(text, mqRef, targetId, name)
    if type(text) ~= "string" then return nil end
    local trimmed = text:match("^%s*(.-)%s*$")
    if trimmed == "" then return nil end
    -- A leading slash still wins over the picker: "a leading / runs the command as typed"
    -- is the one rule the input has always had, and the picker must not silently break it.
    if trimmed:sub(1, 1) == "/" then return trimmed end
    local t = M.targetById(targetId)
    if t.needsName then
        if not name or name == "" then return "/say " .. trimmed end
        return string.format("%s %s %s", t.cmd, name, trimmed)
    end
    return t.cmd .. " " .. trimmed
end

--- Fallback renderer for when Zep is unavailable (or the console for `tab` has not been
--- created yet): draws chat_feed's ring buffer directly inside a scrolling child, with
--- per-channel colors and links stripped so they at least read clean. `lines` is supplied by
--- the caller (chat_window, which already requires chat_feed) rather than fetched here -- see
--- the file header's no-cycle note. This is also the path the headless tests exercise, since
--- there is no real Zep module to require outside the game.
--- opts (all optional): { timestamps = bool, autoScroll = bool, empty = string }.
--- Returns `atBottom` — whether the view is parked at the newest line, which is what the
--- "N new" pill needs to know (a pill that appears while you are already looking at the
--- bottom is noise).
function M.renderFallback(tab, height, lines, opts)
    opts = opts or {}
    local atBottom = true
    if ImGui.BeginChild("##ChatFallback_" .. tostring(tab), ImVec2(0, height or 0), false) then
        if not lines or #lines == 0 then
            theme.TextMuted(opts.empty or "(no chat yet)")
        else
            for i = 1, #lines do
                local e = lines[i]
                local col = channelColor(e.channel)
                local text = e.text
                local ok, stripped = pcall(mq.StripTextLinks, text)
                if ok and type(stripped) == "string" then text = stripped end
                -- 19c's time column. Furniture, drawn ahead of the line and never coloured
                -- by channel: it is the thing you scan past, not the thing you read.
                if opts.timestamps and e.time then
                    if theme.TextFurniture then theme.TextFurniture(e.time) else theme.TextMuted(e.time) end
                    ImGui.SameLine(0, 6)
                end
                if col then ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(col)) end
                if ImGui.TextUnformatted then
                    ImGui.TextUnformatted(text)
                else
                    ImGui.Text((tostring(text):gsub("%%", "%%%%")))
                end
                if col then ImGui.PopStyleColor() end
            end
        end
        -- Scroll bookkeeping INSIDE the child (the scroll values belong to it). A 2px slack
        -- so "one pixel off the bottom" still counts as parked -- ImGui's max scroll moves
        -- as content grows and an exact compare flickers the pill on every new line.
        local y = ImGui.GetScrollY and ImGui.GetScrollY() or 0
        local maxY = ImGui.GetScrollMaxY and ImGui.GetScrollMaxY() or 0
        atBottom = (maxY - y) <= 2
        if opts.autoScroll and ImGui.SetScrollHereY then ImGui.SetScrollHereY(1.0) end
    end
    ImGui.EndChild()
    return atBottom
end

return M
