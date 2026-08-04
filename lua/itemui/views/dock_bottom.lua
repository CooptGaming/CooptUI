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
-- Leaf module (mq only, registers nothing) — safe at the top, unlike view modules whose
-- require-time registration order is launcher-button order.
local keybinds = require('itemui.utils.keybinds')
local hubList = require('itemui.components.hub_list')
local windowHeader = require('itemui.components.window_header')

local M = {}

-- Menu definitions. Module entries are resolved through the registry at draw time, so a
-- companion the user disabled simply is not listed, and "lit" means registry.isOpen.
--
-- Phase 11 (23c): the old Items/Character/Layouts menus fold into ONE "Hub" menu — the
-- same launcher list vertically, grouped ITEMS / CHARACTER / LAYOUTS, "nothing in it is a
-- duplicate of a launcher, it is the same launcher in a form you can read". Item Display
-- + Aug Utility are a real pair — one row, opens and closes as a unit. Bags and Bank are
-- NOT: the merge was rolled back, so they are two rows here and a two-half chip on the
-- bar, aligned by window_zones rather than welded together.
-- TURN 27 — THIS BAR IS ONE KIND OF THING. Every chip between the chat cell and Native UI
-- opens or closes a window. Nothing here starts a job and nothing reports one. That rule
-- is holdable in your head and it decides where anything new goes without a discussion.
-- It retired two menus:
--
--   * Hub — the top bar's CoOpt cell opens the same hub_list.ENTRIES index (26a), so a
--     chip here was a launcher for the list of launchers sitting right next to it.
--   * Actions — Loot All and Auto Sell live on the top bar beside the LANE THAT REPORTS
--     THEM. A duplicate here would be a second way to start the same job with no feedback
--     attached, which is what "no action lives on both bars" exists to forbid.
--
-- Both removals depend on the top bar being present, which is why it is mandatory now
-- (dock_top.isEnabled). Loot and Command Center left with the Actions menu: Loot is in
-- hub_list.ENTRIES, and Command Center is classicOnly in bars mode.
local MENUS = {
    -- Order is Native UI, Layouts, Settings, left to right. Taken off 29a's rendered
    -- frame, not from the caption -- I had them the other way round from reading the
    -- prose, which lists them on separate lines.
    {
        id = "game", label = "Native UI", group = "right",
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
        -- The SAME rows the Hub list's LAYOUTS section draws — one entry kind, two
        -- surfaces, so the preset list can never drift between them.
        id = "layouts", label = "Layouts", group = "right",
        entries = { { kind = "layouts_dynamic" } },
    },
}

--- The menus of one group, in table order.
local function menusIn(group)
    local out = {}
    for _, m in ipairs(MENUS) do
        if m.group == group then out[#out + 1] = m end
    end
    return out
end

-- Unread markers for the collapsed one-liner. Not "all": its marker would just duplicate
-- the sum of these, and the collapsed strip skips it for that reason below.
--
-- 19b turns these from four little labelled buttons into four DOTS. Four words plus four
-- numbers is most of a narrow bar's chat cell spent on counts, and the cell's job is the
-- line itself; a dot answers "is anything waiting, and roughly where" in 7px. The colour
-- is per tab so the answer is readable without reading: amber = somebody talked to you,
-- blue = the tool did, green = CoOpt reported something, grey = everything else. Nothing
-- is lost — each dot still hovers for the exact count and still clicks through to its tab.
local CHAT_BADGE_TABS = {
    { id = "main",  label = "Main",  color = theme.Kit.Attention },
    { id = "mq",    label = "MQ",    color = theme.Kit.SpellBlue },
    { id = "other", label = "Other", color = theme.Colors.TextContent },
    { id = "coopt", label = "CoOpt", color = theme.Kit.Good },
}
local DOT_D = 7                 -- dot diameter, 19b
local CHAT_MIN_W = 220          -- below this the launcher row folds into the Hub menu

-- Transient menu hover state; the pinned menu id lives on uiState (dock state stays outside
-- ImGui's own storage).
local hover = { id = nil, lastAt = 0, inMenu = false }

-- ---------------------------------------------------------------------------
-- Chips (19b): one control shape for every button on this bar
-- ---------------------------------------------------------------------------

--- The chip and its count pill are the KIT's, not this bar's: chat's tab strip draws the
--- same control, and a second copy would be a second dialect (components/window_header).
--- The one thing this bar decides is which EDGE the open accent sits on -- the one that
--- FACES the screen, so a bottom-docked bar accents the top of its chips and a top-docked
--- bar the bottom.
local function accentEdgeFor(edge)
    return (edge == "top") and "bottom" or "top"
end

local function chipButton(label, uid, lit, edge, tint)
    return windowHeader.chip(label, uid, lit, accentEdgeFor(edge), tint)
end

local pillButton = windowHeader.pill

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

-- The launcher list and its row engine live in components/hub_list.lua, because the top
-- bar's CoOpt panel draws the SAME list (23c) and two copies would drift the first time a
-- window was added. Only the window shell below is this bar's own.
local function drawMenuEntries(ctx, menu, s)
    hubList.drawEntries(menu.entries, ctx, s, dockTop.queue)
end

-- Re-exported for the launcher-chip code further down, which needs the same
-- registry-aware label and pair state the menu rows use.
local moduleLabel = hubList.moduleLabel
local pairModules = hubList.pairModules
local pairOpen = hubList.pairOpen
local pairPillCount = hubList.pairPillCount

--- "1 item waiting" / "3 items waiting" -- a pill tooltip that says "1 items" undermines the
--- exact thing it exists to do, which is read as a sentence rather than a number.
local function pillWord(n, one, many)
    return string.format("%d %s", n or 0, (n == 1) and one or many)
end
local hubOpen = hubList.hubOpen


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
    local MENU_MAX_W = 360
    -- Menus grow away from the edge the bar sits on, so they always open into the screen.
    local py = (edge == "bottom") and (y + h - barH) or (y + barH)
    local pivotY = (edge == "bottom") and 1.0 or 0.0
    -- ... and away from the SIDE they would otherwise leave. Hub and Layouts sit in the
    -- right group now, where a left-pivoted 360px panel would hang off the viewport, so a
    -- button whose panel would not fit opens leftward from its own right edge instead.
    local px, pivotX = btn.x or x, 0.0
    if btn.x and (btn.x + MENU_MAX_W) > (x + w) then
        px, pivotX = (btn.x2 or btn.x), 1.0
    end

    ImGui.SetNextWindowPos(ImVec2(px, py), ImGuiCond.Always, ImVec2(pivotX, pivotY))
    -- Bounded by the room actually left, not a fixed 420 -- same reason as the top bar's
    -- popover: the Hub menu draws the same growing ENTRIES list, so a constant cap clips
    -- its tail. 24px keeps it off the screen edge.
    local room = (edge == "bottom") and (py - y - 24) or ((y + h) - py - 24)
    local menuMaxH = math.max(200, math.min(720, room))
    ImGui.SetNextWindowSizeConstraints(ImVec2(190, 0), ImVec2(MENU_MAX_W, menuMaxH))

    -- Scrollable for the same reason: hitting the cap must scroll, never clip.
    local flags = bit32.bor(dockTop.popoverFlags(), ImGuiWindowFlags.AlwaysAutoResize or 0)
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
            -- Two windows, one chip. Bags is the hub; Bank is its own window again (the
            -- merge was rolled back), so each half lights for ITSELF -- the chip says
            -- "these belong together", not "these are one thing".
            --
            -- The Bank half is conditional: every OTHER launcher resolves through
            -- moduleLabel, which returns nil for a module the user disabled in Settings,
            -- so an unconditional half would make Bank the one chip that survives being
            -- turned off — and clicking it would toggle a window that can never draw.
            local bankLabel = present["bank"] and moduleLabel("bank") or nil
            if bankLabel then
                out[#out + 1] = { isPair = true, id = "bagsbank", halves = {
                    { label = "Bags", action = { kind = "hub" },
                      lit = function(c) return hubOpen(c) end },
                    { label = bankLabel, action = { kind = "window", id = "bank", toggle = true },
                      lit = function() return registry.isOpen("bank") == true end },
                } }
            else
                out[#out + 1] = { id = "bags", label = "Bags", isHub = true }
            end
        elseif id == "bank" and present["bags"] then
            -- Absorbed into the Bags|Bank pair above (saved CSVs still carry the id).
            local _ = id
        elseif pairIDAU and (id == "itemDisplay" or id == "augmentUtility") then
            -- The pair renders at the FIRST half's slot; the second occurrence is absorbed.
            if not out._idauPlaced then
                out._idauPlaced = true
                out[#out + 1] = { isPair = true, id = "idau", halves = {
                    { label = idLabel, action = { kind = "window", id = "itemDisplay", toggle = true } },
                    -- The pill is a count that belongs to this window (23c): the empty aug
                    -- sockets on whatever Item Display is showing. It rides beside the
                    -- label, not inside it.
                    { label = auLabel, pill = pairPillCount(),
                      pillTooltip = pillWord(pairPillCount(),
                          "empty augment socket on the item shown",
                          "empty augment sockets on the item shown"),
                      action = { kind = "window", id = "augmentUtility", toggle = true } },
                } }
            end
        else
            -- The Loot window is uiState-managed rather than registry-registered, so
            -- moduleLabel returns nil for it and an unguarded id would silently draw no
            -- chip at all. Same special case hub_list.drawEntries carries, and the queue's
            -- window action already knows the id (main_loop.lua). It needs its own `lit`
            -- for the same reason -- registry.isOpen("loot") is false however open it is.
            local isLoot = (id == "loot")
            local label = isLoot and "Loot" or moduleLabel(id)
            if label then
                local pill, pillTip = nil, nil
                if id == "reroll" then
                    local n = rerollPendingCount(ctx)
                    if n > 0 then
                        pill = n
                        -- Names what it counts, because the window shows three OTHER numbers
                        -- for itself (the two server-list sizes in its band, and "N of 10
                        -- ready" in its body) and a bare pill matches none of them.
                        pillTip = pillWord(n, "item waiting to go on the reroll list",
                                              "items waiting to go on the reroll list")
                    end
                end
                local lit = nil
                if isLoot then
                    lit = function(c) return (c and c.uiState and c.uiState.lootUIOpen) == true end
                end
                out[#out + 1] = { id = id, label = label, pill = pill, pillTooltip = pillTip,
                                  isHub = false, lit = lit }
            end
        end
    end
    out._idauPlaced = nil
    return out
end

--- Whole-chip lit state for a pair entry (23c: "the open pair lights the whole chip,
--- because they travel together"). That holds for Item Display|Aug Utility, which really
--- does open and close as a unit. Bags|Bank does NOT: they are two windows you open
--- independently, so its halves carry their own `lit` predicate instead and this returns
--- nil for it — "no whole-chip state, ask each half".
local function pairEntryLit(ctx, e)
    if e.id == "idau" then return pairOpen() end
    return nil
end

--- Rough reserved width for a launcher row, so the chat strip ahead of it (chat owns the
--- LEFT edge in both styles -- 19b) knows how much room is left, and so the fold below can
--- ask "does this even fit". Not pixel-exact: the bars' anti-jitter discipline (fixed
--- measured slot widths) is for the top bar's segments, which hold the SAME content across
--- frames; a launcher row's content (a count pill appearing) can change, and re-measuring
--- each frame is cheap enough that drift never accumulates.
--- Takes the already-resolved entry list so the estimate and the draw can never disagree
--- about what is on the bar this frame.
local function launcherRowWidth(entries)
    local pad = (constants.UI.DOCK_SLOT_PADDING_X or 12) * 2
    local total, first = 0, true
    local function chip(label, pill)
        total = total + dockLayout.textWidth(label) + pad
        if pill then total = total + dockLayout.textWidth(tostring(pill)) + pad + 1 end
    end
    for _, e in ipairs(entries) do
        if not first then total = total + constants.UI.DOCK_SLOT_GAP end
        first = false
        if e.isPair then
            -- Two half-buttons + the 1px hairline between them.
            for _, h in ipairs(e.halves) do chip(h.label, h.pill) end
            total = total + 1
        else
            chip(e.label, e.pill)
        end
    end
    return total
end

--- Same estimate for a row of menu buttons.
local function menuRowWidth(menus)
    local pad = (constants.UI.DOCK_SLOT_PADDING_X or 12) * 2
    local total, first = 0, true
    for _, m in ipairs(menus) do
        if not first then total = total + constants.UI.DOCK_SLOT_GAP end
        first = false
        total = total + dockLayout.textWidth(m.label) + pad
    end
    return total
end

--- Draw the launcher row itself. "bags" queues the hub, same as the menus' hub entry; every
--- other id toggles its companion window.
---
--- 19b fixed the colour here: an open window used to fill its chip with Keep.Normal, which
--- is the GREEN this product spends on "go" — a launcher that reads as an action button.
--- Open is blue everywhere else in the UI (the OpenWash + OpenBlue pair), and green is
--- reserved for things that start work. So: filled blue = that window is open right now,
--- muted = closed.
local function drawLauncherButtons(ctx, entries, edge)
    local first = true
    for _, e in ipairs(entries) do
        if not first then ImGui.SameLine(0, constants.UI.DOCK_SLOT_GAP) end
        first = false
        if e.isPair then
            -- One chip, two halves split by a hairline (the 1px gap against the dark bar).
            -- A pair that travels together (Item Display|Aug Utility) lights whole; a pair
            -- of independent windows (Bags|Bank) lights per half.
            local whole = pairEntryLit(ctx, e)
            for hi, h in ipairs(e.halves) do
                if hi > 1 then ImGui.SameLine(0, 1) end
                local lit = whole
                if lit == nil and h.lit then lit = h.lit(ctx) end
                local uid = "dockbtn_" .. e.id .. "_" .. hi
                local hit = chipButton(h.label, uid, lit, edge)
                if h.pill and pillButton(h.pill, uid .. "_pill", h.pillTooltip) then hit = true end
                if hit then dockTop.queue(ctx, h.action) end
            end
        else
            -- `lit` beats the registry: Loot is uiState-managed, so registry.isOpen is
            -- false for it no matter what the window is doing. Same escape hatch the pair
            -- halves above already use.
            local open
            if e.lit then
                open = e.lit(ctx) == true
            else
                open = (not e.isHub) and registry.isOpen(e.id) or false
            end
            local uid = "dockbtn_" .. e.id
            local hit = chipButton(e.label, uid, open, edge)
            if e.pill and pillButton(e.pill, uid .. "_pill", e.pillTooltip) then hit = true end
            if hit then
                if e.isHub then
                    dockTop.queue(ctx, { kind = "hub" })
                else
                    dockTop.queue(ctx, { kind = "window", id = e.id, toggle = true })
                end
            end
        end
    end
end

--- A row of menu buttons, recording each one's rect so renderMenu can anchor to it. A menu
--- lights while its own panel is showing — these are not windows, so "lit" here means "this
--- is the list you are reading", which is the same promise the chip makes everywhere else.
local function drawMenuButtons(ctx, menus, edge, showId)
    local first = true
    local lastRight, lastTop, lastBot
    for _, menu in ipairs(menus) do
        if not first then ImGui.SameLine(0, constants.UI.DOCK_SLOT_GAP) end
        first = false
        local tint = (menu.id == "hub") and theme.Kit.SpellBlue or nil
        chipButton(menu.label, "dockmenubtn_" .. menu.id, showId == menu.id, edge, tint)
        local hovered = ImGui.IsItemHovered and ImGui.IsItemHovered() or false
        -- Two numbers, not an ImVec2 -- indexing this return as rmin.x is what killed
        -- everything after the Items button (see dockLayout.itemRectMin).
        local rx, ry = dockLayout.itemRectMin()
        local mxx, mxy = dockLayout.itemRectMax()
        -- x2 as well as x: a menu button in the RIGHT group has to open leftward or its
        -- panel hangs off the screen, and that needs the button's right edge to pivot on.
        M.buttons[menu.id] = { x = rx, y = ry, x2 = mxx, hovered = hovered }
        if mxx and mxy then lastRight, lastTop, lastBot = mxx, ry, mxy end
    end
    return lastRight, lastTop, lastBot
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

--- TextUnformatted, not Text: chat carries '%' (and item links), which Text would treat as
--- a format string. views/effects.lua:88-92 hit the same thing.
local function textRaw(s)
    if ImGui.TextUnformatted then
        ImGui.TextUnformatted(s)
    else
        ImGui.Text((tostring(s):gsub("%%", "%%%%")))
    end
end

local function drawChatLine(e)
    local col = chatConsole.channelColor(e.channel)
    -- 19b draws the speaker's bracket in amber ahead of the line. It is the one token you
    -- scan a one-line chat cell FOR -- "did someone talk to me" -- and colouring the whole
    -- line by channel cannot answer that, because a group line and a group emote are the
    -- same channel. Split, not substring-coloured: only a LEADING bracket is a speaker.
    local speaker, rest = tostring(e.text or ""):match("^(%[[^%]]+%])%s*(.*)$")
    if speaker then
        ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Kit.Attention))
        local okS = pcall(textRaw, speaker)
        ImGui.PopStyleColor()
        if not okS then return end
        ImGui.SameLine(0, 4)
        e = { text = rest, channel = e.channel }
    end
    if col then ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(col)) end
    local ok, err = pcall(textRaw, e.text)
    if col then ImGui.PopStyleColor() end
    if not ok then error(err, 0) end
end

--- The four unread dots (19b). One InvisibleButton per dot so each is a real, hoverable,
--- clickable item -- the count and the click-through the labelled badges used to carry are
--- both still here, they just stopped costing four words of a one-line cell.
local function drawUnreadDots(ctx)
    local lineH = (ImGui.GetTextLineHeight and ImGui.GetTextLineHeight()) or 14
    for i, t in ipairs(CHAT_BADGE_TABS) do
        if i > 1 then ImGui.SameLine(0, 3) end
        local n = chatFeed.getUnread(t.id)
        ImGui.InvisibleButton("##dockdot_" .. t.id, ImVec2(DOT_D, math.max(lineH, DOT_D)))
        local hovered = ImGui.IsItemHovered and ImGui.IsItemHovered() or false
        pcall(function()
            local dl = ImGui.GetWindowDrawList and ImGui.GetWindowDrawList()
            if not dl or not dl.AddCircleFilled then return end
            local x1, y1 = dockLayout.itemRectMin()
            local x2, y2 = dockLayout.itemRectMax()
            if not (x1 and y1 and x2 and y2) then return end
            -- A dot, not a square: AddCircleFilled IS bound (lua_ImGuiUserTypes.cpp:399).
            local rgba = (n > 0) and t.color or theme.Kit.Divider
            local col = ImGui.GetColorU32 and ImGui.GetColorU32(theme.ToVec4(rgba)) or 0
            dl:AddCircleFilled(ImVec2((x1 + x2) / 2, (y1 + y2) / 2), DOT_D / 2, col)
        end)
        if hovered then
            ImGui.BeginTooltip()
            -- Same voice as the cell's other tooltips (C6): lowercase, click-result first,
            -- exact counts here because a tooltip has the room the bar label does not.
            if n > 0 then
                ImGui.Text(string.format("click opens %s - %d unread", t.label, n))
            else
                ImGui.Text(t.label .. " - nothing new")
            end
            ImGui.EndTooltip()
            if ImGui.IsMouseClicked and ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
                chatFeed.clearUnread(t.id)
                -- Non-toggle on purpose: a window action without toggle is an idempotent
                -- OPEN, so clicking a dot while chat is already showing another tab switches
                -- to that tab instead of slamming the window shut.
                ctx.uiState.chatRequestedTab = t.id
                dockTop.queue(ctx, { kind = "window", id = "chat" })
            end
        end
    end
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
        -- Capped at 99+ (C2): past two digits the number stops being read and starts
        -- moving the cell's rendered width. The per-dot tooltips in collapsed mode keep
        -- exact counts -- a tooltip has room, a bar cell does not.
        local n = chatFeed.getUnread()
        local nText = (n > 99) and "99+" or tostring(n)
        local label = (n > 0) and string.format("chat  %s##dockChatShow", nText) or "chat##dockChatShow"
        local pressed = ImGui.SmallButton(label)
        local hoveredHidden = ImGui.IsItemHovered and ImGui.IsItemHovered() or false
        if pressed then openChatWindow(ctx) end
        -- C1: hidden used to be a one-way door -- cycleChat was only reachable from the
        -- collapsed line's '^', so entering hidden cost one click and leaving it cost a
        -- trip to Settings > Dock. Right-click is the way back, and the tooltip states
        -- both actions because neither is guessable from a five-letter button.
        if hoveredHidden then
            if ImGui.IsMouseClicked and ImGui.IsMouseClicked(ImGuiMouseButton.Right) then
                cycleChat(ctx)
            end
            ImGui.BeginTooltip()
            ImGui.Text("click opens the chat window - right-click brings the chat line back")
            ImGui.EndTooltip()
        end
        return
    end

    -- collapsed: the only other mode. The '^' still cycles (collapsed <-> hidden); clicking
    -- the line itself is the way to the full window.
    if ImGui.SmallButton("^##dockChatCycle") then
        cycleChat(ctx)
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        -- One voice across the cell's three tooltips (C6): lowercase, click-result first.
        ImGui.Text("click hides the chat line - the small chat button that remains brings it back")
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
    -- The dots inside the child are real clickable items now, and the whole child is ALSO a
    -- click target. Same rule the top bar's cells use for their inner buttons: remember the
    -- queue length, and only treat the click as "the background was clicked" if nothing
    -- inside it enqueued anything. Without this, a dot click fires the dot's open AND the
    -- line's toggle, and the window opens and shuts in the same frame.
    local queueLenBefore = ctx.uiState.dockActionQueue and #ctx.uiState.dockActionQueue or 0
    if ImGui.BeginChild("dockChatCollapsed", ImVec2(clipW, lineH), false,
            bit32.bor(ImGuiWindowFlags.NoScrollbar, ImGuiWindowFlags.NoScrollWithMouse)) then
        dockLayout.contained(ctx.uiState, "dock chat line", function()
            -- Dots FIRST, then the line: the line is the thing that can be arbitrarily
            -- long, and drawn first it would push the unread markers out of the clip
            -- exactly when chat is busy and they matter most. Unlike the old badges these
            -- cost a fixed 40px whether or not anything is unread, so the line never
            -- reflows sideways as chat arrives.
            drawUnreadDots(ctx)
            ImGui.SameLine(0, 8)
            local lines = chatFeed.getLines(1)
            if lines[1] then
                drawChatLine(lines[1])
            else
                theme.TextMuted("(no chat yet - click to open chat)")
            end
        end)
    end
    ImGui.EndChild()
    -- Click anywhere in the line's child opens the window. EndChild(); IsItemHovered() is
    -- the established pattern for "was the mouse over the child I just closed" --
    -- dock_top.lua's segment slots use it the same way.
    local lineHovered = ImGui.IsItemHovered and ImGui.IsItemHovered() or false
    local q = ctx.uiState.dockActionQueue
    local consumed = (q and #q or 0) ~= queueLenBefore
    if lineHovered and not consumed and ImGui.IsMouseClicked and ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
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

        -- 19b's order, and it is the same in both styles now: CHAT OWNS THE LEFT EDGE, then
        -- the launchers, then the command menus, then the identity group at the right. Chat
        -- used to sit after the menus in the menus style, which put the one flexible thing
        -- on the bar in the middle of two fixed groups.
        -- Every menu is right-grouped since turn 27 retired Hub and Actions; there is no
        -- left menu group any more, so nothing is reserved for one. (A dead menusIn("left")
        -- pass survived the retirement for a while, drawing an empty group and claiming in
        -- its comment to be the only path to Stop -- Stop lives on the TOP bar's button
        -- pair, and MENUS has carried group="right" only ever since.)
        local rightMenus = menusIn("right")
        -- + one gap: menuRowWidth counts the gaps BETWEEN its own buttons, not the one
        -- before Settings. Under-reserving here starts the right group too far right and
        -- pushes Settings past the window edge.
        local rightW = menuRowWidth(rightMenus) + constants.UI.DOCK_SLOT_GAP
            + dockLayout.slotWidth("dockRight", { "Settings" }, 16)

        -- 19b: "the launcher row folds itself into menus automatically instead of being a
        -- setting you have to find". The row is dropped, not squeezed, because squeezing
        -- would cost the chat line -- the one cell that cannot be recovered from a menu.
        --
        -- WHAT CATCHES THE FOLD CHANGED IN TURN 27. It used to be this bar's own Hub menu;
        -- that chip is retired, so the catch is now the TOP bar's CoOpt cell, which opens
        -- the same hub_list.ENTRIES index. Sound because the top bar is mandatory -- and
        -- the precise thing to revisit if a bottom-bar-only mode is ever supported, where
        -- a folded row would leave no launcher surface anywhere.
        local launchers = nil
        local launchW = 0
        if style == "buttons" then
            launchers = launcherEntries(ctx, layoutConfig)
            launchW = launcherRowWidth(launchers) + constants.UI.DOCK_SLOT_GAP
        end
        local gaps = constants.UI.DOCK_SLOT_GAP * 3
        local function chatBudget(withLaunchers)
            return winW - (withLaunchers and launchW or 0) - rightW
                - constants.UI.DOCK_SLOT_PADDING_X * 2 - gaps
        end
        if launchers and chatBudget(true) < CHAT_MIN_W then
            launchers, launchW = nil, 0
        end
        local chatW = math.max(chatBudget(false), 80)

        --- A section divider in the gap after whatever was just drawn -- zero layout width
        --- (see dockTop.drawDividerAt).
        local function dividerAfterLast()
            local nx, ny = dockLayout.itemRectMin()
            local xx, xy = dockLayout.itemRectMax()
            if xx and xy then
                dockTop.drawDividerAt(xx + constants.UI.DOCK_SLOT_GAP * 0.5,
                    (ny or (xy - 16)) + 1, xy - 1)
            end
            local _ = nx
        end

        ImGui.BeginGroup()
        dockLayout.contained(ctx.uiState, "dock chat", renderChat, ctx, chatW)
        ImGui.EndGroup()
        dividerAfterLast()

        if launchers then
            ImGui.SameLine(0, constants.UI.DOCK_SLOT_GAP)
            ImGui.BeginGroup()
            dockLayout.contained(ctx.uiState, "dock launcher buttons",
                drawLauncherButtons, ctx, launchers, edge)
            ImGui.EndGroup()
            dividerAfterLast()
        end

        -- The identity group, right-anchored: Hub, Layouts, Settings (19b and 23c both put
        -- the lit Hub chip HERE, beside them, not on the left).
        ImGui.SameLine(math.max(winW - rightW, 0))
        ImGui.AlignTextToFramePadding()
        drawMenuButtons(ctx, rightMenus, edge, hover.id)
        ImGui.SameLine(0, constants.UI.DOCK_SLOT_GAP)
        -- Settings is a WINDOW, so it lights like one -- and toggles like one. A lit chip
        -- that will not close its window is the one thing 26a's "every segment is a toggle"
        -- exists to prevent.
        if chipButton("Settings", "dockSettings", registry.isOpen("config") == true, edge) then
            dockTop.queue(ctx, { kind = "window", id = "config", toggle = true })
        end
        end)
    end
    ImGui.End()
    ImGui.PopStyleVar(4)

    -- Both styles have hover menus now (the right group is menus in either one), so this is
    -- no longer gated on the style.
    renderMenu(ctx, s, edge)
    renderPresetSavePrompt(ctx)
    -- With the status bar off, this bar hosts the 14d degraded strip; rows (not 1) lands
    -- it above the whole strip even when peek chat makes the bar five rows tall.
    if not dockTop.isEnabled(ctx.layoutConfig) and dockTop.renderDegradedStrip then
        dockTop.renderDegradedStrip(ctx, s, edge, M.rows(ctx.layoutConfig))
    end
end

return M
