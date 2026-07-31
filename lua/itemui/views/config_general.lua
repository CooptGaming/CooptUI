--[[
    Config General tab - Features, Sell options, Loot options, Layout setup.
    Part of ItemUI config view split (Task 07).
--]]

local mq = require('mq')
require('ImGui')

local ConfigFilters = require('itemui.views.config_filters')
local events = require('itemui.core.events')

local KEYBIND_DEBOUNCE_MS = 800
local registry = require('itemui.core.registry')
local skinSync = require('itemui.services.skin_sync')

-- Cached "is the skin installed in the EQ client?" - file probes are not free,
-- so recheck at most every 5s (and immediately after an install click).
local skinInstalledCache = { at = 0, value = false }
local function skinInstalled()
    local now = mq.gettime()
    if (now - skinInstalledCache.at) > 5000 then
        skinInstalledCache.at = now
        skinInstalledCache.value = skinSync.isInstalled()
    end
    return skinInstalledCache.value
end

local ConfigGeneral = {}

-- Debounced numeric InputText (same idea as the keybind debounce below): the in-progress
-- text is held per field and the parsed number is returned once, after ~500ms idle or when
-- the field loses focus after an edit — so typing "500" doesn't apply 5, then 50, then 500
-- (three INI writes + cache invalidations). Returns nil while no value is ready to apply.
local VALUE_DEBOUNCE_MS = 500
local numericFieldPending = {}  -- [inputId] = { text = in-progress text, at = ms of last edit }

local function debouncedNumericInput(id, currentValue)
    local pend = numericFieldPending[id]
    local buf = pend and pend.text or tostring(currentValue)
    local txt, changed = ImGui.InputText(id, buf, ImGuiInputTextFlags.CharsDecimal)
    if changed then
        pend = { text = txt, at = mq.gettime() }
        numericFieldPending[id] = pend
    end
    local deactivated = ImGui.IsItemDeactivatedAfterEdit and ImGui.IsItemDeactivatedAfterEdit()
    if pend and (deactivated or (mq.gettime() - pend.at) >= VALUE_DEBOUNCE_MS) then
        numericFieldPending[id] = nil
        return tonumber(pend.text)
    end
    return nil
end

function ConfigGeneral.render(ctx)
    local uiState = ctx.uiState
    local filterState = ctx.filterState
    local layoutConfig = ctx.layoutConfig
    local config = ctx.config
    local theme = ctx.theme
    local scheduleLayoutSave = ctx.scheduleLayoutSave
    -- Dock keys go through this rather than a bare scheduleLayoutSave: during the 600ms save
    -- debounce loadLayoutConfig still serves the CACHED parse, which would re-apply the old
    -- value over the change and then persist the revert. See LayoutUtils.setLayoutValue.
    local setLayoutValue = ctx.setLayoutValue or function(k, v)
        layoutConfig[k] = v
        if scheduleLayoutSave then scheduleLayoutSave() end
    end
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
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Turn features on or off. Most are enabled by default (Loot/Skip History start off).")
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
        local prevNativeStrip = (uiState.nativeMerchantStrip ~= false)
        local nativeStrip = ImGui.Checkbox("Native window strips (CoOpt skin)", prevNativeStrip)
        if prevNativeStrip ~= nativeStrip then
            uiState.nativeMerchantStrip = nativeStrip
            scheduleLayoutSave()
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Drives the CoOpt controls inside the game's own windows: Merchant (Auto Sell, Preview, status),")
            ImGui.Text("the Actions window's CoOpt launcher tab, and the native Command Center.")
            ImGui.Text("Requires the CoOpt UI skin: /loadskin coopt. Does nothing if the skin isn't loaded.")
            ImGui.EndTooltip()
        end
        -- The skin itself is OPTIONAL: it ships under the MacroQuest folder but is
        -- only copied into the EQ client on explicit request (or kept fresh once there).
        ImGui.SameLine()
        if skinInstalled() then
            theme.TextMuted("(skin installed - kept up to date)")
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("The CoOpt skin is in your EverQuest uifiles folder and updates automatically with CoOpt UI.")
                ImGui.Text("To remove it: /loadskin default, then delete the uifiles\\coopt folder in your EQ directory.")
                ImGui.EndTooltip()
            end
        else
            if ImGui.Button("Install skin (optional)") then
                local res = skinSync.sync({ force = true })
                skinInstalledCache.at = 0
                if res and #res.copied > 0 then
                    if ctx.setStatusMessage then ctx.setStatusMessage("CoOpt skin installed. Use /loadskin coopt to enable it.") end
                else
                    if ctx.setStatusMessage then ctx.setStatusMessage("Skin install failed - check that MQ and EQ paths are available.") end
                end
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Copies the CoOpt skin into your EverQuest uifiles folder (optional - native strips need it).")
                ImGui.Text("Nothing is written to your EQ client unless you click this. Load with /loadskin coopt,")
                ImGui.Text("go back with /loadskin default. Once installed it stays current with CoOpt UI updates.")
                ImGui.EndTooltip()
            end
        end
        local prevNativeHover = (uiState.nativeHoverTooltip ~= false)
        local nativeHover = ImGui.Checkbox("Native inventory hover tooltips", prevNativeHover)
        if prevNativeHover ~= nativeHover then
            uiState.nativeHoverTooltip = nativeHover
            scheduleLayoutSave()
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Hovering a worn equipment slot in the game's own Inventory window shows the full CoOpt stats tooltip.")
            ImGui.EndTooltip()
        end
        local prevIdReplace = (uiState.nativeItemDisplayReplace ~= false)
        local idReplace = ImGui.Checkbox("Equipped inspect opens CoOpt Item Display", prevIdReplace)
        if prevIdReplace ~= idReplace then
            uiState.nativeItemDisplayReplace = idReplace
            scheduleLayoutSave()
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Right-clicking a worn equipment slot in the game's own Inventory window opens the CoOpt Item Display")
            ImGui.Text("(the native inspect garbles on this server) and closes the native window that pops.")
            ImGui.Text("Bag items are covered by the CoOpt Inventory Companion as usual.")
            ImGui.EndTooltip()
        end
        local prevLootHist = (uiState.enableLootHistory == true)
        local lootHist = ImGui.Checkbox("Enable Loot History tab", prevLootHist)
        if prevLootHist ~= lootHist then
            uiState.enableLootHistory = lootHist
            scheduleLayoutSave()
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("When on, the Loot History tab is shown and cumulative loot is recorded. When off, the tab is hidden and no loot history is kept.")
            ImGui.EndTooltip()
        end
        local prevSkipHist = (uiState.enableSkipHistory == true)
        local skipHist = ImGui.Checkbox("Enable Skip History tab", prevSkipHist)
        if prevSkipHist ~= skipHist then
            uiState.enableSkipHistory = skipHist
            scheduleLayoutSave()
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("When on, the Skip History tab is shown and skipped items are recorded. When off, the tab is hidden and no skip history is kept.")
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
        local guardEnabled = (layoutConfig.ActivationGuardEnabled == nil or layoutConfig.ActivationGuardEnabled)
        local prevGuard = guardEnabled
        guardEnabled = ImGui.Checkbox("Enable click-through protection", guardEnabled)
        if prevGuard ~= guardEnabled then
            layoutConfig.ActivationGuardEnabled = guardEnabled
            scheduleLayoutSave()
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("When enabled, an item on cursor that was not picked up from ItemUI (e.g. accidental game-window click) is auto-put in bags.")
            ImGui.Text("Uncheck to allow items on cursor from any source without auto-bagging.")
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
            -- Settings contract leg 3: without the events, attached willSell/
            -- sellReason on visible rows keeps advertising the OLD ruling until
            -- an unrelated rescan.
            events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
            events.emit(events.EVENTS.CONFIG_LOOT_CHANGED)
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
            local preview = (nSelected == 0) and "None selected (epic rules inactive)" or (nSelected == #EPIC_CLASSES) and "All classes" or string.format("%d class%s", nSelected, nSelected == 1 and "" or "es")
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
                    events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
                    events.emit(events.EVENTS.CONFIG_LOOT_CHANGED)
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
                    events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
                    events.emit(events.EVENTS.CONFIG_LOOT_CHANGED)
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
                        events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
                        events.emit(events.EVENTS.CONFIG_LOOT_CHANGED)
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
    if ImGui.CollapsingHeader("Dock", ImGuiTreeNodeFlags.None) then
        renderBreadcrumb("General", "Dock")
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted),
            "Two thin bars instead of the hub's button row: status on one edge, launchers and chat on the other.")
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.TextWrapped("Classic keeps today's UI exactly as it is. Bars adds the strips; " ..
                "turning both strips off inside Bars mode behaves the same as Classic.")
            ImGui.EndTooltip()
        end

        local barsOn = tostring(layoutConfig.UIMode or "classic") == "bars"
        local nextBarsOn = ImGui.Checkbox("Use the bars UI##dockUIMode", barsOn)
        if nextBarsOn ~= barsOn then
            setLayoutValue("UIMode", nextBarsOn and "bars" or "classic")
            -- Re-evaluate eligibility so classicOnly companions (Command Center) close on
            -- entering bars mode and come back when leaving it — same call the loader makes.
            registry.applyEnabledFromLayout(layoutConfig)
        end

        if nextBarsOn then
            ImGui.Indent()

            local topOn = layoutConfig.DockTop ~= false
            local nextTop = ImGui.Checkbox("Status bar##dockTop", topOn)
            if nextTop ~= topOn then
                setLayoutValue("DockTop", nextTop)
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Plugin state, bags, what a sale would fetch, live loot or sell progress,")
                ImGui.Text("buffs, XP/AA and the session total. Read-only - hover a slot for detail.")
                ImGui.EndTooltip()
            end

            local bottomOn = layoutConfig.DockBottom ~= false
            local nextBottom = ImGui.Checkbox("Command bar##dockBottom", bottomOn)
            if nextBottom ~= bottomOn then
                setLayoutValue("DockBottom", nextBottom)
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Window launchers, native game windows, layout presets, Settings and chat.")
                ImGui.EndTooltip()
            end

            -- Which edge the status bar takes; the command bar takes the other one.
            local atBottom = tostring(layoutConfig.DockPosition or "top") == "bottom"
            ImGui.Text("Status bar edge:")
            ImGui.SameLine()
            if ImGui.RadioButton("Top##dockPosTop", not atBottom) then
                if atBottom then setLayoutValue("DockPosition", "top") end
            end
            ImGui.SameLine()
            if ImGui.RadioButton("Bottom##dockPosBottom", atBottom) then
                if not atBottom then setLayoutValue("DockPosition", "bottom") end
            end

            -- "peek" is retired: the four-line strip became the chat WINDOW (click the
            -- chat line on the bar). A stored peek value reads as collapsed everywhere.
            local chatModes = { "hidden", "collapsed" }
            local chatLabels = { "Hidden", "One line" }
            local cur = tostring(layoutConfig.DockChat or "collapsed")
            if cur == "peek" then cur = "collapsed" end
            ImGui.Text("Chat in the command bar (click the line to open the chat window):")
            for i, mode in ipairs(chatModes) do
                ImGui.SameLine()
                if ImGui.RadioButton(chatLabels[i] .. "##dockChat" .. mode, cur == mode) then
                    if cur ~= mode then setLayoutValue("DockChat", mode) end
                end
            end

            ImGui.Spacing()
            local zepOn = (tonumber(layoutConfig.ChatUseZep) or 0) ~= 0
            local nextZep = ImGui.Checkbox("Rich chat console (clickable item links)##chatUseZep", zepOn)
            if nextZep ~= zepOn then
                setLayoutValue("ChatUseZep", nextZep and 1 or 0)
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("On: clickable item links in chat, and real scrollback.")
                ImGui.Text("Off: the built-in renderer - every line still shows, but links")
                ImGui.Text("are plain text.")
                ImGui.Text("")
                ImGui.Text("Turning it ON takes effect the next time the UI starts")
                ImGui.Text("(/itemui quit then /lua run itemui, or a relog). Turning it OFF")
                ImGui.Text("applies right away.")
                ImGui.EndTooltip()
            end

            -- Segment MEMBERSHIP only (phase 13, 26a): the bar is a fixed grid — the order
            -- is the design's and nothing moves between states or between users, so the
            -- old reorder arrows are gone. A disabled cell's width goes to the action
            -- lane. The lane and the Loot All / Auto Sell pair are not segments (26a:
            -- "Buttons are not segments") and cannot be turned off — they are the bar's
            -- job surface and the mythical decision strip rides the lane.
            ImGui.Spacing()
            ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Status bar cells (order is fixed; unchecked width goes to the action lane):")
            local ALL_SEGMENTS = {
                { id = "status",  label = "CoOpt identity & status" },
                { id = "session", label = "Session strip" },
                { id = "bags",    label = "Bags & weight" },
                { id = "sell",    label = "Sell offer" },
                { id = "buffs",   label = "Buffs / songs / aura" },
                { id = "xp",      label = "XP / AA" },
            }
            local enabled = {}
            local hadCsv = false
            -- "none" is the all-off sentinel: layout_io treats an EMPTY value as "key absent"
            -- and restores the default list on the next reload, so a genuinely empty bar has
            -- to be spelled. Unknown ids (incl. the retired "loot") are dropped on the next
            -- write — the lane replaced that segment and cannot be disabled.
            for part in tostring(layoutConfig.DockSegments or ""):gmatch("[^,]+") do
                local t = part:match("^%s*(.-)%s*$")
                if t ~= "" then
                    hadCsv = true
                    if t ~= "none" then enabled[t] = true end
                end
            end
            if not hadCsv then
                for _, seg in ipairs(ALL_SEGMENTS) do enabled[seg.id] = true end
            end
            local changed = false
            for _, seg in ipairs(ALL_SEGMENTS) do
                local on = enabled[seg.id] == true
                local v = ImGui.Checkbox(seg.label .. "##dockSeg" .. seg.id, on)
                if v ~= on then
                    enabled[seg.id] = v or nil
                    changed = true
                end
            end
            if changed then
                -- Canonical order on the way out — the CSV is a SET, but writing it in
                -- bar order keeps hand reads sane.
                local out = {}
                for _, seg in ipairs(ALL_SEGMENTS) do
                    if enabled[seg.id] then out[#out + 1] = seg.id end
                end
                setLayoutValue("DockSegments", (#out > 0) and table.concat(out, ",") or "none")
            end

            -- Command bar style (mockup's second option): hover menus (today's bar) or a flat
            -- row of launcher buttons. DockButtons only matters once "buttons" is picked.
            ImGui.Spacing()
            local barStyle = tostring(layoutConfig.DockBottomStyle or "menus")
            ImGui.Text("Command bar style:")
            ImGui.SameLine()
            if ImGui.RadioButton("Hover menus##dockBottomStyleMenus", barStyle ~= "buttons") then
                if barStyle ~= "menus" then setLayoutValue("DockBottomStyle", "menus") end
            end
            ImGui.SameLine()
            if ImGui.RadioButton("Launcher buttons##dockBottomStyleButtons", barStyle == "buttons") then
                if barStyle ~= "buttons" then setLayoutValue("DockBottomStyle", "buttons") end
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Hover menus: four grouped menus (Items / Character / Actions / Game windows).")
                ImGui.Text("Launcher buttons: one button per window, in the order below.")
                ImGui.EndTooltip()
            end

            if barStyle == "buttons" then
                -- Same list-with-arrows shape as the status bar slots above, copied verbatim:
                -- enabled rows in CSV (bar) order with ^/v + checkbox, disabled registry
                -- modules below re-enable at the end (canonical-relative insert).
                ImGui.Spacing()
                ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Command bar buttons (left to right):")
                local ALL_BUTTONS = {
                    { id = "bags",           label = "Bags" },
                    { id = "bank",           label = "Bank" },
                    { id = "equipment",      label = "Equipment" },
                    { id = "augments",       label = "Augments" },
                    { id = "augmentUtility", label = "Augment Utility" },
                    { id = "mythicals",      label = "Mythicals" },
                    { id = "reroll",         label = "Reroll" },
                    { id = "aa",             label = "AA" },
                    { id = "effects",        label = "Effects" },
                }
                local benabled, border = {}, {}
                for part in tostring(layoutConfig.DockButtons or ""):gmatch("[^,]+") do
                    local t = part:match("^%s*(.-)%s*$")
                    if t ~= "" and t ~= "none" then benabled[t] = true; border[#border + 1] = t end
                end
                local bcanonPos, bbyId = {}, {}
                for ci, cseg in ipairs(ALL_BUTTONS) do bcanonPos[cseg.id] = ci; bbyId[cseg.id] = cseg end
                local bchanged = false
                local bact = nil     -- one click per frame: { kind = "up"|"down"|"off", i = index }
                for i, id in ipairs(border) do
                    local seg = bbyId[id]
                    if seg then
                        if ImGui.SmallButton("^##dockBtnUp" .. id) then bact = { kind = "up", i = i } end
                        ImGui.SameLine(0, 2)
                        if ImGui.SmallButton("v##dockBtnDown" .. id) then bact = { kind = "down", i = i } end
                        ImGui.SameLine(0, 8)
                        if not ImGui.Checkbox(seg.label .. "##dockBtn" .. id, true) then
                            bact = { kind = "off", i = i }
                        end
                    end
                end
                if bact then
                    local id = border[bact.i]
                    if bact.kind == "off" then
                        table.remove(border, bact.i); benabled[id] = nil; bchanged = true
                    elseif bact.kind == "up" and bact.i > 1 then
                        table.remove(border, bact.i); table.insert(border, bact.i - 1, id); bchanged = true
                    elseif bact.kind == "down" and bact.i < #border then
                        table.remove(border, bact.i); table.insert(border, bact.i + 1, id); bchanged = true
                    end
                end
                for _, seg in ipairs(ALL_BUTTONS) do
                    if not benabled[seg.id] then
                        if ImGui.Checkbox(seg.label .. "##dockBtn" .. seg.id, false) then
                            bchanged = true
                            benabled[seg.id] = true
                            local at = #border + 1
                            for i, oid in ipairs(border) do
                                if (bcanonPos[oid] or math.huge) > bcanonPos[seg.id] then at = i; break end
                            end
                            table.insert(border, at, seg.id)
                        end
                    end
                end
                if bchanged then
                    setLayoutValue("DockButtons", (#border > 0) and table.concat(border, ",") or "none")
                end
            end

            ImGui.Unindent()
        end
    end
    ImGui.Spacing()
    if ImGui.CollapsingHeader("Layouts") then
        renderBreadcrumb("General", "Layouts")
        -- Mockup 10c. A preset is "which windows are open, in which zone, at what size";
        -- switching closes what is not in it (pinned windows stay). Everything here goes
        -- through the dock action queue: apply/save/delete touch files and window state,
        -- which is main-loop work, not frame work.
        local function queueDock(action)
            local q = uiState.dockActionQueue
            if not q then q = {}; uiState.dockActionQueue = q end
            q[#q + 1] = action
        end
        local names = uiState.dockPresetNames or {}
        local active = tostring(layoutConfig.LayoutPreset or "")
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted),
            "A layout preset is which windows are open, in which zone, at what size. Switching closes what isn't in it.")
        ImGui.Spacing()
        if #names == 0 then
            theme.TextMuted("No presets yet - the five bundled ones appear after the first bars session.")
        end
        for _, name in ipairs(names) do
            local lit = (name == active)
            if lit then
                theme.TextSuccess(name)
            else
                ImGui.Text(name)
            end
            ImGui.SameLine(220)
            if ImGui.SmallButton((lit and "Re-apply" or "Use") .. "##presetUse_" .. name) then
                queueDock({ kind = "preset", name = name })
            end
            ImGui.SameLine(0, 6)
            if ImGui.SmallButton("Delete##presetDel_" .. name) then
                queueDock({ kind = "preset_delete", name = name })
            end
        end
        ImGui.Spacing()
        ImGui.Text("Save current as")
        ImGui.SameLine(140)
        ImGui.SetNextItemWidth(160)
        -- Two args: the third InputText parameter is FLAGS in this binding, not a size.
        local buf, changed = ImGui.InputText("##presetSaveName", tostring(uiState.dockPresetSaveName or ""))
        if changed then uiState.dockPresetSaveName = buf end
        ImGui.SameLine(0, 6)
        local newName = tostring(uiState.dockPresetSaveName or ""):match("^%s*(.-)%s*$")
        if newName ~= "" and not newName:find("[%[%]:]") then
            if ImGui.SmallButton("Save##presetSaveGo") then
                queueDock({ kind = "preset_save", name = newName })
                uiState.dockPresetSaveName = nil
            end
        else
            theme.TextMuted("Save")
        end
        ImGui.Spacing()
        if ImGui.SmallButton("Re-tidy now##presetRetidy") then
            queueDock({ kind = "retidy" })
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Puts every open window back into its zone and forgets hand-placed positions.")
            ImGui.EndTooltip()
        end
        ImGui.SameLine(0, 10)
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted),
            "Presets live in itemui_presets.ini - Revert to Default Layout never touches them.")
    end
    ImGui.Spacing()
    if ImGui.CollapsingHeader("Keybindings", ImGuiTreeNodeFlags.DefaultOpen) then
        renderBreadcrumb("General", "Keybindings")
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Assign a key to toggle the ItemUI (Inventory Companion) open/closed. Uses /custombind + /bind.")
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Press the key to open ItemUI; press again to close.")
            ImGui.Text("Format: shift+i, ctrl+f2, f12. I and Shift+C are often reserved by EQ.")
            ImGui.Text("Requires MQ2CustomBinds plugin: /plugin MQ2CustomBinds")
            ImGui.EndTooltip()
        end
        ImGui.Spacing()
        ImGui.Text("ItemUI Toggle")
        ImGui.SameLine(140)
        ImGui.SetNextItemWidth(120)
        local keyVal = tostring(layoutConfig.ItemUIToggleKey or "")
        local keyBuf = keyVal
        keyBuf, _ = ImGui.InputText("##ItemUIToggleKey", keyBuf or "", ImGuiInputTextFlags.None)
        if keyBuf ~= keyVal then
            local raw = (keyBuf and keyBuf:match("^%s*(.-)%s*$") or "")
            layoutConfig.ItemUIToggleKey = raw
            scheduleLayoutSave()
            filterState.keybindDebounceAt = mq.gettime()
        end
        -- Debounce: apply bind only after user stops typing (avoids errors on each keystroke)
        if filterState.keybindDebounceAt and (mq.gettime() - filterState.keybindDebounceAt) >= KEYBIND_DEBOUNCE_MS then
            filterState.keybindDebounceAt = nil
            if ctx.applyItemUIToggleBind then
                ctx.applyItemUIToggleBind()
                local key = ctx.getItemUIToggleKeyDisplay and ctx.getItemUIToggleKeyDisplay()
                if key and key ~= "" then
                    print(string.format("\ag[ItemUI]\ax Toggle key set to: %s", key))
                else
                    print("\ag[ItemUI]\ax Toggle key cleared.")
                end
            end
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Key or key combo. Use + for modifiers: shift+c, ctrl+i, alt+f2.")
            ImGui.Text("Bind applies 0.8s after you stop typing. I and Shift+C may be reserved by EQ.")
            ImGui.EndTooltip()
        end
        ImGui.SameLine()
        if ImGui.Button("Apply##ItemUIToggleKey", ImVec2(50, 0)) then
            filterState.keybindDebounceAt = nil
            if ctx.applyItemUIToggleBind then
                ctx.applyItemUIToggleBind()
                local key = ctx.getItemUIToggleKeyDisplay and ctx.getItemUIToggleKeyDisplay()
                if key and key ~= "" then
                    print(string.format("\ag[ItemUI]\ax Toggle key set to: %s", key))
                else
                    print("\ag[ItemUI]\ax Toggle key cleared.")
                end
            end
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Apply the keybind now (or wait 0.8s after typing).")
            ImGui.EndTooltip()
        end
        ImGui.SameLine()
        if ImGui.Button("Clear##ItemUIToggleKey", ImVec2(60, 0)) then
            layoutConfig.ItemUIToggleKey = ""
            scheduleLayoutSave()
            filterState.keybindDebounceAt = nil
            if ctx.applyItemUIToggleBind then
                ctx.applyItemUIToggleBind()
                print("\ag[ItemUI]\ax Toggle key cleared.")
            end
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Remove the keybind.")
            ImGui.EndTooltip()
        end
    end
    ImGui.Spacing()
    if ImGui.CollapsingHeader("Sell", ImGuiTreeNodeFlags.DefaultOpen) then
        renderBreadcrumb("General", "Sell")
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Options for what is never sold. Item lists are on the Sell Rules tab.")
        ImGui.Spacing()
        local function sellFlag(name, key, tooltip)
            local v = ImGui.Checkbox(name, configSellFlags[key])
            if v ~= configSellFlags[key] then configSellFlags[key] = v; config.writeINIValue("sell_flags.ini", "Settings", key, v and "TRUE" or "FALSE"); invalidateSellConfigCache(); events.emit(events.EVENTS.CONFIG_SELL_CHANGED) end
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(tooltip); ImGui.EndTooltip() end
        end
        sellFlag("Enable No-Drop protection", "protectNoDrop", "Never sell items with the No-Drop flag")
        sellFlag("Enable No-Trade protection", "protectNoTrade", "Never sell items with the No-Trade flag")
        sellFlag("Enable Lore protection", "protectLore", "Never sell items with the Lore flag")
        sellFlag("Enable Quest protection", "protectQuest", "Never sell items with the Quest flag")
        sellFlag("Enable Collectible protection", "protectCollectible", "Never sell items with the Collectible flag")
        sellFlag("Enable Heirloom protection", "protectHeirloom", "Never sell items with the Heirloom flag")
        ImGui.Spacing()
        ImGui.Text("Value thresholds (copper)")
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("1 platinum = 1000 copper"); ImGui.EndTooltip() end
        ImGui.Text("Min value (single)")
        ImGui.SameLine(180); ImGui.SetNextItemWidth(120)
        local n = debouncedNumericInput("Min value (single)##SellMin", configSellValues.minSell)
        if n and n ~= configSellValues.minSell then
            configSellValues.minSell = math.max(0, math.floor(n))
            config.writeINIValue("sell_value.ini", "Settings", "minSellValue", tostring(configSellValues.minSell))
            invalidateSellConfigCache()
            events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
        end
        ImGui.SameLine()
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configSellValues.minSell))
        ImGui.Text("Min value (stack)")
        ImGui.SameLine(180); ImGui.SetNextItemWidth(120)
        n = debouncedNumericInput("Min value (stack)##SellStack", configSellValues.minStack)
        if n and n ~= configSellValues.minStack then
            configSellValues.minStack = math.max(0, math.floor(n))
            config.writeINIValue("sell_value.ini", "Settings", "minSellValueStack", tostring(configSellValues.minStack))
            invalidateSellConfigCache()
            events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
        end
        ImGui.SameLine()
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configSellValues.minStack) .. "/unit")
        ImGui.Text("Max keep value")
        ImGui.SameLine(180); ImGui.SetNextItemWidth(120)
        n = debouncedNumericInput("Max keep value##SellKeep", configSellValues.maxKeep)
        if n and n ~= configSellValues.maxKeep then
            configSellValues.maxKeep = math.max(0, math.floor(n))
            config.writeINIValue("sell_value.ini", "Settings", "maxKeepValue", tostring(configSellValues.maxKeep))
            invalidateSellConfigCache()
            events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
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
            if v ~= configLootFlags[key] then configLootFlags[key] = v; config.writeLootINIValue("loot_flags.ini", "Settings", key, v and "TRUE" or "FALSE"); invalidateLootConfigCache(); events.emit(events.EVENTS.CONFIG_LOOT_CHANGED) end
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
        -- Live loot feed is always enabled (toggle removed — feature is non-optional).
        -- Persist it to the INI too: loot.mac's no-plugin fallback reads the INI
        -- (defaults FALSE there), and without this write macro-path users never
        -- got live loot rows.
        if not configLootFlags.enableLiveLootFeed then
            configLootFlags.enableLiveLootFeed = true
            config.writeLootINIValue("loot_flags.ini", "Settings", "enableLiveLootFeed", "TRUE")
        end
        uiState.enableRealTimeLoot = true
        -- Loot console verbosity: controlled via Settings > Advanced > Debug channels > "Debug: Loot"
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
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Ticks to wait after itemnotify/cursor/window. 2 = default (fast), 3 = safe on slower systems, 4+ if laggy."); ImGui.EndTooltip() end
        ImGui.SameLine()
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), tostring(configLootFlags.lootDelayTicks or 3))
        ImGui.Spacing()
        ImGui.Text("Value thresholds (copper)")
        local n  -- declared once; the value-threshold input fields below reuse it (was an accidental global)
        ImGui.Text("Min value (non-stack)")
        ImGui.SameLine(180); ImGui.SetNextItemWidth(120)
        n = debouncedNumericInput("Min loot value##LootMin", configLootValues.minLoot)
        if n and n ~= configLootValues.minLoot then
            configLootValues.minLoot = math.max(0, math.floor(n))
            config.writeLootINIValue("loot_value.ini", "Settings", "minLootValue", tostring(configLootValues.minLoot))
            invalidateLootConfigCache()
            events.emit(events.EVENTS.CONFIG_LOOT_CHANGED)
        end
        ImGui.SameLine()
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configLootValues.minLoot))
        ImGui.Text("Min value (stack)")
        ImGui.SameLine(180); ImGui.SetNextItemWidth(120)
        n = debouncedNumericInput("Min stack value##LootStack", configLootValues.minStack)
        if n and n ~= configLootValues.minStack then
            configLootValues.minStack = math.max(0, math.floor(n))
            config.writeLootINIValue("loot_value.ini", "Settings", "minLootValueStack", tostring(configLootValues.minStack))
            invalidateLootConfigCache()
            events.emit(events.EVENTS.CONFIG_LOOT_CHANGED)
        end
        ImGui.SameLine()
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), formatCurrency(configLootValues.minStack) .. "/unit")
        ImGui.Text("Tribute override (0=off)")
        ImGui.SameLine(180); ImGui.SetNextItemWidth(120)
        n = debouncedNumericInput("Tribute override##LootTrib", configLootValues.tributeOverride)
        if n and n ~= configLootValues.tributeOverride then
            configLootValues.tributeOverride = math.max(0, math.floor(n))
            config.writeLootINIValue("loot_value.ini", "Settings", "tributeOverride", tostring(configLootValues.tributeOverride))
            invalidateLootConfigCache()
            events.emit(events.EVENTS.CONFIG_LOOT_CHANGED)
        end
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
        n = debouncedNumericInput("Weight threshold##LootWt", configLootSorting.minWeight)
        if n and n ~= configLootSorting.minWeight then configLootSorting.minWeight = math.max(0, math.floor(n)); config.writeLootINIValue("loot_sorting.ini", "Settings", "minWeight", tostring(configLootSorting.minWeight)) end
        ImGui.SameLine(); ImGui.Text("Weight threshold (tenths)")
        ImGui.SameLine()
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), string.format("%.1f lbs", (tonumber(configLootSorting.minWeight) or 0) / 10))
    end
end

return ConfigGeneral
