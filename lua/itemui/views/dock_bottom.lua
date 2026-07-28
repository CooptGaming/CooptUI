--[[
    dock_bottom.lua — the command bar: launchers, native windows, Settings, and chat.

    This is where the Command Center window goes to die. Everything reachable from that
    window is reachable here, so it can stay closed for a whole session — that is a phase 3
    acceptance criterion, not a nicety.

    Structure is mockup 13c option B: four hover menus rather than a flat rail of sixteen
    buttons. A rail is faster for someone who has memorised it and is the widest possible
    strip; menus stay honest as the tool keeps growing. Chat has the three heights from 13b.

    The menus use the same second-borderless-window mechanism as dock_top's popovers rather
    than ImGui popups, for the same reason: a popup takes focus, and nothing on these bars may
    take the keyboard away from the game.

    Division of labour with the top bar (mockup 13d): the top bar REPORTS, this one takes
    COMMANDS, and nothing appears on both. One home per control, so there is never a "which
    one do I press".
]]

local mq = require('mq')
local theme = require('itemui.utils.theme')
local constants = require('itemui.constants')
local dockLayout = require('itemui.utils.dock_layout')
local dockState = require('itemui.services.dock_state')
local dockTop = require('itemui.views.dock_top')
local chatFeed = require('itemui.services.chat_feed')
local registry = require('itemui.core.registry')

local M = {}

local PEEK_LINES = 4

-- Menu definitions. Module entries are resolved through the registry at draw time, so a
-- companion the user disabled simply is not listed, and "lit" means registry.isOpen.
local MENUS = {
    {
        id = "items", label = "Items",
        entries = {
            { kind = "hub",    label = "Bags" },
            { kind = "module", id = "bank" },
            { kind = "module", id = "itemDisplay" },
            { kind = "module", id = "augments" },
            { kind = "module", id = "augmentUtility" },
            { kind = "module", id = "mythicals" },
            { kind = "module", id = "reroll" },
        },
    },
    {
        id = "character", label = "Character",
        entries = {
            { kind = "module", id = "equipment" },
            { kind = "module", id = "effects" },
            { kind = "module", id = "favorites" },
            { kind = "module", id = "aa" },
            { kind = "scripttracker", label = "ScriptTracker" },
        },
    },
    {
        id = "actions", label = "Actions",
        entries = {
            { kind = "loot_all",  label = "Loot All" },
            { kind = "loot_stop", label = "Stop" },
            { kind = "auto_sell", label = "Auto Sell" },
            { kind = "module",    id = "loot" },
            { kind = "module",    id = "commandCenter" },
        },
    },
    {
        id = "game", label = "Game windows",
        entries = {
            { kind = "native", label = "Inventory", window = "InventoryWindow" },
            { kind = "native", label = "Merchant",  window = "MerchantWnd" },
            { kind = "native", label = "Actions",   window = "ActionsWindow" },
            { kind = "native", label = "AA window", window = "AAWindow" },
            { kind = "native", label = "Bank",      window = "BigBankWnd" },
            -- The native Command Center. Kept reachable so nothing the old CC window offered
            -- is lost when it is closed for good -- that is a phase 3 acceptance criterion.
            { kind = "native", label = "Native panel", window = "TipWindow" },
        },
    },
}

local CHAT_TABS = {
    { id = "main",  label = "Main" },
    { id = "mq",    label = "MQ" },
    { id = "other", label = "Other" },
    { id = "coopt", label = "CoOpt" },
}

-- Transient menu hover state; the pinned menu id lives on uiState (dock state stays outside
-- ImGui's own storage).
local hover = { id = nil, lastAt = 0, inMenu = false }
local activeTab = "main"

--- How tall the strip is for the current chat mode. Fixed for a given mode — it only changes
--- when the user changes the mode, so nothing reflows mid-session.
function M.rows(layoutConfig)
    local mode = tostring((layoutConfig or {}).DockChat or "collapsed")
    return (mode == "peek") and (1 + PEEK_LINES) or 1
end

function M.isEnabled(layoutConfig)
    if not layoutConfig then return false end
    return tostring(layoutConfig.UIMode or "classic") == "bars" and layoutConfig.DockBottom ~= false
end

--- The command bar takes the edge the status bar did not. With the status bar off it takes
--- the bottom, which is where a command strip belongs.
function M.edge(layoutConfig)
    local statusEdge = dockTop.edge(layoutConfig)
    if not dockTop.isEnabled(layoutConfig) then return "bottom" end
    return (statusEdge == "top") and "bottom" or "top"
end

-- ---------------------------------------------------------------------------
-- Menus
-- ---------------------------------------------------------------------------

--- Label for a module entry, straight from the registry so it cannot drift from the hub's.
local function moduleLabel(id)
    for _, mod in ipairs(registry.getEnabledModules()) do
        if mod.id == id then return mod.label or id end
    end
    return nil
end

local function drawMenuEntries(ctx, menu, s)
    local drew = false
    for _, e in ipairs(menu.entries) do
        if e.kind == "module" then
            -- The Loot window is uiState-managed rather than registry-registered, so it needs
            -- its own label; everything else takes the registry's.
            local label = (e.id == "loot") and "Loot" or moduleLabel(e.id)
            if label then
                drew = true
                local open = (e.id == "loot") and (ctx.uiState and ctx.uiState.lootUIOpen) or registry.isOpen(e.id)
                if open then
                    -- Lit = already open. Clicking again closes it.
                    ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Header))
                end
                if ImGui.Selectable(label .. "##dockmenu_" .. e.id, open == true) then
                    dockTop.queue(ctx, { kind = "window", id = e.id })
                end
                if open then ImGui.PopStyleColor() end
            end

        elseif e.kind == "hub" then
            drew = true
            if ImGui.Selectable(e.label .. "##dockmenu_hub") then
                dockTop.queue(ctx, { kind = "hub" })
            end

        elseif e.kind == "scripttracker" then
            drew = true
            if ImGui.Selectable(e.label .. "##dockmenu_st") then
                dockTop.queue(ctx, { kind = "scripttracker" })
            end

        elseif e.kind == "native" then
            drew = true
            -- These are game windows opened through MQ, not CoOpt windows. The bar is the one
            -- place that launches both kinds; there is no open/closed state to light, because
            -- MQ only gives us DoOpen.
            if ImGui.Selectable(e.label .. "##dockmenu_" .. e.window) then
                dockTop.queue(ctx, { kind = "native", window = e.window })
            end

        elseif e.kind == "loot_all" then
            drew = true
            if ImGui.Selectable("Loot All##dockmenu_lootall") then
                dockTop.queue(ctx, { kind = "loot_all" })
            end

        elseif e.kind == "loot_stop" then
            -- A verb only appears when it works: Stop exists only while something runs.
            if s.lootRunning or s.sellRunning then
                drew = true
                if ImGui.Selectable("Stop##dockmenu_stop") then
                    dockTop.queue(ctx, { kind = s.lootRunning and "loot_stop" or "sell_stop" })
                end
            end

        elseif e.kind == "auto_sell" then
            drew = true
            -- Greyed until a merchant is open, and it says why. No dialog ever tells you to
            -- "open a merchant first" after you have already clicked.
            if s.merchantOpen then
                if ImGui.Selectable("Auto Sell##dockmenu_autosell") then
                    dockTop.queue(ctx, { kind = "auto_sell" })
                end
            else
                theme.TextMuted("Auto Sell - no merchant")
            end
        end
    end
    if not drew then theme.TextMuted("Nothing enabled here.") end
end

--- Draw the open menu, if any, as a sibling borderless window anchored to its button.
local function renderMenu(ctx, s, edge)
    local uiState = ctx.uiState
    local pinned = uiState and uiState.dockPinnedMenu or nil
    local now = mq.gettime()

    local hoveredId = nil
    for id, r in pairs(M.buttons) do
        if r.hovered then hoveredId = id end
    end

    if hoveredId then
        hover.id = hoveredId
        hover.lastAt = now
        if ImGui.IsMouseClicked and ImGui.IsMouseClicked(ImGuiMouseButton.Left) and uiState then
            -- Hover opens, click pins (mockup 13c B).
            uiState.dockPinnedMenu = (pinned == hoveredId) and nil or hoveredId
            pinned = uiState.dockPinnedMenu
        end
    elseif hover.inMenu then
        hover.lastAt = now
    end

    local showId = pinned
    if not showId and hover.id and (now - hover.lastAt) <= constants.TIMING.DOCK_POPOVER_GRACE_MS then
        showId = hover.id
    end
    if not showId then
        hover.id, hover.inMenu = nil, false
        return
    end

    local menu = nil
    for _, m in ipairs(MENUS) do if m.id == showId then menu = m end end
    if not menu then return end

    local btn = M.buttons[showId] or {}
    local x, y, w, h = dockLayout.viewport()
    local rows = M.rows(ctx.layoutConfig)
    local barH = dockLayout.barHeight() * rows
    local px = btn.x or x
    -- Menus grow away from the edge the bar sits on, so they always open into the screen.
    local py = (edge == "bottom") and (y + h - barH) or (y + barH)
    local pivotY = (edge == "bottom") and 1.0 or 0.0

    if pivotY == 1.0 then
        ImGui.SetNextWindowPos(ImVec2(px, py), ImGuiCond.Always, ImVec2(0, 1))
    else
        ImGui.SetNextWindowPos(ImVec2(px, py))
    end
    ImGui.SetNextWindowSizeConstraints(ImVec2(190, 0), ImVec2(360, 420))

    local flags = bit32.bor(dockTop.barFlags(), ImGuiWindowFlags.AlwaysAutoResize or 0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, ImVec2(8, 6))
    local _, visible = ImGui.Begin("##CoOptDockMenu", true, flags)
    if visible then
        hover.inMenu = (ImGui.IsWindowHovered and ImGui.IsWindowHovered()) or false
        theme.TextHeaderAlt(menu.label)
        ImGui.Separator()
        pcall(drawMenuEntries, ctx, menu, s)
    else
        hover.inMenu = false
    end
    ImGui.End()
    ImGui.PopStyleVar(1)

    if pinned and ImGui.IsKeyPressed and ImGui.IsKeyPressed(ImGuiKey.Escape) then
        uiState.dockPinnedMenu = nil
        uiState.escConsumedThisFrame = true
        hover.id, hover.inMenu = nil, false
    end
end

-- ---------------------------------------------------------------------------
-- Chat
-- ---------------------------------------------------------------------------

local function cycleChat(ctx, forward)
    local lc = ctx.layoutConfig
    local order = { "hidden", "collapsed", "peek" }
    local cur = tostring(lc.DockChat or "collapsed")
    local idx = 2
    for i, v in ipairs(order) do if v == cur then idx = i end end
    idx = forward and (idx % #order) + 1 or ((idx - 2) % #order) + 1
    lc.DockChat = order[idx]
    if ctx.scheduleLayoutSave then ctx.scheduleLayoutSave() end
end

local function chatLineColor(channel)
    if channel == "coopt" then return theme.Colors.Header end
    if channel == "mq" then return theme.Colors.Info end
    if channel == "tell" then return theme.Colors.Highlight end
    if channel == "guild" then return theme.Colors.Success end
    if channel == "group" then return theme.Colors.RerollList end
    return nil
end

local function drawChatLine(e)
    local col = chatLineColor(e.channel)
    -- TextUnformatted, not Text: chat carries '%' (and item links), which Text would treat as
    -- a format string. views/effects.lua:88-92 hit the same thing.
    if col then ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(col)) end
    if ImGui.TextUnformatted then
        ImGui.TextUnformatted(e.text)
    else
        ImGui.Text((tostring(e.text):gsub("%%", "%%%%")))
    end
    if col then ImGui.PopStyleColor() end
end

local function renderChat(ctx, availW)
    local mode = tostring(ctx.layoutConfig.DockChat or "collapsed")

    if mode == "hidden" then
        local n = chatFeed.getUnread()
        local label = (n > 0) and string.format("chat  %d##dockChatShow", n) or "chat##dockChatShow"
        if ImGui.SmallButton(label) then cycleChat(ctx, true) end
        return
    end

    if ImGui.SmallButton((mode == "peek") and "v##dockChatCycle" or "^##dockChatCycle") then
        cycleChat(ctx, true)
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text("Cycle chat height: hidden / one line / four lines.")
        ImGui.EndTooltip()
    end
    ImGui.SameLine(0, 6)

    if mode == "collapsed" then
        -- One line: the newest from ANY channel, plus per-channel unread counts. Deliberately
        -- unfiltered -- with one line of space, the most recent thing that happened is more
        -- useful than the most recent thing on whichever tab was last clicked.
        local lines = chatFeed.getLines(1)
        if lines[1] then
            drawChatLine(lines[1])
        else
            theme.TextMuted("(no chat yet)")
        end
        for _, t in ipairs(CHAT_TABS) do
            local n = chatFeed.getUnread(t.id)
            if n > 0 then
                ImGui.SameLine(0, 8)
                theme.TextWarning(string.format("%s %d", t.label, n))
            end
        end
        return
    end

    -- peek: channel tabs plus the last few lines. Still no window.
    ImGui.BeginGroup()
    for _, t in ipairs(CHAT_TABS) do
        local n = chatFeed.getUnread(t.id)
        local label = (n > 0) and string.format("%s %d##dockTab%s", t.label, n, t.id)
                              or string.format("%s##dockTab%s", t.label, t.id)
        if ImGui.SmallButton(label) then
            activeTab = t.id
            chatFeed.clearUnread(t.id)
        end
        ImGui.SameLine(0, 4)
    end
    if ImGui.SmallButton("Type##dockChatType") then
        -- Typing is NOT reimplemented: hand focus to EQ's own chat input. An overlay that
        -- tried to own the game's input is the one thing that always goes wrong.
        dockTop.queue(ctx, { kind = "cmd", cmd = "/keypress enter" })
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text("Hands keyboard focus to EverQuest's own chat input.")
        ImGui.EndTooltip()
    end
    ImGui.EndGroup()

    local lineH = ImGui.GetTextLineHeightWithSpacing and ImGui.GetTextLineHeightWithSpacing() or 16
    if ImGui.BeginChild("dockChatLines", ImVec2(availW, lineH * PEEK_LINES), false,
            ImGuiWindowFlags.NoScrollbar) then
        local lines = chatFeed.getLines(PEEK_LINES, (activeTab ~= "all") and activeTab or nil)
        if #lines == 0 then
            theme.TextMuted("(no chat on this channel yet)")
        else
            for _, e in ipairs(lines) do drawChatLine(e) end
        end
    end
    ImGui.EndChild()
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------

--- Screen rect + hover state of each menu button this frame, so the menus can anchor to them.
M.buttons = {}

function M.render(ctx)
    local layoutConfig = ctx and ctx.layoutConfig
    if not M.isEnabled(layoutConfig) then return end

    dockLayout.refreshCacheKey()
    dockState.requestSell()          -- the Actions menu greys Auto Sell on merchant state
    local s = dockState.get()

    M.buttons = {}

    local edge = M.edge(layoutConfig)
    local rows = M.rows(layoutConfig)
    local vx, vy, vw, vh = dockLayout.viewport()
    local barH = dockLayout.barHeight() * rows
    local bx = vx
    local by = (edge == "bottom") and (vy + vh - barH) or vy

    ImGui.SetNextWindowPos(ImVec2(bx, by))
    ImGui.SetNextWindowSize(ImVec2(vw, barH))
    ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowBorderSize, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding,
        ImVec2(constants.UI.DOCK_SLOT_PADDING_X, constants.UI.DOCK_BAR_PADDING_Y))
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, ImVec2(constants.UI.DOCK_SLOT_GAP, 2))

    local _, visible = ImGui.Begin("##CoOptDockBottom", true, dockTop.barFlags())
    if visible then
        ImGui.AlignTextToFramePadding()

        -- Four menus, left to right.
        for _, menu in ipairs(MENUS) do
            local lit = (ctx.uiState and ctx.uiState.dockPinnedMenu) == menu.id
            if lit then ImGui.PushStyleColor(ImGuiCol.Button, theme.ToVec4(theme.Colors.Keep.Normal)) end
            ImGui.SmallButton(menu.label .. "##dockmenubtn_" .. menu.id)
            if lit then ImGui.PopStyleColor() end
            local hovered = ImGui.IsItemHovered and ImGui.IsItemHovered() or false
            local rmin = ImGui.GetItemRectMin and ImGui.GetItemRectMin()
            M.buttons[menu.id] = { x = rmin and rmin.x or nil, y = rmin and rmin.y or nil, hovered = hovered }
            ImGui.SameLine(0, constants.UI.DOCK_SLOT_GAP)
        end

        -- Settings and Layouts keep the right-hand anchor, so muscle memory survives a
        -- change of bottom-bar style (mockup 13c).
        -- GetWindowWidth, not the viewport width: SameLine's argument is an offset from the
        -- window's content origin, so it has to account for the strip's padding (the hub does
        -- the same thing for its Lock checkbox).
        local winW = ImGui.GetWindowWidth and ImGui.GetWindowWidth() or vw
        local rightW = 150
        local chatW = math.max(winW - ImGui.GetCursorPosX() - rightW - constants.UI.DOCK_SLOT_PADDING_X, 80)

        ImGui.BeginGroup()
        pcall(renderChat, ctx, chatW)
        ImGui.EndGroup()

        ImGui.SameLine(math.max(winW - rightW, 0))
        ImGui.AlignTextToFramePadding()
        if ImGui.SmallButton("Settings##dockSettings") then
            dockTop.queue(ctx, { kind = "window", id = "config" })
        end
    end
    ImGui.End()
    ImGui.PopStyleVar(4)

    renderMenu(ctx, s, edge)
end

return M
