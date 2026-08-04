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
local ItemTooltip = require('itemui.utils.item_tooltip')
-- Leaf module (requires mq only, registers nothing) — safe at the top unlike view
-- modules, whose require-time registration order is button order.
local registry = require('itemui.core.registry')
-- Registers nothing and takes `queue` as an argument rather than requiring this file, so
-- there is no cycle (dock_bottom -> dock_top already exists).
local hubList = require('itemui.components.hub_list')

local M = {}

--- Where each slot landed on screen this frame, plus whether it is hovered:
--- { [segmentId] = { x, y, w, h, hovered } }. Phase 2's popovers anchor to these.
M.slots = {}

-- Phase 13 rebuild (26a/§11): the bar is a FIXED GRID, not a flex row. Canonical order,
-- fixed pixel widths from constants.UI.DOCK_CELL_W, and the action lane is the only cell
-- that flexes and the only one allowed to ellipsize. DockSegments is now an ENABLE SET —
-- which optional cells are on — never an order: the order is the design's (nothing may
-- move between states, and nothing moves between users either). `buttons` and `lane` are
-- not segments (26a: "Buttons are not segments") — always on, never in DockSegments.
-- A disabled segment's width goes to the lane. Saved CSVs carrying the retired `loot` id
-- just skip it: the lane carries every loot state now and cannot be turned off.
local CELL_ORDER = { "status", "session", "bags", "sell", "buttons", "lane", "buffs", "xp" }
local CELL_OPTIONAL = { status = true, session = true, bags = true, sell = true,
                        buffs = true, xp = true }

-- 21c: the cell's background says what the job is doing — the kit's three washes, one
-- meaning each. The LANE carries the job states now (loot's machine has all three edges;
-- a sell run honestly only has "running" — it has no finished/aborted edge in dock_state).
-- Status washes bad when the plugin is missing or errors are queued — same conditions its
-- label already colors.
local function segmentWash(id, s)
    if id == "lane" then
        local st = s.lootState
        if st == "looting" or st == "decision" then return theme.Kit.WashRunning end
        if st == "done" then return theme.Kit.WashDone end
        if st == "problem" then return theme.Kit.WashBad end
        if s.sellRunning or s.scriptRunning then return theme.Kit.WashRunning end
    elseif id == "status" then
        if (not s.pluginPresent) or (s.errorCount or 0) > 0 then return theme.Kit.WashBad end
    end
    return nil
end

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
    -- 26a identity cell: the name plus a status dot. The dot is an 8px square drawn with
    -- AddRectFilled (the one draw-list call proven in this binding — see the lane's
    -- progress underline); green ok, amber pluginless, red errors.
    local label = "CoOpt"
    local dotColor = theme.Kit.Good
    if not s.pluginPresent then
        dotColor = theme.Kit.Attention
        theme.TextInfo(label)
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Running without the plugin - scans are slower.")
            ImGui.Text("Everything still works.")
            ImGui.EndTooltip()
        end
    elseif s.errorCount > 0 then
        dotColor = theme.Kit.Loss
        theme.TextInfo(label)
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text(string.format("%d recent error%s - Settings > Advanced has the log.",
                s.errorCount, s.errorCount == 1 and "" or "s"))
            ImGui.EndTooltip()
        end
    else
        theme.TextInfo(label)
    end
    pcall(function()
        local drawList = ImGui.GetWindowDrawList and ImGui.GetWindowDrawList()
        -- A real DOT, not a square: AddCircleFilled(center, radius, col) is bound on this
        -- pin (lua_ImGuiUserTypes.cpp:399-401). The square was a first-pass stand-in
        -- because only AddRectFilled had been proven here; the circle is the design's
        -- shape (26a) and reads as a status light instead of a block.
        if not drawList or not drawList.AddCircleFilled then return end
        local rx, ry = dockLayout.itemRectMax()
        local ty = dockLayout.itemRectMin and select(2, dockLayout.itemRectMin()) or ry
        if not rx then return end
        local lineH = (ImGui.GetTextLineHeight and ImGui.GetTextLineHeight()) or 16
        local cy = (ty or 0) + math.floor(lineH / 2)
        local color = ImGui.GetColorU32 and ImGui.GetColorU32(theme.ToVec4(dotColor)) or 0xFF40BF59
        drawList:AddCircleFilled(ImVec2(rx + 10, cy), 4, color)
    end)
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
    -- 25b: sell is a STANDING FACT, not job output. "34 items worth 2,110p" is true
    -- whether or not a run is going — the run itself lives in the lane, and this cell
    -- ticks down live as the pile clears (dock_state keeps sellCount current mid-run).
    -- The Auto Sell button moved to the fixed button pair (26a); zero reads `0 —`.
    -- The cell is a DOOR to the hub (which shows Sell whenever a merchant is open). That
    -- matters more since the hub's auto-open on merchant became optional: with it off,
    -- this is how you get the Sell window, and the cell already names the thing it opens.
    local function openHub()
        if ImGui.IsItemHovered() and ImGui.IsMouseClicked and ImGui.IsMouseClicked(0) then
            M.queue(ctx, { kind = "hub" })
        end
    end
    if (s.sellCount or 0) <= 0 then
        labelled("sell", "0")
        openHub()
        ImGui.SameLine(0, 6)
        theme.TextMuted("-")
        openHub()
        return
    end
    local txt = string.format("%d  %sp", s.sellCount, plat(s.sellTotal))
    -- The trust case: keep-list items still queued to sell. This is the number players
    -- distrust, so it does not stay quiet.
    if s.keepInSellQueue > 0 then
        theme.TextMuted("sell")
        openHub()
        ImGui.SameLine(0, 4)
        ImGui.TextColored(theme.ToVec4(theme.Colors.Error), txt)
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text(string.format("%d keep-list item%s still in the sell queue - review before selling.",
                s.keepInSellQueue, s.keepInSellQueue == 1 and "" or "s"))
            ImGui.EndTooltip()
        end
        openHub()
    else
        labelled("sell", txt)
        openHub()
    end
end

-- ---------------------------------------------------------------------------
-- The fixed button pair + the action lane (25a/26a). Loot All and Auto Sell sit together
-- and never move; each green start becomes its own solid-red Stop IN PLACE — same slot,
-- same width — and the other button greys while a job runs (its reason lives in the lane,
-- which is the job surface). The lane belongs to whichever run is going: one progress
-- surface, two owners. Buttons queue through uiState.dockActionQueue — never a direct
-- mq.cmd from inside the frame.
-- ---------------------------------------------------------------------------

-- 25a: the running lane carries a REAL progress bar, inline between the label and the
-- counts — "one progress bar, two owners". It used to be a 3px underline along the cell's
-- bottom edge, which was a workaround from when the loot cell was ~264px wide and an
-- inline bar grew the text line enough to clip the Stop button out of the strip. The
-- phase-13 rebuild moved the buttons OUT of the lane and made the lane the flex cell
-- (~712px at 2554), so the bar fits where the design puts it.
--
-- Height is derived from the text line, never a constant: the segment child is exactly one
-- line tall, so a bar taller than that clips — the same rule the bar buttons and the
-- reroll tray cells each had to learn the hard way this pass.
local LANE_BAR_W = 200

local function laneProgressBar(frac)
    if not frac then return end
    local lh = (ImGui.GetTextLineHeight and ImGui.GetTextLineHeight()) or 13
    if type(lh) ~= "number" or lh <= 0 then lh = 13 end
    ImGui.SameLine(0, 8)
    theme.RenderProgressBar(math.min(1, math.max(0, frac)),
        ImVec2(LANE_BAR_W, math.max(6, lh - 3)), "")
end

-- Half the buttons cell, minus its paddings and the gap between the two buttons.
local BTN_W = math.floor((constants.UI.DOCK_CELL_W.buttons
    - constants.UI.DOCK_SLOT_PADDING_X * 2 - constants.UI.DOCK_SLOT_GAP) / 2)

--- Exact height for a bar button: the segment child is EXACTLY one text line tall
--- (dock_layout.barHeight = lineHeight + DOCK_BAR_PADDING_Y*2, and the child is
--- barHeight - DOCK_BAR_PADDING_Y*2), so anything taller clips against the child's clip
--- rect. That is what cut the bottoms off Loot All / Auto Sell in the field: a sized
--- ImGui.Button under FramePadding.y = 1 measures lineHeight + 2. SmallButton is immune
--- (it forces FramePadding.y = 0) but takes no size argument, and this pair must hold
--- IDENTICAL widths across every job state (§11 acceptance 11) — so: explicit size, and
--- FramePadding.y pushed to 0 by the caller.
local function barButtonSize()
    local lh = (ImGui.GetTextLineHeight and ImGui.GetTextLineHeight()) or 13
    if type(lh) ~= "number" or lh <= 0 then lh = 13 end
    return ImVec2(BTN_W, lh)
end

--- One slot of the pair: go label when startable, solid-red Stop while its own job runs,
--- kit-disabled otherwise. The pcall-around-the-button pattern is this file's standard —
--- a throwing Button must not strand the kit push (5 colors + 2 vars).
local function jobButton(ctx, id, label, running, disabled, startAction, stopAction)
    local pushedDisabled = false
    if running then
        theme.PushStopButton()
    elseif disabled then
        theme.PushKitDisabledButton()
        pushedDisabled = true
    else
        theme.PushGoButton()
    end
    local shown = running and ("Stop##" .. id) or (label .. "##" .. id)
    local ok, clickedOrErr = pcall(ImGui.Button, shown, barButtonSize())
    theme.PopKitButton()
    if not ok then error(clickedOrErr, 0) end
    if clickedOrErr and not pushedDisabled then
        M.queue(ctx, running and stopAction or startAction)
    end
end

segments.buttons = function(ctx, s)
    -- FramePadding.y MUST be 0: the segment child is exactly one text line tall, so any
    -- vertical frame padding pushes the button's bottom edge (and its 1px kit border)
    -- outside the clip rect — the clipping the field pass caught. See barButtonSize.
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, ImVec2(4, 0))
    local okPair, errPair = pcall(function()
        jobButton(ctx, "dockBtnLootAll", "Loot All",
            s.lootRunning == true,
            s.sellRunning == true,
            { kind = "loot_all" }, { kind = "loot_stop" })
        ImGui.SameLine(0, constants.UI.DOCK_SLOT_GAP)
        jobButton(ctx, "dockBtnAutoSell", "Auto Sell",
            s.sellRunning == true,
            (not s.merchantOpen) or s.lootRunning == true,
            { kind = "auto_sell" }, { kind = "sell_stop" })
    end)
    ImGui.PopStyleVar(1)
    if not okPair then error(errPair, 0) end
end

--- The action lane: every job state in one flexing cell (21c/25a). No Loot All / Auto
--- Sell / Stop here — those live in the fixed pair; the lane is the readout plus the
--- state-specific verbs that exist nowhere else (Take/Pass/Reroll, the blocked way out).
segments.lane = function(ctx, s)
    local st = s.lootState
    if st == "decision" then
        theme.TextWarning("decision")
        ImGui.SameLine(0, 4)
        local fullName = s.lootDecisionName or "Mythical item"
        local name = fullName
        -- Plain ASCII: nothing else in this codebase uses a \u{} escape, and MQ's Lua version
        -- is not pinned anywhere here (it ships a bit32 shim), so don't be the first to rely
        -- on 5.3+ escape syntax in a file that has to load for the UI to come up at all.
        --
        -- Budgeted from the lane's ACTUAL width rather than a flat 28 characters: under a
        -- decision the item's identity is the whole question, and this is the one cell that
        -- flexes. The fixed-width discipline everywhere else in this bar exists so numbers
        -- never shove their neighbours; the lane is exempt by design, and the buttons keep
        -- their room because the reserve is measured from their real labels, not guessed.
        -- Anything that still will not fit keeps the hover, which shows the full name (and
        -- the real item tooltip when the slot resolves) -- so growing is a bonus, never the
        -- only way to read it.
        local budget = nil
        if ImGui.GetContentRegionAvail and ImGui.CalcTextSize then
            local availW = ImGui.GetContentRegionAvail()
            if type(availW) == "number" and availW > 0 then
                local reserve = 0
                for _, lbl in ipairs({ "5m 00s", "Take", "Pass", "Take + reroll" }) do
                    local tw = ImGui.CalcTextSize(lbl)
                    reserve = reserve + (tonumber(tw) or 0) + 18   -- frame padding + the gap after
                end
                budget = availW - reserve
            end
        end
        if budget and budget > 60 then
            local tw = ImGui.CalcTextSize(name)
            if (tonumber(tw) or 0) > budget then
                -- Step by 2: a per-character walk on a 60-char name is 60 CalcTextSize calls
                -- a frame, and this only has to land within a character of right.
                while #name > 6 and (tonumber(ImGui.CalcTextSize(name)) or 0) > budget do
                    name = name:sub(1, #name - 2)
                end
                name = name .. "..."
            end
        elseif #name > 28 then
            name = name:sub(1, 25) .. "..."
        end
        safeText(name)
        if ImGui.IsItemHovered() then
            local shownReal = false
            if (s.lootDecisionSlot or 0) > 0 and ctx.getItemStatsForTooltip then
                -- Hover-gated TLO: the accepted exception (loot_ui.lua:310-318 does the same
                -- corpse-item lookup for its own alert card). Only reached while the name is
                -- actually hovered -- never per-frame. The compute-and-prepare step runs
                -- inside pcall so a mid-lookup error can never straddle Begin/EndTooltip;
                -- renderStatsTooltip is separately pcall-guarded internally.
                local ok, item, opts, w, h = pcall(function()
                    local showItem = ctx.getItemStatsForTooltip({ bag = 0, slot = s.lootDecisionSlot }, "corpse")
                    if not (showItem and showItem.name) then return nil end
                    -- The slot is trusted only as far as the NAME agrees: a stale INI slot
                    -- (corpse advanced, alert not yet re-read) would otherwise render a
                    -- different item's stats under this item's label. Mismatch -> the
                    -- plain-name fallback below, never wrong stats.
                    if showItem.name ~= s.lootDecisionName then return nil end
                    local o = { source = "corpse", bag = 0, slot = s.lootDecisionSlot }
                    local effects, ww, hh = ItemTooltip.prepareTooltipContent(showItem, ctx, o)
                    o.effects = effects
                    return showItem, o, ww, hh
                end)
                if ok and item then
                    ItemTooltip.beginItemTooltip(w, h)
                    ItemTooltip.renderStatsTooltip(item, ctx, opts)
                    ImGui.EndTooltip()
                    shownReal = true
                end
            end
            if not shownReal then
                -- Fallback: the FULL untruncated name -- valuable on its own since the slot
                -- above truncates at 28 chars.
                ImGui.BeginTooltip()
                safeText(fullName)
                ImGui.EndTooltip()
            end
        end
        if s.lootDecisionSecs then
            ImGui.SameLine(0, 6)
            theme.TextMuted(mmss(s.lootDecisionSecs))
        end
        ImGui.SameLine(0, 8)
        -- No key hints on these labels: no hotkey handler exists, and EQ binds F1/F2 to
        -- self/group targeting, so ImGui could not safely own those keys anyway (MQ only
        -- blocks the keyboard from EQ while a text input wants it). Buttons only, honestly.
        -- Take and Take + reroll share the keep register ON PURPOSE. Colour here says what
        -- KIND of thing an action is -- keep, skip, danger -- and these are the same kind:
        -- both loot the item. They differ by an ADDITION, not a kind, so the label carries it
        -- and the palette does not. A third colour would assert a difference that is not
        -- there, and would compete with Pass for the eye at the moment Pass is the socially
        -- consequential choice (the pause exists so a NoDrop mythical can be left for someone
        -- else in the group -- config_general's pauseOnMythicalNoDropNoTrade).
        --
        -- The old label was "Reroll", which read as take-it VERSUS reroll-it: two
        -- alternatives. The truth is take-it versus take-it-AND-queue-it, and "+" is the three
        -- characters that say containment. The lane is the flexing cell, so it has the room.
        theme.PushKeepButton()
        if ImGui.SmallButton("Take##dockLootTake") then M.queue(ctx, { kind = "loot_take" }) end
        theme.PopButtonColors()
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            -- The consequence a newcomer is actually weighing, said plainly. Reroll's tooltip
            -- has always modelled this; Take had none, which left the pair explained by half.
            safeText("Loot it. A NoDrop item soulbinds to you.")
            ImGui.EndTooltip()
        end
        ImGui.SameLine(0, 4)
        theme.PushSkipButton()
        if ImGui.SmallButton("Pass##dockLootPass") then M.queue(ctx, { kind = "loot_pass" }) end
        theme.PopButtonColors()
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            safeText("Leave it on the corpse for someone else.")
            ImGui.EndTooltip()
        end
        ImGui.SameLine(0, 4)
        theme.PushKeepButton()
        if ImGui.SmallButton("Take + reroll##dockLootReroll") then M.queue(ctx, { kind = "loot_take_reroll" }) end
        theme.PopButtonColors()
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            safeText("Take it AND queue it for the mythical reroll list.")
            ImGui.EndTooltip()
        end

    elseif st == "problem" then
        -- Blocked (25a): the lane keeps the job it owns and offers the way out inline. The
        -- mockup's "Consolidate - frees 6" needs a bag-consolidation feature this codebase
        -- does not have; until then: sell now (when a merchant makes it possible) or open
        -- the bags. The paused position keeps the run's place visible.
        local msg = tostring(s.lootProblem or "see log")
        if (s.lootTotalCorpses or 0) > 0 then
            msg = string.format("%s - loot paused at corpse %d of %d", msg, s.lootCorpse or 0, s.lootTotalCorpses)
        end
        theme.TextError(msg)
        ImGui.SameLine(0, 8)
        if s.merchantOpen and s.sellCount > 0 then
            if ImGui.SmallButton(string.format("Sell %d now##dockLaneSellNow", s.sellCount)) then
                M.queue(ctx, { kind = "auto_sell" })
            end
            ImGui.SameLine(0, 4)
        end
        if ImGui.SmallButton("Open Bags##dockLaneBags") then M.queue(ctx, { kind = "hub" }) end

    elseif st == "looting" then
        -- Running (25a): label + live counts. No Stop here — the fixed pair's Loot All IS
        -- the Stop while this runs; the lane is the readout.
        if (s.lootTotalCorpses or 0) > 0 then
            labelled("looting corpse", string.format("%d of %d", s.lootCorpse, s.lootTotalCorpses))
        else
            -- Run started, corpse census not in yet: "corpse 0/0" with a dead bar read
            -- as a rendering bug in the field. Say what the run is actually doing.
            theme.TextWarning("finding corpses")
        end
        if s.lootCorpseName and ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            safeText("On: " .. tostring(s.lootCorpseName))
            ImGui.EndTooltip()
        end
        laneProgressBar((s.lootTotalCorpses or 0) > 0
            and ((s.lootCorpse or 0) / s.lootTotalCorpses) or nil)
        ImGui.SameLine(0, 8)
        theme.TextMuted(string.format("%d taken", s.lootTaken))
        if (s.lootSkipped or 0) > 0 then
            ImGui.SameLine(0, 6)
            theme.TextMuted(string.format(". %d skipped", s.lootSkipped))
        end
        if (s.lootRunValue or 0) > 0 then
            ImGui.SameLine(0, 6)
            theme.TextSuccess(plat(s.lootRunValue) .. "p")
        end

    elseif st == "done" then
        -- Finished (25a): hold the result, say what it could NOT do (the skipped count),
        -- then dock_state's own decay returns the lane to idle.
        theme.TextSuccess(string.format("looted %d corpse%s . %sp",
            s.lootTotalCorpses, s.lootTotalCorpses == 1 and "" or "s", plat(s.lootRunValue)))
        if s.lootSkipped > 0 then
            ImGui.SameLine(0, 6)
            theme.TextMuted(string.format("%d skipped - see chat", s.lootSkipped))
        end

    elseif s.sellRunning then
        -- The other owner (25a): identical lane, different job. The sell CELL keeps the
        -- standing count ticking down; this is the run readout.
        labelled("selling", string.format("%d of %d", s.sellRunCurrent or 0, s.sellRunTotal or 0))
        laneProgressBar(s.sellRunFrac)
        if (s.sellRunValue or 0) > 0 then
            ImGui.SameLine(0, 8)
            theme.TextMuted("earned")
            ImGui.SameLine(0, 4)
            theme.TextSuccess(plat(s.sellRunValue) .. "p")
        end

    elseif s.scriptRunning then
        -- The third owner (25c): script turn-in. Unlike loot/sell it has no start button
        -- on the bar (the Scripts window starts it), so its Stop lives HERE — the one
        -- lane state that carries its own interrupt.
        if s.scriptPlanTotal and s.scriptDone then
            labelled("turning in scripts", string.format("%d of %d", s.scriptDone, s.scriptPlanTotal))
            laneProgressBar((s.scriptPlanTotal > 0) and (s.scriptDone / s.scriptPlanTotal) or nil)
        else
            labelled("turning in scripts", string.format("%d left", s.scriptRemaining or 0))
        end
        ImGui.SameLine(0, 8)
        theme.PushStopButton()
        local okStop, clickedStop = pcall(ImGui.SmallButton, "Stop##dockLaneScriptStop")
        theme.PopKitButton()
        if not okStop then error(clickedStop, 0) end
        if clickedStop then M.queue(ctx, { kind = "script_stop" }) end

    else
        -- Idle (26a): the lane names what it is for instead of sitting empty.
        theme.TextMuted("nothing running")
        ImGui.SameLine(0, 6)
        if theme.TextFurniture then
            theme.TextFurniture("- jobs report here")
        else
            theme.TextMuted("- jobs report here")
        end
    end
end

segments.buffs = function(ctx, s)
    labelled("buffs", tostring(s.buffCount))
    ImGui.SameLine(0, 6)
    labelled("songs", tostring(s.songCount))
    ImGui.SameLine(0, 6)
    theme.TextMuted("aura")
    ImGui.SameLine(0, 4)
    -- Plain ASCII, same reasoning as the loot decision name above: no \u{} glyphs. A single
    -- aura keeps the honest "y" it always had; more than one swaps to the actual count, which
    -- says more than a glyph once there is more than one to report.
    if s.auraCount > 1 then
        theme.TextSuccess(tostring(s.auraCount))
    elseif s.auraCount == 1 then
        theme.TextSuccess("y")
    else
        theme.TextMuted("-")
    end
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

--- One session value: white when it has something to say, amber while it needs a call,
--- muted AND INERT at zero (26b: the strip never invites a dead click). Non-zero values
--- are doors — click queues the toggle for the window that answers them.
--- One session value. `action` makes it a door; when the window that door opens is already
--- OPEN the value gets the kit's 2px OpenBlue underline -- the same accent the bar's
--- launchers and chat's tab strip use for "this is open", so the treatment means one thing
--- everywhere. Underline rather than the chip's full wash: these sit inside a dense strip
--- of four values and a wash on one would read as a selection, which this UI does not have.
local function sessionValue(ctx, text, color, action)
    if color then
        ImGui.TextColored(theme.ToVec4(color), text)
    else
        ImGui.Text(text)
    end
    local openId = action and action.kind == "window" and action.id or nil
    if openId and registry.isOpen(openId) then
        pcall(function()
            local dl = ImGui.GetWindowDrawList and ImGui.GetWindowDrawList()
            if not dl or not dl.AddRectFilled then return end
            local x1, y1 = dockLayout.itemRectMin()
            local x2, y2 = dockLayout.itemRectMax()
            if not (x1 and x2) then return end
            local col = ImGui.GetColorU32 and ImGui.GetColorU32(theme.ToVec4(theme.Kit.OpenBlue))
                or 0xFFFA9642
            dl:AddRectFilled(ImVec2(x1, y2 - 2), ImVec2(x2, y2), col)
            local _ = y1
        end)
    end
    if action and ImGui.IsItemHovered() and ImGui.IsMouseClicked and ImGui.IsMouseClicked(0) then
        M.queue(ctx, action)
    end
end

-- (Removed) toggleSessionPanel. 26a had the word "session" and its money value pin the
-- triage panel on left-click, which predates the universal middle-click pin every other
-- cell's popover uses. Two gestures for one job, and only on this cell — so the session
-- cell was the one place a left-click did something no other cell did. Hover still shows
-- the panel and middle-click still pins it, both unchanged and both global.

-- The session label's age suffix: cached, recomputed at most once a second (os.time has
-- 1s resolution, so a same-second hit is a pure table read) and never a date format per
-- frame. The tooltip is the ONE place persistence is explained. A nil startedAt, or a
-- negative/future delta, degrades to the bare label - no age, no error.
local sessionAge = { at = 0, started = nil, label = "session", tip = nil }
local function sessionLabelAndTip(startedAt)
    local now = os.time()
    if sessionAge.at == now and sessionAge.started == startedAt then
        return sessionAge.label, sessionAge.tip
    end
    sessionAge.at, sessionAge.started = now, startedAt
    sessionAge.label, sessionAge.tip = "session", nil
    local d = startedAt and (now - startedAt)
    if d and d >= 0 then
        if d < 60 then
            sessionAge.label = "session just started"
        elseif d < 3600 then
            sessionAge.label = string.format("session %dm", math.floor(d / 60))
        elseif d < 86400 then
            sessionAge.label = string.format("session %dh %dm",
                math.floor(d / 3600), math.floor((d % 3600) / 60))
        elseif d < 604800 then
            sessionAge.label = string.format("session %dd %dh",
                math.floor(d / 86400), math.floor((d % 86400) / 3600))
        else
            sessionAge.label = string.format("session %dd", math.floor(d / 86400))
        end
        sessionAge.tip = os.date("Started %H:%M:%S. Survives logout - Clear starts a new one.", startedAt)
    end
    return sessionAge.label, sessionAge.tip
end

segments.session = function(ctx, s)
    -- 26a slot 2, fixed 470px: the session strip — four values, every non-zero one a
    -- door. The counting rule (§12): augs/mythics show what still NEEDS A CALL, amber
    -- while any do, white 0 once cleared (that 0 is the whole point of a tuned rule
    -- set). The word "session" and the money value open the session panel itself.
    -- The label carries the session's age; when the five pieces would overflow the
    -- cell the age drops WHOLE - "session 2h..." would defeat the point of showing it.
    local label, tip = sessionLabelAndTip(s.srStartedAt)
    local moneyText = plat(s.sessionPlat) .. "p"
    local augsCall, augsTotal = s.srAugsCall or 0, s.srAugsTotal or 0
    local mythCall, mythTotal = s.srMythicsCall or 0, s.srMythicsTotal or 0
    local scripts = s.srScripts or 0
    local augsText = (augsTotal <= 0) and "0 augs"
        or string.format("%d aug%s", augsCall, augsCall == 1 and "" or "s")
    local mythsText = (mythTotal <= 0) and "0 mythics"
        or string.format("%d mythic%s", mythCall, mythCall == 1 and "" or "s")
    local scriptsText = (scripts <= 0) and "0 scripts"
        or string.format("%d script%s", scripts, scripts == 1 and "" or "s")
    if label ~= "session" then
        -- Two floats in this binding (older paths a table) - same guard as chat_window.
        local availW = ImGui.GetContentRegionAvail()
        if type(availW) == "table" then availW = availW.x end
        if type(availW) == "number" then
            local need = dockLayout.textWidth(label) + 4 + dockLayout.textWidth(moneyText)
                + 10 + dockLayout.textWidth(augsText)
                + 10 + dockLayout.textWidth(mythsText)
                + 10 + dockLayout.textWidth(scriptsText)
            if need > availW then label = "session" end
        end
    end
    theme.TextFurniture(label)
    if ImGui.IsItemHovered() then
        if tip then
            ImGui.BeginTooltip()
            ImGui.Text(tip)
            ImGui.EndTooltip()
        end
    end
    ImGui.SameLine(0, 4)
    ImGui.Text(moneyText)
    -- NEITHER the label nor the money pins the panel on left-click any more. Hovering
    -- already shows it and MIDDLE-click already pins it -- and middle-click is the
    -- universal gesture every other cell's popover uses, so a left-click that pinned only
    -- here meant one cell disagreed with the other seven about what a click does. 26a's
    -- "the word session and the money open the session panel" was written before the
    -- middle-click pin existed; the pin is the better mechanism and it is already global.

    -- Every value is a door, INCLUDING a zero. The strip's job and the window's job are
    -- different: the hover panel is for quick calls on what this session turned up, and
    -- clicking opens the full window so you can decide about everything you own. "0 augs
    -- needed a call this session" is no reason to lock you out of Aug Utility. A zero
    -- still renders muted — it is not asking for attention — it is simply not inert.
    ImGui.SameLine(0, 10)
    sessionValue(ctx, augsText,
        (augsCall > 0) and theme.Colors.Warning or ((augsTotal <= 0) and theme.Colors.Muted or nil),
        { kind = "window", id = "augmentUtility", toggle = true })

    ImGui.SameLine(0, 10)
    sessionValue(ctx, mythsText,
        (mythCall > 0) and theme.Colors.Warning or ((mythTotal <= 0) and theme.Colors.Muted or nil),
        { kind = "window", id = "mythicals", toggle = true })

    ImGui.SameLine(0, 10)
    sessionValue(ctx, scriptsText,
        (scripts <= 0) and theme.Colors.Muted or nil,
        { kind = "window", id = "scripttracker", toggle = true })
end

-- Which dock_state walks each cell needs, so an unused cell costs no TLO reads.
local SEGMENT_DEMAND = {
    -- Bags shows weight too, and weight/maxWeight/weightKnown are populated by the STATS
    -- walk -- with only requestBags the "wt" sub-segment never appears unless the xp
    -- segment happens to be enabled and demanding stats on its behalf.
    bags    = function() dockState.requestBags(); dockState.requestStats() end,
    sell    = dockState.requestSell,
    buffs   = dockState.requestBuffs,
    xp      = dockState.requestStats,
    -- The lane reads bag pressure for the blocked state; the button pair greys Auto Sell
    -- on merchant state, which rides the sell walk.
    lane    = dockState.requestBags,
    buttons = dockState.requestSell,
    -- session/status need nothing beyond the every-tick cheap reads.
}

-- ---------------------------------------------------------------------------
-- Every segment is a toggle (26a): click opens the cell's window, click again closes it.
-- The lit pair (OpenWash fill + accent underline) already means "this window is open"
-- everywhere else, so the bar needs no new vocabulary. Buttons are not segments — the
-- pair starts jobs, it never opens windows — and the lane routes to the Loot window
-- while loot owns it (the old field ask, kept).
-- ---------------------------------------------------------------------------

--- Is the hub (the merged Inventory) on screen this frame?
local function hubVisible(ctx)
    local f = ctx and ctx.getShouldDraw
    return (f and f()) == true
end

--- Which open window lights this cell. sell lights only while the hub is showing the
--- Sell view (merchant open) — hub-open alone already lights bags, and three cells lit
--- for one window would read as noise.
local function cellOpen(ctx, id, s)
    -- The identity cell opens the Hub LIST, not a window, so what it lights for is the
    -- list being up — not "is Bags open" (that is the bags cell's job).
    if id == "status" then
        return (ctx.uiState and ctx.uiState.dockPinnedPopover == "status") == true
    end
    if id == "bags" then return hubVisible(ctx) end
    if id == "sell" then return hubVisible(ctx) and s.merchantOpen == true end
    if id == "session" then return registry.isOpen("chat") == true end
    if id == "buffs" then return registry.isOpen("effects") == true end
    if id == "xp" then return registry.isOpen("aa") == true end
    return false
end

--- The queue action a background click on this cell fires. Nil = the cell has no toggle
--- (the button pair; the session cell, whose values are their own doors — §12 — so its
--- background stays inert rather than surprising a missed click).
local function cellToggleAction(id, s)
    -- status is handled inline (it opens the Hub LIST, not a window) — see the click
    -- handler in the render loop.
    if id == "bags" or id == "sell" then return { kind = "hub", toggle = true } end
    if id == "buffs" then return { kind = "window", id = "effects", toggle = true } end
    if id == "xp" then return { kind = "window", id = "aa", toggle = true } end
    if id == "lane" then
        -- Only meaningful while a job owns the lane; an idle lane click does nothing
        -- rather than opening a window nobody asked for. Loot states route to the Loot
        -- window (the old field ask); a script turn-in routes to the Scripts window.
        local st = s and s.lootState
        if st == "looting" or st == "decision" or st == "done" or st == "problem" then
            return { kind = "window", id = "loot" }
        end
        if s and s.scriptRunning then
            return { kind = "window", id = "scripttracker" }
        end
    end
    return nil
end

-- Window flags shared by the bar and its popovers. Declared HERE, above renderPopover,
-- because a `local function` is only in scope after its declaration: defined further down,
-- the call inside renderPopover would resolve to a nil GLOBAL and blow up the first time a
-- popover opened (and trip luacheck 113, which this repo enforces for exactly that reason).
local BAR_FLAGS = nil
local POPOVER_FLAGS = nil
local BASE_FLAG_NAMES = { "NoTitleBar", "NoResize", "NoMove",
                          "NoSavedSettings", "NoFocusOnAppearing", "NoNav", "NoCollapse",
                          "NoBringToFrontOnFocus", "NoDocking" }

local function orFlags(names)
    local f = 0
    local W = ImGuiWindowFlags
    for _, name in ipairs(names) do
        if W[name] then f = bit32.bor(f, W[name]) end
    end
    return f
end

local function barFlags()
    if BAR_FLAGS then return BAR_FLAGS end
    -- The bar is ONE LINE: it must never scroll, or a stray wheel over it shifts the strip.
    BAR_FLAGS = bit32.bor(orFlags(BASE_FLAG_NAMES), orFlags({ "NoScrollbar", "NoScrollWithMouse" }))
    return BAR_FLAGS
end

--- Same chrome as the bar, but SCROLLABLE. A popover is a list, and its content grows with
--- the product -- the Hub list gained Loot, Chat and Settings -- so hitting the height cap
--- has to scroll rather than clip rows away with no way to reach them. Built from the
--- shared base rather than by clearing bits out of barFlags: MQ's `bit32` is a host shim
--- and nothing in this codebase has ever relied on it having `bnot`.
function M.popoverFlags()
    if POPOVER_FLAGS then return POPOVER_FLAGS end
    POPOVER_FLAGS = orFlags(BASE_FLAG_NAMES)
    return POPOVER_FLAGS
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

-- Spell-icon texture handle for the buffs popover grid, memoised once at module scope --
-- mq.FindTextureAnimation is TLO-adjacent, so it must be resolved once, not once per icon
-- per frame. Lifted verbatim from views/effects.lua:40-51.
local BUFF_ICON_SIZE = 24
local spellIconAnim = nil
local function drawSpellIcon(iconId, size)
    if not iconId or iconId < 0 then return false end
    if not spellIconAnim and mq.FindTextureAnimation then
        spellIconAnim = mq.FindTextureAnimation("A_SpellIcons")
    end
    if not spellIconAnim then return false end
    local ok = pcall(function()
        spellIconAnim:SetTextureCell(iconId)
        ImGui.DrawTextureAnimation(spellIconAnim, size, size)
    end)
    return ok
end

--- Muted, format-safe (game names can contain '%') comma-joined name list. Used for the
--- songs/auras summary lines and as the icon grid's fallback when the texture atlas is
--- unavailable -- a grid of empty squares is worse than text.
local function mutedNameList(prefix, list)
    if not list or #list == 0 then return end
    local names = {}
    for i, e in ipairs(list) do names[i] = tostring(e.name or "?") end
    ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Muted))
    -- WRAPPED, not plain text. This was safeText, which does not wrap, so the line simply ran
    -- past the popover's right edge and was clipped -- field-reported as
    -- "songs: Scales of Draton`ra, Gem of Cleave, Double Attack Gem, Gem of Dodging, Myr"
    -- with the fifth name cut mid-word. The popover is capped at 560 wide
    -- (SetNextWindowSizeConstraints below), so any list long enough to exceed that lost its
    -- tail silently -- and a list of buff names is exactly the content whose length is set by
    -- how the character is buffed rather than by anything the UI controls.
    --
    -- Wrap position is the live content width, so it tracks whatever width the popover
    -- actually settled at rather than assuming the cap.
    local availW = ImGui.GetContentRegionAvail()
    if type(availW) == "number" and availW > 40 then
        ImGui.PushTextWrapPos(ImGui.GetCursorPosX() + availW)
        local ok, err = pcall(ImGui.TextWrapped, prefix .. table.concat(names, ", "))
        ImGui.PopTextWrapPos()
        if not ok then error(err, 0) end
    else
        safeText(prefix .. table.concat(names, ", "))
    end
    ImGui.PopStyleColor(1)
end

--- 23c: the CoOpt cell opens the launcher list — "the same launcher in a form you can
--- read", grouped ITEMS / CHARACTER / LAYOUTS, each row carrying its shortcut. The rows
--- and the list itself come from components/hub_list, which the command bar's Hub menu
--- draws from too, so the two surfaces cannot drift.
popovers.status = function(ctx, s)
    theme.TextHeaderAlt("CoOpt")
    ImGui.SameLine(0, 8)
    theme.TextMuted("everything, and where it is")
    ImGui.Separator()
    hubList.drawEntries(hubList.ENTRIES, ctx, s, M.queue)
end

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

    -- Resolved at most once per popover render (see drawSpellIcon above), so an unavailable
    -- texture never re-queries mq.FindTextureAnimation once per icon.
    if not spellIconAnim and mq.FindTextureAnimation then
        spellIconAnim = mq.FindTextureAnimation("A_SpellIcons")
    end

    --- One hoverable icon grid. `prefix` is a muted gutter word on the SAME line as the first
    --- row -- not a header line, because a header would cost a whole line per group and the
    --- groups here are three parts of one section, not three sections (SectionBreak is what
    --- separates "Expiring soon" from "Everything up", and adding another would flatten that
    --- distinction).
    ---
    --- No urgency colouring on the icons, deliberately: the Expiring soon block above already
    --- owns the red/amber ranking, and the same effect appears in both. A second urgency
    --- signal down here could disagree with the first about the same fact. The per-item hover
    --- timer is fine -- it is on demand and cannot contradict a ranking it is not part of.
    ---
    --- No Recast here either. It lives in the expiring block where the urgency is, a tooltip
    --- cannot hold a button anyway, and 25 icons offering it would be a second home for one
    --- control.
    local function iconGrid(prefix, list, idTag)
        if not list or #list == 0 then return end
        local startX = nil
        if prefix and prefix ~= "" then
            theme.TextMuted(prefix)
            ImGui.SameLine(0, 6)
            startX = ImGui.GetCursorPosX and ImGui.GetCursorPosX() or nil
        end
        -- Wrap on the CONTENT width, not the window width minus a guessed padding. This was
        -- GetWindowWidth() - 16 while the popover pushes WindowPadding (10, 8) -- 20
        -- horizontally -- so it reserved 4px too little and the last icon of a row was clipped
        -- by the window edge. GetContentRegionAvail accounts for whatever padding is actually
        -- in force, so it cannot drift from the push again.
        local availW = ImGui.GetContentRegionAvail()
        if type(availW) ~= "number" or availW <= 0 then availW = ImGui.GetWindowWidth() - 20 end
        local perRow = math.max(1, math.floor(availW / (BUFF_ICON_SIZE + 4)))
        for i, b in ipairs(list) do
            if (i - 1) % perRow ~= 0 then
                ImGui.SameLine(0, 4)
            elseif i > 1 and startX then
                -- Wrapped rows line up under the first icon rather than under the gutter word.
                ImGui.SetCursorPosX(startX)
            end
            ImGui.PushID(idTag .. i)
            if not drawSpellIcon(b.icon, BUFF_ICON_SIZE) then
                ImGui.Dummy(ImVec2(BUFF_ICON_SIZE, BUFF_ICON_SIZE))
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                safeText(tostring(b.name or "?"))
                if not b.permanent then theme.TextMuted(mmss(b.seconds)) end
                ImGui.EndTooltip()
            end
            ImGui.PopID()
        end
    end

    local buffs = s.buffs or {}
    if spellIconAnim then
        iconGrid(nil, buffs, "dockbuff")
        -- Songs get the grid too. They are the same KIND of thing as a buff -- timed, plural,
        -- and already sharing the Expiring soon block above -- so every affordance the grid
        -- offers actually fires for them.
        iconGrid("songs", s.songs, "docksong")
    else
        mutedNameList("", buffs)
        mutedNameList("songs: ", s.songs)
    end

    -- Auras stay a NAME, and the line is the clock rather than the count. Every affordance in
    -- the grid is time-related: the hover is the name plus `if not permanent then mmss(...)`,
    -- and the block above escalates the same items as they get short. An aura is permanent, so
    -- that branch never fires -- an aura icon's hover would show its name and nothing else,
    -- which is exactly the text already on screen without hovering. An icon whose hover adds
    -- nothing is a worse label than the label.
    --
    -- Not "a grid of one looks silly": that would flip the moment someone runs two auras. The
    -- clock rule holds at any count. It also keeps the two apart when they read alike -- the
    -- field capture had `songs: Myrmidon's Aura Effect` beside `aura: Myrmidons Aura`, and as
    -- bare icons telling those apart would need a hover on each.
    mutedNameList("aura: ", s.auras)

    if ImGui.Button("Open Buffs window##dockBuffsOpen") then
        M.queue(ctx, { kind = "window", id = "effects" })
    end
end

--- The session triage panel (26b/26c): hover to open, decide from the panel. Nothing
--- ever leaves — a decided item drops into SORTED and the bar counts only what's left.
--- Keyboard triage (arrows + K/R/J) waits on the keybind pass: these bar windows refuse
--- focus by design, so keys belong to the future docked form of this list.
local sessionRecord = require('itemui.services.session_record')

local CALL_ROWS_MAX = 8      -- panel rows before "+N more" (the panel is a glance, not a table)
local SORTED_ROWS_MAX = 10

local augmentHelpers = require('itemui.utils.augment_helpers')

-- ---------------------------------------------------------------------------
-- 26b: "Right-click opens the same menu builder from §7 — a hover panel is just another
-- place to open it."
--
-- It cannot be opened INSIDE the panel. The popover only exists while hover says so, and
-- `hover.inPopover` is re-derived each frame from IsWindowHovered(ChildWindows) — but an
-- ImGui popup is a separate TOP-LEVEL window, not a child, so the moment the mouse enters
-- the menu the popover stops refreshing its grace timer, expires 250ms later, and takes
-- the menu down with it. So the menu gets its own zero-footprint host drawn from
-- M.render, outside renderPopover entirely — the pattern views/native_hover.lua already
-- uses for exactly this reason. Right-clicking also pins the panel, so the list you were
-- reading stays put behind the menu.
-- ---------------------------------------------------------------------------
local SESSION_MENU_POPUP = "##CooptSessionRowMenu"
local sessionMenu = { item = nil, openRequested = false }

--- Turn a session entry into something the §7 builder can render — or nil, which means
--- "do not open a menu for this row".
---
--- ONLY a live entry gets a menu, and only by re-linking to its actual inventory row via
--- acquiredSeq (identity; bag/slot is position — another item can occupy the slot after
--- this one moves). A synthetic stand-in was tried and abandoned: the builder's rows key
--- off bag/slot, and a row with neither still renders Open it / Inspect / Reroll as
--- ENABLED, so the menu offers verbs that quietly do nothing or fire commands at a
--- location that does not exist. Blocking them one at a time is six guards that have to
--- stay in sync with a growing row table; not offering the menu is one rule that cannot
--- rot.
---
--- Departed is now a real answer rather than a bookkeeping artifact: the merge walk
--- re-links an entry to its row by item identity, so a restart or a bag shuffle no longer
--- reads as the item having left. A row that still has no menu genuinely has no item —
--- and it keeps the three chips (Keep / Reroll / Junk), which carry their own canDecide
--- guards and are the decisions the panel exists for.
local function sessionMenuItem(ctx, e)
    if not e or e.departed or not e.rowSeq then return nil, nil end
    local wantId = tonumber(e.itemId) or 0
    for _, row in ipairs(ctx.inventoryItems or {}) do
        -- Identity is verified, not assumed, mirroring the record's own merge walk: an
        -- acquiredSeq follows the SLOT before it follows the item (scan.lua stamps bag:slot
        -- first), so between a bag shuffle and the next tick this stamp can point at
        -- whatever moved into the entry's old slot -- and the menu and hover card would act
        -- on the wrong item.
        if row.acquiredSeq == e.rowSeq
            and tostring(row.name or "") == tostring(e.name or "")
            and (wantId <= 0 or (tonumber(row.id) or 0) == wantId) then
            return row, "inv"
        end
    end
    return nil, nil
end

--- Host + draw the pending session-row menu. Called from M.render AFTER the bar's End(),
--- like the popover, but independent of it.
local function renderSessionMenu(ctx, s)
    if not sessionMenu.item then return end
    -- The same veto renderPopover applies: nothing that eats clicks may sit over the game
    -- at the exact moment the player is being asked to press Take or Pass. The popover
    -- gets this for free by not drawing; this host is independent of it, so it has to
    -- honour the rule itself or the menu would outlive the panel straight through a
    -- mythical decision.
    if s and s.lootState == "decision" then
        sessionMenu.item, sessionMenu.source, sessionMenu.openRequested = nil, nil, false
        return
    end
    ImGui.SetNextWindowPos(ImVec2(-2000, -2000))
    ImGui.SetNextWindowSize(ImVec2(1, 1))
    local flags = bit32.bor(ImGuiWindowFlags.NoTitleBar, ImGuiWindowFlags.NoResize,
        ImGuiWindowFlags.NoMove, ImGuiWindowFlags.NoBackground, ImGuiWindowFlags.NoSavedSettings,
        ImGuiWindowFlags.NoFocusOnAppearing, ImGuiWindowFlags.NoBringToFrontOnFocus,
        ImGuiWindowFlags.NoNav)
    local okBegin = pcall(ImGui.Begin, "##CooptSessionMenuHost", true, flags)
    if not okBegin then sessionMenu.item = nil; return end
    if sessionMenu.openRequested then
        sessionMenu.openRequested = false
        ImGui.OpenPopup(SESSION_MENU_POPUP)
    end
    if ImGui.BeginPopup(SESSION_MENU_POPUP) then
        -- pcall INSIDE the popup pair: a throw that skips EndPopup is the same
        -- unbalanced-stack class that kills the script. ui_common is required lazily —
        -- it pulls in the menu builder, and dock_top loads before the view layer.
        pcall(function()
            local uiCommon = require('itemui.components.ui_common')
            uiCommon.renderItemContextMenuContents(ctx, sessionMenu.item, {
                source = sessionMenu.source or "inv",
                bankOpen = (ctx.isBankWindowOpen and ctx.isBankWindowOpen()) or false,
                hasCursor = (ctx.hasItemOnCursor and ctx.hasItemOnCursor()) or false,
            })
        end)
        ImGui.EndPopup()
    else
        -- The popup closing is how the host learns to stop existing.
        sessionMenu.item = nil
        sessionMenu.source = nil
    end
    ImGui.End()
end

--- 26b's per-row line: "why this deserves attention". The designed copy is "fits 3 of
--- your slots" vs "fits nothing you own", which needs a socket-type census of all 23
--- equipped items — roughly 115 TLO reads, and socket TYPES are cached nowhere (the
--- tooltip cache keeps them only inside formatted strings, and only after a hover).
--- That census belongs on a demand-driven dock_state walk, not here.
---
--- What ships instead is the half that is FREE and always true: the augment's own
--- accepted socket types, from its augType — pure bitmask arithmetic over a value
--- captured at record time. It never claims to know your slots, so it can never be
--- wrong, and there is always something true to print. That last part is the point: the
--- panel never shows a spinner and never shows a number it cannot defend.
local function sessionWhyLine(e)
    if e.cat == "mythic" then
        return e.departed and "mythic . no longer in bags" or "mythic"
    end
    if e.cat == "script" then return "script" end
    local slots = augmentHelpers.getAugTypeSlotIds(tonumber(e.augType) or 0)
    local line
    if #slots == 0 then
        line = "augment"
    elseif #slots == 1 then
        line = string.format("type %d augment", slots[1])
    else
        local ids = {}
        for i = 1, math.min(#slots, 4) do ids[#ids + 1] = tostring(slots[i]) end
        line = "types " .. table.concat(ids, ", ") .. ((#slots > 4) and "..." or "") .. " augment"
    end
    if e.departed then line = line .. " . no longer in bags" end
    return line
end

--- The hover card for a triage row. A LIVE entry re-links to its inventory row and gets
--- the real stats tooltip (the same one Bags and Bank draw). A departed one cannot -
--- there is no item to read - so it says what it knows and says plainly that the item is
--- gone, rather than rendering an empty card that looks like a failure.
---
--- The TLO reads inside the stats path are the accepted hover-gated exception, exactly as
--- the loot decision name does it: reached only while this row is actually under the
--- pointer, never per frame. Contained so a lookup error can never straddle
--- BeginTooltip/EndTooltip.
local function sessionRowTooltip(ctx, e)
    local row = sessionMenuItem(ctx, e)
    if row and ctx.getItemStatsForTooltip then
        local ok, item, opts, w, h = pcall(function()
            local showItem = ctx.getItemStatsForTooltip(row, "inv")
            if not (showItem and showItem.name) then return nil end
            local o = { source = "inv", bag = row.bag, slot = row.slot }
            local effects, ww, hh = ItemTooltip.prepareTooltipContent(showItem, ctx, o)
            o.effects = effects
            return showItem, o, ww, hh
        end)
        if ok and item then
            ItemTooltip.beginItemTooltip(w, h)
            ItemTooltip.renderStatsTooltip(item, ctx, opts)
            ImGui.EndTooltip()
            return
        end
    end
    ImGui.BeginTooltip()
    safeText(tostring(e.name or "?"))
    theme.TextMuted(sessionWhyLine(e))
    if e.departed then
        theme.TextMuted("no longer in your bags - stats unavailable")
    end
    ImGui.EndTooltip()
end

popovers.session = function(ctx, s)
    theme.TextHeaderAlt("This session")
    ImGui.SameLine(0, 8)
    if s.srStartedAt and s.srStartedAt > 0 then
        theme.TextMuted("since " .. os.date("%H:%M", s.srStartedAt))
    else
        theme.TextMuted("nothing looted yet")
    end
    ImGui.SameLine(0, 12)
    if s.srCanUndo then
        if ImGui.SmallButton("Undo last##dockSessUndo") then
            pcall(sessionRecord.undo)
        end
        ImGui.SameLine(0, 4)
    end
    if ImGui.SmallButton("Clear##dockSessClear") then
        -- The design's answer to "does the session end at logout": no — it ends HERE.
        pcall(sessionRecord.clear)
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text("Starts a fresh session record. The one thing that ends a session.")
        ImGui.EndTooltip()
    end
    ImGui.Separator()

    -- The truth line (§12): the header carries the full total; the bar's amber count is
    -- only what still needs a call. It counts the DECISION record — augs and mythics — so
    -- the three numbers add up and every one of them is a row you can go and look at.
    -- Scripts are not in it: they get their own line at the foot of the panel, because
    -- they are a tally of what you collected and never a thing to rule on.
    theme.TextMuted(string.format("%d augs + mythics . %d need a call . %d sorted",
        s.srLooted or 0, s.srNeedCall or 0, s.srSorted or 0))
    theme.TextMuted(string.format("money  %sp looted . %sp sold",
        plat(s.sessionLooted), plat(s.sessionSold)))

    theme.SectionBreak()
    if theme.TextFurniture then theme.TextFurniture("NEEDS A CALL") else theme.TextMuted("NEEDS A CALL") end
    ImGui.SameLine(0, 6)
    theme.TextMuted("best first")
    local calls = {}
    pcall(function() calls = sessionRecord.getCallList() end)
    if #calls == 0 then
        theme.TextMuted("Nothing waiting on you.")
    else
        for i = 1, math.min(#calls, CALL_ROWS_MAX) do
            local e = calls[i]
            ImGui.PushID("dockSessCall" .. i)
            safeText(tostring(e.name or "?"))
            -- Capture hover ONCE, before anything else is submitted. Drawing the tooltip
            -- below submits items of its own, so a second IsItemHovered() after it would
            -- be asking about the wrong item — and the right-click handler that follows
            -- would silently stop firing.
            local rowHovered = ImGui.IsItemHovered and ImGui.IsItemHovered() or false
            -- Hovering a row shows the item, same stats card every other item row in the
            -- product gives you. You cannot decide Keep / Reroll / Junk from a name and a
            -- price - the card IS the decision material, and without it the panel is
            -- asking you to rule on something you cannot see.
            if rowHovered then
                sessionRowTooltip(ctx, e)
            end
            -- Right-click the row = the same §7 menu, from here. Stashed and drawn by
            -- renderSessionMenu outside this window (see its header for why), and the
            -- panel pins itself so the list survives the menu.
            if rowHovered and ImGui.IsMouseClicked and ImGui.IsMouseClicked(ImGuiMouseButton.Right) then
                local item, src = sessionMenuItem(ctx, e)
                if item then
                    sessionMenu.item, sessionMenu.source = item, src
                    sessionMenu.openRequested = true
                    if ctx.uiState then ctx.uiState.dockPinnedPopover = "session" end
                end
            end
            ImGui.SameLine(280)
            ImGui.Text(plat(e.value) .. "p")
            ImGui.SameLine(0, 10)
            -- Three chips cover the common calls; an impossible one greys with its
            -- reason inline (§12) — never a tooltip.
            for _, chip in ipairs({ { c = "keep", l = "Keep" }, { c = "reroll", l = "Reroll" }, { c = "junk", l = "Junk" } }) do
                local okTo, why = sessionRecord.canDecide(e.uid, chip.c)
                if okTo then
                    if ImGui.SmallButton(chip.l .. "##sess" .. i) then
                        pcall(sessionRecord.decide, e.uid, chip.c)
                    end
                else
                    theme.TextMuted(chip.l .. (why and (" - " .. why) or ""))
                end
                ImGui.SameLine(0, 4)
            end
            -- 26b: "Every row says why it is worth your attention... without that line
            -- you are just reading names."
            theme.TextMuted(sessionWhyLine(e))
            ImGui.PopID()
        end
        if #calls > CALL_ROWS_MAX then
            theme.TextMuted(string.format("+%d more", #calls - CALL_ROWS_MAX))
        end
    end

    theme.SectionBreak()
    -- SORTED stays countable (nothing ever leaves the session) but collapsed — a record,
    -- not a queue.
    if ImGui.CollapsingHeader(string.format("SORTED %d##dockSessSorted", s.srSorted or 0)) then
        local sorted = {}
        pcall(function() sorted = sessionRecord.getSortedList() end)
        for i = 1, math.min(#sorted, SORTED_ROWS_MAX) do
            local e = sorted[i]
            ImGui.PushID("dockSessSorted" .. i)
            safeText(tostring(e.name or "?"))
            ImGui.SameLine(280)
            theme.TextMuted(tostring(e.reason or e.choice or ""))
            ImGui.PopID()
        end
        if #sorted > SORTED_ROWS_MAX then
            theme.TextMuted(string.format("+%d more", #sorted - SORTED_ROWS_MAX))
        end
    end

    if (s.srScripts or 0) > 0 then
        theme.SectionBreak()
        theme.TextMuted(string.format("scripts  %d looted this session - the Scripts window turns them in", s.srScripts))
        if ImGui.SmallButton("Open Scripts##dockSessScripts") then
            M.queue(ctx, { kind = "window", id = "scripttracker" })
        end
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
    -- "Full preview" opens the SELL PREVIEW MODAL -- the dry run listing exactly what Auto
    -- Sell would sell, with a Why column. The comment here used to claim there was no such
    -- window and that the hub's Sell view "IS the full preview"; there is one
    -- (sell.lua's "Sell Preview##ItemUI"), it is what the merchant strip's own Preview button
    -- opens, and it is what a button called Full preview should show.
    --
    -- Worse, the old action was a bare hub open, and the hub only switches to Sell when a
    -- merchant is open -- so with no merchant this button silently opened the INVENTORY.
    -- Field-reported exactly that way.
    if s.merchantOpen then
        if ImGui.Button("Full preview##dockSellPreview") then
            M.queue(ctx, { kind = "sell_preview" })
        end
    else
        -- The modal renders INSIDE the sell view, and main_window only renders that view at a
        -- merchant, so there is genuinely nothing to show. Say so, exactly as the Sell button
        -- above already does -- a replacement line, not a greyed control.
        theme.TextMuted("Preview needs an open merchant.")
    end
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
            -- Was `(pinned == hoveredId) and nil or hoveredId`, which is the broken Lua
            -- ternary: with a nil true-branch, `true and nil` is nil and the `or` hands
            -- back hoveredId — so middle-clicking an ALREADY-pinned popover re-pinned it
            -- instead of releasing it, and the only way out was Esc. Pre-existing; found
            -- because the new CoOpt toggle was written in the same shape.
            if pinned == hoveredId then
                uiState.dockPinnedPopover = nil
            else
                uiState.dockPinnedPopover = hoveredId
            end
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
    -- Max height is what is actually left between the bar and the far screen edge, not a
    -- fixed 420. The Hub list grows with the product -- it gained Loot, Chat and Settings
    -- when the one-bar mode turned out to strand them -- and a constant that was generous
    -- in 26a silently CLIPPED the tail, which is worse than the reachability gap those
    -- entries were added to close. 24px keeps it off the very edge.
    local _, vpY, vpW, vpH = dockLayout.viewport()
    local room = (edge == "bottom") and (py - vpY - 24) or ((vpY + vpH) - py - 24)
    local maxH = math.max(200, math.min(720, room))
    -- Width derives from the viewport the same way the height above already does. It was a
    -- flat 560, which is narrow on any modern screen and is what forced the buffs grid to
    -- wrap into two cramped rows while 2000px of bar sat unused beside it. AlwaysAutoResize
    -- means raising the cap only widens a popover whose CONTENT wants the room -- the sell
    -- and session popovers size themselves and are unaffected -- so this buys the icon grid
    -- its row back without making anything else sprawl. Ceiling keeps it a popover rather
    -- than a panel; the floor keeps it usable on a small viewport.
    local maxW = math.max(360, math.min(1000, math.floor((vpW or 1920) * 0.45)))
    ImGui.SetNextWindowSizeConstraints(ImVec2(360, 0), ImVec2(maxW, maxH))

    local flags = bit32.bor(M.popoverFlags(), ImGuiWindowFlags.AlwaysAutoResize or 0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, ImVec2(10, 8))
    -- Same discipline as the bar's own Begin: the style var above must be unwound if Begin
    -- itself throws, or it leaks one entry per frame while the popover is due.
    local okBegin, _, visible = pcall(ImGui.Begin, "##CoOptDockPopover", true, flags)
    if not okBegin then
        ImGui.PopStyleVar(1)
        -- hover.inPopover is normally re-derived from IsWindowHovered a few lines below, every
        -- frame the popover actually draws. Begin never fails in practice, but if it ever did,
        -- skipping that re-derivation would leave a stale `true` in place -- and the elseif
        -- branch up top reads exactly that stale value to decide whether to keep refreshing
        -- the close-grace timer, so a leftover `true` would hold the popover's countdown open
        -- indefinitely on every following frame instead of it closing on schedule.
        hover.inPopover = false
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

-- ---------------------------------------------------------------------------
-- LESSONS: one-time teaching, drawn as a CARD rather than a strip row.
--
-- These started as two more STRIPS entries, which was right about mechanics and wrong about
-- register. The line that decides it is CONDITION versus EVENT: every member of STRIPS above
-- is a condition -- it persists, it recurs, it will still be true in ten minutes -- so quiet
-- is correct, because it gets a second chance to be read. A lesson is an event. It fires once
-- on an edge and dismisses forever. It has exactly one chance, and a register built for the
-- thing that waits is wrong for the thing that happens.
--
-- Shipped as a strip, the re-tidy lesson rendered as a second bar row: same height, same
-- background, no border, no title, and `Success` green -- which in this palette means "fine,
-- informational" and is what stale_bank wears. The one entry that needed attention was
-- dressed in the word for nothing to see. Field-reported as not catching the eye at all.
--
-- So: the geometry stays (dockLayout.barRect, the dock_state trigger, the persisted flag --
-- all the things a window-anchored card would have had to reinvent) and the SHAPE comes from
-- the hint card. Looking like a hint is the goal, not a side effect: a lesson and a hint
-- teach the same kind of thing at the same kind of moment, and two vocabularies for one idea
-- is how a user learns neither. What still separates them is real and needs no styling --
-- a hint points at a cell, a lesson has no anchor at all.
--
-- Contract is the hint's, plus one addition: `action` is optional and queued. A hint teaches
-- something you will do later; a lesson can offer the thing now. M6 deliberately has none --
-- the CoOpt cell is two inches from the card, and a button that opens what the sentence
-- points at is D6's empty "Open Item Display" all over again.
-- ---------------------------------------------------------------------------

--- Copper -> readable, for the floor value in the lootfloor card. NOT the file's plat()
--- helper: that is math.floor(copper/1000), which renders the shipped STACK floor of 500
--- copper as "0p" -- a card teaching the floor by printing a wrong one.
local function copperStr(c)
    c = tonumber(c) or 0
    local p, rem = math.floor(c / 1000), c % 1000
    local g = math.floor(rem / 100)
    if p > 0 and g > 0 then return string.format("%dp %dg", p, g) end
    if p > 0 then return string.format("%dp", p) end
    if g > 0 then return string.format("%dg", g) end
    return string.format("%dc", c)
end

local LESSONS = {
    -- Ordered by dock_state's lessonStrip, not by this table: lootfloor outranks the other
    -- two because it is the only lesson explaining a number currently on the lane.
    lootfloor = {
        title = "Some items were left behind",
        -- bodyFn, not body: the sentence carries this run's counts and the LIVE floor
        -- values (latched by dock_state when the card armed). "kinds of item" is exact,
        -- not hedging: repeat skips of a name short-circuit at loot.mac's session cache,
        -- so the counters count unique names while the lane's "N skipped" counts
        -- occurrences -- a card claiming to partition that number would not add up.
        bodyFn = function(deg)
            local n, ns = tonumber(deg.n) or 0, tonumber(deg.nStack) or 0
            local total = n + ns
            local kinds = (total == 1) and "1 kind of item was" or (total .. " kinds of item were")
            if n > 0 and ns > 0 then
                return kinds .. " below your loot value floors. Settings > Loot Rules sets them."
            end
            local floor = (ns > 0) and deg.floorStack or deg.floor
            return string.format("%s below your loot value floor (%s). Settings > Loot Rules sets it.",
                kinds, copperStr(floor))
        end,
        action = { label = "Open Loot Rules", queued = { kind = "window", id = "config" } },
    },
    retidy = {
        title = "Moved windows stay put",
        -- msg and note merged: the split into a line plus a trailing muted note is a STRIP
        -- affordance (one row, no wrapping) and a card has no reason to keep it. The second
        -- sentence is the half that was missing and the half people actually need -- it was
        -- in docs/DOCK_UI.md and nowhere on screen.
        body = "A window you drag stops auto-slotting and stays where you put it. Re-tidy puts every open window back into its zone and forgets the hand placements.",
        action = { label = "Re-tidy now", queued = { kind = "retidy" } },
    },
    hublist = {
        title = "Every window, in one list",
        body = "Click CoOpt at the left of the status bar for the full list - items, character windows, layouts and their shortcuts. It is the one surface that answers what else is there.",
    },
}

--- A lesson card. Same slot under the bar as the strip, the hint card's shape inside it.
local function renderLessonCard(ctx, s, edge, index, deg)
    local spec = LESSONS[deg.lesson]
    if not spec then return end
    local uiState = ctx.uiState

    -- Positioned by the bar's own geometry, exactly as the strip is -- this is the half of
    -- the strip design worth keeping. AlwaysAutoResize so the wrapped body sets the height
    -- rather than a strip's fixed one row.
    local x, y = dockLayout.barRect(edge, index or 1)
    ImGui.SetNextWindowPos(ImVec2(x, y))
    ImGui.SetNextWindowSizeConstraints(ImVec2(360, 0), ImVec2(560, 400))
    local flags = bit32.bor(barFlags(), ImGuiWindowFlags.AlwaysAutoResize or 0)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, ImVec2(10, 8))
    ImGui.PushStyleColor(ImGuiCol.Border, theme.ToVec4(theme.Colors.Warning))
    local okBegin, _, visible = pcall(ImGui.Begin, "##CoOptDockLesson", true, flags)
    if not okBegin then
        ImGui.PopStyleColor(1)
        ImGui.PopStyleVar(1)
        return
    end
    if visible then
        dockLayout.contained(uiState, "dock lesson card", function()
            theme.TextWarning(tostring(spec.title or ""))
            ImGui.PushTextWrapPos(440)
            -- bodyFn mirrors STRIPS' msgFn: a card whose sentence carries live numbers
            -- builds it from the degraded payload; static cards keep plain body.
            local body = spec.bodyFn and spec.bodyFn(deg) or spec.body
            ImGui.TextWrapped(tostring(body or ""))
            ImGui.PopTextWrapPos()
            ImGui.Spacing()
            -- Got it FIRST, matching the hint card, so the dismissal is in the same place on
            -- both teaching surfaces.
            if ImGui.SmallButton("Got it##dockLessonGotIt") then
                if uiState then
                    uiState.dockStripDismissed = uiState.dockStripDismissed or {}
                    uiState.dockStripDismissed[deg.id] = true
                end
                -- Queued: this writes an INI, and the render path does no file IO.
                M.queue(ctx, { kind = "lesson_seen", id = deg.lesson })
            end
            if spec.action then
                ImGui.SameLine(0, 8)
                if ImGui.SmallButton(spec.action.label .. "##dockLessonAction") then
                    M.queue(ctx, spec.action.queued)
                end
            end
        end)
    end
    ImGui.End()
    ImGui.PopStyleColor(1)
    ImGui.PopStyleVar(1)
end

local function renderDegradedStrip(ctx, s, edge, index)
    local deg = s.degraded
    if not deg then return end
    local uiState = ctx.uiState
    local dismissed = uiState and uiState.dockStripDismissed
    if dismissed and dismissed[deg.id] then return end
    -- A lesson takes the same slot but not the same shape.
    if deg.lesson then return renderLessonCard(ctx, s, edge, index, deg) end
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
            -- A degraded condition can come back, so its dismissal is session-scoped and the
            -- button says exactly that. Lessons never reach here -- they are cards, and their
            -- Got it is permanent.
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

-- Divider color: a quiet grey. Equal RGB channels make the byte-order question moot; the
-- high byte is alpha either way, kept low so the rule reads as furniture, not content.
local DIVIDER_COL = 0x66565656

--- A thin vertical rule drawn INSIDE an existing gap via the draw list, so it costs no
--- layout width -- slot budgets, the overflow math and the test stub (where the draw list
--- is nil) are all untouched. x is the line's screen X; y1/y2 its vertical extent.
function M.drawDividerAt(x, y1, y2)
    local dl = ImGui.GetWindowDrawList and ImGui.GetWindowDrawList()
    if not dl then return end
    pcall(function() dl:AddLine(ImVec2(x, y1), ImVec2(x, y2), DIVIDER_COL, 1) end)
end

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
--- MANDATORY in bars mode as of 2026-08-02. `DockTop` is no longer consulted: the command
--- bar depends on this one existing -- its launcher row folds away on the assumption the
--- CoOpt cell's index catches it, it has no Hub chip because that index is here, and
--- Loot All / Auto Sell sit beside the lane that reports them. An install with a stale
--- `DockTop=0` gets the bar back, which is the intent.
function M.isEnabled(layoutConfig)
    if not layoutConfig then return false end
    return tostring(layoutConfig.UIMode or "classic") == "bars"
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

    -- DockSegments is the ENABLE SET (order is canonical — 26a). Empty = everything on;
    -- "none" enables nothing (no cell has that id); the retired `loot` id is skipped.
    local enabledCsv = csv(layoutConfig.DockSegments)
    local enabled = {}
    if #enabledCsv == 0 then
        for id in pairs(CELL_OPTIONAL) do enabled[id] = true end
    else
        for _, id in ipairs(enabledCsv) do enabled[id] = true end
    end

    -- Raise demand for exactly the cells that are on, so nothing walks TLOs unread.
    for _, id in ipairs(CELL_ORDER) do
        if (not CELL_OPTIONAL[id]) or enabled[id] then
            local want = SEGMENT_DEMAND[id]
            if want then want() end
        end
    end

    -- Rebuilt from scratch each frame. Keeping stale entries would leave a segment the user
    -- just disabled marked hovered forever, and its popover would never close.
    M.slots = {}

    local edge = M.edge(layoutConfig)
    local x, y, w, h = dockLayout.barRect(edge, 0)

    -- Resolve this frame's cells: canonical order, fixed widths, the lane takes the
    -- remainder. If the fixed cells would squeeze the lane under its minimum, optional
    -- cells drop from the RIGHT (xp first) until it fits — the lane and the button pair
    -- never drop. A dropped-or-disabled cell's width is exactly what the lane inherits.
    local CW = constants.UI.DOCK_CELL_W
    local cells = {}
    for _, id in ipairs(CELL_ORDER) do
        if (not CELL_OPTIONAL[id]) or enabled[id] then
            cells[#cells + 1] = { id = id, w = CW[id] or 0 }
        end
    end
    local function fixedTotal()
        local t, n = constants.UI.DOCK_SLOT_PADDING_X * 2, 0
        for _, c in ipairs(cells) do
            t = t + ((c.id == "lane") and 0 or c.w)
            n = n + 1
        end
        return t + math.max(0, n - 1) * constants.UI.DOCK_SLOT_GAP
    end
    while fixedTotal() + constants.UI.DOCK_LANE_MIN_W > w do
        local dropped = false
        for i = #cells, 1, -1 do
            if CELL_OPTIONAL[cells[i].id] then table.remove(cells, i); dropped = true; break end
        end
        if not dropped then break end
    end
    local laneW = math.max(constants.UI.DOCK_LANE_MIN_W, w - fixedTotal())
    for _, c in ipairs(cells) do
        if c.id == "lane" then c.w = laneW end
    end

    -- Tell hints which cells are ACTUALLY on screen this frame -- the enable set minus the
    -- narrow-width drops, i.e. the final `cells` list, not `enabled`. A hint whose anchor
    -- cell is off must be suppressed, not relocated: renderHint's `M.slots[anchor] or {}`
    -- falls back to the bar's left edge, which taught a hover gesture on a slot that was
    -- not present. The push is a plain table write, allowed on the render path.
    do
        local visible = {}
        for _, c in ipairs(cells) do visible[c.id] = true end
        if hintsService.noteVisibleCells then hintsService.noteVisibleCells(visible) end
    end

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
        local cellIds = {}
        for _, c in ipairs(cells) do cellIds[#cellIds + 1] = c.id end
        dbg[#dbg + 1] = string.format("cells(%d)=%s  DockSegments=%s", #cells,
            table.concat(cellIds, ","), tostring(layoutConfig.DockSegments))
        dbg[#dbg + 1] = string.format("GetMainViewport=%s  viewport=%s,%s %sx%s",
            tostring(vpOK), tostring(x), tostring(y), tostring(w), tostring(h))
        dbg[#dbg + 1] = string.format("GetTextLineHeight=%s (%s)  barHeight=%s  childH=%s",
            tostring(lh), type(lh), tostring(dockLayout.barHeight()),
            tostring(h - constants.UI.DOCK_BAR_PADDING_Y * 2))
        dbg[#dbg + 1] = string.format("CalcTextSize('Hello')=%s,%s (%s)",
            tostring(cw), tostring(ch), type(cw))
        local ws = {}
        for _, c in ipairs(cells) do
            ws[#ws + 1] = c.id .. "=" .. tostring(c.w)
        end
        dbg[#dbg + 1] = "cellWidths " .. table.concat(ws, " ")
        dbg[#dbg + 1] = string.format("snap loot=%s corpse=%d/%d taken=%d bags=%d/%d sell=%d buffs=%d",
            tostring(s.lootState), s.lootCorpse or -1, s.lootTotalCorpses or -1, s.lootTaken or -1,
            s.bagItems or -1, s.bagSlots or -1, s.sellCount or -1, s.buffCount or -1)
        -- The three inputs to the `problem` state, which the line above cannot show. bags=N/M
        -- is bagItems/bagSlots and bagSlots is only recomputed when bagFree reads non-nil, so
        -- a full-looking N/N does NOT prove bagFree is currently 0 -- and lootRunFinished is
        -- the guard that decides whether a full bag is a LOOT problem at all. A field report
        -- of "inventory full, console says so, bar says nothing running" could not be settled
        -- from the old dump because neither value was in it.
        dbg[#dbg + 1] = string.format("problem-inputs bagFree=%s lootRunFinished=%s lootRunning=%s problem=%s",
            tostring(s.bagFree), tostring(ctx.uiState and ctx.uiState.lootRunFinished),
            tostring(s.lootRunning), tostring(s.lootProblem))
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
        local lastRect = nil   -- previous slot's rect; the divider is drawn into the gap after it
        for _, cell in ipairs(cells) do
            local id = cell.id
            local slotW = cell.w
            local draw = segments[id]
            if draw then
                if not first then
                    ImGui.SameLine(0, constants.UI.DOCK_SLOT_GAP)
                    -- Section divider, drawn INSIDE the gap (half-way between the previous
                    -- slot's right edge and this one's left) so it adds no width anywhere.
                    if lastRect and lastRect.x then
                        local childH = h - constants.UI.DOCK_BAR_PADDING_Y * 2
                        M.drawDividerAt(lastRect.x + lastRect.w + constants.UI.DOCK_SLOT_GAP * 0.5,
                            lastRect.y + 2, lastRect.y + childH - 2)
                    end
                end
                first = false
                -- A fixed-width, borderless child is what pins the cell: content reflows
                -- inside it and the neighbours never move — the lane is the ONE cell whose
                -- width varies, and only with viewport/enable changes, never job states.
                -- Queue length before the cell draws: "the queue did not grow" identifies
                -- a background click (not on any inner button), which is what makes every
                -- cell a toggle (26a) without wiring each button.
                local queueLenBefore = ctx.uiState.dockActionQueue and #ctx.uiState.dockActionQueue or 0
                -- 21c wash: pushed tight around the child so the pop can never be skipped —
                -- only EndChild sits between, and the throwable content is contained inside.
                -- The open-window fill (26a: lit = this cell's window is open) rides the
                -- same push; a job wash outranks it in the same slot.
                local wash = segmentWash(id, s)
                local litOpen = (not wash) and cellOpen(ctx, id, s) or false
                if wash then
                    ImGui.PushStyleColor(ImGuiCol.ChildBg, theme.ToVec4(wash))
                elseif litOpen then
                    ImGui.PushStyleColor(ImGuiCol.ChildBg, theme.ToVec4(theme.Kit.OpenWash))
                end
                -- The child block runs under pcall so the wash pop below is unconditional —
                -- a throwing BeginChild must not strand the pushed color (the suite injects
                -- exactly that). The error re-raises after the pop for the outer contained.
                local okChild, childErr = pcall(function()
                if ImGui.BeginChild("dockseg_" .. id, ImVec2(slotW, h - constants.UI.DOCK_BAR_PADDING_Y * 2), false,
                        bit32.bor(ImGuiWindowFlags.NoScrollbar, ImGuiWindowFlags.NoScrollWithMouse)) then
                    -- NO AlignTextToFramePadding here. The child is exactly one text line tall
                    -- (bar height minus its two paddings), and that call raises the line's text
                    -- baseline offset by FramePadding.y -- pushing content down by ~3px inside a
                    -- clip rect with no room for it, which shears the descenders off "bags" and
                    -- "expiring" and cuts the bottom border off the inline Take/Pass buttons.
                    -- The parent already aligned; a SmallButton is exactly one line tall
                    -- (FramePadding.y is forced to 0 for it), so everything fits at y=0.
                    -- Per-segment isolation. app.lua's pcall around the whole render is not
                    -- enough on its own: it sits OUTSIDE the four PushStyleVar calls below, so
                    -- an error escaping to it would skip End() and PopStyleVar(4) and leak four
                    -- style-stack entries EVERY frame -- unbounded growth, and eventually an
                    -- ImGui assert. Contained here, a bad segment costs its own slot and
                    -- nothing else -- and the error is queued for main_loop to print.
                    dockLayout.contained(ctx.uiState, "dock segment " .. id, draw, ctx, s)
                end
                ImGui.EndChild()
                end)
                if wash or litOpen then
                    ImGui.PopStyleColor(1)
                end
                if not okChild then error(childErr, 0) end
                -- Slot screen rect + hover state, remembered for phase 2: a popover opens
                -- under the segment it belongs to (or over it, when bottom-docked), so it
                -- needs where the slot actually landed. NOTE: GetItemRectMin returns TWO
                -- NUMBERS in this binding, not an ImVec2 -- indexing its return as `rmin.x`
                -- is the line that silently blanked every segment after the first. The
                -- helper owns that knowledge now (see dockLayout.itemRectMin).
                local hovered = ImGui.IsItemHovered and ImGui.IsItemHovered() or false
                -- Every cell is a toggle (26a): a background click (no inner button grew
                -- the queue) toggles the cell's window — open it, or close it if lit. The
                -- lane routes to the Loot window while loot owns it (the old field ask).
                if hovered and ImGui.IsMouseClicked and ImGui.IsMouseClicked(0) then
                    local q = ctx.uiState.dockActionQueue
                    if (q and #q or 0) == queueLenBefore then
                        if id == "status" then
                            -- 23c: CoOpt opens the LIST of everything, not Bags. Bags has
                            -- its own cell one over. Clicking PINS the panel, so it stays
                            -- while you read it and travel down to a row — hover alone
                            -- would drop it the moment you left the 190px cell.
                            -- NOT `cond and nil or "status"`. Lua's ternary idiom breaks
                            -- when the true-branch value is nil: `true and nil` is nil, so
                            -- the `or` fires and you get "status" back — the toggle could
                            -- never turn OFF. An explicit if is the only correct form.
                            if ctx.uiState.dockPinnedPopover == "status" then
                                ctx.uiState.dockPinnedPopover = nil
                            else
                                ctx.uiState.dockPinnedPopover = "status"
                            end
                        else
                            local act = cellToggleAction(id, s)
                            if act then M.queue(ctx, act) end
                        end
                    end
                end
                local rx, ry = dockLayout.itemRectMin()
                -- The lit cell's 2px accent underline — the open-state accent the whole
                -- product uses (#12161c fill + accent). AddRect (outline) is unproven in
                -- this binding; the underline uses the proven AddRectFilled and reads as
                -- the active-tab treatment.
                if litOpen and rx then
                    pcall(function()
                        local drawList = ImGui.GetWindowDrawList and ImGui.GetWindowDrawList()
                        if not drawList or not drawList.AddRectFilled then return end
                        local childH = h - constants.UI.DOCK_BAR_PADDING_Y * 2
                        local color = ImGui.GetColorU32 and ImGui.GetColorU32(theme.ToVec4(theme.Kit.OpenBlue)) or 0xFFFA9642
                        drawList:AddRectFilled(ImVec2(rx, ry + childH - 2), ImVec2(rx + slotW, ry + childH), color)
                    end)
                end
                M.slots[id] = { x = rx, y = ry, w = slotW, h = h, hovered = hovered }
                if rx then lastRect = M.slots[id] end
            end
        end
        end)
    end
    ImGui.End()
    ImGui.PopStyleVar(4)

    -- Popover after the bar's End(), so it is a sibling window and can extend past the strip.
    renderDegradedStrip(ctx, s, edge)
    renderPopover(ctx, s, edge, x, y, w, h)
    -- AFTER the popover, and deliberately not inside it: the session row menu outlives
    -- the panel's hover grace only because its host is independent (see renderSessionMenu).
    renderSessionMenu(ctx, s)
    renderHint(ctx, s, edge, x, y, w, h)
end

return M
