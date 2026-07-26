--[[
    Shared UI helpers (Phase 6).
    Single path for refresh buttons across Inventory, Sell, Bank, Augments, etc.
    Task 2.1: Shared right-click context menu for all item views.
--]]

require('ImGui')
local mq = require('mq')
local constants = require('itemui.constants')
local registry = require('itemui.core.registry')

local M = {}

--- Top-right "Lock" checkbox for companion windows. Call right after ImGui.Begin
--- (before other content): draws at the window's top-right, then restores the
--- cursor so the caller's layout is unaffected. Locked windows survive ESC's
--- LIFO close AND every close-all gesture (Shift+Q, /itemui hide, hub X);
--- they close only via their own X or by unticking Lock.
function M.renderWindowLock(ctx, id)
    local cx, cy = ImGui.GetCursorPos()
    -- Right-align by MEASURED width, never past (windowWidth - WindowPadding.x).
    -- A fixed offset here once let the checkbox overshoot the content edge; in an
    -- AlwaysAutoResize window (Command Center) auto-fit then grows the window to the
    -- overshoot every frame — the window widens forever.
    local style = ImGui.GetStyle and ImGui.GetStyle() or nil
    local innerX = (style and style.ItemInnerSpacing and style.ItemInnerSpacing.x) or 4
    local padX = (style and style.WindowPadding and style.WindowPadding.x) or 8
    local boxW = (ImGui.GetFrameHeight and ImGui.GetFrameHeight()) or 20
    local textW = ImGui.CalcTextSize("Lock") or 28
    local x = math.floor(ImGui.GetWindowWidth() - padX - (boxW + innerX + textW))
    if x < cx then x = cx end
    ImGui.SetCursorPos(x, cy)
    local locked = registry.isPinned(id)
    local v = ImGui.Checkbox("Lock##winlock_" .. id, locked)
    if v ~= locked then
        registry.setPinned(id, v)
        if ctx and ctx.scheduleLayoutSave then ctx.scheduleLayoutSave() end
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        local keyName = (ctx and ctx.getItemUIToggleKeyDisplay and ctx.getItemUIToggleKeyDisplay()) or "Shift+Q"
        ImGui.Text(string.format("Lock this window: it stays up while you play. ESC, the toggle keybind (%s),", keyName))
        ImGui.Text("/itemui hide, and the hub's X all leave it open. Close it with its own X, or untick Lock.")
        ImGui.EndTooltip()
    end
    ImGui.SetCursorPos(cx, cy)
end

--- Return ImVec4 for Name column sell-status color: green = Keep, red = Will Sell, white = Neutral.
--- Uses ctx.getSellStatusForItem(item) when item.willSell/inKeep not set; otherwise row state.
--- @param ctx table with theme, getSellStatusForItem
--- @param item table row with optional willSell, inKeep (or from getSellStatusForItem)
--- @return ImVec4 color for ImGui.TextColored or PushStyleColor(ImGuiCol.Text, color)
function M.getSellStatusNameColor(ctx, item)
    if not ctx or not item then return ImVec4(1, 1, 1, 1) end
    -- Fall back to a live status computation only when willSell is unknown.
    -- Stored rows persist inKeep only when true, so nil inKeep just means "not kept".
    local willSell, inKeep = item.willSell, item.inKeep
    if willSell == nil then
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

--- Format a sellReason string for display and return the display text + color.
--- Centralizes the Epic→EpicQuest rename and status-specific coloring
--- so views don't duplicate this logic.
--- @param reason string raw sellReason or statusText (e.g. "Epic", "NoDrop", "RerollList")
--- @param willSell boolean whether the item will be sold
--- @param theme table ctx.theme with ToVec4 and Colors
--- @return string displayText, ImVec4 color
function M.formatSellStatus(reason, willSell, theme)
    local text = (reason and reason ~= "") and reason or "\xe2\x80\x94"
    local color = willSell and theme.ToVec4(theme.Colors.Error) or theme.ToVec4(theme.Colors.Success)
    if text == "Epic" then
        text = "EpicQuest"
        color = theme.ToVec4(theme.Colors.EpicQuest or theme.Colors.Muted)
    elseif text == "Favorites" then
        -- rules.lua's raw reason predates the "Clickies" branding
        text = "ClickyList"
    elseif text == "NoDrop" or text == "NoTrade" then
        color = theme.ToVec4(theme.Colors.Error)
    elseif text == "RerollList" and theme.Colors.RerollList then
        color = theme.ToVec4(theme.Colors.RerollList)
    end
    return text, color
end

--- Resolve sellReason/willSell from item row state or fallback to getSellStatusForItem.
--- Returns displayText, color ready for ImGui.TextColored.
--- @param ctx table with theme, getSellStatusForItem
--- @param item table with optional sellReason, willSell
--- @return string displayText, ImVec4 color
function M.resolveSellStatusDisplay(ctx, item)
    local reason, willSell = "", false
    if item.sellReason ~= nil and item.willSell ~= nil then
        reason = item.sellReason or ""
        willSell = item.willSell
    elseif ctx.getSellStatusForItem then
        reason, willSell = ctx.getSellStatusForItem(item)
    end
    return M.formatSellStatus(reason, willSell, ctx.theme)
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
    local opened = ImGui.BeginPopupContextItem(opts.popupId) or ImGui.BeginPopup(opts.popupId)
    if not opened then return end
    M.renderItemContextMenuContents(ctx, item, opts)
    ImGui.EndPopup()
end

--- Menu CONTENTS only (no popup begin/end) - for hosts that manage the popup
--- themselves (e.g. native_hover's Shift+Right-click menu over native slots).
function M.renderItemContextMenuContents(ctx, item, opts)
    if not ctx or not item or not opts then return end
    local source = opts.source or "inv"
    local bankOpen = opts.bankOpen or false
    local hasCursor = opts.hasCursor or false

    local nameKey = (item.name or ""):match("^%s*(.-)%s*$") or ""
    local itemTypeTrim = (item.type or ""):match("^%s*(.-)%s*$") or ""
    local isAugment = (itemTypeTrim == "Augmentation")
    local isScriptItem = (item.name or ""):lower():find("script of", 1, true)
    local isRerollBook = (item.name or ""):lower():find("book of mythical reroll", 1, true)
    local function enqueueScriptConsume(payload)
        if not payload then return end
        if not ctx.uiState.pendingScriptConsume then
            ctx.uiState.pendingScriptConsume = payload
            return
        end
        local q = ctx.uiState.pendingScriptConsumeQueue or {}
        q[#q + 1] = payload
        ctx.uiState.pendingScriptConsumeQueue = q
        if ctx.setStatusMessage then ctx.setStatusMessage(string.format("Alt Currency queued (%d).", #q)) end
    end

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
                    enqueueScriptConsume({
                        bag = item.bag, slot = item.slot, source = source,
                        totalToConsume = stack, consumedSoFar = 0, nextClickAt = 0, itemName = item.name
                    })
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
                    enqueueScriptConsume({
                        bag = item.bag, slot = item.slot, source = "bank",
                        totalToConsume = stack, consumedSoFar = 0, nextClickAt = 0, itemName = item.name
                    })
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
        -- No EndPopup here: this is the contents-only function — the host that
        -- opened the popup closes it (double EndPopup corrupts the ImGui stack).
        return
    end

    -- Book of Mythical Reroll: single "Use" option that right-clicks the item in-game.
    -- After use the book is consumed, so remove it from the UI immediately and schedule a bag rescan.
    if isRerollBook then
        if (source == "inv" or source == "sell" or source == "augments") and item.bag and item.slot then
            if ImGui.MenuItem("Use (Book of Mythical Reroll)") then
                mq.cmdf('/itemnotify in pack%d %d rightmouseup', item.bag, item.slot)
                if ctx.consumeItemAtSlot then ctx.consumeItemAtSlot(source, item.bag, item.slot) end
                if ctx.setStatusMessage then ctx.setStatusMessage("Used Book of Mythical Reroll.") end
            end
        elseif source == "bank" and item.bag and item.slot then
            if ImGui.MenuItem("Use (Book of Mythical Reroll)") then
                mq.cmdf('/itemnotify in bank%d %d rightmouseup', item.bag, item.slot)
                if ctx.consumeItemAtSlot then ctx.consumeItemAtSlot(source, item.bag, item.slot) end
                if ctx.setStatusMessage then ctx.setStatusMessage("Used Book of Mythical Reroll.") end
            end
        end
        -- No EndPopup here (contents-only function; host closes the popup).
        return
    end

    -- Consumables: items the user flagged as right-click-to-use (e.g. "Book of Titles").
    -- Shown up top so the Use action is obvious; the list itself is the safety gate — only
    -- flagged items ever get a consume option, so nothing valuable is right-clicked by accident.
    if ctx.consumables and nameKey ~= "" and ctx.consumables.isConsumable(nameKey)
       and (source == "inv" or source == "sell" or source == "augments" or source == "bank")
       and item.bag and item.slot then
        local notifyLoc = (source == "bank") and "bank" or "pack"
        if ImGui.MenuItem("Use (consume one)") then
            mq.cmdf('/itemnotify in %s%d %d rightmouseup', notifyLoc, item.bag, item.slot)
            if ctx.consumeItemAtSlot then ctx.consumeItemAtSlot(source, item.bag, item.slot) end
            if ctx.setStatusMessage then ctx.setStatusMessage("Used " .. (item.name or "item") .. ".") end
        end
        local stack = (item.stackSize and item.stackSize > 1) and item.stackSize or nil
        if stack and ImGui.MenuItem(string.format("Use all (x%d)", stack)) then
            enqueueScriptConsume({
                bag = item.bag, slot = item.slot, source = (source == "augments") and "inv" or source,
                totalToConsume = stack, consumedSoFar = 0, nextClickAt = 0, itemName = item.name,
            })
        end
        ImGui.Separator()
    end

    -- Inspect (game window)
    if ImGui.MenuItem("Inspect") then
        if hasCursor and ctx.removeItemFromCursor then ctx.removeItemFromCursor()
        else doInspect(ctx, item, source) end
    end
    if ImGui.MenuItem("CoOp UI Item Display") then
        if ctx.addItemDisplayTab then ctx.addItemDisplayTab(item, source) end
    end

    -- Clicky Lists (favorites): toggle membership per list. Items on any list are
    -- protected from selling and from Delete until removed.
    do
        local fav = ctx.favoritesService
        local favItemId = tonumber(item.id or item.ID)
        if fav and favItemId then
            if ImGui.BeginMenu("Clicky Lists") then
                local favLists = fav.getLists()
                if #favLists == 0 then
                    ImGui.MenuItem("(create lists in the Clickies window)", nil, false, false)
                else
                    local containing = fav.listsContaining(favItemId)
                    for _, l in ipairs(favLists) do
                        local on = containing[l.name] == true
                        if ImGui.MenuItem(l.name, nil, on) then
                            if on then
                                fav.removeItem(l.name, favItemId)
                            else
                                fav.addItem(l.name, favItemId, item.name or "")
                            end
                        end
                    end
                end
                ImGui.EndMenu()
            end
        end
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

    -- Consumables list: flag/unflag any named item so it gets the "Use" option above.
    if ctx.consumables and nameKey ~= "" and (source == "inv" or source == "sell" or source == "bank" or source == "augments") then
        ImGui.Separator()
        if ctx.consumables.isConsumable(nameKey) then
            if ImGui.MenuItem("Remove from Consumables") then ctx.consumables.removeConsumable(nameKey) end
        else
            if ImGui.MenuItem("Add to Consumables") then ctx.consumables.addConsumable(nameKey) end
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

    -- Reroll list: single Add entry, destination auto-resolved by the item
    -- (Mythical name prefix -> mythical list, augments -> aug list; nil = not eligible).
    local rerollService = ctx.rerollService
    local resolvedList = ctx.resolveRerollList and ctx.resolveRerollList(item.name, item.type) or nil
    if rerollService and nameKey ~= "" and resolvedList then
        local augList = rerollService.getAugList and rerollService.getAugList() or {}
        local mythicalList = rerollService.getMythicalList and rerollService.getMythicalList() or {}
        local itemId = item.id or item.ID
        local onAugList, onMythicalList = false, false
        if itemId then
            for _, e in ipairs(augList) do if e.id == itemId then onAugList = true; break end end
            for _, e in ipairs(mythicalList) do if e.id == itemId then onMythicalList = true; break end end
        end
        local onResolvedList
        if resolvedList == "mythical" then onResolvedList = onMythicalList else onResolvedList = onAugList end
        ImGui.Separator()
        if not onResolvedList then
            local addLabel = (resolvedList == "mythical") and "Add to Reroll List (Mythical)" or "Add to Reroll List (Aug)"
            if ImGui.MenuItem(addLabel) then
                if ctx.requestAddToRerollList then
                    local payload = (source == "bank") and { bag = item.bag, slot = item.slot, id = itemId, name = item.name, source = "bank" } or item
                    ctx.requestAddToRerollList(resolvedList, payload)
                end
            end
        end
        -- Removes stay per-list: membership by id makes the correct list unambiguous
        -- (an item can sit on either list from before auto-routing).
        if onAugList then
            if ImGui.MenuItem("Remove from Reroll List (Aug)") then
                if itemId and ctx.removeFromRerollList then ctx.removeFromRerollList("aug", itemId) end
            end
        end
        if onMythicalList then
            if ImGui.MenuItem("Remove from Reroll List (Mythical)") then
                if itemId and ctx.removeFromRerollList then ctx.removeFromRerollList("mythical", itemId) end
            end
        end
    end

    -- Reroll view only: Remove from list
    if source == "reroll" and opts.onRemoveFromRerollList and opts.rerollEntryId then
        ImGui.Separator()
        if ImGui.MenuItem("Remove from list") then opts.onRemoveFromRerollList(opts.rerollEntryId) end
    end

    -- Equip (inventory items only; not augments, scripts, or reroll books)
    local canEquip = (source == "inv") and item.bag ~= nil and item.slot ~= nil
        and not isAugment and not isScriptItem and not isRerollBook
    if canEquip then
        -- Slot indices per SLOT_NAMES_ITEMNOTIFY in item_tlo.lua (0-22 map)
        local SLOT_MAINHAND, SLOT_OFFHAND = 13, 14
        -- Determine best equipment slot via live TLO (runs only while menu is open, not per-frame)
        local bestSlotName, preClearSlots = nil, nil
        local Me = mq.TLO and mq.TLO.Me
        local pack = Me and Me.Inventory and Me.Inventory("pack" .. item.bag)
        local it = pack and pack.Item and pack.Item(item.slot)
        if it and it.WornSlots then
            local nSlots = it.WornSlots()
            if nSlots and nSlots > 0 and nSlots < 20 then
                -- Build deduplicated slot index list (weapons, fingers, ears, wrists, etc.)
                local validSlots, slotSet = {}, {}
                for i = 1, nSlots do
                    local s = it.WornSlot and it.WornSlot(i)
                    local idx = s and tonumber(tostring(s))
                    if idx ~= nil and not slotSet[idx] then
                        slotSet[idx] = true
                        validSlots[#validSlots + 1] = idx
                    end
                end
                local eqCache = ctx.equipmentCache or {}
                local getSlotName = ctx.getEquipmentSlotNameForItemNotify
                if slotSet[SLOT_MAINHAND] then
                    -- New item fits mainhand. Determine if a primary-only constraint applies.
                    local newIsPrimaryOnly = not slotSet[SLOT_OFFHAND]
                    -- Check if the currently-equipped mainhand item is primary-only (e.g. a 2-hander).
                    local equippedMHIsPrimaryOnly = false
                    if not newIsPrimaryOnly and eqCache[SLOT_MAINHAND + 1] ~= nil then
                        local mhInv = Me and Me.Inventory and Me.Inventory("mainhand")
                        if mhInv and mhInv.ID and mhInv.ID() and mhInv.ID() > 0 and mhInv.WornSlots then
                            local nMhSlots = mhInv.WornSlots()
                            if nMhSlots and nMhSlots > 0 and nMhSlots < 20 then
                                local mhSlotSet = {}
                                for i = 1, nMhSlots do
                                    local s = mhInv.WornSlot and mhInv.WornSlot(i)
                                    local idx = s and tonumber(tostring(s))
                                    if idx then mhSlotSet[idx] = true end
                                end
                                equippedMHIsPrimaryOnly = mhSlotSet[SLOT_MAINHAND] and not mhSlotSet[SLOT_OFFHAND]
                            end
                        end
                    end
                    if newIsPrimaryOnly or equippedMHIsPrimaryOnly then
                        -- A primary-only constraint is in play: pre-clear BOTH weapon slots
                        -- (offhand first — may be a no-op), then equip to mainhand.
                        -- targetSlot is always mainhand here since we are clearing it.
                        bestSlotName = getSlotName and getSlotName(SLOT_MAINHAND) or nil
                        if getSlotName then
                            preClearSlots = {}
                            local ohName = getSlotName(SLOT_OFFHAND)
                            local mhName = getSlotName(SLOT_MAINHAND)
                            if ohName then preClearSlots[#preClearSlots + 1] = ohName end
                            if mhName then preClearSlots[#preClearSlots + 1] = mhName end
                        end
                    else
                        -- 1H weapon with no primary-only constraint: prefer empty slot
                        -- (fills offhand if mainhand is already taken), fall back to mainhand.
                        table.sort(validSlots, function(a, b)
                            if a == SLOT_MAINHAND then return true end
                            if b == SLOT_MAINHAND then return false end
                            return a < b
                        end)
                        local bestIdx = nil
                        for _, idx in ipairs(validSlots) do
                            if eqCache[idx + 1] == nil then bestIdx = idx; break end
                        end
                        if not bestIdx and #validSlots > 0 then bestIdx = validSlots[1] end
                        if bestIdx ~= nil then
                            bestSlotName = getSlotName and getSlotName(bestIdx) or nil
                        end
                    end
                else
                    -- Non-mainhand item (offhand-only, finger, ear, wrist, etc.):
                    -- prefer an empty slot; fall back to first valid slot.
                    table.sort(validSlots, function(a, b) return a < b end)
                    local bestIdx = nil
                    for _, idx in ipairs(validSlots) do
                        if eqCache[idx + 1] == nil then bestIdx = idx; break end
                    end
                    if not bestIdx and #validSlots > 0 then bestIdx = validSlots[1] end
                    if bestIdx ~= nil then
                        bestSlotName = getSlotName and getSlotName(bestIdx) or nil
                    end
                end
            end
        end
        if bestSlotName then
            ImGui.Separator()
            if ImGui.MenuItem("Equip") then
                local q = ctx.uiState.cursorActionQueue or {}
                q[#q + 1] = { type = "equip", bag = item.bag, slot = item.slot, name = item.name,
                               targetSlot = bestSlotName, attuneable = item.attuneable,
                               preClearSlots = preClearSlots }
                ctx.uiState.cursorActionQueue = q
            end
        end
    end

    -- Destroy
    local canDestroy = (source == "inv" or source == "bank" or source == "sell" or source == "augments" or source == "reroll") and item.bag ~= nil and item.slot ~= nil
    -- Favorites protection: listed items can't be deleted until removed from their lists.
    local favProtected = ctx.favoritesService and ctx.favoritesService.isProtected(tonumber(item.id or item.ID)) or false
    if canDestroy and favProtected then
        ImGui.Separator()
        ImGui.MenuItem("Delete (on a Clicky List)", nil, false, false)
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("This item is on a Clicky List. Remove it from the list (Clickies window) to delete it.")
            ImGui.EndTooltip()
        end
    elseif canDestroy and ctx.setPendingDestroy and ctx.requestDestroyItem then
        ImGui.Separator()
        ImGui.Dummy(ImVec2(0, 6))
        ctx.theme.PushDeleteButton()
        if ImGui.MenuItem("Delete") then
            local stackSize = (item.stackSize and item.stackSize > 0) and item.stackSize or 1
            if ctx.getSkipConfirmDelete and ctx.getSkipConfirmDelete() then
                ctx.requestDestroyItem(item.bag, item.slot, item.name, stackSize)
            else
                ctx.setPendingDestroy({ bag = item.bag, slot = item.slot, name = item.name or "", stackSize = stackSize })
            end
        end
        ctx.theme.PopButtonColors()
    end
end

return M
