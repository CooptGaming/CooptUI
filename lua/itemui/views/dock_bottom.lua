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
    {
        -- Phase 4 (mockup 10c): presets + Re-tidy. Entries are dynamic — the preset list
        -- comes from uiState.dockPresetNames, primed OUTSIDE the frame by main_loop so this
        -- file keeps the "no file reads" bar rule.
        id = "layouts", label = "Layouts",
        entries = { { kind = "layouts_dynamic" } },
    },
}

local CHAT_TABS = {
    -- "all" is a real chat_feed bucket: getUnread("all") sums, clearUnread("all") wipes,
    -- and getLines' tab filter is skipped for it in the peek renderer below.
    { id = "all",   label = "All" },
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
                -- toggle: the entry is lit when open and says so, so clicking it again has to
                -- actually close the window. The status bar's buttons omit this flag on
                -- purpose -- clicking "Rules" twice should not close Settings.
                -- Selectable returns (selected, pressed) in this binding -- SELECTED first
                -- (lua_ImGuiWidgets.cpp:906). Testing the first return with `open` passed in
                -- meant every lit entry queued a close-toggle EVERY FRAME the menu was
                -- visible, slamming its window shut the moment the menu opened.
                local _, pressed = ImGui.Selectable(label .. "##dockmenu_" .. e.id, open == true)
                if pressed then
                    dockTop.queue(ctx, { kind = "window", id = e.id, toggle = true })
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

        elseif e.kind == "layouts_dynamic" then
            drew = true
            local lc = ctx.layoutConfig or {}
            local active = tostring(lc.LayoutPreset or "")
            local names = (ctx.uiState and ctx.uiState.dockPresetNames) or {}
            if active ~= "" then
                theme.TextMuted("layout: " .. active)
            else
                theme.TextMuted("layout: (none)")
            end
            if #names == 0 then
                theme.TextMuted("No presets yet.")
            end
            for _, name in ipairs(names) do
                local lit = (name == active)
                if lit then ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Header)) end
                local _, pressed = ImGui.Selectable(name .. "##dockpreset_" .. name, lit)
                if pressed then
                    dockTop.queue(ctx, { kind = "preset", name = name })
                end
                if lit then ImGui.PopStyleColor() end
            end
            ImGui.Separator()
            if ImGui.Selectable("Re-tidy now##dockmenu_retidy") then
                dockTop.queue(ctx, { kind = "retidy" })
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Puts every open window back into its zone and forgets hand-placed positions.")
                ImGui.EndTooltip()
            end
            if ImGui.Selectable("Save current as...##dockmenu_presetsave") and ctx.uiState then
                ctx.uiState.dockPresetSavePrompt = true
                ctx.uiState.dockPinnedMenu = nil
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
    -- Style var precedes Begin, so Begin failing has to unwind it -- the same invariant
    -- M.render enforces on its own Begin below.
    local okBegin, _, visible = pcall(ImGui.Begin, "##CoOptDockMenu", true, flags)
    if not okBegin then
        ImGui.PopStyleVar(1)
        return
    end
    if visible then
        -- Contained: nothing may escape between Begin and End (see dock_top's render), and
        -- the error is queued for main_loop to print rather than discarded.
        dockLayout.contained(uiState, "dock menu " .. tostring(showId), function()
            hover.inMenu = (ImGui.IsWindowHovered and ImGui.IsWindowHovered()) or false
            theme.TextHeaderAlt(menu.label)
            ImGui.Separator()
            drawMenuEntries(ctx, menu, s)
        end)
    else
        hover.inMenu = false
    end
    ImGui.End()
    ImGui.PopStyleVar(1)

    if pinned and ImGui.IsKeyPressed and ImGui.IsKeyPressed(ImGuiKey.Escape) then
        uiState.dockPinnedMenu = nil
        -- See the note in dock_top's renderPopover: the hub resets escConsumedThisFrame after
        -- the bars have drawn, so the claim is staked on dockEscConsumed and handed over there.
        uiState.dockEscConsumed = true
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
    -- setLayoutValue, not a bare write + scheduleLayoutSave: during the 600ms save debounce
    -- loadLayoutConfig still serves the CACHED parse, which would re-apply the old value over
    -- this change and then persist the revert -- the exact bug LayoutUtils.setLayoutValue
    -- exists to close (config_general.lua routes its dock keys the same way).
    if ctx.setLayoutValue then
        ctx.setLayoutValue("DockChat", order[idx])
    else
        lc.DockChat = order[idx]
        if ctx.scheduleLayoutSave then ctx.scheduleLayoutSave() end
    end
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
    local chatStartX = ImGui.GetCursorPosX and ImGui.GetCursorPosX() or 0

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
        -- Clipped to the chat budget: a long line would otherwise run under the
        -- right-anchored Settings button, which is drawn over it afterwards.
        local usedX = (ImGui.GetCursorPosX and ImGui.GetCursorPosX() or 0) - chatStartX
        local lineH = ImGui.GetTextLineHeightWithSpacing and ImGui.GetTextLineHeightWithSpacing() or 16
        local clipW = math.max(availW - usedX, 60)
        if ImGui.BeginChild("dockChatCollapsed", ImVec2(clipW, lineH), false,
                bit32.bor(ImGuiWindowFlags.NoScrollbar, ImGuiWindowFlags.NoScrollWithMouse)) then
            dockLayout.contained(ctx.uiState, "dock chat line", function()
                -- Badges FIRST, then the line: the line is the thing that can be arbitrarily
                -- long, and drawn first it would push the clear-unread affordance out of the
                -- clip exactly when chat is busy and the counts matter most.
                -- Clickable, and capped for display. clearUnread previously had exactly one
                -- caller -- a peek-mode tab -- so in the default collapsed mode (and in hidden
                -- mode) the counts were unclearable and just climbed for the whole session.
                local drewBadge = false
                for _, t in ipairs(CHAT_TABS) do
                    -- Skip the All tab here: its badge would just duplicate the sum of the
                    -- per-channel badges next to it.
                    local n = (t.id ~= "all") and chatFeed.getUnread(t.id) or 0
                    if n > 0 then
                        if drewBadge then ImGui.SameLine(0, 8) end
                        drewBadge = true
                        theme.PushJunkButton()
                        if ImGui.SmallButton(string.format("%s %s##dockUnread%s", t.label,
                                (n > 99) and "99+" or tostring(n), t.id)) then
                            chatFeed.clearUnread(t.id)
                        end
                        theme.PopButtonColors()
                        if ImGui.IsItemHovered() then
                            ImGui.BeginTooltip()
                            ImGui.Text(string.format("%d unread on %s - click to clear.", n, t.label))
                            ImGui.EndTooltip()
                        end
                    end
                end
                if drewBadge then ImGui.SameLine(0, 8) end
                local lines = chatFeed.getLines(1)
                if lines[1] then
                    drawChatLine(lines[1])
                else
                    theme.TextMuted("(no chat yet)")
                end
            end)
        end
        ImGui.EndChild()
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
        -- The tab being displayed is by definition read: without this, the active tab's
        -- badge climbs while its own lines sit on screen.
        chatFeed.clearUnread(activeTab)
    end
    ImGui.EndChild()
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------

--- Screen rect + hover state of each menu button this frame, so the menus can anchor to them.
M.buttons = {}

--- The work rect companion windows may occupy: viewport minus every visible bar strip on
--- each edge. Stashed into uiState.dockWorkRect by app.lua's render callback each frame so
--- window_zones (a main-loop service that must not call ImGui) can place against it.
function M.currentWorkRect(layoutConfig)
    local topN, botN = 0, 0
    if dockTop.isEnabled(layoutConfig) then
        if dockTop.edge(layoutConfig) == "top" then topN = topN + 1 else botN = botN + 1 end
    end
    if M.isEnabled(layoutConfig) then
        local rows = M.rows(layoutConfig)
        if M.edge(layoutConfig) == "top" then topN = topN + rows else botN = botN + rows end
    end
    local x, y, w, h = dockLayout.workArea(topN, botN)
    return { x = x, y = y, w = w, h = h }
end

--- "Save current as..." prompt (mockup 10c). A real focusable mini-window, NOT bar-flagged:
--- typing needs keyboard focus, which the bars are built to refuse.
local function renderPresetSavePrompt(ctx)
    local uiState = ctx.uiState
    if not uiState or not uiState.dockPresetSavePrompt then return end
    local x, y, w, h = dockLayout.viewport()
    ImGui.SetNextWindowPos(ImVec2(x + w / 2 - 160, y + h / 2 - 40), ImGuiCond.Appearing)
    local flags = bit32.bor(ImGuiWindowFlags.NoCollapse, ImGuiWindowFlags.AlwaysAutoResize,
        ImGuiWindowFlags.NoSavedSettings)
    local okBegin, open, visible = pcall(ImGui.Begin, "Save layout preset##dockPresetSave", true, flags)
    if not okBegin then return end
    if open == false then uiState.dockPresetSavePrompt = nil end
    if visible then
        dockLayout.contained(uiState, "preset save prompt", function()
            ImGui.Text("Name this arrangement:")
            -- Two args only: this binding's third parameter is FLAGS, not a buffer size
            -- (Lua strings need none) — a stray 64 here silently set EnterReturnsTrue-class
            -- behaviour.
            local buf, changed = ImGui.InputText("##dockPresetSaveName",
                tostring(uiState.dockPresetSaveName or ""))
            if changed then uiState.dockPresetSaveName = buf end
            local name = tostring(uiState.dockPresetSaveName or ""):match("^%s*(.-)%s*$")
            theme.TextMuted("Captures open windows, zones and sizes. No [ ] or : in names.")
            local valid = name ~= "" and not name:find("[%[%]:]")
            if valid then
                if ImGui.Button("Save##dockPresetSaveGo") then
                    dockTop.queue(ctx, { kind = "preset_save", name = name })
                    uiState.dockPresetSavePrompt = nil
                    uiState.dockPresetSaveName = nil
                end
            else
                theme.TextMuted("Save")
            end
            ImGui.SameLine(0, 8)
            if ImGui.Button("Cancel##dockPresetSaveCancel") then
                uiState.dockPresetSavePrompt = nil
                uiState.dockPresetSaveName = nil
            end
            if ImGui.IsKeyPressed and ImGui.IsKeyPressed(ImGuiKey.Escape) then
                uiState.dockPresetSavePrompt = nil
                uiState.dockPresetSaveName = nil
                uiState.dockEscConsumed = true
            end
        end)
    end
    ImGui.End()
end

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

    -- See dock_top: the style vars must precede Begin, so Begin failing has to unwind them.
    local okBegin, _, visible = pcall(ImGui.Begin, "##CoOptDockBottom", true, dockTop.barFlags())
    if not okBegin then
        ImGui.PopStyleVar(4)
        return
    end
    if visible then
        -- Everything between Begin and End runs contained for the same reason dock_top
        -- isolates its segments: app.lua's outer pcall sits OUTSIDE the four PushStyleVar
        -- calls above, so an error escaping this window would skip End() and PopStyleVar(4)
        -- and leak four style-stack entries per frame until ImGui asserts. contained, not a
        -- bare pcall: the discarded error message is how the rmin.x crash blanked this whole
        -- bar past the Items button with nothing in the log.
        dockLayout.contained(ctx.uiState, "dock command bar", function()
        ImGui.AlignTextToFramePadding()

        -- The hover menus, left to right (Items / Character / Actions / Game windows / Layouts).
        for _, menu in ipairs(MENUS) do
            local lit = (ctx.uiState and ctx.uiState.dockPinnedMenu) == menu.id
            if lit then ImGui.PushStyleColor(ImGuiCol.Button, theme.ToVec4(theme.Colors.Keep.Normal)) end
            ImGui.SmallButton(menu.label .. "##dockmenubtn_" .. menu.id)
            if lit then ImGui.PopStyleColor() end
            local hovered = ImGui.IsItemHovered and ImGui.IsItemHovered() or false
            -- Two numbers, not an ImVec2 -- indexing this return as rmin.x is what killed
            -- everything after the Items button (see dockLayout.itemRectMin).
            local rx, ry = dockLayout.itemRectMin()
            M.buttons[menu.id] = { x = rx, y = ry, hovered = hovered }
            ImGui.SameLine(0, constants.UI.DOCK_SLOT_GAP)
        end

        -- Settings and Layouts keep the right-hand anchor, so muscle memory survives a
        -- change of bottom-bar style (mockup 13c).
        -- GetWindowWidth, not the viewport width: SameLine's argument is an offset from the
        -- window's content origin, so it has to account for the strip's padding (the hub does
        -- the same thing for its Lock checkbox).
        local winW = ImGui.GetWindowWidth and ImGui.GetWindowWidth() or vw
        -- Sized for what is actually drawn on the right, which is Settings alone. Layouts
        -- landed as the fifth hover menu on the left (phase 4), so the right anchor stays
        -- Settings-only.
        local rightW = dockLayout.slotWidth("dockRight", { "Settings" }, 16)
        local chatW = math.max(winW - ImGui.GetCursorPosX() - rightW - constants.UI.DOCK_SLOT_PADDING_X, 80)

        ImGui.BeginGroup()
        dockLayout.contained(ctx.uiState, "dock chat", renderChat, ctx, chatW)
        ImGui.EndGroup()

        ImGui.SameLine(math.max(winW - rightW, 0))
        ImGui.AlignTextToFramePadding()
        if ImGui.SmallButton("Settings##dockSettings") then
            dockTop.queue(ctx, { kind = "window", id = "config" })
        end
        end)
    end
    ImGui.End()
    ImGui.PopStyleVar(4)

    renderMenu(ctx, s, edge)
    renderPresetSavePrompt(ctx)
    -- With the status bar off, this bar hosts the 14d degraded strip; rows (not 1) lands
    -- it above the whole strip even when peek chat makes the bar five rows tall.
    if not dockTop.isEnabled(ctx.layoutConfig) and dockTop.renderDegradedStrip then
        dockTop.renderDegradedStrip(ctx, s, edge, M.rows(ctx.layoutConfig))
    end
end

return M
