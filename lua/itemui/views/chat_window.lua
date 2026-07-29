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

local function renderTabs()
    for i, t in ipairs(TABS) do
        -- Plain label, no unread count: the window is where you go to READ chat, so a number
        -- that exists to pull you here has nothing left to say once you have arrived. The
        -- command bar keeps its badges -- that is the glance surface -- and this window still
        -- clears their counts as you view each tab (see the clearUnread call in render).
        local label = string.format("%s##chatTab_%s", t.label, t.id)
        local lit = (activeTab == t.id)
        if lit then ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Header)) end
        if ImGui.SmallButton(label) then
            activeTab = t.id
        end
        if lit then ImGui.PopStyleColor() end
        if i < #TABS then ImGui.SameLine(0, 4) end
    end
end

--- Fallback lines for the active tab (chat_console owns no reference to chat_feed itself --
--- see chat_console.lua's file header).
local function fallbackLines()
    return chatFeed.getLines(200, activeTab ~= "all" and activeTab or nil)
end

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

    local layoutConfig = ctx.layoutConfig
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
    if ctx.renderWindowLock then ctx.renderWindowLock(ctx, "chat") end

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

    renderTabs()
    -- Top-right hint line (mockup): muted "Esc collapses" on the tab row. Esc-close already
    -- works for free via the registry's LIFO close, so this is purely a label -- no new key
    -- handling. Deferred: the mockup's shift+Enter size-cycling is not implemented here.
    do
        local hintText = "Esc collapses"
        local winW = ImGui.GetWindowWidth and ImGui.GetWindowWidth() or 0
        local tw = dockLayout.textWidth(hintText)
        ImGui.SameLine(math.max(winW - tw - 12, 0))
        theme.TextMuted(hintText)
    end
    ImGui.Separator()

    local availW, availH = ImGui.GetContentRegionAvail()
    local hintH = (ImGui.GetTextLineHeightWithSpacing and ImGui.GetTextLineHeightWithSpacing()) or 16
    local inputRowH = ((ImGui.GetFrameHeightWithSpacing and ImGui.GetFrameHeightWithSpacing()) or 24) + hintH

    if chatConsole.zepAvailable() then
        local console = chatConsole.ensureConsole(activeTab, function()
            return chatFeed.getLines(500, activeTab ~= "all" and activeTab or nil)
        end)
        if console then
            -- POSITIVE height only: ImGui's BeginChild would resolve a negative, but the
            -- binding also hands the raw value to Zep's SetDisplayRegionSize, which builds
            -- a degenerate rect from it (bottom above top) — blank/garbled console, mouse
            -- hit-testing against nothing. Every in-tree caller (MQImGuiConsole.cpp:537,
            -- examples/console.lua:130) subtracts the footer and passes the result.
            local zepH = math.max((availH or 0) - inputRowH, 1)
            local ok = pcall(function() console:Render(ImVec2(availW, zepH)) end)
            if not ok then
                chatConsole.renderFallback(activeTab, availH - inputRowH, fallbackLines())
            end
        else
            chatConsole.renderFallback(activeTab, availH - inputRowH, fallbackLines())
        end
    else
        chatConsole.renderFallback(activeTab, availH - inputRowH, fallbackLines())
    end

    -- Input row: Enter or Send both submit. EQ loses keyboard focus while this field is
    -- active (see docs/DOCK_UI.md) -- the same tradeoff every focusable CoOpt window makes.
    local buf, submitted = ImGui.InputText("##chatInput", inputBuf, ImGuiInputTextFlags.EnterReturnsTrue)
    inputBuf = buf
    ImGui.SameLine()
    local sendClicked = ImGui.SmallButton("Send##chatSend")
    if submitted or sendClicked then
        local cmd = chatConsole.sendInput(inputBuf)
        if cmd then
            dockTop.queue(ctx, { kind = "cmd", cmd = cmd })
        end
        inputBuf = ""
        if ImGui.SetKeyboardFocusHere then ImGui.SetKeyboardFocusHere(-1) end
    end
    theme.TextMuted("/ commands run as typed - bare text is /say")

    -- Viewing is reading: clear the active tab's unread every frame this window is visible.
    -- The All tab clearing everything is correct -- All shows every channel at once.
    chatFeed.clearUnread(activeTab)

    ImGui.End()
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
