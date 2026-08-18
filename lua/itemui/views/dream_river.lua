--[[
    dream_river.lua — DREAM wave 1 (experiment: ShowDreamRiver, default OFF).

    The session as a TIMELINE, per MOCKUP_dream_session_river: one newest-first
    river of what happened — loot runs and sells as muted time headers (from
    dream_log's run-edge ring), augs/mythics as rows straight out of
    session_record (timestamped, with the choice and reason each carries), the
    pending mythical breathing at the top with the SAME Take/Pass handlers the
    Loot UI uses (ctx.mythicalTake/Pass — no new action path), and the day card
    on demand in the header.

    Observer rules, enforced by construction:
      * reads services (session_record, dream_log, dock_state snap, uiState),
        writes NOTHING except its own layout keys;
      * the only verbs are existing ctx handlers;
      * body pcall'd inside Begin/End (the containment skeleton);
      * experimental registry flag — absent key = the window does not exist.
]]

require('ImGui')
local context = require('itemui.context')
local registry = require('itemui.core.registry')
local windowHeader = require('itemui.components.window_header')
local sessionRecord = require('itemui.services.session_record')
local dreamLog = require('itemui.services.dream_log')
local dockState = require('itemui.services.dock_state')

local RiverView = {}

local WINDOW_W, WINDOW_H = 560, 460

local state = {
    showDayCard = false,
}
function RiverView.getState()
    return state
end

-- Game-supplied names can carry '%'; ImGui.Text formats.
local function esc(s)
    return (tostring(s):gsub("%%", "%%%%"))
end

local function fmtClock(at)
    if not at or at == 0 then return "--:--" end
    local ok, s = pcall(os.date, "%H:%M", at)
    return ok and s or "--:--"
end

local function fmtDuration(fromAt)
    if not fromAt or fromAt == 0 then return "0m" end
    local secs = math.max(0, os.time() - fromAt)
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end

--- Assemble the river, newest first: run-edge rows from dream_log merged with
--- session_record's sorted entries. (The call list renders separately on top —
--- pending things are a live surface, not history.)
local function buildRows()
    local out = {}
    for _, r in ipairs(dreamLog.getRows()) do
        out[#out + 1] = { at = r.at or 0, log = r }
    end
    for _, e in ipairs(sessionRecord.getSortedList()) do
        out[#out + 1] = { at = e.at or 0, entry = e }
    end
    table.sort(out, function(a, b) return a.at > b.at end)
    return out
end

-- ---------------------------------------------------------------- row renderers

local function glyphCell(ctx, glyph, color)
    if color == "warn" then ctx.theme.TextWarning(glyph)
    elseif color == "ok" then ctx.theme.TextSuccess(glyph)
    else ctx.theme.TextMuted(glyph) end
end

--- A muted header line (the mockup's time headers: runs and sells ARE the headers).
local function renderLogRow(ctx, r)
    local text
    if r.kind == "loot_start" then
        text = string.format("%s - loot run started", fmtClock(r.at))
    elseif r.kind == "loot_end" then
        if r.pending then
            text = string.format("%s - loot run finishing...", fmtClock(r.at))
        else
            text = string.format("%s - loot run, %d corpses, %d items", fmtClock(r.at), r.corpses or 0, r.items or 0)
            if (r.skipped or 0) > 0 then text = text .. string.format(", %d skipped", r.skipped) end
        end
    elseif r.kind == "sell_start" then
        text = string.format("%s - merchant, Auto Sell", fmtClock(r.at))
    elseif r.kind == "sell_end" then
        text = string.format("%s - Auto Sell finished", fmtClock(r.at))
        if (r.failed or 0) > 0 then text = text .. string.format(" (%d failed)", r.failed) end
    else
        text = fmtClock(r.at)
    end
    ctx.theme.TextMuted(esc(text))
    -- The best-take line rides under its run header, the mockup's "+ <item> - best of run".
    if r.kind == "loot_end" and not r.pending and r.best and r.best ~= "" then
        glyphCell(ctx, "+", "ok")
        ImGui.SameLine()
        ImGui.Text(esc(r.best))
        ImGui.SameLine()
        ctx.theme.TextMuted("- best of run")
    end
end

--- A sorted session_record entry: glyph by choice, name, reason muted.
local function renderEntryRow(ctx, e)
    local choice = tostring(e.choice or "")
    if choice == "junk" then glyphCell(ctx, "-", "mut") else glyphCell(ctx, "+", "ok") end
    ImGui.SameLine()
    ImGui.Text(esc(tostring(e.name or "?")))
    ImGui.SameLine()
    local why = choice
    if e.reason and e.reason ~= "" then why = e.reason end
    ctx.theme.TextMuted(esc("- " .. why))
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text(esc(tostring(e.name or "?")))
        ImGui.Separator()
        ctx.theme.TextMuted(string.format("%s . %s", fmtClock(e.at), esc(choice ~= "" and choice or "sorted")))
        if e.reason and e.reason ~= "" then ctx.theme.TextMuted(esc(e.reason)) end
        ImGui.EndTooltip()
    end
end

--- The pending surface: the live mythical decision (same handlers as the Loot UI)
--- and the needs-a-call list, amber, sorted to the top while pending.
local function renderPending(ctx)
    local drew = false
    local alert = ctx.uiState.lootMythicalAlert
    if alert and alert.itemName and alert.itemName ~= "" then
        local decision = tostring(alert.decision or ""):lower()
        if decision == "" or decision == "pending" then
            drew = true
            glyphCell(ctx, "!", "warn")
            ImGui.SameLine()
            ImGui.Text(esc(alert.itemName))
            ImGui.SameLine()
            ctx.theme.TextMuted("- needs a call")
            ImGui.SameLine()
            if ImGui.SmallButton("Take##RiverMythTake") and ctx.mythicalTake then ctx.mythicalTake() end
            ImGui.SameLine()
            if ImGui.SmallButton("Pass##RiverMythPass") and ctx.mythicalPass then ctx.mythicalPass() end
        end
    end
    for _, e in ipairs(sessionRecord.getCallList()) do
        drew = true
        glyphCell(ctx, "!", "warn")
        ImGui.SameLine()
        ImGui.Text(esc(tostring(e.name or "?")))
        ImGui.SameLine()
        ctx.theme.TextMuted("- needs a call")
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text(esc(tostring(e.name or "?")))
            ImGui.Separator()
            ctx.theme.TextMuted("Triage lives in the session panel (Keep / Reroll / Junk).")
            ImGui.EndTooltip()
        end
    end
    if drew then
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()
    end
end

--- The day card, on demand: session_record + the dock session totals, verbatim.
local function renderDayCard(ctx)
    local counts = sessionRecord.getCounts()
    local snap = (dockState.get and dockState.get()) or {}
    local kept, best, bestValue = 0, nil, -1
    for _, e in ipairs(sessionRecord.getSortedList()) do
        if e.cat == "mythic" and tostring(e.choice or "") ~= "junk" then kept = kept + 1 end
        if (tonumber(e.value) or 0) > bestValue then bestValue = tonumber(e.value) or 0; best = e.name end
    end
    ImGui.Spacing()
    ImGui.Text(fmtDuration(counts.startedAt))
    ImGui.SameLine()
    ctx.theme.TextSuccess(string.format("%sp", tostring(math.floor((tonumber(snap.sessionPlat) or 0)))))
    ImGui.SameLine()
    ctx.theme.TextMuted("earned")
    ImGui.SameLine()
    ImGui.Text(tostring(counts.looted or 0))
    ImGui.SameLine()
    ctx.theme.TextMuted("augs+mythics")
    ImGui.SameLine()
    ImGui.Text(tostring(counts.scripts or 0))
    ImGui.SameLine()
    ctx.theme.TextMuted("scripts")
    ImGui.SameLine()
    ctx.theme.TextWarning(tostring(kept))
    ImGui.SameLine()
    ctx.theme.TextMuted("mythicals kept")
    if best then
        ctx.theme.TextMuted(esc("best take: " .. tostring(best)))
    end
    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()
end

-- ---------------------------------------------------------------- window

local function renderBody(ctx)
    local counts = sessionRecord.getCounts()
    local snap = (dockState.get and dockState.get()) or {}
    local barsOn = tostring((ctx.layoutConfig and ctx.layoutConfig.UIMode) or "classic") == "bars"
    if barsOn and windowHeader.render then
        windowHeader.render({
            id = "dreamRiver", title = "River",
            stat = string.format("%s . %dp . %d recorded",
                fmtDuration(counts.startedAt),
                math.floor(tonumber(snap.sessionPlat) or 0),
                (counts.looted or 0) + (counts.scripts or 0)),
            lock = {
                locked = registry.isPinned("dreamRiver"),
                onToggle = function()
                    registry.setPinned("dreamRiver", not registry.isPinned("dreamRiver"))
                    if ctx.scheduleLayoutSave then ctx.scheduleLayoutSave() end
                end,
            },
        })
    end
    local label = state.showDayCard and "hide day card" or "day card"
    if ImGui.SmallButton(label .. "##RiverDayCard") then
        state.showDayCard = not state.showDayCard
    end
    ImGui.SameLine()
    ctx.theme.TextFurniture("experiment - the session as a timeline, newest first")
    ImGui.Spacing()

    if state.showDayCard then renderDayCard(ctx) end

    if ImGui.BeginChild("RiverScroll", ImVec2(0, 0), false) then
        renderPending(ctx)
        local riverRows = buildRows()
        if #riverRows == 0 then
            ctx.theme.TextMuted("Nothing yet - loot runs, sells, and tonight's calls land here as they happen.")
        end
        for i, row in ipairs(riverRows) do
            ImGui.PushID("river_" .. i)
            if row.log then renderLogRow(ctx, row.log) else renderEntryRow(ctx, row.entry) end
            ImGui.PopID()
        end
    end
    ImGui.EndChild()
end

function RiverView.render(ctx)
    if not registry.shouldDraw("dreamRiver") then return end
    local layoutConfig = ctx.layoutConfig
    local forceApply = ctx.uiState.layoutRevertedApplyFrames and ctx.uiState.layoutRevertedApplyFrames > 0
    local condPos = forceApply and ImGuiCond.Always or ImGuiCond.FirstUseEver
    local ax = layoutConfig.DreamRiverWindowX or 0
    local ay = layoutConfig.DreamRiverWindowY or 0
    if ax ~= 0 or ay ~= 0 then ImGui.SetNextWindowPos(ImVec2(ax, ay), condPos) end
    local w = layoutConfig.WidthDreamRiver or WINDOW_W
    local h = layoutConfig.HeightDreamRiver or WINDOW_H
    if w > 0 and h > 0 then
        ImGui.SetNextWindowSizeConstraints(ImVec2(380, 240), ImVec2(16384, 16384))
        ImGui.SetNextWindowSize(ImVec2(w, h), condPos)
    end
    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end
    local winOpen, winVis = ImGui.Begin("CoOpt UI River##ItemUIDreamRiver", registry.isOpen("dreamRiver"), windowFlags)
    registry.setWindowState("dreamRiver", winOpen, winOpen)
    if not winOpen then ImGui.End(); return end
    if not winVis then ImGui.End(); return end

    if not ctx.uiState.uiLocked then
        local cw, ch = ImGui.GetWindowSize()
        if cw and ch and cw > 0 and ch > 0 then
            layoutConfig.WidthDreamRiver = cw
            layoutConfig.HeightDreamRiver = ch
        end
    end
    local px, py = ImGui.GetWindowPos()
    if px and py then
        if not layoutConfig.DreamRiverWindowX or math.abs(layoutConfig.DreamRiverWindowX - px) > 1 or
           not layoutConfig.DreamRiverWindowY or math.abs(layoutConfig.DreamRiverWindowY - py) > 1 then
            layoutConfig.DreamRiverWindowX = px
            layoutConfig.DreamRiverWindowY = py
            ctx.scheduleLayoutSave()
        end
    end

    -- Containment skeleton: a throw anywhere in the body must never skip End.
    local ok, err = pcall(renderBody, ctx)
    if not ok then
        pcall(function() ctx.theme.TextError("River hit an error this frame.") end)
        local diagnostics = require('itemui.core.diagnostics')
        diagnostics.recordError("River", "Window body error", err)
    end
    ImGui.End()
end

registry.register({
    id           = "dreamRiver",
    experimental = true,
    zone         = "R2",
    label        = "River",
    buttonWidth  = 60,
    tooltip      = "EXPERIMENT - the session as a timeline: runs, sells, and calls, newest first",
    layoutKeys   = { x = "DreamRiverWindowX", y = "DreamRiverWindowY" },
    enableKey    = "ShowDreamRiver",
    render       = function(refs)
        local ctx = context.build()
        RiverView.render(ctx)
    end,
})

return RiverView
