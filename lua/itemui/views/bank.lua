--[[
    Bank View - Separate window showing live bank data or cached snapshot
    
    Part of ItemUI Phase 5: View Extraction
    Renders the bank window with online/offline modes
--]]

local mq = require('mq')
require('ImGui')
local ItemUtils = require('mq.ItemUtils')
local ItemTooltip = require('itemui.utils.item_tooltip')

local constants = require('itemui.constants')
local BankView = {}

-- Module interface: render bank window
-- Params: context table containing all necessary state and functions from init.lua
function BankView.render(ctx)
    if not ctx.uiState.bankWindowShouldDraw then return end
    
    local bankOpen = ctx.isBankWindowOpen and ctx.isBankWindowOpen() or false
    ctx.ensureBankCacheFromStorage()
    local list = bankOpen and ctx.bankItems or ctx.bankCache
    
    -- Window positioning
    local bankX = ctx.layoutConfig.BankWindowX
    local bankY = ctx.layoutConfig.BankWindowY
    
    local forceApply = ctx.uiState.layoutRevertedApplyFrames and ctx.uiState.layoutRevertedApplyFrames > 0
    if ctx.uiState.syncBankWindow then
        -- When synced, use the position calculated in renderUI (stored in layoutConfig)
        -- This position is updated every frame when sync is enabled
        if bankX and bankY then
            ImGui.SetNextWindowPos(ImVec2(bankX, bankY), ImGuiCond.Always)
        end
    else
        -- When not synced, use saved position or calculate initial position
        if bankX and bankY and bankX ~= 0 and bankY ~= 0 then
            -- Use saved position (Always when forceApply so revert takes effect)
            ImGui.SetNextWindowPos(ImVec2(bankX, bankY), forceApply and ImGuiCond.Always or ImGuiCond.FirstUseEver)
        elseif ctx.uiState.alignToContext then
            -- Calculate initial position relative to ItemUI (if snapping is enabled)
            local invWnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("InventoryWindow")
            if invWnd and invWnd.Open and invWnd.Open() then
                local invX, invY = tonumber(invWnd.X and invWnd.X()) or 0, tonumber(invWnd.Y and invWnd.Y()) or 0
                local invW = tonumber(invWnd.Width and invWnd.Width()) or 0
                if invX and invY and invW > 0 then
                    -- ItemUI position = InventoryWindow.X + InventoryWindow.Width + spacing
                    local itemUIX = invX + invW + constants.UI.WINDOW_GAP
                    local itemUIY = invY
                    local itemUIW = ctx.layoutConfig.WidthInventory or constants.VIEWS.WidthInventory
                    local calculatedX = itemUIX + itemUIW + constants.UI.WINDOW_GAP
                    ImGui.SetNextWindowPos(ImVec2(calculatedX, itemUIY), ImGuiCond.FirstUseEver)
                    -- Save this calculated position for future use
                    ctx.layoutConfig.BankWindowX = calculatedX
                    ctx.layoutConfig.BankWindowY = itemUIY
                    ctx.scheduleLayoutSave()  -- Schedule debounced save
                end
            end
        end
    end
    
    -- Window size (Always when forceApply so revert takes effect)
    local w = ctx.layoutConfig.WidthBankPanel or constants.VIEWS.WidthBankPanel
    local h = ctx.layoutConfig.HeightBank or constants.VIEWS.HeightBank
    if w > 0 and h > 0 then
        ImGui.SetNextWindowSize(ImVec2(w, h), forceApply and ImGuiCond.Always or ImGuiCond.FirstUseEver)
    end
    
    -- Window flags - allow resizing unless UI is locked
    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end
    
    local winOpen, winVis = ImGui.Begin("CoOpt UI Bank Companion##ItemUIBank", ctx.uiState.bankWindowOpen, windowFlags)
    ctx.uiState.bankWindowOpen = winOpen
    ctx.uiState.bankWindowShouldDraw = winOpen
    
    if not winOpen then ImGui.End(); return end
    -- Escape closes this window via main Inventory Companion's LIFO handler only
    if not winVis then ImGui.End(); return end
    
    -- Save window size when resized (if unlocked)
    if not ctx.uiState.uiLocked then
        local currentW, currentH = ImGui.GetWindowSize()
        if currentW and currentH and currentW > 0 and currentH > 0 then
            ctx.layoutConfig.WidthBankPanel = currentW
            ctx.layoutConfig.HeightBank = currentH
        end
    end
    
    -- Save position when window is moved (only if not synced, or when sync is disabled)
    if not ctx.uiState.syncBankWindow then
        local currentX, currentY = ImGui.GetWindowPos()
        if currentX and currentY then
            -- Only save if position actually changed (to avoid constant file writes)
            if not ctx.layoutConfig.BankWindowX or math.abs(ctx.layoutConfig.BankWindowX - currentX) > 1 or 
               not ctx.layoutConfig.BankWindowY or math.abs(ctx.layoutConfig.BankWindowY - currentY) > 1 then
                ctx.layoutConfig.BankWindowX = currentX
                ctx.layoutConfig.BankWindowY = currentY
                ctx.scheduleLayoutSave()  -- Schedule debounced save (was immediate save causing spam)
            end
        end
    end
    
    -- Header
    ctx.theme.TextHeader("Bank")
    ImGui.SameLine()
    ctx.renderRefreshButton(ctx, "Refresh##BankHeader", "Rescan bank", function() ctx.scanBank() end, { width = 80, messageBefore = "Scanning bank...", messageAfter = "Bank refreshed" })
    ImGui.Separator()
    
    -- Bank status
    if bankOpen then
        ctx.theme.TextSuccess("Online")
        ImGui.SameLine()
        ctx.theme.TextInfo("— Shift+click item to move to inventory")
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Bank window is open; hold Shift and left-click an item to move it to inventory"); ImGui.EndTooltip() end
    else
        ctx.theme.TextWarning("Offline")
        ImGui.SameLine()
        ctx.theme.TextMuted(ctx.perfCache.lastBankCacheTime > 0 and string.format("(last: %s)", os.date("%m/%d %H:%M", ctx.perfCache.lastBankCacheTime)) or "(no data)")
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Bank window closed; showing last saved snapshot"); ImGui.EndTooltip() end
    end
    ImGui.Separator()
    
    -- Search
    ImGui.Text("Search:")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(120)
    ctx.uiState.searchFilterBank, _ = ImGui.InputText("##BankSearch", ctx.uiState.searchFilterBank)
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Filter bank items by name"); ImGui.EndTooltip() end
    ImGui.SameLine()
    if ImGui.Button("X##BankSearchClear", ImVec2(22, 0)) then ctx.uiState.searchFilterBank = "" end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Clear search"); ImGui.EndTooltip() end
    if bankOpen then
        ImGui.SameLine()
        ctx.renderRefreshButton(ctx, "Refresh##Bank", "Rescan bank", function() ctx.scanBank() end, { width = 60, messageBefore = "Scanning bank...", messageAfter = "Bank refreshed" })
    end
    ImGui.Separator()
    
    local hasCursor = ctx.hasItemOnCursor()
    local lp = ctx.uiState.lastPickup
    -- Pre-filter bank list
    local filteredBank = {}
    local searchBankLower = (ctx.uiState.searchFilterBank or ""):lower()
    for _, item in ipairs(list) do
        if searchBankLower == "" or (item.name or ""):lower():find(searchBankLower, 1, true) then
            if not ctx.shouldHideRowForCursor(item, "bank") then
                table.insert(filteredBank, item)
            end
        end
    end
    
    -- Build fixed columns list (from config; ImGui SaveSettings handles sort/order)
    local visibleCols = ctx.getFixedColumns("Bank")
    local nCols = #visibleCols
    if nCols == 0 then 
        nCols = 6
        visibleCols = {
            {key = "Name", label = "Name", numeric = false},
            {key = "Bag", label = "Bag", numeric = true},
            {key = "Slot", label = "Slot", numeric = true},
            {key = "Value", label = "Value", numeric = true},
            {key = "Stack", label = "Stack", numeric = true},
            {key = "Type", label = "Type", numeric = false}
        }
    end
    
    if ImGui.BeginTable("ItemUI_Bank", nCols, ctx.uiState.tableFlags) then
        -- Setup columns dynamically
        local function simpleHash(str)
            local h = 0
            for i = 1, #str do
                h = (h * 31 + string.byte(str, i)) % 2147483647
            end
            return h
        end
        
        local bankSortCol = (ctx.sortState.bankColumn and type(ctx.sortState.bankColumn) == "string" and ctx.sortState.bankColumn) or "Name"
        for i, colDef in ipairs(visibleCols) do
            -- Set base flags: Name = WidthStretch, others = WidthFixed
            local flags = (colDef.key == "Name") and ImGuiTableColumnFlags.WidthStretch or ImGuiTableColumnFlags.WidthFixed
            
            -- Add DefaultSort flag if this is the current sort column
            if colDef.key == bankSortCol then
                flags = bit32.bor(flags, ImGuiTableColumnFlags.DefaultSort)
            end
            
            -- Set width: 0 for Name (stretch column), specific widths for fixed columns
            local width = 0
            if colDef.key ~= "Name" then
                if ctx.columnAutofitWidths["Bank"][colDef.key] then
                    width = ctx.columnAutofitWidths["Bank"][colDef.key]
                else
                    -- Default widths
                    if colDef.key == "Bag" then width = 36
                    elseif colDef.key == "Slot" then width = 36
                    elseif colDef.key == "Value" then width = 60
                    elseif colDef.key == "Stack" then width = 40
                    elseif colDef.key == "Type" then width = 70
                    elseif colDef.key == "Icon" then width = 28
                    else width = 60 end
                end
            end
            local userID = simpleHash(colDef.key)
            ImGui.TableSetupColumn(colDef.label, flags, width, userID)
        end
        ImGui.TableSetupScrollFreeze(0, 1)
        
        -- Build column mapping for sort handler
        local colKeyByUserID = {}
        for i, colDef in ipairs(visibleCols) do
            colKeyByUserID[simpleHash(colDef.key)] = colDef.key
        end
        
        -- Handle sort clicks
        local sortSpecs = ImGui.TableGetSortSpecs()
        if sortSpecs and sortSpecs.SpecsDirty and sortSpecs.SpecsCount > 0 then
            local spec = sortSpecs:Specs(1)
            if spec then
                local userID = spec.ColumnUserID
                local colKey = colKeyByUserID[userID]
                if not colKey and visibleCols[spec.ColumnIndex + 1] then
                    colKey = visibleCols[spec.ColumnIndex + 1].key
                end
                if not colKey then colKey = ctx.getColumnKeyByIndex("Bank", spec.ColumnIndex + 1) end
                if colKey then
                    ctx.sortState.bankColumn = colKey
                    ctx.sortState.bankDirection = spec.SortDirection
                    ctx.scheduleLayoutSave()
                    ctx.flushLayoutSave()
                end
            end
            sortSpecs.SpecsDirty = false
        end
        
        -- Capture header rect before/after TableHeadersRow for header-only right-click
        local headerTop = ImGui.GetCursorScreenPosVec and ImGui.GetCursorScreenPosVec()
        ImGui.TableHeadersRow()
        local bodyTop = ImGui.GetCursorScreenPosVec and ImGui.GetCursorScreenPosVec()
        -- Right-click on column headers only (not body) to show column visibility menu
        local hoveredColumn = ImGui.TableGetHoveredColumn()
        local inHeader = false
        if headerTop and bodyTop and ImGui.IsMouseHoveringRect then
            local w = (ImGui.GetWindowWidth and ImGui.GetWindowWidth()) or 9999
            inHeader = ImGui.IsMouseHoveringRect(
                ImVec2(headerTop.x, headerTop.y),
                ImVec2(headerTop.x + w, bodyTop.y),
                false)
        end
        if hoveredColumn >= 0 and ImGui.IsMouseReleased(ImGuiMouseButton.Right) and inHeader then
            ImGui.OpenPopup("ColumnMenu_Bank")
        end
        
        if ImGui.BeginPopup("ColumnMenu_Bank") then
            ImGui.Text("Columns (changes apply on next open)")
            ImGui.Separator()
            for _, colDef in ipairs(ctx.availableColumns["Bank"] or {}) do
                local inFixed = ctx.isColumnInFixedSet("Bank", colDef.key)
                if ImGui.MenuItem(colDef.label, "", inFixed) then
                    ctx.toggleFixedColumn("Bank", colDef.key)
                    ctx.setStatusMessage("Column changes apply when you reopen CoOpt UI Inventory Companion")
                end
            end
            ImGui.Separator()
            if ImGui.MenuItem("Autofit Columns") then
                ctx.autofitColumns("Bank", filteredBank, visibleCols)
            end
            ImGui.EndPopup()
        end
        
        -- Sort cache (Phase 3: shared getSortedList helper)
        local bankSortKey = (ctx.sortState.bankColumn and type(ctx.sortState.bankColumn) == "string" and ctx.sortState.bankColumn) or "Name"
        local bankSortDir = ctx.sortState.bankDirection or ImGuiSortDirection.Ascending
        local bankFilterStr = ctx.uiState.searchFilterBank or ""
        local bankHidingNow = not not (lp and lp.source == "bank" and lp.bag and lp.slot)
        local validity = {
            filter = bankFilterStr,
            hidingSlot = bankHidingNow,
            fullListLen = #list,
            nFiltered = #filteredBank,
        }
        filteredBank = ctx.getSortedList(ctx.perfCache.bank, filteredBank, bankSortKey, bankSortDir, validity, "Bank", ctx.sortColumns)

        local nBank = #filteredBank
        local clipperBank = ImGuiListClipper.new()
        clipperBank:Begin(nBank)
        while clipperBank:Step() do
            for i = clipperBank.DisplayStart + 1, clipperBank.DisplayEnd do
                local item = filteredBank[i]
                if not item then goto bank_continue end
                ImGui.TableNextRow()
                local loc = ctx.uiState.itemDisplayLocateRequest
                if loc and loc.source == "bank" and loc.bag == item.bag and loc.slot == item.slot then
                    ImGui.TableSetBgColor(ImGuiTableBgTarget.RowBg0, ImGui.GetColorU32(ImVec4(0.25, 0.45, 0.75, 0.45)))
                end
                local rid = "bank_" .. item.bag .. "_" .. item.slot
                ImGui.PushID(rid)
                
                -- Render columns dynamically based on visibleCols
                for _, colDef in ipairs(visibleCols) do
                    ImGui.TableNextColumn()
                    local colKey = colDef.key
                    
                    if colKey == "Name" then
                        -- Name column with special interaction logic
                        local dn = item.name or ""
                        if (item.stackSize or 1) > 1 then dn = dn .. string.format(" (x%d)", item.stackSize) end
                        local nameColor = ctx.getSellStatusNameColor and ctx.getSellStatusNameColor(ctx, item) or ImVec4(1, 1, 1, 1)
                        ImGui.PushStyleColor(ImGuiCol.Text, nameColor)
                        ImGui.Selectable(dn, false, ImGuiSelectableFlags.None, ImVec2(0,0))
                        ImGui.PopStyleColor(1)
                        if bankOpen then
                            if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
                                if ImGui.GetIO().KeyShift then
                                    ctx.moveBankToInv(item.bag, item.slot)
                                elseif not hasCursor then
                                    if item.stackSize and item.stackSize > 1 then
                                        ctx.uiState.pendingQuantityPickup = {
                                            bag = item.bag,
                                            slot = item.slot,
                                            source = "bank",
                                            maxQty = item.stackSize,
                                            itemName = item.name
                                        }
                                        ctx.uiState.pendingQuantityPickupTimeoutAt = mq.gettime() + constants.TIMING.QUANTITY_PICKUP_TIMEOUT_MS
                                        ctx.uiState.quantityPickerValue = tostring(item.stackSize)
                                        ctx.uiState.quantityPickerMax = item.stackSize
                                        -- Set lastPickup so activation guard does not treat the upcoming stack pickup as unexpected
                                        ctx.uiState.lastPickup.bag = item.bag
                                        ctx.uiState.lastPickup.slot = item.slot
                                        ctx.uiState.lastPickup.source = "bank"
                                        ctx.uiState.lastPickupSetThisFrame = true
                                    else
                                        ctx.pickupFromSlot(item.bag, item.slot, "bank")
                                    end
                                end
                            end
                        end
                        if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Right) then
                            if ctx.addItemDisplayTab then ctx.addItemDisplayTab(item, "bank") end
                        end
                    elseif colKey == "Icon" then
                        if ctx.drawItemIcon then
                            ctx.drawItemIcon(item.icon)
                        else
                            ImGui.Text(tostring(item.icon or 0))
                        end
                        if ImGui.IsItemHovered() then
                            local showItem = (ctx.getItemStatsForTooltip and ctx.getItemStatsForTooltip(item, "bank")) or item
                            local opts = { source = "bank", bag = item.bag, slot = item.slot }
                            local effects, w, h = ItemTooltip.prepareTooltipContent(showItem, ctx, opts)
                            opts.effects = effects
                            ItemTooltip.beginItemTooltip(w, h)
                            ImGui.Text("Stats")
                            ImGui.Separator()
                            ItemTooltip.renderStatsTooltip(showItem, ctx, opts)
                            ImGui.EndTooltip()
                        end
                        if ImGui.BeginPopupContextItem("ItemContextBankIcon_" .. rid) then
                            local isScriptItem = (item.name or ""):lower():find("script of", 1, true)
                            if isScriptItem then
                                if ImGui.MenuItem("Add All to Alt Currency") then
                                    local Me = mq.TLO and mq.TLO.Me
                                    local bn = Me and Me.Bank and Me.Bank(item.bag)
                                    local it = bn and bn.Item and bn.Item(item.slot)
                                    local stack = (it and it.Stack and it.Stack()) or 0
                                    if stack < 1 then
                                        if ctx.setStatusMessage then ctx.setStatusMessage("Item not found or stack empty.") end
                                    else
                                        ctx.uiState.pendingScriptConsume = {
                                            bag = item.bag, slot = item.slot, source = "bank",
                                            totalToConsume = stack, consumedSoFar = 0, nextClickAt = 0, itemName = item.name
                                        }
                                    end
                                end
                                if ImGui.MenuItem("Add Selected to Alt Currency") then
                                    local maxQty = (item.stackSize and item.stackSize > 0) and item.stackSize or 1
                                    ctx.uiState.pendingQuantityPickup = {
                                        bag = item.bag, slot = item.slot, source = "bank",
                                        maxQty = maxQty, itemName = item.name, intent = "script_consume"
                                    }
                                    ctx.uiState.pendingQuantityPickupTimeoutAt = mq.gettime() + constants.TIMING.QUANTITY_PICKUP_TIMEOUT_MS
                                    ctx.uiState.quantityPickerValue = "1"
                                    ctx.uiState.quantityPickerMax = maxQty
                                end
                            else
                            if ImGui.MenuItem("CoOp UI Item Display") then
                                if ctx.addItemDisplayTab then ctx.addItemDisplayTab(item, "bank") end
                            end
                            if ImGui.MenuItem("Inspect") then
                                if hasCursor then ctx.removeItemFromCursor()
                                else
                                    local Me = mq.TLO and mq.TLO.Me
                                    local bn = Me and Me.Bank and Me.Bank(item.bag)
                                    local sz = bn and bn.Container and bn.Container()
                                    local it = (bn and sz and sz > 0) and (bn.Item and bn.Item(item.slot)) or bn
                                    if it and it.ID and it.ID() and it.ID() > 0 and it.Inspect then it.Inspect() end
                                end
                            end
                            -- Reroll list: only for augments or mythicals; show Add or Remove per list
                            local rerollService = ctx.rerollService
                            if rerollService then
                                local nameKey = (item.name or ""):match("^%s*(.-)%s*$") or ""
                                local itemTypeTrim = (item.type or ""):match("^%s*(.-)%s*$")
                                local isAugment = (itemTypeTrim == "Augmentation")
                                local isMythicalEligible = nameKey:sub(1, 8) == "Mythical"
                                if nameKey ~= "" and (isAugment or isMythicalEligible) then
                                    ImGui.Separator()
                                    local augList = rerollService.getAugList and rerollService.getAugList() or {}
                                    local mythicalList = rerollService.getMythicalList and rerollService.getMythicalList() or {}
                                    local itemId = item.id or item.ID
                                    local onAugList, onMythicalList = false, false
                                    if itemId then
                                        for _, e in ipairs(augList) do if e.id == itemId then onAugList = true; break end end
                                        for _, e in ipairs(mythicalList) do if e.id == itemId then onMythicalList = true; break end end
                                    end
                                    if not onAugList then for _, e in ipairs(augList) do if (e.name or ""):match("^%s*(.-)%s*$") == nameKey then onAugList = true; break end end end
                                    if not onMythicalList then for _, e in ipairs(mythicalList) do if (e.name or ""):match("^%s*(.-)%s*$") == nameKey then onMythicalList = true; break end end end
                                    if isAugment then
                                        if onAugList then if ImGui.MenuItem("Remove from Augment List") then if itemId and ctx.removeFromRerollList then ctx.removeFromRerollList("aug", itemId) end end else if ImGui.MenuItem("Add to Augment List") then if ctx.requestAddToRerollList then ctx.requestAddToRerollList("aug", { bag = item.bag, slot = item.slot, id = itemId, name = item.name, source = "bank" }) end end end
                                    end
                                    if isMythicalEligible then
                                        if onMythicalList then if ImGui.MenuItem("Remove from Mythical List") then if itemId and ctx.removeFromRerollList then ctx.removeFromRerollList("mythical", itemId) end end else if ImGui.MenuItem("Add to Mythical List") then if ctx.requestAddToRerollList then ctx.requestAddToRerollList("mythical", { bag = item.bag, slot = item.slot, id = itemId, name = item.name, source = "bank" }) end end end
                                    end
                                end
                            end
                            end
                            ImGui.EndPopup()
                        end
                    elseif colKey == "Status" then
                        local statusText, willSell = "", false
                        if item.sellReason ~= nil and item.willSell ~= nil then
                            statusText = item.sellReason or "—"
                            willSell = item.willSell
                        elseif ctx.getSellStatusForItem then
                            statusText, willSell = ctx.getSellStatusForItem(item)
                        end
                        if statusText == "" then statusText = "—" end
                        local statusColor = willSell and ctx.theme.ToVec4(ctx.theme.Colors.Error) or ctx.theme.ToVec4(ctx.theme.Colors.Success)
                        if statusText == "Epic" then
                            statusText = "EpicQuest"
                            statusColor = ctx.theme.ToVec4(ctx.theme.Colors.EpicQuest or ctx.theme.Colors.Muted)
                        elseif statusText == "NoDrop" or statusText == "NoTrade" then
                            statusColor = ctx.theme.ToVec4(ctx.theme.Colors.Error)
                        elseif statusText == "RerollList" and ctx.theme.Colors.RerollList then
                            statusColor = ctx.theme.ToVec4(ctx.theme.Colors.RerollList)
                        end
                        ImGui.TextColored(statusColor, statusText)
                    else
                        -- All other columns use dynamic display text
                        ImGui.Text(ctx.sortColumns.getCellDisplayText(item, colKey, "Bank"))
                    end
                end
                
                ImGui.PopID()
                ::bank_continue::
            end
        end
        ImGui.EndTable()
    end
    
    ImGui.End()
end

return BankView
