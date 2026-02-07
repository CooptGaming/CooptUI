--[[
    ItemUI - Item Operations Service
    Item manipulation (add/remove), movement (inv<->bank), sell queue, flags.
    Part of CoopUI — EverQuest EMU Companion
--]]

local mq = require('mq')

local M = {}
local deps  -- set by init()
local sellQueue = {}
local isSelling = false

function M.init(d)
    deps = d
end

function M.setTransferStampPath(path)
    deps.transferStampPath = path
end

-- ============================================================================
-- Sell Queue
-- ============================================================================

function M.queueItemForSelling(itemData)
    if isSelling then
        deps.setStatusMessage("Already selling, please wait...")
        return false
    end
    table.insert(sellQueue, { name = itemData.name, bag = itemData.bag, slot = itemData.slot, id = itemData.id })
    deps.setStatusMessage("Queued for sell")
    return true
end

function M.processSellQueue()
    if #sellQueue == 0 or isSelling then return end
    if not deps.isMerchantWindowOpen() then
        sellQueue = {}
        return
    end
    isSelling = true
    local itemToSell = table.remove(sellQueue, 1)
    local itemName, bagNum, slotNum = itemToSell.name, itemToSell.bag, itemToSell.slot
    local Me = mq.TLO and mq.TLO.Me
    local pack = Me and Me.Inventory and Me.Inventory("pack" .. bagNum)
    local item = pack and pack.Item and pack.Item(slotNum)
    if not item or not item.ID or not item.ID() or item.ID() == 0 then
        isSelling = false
        return
    end
    mq.delay(200)
    mq.cmdf('/itemnotify in pack%d %d leftmouseup', bagNum, slotNum)
    mq.delay(300)
    local selected = false
    for i = 1, 10 do
        local wnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("MerchantWnd/MW_SelectedItemLabel")
        if wnd and wnd.Text and wnd.Text() == itemName then selected = true; break end
        mq.delay(100)
    end
    if not selected then
        isSelling = false
        return
    end
    mq.cmd('/nomodkey /shiftkey /notify MerchantWnd MW_Sell_Button leftmouseup')
    mq.delay(300)
    for i = 1, 15 do
        local wnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("MerchantWnd/MW_SelectedItemLabel")
        local sel = (wnd and wnd.Text and wnd.Text()) or ""
        if sel == "" or sel ~= itemName then
            local v = pack and pack.Item and pack.Item(slotNum)
            if not v or not v.ID or not v.ID() or v.ID() == 0 then break end
        end
        mq.delay(100)
    end
    M.removeItemFromInventoryBySlot(bagNum, slotNum)
    M.removeItemFromSellItemsBySlot(bagNum, slotNum)
    isSelling = false
    deps.setStatusMessage(string.format("Sold: %s", itemName))
end

-- ============================================================================
-- Item List Manipulation (add/remove without rescan)
-- ============================================================================

function M.updateSellStatusForItemName(itemName, inKeep, inJunk)
    if not itemName or itemName == "" then return end
    deps.invalidateSortCache("sell")
    local key = (itemName or ""):match("^%s*(.-)%s*$")
    if key == "" then return end
    if not deps.perfCache.sellConfigCache then deps.sellStatus.loadSellConfigCache() end
    for _, row in ipairs(deps.sellItems) do
        local rn = (row.name or ""):match("^%s*(.-)%s*$")
        if rn == key then
            row.inKeep = inKeep
            row.inJunk = inJunk
            local ws, reason = deps.sellStatus.willItemBeSold(row)
            row.willSell = ws
            row.sellReason = reason
        end
    end
end

function M.removeLootItemBySlot(slot)
    for i = #deps.lootItems, 1, -1 do
        if deps.lootItems[i].slot == slot then
            table.remove(deps.lootItems, i)
            return true
        end
    end
    return false
end

function M.removeItemFromInventoryBySlot(bag, slot)
    for i = #deps.inventoryItems, 1, -1 do
        if deps.inventoryItems[i].bag == bag and deps.inventoryItems[i].slot == slot then
            deps.invalidateSortCache("inv")
            table.remove(deps.inventoryItems, i)
            return
        end
    end
end

function M.removeItemFromSellItemsBySlot(bag, slot)
    deps.invalidateSortCache("sell")
    for i = #deps.sellItems, 1, -1 do
        if deps.sellItems[i].bag == bag and deps.sellItems[i].slot == slot then
            table.remove(deps.sellItems, i)
            return
        end
    end
end

function M.removeItemFromBankBySlot(bag, slot)
    deps.invalidateSortCache("bank")
    for i = #deps.bankItems, 1, -1 do
        if deps.bankItems[i].bag == bag and deps.bankItems[i].slot == slot then
            table.remove(deps.bankItems, i)
            break
        end
    end
    for i = #deps.bankCache, 1, -1 do
        if deps.bankCache[i].bag == bag and deps.bankCache[i].slot == slot then
            table.remove(deps.bankCache, i)
            return
        end
    end
end

function M.addItemToBank(bag, slot, name, id, value, totalValue, stackSize, itemType, nodrop, notrade, lore, quest, collectible, heirloom, attuneable, augSlots, weight, clicky, container)
    weight = weight or 0
    clicky = clicky or 0
    container = container or 0
    local row = {
        bag = bag, slot = slot, name = name, id = id, value = value or 0, totalValue = totalValue or value or 0,
        stackSize = stackSize or 1, type = itemType or "", weight = weight, nodrop = nodrop or false, notrade = notrade or false,
        lore = lore or false, quest = quest or false, collectible = collectible or false, heirloom = heirloom or false,
        attuneable = attuneable or false, augSlots = augSlots or 0, clicky = clicky, container = container
    }
    deps.invalidateSortCache("bank")
    table.insert(deps.bankItems, row)
    if deps.isBankWindowOpen() then
        table.insert(deps.bankCache, { bag = row.bag, slot = row.slot, name = row.name, id = row.id, value = row.value, totalValue = row.totalValue, stackSize = row.stackSize, type = row.type, weight = row.weight })
        deps.perfCache.lastBankCacheTime = os.time()
    end
end

function M.addItemToInventory(bag, slot, name, id, value, totalValue, stackSize, itemType, nodrop, notrade, lore, quest, collectible, heirloom, attuneable, augSlots)
    deps.invalidateSortCache("inv")
    local row = { bag = bag, slot = slot, name = name, id = id, value = value or 0, totalValue = totalValue or value or 0,
        stackSize = stackSize or 1, type = itemType or "", nodrop = nodrop or false, notrade = notrade or false,
        lore = lore or false, quest = quest or false, collectible = collectible or false, heirloom = heirloom or false,
        attuneable = attuneable or false, augSlots = augSlots or 0 }
    table.insert(deps.inventoryItems, row)
    local dup = { bag = row.bag, slot = row.slot, name = row.name, id = row.id, value = row.value, totalValue = row.totalValue,
        stackSize = row.stackSize, type = row.type, nodrop = row.nodrop, notrade = row.notrade, lore = row.lore, quest = row.quest,
        collectible = row.collectible, heirloom = row.heirloom, attuneable = row.attuneable, augSlots = row.augSlots }
    dup.inKeep = deps.sellStatus.isInKeepList(row.name) or deps.sellStatus.isKeptByContains(row.name) or deps.sellStatus.isKeptByType(row.type)
    dup.inJunk = deps.sellStatus.isInJunkList(row.name)
    dup.isProtected = deps.sellStatus.isProtectedType(row.type)
    local ws, reason = deps.sellStatus.willItemBeSold(dup)
    dup.willSell, dup.sellReason = ws, reason
    deps.invalidateSortCache("sell")
    table.insert(deps.sellItems, dup)
end

-- ============================================================================
-- Helpers
-- ============================================================================

function M.getItemFlags(d)
    local t = {}
    if d.nodrop then table.insert(t, "NoDrop") end
    if d.notrade then table.insert(t, "NoTrade") end
    if d.lore then table.insert(t, "Lore") end
    if d.quest then table.insert(t, "Quest") end
    if d.collectible then table.insert(t, "Collectible") end
    if d.heirloom then table.insert(t, "Heirloom") end
    if d.attuneable then table.insert(t, "Attuneable") end
    if d.augSlots and d.augSlots > 0 then table.insert(t, string.format("Aug(%d)", d.augSlots)) end
    if deps.getItemSpellId(d, "Clicky") > 0 then table.insert(t, "Clicky") end
    if d.container and d.container > 0 then table.insert(t, string.format("Bag(%d)", d.container)) end
    return #t > 0 and table.concat(t, ", ") or "None"
end

function M.hasItemOnCursor()
    return (mq.TLO and mq.TLO.Cursor and mq.TLO.Cursor()) and true or false
end

-- ============================================================================
-- Item Movement (inv <-> bank)
-- ============================================================================

local function findFirstFreeBankSlot()
    local Me = mq.TLO and mq.TLO.Me
    if not Me or not Me.Bank then return nil, nil end
    for b = 1, 24 do
        local s = Me.Bank(b)
        if s then
            local sz = (s.Container and s.Container()) or 0
            if sz and sz > 0 then
                for i = 1, sz do
                    local it = s.Item and s.Item(i)
                    if not it or not it.ID or not it.ID() or it.ID() == 0 then return b, i end
                end
            elseif (not s.ID or not s.ID() or s.ID() == 0) then return b, 1 end
        end
    end
    return nil, nil
end

local function findFirstFreeInvSlot()
    local Me = mq.TLO and mq.TLO.Me
    if not Me or not Me.Inventory then return nil, nil end
    for b = 1, 10 do
        local p = Me.Inventory("pack" .. b)
        local sz = p and p.Container and p.Container() or 0
        if sz and sz > 0 then
            for i = 1, sz do
                local it = p.Item and p.Item(i)
                if not it or not it.ID or not it.ID() or it.ID() == 0 then return b, i end
            end
        end
    end
    return nil, nil
end

function M.moveInvToBank(invBag, invSlot)
    local row
    for _, r in ipairs(deps.inventoryItems) do
        if r.bag == invBag and r.slot == invSlot then row = r; break end
    end
    local bb, bs = findFirstFreeBankSlot()
    if not bb or not bs then deps.setStatusMessage("No free bank slot"); return false end
    mq.cmdf('/itemnotify in pack%d %d leftmouseup', invBag, invSlot)
    mq.cmdf('/itemnotify in bank%d %d leftmouseup', bb, bs)
    deps.uiState.lastPickup.bag, deps.uiState.lastPickup.slot, deps.uiState.lastPickup.source = nil, nil, nil
    if deps.transferStampPath then local f = io.open(deps.transferStampPath, "w"); if f then f:write(tostring(os.time())); f:close() end end
    M.removeItemFromInventoryBySlot(invBag, invSlot)
    M.removeItemFromSellItemsBySlot(invBag, invSlot)
    if row then
        M.addItemToBank(bb, bs, row.name, row.id, row.value, row.totalValue, row.stackSize, row.type, row.nodrop, row.notrade, row.lore, row.quest, row.collectible, row.heirloom, row.attuneable, row.augSlots, row.weight, deps.getItemSpellId(row, "Clicky"), row.container)
        deps.setStatusMessage(string.format("Moved to bank: %s", row.name or "item"))
    end
    return true
end

function M.moveBankToInv(bagIdx, slotIdx)
    local row
    for _, r in ipairs(deps.bankItems) do
        if r.bag == bagIdx and r.slot == slotIdx then row = r; break end
    end
    if not row and deps.isBankWindowOpen() then
        deps.scanBank()
        for _, r in ipairs(deps.bankItems) do
            if r.bag == bagIdx and r.slot == slotIdx then row = r; break end
        end
    end
    local ib, is_ = findFirstFreeInvSlot()
    if not ib or not is_ then deps.setStatusMessage("No free inventory slot"); return false end
    mq.cmdf('/itemnotify in bank%d %d leftmouseup', bagIdx, slotIdx)
    mq.cmdf('/itemnotify in pack%d %d leftmouseup', ib, is_)
    deps.uiState.lastPickup.bag, deps.uiState.lastPickup.slot, deps.uiState.lastPickup.source = nil, nil, nil
    if deps.transferStampPath then local f = io.open(deps.transferStampPath, "w"); if f then f:write(tostring(os.time())); f:close() end end
    if row then
        M.removeItemFromBankBySlot(bagIdx, slotIdx)
        M.addItemToInventory(ib, is_, row.name, row.id, row.value, row.totalValue, row.stackSize, row.type, row.nodrop, row.notrade, row.lore, row.quest, row.collectible, row.heirloom, row.attuneable, row.augSlots)
        deps.setStatusMessage(string.format("Moved to inventory: %s", row.name or "item"))
    end
    return true
end

function M.removeItemFromCursor()
    if not M.hasItemOnCursor() then return false end
    if deps.uiState.lastPickup.bag and deps.uiState.lastPickup.slot then
        if deps.uiState.lastPickup.source == "bank" then
            mq.cmdf('/itemnotify in bank%d %d leftmouseup', deps.uiState.lastPickup.bag, deps.uiState.lastPickup.slot)
        else
            mq.cmdf('/itemnotify in pack%d %d leftmouseup', deps.uiState.lastPickup.bag, deps.uiState.lastPickup.slot)
        end
        deps.uiState.lastPickup.bag, deps.uiState.lastPickup.slot, deps.uiState.lastPickup.source = nil, nil, nil
    else
        mq.cmd('/autoinv')
    end
    return true
end

return M
