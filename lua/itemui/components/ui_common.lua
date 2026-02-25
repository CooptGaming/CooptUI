--[[
    Shared UI helpers (Phase 6).
    Single path for refresh buttons across Inventory, Sell, Bank, Augments, etc.
    Task 2.1: Shared right-click context menu for all item views.
--]]

require('ImGui')
local mq = require('mq')
local constants = require('itemui.constants')

local M = {}

--- Return ImVec4 for Name column sell-status color: green = Keep, red = Will Sell, white = Neutral.
--- Uses ctx.getSellStatusForItem(item) when item.willSell/inKeep not set; otherwise row state.
--- @param ctx table with theme, getSellStatusForItem
--- @param item table row with optional willSell, inKeep (or from getSellStatusForItem)
--- @return ImVec4 color for ImGui.TextColored or PushStyleColor(ImGuiCol.Text, color)
function M.getSellStatusNameColor(ctx, item)
    if not ctx or not item then return ImVec4(1, 1, 1, 1) end
    local willSell, inKeep = item.willSell, item.inKeep
    if willSell == nil or inKeep == nil then
        local ok, st, ws, k = pcall(function()
            if ctx.getSellStatusForItem then
                local statusText, w, inKeepVal, inJunkVal = ctx.getSellStatusForItem(item)
                return statusText, w, inKeepVal
            end
            return "", false, false
        end)
        if ok and ws ~= nil then willSell = ws; inKeep = k end
    end
    if willSell then
        return ctx.theme and ctx.theme.ToVec4(ctx.theme.Colors.Error) or ImVec4(0.9, 0.25, 0.25, 1)
    end
    if inKeep then
        return ctx.theme and ctx.theme.ToVec4(ctx.theme.Colors.Success) or ImVec4(0.25, 0.75, 0.35, 1)
    end
    return ImVec4(1, 1, 1, 1)
end

--- Draw a Refresh button with tooltip and optional status messages. Call onRefresh() on click.
--- @param ctx table context (setStatusMessage, etc.)
--- @param id string unique button id (e.g. "Refresh##Inv")
--- @param tooltip string hover tooltip
--- @param onRefresh function() called on click
--- @param opts table optional: width (number), messageBefore (string), messageAfter (string)
function M.renderRefreshButton(ctx, id, tooltip, onRefresh, opts)
    opts = opts or {}
    local w = opts.width or 70
    if ImGui.Button(id, ImVec2(w, 0)) then
        if opts.messageBefore and ctx.setStatusMessage then ctx.setStatusMessage(opts.messageBefore) end
        onRefresh()
        if opts.messageAfter and ctx.setStatusMessage then ctx.setStatusMessage(opts.messageAfter) end
    end
    if tooltip and tooltip ~= "" and ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text(tooltip)
        ImGui.EndTooltip()
    end
end

--- Run game Inspect on the item (TLO) based on source.
local function doInspect(ctx, item, source)
    if not ctx or not item then return end
    if source == "inv" or source == "sell" or source == "augments" then
        local Me = mq.TLO and mq.TLO.Me
        local pack = Me and Me.Inventory and Me.Inventory("pack" .. (item.bag or 0))
        local tlo = pack and pack.Item and pack.Item(item.slot)
        if tlo and tlo.ID and tlo.ID() and tlo.ID() > 0 and tlo.Inspect then tlo.Inspect() end
    elseif source == "bank" then
        local Me = mq.TLO and mq.TLO.Me
        local bn = Me and Me.Bank and Me.Bank(item.bag)
        local sz = bn and bn.Container and bn.Container()
        local it = (bn and sz and sz > 0) and (bn.Item and bn.Item(item.slot)) or bn
        if it and it.ID and it.ID() and it.ID() > 0 and it.Inspect then it.Inspect() end
    elseif source == "equipped" and item.slot ~= nil and ctx.getEquipmentSlotNameForItemNotify then
        local Me = mq.TLO and mq.TLO.Me
        local slotName = ctx.getEquipmentSlotNameForItemNotify(item.slot)
        if slotName and Me and Me.Inventory then
            local inv = Me.Inventory(slotName)
            local slotIt = inv and inv.Item and inv.Item(1)
            if slotIt and slotIt.ID and slotIt.ID() and slotIt.ID() > 0 and slotIt.Inspect then slotIt.Inspect() end
        end
    end
end

--- Shared right-click context menu for item views. Call after drawing the item (icon) so
--- the last item is the popup trigger. Also supports opening via OpenPopup(popupId) from name column.
--- opts.source: "inv"|"bank"|"sell"|"equipped"|"augments"|"reroll".
--- opts.popupId must be unique per row (e.g. "ItemContextInv_"..rid). opts.bankOpen, opts.hasCursor.
function M.renderItemContextMenu(ctx, item, opts)
    if not ctx or not item or not opts or not opts.popupId then return end
    local source = opts.source or "inv"
    local bankOpen = opts.bankOpen or false
    local hasCursor = opts.hasCursor or false

    local opened = ImGui.BeginPopupContextItem(opts.popupId) or ImGui.BeginPopup(opts.popupId)
    if not opened then return end

    local nameKey = (item.name or ""):match("^%s*(.-)%s*$") or ""
    local itemTypeTrim = (item.type or ""):match("^%s*(.-)%s*$") or ""
    local isAugment = (itemTypeTrim == "Augmentation")
    local isScriptItem = (item.name or ""):lower():find("script of", 1, true)

    if isScriptItem then
        -- Script items: only Alt Currency options
        if source == "inv" or source == "augments" then
            if ImGui.MenuItem("Add All to Alt Currency") then
                local Me = mq.TLO and mq.TLO.Me
                local pack = Me and Me.Inventory and Me.Inventory("pack" .. (item.bag or 0))
                local it = pack and pack.Item and pack.Item(item.slot)
                local stack = (it and it.Stack and it.Stack()) or 0
                if stack < 1 then
                    if ctx.setStatusMessage then ctx.setStatusMessage("Item not found or stack empty.") end
                else
                    ctx.uiState.pendingScriptConsume = {
                        bag = item.bag, slot = item.slot, source = source,
                        totalToConsume = stack, consumedSoFar = 0, nextClickAt = 0, itemName = item.name
                    }
                end
            end
        elseif source == "bank" then
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
        end
        if ImGui.MenuItem("Add Selected to Alt Currency") then
            local maxQty = (item.stackSize and item.stackSize > 0) and item.stackSize or 1
            ctx.uiState.pendingQuantityPickup = {
                bag = item.bag, slot = item.slot, source = source == "augments" and "inv" or source,
                maxQty = maxQty, itemName = item.name, intent = "script_consume"
            }
            ctx.uiState.pendingQuantityPickupTimeoutAt = mq.gettime() + (constants and constants.TIMING and constants.TIMING.QUANTITY_PICKUP_TIMEOUT_MS or 60000)
            ctx.uiState.quantityPickerValue = "1"
            ctx.uiState.quantityPickerMax = maxQty
        end
        ImGui.EndPopup()
        return
    end

    -- Inspect (game window)
    if ImGui.MenuItem("Inspect") then
        if hasCursor and ctx.removeItemFromCursor then ctx.removeItemFromCursor()
        else doInspect(ctx, item, source) end
    end
    if ImGui.MenuItem("CoOp UI Item Display") then
        if ctx.addItemDisplayTab then ctx.addItemDisplayTab(item, source) end
    end

    -- Move to Bank / Move to Inventory
    if (source == "inv" or source == "sell" or source == "augments") and bankOpen and ctx.moveInvToBank and item.bag and item.slot then
        ImGui.Separator()
        if ImGui.MenuItem("Move to Bank") then ctx.moveInvToBank(item.bag, item.slot) end
    end
    if source == "bank" and bankOpen and ctx.moveBankToInv and item.bag and item.slot then
        ImGui.Separator()
        if ImGui.MenuItem("Move to Inventory") then ctx.moveBankToInv(item.bag, item.slot) end
    end

    -- Keep list / Always sell list (inv, sell, bank, augments, reroll when item has location)
    local sellListSource = (source == "inv" or source == "sell" or source == "bank" or source == "augments" or source == "reroll")
    if sellListSource and ctx.applySellListChange then
        local inKeep, inJunk = false, false
        if item.inKeep ~= nil and item.inJunk ~= nil then
            inKeep, inJunk = item.inKeep, item.inJunk
        elseif ctx.getSellStatusForItem then
            local _, _, k, j = ctx.getSellStatusForItem(item)
            inKeep, inJunk = k, j
        end
        ImGui.Separator()
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

    -- Augment Always sell / Augment Never loot (augments only)
    if isAugment and nameKey ~= "" and ctx.augmentLists then
        local inAugmentAlwaysSell = ctx.augmentLists.isInAugmentAlwaysSellList and ctx.augmentLists.isInAugmentAlwaysSellList(nameKey)
        local inAugmentNeverLoot = ctx.augmentLists.isInAugmentNeverLootList and ctx.augmentLists.isInAugmentNeverLootList(nameKey)
        ImGui.Separator()
        if inAugmentAlwaysSell then
            if ImGui.MenuItem("Remove from Augment Always sell") then
                if ctx.augmentLists.removeFromAugmentAlwaysSellList(nameKey) then
                    local inKeep, inJunk = item.inKeep, item.inJunk
                    if ctx.getSellStatusForItem then local _, _, k, j = ctx.getSellStatusForItem(item); inKeep, inJunk = k, j end
                    if ctx.updateSellStatusForItemName then ctx.updateSellStatusForItemName(item.name, inKeep, inJunk) end
                    if ctx.storage and ctx.inventoryItems then ctx.storage.saveInventory(ctx.inventoryItems) end
                end
            end
        else
            if ImGui.MenuItem("Add to Augment Always sell") then
                if ctx.augmentLists.addToAugmentAlwaysSellList(nameKey) then
                    local inKeep, inJunk = item.inKeep, item.inJunk
                    if ctx.getSellStatusForItem then local _, _, k, j = ctx.getSellStatusForItem(item); inKeep, inJunk = k, j end
                    if ctx.updateSellStatusForItemName then ctx.updateSellStatusForItemName(item.name, inKeep, inJunk) end
                    if ctx.storage and ctx.inventoryItems then ctx.storage.saveInventory(ctx.inventoryItems) end
                end
            end
        end
        if inAugmentNeverLoot then
            if ImGui.MenuItem("Remove from Augment Never loot") then
                if ctx.augmentLists.removeFromAugmentNeverLootList(nameKey) then
                    local inKeep, inJunk = item.inKeep, item.inJunk
                    if ctx.getSellStatusForItem then local _, _, k, j = ctx.getSellStatusForItem(item); inKeep, inJunk = k, j end
                    if ctx.updateSellStatusForItemName then ctx.updateSellStatusForItemName(item.name, inKeep, inJunk) end
                    if ctx.storage and ctx.inventoryItems then ctx.storage.saveInventory(ctx.inventoryItems) end
                end
            end
        else
            if ImGui.MenuItem("Add to Augment Never loot") then
                if ctx.augmentLists.addToAugmentNeverLootList(nameKey) then
                    local inKeep, inJunk = item.inKeep, item.inJunk
                    if ctx.getSellStatusForItem then local _, _, k, j = ctx.getSellStatusForItem(item); inKeep, inJunk = k, j end
                    if ctx.updateSellStatusForItemName then ctx.updateSellStatusForItemName(item.name, inKeep, inJunk) end
                    if ctx.storage and ctx.inventoryItems then ctx.storage.saveInventory(ctx.inventoryItems) end
                end
            end
        end
    end

    -- Reroll lists: Augment List / Mythical List
    local isMythicalEligible = nameKey:sub(1, 8) == "Mythical"
    local rerollService = ctx.rerollService
    if rerollService and nameKey ~= "" and (isAugment or isMythicalEligible) then
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
        ImGui.Separator()
        if isAugment then
            if onAugList then
                if ImGui.MenuItem("Remove from Augment List") then
                    if itemId and ctx.removeFromRerollList then ctx.removeFromRerollList("aug", itemId) end
                end
            else
                if ImGui.MenuItem("Add to Augment List") then
                    if ctx.requestAddToRerollList then
                        local payload = (source == "bank") and { bag = item.bag, slot = item.slot, id = itemId, name = item.name, source = "bank" } or item
                        ctx.requestAddToRerollList("aug", payload)
                    end
                end
            end
        end
        if isMythicalEligible then
            if onMythicalList then
                if ImGui.MenuItem("Remove from Mythical List") then
                    if itemId and ctx.removeFromRerollList then ctx.removeFromRerollList("mythical", itemId) end
                end
            else
                if ImGui.MenuItem("Add to Mythical List") then
                    if ctx.requestAddToRerollList then
                        local payload = (source == "bank") and { bag = item.bag, slot = item.slot, id = itemId, name = item.name, source = "bank" } or item
                        ctx.requestAddToRerollList("mythical", payload)
                    end
                end
            end
        end
    end

    -- Reroll view only: Remove from list
    if source == "reroll" and opts.onRemoveFromRerollList and opts.rerollEntryId then
        ImGui.Separator()
        if ImGui.MenuItem("Remove from list") then opts.onRemoveFromRerollList(opts.rerollEntryId) end
    end

    -- Destroy
    local canDestroy = (source == "inv" or source == "bank" or source == "sell" or source == "augments" or source == "reroll") and item.bag ~= nil and item.slot ~= nil
    if canDestroy and ctx.setPendingDestroy and ctx.requestDestroyItem then
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
    end

    ImGui.EndPopup()
end

return M
