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
    { label = "Effects",     id = "effects" },
    { label = "Clickies",    id = "favorites" },
    -- The registry Scripts companion. This used to be a bespoke button that probed and
    -- launched the standalone sidecar -- the lesser window, kept only for running without
    -- itemui, an audience that by definition is not looking at this panel. As a LAUNCHERS
    -- row it opens the real window and lights while it is open, like every other entry.
    { label = "Scripts",     id = "scripttracker" },
    { label = "Settings",    id = "config" },
}

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
    if cxPos ~= 0 or cyPos ~= 0 then
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
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        -- The grey has two causes and the tooltip names the live one - "Open a merchant
        -- first" over a button greyed by a RUNNING MACRO sent people to a merchant for
        -- nothing.
        if busy then ImGui.Text("A macro is running - wait for it or stop it above.")
        elseif not merchantOpen then ImGui.Text("Open a merchant first.")
        else ImGui.Text("Sell everything marked Sell to this merchant.") end
        ImGui.EndTooltip()
    end
    ImGui.Separator()

    -- Windows
    theme.TextHeader("Windows")
    if ImGui.Button("CoOpt UI##CmdCenter", ImVec2(110, 0)) then
        mq.cmd('/itemui')
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        local keyName = (ctx.getItemUIToggleKeyDisplay and ctx.getItemUIToggleKeyDisplay()) or "Shift+Q"
        ImGui.Text(string.format("Show/hide the CoOpt UI hub (same as %s).", keyName))
        ImGui.EndTooltip()
    end
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
    -- In this window the Keep push means OPEN, not disabled - a third meaning of one
    -- colour, and the only fully-clickable "grey" on the panel. The tooltip is what keeps
    -- that legible.
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text(lootUIOpen and "Loot window is open - click to close it." or "Open the Loot window.")
        ImGui.EndTooltip()
    end

    for i, spec in ipairs(LAUNCHERS) do
        if i % 2 == 0 then ImGui.SameLine() end
        local open = registry.isOpen(spec.id) and true or false
        theme.PushKeepButton(open)
        if ImGui.Button(spec.label .. "##CmdCenter", ImVec2(110, 0)) then
            registry.toggleWindow(spec.id)
        end
        theme.PopButtonColors()
        if open and ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text(spec.label .. " is open - click to close it.")
            ImGui.EndTooltip()
        end
    end

    ImGui.End()
end

registry.register({
    id          = "commandCenter",
    zone        = "B2",  -- window_zones placement column/slot (mockup 10a)
    -- Windows pass §0.3: in bars mode the bars carry every launcher, Loot All, Auto Sell
    -- and every status this window showed — 100% duplication. The file stays as the
    -- classic-mode surface; the registry hides it (launchers, render, tick) while
    -- UIMode=bars. Nothing is deleted.
    classicOnly = true,
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
