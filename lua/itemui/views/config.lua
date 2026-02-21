--[[
    Config View - Orchestrator for CoOpt UI Settings window.
    Renders tab bar and delegates to config_general, config_sell, config_loot, config_shared.
    Part of ItemUI Phase 7 / Task 07: Split config view.
--]]

local mq = require('mq')
require('ImGui')

local ConfigView = {}
local ConfigGeneral = require('itemui.views.config_general')
local ConfigSell = require('itemui.views.config_sell')
local ConfigLoot = require('itemui.views.config_loot')
local ConfigShared = require('itemui.views.config_shared')
local ConfigFilters = require('itemui.views.config_filters')

local function renderConfigWindow(ctx)
    local uiState = ctx.uiState
    local filterState = ctx.filterState
    local layoutConfig = ctx.layoutConfig
    local config = ctx.config
    local theme = ctx.theme
    local loadConfigCache = ctx.loadConfigCache
    local scheduleLayoutSave = ctx.scheduleLayoutSave

    local w, h = layoutConfig.WidthConfig or 0, layoutConfig.HeightConfig or 0
    if w and h and w > 0 and h > 0 then
        ImGui.SetNextWindowSize(ImVec2(w, h), ImGuiCond.FirstUseEver)
    end
    local ok = ImGui.Begin("CoOpt UI Settings##ItemUIConfig", uiState.configWindowOpen)
    uiState.configWindowOpen = ok
    if not ok then uiState.configNeedsLoad = true; ImGui.End(); return end

    if uiState.configNeedsLoad then loadConfigCache(); uiState.configNeedsLoad = false end
    if not uiState._firstRunChecked then
        uiState._firstRunChecked = true
        local flagsPath = config.getConfigFile and config.getConfigFile("sell_flags.ini")
        if flagsPath then
            local f = io.open(flagsPath, "r")
            if not f then
                ConfigFilters.loadDefaultProtectList(ctx)
                ctx.setStatusMessage("Welcome! Default protection loaded.")
            else f:close() end
        end
    end

    ImGui.TextColored(theme.ToVec4(theme.Colors.Header), "CoOpt UI Settings")
    ImGui.SameLine()
    if ImGui.Button("Reload from files##Config", ImVec2(130, 0)) then loadConfigCache() end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Reload all settings from INI files"); ImGui.EndTooltip() end
    ImGui.SameLine()
    if ImGui.Button("Open Config Folder##Config", ImVec2(150, 0)) then
        local path = config.CONFIG_PATH
        if path and path ~= "" then
            path = path:gsub("/", "\\")
            mq.cmd(string.format('/execute explorer.exe "%s"', path))
            os.execute(('start "" "%s"'):format(path))
            ctx.setStatusMessage("Opened config folder")
        else ctx.setStatusMessage("Config path not available") end
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Open the config folder in Windows Explorer."); ImGui.Text("Quick access to all INI files."); ImGui.EndTooltip() end
    ImGui.Separator()

    filterState.configTab = filterState.configTab or 1
    if filterState.configTab < 1 or filterState.configTab > 4 then filterState.configTab = 1 end
    local function tabBtn(label, tabId, width, tooltip)
        if ImGui.Button(label, ImVec2(width, 0)) then filterState.configTab = tabId; scheduleLayoutSave() end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(tooltip); ImGui.EndTooltip() end
        if filterState.configTab == tabId then ImGui.SameLine(0, 0); ImGui.TextColored(theme.ToVec4(theme.Colors.Success), "  <") end
    end
    tabBtn("General", 1, 90, "Window behavior, Sell options, and Loot options")
    ImGui.SameLine()
    tabBtn("Sell Rules", 2, 90, "Sell item lists (Keep, Always sell, Never sell by type)")
    ImGui.SameLine()
    tabBtn("Loot Rules", 3, 90, "Loot item lists (Always loot, Skip)")
    ImGui.SameLine()
    tabBtn("Shared", 4, 90, "Valuable list (never sell, always loot)")
    ImGui.Separator()

    if filterState.configTab == 1 then ConfigGeneral.render(ctx)
    elseif filterState.configTab == 2 then ConfigSell.render(ctx)
    elseif filterState.configTab == 3 then ConfigLoot.render(ctx)
    else ConfigShared.render(ctx) end

    local cw, ch = ImGui.GetWindowSize()
    local savedW, savedH = layoutConfig.WidthConfig or 0, layoutConfig.HeightConfig or 0
    if cw and ch and (math.abs(cw - savedW) > 1 or math.abs(ch - savedH) > 1) then
        layoutConfig.WidthConfig = cw
        layoutConfig.HeightConfig = ch
        scheduleLayoutSave()
    end
    ImGui.End()
end

function ConfigView.render(ctx)
    renderConfigWindow(ctx)
end

return ConfigView
