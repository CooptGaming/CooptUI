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

local mq = require('mq')
local theme = require('itemui.utils.theme')
local constants = require('itemui.constants')
local dockLayout = require('itemui.utils.dock_layout')
local dockState = require('itemui.services.dock_state')
local hintsService = require('itemui.services.hints')

local M = {}

--- Where each slot landed on screen this frame, plus whether it is hovered:
--- { [segmentId] = { x, y, w, h, hovered } }. Phase 2's popovers anchor to these.
M.slots = {}

-- Widest possible content per slot. These strings are never displayed -- they exist only to
-- reserve width, so each must be at least as wide as anything the segment can actually show.
local WIDEST = {
    status  = { "CoOpt  plugin missing  9 errors" },
    bags    = { "bags 300/300 . wt 9999/9999" },
    sell    = { "9,999 to sell . 9,999,999p", "selling 999/999 . 9,999,999p" },
    -- The loot slot is deliberately the widest of all five states at once (mockup 12a: the
    -- slot is one fixed width whether it says "idle" or holds a progress bar and two buttons).
    loot    = { "stopped - bags full, 99 left on corpses", "decision - Mythical Faceplate of Blinding Fury" },
    buffs   = { "buffs 99 . songs 99 . aura Y . 99 expiring" },
    xp      = { "XP 100.0% . AA 99999 . scripts 9999" },
    session = { "session 9,999,999p" },
}

-- Extra width for segments that hold inline buttons (Stop, Take/Pass, Consolidate/Resume)
-- or an inline progress bar (sell/loot running states: 48px bar + gap).
local EXTRA = { loot = 198, sell = 54 }

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

--- Format-safe text, for anything the GAME or the user's config supplies: item names, buff
--- names, corpse names, rule text. ImGui.Text treats its argument as a format string, so an
--- item called "Potion of 50% Haste" makes it raise -- and because theme's text helpers are
--- Push -> Text -> Pop, a raise there strands the pushed style colour for the rest of the
--- frame. views/effects.lua:88-95 guards the same way for spell descriptions.
--- Static strings we author ourselves do not need this.
local function safeText(s)
    s = tostring(s)
    if ImGui.TextUnformatted then
        ImGui.TextUnformatted(s)
    else
        ImGui.Text((s:gsub("%%", "%%%%")))
    end
end
M.safeText = safeText

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
    -- A running sell (macro or Lua batch) owns the slot: progress beats the static offer,
    -- and the keep-list warning stays quiet until the run is over — mid-run it is not
    -- actionable anyway.
    if s.sellRunning then
        theme.TextWarning("selling")
        ImGui.SameLine(0, 4)
        ImGui.Text(string.format("%d/%d", s.sellRunCurrent or 0, s.sellRunTotal or 0))
        ImGui.SameLine(0, 6)
        theme.RenderProgressBar(math.min(1, math.max(0, s.sellRunFrac or 0)), ImVec2(48, 12), "")
        if (s.sellRunValue or 0) > 0 then
            ImGui.SameLine(0, 6)
            theme.TextSuccess(plat(s.sellRunValue) .. "p")
        end
        return
    end
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
        safeText(name)
        if s.lootDecisionSecs then
            ImGui.SameLine(0, 6)
            theme.TextMuted(mmss(s.lootDecisionSecs))
        end
        ImGui.SameLine(0, 8)
        -- No key hints on these labels: no hotkey handler exists, and EQ binds F1/F2 to
        -- self/group targeting, so ImGui could not safely own those keys anyway (MQ only
        -- blocks the keyboard from EQ while a text input wants it). Buttons only, honestly.
        theme.PushKeepButton()
        if ImGui.SmallButton("Take##dockLootTake") then M.queue(ctx, { kind = "loot_take" }) end
        theme.PopButtonColors()
        ImGui.SameLine(0, 4)
        theme.PushSkipButton()
        if ImGui.SmallButton("Pass##dockLootPass") then M.queue(ctx, { kind = "loot_pass" }) end
        theme.PopButtonColors()

    elseif st == "problem" then
        -- A problem strip says what happened and offers a fix that actually exists. The
        -- mockup's "Consolidate - frees 6" needs a bag-consolidation feature this codebase
        -- does not have; it belongs with the phase 6 degraded-state work rather than as a
        -- button here that would look real and do nothing. Until then: open the bags, and
        -- offer the sell only when a merchant makes it possible.
        theme.TextError(string.format("stopped - %s", s.lootProblem or "see log"))
        ImGui.SameLine(0, 8)
        if ImGui.SmallButton("Bags##dockLootBags") then M.queue(ctx, { kind = "hub" }) end
        if s.merchantOpen and s.sellCount > 0 then
            ImGui.SameLine(0, 4)
            if ImGui.SmallButton("Sell junk##dockLootSellJunk") then M.queue(ctx, { kind = "auto_sell" }) end
        end

    elseif st == "looting" then
        labelled("corpse", string.format("%d/%d", s.lootCorpse, s.lootTotalCorpses))
        if s.lootCorpseName and ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            safeText("On: " .. tostring(s.lootCorpseName))
            ImGui.EndTooltip()
        end
        ImGui.SameLine(0, 6)
        local lootFrac = (s.lootTotalCorpses or 0) > 0 and (s.lootCorpse / s.lootTotalCorpses) or 0
        theme.RenderProgressBar(math.min(1, math.max(0, lootFrac)), ImVec2(48, 12), "")
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
    -- Bags shows weight too, and weight/maxWeight/weightKnown are populated by the STATS
    -- walk -- with only requestBags the "wt" sub-segment never appears unless the xp
    -- segment happens to be enabled and demanding stats on its behalf.
    bags    = function() dockState.requestBags(); dockState.requestStats() end,
    sell    = dockState.requestSell,
    buffs   = dockState.requestBuffs,
    xp      = dockState.requestStats,
    -- The loot segment reads bag pressure to detect the bags-full problem state.
    loot    = dockState.requestBags,
    -- session/status need nothing beyond the every-tick cheap reads.
}

-- Window flags shared by the bar and its popovers. Declared HERE, above renderPopover,
-- because a `local function` is only in scope after its declaration: defined further down,
-- the call inside renderPopover would resolve to a nil GLOBAL and blow up the first time a
-- popover opened (and trip luacheck 113, which this repo enforces for exactly that reason).
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

-- ---------------------------------------------------------------------------
-- Popovers
--
-- A popover is a SECOND borderless window, not a tooltip: BeginTooltip cannot hold buttons,
-- and the whole point is that the mouse can walk into it and click Recast or Sell.
--
-- Because it is a real window it swallows mouse input where it sits -- a popover hanging over
-- the game world will eat a click meant for the world underneath. That is the one genuine
-- limit here, and it dictates the rules: open only on deliberate hover, close the moment the
-- mouse leaves (with just enough grace to travel there), and never appear unbidden while a
-- loot decision is on screen.
-- ---------------------------------------------------------------------------

-- Transient hover bookkeeping. The PINNED id lives on uiState instead (rule 4: dock state
-- lives outside ImGui's storage), so it survives a view reload and is inspectable.
local hover = { id = nil, lastAt = 0, inPopover = false }

local popovers = {}

--- Expiring buffs, each with a Recast when we can identify the item that casts it, plus the
--- full grid and a way into the real window. Mockup 12b.
popovers.buffs = function(ctx, s)
    dockState.requestClickyMap()
    theme.TextHeaderAlt("Expiring soon")
    ImGui.Separator()
    if s.expiringCount == 0 then
        theme.TextMuted("Nothing under five minutes.")
    else
        local clicky = s.clickyBySpell or {}
        for i, e in ipairs(s.expiring) do
            ImGui.PushID("dockexp" .. i)
            local col = (e.seconds and e.seconds <= 60) and theme.Colors.Error or theme.Colors.Warning
            ImGui.TextColored(theme.ToVec4(col), mmss(e.seconds))
            ImGui.SameLine(60)
            safeText(tostring(e.name or "?"))
            -- Recast is offered only when an item in bags actually casts this spell (matched
            -- by spell id, not name) and it is off cooldown. No item, no button -- rather
            -- than a button that does nothing.
            local src = e.spellId and clicky[e.spellId] or nil
            if src then
                ImGui.SameLine(300)
                if (src.ready or 0) > 0 then
                    theme.TextMuted(string.format("%ds", src.ready))
                elseif ImGui.SmallButton("Recast") then
                    M.queue(ctx, { kind = "clicky", bag = src.bag, slot = src.slot })
                end
                if ImGui.IsItemHovered() then
                    ImGui.BeginTooltip()
                    ImGui.Text(string.format("Cast from %s", tostring(src.name or "item in bags")))
                    ImGui.EndTooltip()
                end
            end
            ImGui.PopID()
        end
        if s.expiringCount > #s.expiring then
            theme.TextMuted(string.format("+%d more", s.expiringCount - #s.expiring))
        end
    end

    theme.SectionBreak()
    theme.TextMuted(string.format("Everything up . %d buffs, %d songs, %d aura%s",
        s.buffCount, s.songCount, s.auraCount, s.auraCount == 1 and "" or "s"))
    if ImGui.Button("Open Buffs window##dockBuffsOpen") then
        M.queue(ctx, { kind = "window", id = "effects" })
    end
end

--- What a sale would do right now, grouped by the RULE that decided each item -- this is
--- where players learn their own rules. Mockups 11d and 3f.
popovers.sell = function(ctx, s)
    dockState.requestSell()
    theme.TextHeaderAlt("If you sold now")
    theme.TextMuted("grouped by the rule that decided it")
    ImGui.Separator()
    local groups = s.sellGroups or {}
    if #groups == 0 then
        theme.TextMuted("Nothing matches your sell rules.")
    else
        for i, g in ipairs(groups) do
            ImGui.PushID("dockgrp" .. i)
            safeText(tostring(g.reason))
            ImGui.SameLine(240)
            theme.TextMuted(tostring(g.count))
            ImGui.SameLine(285)
            ImGui.Text(plat(g.total) .. "p")
            ImGui.PopID()
        end
        ImGui.Separator()
        theme.TextMuted(string.format("Held back: %d kept, %d protected", s.keepCount, s.protectCount))
    end

    theme.SectionBreak()
    -- A verb only appears when it works: Auto Sell needs a merchant, and saying so beats a
    -- dialog that tells you to open one after you have already clicked.
    if s.merchantOpen then
        theme.PushKeepButton()
        if ImGui.Button("Sell##dockSellGo") then M.queue(ctx, { kind = "auto_sell" }) end
        theme.PopButtonColors()
    else
        theme.TextMuted("Auto Sell needs an open merchant.")
    end
    -- "Full preview" is the hub: it switches itself to the Sell view whenever a merchant is
    -- open, which IS the full preview. There is no separate preview window to open.
    if ImGui.Button("Full preview##dockSellPreview") then M.queue(ctx, { kind = "hub" }) end
    ImGui.SameLine()
    if ImGui.Button("Rules##dockSellRules") then M.queue(ctx, { kind = "window", id = "config" }) end
end

--- Decide which popover (if any) should be on screen, and draw it.
--- Called AFTER the bar's own End(), so the popover is a sibling window rather than a child.
local function renderPopover(ctx, s, edge, barX, barY, barW, barH)
    local uiState = ctx.uiState
    local pinned = uiState and uiState.dockPinnedPopover or nil

    -- Never during a loot decision. A window that eats clicks must not appear over the game
    -- at the exact moment the player is being asked to press Take or Pass.
    if s.lootState == "decision" then
        hover.id = nil
        if pinned then uiState.dockPinnedPopover = nil end
        return
    end

    -- Which segment is under the mouse this frame?
    local hoveredId = nil
    for id, slot in pairs(M.slots) do
        if slot.hovered and popovers[id] then hoveredId = id end
    end

    local now = mq.gettime()
    if hoveredId then
        hover.id = hoveredId
        hover.lastAt = now
        -- Middle-click pins the popover open so it survives the mouse leaving.
        if ImGui.IsMouseClicked and ImGui.IsMouseClicked(ImGuiMouseButton.Middle) and uiState then
            uiState.dockPinnedPopover = (pinned == hoveredId) and nil or hoveredId
            pinned = uiState.dockPinnedPopover
        end
    elseif hover.inPopover then
        hover.lastAt = now       -- the mouse is in the popover itself; keep it alive
    end

    local showId = pinned
    if not showId and hover.id and (now - hover.lastAt) <= constants.TIMING.DOCK_POPOVER_GRACE_MS then
        showId = hover.id
    end
    if not showId then
        hover.id, hover.inPopover = nil, false
        return
    end
    local draw = popovers[showId]
    if not draw then return end

    local slot = M.slots[showId] or {}
    local px = slot.x or barX
    -- Opens downward from a top bar and upward from a bottom one, so it always grows into the
    -- screen rather than off it. AlwaysAutoResize means the height is unknown until after
    -- Begin, so an upward popover is placed with a bottom-left pivot.
    local py = (edge == "bottom") and (barY) or (barY + barH)
    local pivotY = (edge == "bottom") and 1.0 or 0.0
    if ImGui.SetNextWindowPos and pivotY == 1.0 then
        ImGui.SetNextWindowPos(ImVec2(px, py), ImGuiCond.Always, ImVec2(0, 1))
    else
        ImGui.SetNextWindowPos(ImVec2(px, py))
    end
    ImGui.SetNextWindowSizeConstraints(ImVec2(360, 0), ImVec2(560, 420))

    local flags = bit32.bor(barFlags(), ImGuiWindowFlags.AlwaysAutoResize or 0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, ImVec2(10, 8))
    -- Same discipline as the bar's own Begin: the style var above must be unwound if Begin
    -- itself throws, or it leaks one entry per frame while the popover is due.
    local okBegin, _, visible = pcall(ImGui.Begin, "##CoOptDockPopover", true, flags)
    if not okBegin then
        ImGui.PopStyleVar(1)
        return
    end
    if visible then
        -- Contained for the same reason as the bar body: an error escaping between Begin and
        -- End would leave the popover window open and ImGui short an End().
        dockLayout.contained(uiState, "dock popover " .. tostring(showId), function()
            hover.inPopover = (ImGui.IsWindowHovered and ImGui.IsWindowHovered(
                ImGuiHoveredFlags and ImGuiHoveredFlags.ChildWindows or 0)) or false
            if pinned then
                theme.TextMuted("pinned - middle-click the slot again, or Esc, to close")
            end
            draw(ctx, s)
        end)
    else
        hover.inPopover = false
    end
    ImGui.End()
    ImGui.PopStyleVar(1)

    -- Esc closes a pinned popover. Only consume the key when one is actually pinned, so the
    -- hub's own LIFO Esc handling is untouched the rest of the time.
    if pinned and ImGui.IsKeyPressed and ImGui.IsKeyPressed(ImGuiKey.Escape) then
        uiState.dockPinnedPopover = nil
        -- dockEscConsumed, not escConsumedThisFrame: the hub renders after the bars and
        -- resets escConsumedThisFrame at the top of its own render, so a write here would be
        -- erased and the same Esc would also close the newest companion window.
        -- main_window hands this flag over into escConsumedThisFrame instead.
        uiState.dockEscConsumed = true
        hover.id, hover.inPopover = nil, false
    end
end

-- ---------------------------------------------------------------------------
-- Degraded-state strip (mockup 14d): say what, say the cost, offer the fix, stay out of
-- the way. One 30px strip under the bar, dismissible per session, never a modal.
-- Buttons that would do nothing do not exist; fixes that are real go through the queue.
-- ---------------------------------------------------------------------------

local STRIPS = {
    sellmac_missing = {
        color = "Error",
        msg = "Auto Sell needs sell.mac - not found in Macros",
        note = "Auto Sell will fail until then",
        tip = "Expected in your MacroQuest Macros folder. Re-run the installer, or copy sell.mac from the bundle.",
    },
    no_rules = {
        -- The default rule pipeline SELLS unmatched tradeable items at/above the value
        -- floor (rules.lua step 19 falls through to "Sell") — empty lists are the LEAST
        -- protected state, not the safest. An earlier draft of this strip said "would
        -- sell nothing / safe by default", which was factually inverted.
        color = "Warning",
        msg = "no sell rules yet - Auto Sell falls back to defaults (sells tradeable items above the value floor)",
        note = "review before selling",
        btn = { label = "Open rules", action = { kind = "window", id = "config" } },
    },
    stale_bank = {
        color = "Success",
        msgFn = function(deg) return string.format("bank shown from a snapshot taken %d day%s ago",
            deg.days or 0, (deg.days or 0) == 1 and "" or "s") end,
        note = "read-only until then - open a bank to refresh",
    },
    no_plugin = {
        color = "Warning",
        msg = "running without the plugin - scans are slower",
        note = "everything still works",
        tip = "The MQ2CoOptUI plugin reads items natively. Without it CoOpt falls back to slower TLO scans - every feature still functions.",
    },
}

local function renderDegradedStrip(ctx, s, edge, index)
    local deg = s.degraded
    if not deg then return end
    local uiState = ctx.uiState
    local dismissed = uiState and uiState.dockStripDismissed
    if dismissed and dismissed[deg.id] then return end
    local spec = STRIPS[deg.id]
    if not spec then return end

    -- index 1 = just inside this bar's edge. The command bar passes its own row count so
    -- the strip lands above it even in peek-chat mode (it is the strip's fallback host
    -- when the status bar is disabled).
    local x, y, w, h = dockLayout.barRect(edge, index or 1)
    ImGui.SetNextWindowPos(ImVec2(x, y))
    ImGui.SetNextWindowSize(ImVec2(w, h))
    ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowBorderSize, (deg.id == "sellmac_missing") and 1 or 0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding,
        ImVec2(constants.UI.DOCK_SLOT_PADDING_X, constants.UI.DOCK_BAR_PADDING_Y))
    local okBegin, _, visible = pcall(ImGui.Begin, "##CoOptDockStrip", true, barFlags())
    if not okBegin then
        ImGui.PopStyleVar(3)
        return
    end
    if visible then
        dockLayout.contained(uiState, "dock degraded strip", function()
            ImGui.AlignTextToFramePadding()
            theme.TextMuted("CoOpt")
            ImGui.SameLine(0, 8)
            local col = theme.Colors[spec.color] or theme.Colors.Warning
            local msg = spec.msgFn and spec.msgFn(deg) or spec.msg
            ImGui.TextColored(theme.ToVec4(col), msg)
            if spec.tip and ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.PushTextWrapPos(360)
                ImGui.TextWrapped(spec.tip)
                ImGui.PopTextWrapPos()
                ImGui.EndTooltip()
            end
            if spec.btn then
                ImGui.SameLine(0, 10)
                if ImGui.SmallButton(spec.btn.label .. "##dockStripFix") then
                    M.queue(ctx, spec.btn.action)
                end
            end
            ImGui.SameLine(0, 10)
            if ImGui.SmallButton("Hide for this session##dockStripHide") and uiState then
                uiState.dockStripDismissed = uiState.dockStripDismissed or {}
                uiState.dockStripDismissed[deg.id] = true
            end
            ImGui.SameLine(0, 12)
            theme.TextMuted(spec.note or "")
        end)
    end
    ImGui.End()
    ImGui.PopStyleVar(3)
end

--- Exported for dock_bottom: when the status bar is off, the command bar hosts the strip
--- so the degraded conditions still have a surface (they are the states that decide
--- whether a stranger keeps using the product).
M.renderDegradedStrip = renderDegradedStrip

--- The one-at-a-time first-run hint (mockup 14c), anchored to the segment it teaches.
--- Drawn as its own sibling window AFTER the popover so the two never fight for the same
--- screen spot; buttons queue through the action drain because dismissal writes an INI.
--- Unlike popovers this DOES show during a mythical decision — the mythical hint's whole
--- trigger is that moment.
local function renderHint(ctx, s, edge, barX, barY, barW, barH)
    local hint = hintsService.getActive()
    if not hint then return end
    local uiState = ctx.uiState

    local slot = M.slots[hint.anchor or ""] or {}
    local px = slot.x or barX
    local py = (edge == "bottom") and barY or (barY + barH)
    local pivotY = (edge == "bottom") and 1.0 or 0.0
    if ImGui.SetNextWindowPos and pivotY == 1.0 then
        ImGui.SetNextWindowPos(ImVec2(px, py), ImGuiCond.Always, ImVec2(0, 1))
    else
        ImGui.SetNextWindowPos(ImVec2(px, py))
    end
    ImGui.SetNextWindowSizeConstraints(ImVec2(320, 0), ImVec2(480, 300))

    local flags = bit32.bor(barFlags(), ImGuiWindowFlags.AlwaysAutoResize or 0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, ImVec2(10, 8))
    ImGui.PushStyleColor(ImGuiCol.Border, theme.ToVec4(theme.Colors.Warning))
    local okBegin, _, visible = pcall(ImGui.Begin, "##CoOptDockHint", true, flags)
    if not okBegin then
        ImGui.PopStyleColor(1)
        ImGui.PopStyleVar(1)
        return
    end
    if visible then
        dockLayout.contained(uiState, "dock hint", function()
            theme.TextWarning(tostring(hint.title or ""))
            ImGui.PushTextWrapPos(440)
            ImGui.TextWrapped(tostring(hint.body or ""))
            ImGui.PopTextWrapPos()
            ImGui.Spacing()
            if ImGui.SmallButton("Got it##dockHintGotIt") then
                M.queue(ctx, { kind = "hint_got_it" })
            end
            ImGui.SameLine(0, 8)
            if not hint.replay and ImGui.SmallButton("Show me all hints##dockHintAll") then
                M.queue(ctx, { kind = "hint_show_all" })
            end
        end)
    end
    ImGui.End()
    ImGui.PopStyleColor(1)
    ImGui.PopStyleVar(1)
end

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

    -- Rebuilt from scratch each frame. Keeping stale entries would leave a segment the user
    -- just disabled marked hovered forever, and its popover would never close.
    M.slots = {}

    local edge = M.edge(layoutConfig)
    local x, y, w, h = dockLayout.barRect(edge, 0)

    -- /itemui dock debug: capture what the bar actually computed, from INSIDE the frame where
    -- the ImGui queries are valid. main_loop prints it on the next tick (printing from within
    -- the render callback is the thing this whole file exists to avoid). Costs nothing unless
    -- the flag is set.
    local dbg = ctx.uiState and ctx.uiState.dockDebugRequested and {} or nil
    if dbg then
        ctx.uiState.dockDebugRequested = nil
        local lh = ImGui.GetTextLineHeight and ImGui.GetTextLineHeight()
        local vpOK = ImGui.GetMainViewport ~= nil
        local cw, ch = ImGui.CalcTextSize("Hello")
        dbg[#dbg + 1] = string.format("UIMode=%s DockTop=%s DockBottom=%s pos=%s chat=%s",
            tostring(layoutConfig.UIMode), tostring(layoutConfig.DockTop),
            tostring(layoutConfig.DockBottom), tostring(layoutConfig.DockPosition),
            tostring(layoutConfig.DockChat))
        dbg[#dbg + 1] = string.format("segments(%d)=%s", #order, table.concat(order, ","))
        dbg[#dbg + 1] = string.format("GetMainViewport=%s  viewport=%s,%s %sx%s",
            tostring(vpOK), tostring(x), tostring(y), tostring(w), tostring(h))
        dbg[#dbg + 1] = string.format("GetTextLineHeight=%s (%s)  barHeight=%s  childH=%s",
            tostring(lh), type(lh), tostring(dockLayout.barHeight()),
            tostring(h - constants.UI.DOCK_BAR_PADDING_Y * 2))
        dbg[#dbg + 1] = string.format("CalcTextSize('Hello')=%s,%s (%s)",
            tostring(cw), tostring(ch), type(cw))
        local ws = {}
        for _, id in ipairs(order) do
            ws[#ws + 1] = id .. "=" .. tostring(dockLayout.slotWidth(id, WIDEST[id] or { id }, EXTRA[id]))
        end
        dbg[#dbg + 1] = "slotWidths " .. table.concat(ws, " ")
        dbg[#dbg + 1] = string.format("snap loot=%s corpse=%d/%d taken=%d bags=%d/%d sell=%d buffs=%d",
            tostring(s.lootState), s.lootCorpse or -1, s.lootTotalCorpses or -1, s.lootTaken or -1,
            s.bagItems or -1, s.bagSlots or -1, s.sellCount or -1, s.buffCount or -1)
        -- Every render error contained this session (dockLayout.contained dedupes into .seen),
        -- so the debug dump answers "what broke" and not just "what was computed".
        local errs = ctx.uiState.dockErrors
        if errs and errs.seen then
            for msg in pairs(errs.seen) do dbg[#dbg + 1] = "error: " .. msg end
        end
        ctx.uiState.dockDebugReport = dbg
    end

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
    -- Begin is guarded because the four style vars above it MUST be pushed first (they shape
    -- the window itself), so a throw inside Begin would strand them for the rest of the frame.
    -- If it fails there is no window to close -- unwind the pushes and give up on this frame.
    local okBegin, _, visible = pcall(ImGui.Begin, "##CoOptDockTop", true, barFlags())
    if not okBegin then
        ImGui.PopStyleVar(4)
        return
    end
    if visible then
        -- EVERYTHING between Begin and End is contained. app.lua pcalls this whole function,
        -- which sits OUTSIDE the Begin -- so an error escaping from in here would swallow the
        -- End() below and leave ImGui with an unbalanced window stack ("Missing End()"), with
        -- no Lua error shown because the pcall ate it. Per-segment containment is not enough:
        -- the slot-width measurement, SameLine, BeginChild/EndChild and the rect capture all
        -- sit between the segments and can throw too. contained (not a bare pcall) so the
        -- error is QUEUED for main_loop to print -- a bare pcall here is how the rmin.x crash
        -- blanked six segments for days with nothing in the log.
        dockLayout.contained(ctx.uiState, "dock top bar", function()
        ImGui.AlignTextToFramePadding()
        local first = true
        -- Running width, so segments that would overflow a narrow viewport are dropped from
        -- the right instead of drawing off-screen (the seven default slots reserve ~1700px).
        local usedW = constants.UI.DOCK_SLOT_PADDING_X * 2
        for _, id in ipairs(order) do
            local draw = segments[id]
            if draw then
                local slotW = dockLayout.slotWidth(id, WIDEST[id] or { id }, EXTRA[id])
                local needed = slotW + (first and 0 or constants.UI.DOCK_SLOT_GAP)
                if not first and usedW + needed > w then break end
                usedW = usedW + needed
                if not first then ImGui.SameLine(0, constants.UI.DOCK_SLOT_GAP) end
                first = false
                -- A fixed-width, borderless child is what pins the slot: content reflows
                -- inside it and the neighbours never move.
                if ImGui.BeginChild("dockseg_" .. id, ImVec2(slotW, h - constants.UI.DOCK_BAR_PADDING_Y * 2), false,
                        bit32.bor(ImGuiWindowFlags.NoScrollbar, ImGuiWindowFlags.NoScrollWithMouse)) then
                    -- NO AlignTextToFramePadding here. The child is exactly one text line tall
                    -- (bar height minus its two paddings), and that call raises the line's text
                    -- baseline offset by FramePadding.y -- pushing content down by ~3px inside a
                    -- clip rect with no room for it, which shears the descenders off "bags" and
                    -- "expiring" and cuts the bottom border off the inline Take/Pass/Stop
                    -- buttons. The parent already aligned; a SmallButton is exactly one line
                    -- tall (FramePadding.y is forced to 0 for it), so everything fits at y=0.
                    -- Per-segment isolation. app.lua's pcall around the whole render is not
                    -- enough on its own: it sits OUTSIDE the four PushStyleVar calls below, so
                    -- an error escaping to it would skip End() and PopStyleVar(4) and leak four
                    -- style-stack entries EVERY frame -- unbounded growth, and eventually an
                    -- ImGui assert. Contained here, a bad segment costs its own slot and
                    -- nothing else -- and the error is queued for main_loop to print.
                    dockLayout.contained(ctx.uiState, "dock segment " .. id, draw, ctx, s)
                end
                ImGui.EndChild()
                -- Slot screen rect + hover state, remembered for phase 2: a popover opens
                -- under the segment it belongs to (or over it, when bottom-docked), so it
                -- needs where the slot actually landed. NOTE: GetItemRectMin returns TWO
                -- NUMBERS in this binding, not an ImVec2 -- indexing its return as `rmin.x`
                -- is the line that silently blanked every segment after the first. The
                -- helper owns that knowledge now (see dockLayout.itemRectMin).
                local hovered = ImGui.IsItemHovered and ImGui.IsItemHovered() or false
                local rx, ry = dockLayout.itemRectMin()
                M.slots[id] = { x = rx, y = ry, w = slotW, h = h, hovered = hovered }
            end
        end
        end)
    end
    ImGui.End()
    ImGui.PopStyleVar(4)

    -- Popover after the bar's End(), so it is a sibling window and can extend past the strip.
    renderDegradedStrip(ctx, s, edge)
    renderPopover(ctx, s, edge, x, y, w, h)
    renderHint(ctx, s, edge, x, y, w, h)
end

return M
