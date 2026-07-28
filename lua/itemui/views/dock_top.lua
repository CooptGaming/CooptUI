--[[
    dock_top.lua — the top status bar.

    A borderless strip pinned to one screen edge. Read-only status in FIXED-WIDTH slots,
    each with a click action (popovers land in phase 2). Mockups 12a (five loot states),
    12b (buffs segment), 13a (in situ), 13d (what belongs on which bar).

    Four rules this file must not break:

      1. FIXED SLOT WIDTHS. Every segment reserves the width of its widest possible string,
         measured once by dock_layout and cached. Content changes inside the slot; the slot
         never resizes. The loot slot is the extreme case -- it holds "idle" and also a
         progress readout with two buttons, and it is the same width either way.
      2. CACHED DATA ONLY. Everything drawn here comes from dock_state.get(). No TLO calls,
         no scans, no file reads in this file.
      3. ONE COARSE CLOCK. dock_state ticks at 250ms; this file just renders what it finds.
      4. NO INPUT THEFT. NoFocusOnAppearing keeps the game's keyboard focus, and
         NoBringToFrontOnFocus keeps the strip under the companion windows -- draw order
         alone does NOT do that, because ImGui z-order is focus-ordered.
]]

local theme = require('itemui.utils.theme')
local constants = require('itemui.constants')
local dockLayout = require('itemui.utils.dock_layout')
local dockState = require('itemui.services.dock_state')

local M = {}

--- Where each slot landed on screen this frame, plus whether it is hovered:
--- { [segmentId] = { x, y, w, h, hovered } }. Phase 2's popovers anchor to these.
M.slots = {}

-- Widest possible content per slot. These strings are never displayed -- they exist only to
-- reserve width, so each must be at least as wide as anything the segment can actually show.
local WIDEST = {
    status  = { "CoOpt  plugin missing  9 errors" },
    bags    = { "bags 300/300 . wt 9999/9999" },
    sell    = { "9,999 to sell . 9,999,999p" },
    -- The loot slot is deliberately the widest of all five states at once (mockup 12a: the
    -- slot is one fixed width whether it says "idle" or holds a progress bar and two buttons).
    loot    = { "stopped - bags full, 99 left on corpses", "decision - Mythical Faceplate of Blinding Fury" },
    buffs   = { "buffs 99 . songs 99 . aura Y . 99 expiring" },
    xp      = { "XP 100.0% . AA 99999 . scripts 9999" },
    session = { "session 9,999,999p" },
}

-- Extra width for segments that hold inline buttons (Stop, Take/Pass, Consolidate/Resume).
local EXTRA = { loot = 150 }

local SEGMENT_ORDER_FALLBACK = { "status", "bags", "sell", "loot", "buffs", "xp", "session" }

--- Split a CSV INI value into a list, trimming each entry. Empty string -> empty list.
local function csv(s)
    local out = {}
    for part in tostring(s or ""):gmatch("[^,]+") do
        local t = part:match("^%s*(.-)%s*$")
        if t ~= "" then out[#out + 1] = t end
    end
    return out
end
M.csv = csv

--- "1,208p" -- thousands separators, matching the mockups' plat readouts.
local function commas(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end
M.commas = commas

--- Copper total -> whole platinum, which is the unit every bar readout uses.
local function plat(copper)
    return commas(math.floor((tonumber(copper) or 0) / 1000))
end

local function mmss(secs)
    secs = math.max(0, math.floor(tonumber(secs) or 0))
    if secs >= 3600 then return string.format("%dh %02dm", math.floor(secs / 3600), math.floor((secs % 3600) / 60)) end
    if secs >= 60 then return string.format("%dm %02ds", math.floor(secs / 60), secs % 60) end
    return string.format("%ds", secs)
end
M.mmss = mmss

--- Muted label + normal value on one line, without a trailing SameLine.
local function labelled(label, value, valueColor)
    theme.TextMuted(label)
    ImGui.SameLine(0, 4)
    if valueColor then
        ImGui.TextColored(theme.ToVec4(valueColor), tostring(value))
    else
        ImGui.Text(tostring(value))
    end
end

-- ---------------------------------------------------------------------------
-- Segments. Each draws inside a fixed-width child; none may exceed its slot.
-- ---------------------------------------------------------------------------

local segments = {}

segments.status = function(ctx, s)
    local label = "CoOpt"
    if not s.pluginPresent then
        theme.TextWarning(label)
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Running without the plugin - scans are slower.")
            ImGui.Text("Everything still works.")
            ImGui.EndTooltip()
        end
    elseif s.errorCount > 0 then
        theme.TextError(label)
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text(string.format("%d recent error%s - Settings > Advanced has the log.",
                s.errorCount, s.errorCount == 1 and "" or "s"))
            ImGui.EndTooltip()
        end
    else
        theme.TextSuccess(label)
    end
end

segments.bags = function(ctx, s)
    -- Bag pressure turns amber past 90%, per mockup 9a.
    local col = (s.bagPct >= 0.9) and theme.Colors.Warning or nil
    if s.bagSlots > 0 then
        labelled("bags", string.format("%d/%d", s.bagItems, s.bagSlots), col)
    else
        labelled("bags", tostring(s.bagItems), col)
    end
    -- Weight is native window text and is unknown while the game's Inventory window is
    -- closed, which is most of the time for a bar that is always on screen. Omit the
    -- sub-segment rather than show "N/A"; the slot stays the same width either way.
    if s.weightKnown then
        ImGui.SameLine(0, 6)
        theme.TextMuted("wt")
        ImGui.SameLine(0, 4)
        ImGui.Text(string.format("%s/%s", tostring(s.weight), tostring(s.maxWeight)))
    end
end

segments.sell = function(ctx, s)
    if s.sellCount <= 0 then
        theme.TextMuted("nothing to sell")
        return
    end
    local txt = string.format("%d to sell . %sp", s.sellCount, plat(s.sellTotal))
    -- The trust case: keep-list items still queued to sell. This is the number players
    -- distrust, so it does not stay quiet.
    if s.keepInSellQueue > 0 then
        ImGui.TextColored(theme.ToVec4(theme.Colors.Error), txt)
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text(string.format("%d keep-list item%s still in the sell queue - review before selling.",
                s.keepInSellQueue, s.keepInSellQueue == 1 and "" or "s"))
            ImGui.EndTooltip()
        end
    else
        ImGui.Text(txt)
    end
end

--- The loot segment: one slot, five states (mockup 12a). Buttons queue through
--- uiState.dockActionQueue -- never a direct mq.cmd, which is what views/command_center.lua
--- does today from inside the frame.
segments.loot = function(ctx, s)
    local st = s.lootState
    if st == "decision" then
        theme.TextWarning("decision")
        ImGui.SameLine(0, 4)
        local name = s.lootDecisionName or "Mythical item"
        -- Plain ASCII: nothing else in this codebase uses a \u{} escape, and MQ's Lua version
        -- is not pinned anywhere here (it ships a bit32 shim), so don't be the first to rely
        -- on 5.3+ escape syntax in a file that has to load for the UI to come up at all.
        if #name > 28 then name = name:sub(1, 25) .. "..." end
        ImGui.Text(name)
        if s.lootDecisionSecs then
            ImGui.SameLine(0, 6)
            theme.TextMuted(mmss(s.lootDecisionSecs))
        end
        ImGui.SameLine(0, 8)
        theme.PushKeepButton()
        if ImGui.SmallButton("Take F1##dockLootTake") then M.queue(ctx, { kind = "loot_take" }) end
        theme.PopButtonColors()
        ImGui.SameLine(0, 4)
        theme.PushSkipButton()
        if ImGui.SmallButton("Pass F2##dockLootPass") then M.queue(ctx, { kind = "loot_pass" }) end
        theme.PopButtonColors()

    elseif st == "problem" then
        theme.TextError(string.format("stopped - %s", s.lootProblem or "see log"))
        ImGui.SameLine(0, 8)
        if ImGui.SmallButton("Consolidate##dockLootConsolidate") then M.queue(ctx, { kind = "consolidate" }) end

    elseif st == "looting" then
        labelled("corpse", string.format("%d/%d", s.lootCorpse, s.lootTotalCorpses))
        ImGui.SameLine(0, 6)
        theme.TextMuted(string.format("%d taken", s.lootTaken))
        ImGui.SameLine(0, 8)
        theme.PushDeleteButton()
        if ImGui.SmallButton("Stop##dockLootStop") then M.queue(ctx, { kind = "loot_stop" }) end
        theme.PopButtonColors()

    elseif st == "done" then
        theme.TextSuccess(string.format("looted %d corpse%s . %sp",
            s.lootTotalCorpses, s.lootTotalCorpses == 1 and "" or "s", plat(s.lootRunValue)))
        if s.lootSkipped > 0 then
            ImGui.SameLine(0, 6)
            theme.TextMuted(string.format("%d skipped", s.lootSkipped))
        end
        ImGui.SameLine(0, 8)
        if ImGui.SmallButton("Review##dockLootReview") then M.queue(ctx, { kind = "window", id = "loot" }) end

    else
        theme.TextMuted("loot")
        ImGui.SameLine(0, 4)
        theme.TextMuted("idle")
    end
end

segments.buffs = function(ctx, s)
    labelled("buffs", tostring(s.buffCount))
    ImGui.SameLine(0, 6)
    labelled("songs", tostring(s.songCount))
    ImGui.SameLine(0, 6)
    theme.TextMuted("aura")
    ImGui.SameLine(0, 4)
    if s.auraCount > 0 then theme.TextSuccess("y") else theme.TextMuted("-") end
    -- Amber only when something is under five minutes, so a healthy character sees plain grey.
    if s.expiringCount > 0 then
        ImGui.SameLine(0, 6)
        theme.TextWarning(string.format("%d expiring", s.expiringCount))
    end
end

segments.xp = function(ctx, s)
    labelled("XP", string.format("%.1f%%", tonumber(s.exp) or 0))
    ImGui.SameLine(0, 6)
    labelled("AA", commas(s.aaTotal))
    if (tonumber(s.scriptAA) or 0) > 0 then
        ImGui.SameLine(0, 6)
        labelled("scripts", commas(s.scriptAA))
    end
end

segments.session = function(ctx, s)
    labelled("session", plat(s.sessionPlat) .. "p")
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text(string.format("This session: %sp looted, %sp sold.", plat(s.sessionLooted), plat(s.sessionSold)))
        ImGui.EndTooltip()
    end
end

-- Which dock_state walks each segment needs, so an unused segment costs no TLO reads.
local SEGMENT_DEMAND = {
    bags    = dockState.requestBags,
    sell    = dockState.requestSell,
    buffs   = dockState.requestBuffs,
    xp      = dockState.requestStats,
    -- The loot segment reads bag pressure to detect the bags-full problem state.
    loot    = dockState.requestBags,
    -- session/status need nothing beyond the every-tick cheap reads.
}

-- ---------------------------------------------------------------------------
-- Action queue
-- ---------------------------------------------------------------------------

--- Queue a bar action for main_loop to drain. NOTHING that scans, sleeps or issues a game
--- command may run inside the ImGui callback, so every button here goes through the queue --
--- the same discipline as uiState.deferredBankScanRequested and uiState.autoSellRequested.
function M.queue(ctx, action)
    local uiState = ctx and ctx.uiState
    if not uiState or not action then return end
    local q = uiState.dockActionQueue
    if not q then q = {}; uiState.dockActionQueue = q end
    q[#q + 1] = action
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------

local BAR_FLAGS = nil
local function barFlags()
    if BAR_FLAGS then return BAR_FLAGS end
    local f = 0
    local W = ImGuiWindowFlags
    for _, name in ipairs({ "NoTitleBar", "NoResize", "NoMove", "NoScrollbar", "NoScrollWithMouse",
                            "NoSavedSettings", "NoFocusOnAppearing", "NoNav", "NoCollapse",
                            "NoBringToFrontOnFocus", "NoDocking" }) do
        if W[name] then f = bit32.bor(f, W[name]) end
    end
    BAR_FLAGS = f
    return f
end
M.barFlags = barFlags

--- True when the bars should draw at all. Also the gate main_loop uses to decide whether the
--- loop needs the fast delay -- otherwise a visible bar would update at 10Hz with the hub closed.
function M.isEnabled(layoutConfig)
    if not layoutConfig then return false end
    return tostring(layoutConfig.UIMode or "classic") == "bars" and layoutConfig.DockTop ~= false
end

--- Which edge the status bar takes. The bottom bar takes the other one when both are on.
function M.edge(layoutConfig)
    return (layoutConfig and tostring(layoutConfig.DockPosition or "top") == "bottom") and "bottom" or "top"
end

function M.render(ctx)
    local layoutConfig = ctx and ctx.layoutConfig
    if not M.isEnabled(layoutConfig) then return end

    dockLayout.refreshCacheKey()
    local s = dockState.get()

    local order = csv(layoutConfig.DockSegments)
    if #order == 0 then order = SEGMENT_ORDER_FALLBACK end

    -- Raise demand for exactly the segments that are on, so nothing walks TLOs unread.
    for _, id in ipairs(order) do
        local want = SEGMENT_DEMAND[id]
        if want then want() end
    end

    local edge = M.edge(layoutConfig)
    local x, y, w, h = dockLayout.barRect(edge, 0)
    ImGui.SetNextWindowPos(ImVec2(x, y))
    ImGui.SetNextWindowSize(ImVec2(w, h))
    ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowBorderSize, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, ImVec2(constants.UI.DOCK_SLOT_PADDING_X, constants.UI.DOCK_BAR_PADDING_Y))
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, ImVec2(constants.UI.DOCK_SLOT_GAP, 0))

    -- Begin returns (open, visible) in this binding -- see views/aa.lua:182 and friends. The
    -- bar has no close button (NoTitleBar), so `open` is always true and it is the SECOND
    -- value that says whether to draw. End() is still called unconditionally either way,
    -- which is the Begin/End contract.
    local _, visible = ImGui.Begin("##CoOptDockTop", true, barFlags())
    if visible then
        ImGui.AlignTextToFramePadding()
        local first = true
        for _, id in ipairs(order) do
            local draw = segments[id]
            if draw then
                if not first then ImGui.SameLine(0, constants.UI.DOCK_SLOT_GAP) end
                first = false
                local slotW = dockLayout.slotWidth(id, WIDEST[id] or { id }, EXTRA[id])
                -- A fixed-width, borderless child is what pins the slot: content reflows
                -- inside it and the neighbours never move.
                if ImGui.BeginChild("dockseg_" .. id, ImVec2(slotW, h - constants.UI.DOCK_BAR_PADDING_Y * 2), false,
                        bit32.bor(ImGuiWindowFlags.NoScrollbar, ImGuiWindowFlags.NoScrollWithMouse)) then
                    ImGui.AlignTextToFramePadding()
                    draw(ctx, s)
                end
                ImGui.EndChild()
                -- Slot screen rect + hover state, remembered for phase 2: a popover opens
                -- under the segment it belongs to (or over it, when bottom-docked), so it
                -- needs where the slot actually landed. GetItemRectMin returns an ImVec2 here
                -- (see utils/icons.lua:39 and views/equipment.lua:257) and is existence-guarded
                -- the same way, since the binding is not guaranteed to expose it.
                local hovered = ImGui.IsItemHovered and ImGui.IsItemHovered() or false
                local rmin = ImGui.GetItemRectMin and ImGui.GetItemRectMin()
                if rmin and rmin.x then
                    M.slots[id] = { x = rmin.x, y = rmin.y, w = slotW, h = h, hovered = hovered }
                else
                    M.slots[id] = { x = nil, y = nil, w = slotW, h = h, hovered = hovered }
                end
            end
        end
    end
    ImGui.End()
    ImGui.PopStyleVar(4)
end

return M
