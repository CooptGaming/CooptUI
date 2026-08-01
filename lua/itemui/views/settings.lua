--[[
    Settings View - Orchestrator for CoOpt UI Settings window.
    Renders tab bar and delegates to config_general, config_sell, config_loot, config_shared.
    Part of ItemUI Phase 7 / Task 07: Split config view.
    Renamed from views/config.lua to avoid confusion with root config.lua (INI utilities).
--]]

require('ImGui')

local context = require('itemui.context')
local registry = require('itemui.core.registry')
local windowHeader = require('itemui.components.window_header')

local ConfigView = {}

-- Per 4.2 state ownership: load flag
local state = {
    configNeedsLoad = false,
}
function ConfigView.getState()
    return state
end

local ConfigGeneral = require('itemui.views.config_general')
local ConfigSell = require('itemui.views.config_sell')
local ConfigLoot = require('itemui.views.config_loot')
local ConfigShared = require('itemui.views.config_shared')
local ConfigAdvanced = require('itemui.views.config_advanced')
local ConfigFilters = require('itemui.views.config_filters')
local defaultLayout = require('itemui.utils.default_layout')

local function renderConfigWindow(ctx)
    local uiState = ctx.uiState
    local filterState = ctx.filterState
    local layoutConfig = ctx.layoutConfig
    local config = ctx.config
    local theme = ctx.theme
    local loadConfigCache = ctx.loadConfigCache
    local scheduleLayoutSave = ctx.scheduleLayoutSave

    local forceApply = uiState.layoutRevertedApplyFrames and uiState.layoutRevertedApplyFrames > 0
    local w, h = layoutConfig.WidthConfig or 0, layoutConfig.HeightConfig or 0
    if w and h and w > 0 and h > 0 then
        ImGui.SetNextWindowSize(ImVec2(w, h), forceApply and ImGuiCond.Always or ImGuiCond.FirstUseEver)
    end
    local ok = ImGui.Begin("CoOpt UI Settings##ItemUIConfig", registry.isOpen("config"))
    registry.setWindowState("config", ok, ok)
    if not ok then state.configNeedsLoad = true; ImGui.End(); return end

    if state.configNeedsLoad then loadConfigCache(); state.configNeedsLoad = false end
    if not uiState._firstRunChecked then
        uiState._firstRunChecked = true
        -- First-run default protection, keyed on a persistent marker in the onboarding INI.
        -- (The old sell_flags.ini-existence heuristic was dead: the welcome env check
        -- generates that file before Settings ever opens.) Seed only when the user has no
        -- keep keywords, so real config is never stomped; then mark seeded either way.
        local seeded = config.readINIValue and config.readINIValue("coopui_onboarding.ini", "Onboarding", "defaults_seeded", "FALSE")
        if seeded ~= "TRUE" then
            local keepContains = ctx.configSellLists and ctx.configSellLists.keepContains
            if keepContains then
                if #keepContains == 0 then
                    ConfigFilters.loadDefaultProtectList(ctx)
                    ctx.setStatusMessage("Welcome! Default protection loaded.")
                end
                if config.writeINIValue then
                    config.writeINIValue("coopui_onboarding.ini", "Onboarding", "defaults_seeded", "TRUE")
                end
            end
        end
    end

    local barsOn = tostring(layoutConfig.UIMode or "classic") == "bars"

    --- Open the INI folder in Explorer. Shared by both header forms so the icon and the
    --- classic button can never drift apart.
    local function openConfigFolder()
        local path = config.CONFIG_PATH
        if path and path ~= "" then
            path = path:gsub("/", "\\")
            -- Single launcher (the old extra mq.cmd('/execute ...') opened Explorer twice;
            -- /execute is not a verified command in this MQ setup). os.execute causes a
            -- brief render-thread hitch, but no main-loop deferral is reachable from here.
            os.execute(('start "" "%s"'):format(path))
            ctx.setStatusMessage("Opened config folder")
        else ctx.setStatusMessage("Config path not available") end
    end

    if barsOn then
        -- 19d: the shared band. "CoOpt UI Settings" as a line under a title bar that
        -- already says it is the §9 duplication, so the band's title replaces it outright.
        -- Reload and Open folder become icon actions; Revert stays a NAMED button below,
        -- because an unlabelled icon is the wrong home for something that rewrites layout
        -- (rule 6's concern -- destructive verbs say what they are).
        -- No stat: the band's stat answers "the one number the bar does not show", and this
        -- window genuinely has no number. Inventing one would be furniture.
        windowHeader.render({
            id = "config", title = "Settings",
            actions = {
                { label = windowHeader.GLYPHS.REFRESH, tooltip = "Reload all settings from INI files",
                  onClick = function() loadConfigCache() end },
                { label = windowHeader.GLYPHS.FOLDER, tooltip = "Open the config folder in Windows Explorer",
                  onClick = openConfigFolder },
            },
            lock = windowHeader.registryLock("config", ctx),
        })
        if ImGui.Button("Revert to Default Layout##Config", ImVec2(170, 0)) then
            if ctx.revertToBundledDefaultLayoutRequest then ctx.revertToBundledDefaultLayoutRequest() end
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Reset all window positions, sizes, column settings, and layout preferences to the bundled default."); ImGui.Text("Does not affect user data (lists, filters, cached items)."); ImGui.EndTooltip() end
    else
        ImGui.TextColored(theme.ToVec4(theme.Colors.Header), "CoOpt UI Settings")
        ImGui.SameLine()
        if ImGui.Button("Reload from files##Config", ImVec2(130, 0)) then loadConfigCache() end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Reload all settings from INI files"); ImGui.EndTooltip() end
        ImGui.SameLine()
        if ImGui.Button("Open Config Folder##Config", ImVec2(150, 0)) then openConfigFolder() end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Open the config folder in Windows Explorer."); ImGui.Text("Quick access to all INI files."); ImGui.EndTooltip() end
        ImGui.SameLine()
        if ImGui.Button("Revert to Default Layout##Config", ImVec2(170, 0)) then
            if ctx.revertToBundledDefaultLayoutRequest then ctx.revertToBundledDefaultLayoutRequest() end
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Reset all window positions, sizes, column settings, and layout preferences to the bundled default."); ImGui.Text("Does not affect user data (lists, filters, cached items)."); ImGui.EndTooltip() end
        ImGui.Separator()
    end

    -- Revert to Default Layout confirmation modal
    if uiState.revertLayoutConfirmOpen and not ImGui.IsPopupOpen("Revert to Default Layout##ItemUI") then
        ImGui.OpenPopup("Revert to Default Layout##ItemUI")
    end
    if ImGui.BeginPopupModal("Revert to Default Layout##ItemUI", nil, ImGuiWindowFlags.AlwaysAutoResize) then
        ImGui.TextColored(theme.ToVec4(theme.Colors.Warning), "Revert to Default Layout")
        ImGui.Separator()
        ImGui.TextWrapped("This will reset all window positions, sizes, column settings, and layout preferences to the bundled default.")
        ImGui.TextWrapped("Your lists, filters, and cached items will not be changed.")
        ImGui.Spacing()
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Companion windows will reposition immediately. The main Inventory Companion window position applies after you restart MacroQuest.")
        ImGui.Spacing()
        if ImGui.Button("Confirm##RevertLayout", ImVec2(120, 0)) then
            -- The bundled default file says UIMode=classic (so upgrades never flip into
            -- bars), which means a bars user's mode choice must survive the overwrite by
            -- hand. Same for the bar toggles: reverting the LAYOUT should not silently
            -- switch the whole UI paradigm out from under the player.
            local lc = ctx.layoutConfig or {}
            local keepMode, keepTop, keepBottom = lc.UIMode, lc.DockTop, lc.DockBottom
            local keepPos, keepChat = lc.DockPosition, lc.DockChat
            local keepBotStyle, keepButtons = lc.DockBottomStyle, lc.DockButtons
            local ok, err = defaultLayout.revertToBundledDefaultLayout()
            if ok then
                if ctx.perfCache then ctx.perfCache.layoutCached = nil; ctx.perfCache.layoutNeedsReload = true end
                if ctx.loadLayoutConfig then ctx.loadLayoutConfig() end
                if ctx.setLayoutValue and keepMode ~= nil then
                    ctx.setLayoutValue("UIMode", keepMode)
                    if keepTop ~= nil then ctx.setLayoutValue("DockTop", keepTop) end
                    if keepBottom ~= nil then ctx.setLayoutValue("DockBottom", keepBottom) end
                    if keepPos ~= nil then ctx.setLayoutValue("DockPosition", keepPos) end
                    if keepChat ~= nil then ctx.setLayoutValue("DockChat", keepChat) end
                    if keepBotStyle ~= nil then ctx.setLayoutValue("DockBottomStyle", keepBotStyle) end
                    if keepButtons ~= nil then ctx.setLayoutValue("DockButtons", keepButtons) end
                end
                uiState.layoutRevertedApplyFrames = 5  -- Force SetNextWindowPos/Size to apply from layoutConfig for next 5 frames
                ctx.setStatusMessage("Layout reverted to default. Companion windows will reposition; main window position applies after restarting MacroQuest.")
            else
                ctx.setStatusMessage("Revert failed: " .. tostring(err or "unknown"))
            end
            uiState.revertLayoutConfirmOpen = false
            ImGui.CloseCurrentPopup()
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Apply bundled default layout"); ImGui.EndTooltip() end
        ImGui.SameLine()
        if ImGui.Button("Cancel##RevertLayout", ImVec2(80, 0)) then
            uiState.revertLayoutConfirmOpen = false
            ImGui.CloseCurrentPopup()
        end
        ImGui.EndPopup()
    end

    filterState.configTab = filterState.configTab or 1
    if filterState.configTab < 1 or filterState.configTab > 5 then filterState.configTab = 1 end
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
    ImGui.SameLine()
    tabBtn("Advanced", 5, 90, "Debug channels and advanced options")
    ImGui.Separator()

    if filterState.configTab == 1 then ConfigGeneral.render(ctx)
    elseif filterState.configTab == 2 then ConfigSell.render(ctx)
    elseif filterState.configTab == 3 then ConfigLoot.render(ctx)
    elseif filterState.configTab == 5 then ConfigAdvanced.render(ctx)
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

-- Registry: Config module (4.2 state ownership — window in registry, needsLoad/advancedMode in view)
registry.register({
    id        = "config",
    label     = "Settings",
    enableKey = "ShowConfigWindow",
    render    = function(refs)
        local ctx = context.build()
        ConfigView.render(ctx)
    end,
})

return ConfigView
