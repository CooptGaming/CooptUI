--[[
    dock_bottom.lua — the command bar: launchers, native windows, Settings, and chat.

    This is where the Command Center window goes to die. Everything reachable from that
    window is reachable here, so it can stay closed for a whole session — that is a phase 3
    acceptance criterion, not a nicety.

    Structure is mockup 13c option B: four hover menus rather than a flat rail of sixteen
    buttons. A rail is faster for someone who has memorised it and is the widest possible
    strip; menus stay honest as the tool keeps growing. Chat is hidden or a collapsed
    one-liner here; the tabs, scrollback and typing all live in views/chat_window.lua, opened
    by clicking the line (mockup 13b's peek mode is retired in favor of that window).

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
local chatConsole = require('itemui.services.chat_console')
local registry = require('itemui.core.registry')

local M = {}

-- Menu definitions. Module entries are resolved through the registry at draw time, so a
-- companion the user disabled simply is not listed, and "lit" means registry.isOpen.
--
-- Phase 11 (23c): the old Items/Character/Layouts menus fold into ONE "Hub" menu — the
-- same launcher list vertically, grouped ITEMS / CHARACTER / LAYOUTS, "nothing in it is a
-- duplicate of a launcher, it is the same launcher in a form you can read". Pairs read as
-- one row that travels together: Inventory is the merged Bags+Bank hub (phase 10), and
-- Item Display + Aug Utility open and close as a unit. Shortcut labels wait on the
-- keybind proposal (§10 — audit first, nothing wired until approved).
local MENUS = {
    {
        id = "hub", label = "Hub",
        entries = {
            { kind = "header", label = "ITEMS" },
            { kind = "hub",    label = "Inventory (bags + bank)" },
            { kind = "pair",   ids = { "itemDisplay", "augmentUtility" } },
            { kind = "module", id = "mythicals" },
            { kind = "module", id = "reroll" },
            { kind = "module", id = "favorites" },
            { kind = "header", label = "CHARACTER" },
            { kind = "module", id = "equipment" },
            { kind = "module", id = "effects" },
            { kind = "module", id = "aa" },
            -- Phase 15: a registry module now (views/script_tracker.lua), so it lights,
            -- toggles and Esc-closes like everything else — no more /lua run sidecar
            -- from the bars (the standalone script remains for classic/CC).
            { kind = "module", id = "scripttracker" },
            { kind = "header", label = "LAYOUTS" },
            { kind = "layouts_dynamic" },
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

-- Unread badges for the collapsed one-liner (mockup 13b). Not "all": its badge would just
-- duplicate the sum of these, and the collapsed strip skips it for that reason below.
local CHAT_BADGE_TABS = {
    { id = "main",  label = "Main" },
    { id = "mq",    label = "MQ" },
    { id = "other", label = "Other" },
    { id = "coopt", label = "CoOpt" },
}

-- Transient menu hover state; the pinned menu id lives on uiState (dock state stays outside
-- ImGui's own storage).
local hover = { id = nil, lastAt = 0, inMenu = false }

--- How tall the strip is. Always one row now that peek (the old 5-row tab+lines mode) is
--- retired in favor of the chat window -- collapsed and hidden were already both one row, so
--- this used to only ever vary for peek.
function M.rows(layoutConfig)
    return 1
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

-- Lazy requires (same reason as inventory.lua's bankView): both modules register
-- themselves at require time, and a top-level require here would move their registry
-- slot. By first bar frame app.lua has loaded them, so these are table lookups.
local ItemDisplayViewLazy, TooltipDataLazy
local function itemDisplayView()
    ItemDisplayViewLazy = ItemDisplayViewLazy or require('itemui.views.item_display')
    return ItemDisplayViewLazy
end
local function tooltipData()
    TooltipDataLazy = TooltipDataLazy or require('itemui.utils.tooltip_data')
    return TooltipDataLazy
end

--- 23c's pill: empty aug sockets on the item currently in Item Display. PEEK ONLY —
--- reads the tooltip cache entry ID's own render already built; a cache miss is nil (no
--- pill), never a TLO walk. The bar must stay read-cheap every frame.
local function pairPillCount()
    local ok, n = pcall(function()
        local st = itemDisplayView().getState()
        local tabs = st.itemDisplayTabs or {}
        local idx = st.itemDisplayActiveTabIndex or 1
        local tab = tabs[idx]
        if not tab or not tab.item then return nil end
        local entry = tooltipData().getCachedTooltipEntry(tab.item,
            { source = tab.source, bag = tab.bag, slot = tab.slot })
        local lines = entry and entry.augLines
        if type(lines) ~= "table" then return nil end  -- augLines caches `false` for "none"
        local count = 0
        for _, l in ipairs(lines) do
            if l and l.augName == "empty" then count = count + 1 end
        end
        return count
    end)
    if not ok or not n or n <= 0 then return nil end
    return n
end

--- The Item Display + Aug Utility pair (23c): halves resolve through the registry, the
--- pair exists only when BOTH are enabled, and it opens/closes as a unit — "the open pair
--- lights the whole chip, because they travel together".
local function pairModules()
    local a, b = moduleLabel("itemDisplay"), moduleLabel("augmentUtility")
    if a and b then return a, b end
    return nil, nil
end

local function pairOpen()
    return (registry.isOpen("itemDisplay") or registry.isOpen("augmentUtility")) == true
end

--- Open both halves, or close both when the pair is already open. Queued, never a direct
--- registry write from the render callback.
local function togglePair(ctx)
    if pairOpen() then
        -- Close whichever halves are open (toggle only the open ones).
        if registry.isOpen("itemDisplay") then
            dockTop.queue(ctx, { kind = "window", id = "itemDisplay", toggle = true })
        end
        if registry.isOpen("augmentUtility") then
            dockTop.queue(ctx, { kind = "window", id = "augmentUtility", toggle = true })
        end
    else
        -- Idempotent opens (non-toggle) for both.
        dockTop.queue(ctx, { kind = "window", id = "itemDisplay" })
        dockTop.queue(ctx, { kind = "window", id = "augmentUtility" })
    end
end

--- Is the hub (the merged Inventory in bars) on screen? The whole Bags|Bank chip lights
--- on this OR a stray open bank companion (defensive — bank is classicOnly in bars).
local function hubOpen(ctx)
    local f = ctx and ctx.getShouldDraw
    return ((f and f()) or registry.isOpen("bank")) == true
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
            local lit = hubOpen(ctx)
            if lit then ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Header)) end
            -- Selectable returns (selected, pressed) — read the SECOND (see the module
            -- branch above for the bug the first return caused).
            local _, pressedHub = ImGui.Selectable(e.label .. "##dockmenu_hub", lit)
            if pressedHub then
                dockTop.queue(ctx, { kind = "hub" })
            end
            if lit then ImGui.PopStyleColor() end

        elseif e.kind == "header" then
            -- 23c group label: furniture, not a row. Never counts as `drew` on its own —
            -- a menu of nothing but headers is still "Nothing enabled here."
            if theme.TextFurniture then theme.TextFurniture(e.label) else theme.TextMuted(e.label) end

        elseif e.kind == "pair" then
            -- Item Display + Aug Utility as one row that travels together (23c). Only
            -- offered when both halves are enabled; the pill is the empty-socket count on
            -- ID's current subject, peeked from the tooltip cache.
            local a, b = pairModules()
            if a and b then
                drew = true
                local lit = pairOpen()
                local label = a .. " + " .. b
                local pill = pairPillCount()
                if pill then label = string.format("%s  %d", label, pill) end
                if lit then ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Header)) end
                local _, pressedPair = ImGui.Selectable(label .. "##dockmenu_pair_idau", lit)
                if pressedPair then
                    togglePair(ctx)
                end
                if lit then ImGui.PopStyleColor() end
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
            end
        end
    end
    if not drew then theme.TextMuted("Nothing enabled here.") end
end

--- Draw the open menu, if any, as a sibling borderless window anchored to its button.
--- Hover opens it; a click on the button does the same (you have to be hovering to click, so
--- it adds nothing beyond keeping hover.lastAt fresh) -- there is no pin anymore. The menu
--- closes DOCK_POPOVER_GRACE_MS after the mouse leaves both the button and the menu itself,
--- exactly like dock_top's popovers (hover.inMenu is this file's equivalent of hover.inPopover).
local function renderMenu(ctx, s, edge)
    local uiState = ctx.uiState
    local now = mq.gettime()

    local hoveredId = nil
    for id, r in pairs(M.buttons) do
        if r.hovered then hoveredId = id end
    end

    if hoveredId then
        hover.id = hoveredId
        hover.lastAt = now
    elseif hover.inMenu then
        hover.lastAt = now       -- the mouse is in the menu itself; keep it alive
    end

    local showId = nil
    if hover.id and (now - hover.lastAt) <= constants.TIMING.DOCK_POPOVER_GRACE_MS then
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
    -- No pin, so no Esc-unpin path: the menu has nothing to unpin, and Esc otherwise falls
    -- through to the hub's own LIFO close undisturbed (dock_top's popover Esc handling is the
    -- one that still stakes a claim on dockEscConsumed, for the thing that can still be pinned).
end

-- ---------------------------------------------------------------------------
-- Launcher buttons (DockBottomStyle = "buttons" -- the mockup's second option: a row of
-- direct buttons instead of hover menus). "bags" is the hub, same as the menus' hub entry;
-- everything else is registry-driven exactly like drawMenuEntries' module branch, so a
-- disabled companion simply is not listed here either.
-- ---------------------------------------------------------------------------

--- Reroll's pending count, for the badge on its launcher button. There is no direct "how many
--- pending" field on rerollService.getState() -- that table holds in-flight add/sync
--- bookkeeping (pendingRerollAdd, pendingRerollSync, ...), not the pending LISTS themselves.
--- The lists live behind getPendingAugList()/getPendingMythicalList() (views/reroll.lua reads
--- them the same way), so that is what is counted here.
local function rerollPendingCount(ctx)
    local rs = ctx and ctx.rerollService
    if not rs then return 0 end
    local aug = (rs.getPendingAugList and rs.getPendingAugList()) or {}
    local myth = (rs.getPendingMythicalList and rs.getPendingMythicalList()) or {}
    return #aug + #myth
end

--- The ordered, filtered list of launcher entries this frame. Shared by the width estimate
--- and the actual draw so the two never disagree about what is on the bar.
---
--- Phase 11 (23c): pairs read as one chip with two halves split by a hairline, and the
--- open pair lights the whole chip. "bags" becomes the Bags|Bank pair (both halves are the
--- merged hub — phase 10 — so both route there; the split names the two panes). If
--- itemDisplay and augmentUtility are BOTH present/enabled, the first of them becomes the
--- Item Display|Aug Utility pair and the other's standalone entry is absorbed.
--- Entry shapes: { id, label, isHub } (plain) or { isPair = true, id, halves = { {label,
--- action}, ... } } where action is the queue payload half-clicks send.
local function launcherEntries(ctx, layoutConfig)
    local ids = dockTop.csv(layoutConfig.DockButtons)
    local present = {}
    for _, id in ipairs(ids) do present[id] = true end
    local idLabel, auLabel = pairModules()
    local pairIDAU = present["itemDisplay"] and present["augmentUtility"] and idLabel and auLabel
    local out = {}
    for _, id in ipairs(ids) do
        if id == "bags" then
            out[#out + 1] = { isPair = true, id = "bagsbank", halves = {
                { label = "Bags", action = { kind = "hub" } },
                { label = "Bank", action = { kind = "hub" } },
            } }
        elseif id == "bank" and present["bags"] then
            -- Absorbed into the Bags|Bank pair above (saved CSVs still carry the id).
            local _ = id
        elseif pairIDAU and (id == "itemDisplay" or id == "augmentUtility") then
            -- The pair renders at the FIRST half's slot; the second occurrence is absorbed.
            if not out._idauPlaced then
                out._idauPlaced = true
                local auHalf = auLabel
                local pill = pairPillCount()
                if pill then auHalf = string.format("%s %d", auHalf, pill) end
                out[#out + 1] = { isPair = true, id = "idau", halves = {
                    { label = idLabel, action = { kind = "window", id = "itemDisplay", toggle = true } },
                    { label = auHalf,  action = { kind = "window", id = "augmentUtility", toggle = true } },
                } }
            end
        else
            local label = moduleLabel(id)
            if label then
                if id == "reroll" then
                    local n = rerollPendingCount(ctx)
                    if n > 0 then label = string.format("%s %d", label, n) end
                end
                out[#out + 1] = { id = id, label = label, isHub = false }
            end
        end
    end
    out._idauPlaced = nil
    return out
end

--- Whole-chip lit state for a pair entry (23c: the open pair lights the whole chip).
local function pairEntryLit(ctx, e)
    if e.id == "bagsbank" then return hubOpen(ctx) end
    if e.id == "idau" then return pairOpen() end
    return false
end

--- Rough reserved width for the whole launcher row, so the chat strip ahead of it (buttons
--- style puts chat FIRST -- see M.render) knows how much room is left. Not pixel-exact: the
--- bars' anti-jitter discipline (fixed measured slot widths) is for the top bar's segments,
--- which hold the SAME content across frames; a launcher row's content (the reroll badge)
--- can change, and re-measuring each frame is cheap enough that drift never accumulates.
local function launcherRowWidth(ctx, layoutConfig)
    local pad = (constants.UI.DOCK_SLOT_PADDING_X or 12) * 2
    local total, first = 0, true
    for _, e in ipairs(launcherEntries(ctx, layoutConfig)) do
        if not first then total = total + constants.UI.DOCK_SLOT_GAP end
        first = false
        if e.isPair then
            -- Two half-buttons + the 1px hairline between them.
            for _, h in ipairs(e.halves) do
                total = total + dockLayout.textWidth(h.label) + pad
            end
            total = total + 1
        else
            total = total + dockLayout.textWidth(e.label) + pad
        end
    end
    return total
end

--- Draw the launcher row itself. "bags" queues the hub, same as the menus' hub entry; every
--- other id toggles its companion window, LIT (Keep.Normal) while open -- the same
--- push/pop-around-SmallButton idiom this file already used for the (now-removed) pinned menu
--- button, repointed at registry.isOpen instead of a pin.
local function drawLauncherButtons(ctx, layoutConfig)
    local first = true
    for _, e in ipairs(launcherEntries(ctx, layoutConfig)) do
        if not first then ImGui.SameLine(0, constants.UI.DOCK_SLOT_GAP) end
        first = false
        if e.isPair then
            -- One chip, two halves split by a hairline (the 1px gap against the dark bar).
            -- The whole chip lights when the pair is open — both halves get the lit fill.
            local lit = pairEntryLit(ctx, e)
            if lit then ImGui.PushStyleColor(ImGuiCol.Button, theme.ToVec4(theme.Colors.Keep.Normal)) end
            for hi, h in ipairs(e.halves) do
                if hi > 1 then ImGui.SameLine(0, 1) end
                if ImGui.SmallButton(h.label .. "##dockbtn_" .. e.id .. "_" .. hi) then
                    dockTop.queue(ctx, h.action)
                end
            end
            if lit then ImGui.PopStyleColor() end
        else
            local open = (not e.isHub) and registry.isOpen(e.id) or false
            if open then ImGui.PushStyleColor(ImGuiCol.Button, theme.ToVec4(theme.Colors.Keep.Normal)) end
            if ImGui.SmallButton(e.label .. "##dockbtn_" .. e.id) then
                if e.isHub then
                    dockTop.queue(ctx, { kind = "hub" })
                else
                    dockTop.queue(ctx, { kind = "window", id = e.id, toggle = true })
                end
            end
            if open then ImGui.PopStyleColor() end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Chat
-- ---------------------------------------------------------------------------

--- hidden <-> collapsed. Peek (the old third mode, five rows of tabs+lines) is retired in
--- favor of the chat window -- a stored "peek" from an older session reads as collapsed (see
--- renderChat's mode read below), it is just no longer a state this toggles INTO.
local function cycleChat(ctx)
    local lc = ctx.layoutConfig
    local cur = tostring(lc.DockChat or "collapsed")
    local next_ = (cur == "hidden") and "collapsed" or "hidden"
    -- setLayoutValue, not a bare write + scheduleLayoutSave: during the 600ms save debounce
    -- loadLayoutConfig still serves the CACHED parse, which would re-apply the old value over
    -- this change and then persist the revert -- the exact bug LayoutUtils.setLayoutValue
    -- exists to close (config_general.lua routes its dock keys the same way).
    if ctx.setLayoutValue then
        ctx.setLayoutValue("DockChat", next_)
    else
        lc.DockChat = next_
        if ctx.scheduleLayoutSave then ctx.scheduleLayoutSave() end
    end
end

--- Read DockChat, mapping a legacy "peek" (a session's INI predates this retirement) onto
--- its closest surviving mode.
local function chatMode(layoutConfig)
    local mode = tostring((layoutConfig or {}).DockChat or "collapsed")
    return (mode == "peek") and "collapsed" or mode
end

local function drawChatLine(e)
    local col = chatConsole.channelColor(e.channel)
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

--- Open the chat window through the same queue every other bar action uses -- never a direct
--- registry write from inside the render callback.
local function openChatWindow(ctx)
    dockTop.queue(ctx, { kind = "window", id = "chat", toggle = true })
end

local function renderChat(ctx, availW)
    local mode = chatMode(ctx.layoutConfig)
    local chatStartX = ImGui.GetCursorPosX and ImGui.GetCursorPosX() or 0

    if mode == "hidden" then
        local n = chatFeed.getUnread()
        local label = (n > 0) and string.format("chat  %d##dockChatShow", n) or "chat##dockChatShow"
        -- Opens the window directly now -- there is no more collapsed strip to cycle into on
        -- the way there, so this button's whole job is "show me chat".
        if ImGui.SmallButton(label) then openChatWindow(ctx) end
        return
    end

    -- collapsed: the only other mode. The '^' still cycles (collapsed <-> hidden); clicking
    -- the line itself is the way to the full window.
    if ImGui.SmallButton("^##dockChatCycle") then
        cycleChat(ctx)
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text("Hide the chat line. Click the line itself to open the chat window.")
        ImGui.EndTooltip()
    end
    ImGui.SameLine(0, 6)

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
            local drewBadge = false
            for _, t in ipairs(CHAT_BADGE_TABS) do
                local n = chatFeed.getUnread(t.id)
                if n > 0 then
                    if drewBadge then ImGui.SameLine(0, 8) end
                    drewBadge = true
                    theme.PushJunkButton()
                    if ImGui.SmallButton(string.format("%s %s##dockUnread%s", t.label,
                            (n > 99) and "99+" or tostring(n), t.id)) then
                        chatFeed.clearUnread(t.id)
                        -- Non-toggle form on purpose: a window action without toggle is an
                        -- idempotent OPEN, so clicking a badge while the chat window is
                        -- already showing another tab clears the count without closing it.
                        dockTop.queue(ctx, { kind = "window", id = "chat" })
                    end
                    theme.PopButtonColors()
                    if ImGui.IsItemHovered() then
                        ImGui.BeginTooltip()
                        ImGui.Text(string.format("%d unread on %s - click to open chat and clear.", n, t.label))
                        ImGui.EndTooltip()
                    end
                end
            end
            if drewBadge then ImGui.SameLine(0, 8) end
            local lines = chatFeed.getLines(1)
            if lines[1] then
                drawChatLine(lines[1])
            else
                theme.TextMuted("(no chat yet - click to open chat)")
            end
        end)
    end
    ImGui.EndChild()
    -- Click anywhere in the line's child (badges included) opens the window. EndChild();
    -- IsItemHovered() is the established pattern for "was the mouse over the child I just
    -- closed" -- dock_top.lua's segment slots use it the same way.
    local lineHovered = ImGui.IsItemHovered and ImGui.IsItemHovered() or false
    if lineHovered and ImGui.IsMouseClicked and ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
        openChatWindow(ctx)
    end
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
    local style = tostring(layoutConfig.DockBottomStyle or "menus")

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

        -- GetWindowWidth, not the viewport width: SameLine's argument is an offset from the
        -- window's content origin, so it has to account for the strip's padding (the hub does
        -- the same thing for its Lock checkbox).
        local winW = ImGui.GetWindowWidth and ImGui.GetWindowWidth() or vw
        -- Sized for what is actually drawn on the right, which is Settings alone. Layouts
        -- landed as the fifth hover menu on the left (phase 4), so the right anchor stays
        -- Settings-only.
        local rightW = dockLayout.slotWidth("dockRight", { "Settings" }, 16)

        if style == "buttons" then
            -- Second mockup: chat FIRST (left edge), then one button per DockButtons id, then
            -- the same right-anchored Settings every style keeps.
            local buttonsW = launcherRowWidth(ctx, layoutConfig)
            local chatW = math.max(winW - buttonsW - rightW - constants.UI.DOCK_SLOT_PADDING_X * 2, 80)

            ImGui.BeginGroup()
            dockLayout.contained(ctx.uiState, "dock chat", renderChat, ctx, chatW)
            ImGui.EndGroup()
            -- Section divider between chat and the launcher row, drawn into the gap so it
            -- costs no width (see dockTop.drawDividerAt).
            local cnx, cny = dockLayout.itemRectMin()
            local cxx, cxy = dockLayout.itemRectMax()
            if cxx and cxy then
                dockTop.drawDividerAt(cxx + constants.UI.DOCK_SLOT_GAP * 0.5, (cny or (cxy - 16)) + 1, cxy - 1)
            end
            ImGui.SameLine(0, constants.UI.DOCK_SLOT_GAP)
            dockLayout.contained(ctx.uiState, "dock launcher buttons", drawLauncherButtons, ctx, layoutConfig)
        else
            -- The hover menus, left to right (Hub / Actions / Game windows), with a section
            -- divider at the one group boundary left: CoOpt windows (Hub/Actions) | the
            -- game's own windows | chat. Dividers draw into the gaps -- zero layout width.
            local DIVIDER_BEFORE = { game = true }
            local prevRight, prevTop, prevBot = nil, nil, nil
            for _, menu in ipairs(MENUS) do
                if DIVIDER_BEFORE[menu.id] and prevRight then
                    dockTop.drawDividerAt(prevRight + constants.UI.DOCK_SLOT_GAP * 0.5,
                        (prevTop or (prevBot - 16)) + 1, prevBot - 1)
                end
                ImGui.SmallButton(menu.label .. "##dockmenubtn_" .. menu.id)
                local hovered = ImGui.IsItemHovered and ImGui.IsItemHovered() or false
                -- Two numbers, not an ImVec2 -- indexing this return as rmin.x is what killed
                -- everything after the Items button (see dockLayout.itemRectMin).
                local rx, ry = dockLayout.itemRectMin()
                M.buttons[menu.id] = { x = rx, y = ry, hovered = hovered }
                local mxx, mxy = dockLayout.itemRectMax()
                if mxx and mxy then prevRight, prevTop, prevBot = mxx, ry, mxy end
                ImGui.SameLine(0, constants.UI.DOCK_SLOT_GAP)
            end
            -- Last boundary: menu row | chat.
            if prevRight and prevBot then
                dockTop.drawDividerAt(prevRight + constants.UI.DOCK_SLOT_GAP * 0.5,
                    (prevTop or (prevBot - 16)) + 1, prevBot - 1)
            end

            local chatW = math.max(winW - ImGui.GetCursorPosX() - rightW - constants.UI.DOCK_SLOT_PADDING_X, 80)
            ImGui.BeginGroup()
            dockLayout.contained(ctx.uiState, "dock chat", renderChat, ctx, chatW)
            ImGui.EndGroup()
        end

        ImGui.SameLine(math.max(winW - rightW, 0))
        ImGui.AlignTextToFramePadding()
        if ImGui.SmallButton("Settings##dockSettings") then
            dockTop.queue(ctx, { kind = "window", id = "config" })
        end
        end)
    end
    ImGui.End()
    ImGui.PopStyleVar(4)

    -- Menus style only: buttons style has no hover menus, and M.buttons stays empty for it
    -- (populated only in the branch above), so renderMenu would just no-op anyway -- gating it
    -- here avoids a stray leftover menu surviving a mid-session style switch during its grace
    -- window.
    if style ~= "buttons" then
        renderMenu(ctx, s, edge)
    end
    renderPresetSavePrompt(ctx)
    -- With the status bar off, this bar hosts the 14d degraded strip; rows (not 1) lands
    -- it above the whole strip even when peek chat makes the bar five rows tall.
    if not dockTop.isEnabled(ctx.layoutConfig) and dockTop.renderDegradedStrip then
        dockTop.renderDegradedStrip(ctx, s, edge, M.rows(ctx.layoutConfig))
    end
end

return M
