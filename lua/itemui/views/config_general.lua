--[[
    Config General tab - Features, Sell options, Loot options, Layout setup.
    Part of ItemUI config view split (Task 07).
--]]

require('ImGui')

local ConfigFilters = require('itemui.views.config_filters')
local registry = require('itemui.core.registry')

local ConfigGeneral = {}

function ConfigGeneral.render(ctx)
    local uiState = ctx.uiState
    local filterState = ctx.filterState
    local layoutConfig = ctx.layoutConfig
    local config = ctx.config
    local theme = ctx.theme
    local scheduleLayoutSave = ctx.scheduleLayoutSave
    local saveLayoutToFile = ctx.saveLayoutToFile
    local loadLayoutConfig = ctx.loadLayoutConfig
    local invalidateSellConfigCache = ctx.invalidateSellConfigCache
    local invalidateLootConfigCache = ctx.invalidateLootConfigCache

    local configSellFlags = ctx.configSellFlags
    local configSellValues = ctx.configSellValues
    local configLootFlags = ctx.configLootFlags
    local configLootValues = ctx.configLootValues
    local configLootSorting = ctx.configLootSorting
    local configEpicClasses = ctx.configEpicClasses
    local EPIC_CLASSES = ctx.EPIC_CLASSES or {}

    local formatCurrency = ctx.formatCurrency
    local renderBreadcrumb = function(tab, section) ConfigFilters.renderBreadcrumb(ctx, tab, section) end
    local classLabel = ConfigFilters.classLabel

    ImGui.Spacing()
    renderBreadcrumb("General", "Overview")
    if ImGui.CollapsingHeader("Features", ImGuiTreeNodeFlags.DefaultOpen) then
        renderBreadcrumb("General", "Features")
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Turn features on or off. All are enabled by default; uncheck to disable.")
        ImGui.Spacing()
        local prevAlign = uiState.alignToContext
        uiState.alignToContext = ImGui.Checkbox("Enable snap to Inventory", uiState.alignToContext)
        if prevAlign ~= uiState.alignToContext then scheduleLayoutSave() end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("When enabled, CoOpt UI Inventory Companion stays locked to the built-in Inventory window.")
            ImGui.Text("Uncheck to place CoOpt UI Inventory Companion freely.")
            ImGui.EndTooltip()
        end
        local enableLootUI = not uiState.suppressWhenLootMac
        local prevEnableLootUI = enableLootUI
        enableLootUI = ImGui.Checkbox("Enable Loot UI during looting", enableLootUI)
        if prevEnableLootUI ~= enableLootUI then
            uiState.suppressWhenLootMac = not enableLootUI
            scheduleLayoutSave()
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("When enabled, the Loot UI window opens when you loot (manual or macro).")
            ImGui.Text("Uncheck to keep the Loot UI closed during looting.")
            ImGui.EndTooltip()
        end
        local prevConfirm = uiState.confirmBeforeDelete
        uiState.confirmBeforeDelete = ImGui.Checkbox("Enable confirm before delete", uiState.confirmBeforeDelete)
        if prevConfirm ~= uiState.confirmBeforeDelete then scheduleLayoutSave() end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("When enabled, a confirmation dialog appears before destroying an item from the context menu.")
            ImGui.Text("Uncheck to destroy without confirming.")
            ImGui.EndTooltip()
        end
        ImGui.Spacing()
        local epicEnabled = configSellFlags.protectEpic or configLootFlags.alwaysLootEpic
        local prevEpic = epicEnabled
        epicEnabled = ImGui.Checkbox("Enable Epic Loot and Protection", epicEnabled)
        if prevEpic ~= epicEnabled then
            configSellFlags.protectEpic = epicEnabled
            configLootFlags.alwaysLootEpic = epicEnabled
            config.writeINIValue("sell_flags.ini", "Settings", "protectEpic", epicEnabled and "TRUE" or "FALSE")
            config.writeLootINIValue("loot_flags.ini", "Settings", "alwaysLootEpic", epicEnabled and "TRUE" or "FALSE")
            invalidateSellConfigCache()
            invalidateLootConfigCache()
            scheduleLayoutSave()
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("When enabled, epic quest items are never sold and are always looted. Optionally limit by class below.")
            ImGui.Text("Uncheck to allow selling epic items and to stop always-looting them.")
            ImGui.EndTooltip()
        end
        ImGui.Spacing()
        if ImGui.CollapsingHeader("Companion windows", ImGuiTreeNodeFlags.None) then
            renderBreadcrumb("General", "Companion windows")
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Show or hide each companion's button and window. Uncheck to disable.")
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Re-enable any companion here or by editing Show*Window=1 in itemui_layout.ini")
                ImGui.EndTooltip()
            end
            local companions = {
                { id = "equipment",  key = "ShowEquipmentWindow",  label = "Equipment" },
                { id = "bank",       key = "ShowBankWindow",       label = "Bank" },
                { id = "augments",   key = "ShowAugmentsWindow",   label = "Augments" },
                { id = "augmentUtility", key = "ShowAugmentUtilityWindow", label = "Augment Utility" },
                { id = "itemDisplay", key = "ShowItemDisplayWindow", label = "Item Display" },
                { id = "config",     key = "ShowConfigWindow",     label = "Settings" },
                { id = "aa",        key = "ShowAAWindow",         label = "AA" },
                { id = "reroll",    key = "ShowRerollWindow",    label = "Reroll" },
            }
            for _, c in ipairs(companions) do
                local val = (tonumber(layoutConfig[c.key]) or 1) ~= 0
                local prev = val
                val = ImGui.Checkbox("Show " .. c.label .. " window##" .. c.id, val)
                if prev ~= val then
                    layoutConfig[c.key] = val and 1 or 0
                    if not val then registry.setWindowState(c.id, false, false) end
                    scheduleLayoutSave()
                end
                if c.id == "config" and ImGui.IsItemHovered() then
                    ImGui.BeginTooltip()
                    ImGui.Text("Uncheck to hide the Settings button and window.")
                    ImGui.Text("To show Settings again, set ShowConfigWindow=1 in itemui_layout.ini.")
                    ImGui.EndTooltip()
                end
            end
        end
        if epicEnabled and EPIC_CLASSES and #EPIC_CLASSES > 0 then
            ImGui.Indent()
            local nSelected = 0
            for _, cls in ipairs(EPIC_CLASSES) do
                if configEpicClasses[cls] == true then nSelected = nSelected + 1 end
            end
            local preview = (nSelected == 0) and "All classes (none selected)" or (nSelected == #EPIC_CLASSES) and "All classes" or string.format("%d class%s", nSelected, nSelected == 1 and "" or "es")
            ImGui.SetNextItemWidth(320)
            if ImGui.BeginCombo("Classes for epic##epic", preview, ImGuiComboFlags.None) then
                local rowHeight = (ImGui.GetFrameHeight and ImGui.GetFrameHeight()) or 24
                local popupHeight = (1 + #EPIC_CLASSES) * rowHeight + 24
                if ImGui.SetWindowSize then
                    ImGui.SetWindowSize(ImVec2(320, math.max(200, popupHeight)))
                end
                if ImGui.SmallButton("Select all##epic") then
                    for _, cls in ipairs(EPIC_CLASSES) do
                        configEpicClasses[cls] = true
                        config.writeSharedINIValue("epic_classes.ini", "Classes", cls, "TRUE")
                    end
                    invalidateSellConfigCache()
                    invalidateLootConfigCache()
                end
                if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Check all classes"); ImGui.EndTooltip() end
                ImGui.SameLine()
                if ImGui.SmallButton("Clear all##epic") then
                    for _, cls in ipairs(EPIC_CLASSES) do
                        configEpicClasses[cls] = false
                        config.writeSharedINIValue("epic_classes.ini", "Classes", cls, "FALSE")
                    end
                    invalidateSellConfigCache()
                    invalidateLootConfigCache()
                end
                if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Uncheck all (no epic items when none selected)"); ImGui.EndTooltip() end
                ImGui.Spacing()
                for _, cls in ipairs(EPIC_CLASSES) do
                    local v = ImGui.Checkbox(classLabel(cls) .. "##epic_" .. cls, configEpicClasses[cls] == true)
                    if v ~= (configEpicClasses[cls] == true) then
                        configEpicClasses[cls] = v
                        config.writeSharedINIValue("epic_classes.ini", "Classes", cls, v and "TRUE" or "FALSE")
                        invalidateSellConfigCache()
                        invalidateLootConfigCache()
                    end
                end
                ImGui.EndCombo()
            end
            if ImGui.IsItemHovered() then
                if ImGui.SetNextWindowSize then
                    ImGui.SetNextWindowSize(ImVec2(320, 0), ImGuiCond.Always)
                end
                ImGui.BeginTooltip()
                ImGui.TextWrapped("Choose which classes' epic quest items are protected and always looted. If none are checked, no epic items are included.")
                ImGui.EndTooltip()
            end
            ImGui.Unindent()
        end
    end
    ImGui.Spacing()
    if ImGui.CollapsingHeader("Sell", ImGuiTreeNodeFlags.DefaultOpen) then
        renderBreadcrumb("General", "Sell")
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Options for what is never sold. Item lists are on the Sell Rules tab.")
        ImGui.Spacing()
        local function sellFlag(name, key, tooltip)
            local v = ImGui.Checkbox(name, configSellFlags[key])
            if v ~= configSellFlags[key] then configSellFlags[key] = v; config.writeINIValue("sell_flags.ini", "Settings", key, v and "TRUE" or "FALSE"); invalidateSellConfigCache() end
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(tooltip); ImGui.EndTooltip() end
        end
        sellFlag("Enable No-Drop protection", "protectNoDrop", "Never sell items with the No-Drop flag")
        sellFlag("Enable No-Trade protection", "protectNoTrade", "Never sell items with the No-Trade flag")
        sellFlag("Enable Lore protection", "protectLore", "Never sell items with the Lore flag")
        sellFlag("Enable Quest protection", "protectQuest", "Never sell items with the Quest flag")
        sellFlag("Enable Collectible protection", "protectCollectible", "Never sell items with the Collectible flag")
        sellFlag("Enable Heirloom protection", "protectHeirloom", "Never sell items with the Heirloom flag")
        sellFlag("Enable sell history log", "enableSellHistoryLog", "Append each sold item to Macros/logs/item_management/sell_history.log. Off by default to avoid I/O delays when opening sell or between items.")
        ImGui.Spacing()
        ImGui.Text("Value thresholds (copper)")
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("1 platinum = 1000 copper"); ImGui.EndTooltip() end
        ImGui.Text("Min value (single)")
        ImGui.SameLine(180); ImGui.SetNextItemWidth(120)
        local vs = tostring(configSellValues.minSell)
        vs, _ = ImGui.InputText("Min value (single)##SellMin", vs, ImGuiInputTextFlags.CharsDecimal)
        local n = tonumber(vs)
        if n and n ~= configSellValues.minSell then
            configSellValues.minSell = math.max(0, math.floor(n))
            config.writeINIValue("sell_value.ini", "Settings", "minSellValue", tostring(configSellValues.minSell))
            invalidateSellConfigCache()
        end
        ImGui.SameLine()
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configSellValues.minSell))
        ImGui.Text("Min value (stack)")
        ImGui.SameLine(180); ImGui.SetNextItemWidth(120)
        vs = tostring(configSellValues.minStack)
        vs, _ = ImGui.InputText("Min value (stack)##SellStack", vs, ImGuiInputTextFlags.CharsDecimal)
        n = tonumber(vs)
        if n and n ~= configSellValues.minStack then
            configSellValues.minStack = math.max(0, math.floor(n))
            config.writeINIValue("sell_value.ini", "Settings", "minSellValueStack", tostring(configSellValues.minStack))
            invalidateSellConfigCache()
        end
        ImGui.SameLine()
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configSellValues.minStack) .. "/unit")
        ImGui.Text("Max keep value")
        ImGui.SameLine(180); ImGui.SetNextItemWidth(120)
        vs = tostring(configSellValues.maxKeep)
        vs, _ = ImGui.InputText("Max keep value##SellKeep", vs, ImGuiInputTextFlags.CharsDecimal)
        n = tonumber(vs)
        if n and n ~= configSellValues.maxKeep then
            configSellValues.maxKeep = math.max(0, math.floor(n))
            config.writeINIValue("sell_value.ini", "Settings", "maxKeepValue", tostring(configSellValues.maxKeep))
            invalidateSellConfigCache()
        end
        ImGui.SameLine()
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configSellValues.maxKeep))
    end
    ImGui.Spacing()
    if ImGui.CollapsingHeader("Loot", ImGuiTreeNodeFlags.DefaultOpen) then
        renderBreadcrumb("General", "Loot")
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Options for what to loot (loot.mac). Item lists are on the Loot Rules tab.")
        ImGui.Spacing()
        local function lootFlag(name, key, tooltip)
            local v = ImGui.Checkbox(name, configLootFlags[key])
            if v ~= configLootFlags[key] then configLootFlags[key] = v; config.writeLootINIValue("loot_flags.ini", "Settings", key, v and "TRUE" or "FALSE") end
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(tooltip); ImGui.EndTooltip() end
        end
        lootFlag("Enable loot clickies", "lootClickies", "Loot wearable items with clicky effects")
        lootFlag("Enable loot quest items", "lootQuest", "Loot items with the Quest flag")
        lootFlag("Enable loot collectible", "lootCollectible", "Loot items with the Collectible flag")
        lootFlag("Enable loot heirloom", "lootHeirloom", "Loot items with the Heirloom flag")
        lootFlag("Enable loot attuneable", "lootAttuneable", "Loot items with the Attuneable flag")
        lootFlag("Enable loot augment slots", "lootAugSlots", "Loot items that can have augments")
        ImGui.Spacing()
        lootFlag("Enable pause on Mythical NoDrop/NoTrade", "pauseOnMythicalNoDropNoTrade", "Loot Companion will open and pause so you can choose Take or Pass (5 min).")
        lootFlag("Enable alert group when Mythical pause", "alertMythicalGroupChat", "When pause triggers, send the item and corpse name to group chat (only if grouped).")
        lootFlag("Enable live loot feed", "enableLiveLootFeed", "When on, CoOpt UI Loot tab updates in real time as items are looted (one echo per item). When off, macro is slightly faster and Current/History load when the macro completes.")
        lootFlag("Quiet loot (suppress console echo)", "quietMode", "When on, the loot macro does not echo Evaluating, Skipping, LOOTING, Corpses Remaining, or startup banner. Reduces console spam and slight overhead.")
        ImGui.Spacing()
        ImGui.Text("Loot delay (ticks)")
        local ticks = tonumber(configLootFlags.lootDelayTicks)
        if not ticks or ticks < 1 or ticks > 10 then ticks = 3 end
        local val, changed = ImGui.SliderInt("##lootDelayTicks", ticks, 1, 10, "%d")
        if changed then
            val = math.max(1, math.min(10, tonumber(val) or 3))
            configLootFlags.lootDelayTicks = val
            config.writeLootINIValue("loot_flags.ini", "Settings", "lootDelayTicks", tostring(val))
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Ticks to wait after itemnotify/cursor/window. 2 = faster, 3 = default, 4+ if laggy."); ImGui.EndTooltip() end
        ImGui.SameLine()
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), tostring(configLootFlags.lootDelayTicks or 3))
        ImGui.Spacing()
        ImGui.Text("Value thresholds (copper)")
        ImGui.Text("Min value (non-stack)")
        ImGui.SameLine(180); ImGui.SetNextItemWidth(120)
        vs = tostring(configLootValues.minLoot)
        vs, _ = ImGui.InputText("Min loot value##LootMin", vs, ImGuiInputTextFlags.CharsDecimal)
        n = tonumber(vs)
        if n and n ~= configLootValues.minLoot then configLootValues.minLoot = math.max(0, math.floor(n)); config.writeLootINIValue("loot_value.ini", "Settings", "minLootValue", tostring(configLootValues.minLoot)) end
        ImGui.SameLine()
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configLootValues.minLoot))
        ImGui.Text("Min value (stack)")
        ImGui.SameLine(180); ImGui.SetNextItemWidth(120)
        vs = tostring(configLootValues.minStack)
        vs, _ = ImGui.InputText("Min stack value##LootStack", vs, ImGuiInputTextFlags.CharsDecimal)
        n = tonumber(vs)
        if n and n ~= configLootValues.minStack then configLootValues.minStack = math.max(0, math.floor(n)); config.writeLootINIValue("loot_value.ini", "Settings", "minLootValueStack", tostring(configLootValues.minStack)) end
        ImGui.SameLine()
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configLootValues.minStack) .. "/unit")
        ImGui.Text("Tribute override (0=off)")
        ImGui.SameLine(180); ImGui.SetNextItemWidth(120)
        vs = tostring(configLootValues.tributeOverride)
        vs, _ = ImGui.InputText("Tribute override##LootTrib", vs, ImGuiInputTextFlags.CharsDecimal)
        n = tonumber(vs)
        if n and n ~= configLootValues.tributeOverride then configLootValues.tributeOverride = math.max(0, math.floor(n)); config.writeLootINIValue("loot_value.ini", "Settings", "tributeOverride", tostring(configLootValues.tributeOverride)) end
        ImGui.SameLine()
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configLootValues.tributeOverride))
        ImGui.Spacing()
        ImGui.Text("Sorting")
        local v = ImGui.Checkbox("Enable sorting", configLootSorting.enableSorting)
        if v ~= configLootSorting.enableSorting then configLootSorting.enableSorting = v; config.writeLootINIValue("loot_sorting.ini", "Settings", "enableSorting", v and "TRUE" or "FALSE") end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Master toggle for loot sorting"); ImGui.EndTooltip() end
        v = ImGui.Checkbox("Enable weight sort", configLootSorting.enableWeightSort)
        if v ~= configLootSorting.enableWeightSort then configLootSorting.enableWeightSort = v; config.writeLootINIValue("loot_sorting.ini", "Settings", "enableWeightSort", v and "TRUE" or "FALSE") end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Sort inventory by weight when looting"); ImGui.EndTooltip() end
        ImGui.SetNextItemWidth(120)
        vs = tostring(configLootSorting.minWeight)
        vs, _ = ImGui.InputText("Weight threshold##LootWt", vs, ImGuiInputTextFlags.CharsDecimal)
        n = tonumber(vs)
        if n and n ~= configLootSorting.minWeight then configLootSorting.minWeight = math.max(0, math.floor(n)); config.writeLootINIValue("loot_sorting.ini", "Settings", "minWeight", tostring(configLootSorting.minWeight)) end
        ImGui.SameLine(); ImGui.Text("Weight threshold (tenths)")
        ImGui.SameLine()
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), string.format("%.1f lbs", (tonumber(configLootSorting.minWeight) or 0) / 10))
    end
    ImGui.Spacing()
    if ImGui.CollapsingHeader("Layout setup", ImGuiTreeNodeFlags.DefaultOpen) then
        renderBreadcrumb("General", "Layout setup")
        local setupWasOn = uiState.setupMode
        if setupWasOn then ImGui.PushStyleColor(ImGuiCol.Button, theme.ToVec4(theme.Colors.Warning)) end
        if ImGui.Button("Initial Setup", ImVec2(120, 0)) then
            uiState.setupMode = not uiState.setupMode
            if uiState.setupMode then
                uiState.setupStep = 0
                if ctx.loadConfigCache then ctx.loadConfigCache() end
                if loadLayoutConfig then loadLayoutConfig() end
            else
                uiState.setupStep = 0
            end
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Save window sizes for Inventory, Sell, and Inv+Bank.")
            ImGui.Text("Follow the on-screen steps to capture positions.")
            ImGui.EndTooltip()
        end
        if setupWasOn then ImGui.PopStyleColor(1) end
        ImGui.SameLine()
        if ImGui.Button("Show welcome panel again", ImVec2(180, 0)) then
            if ctx.resetOnboarding then ctx.resetOnboarding() end
            registry.setWindowState("config", false, false)
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Re-display the first-run welcome panel in the main window.")
            ImGui.Text("Useful for testing or to see the default flow again.")
            ImGui.EndTooltip()
        end
    end
end

return ConfigGeneral
