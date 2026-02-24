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
local ConfigView = require('itemui.views.config')
local RerollView = require('itemui.views.reroll')
local aa_data = require('itemui.services.aa_data')

local function buildViewContext()
    return context.build()
end

local function extendContext(ctx)
    return context.extend(ctx)
end

local function renderInventoryContent(refs)
    local ctx = extendContext(buildViewContext())
    local merchOpen = refs.isMerchantWindowOpen and refs.isMerchantWindowOpen()
    local bankOpen = refs.isBankWindowOpen and refs.isBankWindowOpen()
    local lootOpen = refs.isLootWindowOpen and refs.isLootWindowOpen()
    local uiState = refs.uiState
    local simulateSellView = (uiState.setupMode and uiState.setupStep == 2)
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

local function renderRerollWindow(refs)
    local ctx = extendContext(buildViewContext())
    RerollView.render(ctx)
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
    if uiState.setupMode and uiState.setupStep == 1 then
        curView = "Inventory"
    elseif uiState.setupMode and uiState.setupStep == 2 then
        curView = "Sell"
    elseif uiState.setupMode and uiState.setupStep == 3 then
        curView = "Inventory"
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
            uiState.configWindowOpen = false
            refs.closeGameInventoryIfOpen()
            ImGui.End()
            if uiState.lootUIOpen then renderLootWindow(refs) end
            return
        end
        if ImGui.IsKeyPressed(ImGuiKey.Escape) then
            if uiState.pendingQuantityPickup then
                uiState.pendingQuantityPickup = nil
                uiState.pendingQuantityPickupTimeoutAt = nil
                uiState.quantityPickerValue = ""
            else
                local mostRecent = refs.getMostRecentlyOpenedCompanion and refs.getMostRecentlyOpenedCompanion()
                if mostRecent then
                    refs.closeCompanionWindow(mostRecent)
                else
                    ImGui.SetKeyboardFocusHere(-1)
                    refs.setShouldDraw(false)
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

        if uiState.syncBankWindow and uiState.bankWindowOpen and uiState.bankWindowShouldDraw and uiState.itemUIPositionX and uiState.itemUIPositionY and itemUIWidth then
            local bankX = uiState.itemUIPositionX + itemUIWidth + constants.UI.WINDOW_GAP
            local bankY = uiState.itemUIPositionY
            layoutConfig.BankWindowX = bankX
            layoutConfig.BankWindowY = bankY
        end

        local hubX, hubY = uiState.itemUIPositionX, uiState.itemUIPositionY
        local hubW, hubH = itemUIWidth, (ImGui.GetWindowSize and select(2, ImGui.GetWindowSize())) or constants.VIEWS.Height
        local defGap = constants.UI.WINDOW_GAP
        local eqW = layoutConfig.WidthEquipmentPanel or constants.UI.EQUIPMENT_PANEL_WIDTH
        local eqH = layoutConfig.HeightEquipment or constants.UI.EQUIPMENT_PANEL_HEIGHT
        if hubX and hubY and hubW then
            if uiState.equipmentWindowShouldDraw and (layoutConfig.EquipmentWindowX or 0) == 0 and (layoutConfig.EquipmentWindowY or 0) == 0 then
                layoutConfig.EquipmentWindowX = hubX - eqW - defGap
                layoutConfig.EquipmentWindowY = hubY
            end
            if uiState.itemDisplayWindowShouldDraw and (layoutConfig.ItemDisplayWindowX or 0) == 0 and (layoutConfig.ItemDisplayWindowY or 0) == 0 then
                layoutConfig.ItemDisplayWindowX = hubX + hubW + defGap
                layoutConfig.ItemDisplayWindowY = hubY
            end
            if uiState.augmentsWindowShouldDraw and (layoutConfig.AugmentsWindowX or 0) == 0 and (layoutConfig.AugmentsWindowY or 0) == 0 then
                local aw = layoutConfig.WidthAugmentsPanel or layoutDefaults.WidthAugmentsPanel or 560
                layoutConfig.AugmentsWindowX = hubX - aw - defGap
                layoutConfig.AugmentsWindowY = hubY + eqH + defGap
            end
            if uiState.augmentUtilityWindowShouldDraw and (layoutConfig.AugmentUtilityWindowX or 0) == 0 and (layoutConfig.AugmentUtilityWindowY or 0) == 0 then
                local auw = layoutConfig.WidthAugmentUtilityPanel or layoutDefaults.WidthAugmentUtilityPanel or constants.VIEWS.WidthAugmentUtilityPanel
                layoutConfig.AugmentUtilityWindowX = hubX - auw - defGap
                layoutConfig.AugmentUtilityWindowY = hubY + math.floor(eqH * 0.45)
            end
            if uiState.aaWindowShouldDraw and (layoutConfig.AAWindowX or 0) == 0 and (layoutConfig.AAWindowY or 0) == 0 then
                local idH = layoutConfig.HeightItemDisplay or layoutDefaults.HeightItemDisplay or constants.VIEWS.HeightItemDisplay
                layoutConfig.AAWindowX = hubX + hubW + defGap
                layoutConfig.AAWindowY = hubY + idH + defGap
            end
            if uiState.rerollWindowShouldDraw and (layoutConfig.RerollWindowX or 0) == 0 and (layoutConfig.RerollWindowY or 0) == 0 then
                local rw = layoutConfig.WidthRerollPanel or layoutDefaults.WidthRerollPanel or constants.VIEWS.WidthRerollPanel or 520
                layoutConfig.RerollWindowX = hubX + hubW + defGap
                layoutConfig.RerollWindowY = hubY
            end
            if uiState.lootUIOpen and (layoutConfig.LootWindowX or 0) == 0 and (layoutConfig.LootWindowY or 0) == 0 then
                layoutConfig.LootWindowX = hubX + hubW + defGap
                layoutConfig.LootWindowY = hubY
            end
        end

        if ImGui.Button("Equipment", ImVec2(75, 0)) then
            uiState.equipmentWindowOpen = not uiState.equipmentWindowOpen
            uiState.equipmentWindowShouldDraw = uiState.equipmentWindowOpen
            if uiState.equipmentWindowOpen then refs.recordCompanionWindowOpened("equipment"); setStatusMessage("Equipment Companion opened") end
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Open Equipment Companion (current equipped items)"); ImGui.EndTooltip() end
        ImGui.SameLine()
        if (tonumber(layoutConfig.ShowAAWindow) or 1) ~= 0 then
            if ImGui.Button("AA", ImVec2(45, 0)) then
                uiState.aaWindowOpen = not uiState.aaWindowOpen
                uiState.aaWindowShouldDraw = uiState.aaWindowOpen
                if uiState.aaWindowOpen then
                    refs.recordCompanionWindowOpened("aa")
                    if aa_data.shouldRefresh() then aa_data.refresh() end
                    setStatusMessage("Alt Advancement window opened")
                end
            end
            if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Open Alt Advancement window (view, train, backup/restore AAs)"); ImGui.EndTooltip() end
            ImGui.SameLine()
        end
        if ImGui.Button("Augment Utility", ImVec2(100, 0)) then
            uiState.augmentUtilityWindowOpen = not uiState.augmentUtilityWindowOpen
            uiState.augmentUtilityWindowShouldDraw = uiState.augmentUtilityWindowOpen
            if uiState.augmentUtilityWindowOpen then refs.recordCompanionWindowOpened("augmentUtility"); setStatusMessage("Augment Utility opened") end
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Insert/remove augments (use Item Display tab as target)"); ImGui.EndTooltip() end
        ImGui.SameLine()
        if ImGui.Button("Augments", ImVec2(55, 0)) then
            uiState.augmentsWindowOpen = not uiState.augmentsWindowOpen
            uiState.augmentsWindowShouldDraw = uiState.augmentsWindowOpen
            if uiState.augmentsWindowOpen then refs.recordCompanionWindowOpened("augments"); setStatusMessage("Augments window opened") end
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Open Augments window (augment inventory, Always sell / Never loot lists, stats on hover)"); ImGui.EndTooltip() end
        ImGui.SameLine()
        if ImGui.Button("Reroll", ImVec2(55, 0)) then
            uiState.rerollWindowOpen = not uiState.rerollWindowOpen
            uiState.rerollWindowShouldDraw = uiState.rerollWindowOpen
            if uiState.rerollWindowOpen then refs.recordCompanionWindowOpened("reroll"); setStatusMessage("Reroll Companion opened") end
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Open Reroll Companion (augment and mythical reroll lists)"); ImGui.EndTooltip() end
        ImGui.SameLine(ImGui.GetWindowWidth() - 210)
        if ImGui.Button("Settings", ImVec2(70, 0)) then uiState.configWindowOpen = true; uiState.configNeedsLoad = true; refs.recordCompanionWindowOpened("config") end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Open CoOpt UI Settings"); ImGui.EndTooltip() end
        ImGui.SameLine()
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
        ImGui.SameLine()
        local bankOnline = refs.isBankWindowOpen and refs.isBankWindowOpen()
        if bankOnline then
            ImGui.PushStyleColor(ImGuiCol.Button, refs.theme.ToVec4(refs.theme.Colors.Keep.Normal))
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, refs.theme.ToVec4(refs.theme.Colors.Keep.Hover))
            ImGui.PushStyleColor(ImGuiCol.ButtonActive, refs.theme.ToVec4(refs.theme.Colors.Keep.Active))
        else
            ImGui.PushStyleColor(ImGuiCol.Button, refs.theme.ToVec4(refs.theme.Colors.Delete.Normal))
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, refs.theme.ToVec4(refs.theme.Colors.Delete.Hover))
            ImGui.PushStyleColor(ImGuiCol.ButtonActive, refs.theme.ToVec4(refs.theme.Colors.Delete.Active))
        end
        if ImGui.Button("Bank", ImVec2(60, 0)) then
            uiState.bankWindowOpen = not uiState.bankWindowOpen
            uiState.bankWindowShouldDraw = uiState.bankWindowOpen
            if uiState.bankWindowOpen then refs.recordCompanionWindowOpened("bank"); if bankOnline and refs.maybeScanBank then refs.maybeScanBank(bankOnline) end end
        end
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(bankOnline and "Open or close the bank window. Bank is online." or "Open or close the bank window. Bank is offline."); ImGui.EndTooltip() end
        ImGui.PopStyleColor(3)
        ImGui.Separator()

        if uiState.setupMode then
            if uiState.setupStep == 1 then
                ImGui.TextColored(refs.theme.ToVec4(refs.theme.Colors.Warning), "Step 1 of 3: Inventory — Resize the window and columns as you like.")
                ImGui.SameLine()
                if ImGui.Button("Next", ImVec2(60, 0)) then
                    local w, h = ImGui.GetWindowSize()
                    if w and h and w > 0 and h > 0 then saveLayoutForView("Inventory", w, h, nil) end
                    uiState.setupStep = 2
                    print("\ag[ItemUI]\ax Saved Inventory layout. Step 2: Open a merchant, then resize and click Next.")
                end
            elseif uiState.setupStep == 2 then
                ImGui.TextColored(refs.theme.ToVec4(refs.theme.Colors.Warning), "Step 2 of 3: Sell view — Resize the window and columns, then click Next.")
                if not merchOpen then
                    ImGui.SameLine()
                    ImGui.TextColored(refs.theme.ToVec4(refs.theme.Colors.Success), "(Simulated view - no merchant needed)")
                end
                if refs.sellItems and #refs.sellItems == 0 and refs.maybeScanInventory and refs.maybeScanSellItems then
                    local _w = mq.TLO and mq.TLO.Window and mq.TLO.Window("InventoryWindow")
                    local invO = (_w and _w.Open and _w.Open()) or false
                    local merchO = refs.isMerchantWindowOpen and refs.isMerchantWindowOpen()
                    refs.maybeScanInventory(invO); refs.maybeScanSellItems(merchO)
                end
                if ImGui.Button("Back", ImVec2(50, 0)) then uiState.setupStep = 1 end
                ImGui.SameLine()
                if ImGui.Button("Next", ImVec2(60, 0)) then
                    local w, h = ImGui.GetWindowSize()
                    if w and h and w > 0 and h > 0 then saveLayoutForView("Sell", w, h, nil) end
                    uiState.setupStep = 3
                    uiState.bankWindowOpen = true
                    uiState.bankWindowShouldDraw = true
                    refs.recordCompanionWindowOpened("bank")
                    print("\ag[ItemUI]\ax Saved Sell layout. Step 3: Open the bank window and resize it, then Save & finish.")
                end
            elseif uiState.setupStep == 3 then
                ImGui.TextColored(refs.theme.ToVec4(refs.theme.Colors.Warning), "Step 3 of 3: Open and resize the Bank window, then save.")
                if ImGui.Button("Back", ImVec2(50, 0)) then uiState.setupStep = 2; uiState.bankWindowOpen = false; uiState.bankWindowShouldDraw = false end
                ImGui.SameLine()
                if ImGui.Button("Save & finish", ImVec2(100, 0)) then
                    uiState.setupMode = false
                    uiState.setupStep = 0
                    print("\ag[ItemUI]\ax Setup complete! Your layout is saved.")
                end
            end
            ImGui.Separator()
        end

        if refs.CharacterStats and refs.CharacterStats.render then refs.CharacterStats.render() end
        ImGui.SameLine()

        ImGui.BeginChild("MainContent", ImVec2(0, -C.FOOTER_HEIGHT), true)
        renderInventoryContent(refs)
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
        ImGui.End()

        if uiState.configWindowOpen then
            local ctx = extendContext(buildViewContext())
            ConfigView.render(ctx)
        end

        if uiState.equipmentWindowShouldDraw then
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
        renderEquipmentWindow(refs)
        renderBankWindow(refs)
        if uiState.augmentsWindowShouldDraw then
            renderAugmentsWindow(refs)
        end
        if uiState.augmentUtilityWindowShouldDraw then
            renderAugmentUtilityWindow(refs)
        end
        if uiState.itemDisplayWindowShouldDraw then
            renderItemDisplayWindow(refs)
        end
        if uiState.itemDisplayLocateRequest and uiState.itemDisplayLocateRequestAt then
            local now = mq.gettime()
            local clearMs = (constants.TIMING.ITEM_DISPLAY_LOCATE_CLEAR_SEC or 3) * 1000
            if now - uiState.itemDisplayLocateRequestAt > clearMs then
                uiState.itemDisplayLocateRequest = nil
                uiState.itemDisplayLocateRequestAt = nil
            end
        end
        if (tonumber(layoutConfig.ShowAAWindow) or 1) ~= 0 and uiState.aaWindowShouldDraw then
            renderAAWindow(refs)
        end
        if uiState.rerollWindowShouldDraw then
            renderRerollWindow(refs)
        end
    end

    if uiState.lootUIOpen then
        renderLootWindow(refs)
    end
end

return M
