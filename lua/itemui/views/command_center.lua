--[[
    Command Center - one-stop CoOpt control panel (pop-out companion).

    Status block (plugin IPC, sell/loot macro state, guild hall), process
    controls (Loot All / stop, Auto Sell, ScriptTracker), and launcher
    buttons for every CoOpt window. Ideal pairing with the native Actions
    tab or a keybind: everything reachable without the hub open.
--]]

local mq = require('mq')
require('ImGui')
local context = require('itemui.context')
local registry = require('itemui.core.registry')

local CommandCenterView = {}

local LAUNCHERS = {
    { label = "Equipment",   id = "equipment" },
    { label = "Bank",        id = "bank" },
    { label = "Augments",    id = "augments" },
    { label = "Mythics",     id = "mythicals" },
    { label = "Aug Utility", id = "augmentUtility" },
    { label = "Reroll",      id = "reroll" },
    { label = "AA",          id = "aa" },
    { label = "Settings",    id = "config" },
}

-- MQ2Lua's Lua TLO isn't guaranteed on every build; nil = unknown.
local function scriptTrackerRunning()
    local ok, status = pcall(function()
        local l = mq.TLO and mq.TLO.Lua
        local s = l and l.Script and l.Script('scripttracker')
        return s and s.Status and s.Status()
    end)
    if ok and type(status) == 'string' then return status:upper() == 'RUNNING' end
    return nil
end

local function statusDot(theme, okState, labelOn, labelOff)
    if okState then theme.TextSuccess(labelOn) else theme.TextMuted(labelOff) end
end

function CommandCenterView.render(ctx)
    if not registry.shouldDraw("commandCenter") then return end

    local uiState = ctx.uiState
    local layoutConfig = ctx.layoutConfig
    local theme = ctx.theme
    local mb = ctx.macroBridge

    local forceApply = uiState.layoutRevertedApplyFrames and uiState.layoutRevertedApplyFrames > 0
    local condPos = forceApply and ImGuiCond.Always or ImGuiCond.FirstUseEver
    local cxPos = layoutConfig.CommandCenterWindowX or 0
    local cyPos = layoutConfig.CommandCenterWindowY or 0
    if cxPos ~= 0 and cyPos ~= 0 then
        ImGui.SetNextWindowPos(ImVec2(cxPos, cyPos), condPos)
    end

    local windowFlags = ImGuiWindowFlags.AlwaysAutoResize
    local winOpen, winVis = ImGui.Begin("CoOpt Command Center##ItemUICommandCenter", registry.isOpen("commandCenter"), windowFlags)
    registry.setWindowState("commandCenter", winOpen, winOpen)
    if not winOpen then ImGui.End(); return end
    if not winVis then ImGui.End(); return end
    if ctx.renderWindowLock then ctx.renderWindowLock(ctx, "commandCenter") end

    local px, py = ImGui.GetWindowPos()
    if px and py then
        if not layoutConfig.CommandCenterWindowX or math.abs(layoutConfig.CommandCenterWindowX - px) > 1 or
           not layoutConfig.CommandCenterWindowY or math.abs(layoutConfig.CommandCenterWindowY - py) > 1 then
            layoutConfig.CommandCenterWindowX = px
            layoutConfig.CommandCenterWindowY = py
            ctx.scheduleLayoutSave()
        end
    end

    local sellRunning = (mb and mb.isSellMacroRunning and mb.isSellMacroRunning()) or false
    local lootRunning = (mb and mb.isLootMacroRunning and mb.isLootMacroRunning()) or false
    local merchantOpen = (ctx.isMerchantWindowOpen and ctx.isMerchantWindowOpen()) or false
    local inGuildHall = (ctx.rerollService and ctx.rerollService.isInGuildHall and ctx.rerollService.isInGuildHall()) or false
    local pluginOn = (mb and mb.isIPCAvailable and mb.isIPCAvailable()) or false

    -- Status
    theme.TextHeader("Status")
    statusDot(theme, pluginOn, "Plugin: connected", "Plugin: not loaded (TLO fallback)")
    if sellRunning then theme.TextWarning("Sell macro: running") end
    if lootRunning then theme.TextWarning("Loot macro: running") end
    if not sellRunning and not lootRunning then theme.TextMuted("Macros: idle") end
    statusDot(theme, inGuildHall, "Guild hall: yes (reroll sync ok)", "Guild hall: no")
    ImGui.Separator()

    -- Processes
    theme.TextHeader("Processes")
    local busy = sellRunning or lootRunning
    theme.PushKeepButton(busy)
    if ImGui.Button("Loot All##CmdCenter", ImVec2(110, 0)) and not busy then
        if not uiState.suppressWhenLootMac then
            uiState.lootUIOpen = true
            uiState.lootRunFinished = false
            if ctx.recordCompanionWindowOpened then ctx.recordCompanionWindowOpened("loot") end
        end
        mq.cmd('/macro loot')
    end
    theme.PopButtonColors()
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Loot all nearby corpses using your loot rules (/macro loot)."); ImGui.EndTooltip() end
    ImGui.SameLine()
    theme.PushKeepButton(not lootRunning)
    if ImGui.Button("Stop Loot##CmdCenter", ImVec2(110, 0)) and lootRunning then
        mq.cmd('/endmacro')
    end
    theme.PopButtonColors()
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Stop the running loot macro (/endmacro)."); ImGui.EndTooltip() end

    local sellDisabled = busy or not merchantOpen
    theme.PushKeepButton(sellDisabled)
    if ImGui.Button("Auto Sell##CmdCenter", ImVec2(110, 0)) and not sellDisabled then
        uiState.autoSellRequested = true
    end
    theme.PopButtonColors()
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(merchantOpen and "Sell everything marked Sell to this merchant." or "Open a merchant first."); ImGui.EndTooltip() end
    ImGui.SameLine()
    local stRunning = scriptTrackerRunning()
    if ImGui.Button("ScriptTracker##CmdCenter", ImVec2(110, 0)) then
        if stRunning == false then
            mq.cmd('/lua run scripttracker')
        else
            -- running or unknown: show it (harmless no-op chat error when not loaded)
            mq.cmd('/st show')
            if stRunning == nil then mq.cmd('/lua run scripttracker') end
        end
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Open the ScriptTracker window (starts it if needed)."); ImGui.EndTooltip() end
    ImGui.Separator()

    -- Windows
    theme.TextHeader("Windows")
    if ImGui.Button("CoOpt UI##CmdCenter", ImVec2(110, 0)) then
        mq.cmd('/itemui')
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Show/hide the CoOpt UI hub (same as Shift+Q)."); ImGui.EndTooltip() end
    ImGui.SameLine()
    if ImGui.Button("Native Panel##CmdCenter", ImVec2(110, 0)) then
        pcall(function() mq.TLO.Window('TipWindow').DoOpen() end)
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Open the NATIVE Command Center (requires /loadskin coopt). Also: /itemui center"); ImGui.EndTooltip() end
    ImGui.SameLine()
    local lootUIOpen = uiState.lootUIOpen and true or false
    theme.PushKeepButton(lootUIOpen)
    if ImGui.Button("Loot UI##CmdCenter", ImVec2(110, 0)) then
        uiState.lootUIOpen = not lootUIOpen
        if uiState.lootUIOpen and ctx.recordCompanionWindowOpened then ctx.recordCompanionWindowOpened("loot") end
    end
    theme.PopButtonColors()

    for i, spec in ipairs(LAUNCHERS) do
        if i % 2 == 0 then ImGui.SameLine() end
        local open = registry.isOpen(spec.id) and true or false
        theme.PushKeepButton(open)
        if ImGui.Button(spec.label .. "##CmdCenter", ImVec2(110, 0)) then
            registry.toggleWindow(spec.id)
        end
        theme.PopButtonColors()
    end

    ImGui.End()
end

registry.register({
    id          = "commandCenter",
    label       = "Cmd",
    buttonWidth = 40,
    tooltip     = "Command Center: status, process controls, and launchers for every CoOpt window",
    layoutKeys  = { x = "CommandCenterWindowX", y = "CommandCenterWindowY" },
    enableKey   = "ShowCommandCenterWindow",
    render      = function(refs)
        local ctx = context.build()
        CommandCenterView.render(ctx)
    end,
})

return CommandCenterView
