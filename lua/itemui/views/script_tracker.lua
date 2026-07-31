--[[
    Script Tracker — AA scripts folded into the suite (25c / windows pass phase 15).

    What the standalone /lua run scripttracker did, as a real companion:
      * shared 26px header band (bars), the suite's lock, a launcher, Esc/LIFO
      * NO second bag scan — counts come from ctx.inventoryItems, the list core/cache
        already maintains (the old tool re-walked 10 packs on a 300ms fingerprint)
      * the by-tier grid: Lost, Planar and Rebirthed are worth the same at a given
        tier, so they share a row (the existing tool's logic, kept)
      * turn-in runs as a JOB through the existing script-consume FSM
        (main_loop.handleScriptConsume: right-click from bags + chat verification —
        no NPC involved), so it shows in the action lane with a Stop and can be
        interrupted; handing in 38 items one at a time is exactly what a user needs
        to be able to interrupt.

    Definitions live in utils/script_defs.lua — the ONE list (the standalone tool now
    reads the same module), so a Legendary can't get vendored because two lists drifted.
]]

require('ImGui')
local constants = require('itemui.constants')
local context = require('itemui.context')
local registry = require('itemui.core.registry')
local scriptDefs = require('itemui.utils.script_defs')
local windowHeader = require('itemui.components.window_header')

local ScriptTrackerView = {}

-- ---------------------------------------------------------------------------
-- Counts, from the shared inventory list. Cached: the walk is pure in-memory
-- (#items × exact-name lookup) but there is no reason to redo it per frame.
-- Keyed on the scan time + list length core/cache already maintains.
-- ---------------------------------------------------------------------------

local countCache = { key = nil, byKey = {}, totalAA = 0, totalCount = 0, slots = {} }

local function rebuildCounts(ctx)
    local items = ctx.inventoryItems or {}
    local key = string.format("%d|%s", #items, tostring(ctx.perfCache and ctx.perfCache.lastScanTimeInv or 0))
    if countCache.key == key then return countCache end
    local byKey, slots = {}, {}
    local totalAA, totalCount = 0, 0
    for _, it in ipairs(items) do
        local def = scriptDefs.BY_NAME[it.name or ""]
        if def then
            local stack = (tonumber(it.stackSize) or 1)
            if stack < 1 then stack = 1 end
            local k = def.familyShort .. ":" .. def.tierKey
            byKey[k] = (byKey[k] or 0) + stack
            totalAA = totalAA + def.aa * stack
            totalCount = totalCount + stack
            slots[#slots + 1] = { bag = it.bag, slot = it.slot, stack = stack,
                name = it.name, tierKey = def.tierKey, aa = def.aa }
        end
    end
    countCache.key = key
    countCache.byKey = byKey
    countCache.totalAA = totalAA
    countCache.totalCount = totalCount
    countCache.slots = slots
    return countCache
end

--- Force a recount on the next frame (turn-in mutates stacks through item_ops, which
--- bumps neither scan time nor necessarily list length).
local function invalidateCounts()
    countCache.key = nil
end

-- ---------------------------------------------------------------------------
-- Turn-in: enqueue through the same FSM the context menu's "Add all to Alt
-- Currency" uses. One queue entry per SLOT (the FSM consumes a slot's stack
-- sequentially, verifying each via the alternate-currency chat line).
-- ---------------------------------------------------------------------------

local function enqueueScriptConsume(uiState, payload)
    if not payload then return end
    if not uiState.pendingScriptConsume then
        uiState.pendingScriptConsume = payload
        return
    end
    local q = uiState.pendingScriptConsumeQueue or {}
    q[#q + 1] = payload
    uiState.pendingScriptConsumeQueue = q
end

local function turninRunning(uiState)
    return uiState.pendingScriptConsume ~= nil
        or (uiState.pendingScriptConsumeQueue and #uiState.pendingScriptConsumeQueue > 0) or false
end

--- Queue every counted slot (optionally one tier only) for consumption, and stamp the
--- plan total the action lane renders progress against.
local function startTurnin(ctx, counts, tierKey)
    local uiState = ctx.uiState
    local queued = 0
    for _, s in ipairs(counts.slots) do
        if (not tierKey) or s.tierKey == tierKey then
            enqueueScriptConsume(uiState, {
                bag = s.bag, slot = s.slot, source = "inv",
                totalToConsume = s.stack, consumedSoFar = 0, nextClickAt = 0,
                itemName = s.name,
            })
            queued = queued + s.stack
        end
    end
    if queued > 0 then
        -- The lane's denominator. dock_state clears it when nothing is pending.
        uiState.scriptTurninPlanTotal = (uiState.scriptTurninPlanTotal or 0) + queued
        if ctx.setStatusMessage then
            ctx.setStatusMessage(string.format("Turning in %d script%s...", queued, queued == 1 and "" or "s"))
        end
    end
    invalidateCounts()
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------

function ScriptTrackerView.render(ctx)
    if not registry.shouldDraw("scripttracker") then return end
    local layoutConfig = ctx.layoutConfig

    local wx = layoutConfig.ScriptTrackerWindowX
    local wy = layoutConfig.ScriptTrackerWindowY
    local forceApply = ctx.uiState.layoutRevertedApplyFrames and ctx.uiState.layoutRevertedApplyFrames > 0
    if wx and wy then
        ImGui.SetNextWindowPos(ImVec2(wx, wy), forceApply and ImGuiCond.Always or ImGuiCond.FirstUseEver)
    end
    local w = layoutConfig.WidthScriptTrackerPanel or constants.VIEWS.WidthScriptTrackerPanel
    local h = layoutConfig.HeightScriptTracker or constants.VIEWS.HeightScriptTracker
    if w > 0 and h > 0 then
        ImGui.SetNextWindowSize(ImVec2(w, h), forceApply and ImGuiCond.Always or ImGuiCond.FirstUseEver)
    end

    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end

    local winOpen, winVis = ImGui.Begin("CoOpt UI Scripts##ItemUIScriptTracker", registry.isOpen("scripttracker"), windowFlags)
    registry.setWindowState("scripttracker", winOpen, winOpen)
    if not winOpen then ImGui.End(); return end
    if not winVis then ImGui.End(); return end

    local barsOn = tostring(layoutConfig.UIMode or "classic") == "bars"
    if not barsOn and ctx.renderWindowLock then ctx.renderWindowLock(ctx, "scripttracker") end

    if not ctx.uiState.uiLocked then
        local cw, ch = ImGui.GetWindowSize()
        if cw and ch and cw > 0 and ch > 0 then
            layoutConfig.WidthScriptTrackerPanel = cw
            layoutConfig.HeightScriptTracker = ch
        end
    end
    local px, py = ImGui.GetWindowPos()
    if px and py then
        if not layoutConfig.ScriptTrackerWindowX or math.abs(layoutConfig.ScriptTrackerWindowX - px) > 1 or
           not layoutConfig.ScriptTrackerWindowY or math.abs(layoutConfig.ScriptTrackerWindowY - py) > 1 then
            layoutConfig.ScriptTrackerWindowX = px
            layoutConfig.ScriptTrackerWindowY = py
            ctx.scheduleLayoutSave()
        end
    end

    -- pcall INSIDE Begin/End so ImGui.End below is unconditional (window-body
    -- containment — the aec75c0 rule; every future window copies it).
    pcall(ScriptTrackerView.renderBody, ctx, barsOn)

    ImGui.End()
end

function ScriptTrackerView.renderBody(ctx, barsOn)
    local counts = rebuildCounts(ctx)
    local uiState = ctx.uiState
    local running = turninRunning(uiState)

    if barsOn then
        windowHeader.render({
            id = "scripttracker", title = "Scripts",
            stat = string.format("%d in bags · worth %d AA · last scan %s",
                counts.totalCount, counts.totalAA,
                os.date("%H:%M:%S", (ctx.perfCache.lastScanTimeInv or 0) / 1000)),
            actions = {
                { label = "R", tooltip = "Rescan inventory", onClick = function()
                    if ctx.refreshAllScans then ctx.refreshAllScans() end
                    invalidateCounts()
                end },
            },
            lock = {
                locked = registry.isPinned("scripttracker"),
                onToggle = function()
                    registry.setPinned("scripttracker", not registry.isPinned("scripttracker"))
                    if ctx.scheduleLayoutSave then ctx.scheduleLayoutSave() end
                end,
            },
        })
    else
        ctx.theme.TextHeader("Scripts")
        ImGui.SameLine()
        ctx.renderRefreshButton(ctx, "Refresh##ScriptTracker", "Rescan inventory",
            function() if ctx.refreshAllScans then ctx.refreshAllScans() end; invalidateCounts() end,
            { width = 70, messageBefore = "Scanning..." })
        ImGui.Separator()
    end

    -- The one number this window answers (25c): what is WAITING.
    ctx.theme.TextHeader(string.format("%d AA waiting", counts.totalAA))
    ctx.theme.TextMuted(string.format("across %d script%s", counts.totalCount,
        counts.totalCount == 1 and "" or "s"))
    ImGui.Spacing()

    -- Turn-in verbs. Disabled while a turn-in runs, reason printed beside (kit §3.5 —
    -- never a tooltip); the run itself reports in the action lane with its Stop.
    local canRun = counts.totalCount > 0 and not running
    if canRun then
        ctx.theme.PushGoButton()
    else
        ctx.theme.PushKitDisabledButton()
    end
    local okAll, clickedAll = pcall(ImGui.Button,
        string.format("Turn in all %d##scriptTurninAll", counts.totalCount), ImVec2(150, 0))
    ctx.theme.PopKitButton()
    if not okAll then error(clickedAll, 0) end
    if clickedAll and canRun then startTurnin(ctx, counts, nil) end
    ImGui.SameLine(0, 8)
    local legendaryCount = 0
    for fam, n in pairs(counts.byKey) do
        if fam:find(":legendary", 1, true) then legendaryCount = legendaryCount + n end
    end
    local canLegendary = legendaryCount > 0 and not running
    if canLegendary then
        ctx.theme.PushGoButton()
    else
        ctx.theme.PushKitDisabledButton()
    end
    local okLeg, clickedLeg = pcall(ImGui.Button, "Turn in Legendary only##scriptTurninLeg", ImVec2(180, 0))
    ctx.theme.PopKitButton()
    if not okLeg then error(clickedLeg, 0) end
    if clickedLeg and canLegendary then startTurnin(ctx, counts, "legendary") end
    if running then
        ImGui.SameLine(0, 8)
        ctx.theme.TextMuted("turn-in running - the bar's lane has the progress and the Stop")
    elseif counts.totalCount == 0 then
        ImGui.SameLine(0, 8)
        ctx.theme.TextMuted("no scripts in bags")
    end
    ImGui.Spacing()

    -- BY TIER (25c): Lost / Planar / Rebirthed share a row per tier.
    if ctx.theme.TextFurniture then
        ctx.theme.TextFurniture("BY TIER")
        ImGui.SameLine(0, 8)
        ctx.theme.TextFurniture("Lost, Planar and Rebirthed are worth the same at a given tier")
    end
    if ImGui.BeginTable("ScriptTiers", 8, ctx.uiState.tableFlags or 0) then
        local okTable = pcall(function()
            ImGui.TableSetupColumn("tier")
            ImGui.TableSetupColumn("lost")
            ImGui.TableSetupColumn("planar")
            ImGui.TableSetupColumn("rebirthed")
            ImGui.TableSetupColumn("have")
            ImGui.TableSetupColumn("aa each")
            ImGui.TableSetupColumn("aa")
            ImGui.TableSetupColumn("")
            ImGui.TableHeadersRow()
            local totHave, totAA = 0, 0
            for _, tier in ipairs(scriptDefs.TIERS) do
                local lost = counts.byKey["Lost:" .. tier.tierKey] or 0
                local planar = counts.byKey["Planar:" .. tier.tierKey] or 0
                local rebirthed = counts.byKey["Rebirthed:" .. tier.tierKey] or 0
                local have = lost + planar + rebirthed
                totHave = totHave + have
                totAA = totAA + have * tier.aa
                ImGui.TableNextRow()
                ImGui.TableNextColumn(); ImGui.Text(tier.label)
                ImGui.TableNextColumn(); ImGui.Text(tostring(lost))
                ImGui.TableNextColumn(); ImGui.Text(tostring(planar))
                ImGui.TableNextColumn(); ImGui.Text(tostring(rebirthed))
                ImGui.TableNextColumn(); ImGui.Text(tostring(have))
                ImGui.TableNextColumn(); ImGui.Text(tostring(tier.aa))
                ImGui.TableNextColumn(); ImGui.Text(tostring(have * tier.aa))
                ImGui.TableNextColumn()
                if have > 0 and not running then
                    if ImGui.SmallButton(string.format("Turn in %d##scriptTurnin_%s", have, tier.tierKey)) then
                        startTurnin(ctx, counts, tier.tierKey)
                    end
                end
            end
            ImGui.TableNextRow()
            ImGui.TableNextColumn(); ctx.theme.TextMuted("total")
            ImGui.TableNextColumn()
            ImGui.TableNextColumn()
            ImGui.TableNextColumn()
            ImGui.TableNextColumn(); ImGui.Text(tostring(totHave))
            ImGui.TableNextColumn()
            ImGui.TableNextColumn(); ImGui.Text(tostring(totAA))
            ImGui.TableNextColumn()
        end)
        ImGui.EndTable()
        if not okTable then
            -- Contained: an unbalanced table is a script-killing C++ ImGuiException.
            ctx.theme.TextMuted("(table error - see log)")
        end
    end
end

-- Registry: launcher + lifecycle like every other companion. No enableKey — the module
-- is a suite member; hiding it is closing it (matches mythicals/favorites today).
registry.register({
    id          = "scripttracker",
    label       = "Scripts",
    buttonWidth = 60,
    tooltip     = "AA scripts in bags by tier, and turn them in as an interruptible job",
    layoutKeys  = { x = "ScriptTrackerWindowX", y = "ScriptTrackerWindowY" },
    render      = function(refs)
        local ctx = context.build()
        ScriptTrackerView.render(ctx)
    end,
})

return ScriptTrackerView
