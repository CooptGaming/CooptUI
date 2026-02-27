--[[
    Main window: hub (Inventory Companion) + header, setup wizard, content area,
    quantity picker, cursor bar, footer, and companion window rendering.
    render(refs) — refs supplied by init.lua (state, callbacks, layout, view modules).
]]

local mq = require('mq')
require('ImGui')
local context = require('itemui.context')
local constants = require('itemui.constants')
local InventoryView = require('itemui.views.inventory')
local SellView = require('itemui.views.sell')
local BankView = require('itemui.views.bank')
local EquipmentView = require('itemui.views.equipment')
local AugmentsView = require('itemui.views.augments')
local AugmentUtilityView = require('itemui.views.augment_utility')
local ItemDisplayView = require('itemui.views.item_display')
local AAView = require('itemui.views.aa')
local LootUIView = require('itemui.views.loot_ui')
local LootView = require('itemui.views.loot')
local ConfigView = require('itemui.views.settings')
local RerollView = require('itemui.views.reroll')
local aa_data = require('itemui.services.aa_data')
local registry = require('itemui.core.registry')
local diagnostics = require('itemui.core.diagnostics')
local tutorial = require('itemui.views.tutorial')

local function buildViewContext()
    return context.build()
end

local function extendContext(ctx)
    return context.extend(ctx)
end

local function renderSetupStep0Content(refs)
    local theme = refs.theme
    local uiState = refs.uiState
    local configEpicClasses = refs.configEpicClasses or {}
    local EPIC_CLASSES = refs.EPIC_CLASSES or {}
    local config = refs.config
    local invalidateSellConfigCache = refs.invalidateSellConfigCache or function() end
    local invalidateLootConfigCache = refs.invalidateLootConfigCache or function() end
    local classLabel = refs.classLabel or function(c) return tostring(c) end
    ImGui.TextColored(theme.ToVec4(theme.Colors.Header), "Epic quest item protection")
    ImGui.Separator()
    ImGui.TextWrapped("Optionally choose which classes' epic quest items are protected from selling and always looted. You can skip or select your class(es).")
    ImGui.Spacing()
    ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Epic items for selected classes will never be sold and will always be looted.")
    ImGui.Spacing()
    if EPIC_CLASSES and #EPIC_CLASSES > 0 then
        ImGui.Text("Classes:")
        local nSelected = 0
        for _, cls in ipairs(EPIC_CLASSES) do
            if configEpicClasses[cls] == true then nSelected = nSelected + 1 end
        end
        ImGui.SameLine()
        if ImGui.SmallButton("Select all##setup_epic") then
            for _, cls in ipairs(EPIC_CLASSES) do
                configEpicClasses[cls] = true
                if config and config.writeSharedINIValue then config.writeSharedINIValue("epic_classes.ini", "Classes", cls, "TRUE") end
            end
            invalidateSellConfigCache()
            invalidateLootConfigCache()
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Check all classes"); ImGui.EndTooltip() end
        ImGui.SameLine()
        if ImGui.SmallButton("Clear all##setup_epic") then
            for _, cls in ipairs(EPIC_CLASSES) do
                configEpicClasses[cls] = false
                if config and config.writeSharedINIValue then config.writeSharedINIValue("epic_classes.ini", "Classes", cls, "FALSE") end
            end
            invalidateSellConfigCache()
            invalidateLootConfigCache()
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Uncheck all"); ImGui.EndTooltip() end
        ImGui.Spacing()
        for _, cls in ipairs(EPIC_CLASSES) do
            local v = ImGui.Checkbox(classLabel(cls) .. "##setup_epic_" .. cls, configEpicClasses[cls] == true)
            if v ~= (configEpicClasses[cls] == true) then
                configEpicClasses[cls] = v
                if config and config.writeSharedINIValue then config.writeSharedINIValue("epic_classes.ini", "Classes", cls, v and "TRUE" or "FALSE") end
                invalidateSellConfigCache()
                invalidateLootConfigCache()
            end
        end
    end
end

local function renderInventoryContent(refs)
    local ctx = extendContext(buildViewContext())
    local merchOpen = refs.isMerchantWindowOpen and refs.isMerchantWindowOpen()
    local bankOpen = refs.isBankWindowOpen and refs.isBankWindowOpen()
    local lootOpen = refs.isLootWindowOpen and refs.isLootWindowOpen()
    local uiState = refs.uiState
    local simulateSellView = (uiState.setupMode and (uiState.setupStep == 3 or uiState.setupStep == 4))
    if false then
        LootView.render(ctx)
        return
    end
    if merchOpen or simulateSellView then
        SellView.render(ctx, simulateSellView)
    else
        InventoryView.render(ctx, bankOpen)
    end
end

local function renderBankWindow(refs)
    local ctx = extendContext(buildViewContext())
    BankView.render(ctx)
end

local function renderEquipmentWindow(refs)
    local ctx = extendContext(buildViewContext())
    EquipmentView.render(ctx)
end

local function renderAugmentsWindow(refs)
    local ctx = extendContext(buildViewContext())
    AugmentsView.render(ctx)
end

local function renderItemDisplayWindow(refs)
    local ctx = extendContext(buildViewContext())
    ItemDisplayView.render(ctx)
end

local function renderAugmentUtilityWindow(refs)
    local ctx = extendContext(buildViewContext())
    AugmentUtilityView.render(ctx)
end

local function renderAAWindow(refs)
    local ctx = buildViewContext()
    ctx.refreshAA = function() aa_data.refresh() end
    ctx.getAAList = function() return aa_data.getList() end
    ctx.getAAPointsSummary = function() return aa_data.getPointsSummary() end
    ctx.shouldRefreshAA = function() return aa_data.shouldRefresh() end
    ctx.getAALastRefreshTime = function() return aa_data.getLastRefreshTime() end
    AAView.render(ctx)
end

local function renderLootWindow(refs)
    local ctx = extendContext(buildViewContext())
    local uiState = refs.uiState
    local config = refs.config
    ctx.runLootCurrent = function()
        if not uiState.suppressWhenLootMac then
            uiState.lootUIOpen = true
            uiState.lootRunFinished = false
            refs.recordCompanionWindowOpened("loot")
        end
        mq.cmd('/macro loot current')
    end
    ctx.runLootAll = function()
        if not uiState.suppressWhenLootMac then
            uiState.lootUIOpen = true
            uiState.lootRunFinished = false
            refs.recordCompanionWindowOpened("loot")
        end
        mq.cmd('/macro loot')
    end
    ctx.clearLootUIMythicalAlert = function()
        uiState.lootMythicalAlert = nil
        uiState.lootMythicalDecisionStartAt = nil
        uiState.lootMythicalFeedback = nil
        local path = config.getLootConfigFile and config.getLootConfigFile("loot_mythical_alert.ini")
        if path and path ~= "" then
            mq.cmdf('/ini "%s" Alert decision "skip"', path)
            mq.cmdf('/ini "%s" Alert itemName ""', path)
            mq.cmdf('/ini "%s" Alert corpseName ""', path)
            mq.cmdf('/ini "%s" Alert itemLink ""', path)
        end
    end
    ctx.setMythicalDecision = function(decision)
        if decision ~= "loot" and decision ~= "skip" then return end
        local path = config.getLootConfigFile and config.getLootConfigFile("loot_mythical_alert.ini")
        if path and path ~= "" then
            mq.cmdf('/ini "%s" Alert decision "%s"', path, decision)
        end
    end
    ctx.mythicalTake = function()
        local alert = uiState.lootMythicalAlert
        if not alert then return end
        local name = alert.itemName or ""
        local link = (alert.itemLink and alert.itemLink ~= "") and alert.itemLink or nil
        local grouped = mq.TLO and mq.TLO.Me and mq.TLO.Me.Grouped and mq.TLO.Me.Grouped()
        if grouped and (name ~= "" or link) then
            if link then mq.cmdf('/g Taking %s — looting.', link) else mq.cmdf('/g Taking %s — looting.', name) end
        end
        ctx.setMythicalDecision("loot")
        uiState.lootMythicalFeedback = { message = "You chose: Take", showUntil = mq.gettime() + 2000 }
        uiState.lootMythicalAlert = nil
        local path = config.getLootConfigFile and config.getLootConfigFile("loot_mythical_alert.ini")
        if path and path ~= "" then
            mq.cmdf('/ini "%s" Alert itemName ""', path)
            mq.cmdf('/ini "%s" Alert corpseName ""', path)
            mq.cmdf('/ini "%s" Alert itemLink ""', path)
        end
    end
    ctx.mythicalPass = function()
        local alert = uiState.lootMythicalAlert
        if not alert then return end
        local name = alert.itemName or ""
        local link = (alert.itemLink and alert.itemLink ~= "") and alert.itemLink or nil
        local grouped = mq.TLO and mq.TLO.Me and mq.TLO.Me.Grouped and mq.TLO.Me.Grouped()
        if grouped and (name ~= "" or link) then
            if link then mq.cmdf('/g Passing on %s — someone else can loot.', link) else mq.cmdf('/g Passing on %s — someone else can loot.', name) end
        end
        ctx.setMythicalDecision("skip")
        uiState.lootMythicalFeedback = { message = "Passed - left on corpse for group.", showUntil = mq.gettime() + 2000 }
        uiState.lootMythicalAlert = nil
        local path = config.getLootConfigFile and config.getLootConfigFile("loot_mythical_alert.ini")
        if path and path ~= "" then
            mq.cmdf('/ini "%s" Alert itemName ""', path)
            mq.cmdf('/ini "%s" Alert corpseName ""', path)
            mq.cmdf('/ini "%s" Alert itemLink ""', path)
        end
    end
    ctx.setMythicalCopyName = function(name)
        if name and name ~= "" then print(string.format("\ay[ItemUI]\ax Mythical item name: %s", name)) end
    end
    ctx.setMythicalCopyLink = function(link)
        if not link or link == "" then return end
        if ImGui and ImGui.SetClipboardText then ImGui.SetClipboardText(link) end
        print(string.format("\ay[ItemUI]\ax Mythical item link copied to clipboard (or see console)."))
    end
    ctx.clearLootUIState = function()
        uiState.lootRunLootedList = {}
        uiState.lootRunLootedItems = {}
        uiState.lootRunCorpsesLooted = 0
        uiState.lootRunTotalCorpses = 0
        uiState.lootRunCurrentCorpse = ""
        uiState.lootRunFinished = false
        uiState.lootMythicalAlert = nil
        uiState.lootMythicalDecisionStartAt = nil
        uiState.lootMythicalFeedback = nil
        uiState.lootRunTotalValue = 0
        uiState.lootRunTributeValue = 0
        uiState.lootRunBestItemName = ""
        uiState.lootRunBestItemValue = 0
    end
    ctx.loadLootHistory = function()
        if not uiState.lootHistory then refs.loadLootHistoryFromFile() end
        if not uiState.lootHistory then uiState.lootHistory = {} end
    end
    ctx.loadSkipHistory = function()
        if not uiState.skipHistory then refs.loadSkipHistoryFromFile() end
        if not uiState.skipHistory then uiState.skipHistory = {} end
    end
    ctx.clearLootHistory = function()
        uiState.lootHistory = {}
        local path = config.getLootConfigFile and config.getLootConfigFile("loot_history.ini")
        if path and path ~= "" then mq.cmdf('/ini "%s" History count 0', path) end
        refs.lootLoopRefs.saveHistoryAt = 0
    end
    ctx.clearSkipHistory = function()
        uiState.skipHistory = {}
        local path = config.getLootConfigFile and config.getLootConfigFile("skip_history.ini")
        if path and path ~= "" then mq.cmdf('/ini "%s" Skip count 0', path) end
        refs.lootLoopRefs.saveSkipAt = 0
    end
    LootUIView.render(ctx)
end

local M = {}

function M.render(refs)
    local shouldDraw = refs.getShouldDraw and refs.getShouldDraw()
    local isOpen = refs.getOpen and refs.getOpen()
    local uiState = refs.uiState
    if not shouldDraw and not uiState.lootUIOpen then return end
    uiState.lastPickupSetThisFrame = false
    local merchOpen = refs.isMerchantWindowOpen and refs.isMerchantWindowOpen()
    local layoutConfig = refs.layoutConfig or {}
    local layoutDefaults = refs.layoutDefaults or {}
    local C = refs.C or {}
    local sellMacState = refs.sellMacState or {}
    local setStatusMessage = refs.setStatusMessage or function() end
    local saveLayoutToFile = refs.saveLayoutToFile or function() end
    local saveLayoutForView = refs.saveLayoutForView or function() end

    local curView
    if uiState.setupMode then
        if uiState.setupStep == 3 or uiState.setupStep == 4 then
            curView = "Sell"
        else
            curView = "Inventory"  -- steps 1, 2, 5, 6, 7, 8, 9, 10, 11, 12, 13
        end
    else
        curView = (merchOpen and "Sell") or "Inventory"
    end

    if shouldDraw then
        if not uiState.setupMode then
            local w, h = nil, nil
            if curView == "Inventory" then w, h = layoutConfig.WidthInventory, layoutConfig.Height
            elseif curView == "Sell" then w, h = layoutConfig.WidthSell, layoutConfig.Height
            elseif curView == "Loot" then w, h = layoutConfig.WidthLoot or layoutDefaults.WidthLoot, layoutConfig.Height
            end
            if w and h and w > 0 and h > 0 then
                local forceApply = uiState.layoutRevertedApplyFrames and uiState.layoutRevertedApplyFrames > 0
                if uiState.uiLocked or forceApply then
                    ImGui.SetNextWindowSize(ImVec2(w, h), ImGuiCond.Always)
                else
                    ImGui.SetNextWindowSize(ImVec2(w, h), ImGuiCond.FirstUseEver)
                end
            end
            if uiState.alignToContext then
                local invWnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("InventoryWindow")
                if invWnd and invWnd.Open and invWnd.Open() then
                    local x, y = tonumber(invWnd.X and invWnd.X()) or 0, tonumber(invWnd.Y and invWnd.Y()) or 0
                    local pw = tonumber(invWnd.Width and invWnd.Width()) or 0
                    if x and y and pw > 0 then
                        local itemUIX = x + pw + constants.UI.WINDOW_GAP
                        ImGui.SetNextWindowPos(ImVec2(itemUIX, y), ImGuiCond.Always)
                        uiState.itemUIPositionX = itemUIX
                        uiState.itemUIPositionY = y
                    end
                end
            end
        end

        local windowFlags = 0
        if uiState.uiLocked then
            windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
        end

        local winOpen, winVis = ImGui.Begin("CoOpt UI Inventory Companion##ItemUI", isOpen, windowFlags)
        refs.setOpen(winOpen)
        if not winOpen then
            refs.setShouldDraw(false)
            uiState.welcomeSkippedThisSession = false
            uiState.configWindowOpen = false
            refs.closeGameInventoryIfOpen()
            ImGui.End()
            if uiState.lootUIOpen then renderLootWindow(refs) end
            return
        end
        -- Request keyboard capture so ESC closes companion only, not native EQ bags (LIFO fix)
        if winVis then
            -- Intentionally silent pcall: ImGui.SetNextFrameWantCaptureKeyboard may not exist in all MQ/ImGui builds; no diagnostics needed.
            pcall(function()
                if ImGui.SetNextFrameWantCaptureKeyboard then ImGui.SetNextFrameWantCaptureKeyboard(true)
                elseif ImGui.GetIO and ImGui.GetIO().SetNextFrameWantCaptureKeyboard then ImGui.GetIO().SetNextFrameWantCaptureKeyboard(true) end
            end)
        end
        if ImGui.IsKeyPressed(ImGuiKey.Escape) then
            if uiState.pendingQuantityPickup then
                uiState.pendingQuantityPickup = nil
                uiState.pendingQuantityPickupTimeoutAt = nil
                uiState.quantityPickerValue = ""
            else
                local mostRecent = refs.getMostRecentlyOpenedCompanion and refs.getMostRecentlyOpenedCompanion()
                if mostRecent then
                    if refs.closeCompanionWindow then refs.closeCompanionWindow(mostRecent) end
                else
                    ImGui.SetKeyboardFocusHere(-1)
                    refs.setShouldDraw(false)
                    uiState.welcomeSkippedThisSession = false
                    refs.setOpen(false)
                    uiState.configWindowOpen = false
                    refs.closeGameInventoryIfOpen()
                    refs.closeGameMerchantIfOpen()
                    ImGui.End()
                    if uiState.lootUIOpen then renderLootWindow(refs) end
                    return
                end
            end
        end
        if not winVis then
            ImGui.End()
            if uiState.lootUIOpen then renderLootWindow(refs) end
            return
        end

        uiState.hasItemOnCursorThisFrame = refs.itemOps and refs.itemOps.hasItemOnCursor and refs.itemOps.hasItemOnCursor()

        if not uiState.alignToContext then
            uiState.itemUIPositionX, uiState.itemUIPositionY = ImGui.GetWindowPos()
        end
        local itemUIWidth = ImGui.GetWindowWidth()

        local hubX, hubY = uiState.itemUIPositionX, uiState.itemUIPositionY
        local hubW, hubH = itemUIWidth, (ImGui.GetWindowSize and select(2, ImGui.GetWindowSize())) or constants.VIEWS.Height
        local defGap = constants.UI.WINDOW_GAP
        local eqW = layoutConfig.WidthEquipmentPanel or constants.UI.EQUIPMENT_PANEL_WIDTH
        local eqH = layoutConfig.HeightEquipment or constants.UI.EQUIPMENT_PANEL_HEIGHT
        if hubX and hubY and hubW then
            if registry.shouldDraw("equipment") and (layoutConfig.EquipmentWindowX or 0) == 0 and (layoutConfig.EquipmentWindowY or 0) == 0 then
                layoutConfig.EquipmentWindowX = hubX - eqW - defGap
                layoutConfig.EquipmentWindowY = hubY
            end
            if registry.shouldDraw("itemDisplay") and (layoutConfig.ItemDisplayWindowX or 0) == 0 and (layoutConfig.ItemDisplayWindowY or 0) == 0 then
                layoutConfig.ItemDisplayWindowX = hubX + hubW + defGap
                layoutConfig.ItemDisplayWindowY = hubY
            end
            if registry.shouldDraw("augments") and (layoutConfig.AugmentsWindowX or 0) == 0 and (layoutConfig.AugmentsWindowY or 0) == 0 then
                local aw = layoutConfig.WidthAugmentsPanel or layoutDefaults.WidthAugmentsPanel or 560
                layoutConfig.AugmentsWindowX = hubX - aw - defGap
                layoutConfig.AugmentsWindowY = hubY + eqH + defGap
            end
            if registry.shouldDraw("augmentUtility") and (layoutConfig.AugmentUtilityWindowX or 0) == 0 and (layoutConfig.AugmentUtilityWindowY or 0) == 0 then
                local auw = layoutConfig.WidthAugmentUtilityPanel or layoutDefaults.WidthAugmentUtilityPanel or constants.VIEWS.WidthAugmentUtilityPanel
                layoutConfig.AugmentUtilityWindowX = hubX - auw - defGap
                layoutConfig.AugmentUtilityWindowY = hubY + math.floor(eqH * 0.45)
            end
            if registry.shouldDraw("aa") and (layoutConfig.AAWindowX or 0) == 0 and (layoutConfig.AAWindowY or 0) == 0 then
                local idH = layoutConfig.HeightItemDisplay or layoutDefaults.HeightItemDisplay or constants.VIEWS.HeightItemDisplay
                layoutConfig.AAWindowX = hubX + hubW + defGap
                layoutConfig.AAWindowY = hubY + idH + defGap
            end
            if registry.shouldDraw("reroll") and (layoutConfig.RerollWindowX or 0) == 0 and (layoutConfig.RerollWindowY or 0) == 0 then
                local rw = layoutConfig.WidthRerollPanel or layoutDefaults.WidthRerollPanel or constants.VIEWS.WidthRerollPanel or 520
                layoutConfig.RerollWindowX = hubX + hubW + defGap
                layoutConfig.RerollWindowY = hubY
            end
            if uiState.lootUIOpen and (layoutConfig.LootWindowX or 0) == 0 and (layoutConfig.LootWindowY or 0) == 0 then
                layoutConfig.LootWindowX = hubX + hubW + defGap
                layoutConfig.LootWindowY = hubY
            end
            if registry.shouldDraw("bank") and (layoutConfig.BankWindowX or 0) == 0 and (layoutConfig.BankWindowY or 0) == 0 then
                layoutConfig.BankWindowX = hubX + hubW + defGap
                layoutConfig.BankWindowY = hubY
            end
        end

        -- Reset Window Positions: re-apply hub-relative defaults for all companions (positions only)
        if uiState.resetWindowPositionsRequested and hubX and hubY and hubW then
            local defGapReset = constants.UI.WINDOW_GAP
            local eqW = layoutConfig.WidthEquipmentPanel or constants.UI.EQUIPMENT_PANEL_WIDTH
            local eqH = layoutConfig.HeightEquipment or constants.UI.EQUIPMENT_PANEL_HEIGHT
            layoutConfig.EquipmentWindowX = hubX - eqW - defGapReset
            layoutConfig.EquipmentWindowY = hubY
            layoutConfig.ItemDisplayWindowX = hubX + hubW + defGapReset
            layoutConfig.ItemDisplayWindowY = hubY
            local aw = layoutConfig.WidthAugmentsPanel or layoutDefaults.WidthAugmentsPanel or 560
            layoutConfig.AugmentsWindowX = hubX - aw - defGapReset
            layoutConfig.AugmentsWindowY = hubY + eqH + defGapReset
            local auw = layoutConfig.WidthAugmentUtilityPanel or layoutDefaults.WidthAugmentUtilityPanel or constants.VIEWS.WidthAugmentUtilityPanel
            layoutConfig.AugmentUtilityWindowX = hubX - auw - defGapReset
            layoutConfig.AugmentUtilityWindowY = hubY + math.floor(eqH * 0.45)
            local idH = layoutConfig.HeightItemDisplay or layoutDefaults.HeightItemDisplay or constants.VIEWS.HeightItemDisplay
            layoutConfig.AAWindowX = hubX + hubW + defGapReset
            layoutConfig.AAWindowY = hubY + idH + defGapReset
            layoutConfig.RerollWindowX = hubX + hubW + defGapReset
            layoutConfig.RerollWindowY = hubY
            layoutConfig.LootWindowX = hubX + hubW + defGapReset
            layoutConfig.LootWindowY = hubY
            layoutConfig.BankWindowX = hubX + hubW + defGapReset
            layoutConfig.BankWindowY = hubY
            uiState.resetWindowPositionsRequested = false
            uiState.layoutRevertedApplyFrames = 5
            if refs.scheduleLayoutSave then refs.scheduleLayoutSave() end
            if setStatusMessage then setStatusMessage("Window positions reset to hub-relative defaults.") end
        end

        local bankOnline = refs.isBankWindowOpen and refs.isBankWindowOpen()
        for _, mod in ipairs(registry.getEnabledModules()) do
            if mod.id == "bank" then
                if bankOnline then
                    ImGui.PushStyleColor(ImGuiCol.Button, refs.theme.ToVec4(refs.theme.Colors.Keep.Normal))
                    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, refs.theme.ToVec4(refs.theme.Colors.Keep.Hover))
                    ImGui.PushStyleColor(ImGuiCol.ButtonActive, refs.theme.ToVec4(refs.theme.Colors.Keep.Active))
                else
                    ImGui.PushStyleColor(ImGuiCol.Button, refs.theme.ToVec4(refs.theme.Colors.Delete.Normal))
                    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, refs.theme.ToVec4(refs.theme.Colors.Delete.Hover))
                    ImGui.PushStyleColor(ImGuiCol.ButtonActive, refs.theme.ToVec4(refs.theme.Colors.Delete.Active))
                end
            end
            if ImGui.Button(mod.label, ImVec2(mod.buttonWidth or 60, 0)) then
                registry.toggleWindow(mod.id)
                if registry.isOpen(mod.id) then
                    refs.recordCompanionWindowOpened(mod.id)
                    if mod.id == "aa" and aa_data.shouldRefresh() then aa_data.refresh() end
                    if mod.id == "bank" and bankOnline and refs.maybeScanBank then refs.maybeScanBank(bankOnline) end
                    if mod.id == "config" then uiState.configNeedsLoad = true end
                    local msg = (mod.id == "aa" and "Alt Advancement window opened") or (mod.id == "reroll" and "Reroll Companion opened") or (mod.label .. " opened")
                    setStatusMessage(msg)
                end
            end
            if mod.id == "bank" then ImGui.PopStyleColor(3) end
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(mod.tooltip or ""); ImGui.EndTooltip() end
            ImGui.SameLine()
        end
        ImGui.SameLine(ImGui.GetWindowWidth() - 210)
        local prevLocked = uiState.uiLocked
        uiState.uiLocked = ImGui.Checkbox("##Lock", uiState.uiLocked)
        if prevLocked ~= uiState.uiLocked then
            saveLayoutToFile()
            if uiState.uiLocked then
                local w, h = ImGui.GetWindowSize()
                if curView == "Inventory" then layoutConfig.WidthInventory = w; layoutConfig.Height = h
                elseif curView == "Sell" then layoutConfig.WidthSell = w; layoutConfig.Height = h
                elseif curView == "Loot" then layoutConfig.WidthLoot = w; layoutConfig.Height = h
                end
                saveLayoutToFile()
            end
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(uiState.uiLocked and "Pin: UI locked (click to unlock and resize)" or "Pin: UI unlocked (click to lock)"); ImGui.EndTooltip() end
        ImGui.Separator()

        if uiState.setupMode then
            tutorial.renderSetupBar(refs)
            ImGui.Separator()
        end

        if refs.CharacterStats and refs.CharacterStats.render then refs.CharacterStats.render() end
        ImGui.SameLine()

        ImGui.BeginChild("MainContent", ImVec2(0, -C.FOOTER_HEIGHT), true)
        local showWelcomePanel = not uiState.setupMode and refs.getOnboardingComplete and not refs.getOnboardingComplete() and not uiState.welcomeSkippedThisSession
        if showWelcomePanel then
            tutorial.renderWelcomeScreen(refs)
        elseif uiState.setupMode and uiState.setupStep == 1 then
            tutorial.renderDescriptionOverlay(1, refs)
            renderInventoryContent(refs)
        elseif uiState.setupMode and uiState.setupStep == 2 then
            renderInventoryContent(refs)
        elseif uiState.setupMode and uiState.setupStep == 3 then
            if refs.sellItems and #(refs.sellItems or {}) == 0 and refs.maybeScanInventory and refs.maybeScanSellItems then
                local _w = mq.TLO and mq.TLO.Window and mq.TLO.Window("InventoryWindow")
                local invO = (_w and _w.Open and _w.Open()) or false
                local merchO = refs.isMerchantWindowOpen and refs.isMerchantWindowOpen()
                refs.maybeScanInventory(invO)
                refs.maybeScanSellItems(merchO)
            end
            tutorial.renderDescriptionOverlay(3, refs)
            renderInventoryContent(refs)
        elseif uiState.setupMode and uiState.setupStep == 4 then
            if refs.sellItems and #(refs.sellItems or {}) == 0 and refs.maybeScanInventory and refs.maybeScanSellItems then
                local _w = mq.TLO and mq.TLO.Window and mq.TLO.Window("InventoryWindow")
                local invO = (_w and _w.Open and _w.Open()) or false
                local merchO = refs.isMerchantWindowOpen and refs.isMerchantWindowOpen()
                refs.maybeScanInventory(invO)
                refs.maybeScanSellItems(merchO)
            end
            renderInventoryContent(refs)
        elseif uiState.setupMode and uiState.setupStep == 5 then
            tutorial.renderDescriptionOverlay(5, refs)
            renderInventoryContent(refs)
        elseif uiState.setupMode and uiState.setupStep == 6 then
            renderInventoryContent(refs)
        elseif uiState.setupMode and uiState.setupStep == 7 then
            tutorial.renderDescriptionOverlay(7, refs)
            renderInventoryContent(refs)
        elseif uiState.setupMode and uiState.setupStep == 8 then
            if not uiState.setupCompanionsOpenedAtStep8 then
                for _, mod in ipairs(registry.getEnabledModules() or {}) do
                    registry.setWindowState(mod.id, true, true)
                    if refs.recordCompanionWindowOpened then refs.recordCompanionWindowOpened(mod.id) end
                end
                uiState.setupCompanionsOpenedAtStep8 = true
            end
            if not uiState.setupSampleItemShownInDisplay and refs.addItemDisplayTab then
                if refs.equipmentCache then
                    for i = 1, 23 do
                        local it = refs.equipmentCache[i]
                        if it and it.bag ~= nil and it.slot ~= nil then
                            refs.addItemDisplayTab(it, "equipped")
                            uiState.setupSampleItemShownInDisplay = true
                            break
                        end
                    end
                end
                if not uiState.setupSampleItemShownInDisplay and refs.inventoryItems then
                    for _, entry in ipairs(refs.inventoryItems) do
                        if entry and (entry.bag ~= nil or entry.slot ~= nil) then
                            local it = (entry.item and (entry.item.bag ~= nil or entry.item.slot ~= nil)) and entry.item or { bag = entry.bag, slot = entry.slot, name = (entry.item and entry.item.name) or "" }
                            refs.addItemDisplayTab(it, entry.source or "inv")
                            uiState.setupSampleItemShownInDisplay = true
                            break
                        end
                    end
                end
            end
            renderInventoryContent(refs)
        elseif uiState.setupMode and uiState.setupStep == 9 then
            tutorial.renderDescriptionOverlay(9, refs)
        elseif uiState.setupMode and (uiState.setupStep == 10 or uiState.setupStep == 11) then
            local theme = refs.theme
            local config = refs.config
            local configSellFlags = refs.configSellFlags or {}
            local configLootFlags = refs.configLootFlags or {}
            local configLootValues = refs.configLootValues or {}
            local invalidateSellConfigCache = refs.invalidateSellConfigCache or function() end
            if uiState.setupStep == 10 then
                ImGui.TextColored(theme.ToVec4(theme.Colors.Header), "Sell protection")
                ImGui.Separator()
                ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Items with these flags will never be sold when you use Sell.")
                ImGui.Spacing()
                local function sellFlag(name, key, tooltip)
                    local v = ImGui.Checkbox(name, configSellFlags[key])
                    if v ~= configSellFlags[key] then
                        configSellFlags[key] = v
                        if config and config.writeINIValue then config.writeINIValue("sell_flags.ini", "Settings", key, v and "TRUE" or "FALSE") end
                        invalidateSellConfigCache()
                    end
                    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(tooltip); ImGui.EndTooltip() end
                end
                sellFlag("Protect NoDrop", "protectNoDrop", "Never sell items with the NoDrop flag")
                sellFlag("Protect NoTrade", "protectNoTrade", "Never sell items with the NoTrade flag")
                sellFlag("Protect Lore", "protectLore", "Never sell Lore items (unique)")
                ImGui.Spacing()
                ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Additional settings can be found in the Settings window.")
            elseif uiState.setupStep == 11 then
                ImGui.TextColored(theme.ToVec4(theme.Colors.Header), "Loot rules")
                ImGui.Separator()
                ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "When looting (e.g. /doloot), items matching these rules will be picked up.")
                ImGui.Spacing()
                local function lootFlag(name, key, tooltip)
                    local v = ImGui.Checkbox(name, configLootFlags[key])
                    if v ~= configLootFlags[key] then
                        configLootFlags[key] = v
                        if config and config.writeLootINIValue then config.writeLootINIValue("loot_flags.ini", "Settings", key, v and "TRUE" or "FALSE") end
                    end
                    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(tooltip); ImGui.EndTooltip() end
                end
                lootFlag("Auto-loot quest items", "lootQuest", "Loot items with the Quest flag")
                lootFlag("Auto-loot collectibles", "lootCollectible", "Loot items with the Collectible flag")
                ImGui.Spacing()
                ImGui.Text("Min value (non-stack)")
                if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("1 platinum = 1000 copper. Non-stackable items worth less are skipped."); ImGui.EndTooltip() end
                local minVal = tonumber(configLootValues.minLoot) or 0
                local minStr = tostring(minVal)
                ImGui.SameLine(180)
                ImGui.SetNextItemWidth(120)
                minStr, _ = ImGui.InputText("##SetupMinLoot", minStr, ImGuiInputTextFlags.CharsDecimal)
                local n = tonumber(minStr)
                if n and n >= 0 and n ~= (configLootValues.minLoot or 0) then
                    configLootValues.minLoot = math.floor(n)
                    if config and config.writeLootINIValue then config.writeLootINIValue("loot_value.ini", "Settings", "minLootValue", tostring(configLootValues.minLoot)) end
                end
                ImGui.Text("Min value (stack)")
                if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Stackable items worth less per unit are skipped."); ImGui.EndTooltip() end
                local minStackVal = tonumber(configLootValues.minStack) or 0
                local minStackStr = tostring(minStackVal)
                ImGui.SameLine(180)
                ImGui.SetNextItemWidth(120)
                minStackStr, _ = ImGui.InputText("##SetupMinLootStack", minStackStr, ImGuiInputTextFlags.CharsDecimal)
                local nStack = tonumber(minStackStr)
                if nStack and nStack >= 0 and nStack ~= (configLootValues.minStack or 0) then
                    configLootValues.minStack = math.floor(nStack)
                    if config and config.writeLootINIValue then config.writeLootINIValue("loot_value.ini", "Settings", "minLootValueStack", tostring(configLootValues.minStack)) end
                end
                ImGui.Spacing()
                ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Additional settings can be found in the Settings window.")
            end
        elseif uiState.setupMode and uiState.setupStep == 12 then
            renderSetupStep0Content(refs)
            ImGui.Spacing()
            do
                local t = refs.theme
                if t and t.ToVec4 and t.Colors and t.Colors.Muted then
                    ImGui.TextColored(t:ToVec4(t.Colors.Muted), "Additional settings can be found in the Settings window.")
                else
                    ImGui.TextColored(ImVec4(0.6, 0.6, 0.6, 1), "Additional settings can be found in the Settings window.")
                end
            end
        elseif uiState.setupMode and uiState.setupStep == 13 then
            tutorial.renderDescriptionOverlay(13, refs)
        else
            renderInventoryContent(refs)
        end
        ImGui.EndChild()

        if uiState.pendingQuantityPickup then
            if uiState.quantityPickerSubmitPending ~= nil then
                local qty = uiState.quantityPickerSubmitPending
                uiState.quantityPickerSubmitPending = nil
                local pickup = uiState.pendingQuantityPickup
                if qty and qty > 0 and qty <= (pickup and pickup.maxQty or 0) then
                    if pickup and pickup.intent == "script_consume" then
                        uiState.pendingScriptConsume = {
                            bag = pickup.bag, slot = pickup.slot, source = pickup.source,
                            totalToConsume = qty, consumedSoFar = 0, nextClickAt = 0, itemName = pickup.itemName
                        }
                    else
                        uiState.pendingQuantityAction = { action = "set", qty = qty, pickup = pickup }
                    end
                    uiState.pendingQuantityPickup = nil
                    uiState.pendingQuantityPickupTimeoutAt = nil
                    uiState.quantityPickerValue = ""
                else
                    setStatusMessage(string.format("Invalid quantity (1-%d)", pickup and pickup.maxQty or 1))
                end
            else
                ImGui.Separator()
                ImGui.TextColored(refs.theme.ToVec4(refs.theme.Colors.Warning), "Quantity Picker")
                ImGui.SameLine()
                ImGui.Text(string.format("(%s)", uiState.pendingQuantityPickup.itemName or "Item"))
                ImGui.Text(string.format("Max: %d", uiState.pendingQuantityPickup.maxQty))
                ImGui.SameLine()
                ImGui.Text("Quantity:")
                ImGui.SameLine()
                ImGui.SetNextItemWidth(constants.UI.QUANTITY_INPUT_WIDTH)
                local qtyFlags = bit32.bor(ImGuiInputTextFlags.CharsDecimal, ImGuiInputTextFlags.EnterReturnsTrue)
                local submitted
                uiState.quantityPickerValue, submitted = ImGui.InputText("##QuantityPicker", uiState.quantityPickerValue, qtyFlags)
                if submitted then
                    uiState.quantityPickerSubmitPending = tonumber(uiState.quantityPickerValue)
                end
                ImGui.SameLine()
                if ImGui.Button("Set", ImVec2(60, 0)) then
                    local qty = tonumber(uiState.quantityPickerValue)
                    local pickup = uiState.pendingQuantityPickup
                    if qty and qty > 0 and qty <= (pickup and pickup.maxQty or 0) then
                        if pickup and pickup.intent == "script_consume" then
                            uiState.pendingScriptConsume = {
                                bag = pickup.bag, slot = pickup.slot, source = pickup.source,
                                totalToConsume = qty, consumedSoFar = 0, nextClickAt = 0, itemName = pickup.itemName
                            }
                        else
                            uiState.pendingQuantityAction = { action = "set", qty = qty, pickup = pickup }
                        end
                        uiState.pendingQuantityPickup = nil
                        uiState.pendingQuantityPickupTimeoutAt = nil
                        uiState.quantityPickerValue = ""
                    else
                        setStatusMessage(string.format("Invalid quantity (1-%d)", pickup and pickup.maxQty or 1))
                    end
                end
                if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Pick up this quantity"); ImGui.EndTooltip() end
                ImGui.SameLine()
                if ImGui.Button("Max", ImVec2(50, 0)) then
                    local pickup = uiState.pendingQuantityPickup
                    local qty = pickup and pickup.maxQty or 1
                    if pickup and pickup.intent == "script_consume" then
                        uiState.pendingScriptConsume = {
                            bag = pickup.bag, slot = pickup.slot, source = pickup.source,
                            totalToConsume = qty, consumedSoFar = 0, nextClickAt = 0, itemName = pickup.itemName
                        }
                    else
                        uiState.pendingQuantityAction = { action = "max", qty = qty, pickup = pickup }
                    end
                    uiState.pendingQuantityPickup = nil
                    uiState.pendingQuantityPickupTimeoutAt = nil
                    uiState.quantityPickerValue = ""
                end
                if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Pick up maximum quantity"); ImGui.EndTooltip() end
                ImGui.SameLine()
                if ImGui.Button("Cancel", ImVec2(60, 0)) then
                    uiState.pendingQuantityPickup = nil
                    uiState.pendingQuantityPickupTimeoutAt = nil
                    uiState.quantityPickerValue = ""
                end
                if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Cancel quantity selection"); ImGui.EndTooltip() end
            end
        end

        local hasCursor = refs.hasItemOnCursor and refs.hasItemOnCursor()
        if hasCursor then
            ImGui.Separator()
            local cursor = mq.TLO and mq.TLO.Cursor
            local cn = (cursor and cursor.Name and cursor.Name()) or "Item"
            local st = (cursor and cursor.Stack and cursor.Stack()) or 0
            if st and st > 1 then cn = cn .. string.format(" (x%d)", st) end
            ImGui.TextColored(refs.theme.ToVec4(refs.theme.Colors.Warning), "Cursor: " .. cn)
            if ImGui.Button("Clear cursor", ImVec2(90,0)) then refs.removeItemFromCursor() end
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Put item back to last location or use /autoinv"); ImGui.EndTooltip() end
            ImGui.SameLine()
            if ImGui.Button("Put in bags", ImVec2(90,0)) then refs.putCursorInBags() end
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Place item in first free inventory slot"); ImGui.EndTooltip() end
            ImGui.SameLine()
            ImGui.TextColored(refs.theme.ToVec4(refs.theme.Colors.Muted), "Right-click to put back")
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Right-click anywhere on this window to put the item back"); ImGui.EndTooltip() end
        end
        if hasCursor and ImGui.IsMouseReleased(ImGuiMouseButton.Right) and ImGui.IsWindowHovered() then
            refs.removeItemFromCursor()
        end
        -- Don't clear lastPickup while quantity picker is open or quantity action is in progress (phase 7 delay)
        if not hasCursor and not uiState.lastPickupSetThisFrame and not uiState.pendingQuantityPickup and not uiState.pendingQuantityAction then
            if uiState.lastPickup and (uiState.lastPickup.bag ~= nil or uiState.lastPickup.slot ~= nil) then
                uiState.deferredInventoryScanAt = mq.gettime() + constants.TIMING.DEFERRED_SCAN_DELAY_MS
            end
            uiState.lastPickup.bag, uiState.lastPickup.slot, uiState.lastPickup.source = nil, nil, nil
            uiState.lastPickupClearedAt = mq.gettime()
        end
        if not hasCursor then
            uiState.hadItemOnCursorLastFrame = false
        else
            uiState.hadItemOnCursorLastFrame = true
        end

        ImGui.Separator()
        if uiState.pendingDestroy then
            local pd = uiState.pendingDestroy
            local name = pd.name or "item"
            if #name > constants.UI.ITEM_NAME_DISPLAY_MAX then name = name:sub(1, constants.UI.ITEM_NAME_TRUNCATE_LEN) .. "..." end
            local stackSize = (pd.stackSize and pd.stackSize > 0) and pd.stackSize or 1
            ImGui.Text("Destroy " .. name .. "?")
            if stackSize > 1 then
                ImGui.SameLine()
                ImGui.SetNextItemWidth(60)
                local qtyFlags = bit32.bor(ImGuiInputTextFlags.CharsDecimal, ImGuiInputTextFlags.EnterReturnsTrue)
                uiState.destroyQuantityValue, _ = ImGui.InputText("##DestroyQty", uiState.destroyQuantityValue, qtyFlags)
                ImGui.SameLine()
                ImGui.Text(string.format("(1-%d)", stackSize))
            end
            ImGui.SameLine()
            local theme = refs.theme
            local errCol = theme and theme.ToVec4 and theme.ToVec4(theme.Colors.Error) or ImVec4(0.9, 0.25, 0.2, 1)
            ImGui.PushStyleColor(ImGuiCol.Button, errCol)
            if ImGui.Button("Confirm Delete", ImVec2(constants.UI.DESTROY_CONFIRM_BUTTON_WIDTH, 0)) then
                local qty = stackSize
                if stackSize > 1 then
                    local n = tonumber(uiState.destroyQuantityValue)
                    if n and n >= 1 and n <= stackSize then qty = math.floor(n) else qty = stackSize end
                end
                uiState.pendingDestroyAction = { bag = pd.bag, slot = pd.slot, name = pd.name, qty = qty }
                uiState.pendingDestroy = nil
                uiState.destroyQuantityValue = ""
                uiState.destroyQuantityMax = 1
            end
            ImGui.PopStyleColor()
            ImGui.SameLine()
            if ImGui.Button("Cancel", ImVec2(60, 0)) then
                uiState.pendingDestroy = nil
                uiState.destroyQuantityValue = ""
                uiState.destroyQuantityMax = 1
            end
        end
        if sellMacState.failedCount and sellMacState.failedCount > 0 and mq.gettime() < (sellMacState.showFailedUntil or 0) then
            ImGui.TextColored(ImVec4(1, 0.6, 0.2, 1), string.format("Failed to sell (%d):", sellMacState.failedCount))
            ImGui.SameLine()
            local failedList = table.concat(sellMacState.failedItems or {}, ", ")
            if #failedList > constants.UI.FAILED_LIST_TRUNCATE_LEN then failedList = failedList:sub(1, constants.UI.FAILED_LIST_DISPLAY_MAX) .. "..." end
            ImGui.TextColored(ImVec4(1, 0.7, 0.3, 1), failedList)
            ImGui.SameLine()
            ImGui.TextColored(refs.theme.ToVec4(refs.theme.Colors.Muted), "— Rerun /macro sell confirm to retry.")
        end
        if uiState.statusMessage ~= "" then
            ImGui.TextColored(refs.theme.ToVec4(refs.theme.Colors.Success), uiState.statusMessage)
        end
        local errCount = diagnostics.getErrorCount()
        if errCount > 0 then
            ImGui.SameLine()
            local theme = refs.theme
            ImGui.PushStyleColor(ImGuiCol.Button, theme.ToVec4(theme.Colors.Warning))
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, theme.ToVec4(theme.Colors.Warning))
            if ImGui.Button("!##Diagnostics", ImVec2(22, 0)) then
                uiState.diagnosticsPanelOpen = true
            end
            ImGui.PopStyleColor(2)
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text(string.format("%d recent error(s) — click to open diagnostics", errCount))
                ImGui.EndTooltip()
            end
        end
        if uiState.diagnosticsPanelOpen and not ImGui.IsPopupOpen("Diagnostics##ItemUI") then
            ImGui.OpenPopup("Diagnostics##ItemUI")
            uiState.diagnosticsPanelOpen = false
        end
        if ImGui.BeginPopupModal("Diagnostics##ItemUI", nil, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.TextColored(refs.theme.ToVec4(refs.theme.Colors.Header), "Diagnostics")
            ImGui.Separator()
            local configPath = (refs.config and refs.config.CONFIG_PATH) and refs.config.CONFIG_PATH or "—"
            local charName = (refs.mq and refs.mq.TLO and refs.mq.TLO.Me and refs.mq.TLO.Me.Name) and refs.mq.TLO.Me.Name() or "—"
            local version = (refs.C and refs.C.VERSION) and refs.C.VERSION or "—"
            ImGui.Text("Config path: " .. tostring(configPath))
            ImGui.Text("Character: " .. tostring(charName))
            ImGui.Text("Version: " .. tostring(version))
            ImGui.Text("Last scan: —")
            ImGui.Spacing()
            ImGui.Text("Module status:")
            for _, mod in ipairs(registry.getEnabledModules() or {}) do
                local open = registry.isOpen(mod.id)
                ImGui.Text(string.format("  %s: %s", mod.label or mod.id, open and "open" or "closed"))
            end
            ImGui.Separator()
            ImGui.TextColored(refs.theme.ToVec4(refs.theme.Colors.Warning), "Recent errors:")
            local errs = diagnostics.getErrors()
            for i = 1, #errs do
                local e = errs[i]
                local ts = e.timestamp and os.date("%H:%M:%S", e.timestamp) or "?"
                ImGui.TextWrapped(string.format("[%s] %s: %s", ts, e.source, e.message))
                if e.err and e.err ~= "" then
                    ImGui.TextColored(refs.theme.ToVec4(refs.theme.Colors.Muted), "  " .. e.err)
                end
            end
            ImGui.Spacing()
            if ImGui.Button("Clear errors", ImVec2(100, 0)) then
                diagnostics.clearErrors()
            end
            ImGui.SameLine()
            if ImGui.Button("Close", ImVec2(80, 0)) then
                ImGui.CloseCurrentPopup()
            end
            ImGui.EndPopup()
        end
        ImGui.End()

        -- Config rendered via registry.getDrawableModules()

        if registry.shouldDraw("equipment") then
            local now = mq.gettime()
            local shouldRefresh = false
            if uiState.equipmentDeferredRefreshAt and now >= uiState.equipmentDeferredRefreshAt then
                uiState.equipmentDeferredRefreshAt = nil
                shouldRefresh = true
            elseif not uiState.equipmentLastRefreshAt or (now - uiState.equipmentLastRefreshAt) > constants.TIMING.EQUIPMENT_REFRESH_THROTTLE_MS then
                shouldRefresh = true
            end
            if shouldRefresh and refs.refreshEquipmentCache then
                refs.refreshEquipmentCache()
                uiState.equipmentLastRefreshAt = now
            end
        else
            uiState.equipmentLastRefreshAt = nil
        end
        if uiState.deferredInventoryScanAt and mq.gettime() >= uiState.deferredInventoryScanAt then
            local invWnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("InventoryWindow")
            local invOpen = (invWnd and invWnd.Open and invWnd.Open()) or false
            if refs.maybeScanInventory then refs.maybeScanInventory(invOpen) end
            uiState.deferredInventoryScanAt = nil
        end
        -- Equipment rendered via registry.getDrawableModules()
        -- Bank rendered via registry.getDrawableModules()
        -- Augments rendered via registry.getDrawableModules()
        -- Augment Utility rendered via registry.getDrawableModules()
        -- Item Display rendered via registry.getDrawableModules()
        local itemDisplayState = ItemDisplayView.getState()
        if itemDisplayState.itemDisplayLocateRequest and itemDisplayState.itemDisplayLocateRequestAt then
            local now = mq.gettime()
            local clearMs = (constants.TIMING.ITEM_DISPLAY_LOCATE_CLEAR_SEC or 3) * 1000
            if now - itemDisplayState.itemDisplayLocateRequestAt > clearMs then
                itemDisplayState.itemDisplayLocateRequest = nil
                itemDisplayState.itemDisplayLocateRequestAt = nil
            end
        end
        for _, mod in ipairs(registry.getDrawableModules()) do
            mod.render(refs)
        end
    end

    if uiState.lootUIOpen then
        renderLootWindow(refs)
    end
end

return M
