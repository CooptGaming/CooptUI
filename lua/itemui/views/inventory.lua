--[[
    Inventory View - Gameplay view for inventory management
    
    Part of ItemUI Phase 5: View Extraction
    Renders the main inventory view with bag, slot, weight, flags
--]]

local mq = require('mq')
require('ImGui')
local ItemUtils = require('mq.ItemUtils')
local ItemTooltip = require('itemui.utils.item_tooltip')
local constants = require('itemui.constants')

local InventoryView = {}

-- Module interface: render inventory view content
-- Params: context table containing all necessary state and functions from init.lua
function InventoryView.render(ctx, bankOpen)
    -- Gameplay view: bag, slot, weight, flags; Shift+click to move when bank open
    ImGui.Text("Search:")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(180)
    ctx.uiState.searchFilterInv, _ = ImGui.InputText("##InvSearch", ctx.uiState.searchFilterInv)
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Filter items by name"); ImGui.EndTooltip() end
    ImGui.SameLine()
    if ImGui.Button("X##InvSearchClear2", ImVec2(22, 0)) then ctx.uiState.searchFilterInv = "" end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Clear search"); ImGui.EndTooltip() end
    ImGui.SameLine()
    ctx.renderRefreshButton(ctx, "Refresh##Inv", "Rescan inventory, bank (if open), sell list, and loot", function() ctx.refreshAllScans() end, { messageBefore = "Scanning..." })
    ImGui.SameLine()
    ctx.theme.TextMuted(string.format("Last: %s", os.date("%H:%M:%S", ctx.perfCache.lastScanTimeInv/1000)))
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Last inventory scan time"); ImGui.EndTooltip() end
    ImGui.Separator()
    
    if bankOpen then
        ctx.theme.TextSuccess("Bank open — Shift+click item to move to bank")
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Hold Shift and left-click an item to move it to bank (or to inventory from bank panel)"); ImGui.EndTooltip() end
    else
        -- Current items / total bag (container) spaces (cached; invalidated on scan/move)
        local used = #ctx.inventoryItems
        if ctx.perfCache.invTotalSlots == nil then
            local n = 0
            local Me = mq.TLO and mq.TLO.Me
            if Me and Me.Inventory then
                for i = 1, 10 do
                    local pack = Me.Inventory("pack" .. i)
                    if pack and pack.Container then n = n + (tonumber(pack.Container()) or 0) end
                end
            end
            ctx.perfCache.invTotalSlots = (n > 0) and n or 80
        end
        local totalSlots = ctx.perfCache.invTotalSlots
        if ctx.perfCache.invTotalValue == nil then
            local v = 0
            for _, it in ipairs(ctx.inventoryItems) do v = v + (it.totalValue or 0) end
            ctx.perfCache.invTotalValue = v
        end
        local totalValue = ctx.perfCache.invTotalValue
        ctx.theme.TextInfo(string.format("Items: %d / %d", used, totalSlots))
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Items in bags / total bag and container slots"); ImGui.EndTooltip() end
        if ImGui.IsItemHovered() and ctx.hasItemOnCursor() and ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
            if ctx.putCursorInBags then ctx.putCursorInBags() end
        end
        ImGui.SameLine()
        ctx.theme.TextMuted(string.format("Total value: %s", ItemUtils.formatValue(totalValue)))
        if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Total vendor value of all items in inventory"); ImGui.EndTooltip() end
        if ImGui.IsItemHovered() and ctx.hasItemOnCursor() and ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
            if ctx.putCursorInBags then ctx.putCursorInBags() end
        end
    end
    ImGui.Separator()
    
    -- Build fixed columns list (from config; ImGui SaveSettings handles sort/order)
    local visibleCols = ctx.getFixedColumns("Inventory")
    local nCols = #visibleCols
    if nCols == 0 then nCols = 1; visibleCols = {{key = "Name", label = "Name", numeric = false}} end
    
    if ImGui.BeginTable("ItemUI_InvGameplay", nCols, ctx.uiState.tableFlags) then
        -- Use a stable hash of the column key as UserID so ImGui can persist across visibility changes
        local function simpleHash(str)
            local h = 0
            for i = 1, #str do
                h = (h * 31 + string.byte(str, i)) % 2147483647
            end
            return h
        end
        -- Setup columns with stable user IDs based on column key hash or index
        local sortCol = (ctx.sortState.invColumn and type(ctx.sortState.invColumn) == "string" and ctx.sortState.invColumn) or "Name"
        for i, colDef in ipairs(visibleCols) do
            local flags = (colDef.key == "Name") and ImGuiTableColumnFlags.WidthStretch or ImGuiTableColumnFlags.WidthFixed
            
            if colDef.key == sortCol then
                flags = bit32.bor(flags, ImGuiTableColumnFlags.DefaultSort)
            end
            
            local width = 0
            if colDef.key ~= "Name" then
                if ctx.columnAutofitWidths["Inventory"][colDef.key] then
                    width = ctx.columnAutofitWidths["Inventory"][colDef.key]
                else
                    if colDef.key == "Value" then width = 70
                    elseif colDef.key == "Weight" then width = 55
                    elseif colDef.key == "Type" then width = 80
                    elseif colDef.key == "Bag" then width = 40
                    elseif colDef.key == "Clicky" then width = 150
                    elseif colDef.key == "Icon" then width = 28
                    elseif colDef.key == "Slot" then width = 40
                    elseif colDef.key == "Stack" then width = 50
                    elseif colDef.key == "Status" then width = 100
                    elseif colDef.key == "Acquired" then width = 56
                    else width = 80 end
                end
            end
            local userID = simpleHash(colDef.key)
            ImGui.TableSetupColumn(colDef.label, flags, width, userID)
        end
        ImGui.TableSetupScrollFreeze(0, 1)
        
        -- Build column mapping: UserID (hash of column key) -> column key
        local colKeyByUserID = {}
        for i, colDef in ipairs(visibleCols) do
            colKeyByUserID[simpleHash(colDef.key)] = colDef.key
        end
        
        -- Handle sort clicks
        local sortSpecs = ImGui.TableGetSortSpecs()
        if sortSpecs and sortSpecs.SpecsDirty and sortSpecs.SpecsCount > 0 then
            local spec = sortSpecs:Specs(1)
            if spec then
                -- Use ColumnUserID to find which column was clicked (handles reordering)
                local userID = spec.ColumnUserID
                local colKey = colKeyByUserID[userID]
                if colKey then
                    ctx.sortState.invColumn = colKey
                    ctx.sortState.invDirection = spec.SortDirection
                    ctx.scheduleLayoutSave()
                    ctx.flushLayoutSave()
                end
            end
            sortSpecs.SpecsDirty = false
        end
        
        -- Capture header rect before/after TableHeadersRow for header-only right-click
        local headerTop = ImGui.GetCursorScreenPosVec and ImGui.GetCursorScreenPosVec()
        -- Render headers
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
            ImGui.OpenPopup("ColumnMenu_Inventory")
        end
        
        if ImGui.BeginPopup("ColumnMenu_Inventory") then
            ImGui.Text("Columns (changes apply on next open)")
            ImGui.Separator()
            for _, colDef in ipairs(ctx.availableColumns["Inventory"] or {}) do
                local inFixed = ctx.isColumnInFixedSet("Inventory", colDef.key)
                if ImGui.MenuItem(colDef.label, "", inFixed) then
                    ctx.toggleFixedColumn("Inventory", colDef.key)
                    ctx.setStatusMessage("Column changes apply when you reopen CoOpt UI Inventory Companion")
                end
            end
            ImGui.Separator()
            if ImGui.MenuItem("Autofit Columns") then
                ctx.autofitColumns("Inventory", ctx.inventoryItems, visibleCols)
            end
            ImGui.EndPopup()
        end
        
        local hasCursor = ctx.hasItemOnCursor()
        local lp = ctx.uiState.lastPickup
        local filtered = {}
        for _, it in ipairs(ctx.inventoryItems) do
            if ctx.uiState.searchFilterInv == "" or (it.name or ""):lower():find((ctx.uiState.searchFilterInv or ""):lower(), 1, true) then
                if not ctx.shouldHideRowForCursor(it, "inv") then
                    table.insert(filtered, it)
                end
            end
        end
        
        -- Sort cache (Phase 3: shared getSortedList helper)
        local sortKey = (ctx.sortState.invColumn and type(ctx.sortState.invColumn) == "string" and ctx.sortState.invColumn) or "Name"
        local sortDir = ctx.sortState.invDirection or ImGuiSortDirection.Ascending
        local filterStr = ctx.uiState.searchFilterInv or ""
        local hidingNow = not not (lp and lp.source == "inv" and lp.bag and lp.slot)
        local validity = {
            filter = filterStr,
            hidingSlot = hidingNow,
            fullListLen = #ctx.inventoryItems,
            scanTime = ctx.perfCache.lastScanTimeInv,
        }
        filtered = ctx.getSortedList(ctx.perfCache.inv, filtered, sortKey, sortDir, validity, "Inventory", ctx.sortColumns)

        local nInv = #filtered
        local clipperInv = ImGuiListClipper.new()
        clipperInv:Begin(nInv)
        while clipperInv:Step() do
            for i = clipperInv.DisplayStart + 1, clipperInv.DisplayEnd do
                local item = filtered[i]
                if not item then goto continue end
                ImGui.TableNextRow()
                local loc = ctx.uiState.itemDisplayLocateRequest
                if loc and loc.source == "inv" and loc.bag == item.bag and loc.slot == item.slot then
                    ImGui.TableSetBgColor(ImGuiTableBgTarget.RowBg0, ImGui.GetColorU32(ImVec4(0.25, 0.45, 0.75, 0.45)))
                end
                local rid = "inv_" .. item.bag .. "_" .. item.slot
                ImGui.PushID(rid)
                for _, colDef in ipairs(visibleCols) do
                    ImGui.TableNextColumn()
                    local colKey = colDef.key
                    if colKey == "Name" then
                        local dn = item.name or ""
                        if (item.stackSize or 1) > 1 then dn = dn .. string.format(" (x%d)", item.stackSize) end
                        ImGui.Selectable(dn, false, ImGuiSelectableFlags.None, ImVec2(0,0))
                        if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
                            if ImGui.GetIO().KeyShift and bankOpen then
                                ctx.moveInvToBank(item.bag, item.slot)
                            elseif hasCursor then
                                ctx.dropAtSlot(item.bag, item.slot, "inv")
                            elseif not hasCursor then
                                if item.stackSize and item.stackSize > 1 then
                                    ctx.uiState.pendingQuantityPickup = {
                                        bag = item.bag,
                                        slot = item.slot,
                                        source = "inv",
                                        maxQty = item.stackSize,
                                        itemName = item.name
                                    }
                                    ctx.uiState.pendingQuantityPickupTimeoutAt = mq.gettime() + constants.TIMING.QUANTITY_PICKUP_TIMEOUT_MS
                                    ctx.uiState.quantityPickerValue = tostring(item.stackSize)
                                    ctx.uiState.quantityPickerMax = item.stackSize
                                else
                                    ctx.pickupFromSlot(item.bag, item.slot, "inv")
                                end
                            end
                        end
                        if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Right) then
                            if ctx.addItemDisplayTab then ctx.addItemDisplayTab(item, "inv") end
                        end
                    elseif colKey == "Clicky" then
                        local cid = ctx.getItemSpellId(item, "Clicky")
                        if cid > 0 then
                            local spellName = ctx.getSpellName(cid) or "Unknown"
                            local timerReady = ctx.getTimerReady(item.bag, item.slot)
                            local isOnCooldown = timerReady and timerReady > 0
                            if isOnCooldown then
                                ImGui.PushStyleColor(ImGuiCol.Text, ctx.theme.ToVec4(ctx.theme.Colors.Error))
                            else
                                ImGui.PushStyleColor(ImGuiCol.Text, ctx.theme.ToVec4(ctx.theme.Colors.Success))
                            end
                            ImGui.Selectable(spellName, false, ImGuiSelectableFlags.None, ImVec2(0, 0))
                            ImGui.PopStyleColor()
                            if ImGui.IsItemHovered() and ImGui.IsMouseReleased(ImGuiMouseButton.Right) then
                                if not isOnCooldown then
                                    mq.cmdf('/itemnotify in pack%d %d rightmouseup', item.bag, item.slot)
                                end
                            end
                            if ImGui.IsItemHovered() then
                                ImGui.BeginTooltip()
                                local desc = ctx.getSpellDescription(cid)
                                if desc and desc ~= "" then
                                    ImGui.TextWrapped(desc)
                                    ImGui.Spacing()
                                end
                                if isOnCooldown then
                                    ImGui.Text(string.format("On cooldown (%d seconds remaining)", timerReady))
                                else
                                    ImGui.Text("Right-click to activate clicky effect")
                                end
                                ImGui.EndTooltip()
                            end
                        else
                            ImGui.PushStyleColor(ImGuiCol.Text, ctx.theme.ToVec4(ctx.theme.Colors.Muted))
                            ImGui.Selectable("No", false, ImGuiSelectableFlags.None, ImVec2(0, 0))
                            ImGui.PopStyleColor()
                        end
                    elseif colKey == "Icon" then
                        if ctx.drawItemIcon then
                            ctx.drawItemIcon(item.icon)
                        else
                            ImGui.Text(tostring(item.icon or 0))
                        end
                        if ImGui.IsItemHovered() then
                            local showItem = (ctx.getItemStatsForTooltip and ctx.getItemStatsForTooltip(item, "inv")) or item
                            local opts = { source = "inv", bag = item.bag, slot = item.slot }
                            local effects, w, h = ItemTooltip.prepareTooltipContent(showItem, ctx, opts)
                            opts.effects = effects
                            ItemTooltip.beginItemTooltip(w, h)
                            ImGui.Text("Stats")
                            ImGui.Separator()
                            ItemTooltip.renderStatsTooltip(showItem, ctx, opts)
                            ImGui.EndTooltip()
                        end
                        -- Right-click on icon: context menu for Inspect, Keep, Always sell, augment lists.
                        -- Status and menu use row state when set; list changes must update rows (updateSellStatusForItemName or computeAndAttachSellStatus) so all views stay in sync.
                        if ImGui.BeginPopupContextItem("ItemContextInv_" .. rid) then
                            local inKeep, inJunk = false, false
                            if item.inKeep ~= nil and item.inJunk ~= nil then
                                inKeep, inJunk = item.inKeep, item.inJunk
                            elseif ctx.getSellStatusForItem then
                                local _, _, k, j = ctx.getSellStatusForItem(item)
                                inKeep, inJunk = k, j
                            end
                            local nameKey = (item.name or ""):match("^%s*(.-)%s*$")
                            local itemTypeTrim = (item.type or ""):match("^%s*(.-)%s*$")
                            local isAugment = (itemTypeTrim == "Augmentation")
                            local inAugmentAlwaysSell = isAugment and ctx.augmentLists and ctx.augmentLists.isInAugmentAlwaysSellList and ctx.augmentLists.isInAugmentAlwaysSellList(nameKey)
                            local inAugmentNeverLoot = isAugment and ctx.augmentLists and ctx.augmentLists.isInAugmentNeverLootList and ctx.augmentLists.isInAugmentNeverLootList(nameKey)

                            if ImGui.MenuItem("Inspect") then
                                if hasCursor then
                                    ctx.removeItemFromCursor()
                                else
                                    local Me = mq.TLO and mq.TLO.Me
                                    local pack = Me and Me.Inventory and Me.Inventory("pack" .. item.bag)
                                    local tlo = pack and pack.Item and pack.Item(item.slot)
                                    if tlo and tlo.ID and tlo.ID() and tlo.ID() > 0 and tlo.Inspect then tlo.Inspect() end
                                end
                            end
                            if ImGui.MenuItem("CoOp UI Item Display") then
                                if ctx.addItemDisplayTab then ctx.addItemDisplayTab(item, "inv") end
                            end
                            ImGui.Separator()
                            if ctx.applySellListChange then
                                if inKeep then
                                    if ImGui.MenuItem("Remove from Keep list") then ctx.applySellListChange(item.name, false, inJunk) end
                                else
                                    if ImGui.MenuItem("Add to Keep list") then ctx.applySellListChange(item.name, true, false) end
                                end
                                if inJunk then
                                    if ImGui.MenuItem("Remove from Always sell list") then ctx.applySellListChange(item.name, inKeep, false) end
                                else
                                    if ImGui.MenuItem("Add to Always sell list") then ctx.applySellListChange(item.name, false, true) end
                                end
                            end
                            if isAugment and ctx.augmentLists and nameKey ~= "" then
                                ImGui.Separator()
                                if inAugmentAlwaysSell then
                                    if ImGui.MenuItem("Remove from Augment Always sell") then
                                        if ctx.augmentLists.removeFromAugmentAlwaysSellList(nameKey) then
                                            ctx.updateSellStatusForItemName(item.name, inKeep, inJunk)
                                            if ctx.storage and ctx.inventoryItems then ctx.storage.saveInventory(ctx.inventoryItems) end
                                        end
                                    end
                                else
                                    if ImGui.MenuItem("Add to Augment Always sell") then
                                        if ctx.augmentLists.addToAugmentAlwaysSellList(nameKey) then
                                            ctx.updateSellStatusForItemName(item.name, inKeep, inJunk)
                                            if ctx.storage and ctx.inventoryItems then ctx.storage.saveInventory(ctx.inventoryItems) end
                                        end
                                    end
                                end
                                if inAugmentNeverLoot then
                                    if ImGui.MenuItem("Remove from Augment Never loot") then
                                        if ctx.augmentLists.removeFromAugmentNeverLootList(nameKey) then
                                            ctx.updateSellStatusForItemName(item.name, inKeep, inJunk)
                                            if ctx.storage and ctx.inventoryItems then ctx.storage.saveInventory(ctx.inventoryItems) end
                                        end
                                    end
                                else
                                    if ImGui.MenuItem("Add to Augment Never loot") then
                                        if ctx.augmentLists.addToAugmentNeverLootList(nameKey) then
                                            ctx.updateSellStatusForItemName(item.name, inKeep, inJunk)
                                            if ctx.storage and ctx.inventoryItems then ctx.storage.saveInventory(ctx.inventoryItems) end
                                        end
                                    end
                                end
                            end
                            ImGui.Separator()
                            ImGui.Dummy(ImVec2(0, 6))
                            ImGui.PushStyleColor(ImGuiCol.Text, ctx.theme.ToVec4(ctx.theme.Colors.Error))
                            if ImGui.MenuItem("Delete") then
                                local stackSize = (item.stackSize and item.stackSize > 0) and item.stackSize or 1
                                if ctx.getSkipConfirmDelete and ctx.getSkipConfirmDelete() then
                                    ctx.requestDestroyItem(item.bag, item.slot, item.name, stackSize)
                                else
                                    ctx.setPendingDestroy({ bag = item.bag, slot = item.slot, name = item.name or "", stackSize = stackSize })
                                end
                            end
                            ImGui.PopStyleColor()
                            ImGui.EndPopup()
                        end
                    elseif colKey == "Status" then
                        -- Prefer row state (updated by list changes) so Status updates immediately; fallback to getSellStatusForItem
                        local statusText, willSell = "", false
                        if item.sellReason ~= nil and item.willSell ~= nil then
                            statusText = item.sellReason or "—"
                            willSell = item.willSell
                        elseif ctx.getSellStatusForItem then
                            statusText, willSell = ctx.getSellStatusForItem(item)
                        end
                        if statusText == "" then statusText = "—" end
                        local statusColor = willSell and ctx.theme.ToVec4(ctx.theme.Colors.Warning) or ctx.theme.ToVec4(ctx.theme.Colors.Success)
                        if statusText == "Epic" then
                            statusText = "EpicQuest"
                            statusColor = ctx.theme.ToVec4(ctx.theme.Colors.EpicQuest or ctx.theme.Colors.Muted)
                        elseif statusText == "NoDrop" or statusText == "NoTrade" then
                            statusColor = ctx.theme.ToVec4(ctx.theme.Colors.Error)
                        end
                        ImGui.TextColored(statusColor, statusText)
                    else
                        ImGui.Text(ctx.sortColumns.getCellDisplayText(item, colKey, "Inventory"))
                    end
                end
                ImGui.PopID()
            ::continue::
            end
        end
        ImGui.EndTable()
    end
end

return InventoryView
