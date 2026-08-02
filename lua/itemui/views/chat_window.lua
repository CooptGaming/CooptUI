--[[
    chat_window.lua — the chat console window (mockup 13b's replacement for peek chat).

    A registry companion, structurally cloned from views/effects.lua: geometry apply with
    forceApply/condPos, Begin/setWindowState/early-outs, size+pos write-back, renderWindowLock.
    That makes it a full citizen of the registry -- zones, ESC-LIFO close, pinning, the Lock
    checkbox -- for free, the same as every other companion window.

    Content, top to bottom: a tab row (All/Main/MQ/Other/CoOpt with unread counts), the
    console area (a real Zep.Console when the plugin build has one, chat_console's fallback
    ring-buffer renderer otherwise), an input row, and a muted hint line under it. Typing runs
    "/commands" as typed; bare text sends as "/say ". Submits go through
    uiState.dockActionQueue like every other bar action -- nothing in a render callback may
    issue a game command directly.
]]

local mq = require('mq')
require('ImGui')
local context = require('itemui.context')
local registry = require('itemui.core.registry')
local theme = require('itemui.utils.theme')
local chatFeed = require('itemui.services.chat_feed')
local chatConsole = require('itemui.services.chat_console')
local dockTop = require('itemui.views.dock_top')
local dockLayout = require('itemui.utils.dock_layout')
local dockBottom = require('itemui.views.dock_bottom')
local windowHeader = require('itemui.components.window_header')

local ChatWindowView = {}

local CHAT_WINDOW_WIDTH = 560
local CHAT_WINDOW_HEIGHT = 380

-- Set (and cleared) across frames the window is/ isn't drawing, so the popup anchor below can
-- tell "just opened via the bar" from "still open, still being dragged/resized". Module-local
-- by design, same as dock_bottom's old peek tab state -- one chat window per session.
local wasDrawing = false

local TABS = {
    { id = "all",   label = "All" },
    { id = "main",  label = "Main" },
    { id = "mq",    label = "MQ" },
    { id = "other", label = "Other" },
    { id = "coopt", label = "CoOpt" },
}

-- Module-locals: one chat window exists per session, same as dock_bottom's old peek tab state.
local activeTab = "all"
local inputBuf = ""
-- 19c's filter. Deliberately NOT persisted: a filter you left on last session and cannot
-- see is a chat window that has silently stopped showing you your chat.
local filterOn = false
local filterText = ""
-- "N new" bookkeeping: how many lines existed when we were last parked at the bottom.
local seenCount = 0
local atBottom = true

local function renderTabs()
    for i, t in ipairs(TABS) do
        -- Plain label, no unread count: the window is where you go to READ chat, so a number
        -- that exists to pull you here has nothing left to say once you have arrived. The
        -- command bar keeps its dots -- that is the glance surface -- and this window still
        -- clears their counts as you view each tab (see the clearUnread call in render).
        --
        -- 19c calls these "real tabs", and the kit's active-tab treatment IS the chip: the
        -- open wash plus a 2px accent, here UNDER the tab, which is where a tab strip's
        -- accent belongs. Same control the bars draw, so "active" reads the same everywhere.
        if windowHeader.chip(t.label, "chatTab_" .. t.id, activeTab == t.id, "bottom") then
            activeTab = t.id
        end
        if i < #TABS then ImGui.SameLine(0, 4) end
    end
end

--- Fallback lines for the active tab (chat_console owns no reference to chat_feed itself --
--- see chat_console.lua's file header), narrowed by the filter when one is set.
local function fallbackLines()
    local lines = chatFeed.getLines(200, activeTab ~= "all" and activeTab or nil)
    local needle = filterOn and filterText:lower() or ""
    if needle == "" then return lines end
    local out = {}
    for i = 1, #lines do
        if (lines[i].text or ""):lower():find(needle, 1, true) then out[#out + 1] = lines[i] end
    end
    return out
end

-- Forward-declared: render() pcalls it, and it is defined after render() so the file still
-- reads top-down (open the window, then draw it).
local renderWindowBody

function ChatWindowView.render(ctx)
    if not registry.shouldDraw("chat") then
        wasDrawing = false
        -- A queued bar-open that got closed before its first render must not leave a stale
        -- flag behind to anchor some LATER open (e.g. a preset apply).
        ctx.uiState.chatOpenedFromBar = nil
        return
    end
    -- The open EDGE: the first render call after a stretch of not drawing. Checked before
    -- anything else touches wasDrawing, so a throw further down (contained by the caller,
    -- same as every other bar/companion render) can never leave it stuck true.
    local justOpened = not wasDrawing
    wasDrawing = true
    -- The anchor fires ONLY for opens that came from the bar (main_loop's window-action
    -- drain sets this flag for id=="chat"): a preset apply or zone placement opens through
    -- registry.setWindowState with its own saved geometry, which the anchor must not eat.
    local openedFromBar = justOpened and ctx.uiState.chatOpenedFromBar == true
    ctx.uiState.chatOpenedFromBar = nil

    -- The command bar's unread dots ask for a specific tab (19b). Consumed once, like the
    -- open-from-bar flag above, so a later open never inherits a stale request.
    local wantTab = ctx.uiState.chatRequestedTab
    ctx.uiState.chatRequestedTab = nil
    if wantTab then
        for _, t in ipairs(TABS) do
            if t.id == wantTab then activeTab = wantTab end
        end
    end

    local layoutConfig = ctx.layoutConfig
    -- Zep is opt-in and OFF by default: requiring it registers a usertype whose teardown
    -- crashes the CLIENT on script stop (see chat_console.lua's zepAvailable comment).
    chatConsole.setZepEnabled((tonumber(layoutConfig.ChatUseZep) or 0) ~= 0)
    local forceApply = ctx.uiState.layoutRevertedApplyFrames and ctx.uiState.layoutRevertedApplyFrames > 0
    local condPos = forceApply and ImGuiCond.Always or ImGuiCond.FirstUseEver
    local ax = layoutConfig.ChatWindowX or 0
    local ay = layoutConfig.ChatWindowY or 0

    -- Best-effort popup anchor (mockup): the first frame the chat window opens VIA THE BAR
    -- in bars mode, while it has no saved position, place it against the command bar --
    -- edge-aware: a bottom-docked bar opens the window UPWARD (bottom-left pivot on the
    -- bar's top edge); a top-docked bar opens it DOWNWARD from under the strip (top-left
    -- pivot), or a 380px window would sit entirely above the screen. One frame with
    -- Always; the write-back below records the on-screen result and every later frame
    -- takes the normal ax/ay path.
    local neverDragged = (ax == 0 and ay == 0)
    if openedFromBar and neverDragged and tostring(layoutConfig.UIMode or "classic") == "bars"
            and dockBottom.isEnabled(layoutConfig) then
        local barEdge = dockBottom.edge(layoutConfig)
        local bx, by, _, bh = dockLayout.barRect(barEdge, 0)
        if barEdge == "top" then
            ImGui.SetNextWindowPos(ImVec2(bx, by + bh), ImGuiCond.Always, ImVec2(0, 0))
        else
            ImGui.SetNextWindowPos(ImVec2(bx, by), ImGuiCond.Always, ImVec2(0, 1))
        end
        -- The anchor is a programmatic move: hold window_zones' `applying` cover open so
        -- the write-back it triggers is adopted, not misread as a user drag (the first
        -- draw can lag the open by a couple of main-loop ticks). 2, not 1: the counter
        -- decrements BEFORE the zones tick in the same pass.
        local u = ctx.uiState
        u.layoutRevertedApplyFrames = math.max(tonumber(u.layoutRevertedApplyFrames) or 0, 2)
    elseif ax ~= 0 or ay ~= 0 then
        ImGui.SetNextWindowPos(ImVec2(ax, ay), condPos)
    end
    local w = layoutConfig.WidthChatPanel or CHAT_WINDOW_WIDTH
    local h = layoutConfig.HeightChat or CHAT_WINDOW_HEIGHT
    if w > 0 and h > 0 then
        ImGui.SetNextWindowSize(ImVec2(w, h), condPos)
    end

    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end

    local winOpen, winVis = ImGui.Begin("CoOpt UI Chat##ItemUIChat", registry.isOpen("chat"), windowFlags)
    registry.setWindowState("chat", winOpen, winOpen)
    if not winOpen then ImGui.End(); return end
    if not winVis then ImGui.End(); return end

    -- Everything between Begin and End runs under one pcall so ImGui.End() is
    -- UNCONDITIONAL. A throw anywhere in the body -- geometry write-back, the band, a tab,
    -- the picker -- would otherwise skip End, and a missing End is a C++ ImGuiException
    -- that Lua cannot catch: MQ2Lua kills the script, and stopping a script in that state
    -- has crashed the client. Same containment item_display.lua carries (commit aec75c0);
    -- this window never got it, and the suite's injected SmallButton throw proved it.
    local bodyOk, bodyErr = pcall(renderWindowBody, ctx, layoutConfig)
    if not bodyOk then
        pcall(function() theme.TextError("Chat hit an error this frame.") end)
        local diagnostics = require('itemui.core.diagnostics')
        diagnostics.recordError("Chat", "Window body error", bodyErr)
    end
    ImGui.End()
end

--- Everything between Begin and End, extracted so render() can pcall it (see the call site).
renderWindowBody = function(ctx, layoutConfig)
    -- The kit band carries the pin in bars; the legacy checkbox row stays for classic.
    if tostring(layoutConfig.UIMode or "classic") ~= "bars" and ctx.renderWindowLock then
        ctx.renderWindowLock(ctx, "chat")
    end

    if not ctx.uiState.uiLocked then
        local cw, ch = ImGui.GetWindowSize()
        if cw and ch and cw > 0 and ch > 0 then
            layoutConfig.WidthChatPanel = cw
            layoutConfig.HeightChat = ch
        end
    end
    local px, py = ImGui.GetWindowPos()
    if px and py then
        if not layoutConfig.ChatWindowX or math.abs(layoutConfig.ChatWindowX - px) > 1 or
           not layoutConfig.ChatWindowY or math.abs(layoutConfig.ChatWindowY - py) > 1 then
            layoutConfig.ChatWindowX = px
            layoutConfig.ChatWindowY = py
            ctx.scheduleLayoutSave()
        end
    end

    local barsOn = tostring(layoutConfig.UIMode or "classic") == "bars"
    local timestamps = (tonumber(layoutConfig.ChatTimestamps) or 1) ~= 0

    -- 19c recovers two lines of chrome. The band replaces the "Esc collapses" hint (Esc
    -- already closes via the registry's LIFO handler -- the hint was pure label), and the
    -- send-to picker below replaces "/ commands run as typed - bare text is /say", because
    -- the picker states where bare text goes and the input's own placeholder states the
    -- slash rule. Two lines of a 380px window back.
    if barsOn then
        windowHeader.render({
            id = "chat", title = "Chat",
            stat = string.format("%d line%s", chatFeed.count(),
                (chatFeed.count() == 1) and "" or "s"),
            actions = {
                { label = windowHeader.GLYPHS.FILTER,
                  tooltip = filterOn and "Stop filtering" or "Filter these lines",
                  onClick = function()
                      filterOn = not filterOn
                      if not filterOn then filterText = "" end
                  end },
                { label = windowHeader.GLYPHS.CLOCK,
                  tooltip = timestamps and "Hide the time column" or "Show the time column",
                  onClick = function()
                      if ctx.setLayoutValue then
                          ctx.setLayoutValue("ChatTimestamps", timestamps and 0 or 1)
                      else
                          layoutConfig.ChatTimestamps = timestamps and 0 or 1
                          if ctx.scheduleLayoutSave then ctx.scheduleLayoutSave() end
                      end
                  end },
            },
            lock = windowHeader.registryLock("chat", ctx),
        })
    end

    renderTabs()
    if not barsOn then
        -- Classic keeps the old hint line and the old separator.
        local hintText = "Esc collapses"
        local winW = ImGui.GetWindowWidth and ImGui.GetWindowWidth() or 0
        local tw = dockLayout.textWidth(hintText)
        ImGui.SameLine(math.max(winW - tw - 12, 0))
        theme.TextMuted(hintText)
        ImGui.Separator()
    end

    -- The renderer note (handoff item 2): the filter and the time column force the plain
    -- renderer, and that tradeoff must be stated where it happens, not discovered. Gated on
    -- the USER'S Zep setting AND the library actually loading - zepAvailable() alone only
    -- says the library is present, and a user who never enabled Zep (the default install)
    -- is on the plain renderer unconditionally and lost nothing. TextFurniture, never
    -- Attention amber: this is a consequence of a choice the user just made, not a warning.
    local zepOn = chatConsole.zepAvailable() and ((tonumber(layoutConfig.ChatUseZep) or 0) ~= 0)
    local function rendererNote()
        theme.TextFurniture("plain text - links are not clickable")
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Clear the filter and turn off times to get links back.")
            ImGui.EndTooltip()
        end
    end

    -- The filter is a row, not a mode you cannot see: it only exists while it is on, and
    -- turning it off from the band clears it. A hidden active filter is a chat window that
    -- has quietly stopped showing you your chat.
    if filterOn then
        ImGui.SetNextItemWidth(200)
        -- NOT `ImGui.InputTextWithHint and ImGui.InputTextWithHint(...) or ImGui.InputText(...)`:
        -- that idiom TRUNCATES a multi-value call to one value, so `changed` would silently
        -- be nil. An explicit if is the only correct form (same family as `cond and nil or X`).
        local ft
        if ImGui.InputTextWithHint then
            ft = ImGui.InputTextWithHint("##chatFilter", "show only lines containing...", filterText)
        else
            ft = ImGui.InputText("##chatFilter", filterText)
        end
        filterText = ft or ""
        ImGui.SameLine(0, 6)
        if ImGui.SmallButton("clear##chatFilterClear") then filterText = "" end
        if zepOn then
            ImGui.SameLine(0, 10)
            rendererNote()
        end
    elseif zepOn and timestamps then
        -- Timestamps alone force the plain renderer with no filter row to carry the note,
        -- so it gets the filter row's own rule: a line that exists only while the cause is
        -- active. Only Zep users ever see it, so the default install pays no chrome.
        rendererNote()
    end

    local availW, availH = ImGui.GetContentRegionAvail()
    local inputRowH = ((ImGui.GetFrameHeightWithSpacing and ImGui.GetFrameHeightWithSpacing()) or 24)
        + ((ImGui.GetTextLineHeightWithSpacing and ImGui.GetTextLineHeightWithSpacing()) or 16)

    -- The filter and the time column are ours, not Zep's -- Zep owns its own buffer and
    -- renders it whole. So either of those forces the plain renderer, which is a real
    -- tradeoff (no clickable links while filtering) and is stated by the renderer note
    -- above (on the filter row, or its own row when timestamps alone force it) rather
    -- than left for the user to discover.
    local ownRenderer = filterOn or timestamps
    local lines = fallbackLines()
    local consoleH = math.max((availH or 0) - inputRowH, 1)
    local wasAtBottom = atBottom
    if not ownRenderer and chatConsole.zepAvailable() then
        local console = chatConsole.ensureConsole(activeTab, function()
            return chatFeed.getLines(500, activeTab ~= "all" and activeTab or nil)
        end)
        if console then
            -- POSITIVE height only: ImGui's BeginChild would resolve a negative, but the
            -- binding also hands the raw value to Zep's SetDisplayRegionSize, which builds
            -- a degenerate rect from it (bottom above top) — blank/garbled console, mouse
            -- hit-testing against nothing. Every in-tree caller (MQImGuiConsole.cpp:537,
            -- examples/console.lua:130) subtracts the footer and passes the result.
            local ok = pcall(function() console:Render(ImVec2(availW, consoleH)) end)
            if not ok then
                atBottom = chatConsole.renderFallback(activeTab, consoleH, lines,
                    { timestamps = timestamps })
            else
                atBottom = true    -- Zep autoscrolls itself; there is nothing to catch up to
            end
        else
            atBottom = chatConsole.renderFallback(activeTab, consoleH, lines,
                { timestamps = timestamps })
        end
    else
        atBottom = chatConsole.renderFallback(activeTab, consoleH, lines, {
            timestamps = timestamps,
            -- Scroll to the newest line only when we were ALREADY parked there. Scrolling a
            -- user who has walked back up the log is the single worst thing a chat window
            -- can do, and it is what the "N new" pill exists to avoid needing.
            autoScroll = wasAtBottom,
            empty = (filterOn and filterText ~= "") and "(nothing on this tab matches)" or nil,
        })
    end

    -- "N new" (19c): only while you are scrolled away, and it says how many arrived since
    -- you left the bottom. Clicking it parks you back at the newest line.
    local total = chatFeed.count()
    if atBottom then
        seenCount = total
    elseif total > seenCount then
        if ImGui.SmallButton(string.format("%d new##chatJump", total - seenCount)) then
            seenCount = total
            atBottom = true
        end
        ImGui.SameLine(0, 8)
    end

    -- Send row: the picker, the input, Send. Enter and Send both submit. EQ loses keyboard
    -- focus while this field is active (see docs/DOCK_UI.md) -- the same tradeoff every
    -- focusable CoOpt window makes.
    local sendTo = tostring(layoutConfig.ChatSendTo or "say")
    local target = chatConsole.targetById(sendTo)
    local lastTell = chatFeed.lastTellFrom()
    if ImGui.SmallButton(target.label .. " v##chatSendTo") then
        ImGui.OpenPopup("##chatSendToPopup")
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text("Where bare text goes. A leading / still runs the command as typed.")
        ImGui.EndTooltip()
    end
    if ImGui.BeginPopup("##chatSendToPopup") then
        -- pcall INSIDE the pair: a throw between BeginPopup and EndPopup is an unbalanced
        -- ImGui stack, which is a C++ exception Lua cannot catch and MQ2Lua answers by
        -- killing the script.
        pcall(function()
            for _, t in ipairs(chatConsole.SEND_TARGETS) do
                local where = t.where
                if t.needsName then where = lastTell and ("last: " .. lastTell) or nil end
                if where then
                    -- Selectable returns (selected, pressed) -- SELECTED first. Read the
                    -- second, or every already-picked row fires on every frame.
                    local _, pressed = ImGui.Selectable(t.label .. "##chatTo_" .. t.id, t.id == sendTo)
                    ImGui.SameLine(70)
                    if theme.TextFurniture then theme.TextFurniture(where) else theme.TextMuted(where) end
                    if pressed then
                        if ctx.setLayoutValue then
                            ctx.setLayoutValue("ChatSendTo", t.id)
                        else
                            layoutConfig.ChatSendTo = t.id
                            if ctx.scheduleLayoutSave then ctx.scheduleLayoutSave() end
                        end
                    end
                end
            end
        end)
        ImGui.EndPopup()
    end
    ImGui.SameLine(0, 6)
    local sendW = dockLayout.textWidth("Send") + 24
    -- GetContentRegionAvail returns TWO FLOATS in this binding, not a vec (older paths a
    -- table) -- indexing it as .x throws, and select(1, ...) on a table hands back the table.
    local availNow = ImGui.GetContentRegionAvail()
    if type(availNow) == 'table' then availNow = availNow.x end
    if type(availNow) ~= 'number' then availNow = 200 end
    ImGui.SetNextItemWidth(math.max(availNow - sendW, 80))
    local buf, submitted
    if ImGui.InputTextWithHint then
        buf, submitted = ImGui.InputTextWithHint("##chatInput",
            "type here - a leading / runs the command as typed", inputBuf,
            ImGuiInputTextFlags.EnterReturnsTrue)
    else
        buf, submitted = ImGui.InputText("##chatInput", inputBuf, ImGuiInputTextFlags.EnterReturnsTrue)
    end
    inputBuf = buf
    ImGui.SameLine()
    local sendClicked = ImGui.SmallButton("Send##chatSend")
    if submitted or sendClicked then
        local cmd = chatConsole.sendInput(inputBuf, nil, sendTo, lastTell)
        if cmd then
            dockTop.queue(ctx, { kind = "cmd", cmd = cmd })
        end
        inputBuf = ""
        if ImGui.SetKeyboardFocusHere then ImGui.SetKeyboardFocusHere(-1) end
    end

    -- Viewing is reading: clear the active tab's unread every frame this window is visible.
    -- The All tab clearing everything is correct -- All shows every channel at once.
    chatFeed.clearUnread(activeTab)
end

registry.register({
    id          = "chat",
    zone        = "B2",
    label       = "Chat",
    buttonWidth = 60,
    tooltip     = "Chat console: every channel, clickable links, type to run / commands or /say.",
    layoutKeys  = { x = "ChatWindowX", y = "ChatWindowY" },
    enableKey   = "ShowChatWindow",
    render      = function(refs)
        local ctx = context.build()
        ChatWindowView.render(ctx)
    end,
})

return ChatWindowView
