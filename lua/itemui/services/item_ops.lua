--[[
    ItemUI - Item Operations Service
    Item manipulation (add/remove), movement (inv<->bank), manual sell (single item), flags.
    Part of CoOpt UI — EverQuest EMU Companion
    Manual Sell: one item at a time, no queue. Auto Sell is separate (runs sell macro).
--]]

local mq = require('mq')
local constants = require('itemui.constants')

local M = {}
local deps  -- set by init()

-- Per 4.2 state ownership: destroy, move, quantity picker, cursor/pickup
-- sellState: nil when idle; else { phase, item = {name, bag, slot}, enteredAt, pollCount? } for non-blocking sell (task 1.3)
local state = {
    sellState = nil,
    pendingDestroy = nil,
    pendingDestroyAction = nil,
    destroyQuantityValue = "",
    destroyQuantityMax = 1,
    pendingMoveAction = nil,
    quantityPickerValue = "",
    quantityPickerMax = 1,
    quantityPickerSubmitPending = nil,
    pendingQuantityPickup = nil,
    pendingQuantityPickupTimeoutAt = nil,
    pendingQuantityAction = nil,
    pendingScriptConsume = nil,
    lastPickup = { bag = nil, slot = nil, source = nil },
    lastPickupSetThisFrame = false,
    lastPickupClearedAt = 0,
    activationGuardUntil = 0,
    hadItemOnCursorLastFrame = false,
    hasItemOnCursorThisFrame = nil,
}
function M.getState()
    return state
end

function M.init(d)
    deps = d
end

function M.setTransferStampPath(path)
    deps.transferStampPath = path
end

-- ============================================================================
-- Manual Sell (single item, no queue — task 1.3)
-- ============================================================================

--- Start selling one item to the vendor. Manual override: sells this item immediately (non-blocking state machine).
--- Returns false if a sell is already in progress, merchant closed, or item missing. No queue; one item at a time.
function M.queueItemForSelling(itemData)
    if state.sellState ~= nil then
        deps.setStatusMessage("Already selling, please wait.")
        return false
    end
    if not deps.isMerchantWindowOpen() then
        deps.setStatusMessage("Open a merchant to sell.")
        return false
    end
    local bagNum, slotNum = itemData.bag, itemData.slot
    local Me = mq.TLO and mq.TLO.Me
    local pack = Me and Me.Inventory and Me.Inventory("pack" .. bagNum)
    local item = pack and pack.Item and pack.Item(slotNum)
    if not item or not item.ID or not item.ID() or item.ID() == 0 then
        deps.setStatusMessage("Item not found in pack.")
        return false
    end
    state.sellState = {
        phase = "initial_delay",
        item = { name = itemData.name, bag = bagNum, slot = slotNum, id = itemData.id },
        enteredAt = mq.gettime and mq.gettime() or 0,
    }
    deps.setStatusMessage("Selling...")
    return true
end

--- Advance manual sell state machine one step per frame (task 1.3). Pass current time from main_loop. No queue; sell is started by queueItemForSelling (Sell button).
function M.processSellQueue(now)
    now = now or (mq.gettime and mq.gettime() or 0)
    local T = constants.TIMING
    local INITIAL_MS = T.ITEM_OPS_DELAY_INITIAL_MS
    local DELAY_MS = T.ITEM_OPS_DELAY_MS

    -- If a sell is in progress, run one step of the state machine
    if state.sellState ~= nil then
        local ss = state.sellState
        local itemName, bagNum, slotNum = ss.item.name, ss.item.bag, ss.item.slot
        local Me = mq.TLO and mq.TLO.Me
        local pack = Me and Me.Inventory and Me.Inventory("pack" .. bagNum)

        -- Merchant closed mid-sell: abort (no queue to clear)
        if not deps.isMerchantWindowOpen() then
            state.sellState = nil
            deps.setStatusMessage("Merchant closed; sell cancelled.")
            return
        end

        if ss.phase == "initial_delay" then
            if (now - ss.enteredAt) < INITIAL_MS then return end
            mq.cmdf('/itemnotify in pack%d %d leftmouseup', bagNum, slotNum)
            ss.phase = "after_pickup_delay"
            ss.enteredAt = now
            return
        end

        if ss.phase == "after_pickup_delay" then
            if (now - ss.enteredAt) < DELAY_MS then return end
            ss.phase = "wait_selected"
            ss.enteredAt = now
            ss.pollCount = 0
            return
        end

        if ss.phase == "wait_selected" then
            local wnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("MerchantWnd/MW_SelectedItemLabel")
            local sel = (wnd and wnd.Text and wnd.Text()) or ""
            if sel == itemName then
                ss.phase = "click_sell_delay"
                ss.enteredAt = now
                return
            end
            ss.pollCount = (ss.pollCount or 0) + 1
            if ss.pollCount >= 10 then
                state.sellState = nil
                deps.setStatusMessage("Sell failed; item not selected.")
                return
            end
            return
        end

        if ss.phase == "click_sell_delay" then
            if (now - ss.enteredAt) < DELAY_MS then return end
            mq.cmd('/nomodkey /shiftkey /notify MerchantWnd MW_Sell_Button leftmouseup')
            ss.phase = "wait_sold"
            ss.enteredAt = now
            ss.pollCount = 0
            return
        end

        if ss.phase == "wait_sold" then
            local wnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("MerchantWnd/MW_SelectedItemLabel")
            local sel = (wnd and wnd.Text and wnd.Text()) or ""
            local slotItem = pack and pack.Item and pack.Item(slotNum)
            local slotId = (slotItem and slotItem.ID and slotItem.ID()) or 0
            local itemGone = (not slotItem or not slotItem.ID or slotId == 0)
            local labelCleared = (sel == "" or sel ~= itemName)
            if labelCleared and itemGone then
                M.removeItemFromInventoryBySlot(bagNum, slotNum)
                M.removeItemFromSellItemsBySlot(bagNum, slotNum)
                state.sellState = nil
                deps.setStatusMessage(string.format("Sold: %s", itemName))
                return
            end
            ss.pollCount = (ss.pollCount or 0) + 1
            if ss.pollCount >= 15 then
                state.sellState = nil
                deps.setStatusMessage("Sell may have failed; check inventory.")
                return
            end
            return
        end
        return
    end

    -- Idle: nothing to do. Selling is started only by queueItemForSelling (Sell button); no queue.
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
    local function applyFlags(row)
        local rn = (row.name or ""):match("^%s*(.-)%s*$")
        row.inKeepExact = inKeep
        row.inJunkExact = inJunk
        row.inKeepContains = deps.sellStatus.isKeptByContains(rn)
        row.inJunkContains = deps.sellStatus.isInJunkContainsList(rn)
        row.inKeepType = deps.sellStatus.isKeptByType(row.type)
        row.isProtectedType = deps.sellStatus.isProtectedType(row.type)
        row.inKeep = row.inKeepExact or row.inKeepContains or row.inKeepType
        row.inJunk = row.inJunkExact or row.inJunkContains
        row.isProtected = row.isProtectedType
        local ws, reason = deps.sellStatus.willItemBeSold(row)
        row.willSell = ws
        row.sellReason = reason
    end
    for _, row in ipairs(deps.sellItems) do
        local rn = (row.name or ""):match("^%s*(.-)%s*$")
        if rn == key then applyFlags(row) end
    end
    -- Sync inventoryItems so saveInventory() persists correct Keep/Junk state
    if deps.inventoryItems then
        deps.invalidateSortCache("inv")
        for _, row in ipairs(deps.inventoryItems) do
            local rn = (row.name or ""):match("^%s*(.-)%s*$")
            if rn == key then applyFlags(row) end
        end
    end
    -- Regenerate sell cache so sell.mac sees the change immediately (A5)
    if deps.storage and deps.storage.writeSellCache then
        deps.storage.writeSellCache(deps.sellItems)
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

--- Reduce stack at bag/slot by destroyQty; remove row if stack would be 0. Updates both inventoryItems and sellItems.
function M.reduceStackOrRemoveBySlot(bag, slot, destroyQty)
    if not destroyQty or destroyQty < 1 then return end
    deps.invalidateSortCache("inv")
    deps.invalidateSortCache("sell")
    for i = #deps.inventoryItems, 1, -1 do
        if deps.inventoryItems[i].bag == bag and deps.inventoryItems[i].slot == slot then
            local row = deps.inventoryItems[i]
            local cur = (row.stackSize and row.stackSize > 0) and row.stackSize or 1
            if destroyQty >= cur then
                table.remove(deps.inventoryItems, i)
            else
                row.stackSize = cur - destroyQty
                row.totalValue = (row.value or 0) * row.stackSize
            end
            break
        end
    end
    for i = #deps.sellItems, 1, -1 do
        if deps.sellItems[i].bag == bag and deps.sellItems[i].slot == slot then
            local row = deps.sellItems[i]
            local cur = (row.stackSize and row.stackSize > 0) and row.stackSize or 1
            if destroyQty >= cur then
                table.remove(deps.sellItems, i)
            else
                row.stackSize = cur - destroyQty
                row.totalValue = (row.value or 0) * row.stackSize
            end
            return
        end
    end
end

--- Reduce stack at bag/slot in bank by qty; remove row if stack would be 0. Updates bankItems and bankCache (same pattern as reduceStackOrRemoveBySlot for inv).
function M.reduceStackOrRemoveBySlotBank(bag, slot, qty)
    if not qty or qty < 1 then return end
    deps.invalidateSortCache("bank")
    for i = #deps.bankItems, 1, -1 do
        if deps.bankItems[i].bag == bag and deps.bankItems[i].slot == slot then
            local row = deps.bankItems[i]
            local cur = (row.stackSize and row.stackSize > 0) and row.stackSize or 1
            if qty >= cur then
                table.remove(deps.bankItems, i)
            else
                row.stackSize = cur - qty
                row.totalValue = (row.value or 0) * row.stackSize
            end
            break
        end
    end
    for i = #deps.bankCache, 1, -1 do
        if deps.bankCache[i].bag == bag and deps.bankCache[i].slot == slot then
            local row = deps.bankCache[i]
            local cur = (row.stackSize and row.stackSize > 0) and row.stackSize or 1
            if qty >= cur then
                table.remove(deps.bankCache, i)
            else
                row.stackSize = cur - qty
                row.totalValue = (row.value or 0) * row.stackSize
            end
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

function M.addItemToBank(bag, slot, name, id, value, totalValue, stackSize, itemType, nodrop, notrade, lore, quest, collectible, heirloom, attuneable, augSlots, weight, clicky, container, icon)
    weight = weight or 0
    clicky = clicky or 0
    container = container or 0
    icon = tonumber(icon) or 0
    local row = {
        bag = bag, slot = slot, name = name, id = id, value = value or 0, totalValue = totalValue or value or 0,
        stackSize = stackSize or 1, type = itemType or "", weight = weight, icon = icon,
        nodrop = nodrop or false, notrade = notrade or false, lore = lore or false, quest = quest or false,
        collectible = collectible or false, heirloom = heirloom or false, attuneable = attuneable or false, augSlots = augSlots or 0,
        clicky = clicky, container = container
    }
    deps.invalidateSortCache("bank")
    table.insert(deps.bankItems, row)
    if deps.isBankWindowOpen() then
        table.insert(deps.bankCache, { bag = row.bag, slot = row.slot, name = row.name, id = row.id, value = row.value, totalValue = row.totalValue, stackSize = row.stackSize, type = row.type, weight = row.weight, icon = row.icon })
        deps.perfCache.lastBankCacheTime = os.time()
    end
end

function M.addItemToInventory(bag, slot, name, id, value, totalValue, stackSize, itemType, nodrop, notrade, lore, quest, collectible, heirloom, attuneable, augSlots, icon)
    icon = tonumber(icon) or 0
    deps.invalidateSortCache("inv")
    local row = { bag = bag, slot = slot, name = name, id = id, value = value or 0, totalValue = totalValue or value or 0,
        stackSize = stackSize or 1, type = itemType or "", icon = icon,
        nodrop = nodrop or false, notrade = notrade or false, lore = lore or false, quest = quest or false,
        collectible = collectible or false, heirloom = heirloom or false, attuneable = attuneable or false, augSlots = augSlots or 0 }
    if deps.scanState and deps.scanState.nextAcquiredSeq then
        row.acquiredSeq = deps.scanState.nextAcquiredSeq
        deps.scanState.nextAcquiredSeq = deps.scanState.nextAcquiredSeq + 1
    end
    table.insert(deps.inventoryItems, row)
    deps.sellStatus.attachGranularFlags(row, nil)
    local ws, reason = deps.sellStatus.willItemBeSold(row)
    row.willSell, row.sellReason = ws, reason or ""
    local dup = { bag = row.bag, slot = row.slot, name = row.name, id = row.id, value = row.value, totalValue = row.totalValue,
        stackSize = row.stackSize, type = row.type, icon = row.icon,
        nodrop = row.nodrop, notrade = row.notrade, lore = row.lore, quest = row.quest,
        collectible = row.collectible, heirloom = row.heirloom, attuneable = row.attuneable, augSlots = row.augSlots,
        inKeep = row.inKeep, inJunk = row.inJunk, willSell = row.willSell, sellReason = row.sellReason }
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

--- Find a bank slot that already has this item and has room for more. Prefer slot with most room.
--- Returns destBag, destSlot or nil,nil. movingQty is how many we're adding.
local function findExistingBankStackSlot(itemName, itemId, movingQty)
    if not itemName and not itemId then return nil, nil end
    movingQty = (movingQty and movingQty > 0) and movingQty or 1
    local bestBag, bestSlot, bestRoom = nil, nil, -1
    for _, r in ipairs(deps.bankItems) do
        local same = (itemId and r.id and r.id == itemId) or (itemName and r.name and (r.name == itemName or (r.name or ""):lower() == (itemName or ""):lower()))
        if same then
            local cur = (r.stackSize and r.stackSize > 0) and r.stackSize or 1
            local maxStack = (r.stackSizeMax and r.stackSizeMax > 0) and r.stackSizeMax or cur
            if maxStack > cur then
                local room = maxStack - cur
                if room >= movingQty and room > bestRoom then
                    bestBag, bestSlot, bestRoom = r.bag, r.slot, room
                end
            end
        end
    end
    return bestBag, bestSlot
end

--- Add quantity to an existing bank stack (merge). Updates bankItems and bankCache.
local function addQtyToBankStack(bag, slot, addQty, valuePerUnit)
    if not addQty or addQty < 1 then return end
    valuePerUnit = valuePerUnit or 0
    deps.invalidateSortCache("bank")
    for _, row in ipairs(deps.bankItems) do
        if row.bag == bag and row.slot == slot then
            local cur = (row.stackSize and row.stackSize > 0) and row.stackSize or 1
            row.stackSize = cur + addQty
            row.totalValue = (row.value or valuePerUnit) * row.stackSize
            break
        end
    end
    if deps.isBankWindowOpen() then
        for _, row in ipairs(deps.bankCache) do
            if row.bag == bag and row.slot == slot then
                local cur = (row.stackSize and row.stackSize > 0) and row.stackSize or 1
                row.stackSize = cur + addQty
                row.totalValue = (row.value or valuePerUnit) * row.stackSize
                deps.perfCache.lastBankCacheTime = os.time()
                break
            end
        end
    end
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

--- Count empty inventory bag slots (for pre-flight checks, e.g. reroll bank-to-bag moves).
function M.countFreeInvSlots()
    local Me = mq.TLO and mq.TLO.Me
    if not Me or not Me.Inventory then return 0 end
    local n = 0
    for b = 1, 10 do
        local p = Me.Inventory("pack" .. b)
        local sz = p and p.Container and p.Container() or 0
        if sz and sz > 0 then
            for i = 1, sz do
                local it = p.Item and p.Item(i)
                if not it or not it.ID or not it.ID() or it.ID() == 0 then n = n + 1 end
            end
        end
    end
    return n
end

function M.moveInvToBank(invBag, invSlot)
    local row
    for _, r in ipairs(deps.inventoryItems) do
        if r.bag == invBag and r.slot == invSlot then row = r; break end
    end
    local stackSize = (row and row.stackSize and row.stackSize > 0) and row.stackSize or 1
    local bb, bs = nil, nil
    local mergeIntoExisting = false
    if row and (row.name or row.id) then
        local eb, es = findExistingBankStackSlot(row.name, row.id, stackSize)
        if eb and es then bb, bs, mergeIntoExisting = eb, es, true end
    end
    if not bb or not bs then
        bb, bs = findFirstFreeBankSlot()
    end
    if not bb or not bs then deps.setStatusMessage("No free bank slot"); return false end
    if stackSize > 1 then
        state.pendingMoveAction = {
            source = "inv", bag = invBag, slot = invSlot, destBag = bb, destSlot = bs, qty = stackSize,
            mergeIntoExisting = mergeIntoExisting,
            row = row and { name = row.name, id = row.id, value = row.value, totalValue = row.totalValue, stackSize = row.stackSize, type = row.type, nodrop = row.nodrop, notrade = row.notrade, lore = row.lore, quest = row.quest, collectible = row.collectible, heirloom = row.heirloom, attuneable = row.attuneable, augSlots = row.augSlots, weight = row.weight, container = row.container, icon = row.icon },
            phase = "start",
        }
        if state.pendingMoveAction.row then state.pendingMoveAction.row.clicky = deps.getItemSpellId(row, "Clicky") end
        return true
    end
    mq.cmdf('/itemnotify in pack%d %d leftmouseup', invBag, invSlot)
    mq.cmdf('/itemnotify in bank%d %d leftmouseup', bb, bs)
    state.lastPickup.bag, state.lastPickup.slot, state.lastPickup.source = nil, nil, nil
    state.lastPickupClearedAt = mq.gettime()
    if deps.transferStampPath then local f = io.open(deps.transferStampPath, "w"); if f then f:write(tostring(os.time())); f:close() end end
    M.removeItemFromInventoryBySlot(invBag, invSlot)
    M.removeItemFromSellItemsBySlot(invBag, invSlot)
    if row then
        if mergeIntoExisting then
            addQtyToBankStack(bb, bs, 1, row.value)
        else
            M.addItemToBank(bb, bs, row.name, row.id, row.value, row.totalValue, row.stackSize, row.type, row.nodrop, row.notrade, row.lore, row.quest, row.collectible, row.heirloom, row.attuneable, row.augSlots, row.weight, deps.getItemSpellId(row, "Clicky"), row.container, row.icon)
        end
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
    local stackSize = (row and row.stackSize and row.stackSize > 0) and row.stackSize or 1
    if stackSize > 1 then
        state.pendingMoveAction = {
            source = "bank", bag = bagIdx, slot = slotIdx, destBag = ib, destSlot = is_, qty = stackSize,
            row = row and { name = row.name, id = row.id, value = row.value, totalValue = row.totalValue, stackSize = row.stackSize, type = row.type, nodrop = row.nodrop, notrade = row.notrade, lore = row.lore, quest = row.quest, collectible = row.collectible, heirloom = row.heirloom, attuneable = row.attuneable, augSlots = row.augSlots, icon = row.icon },
            phase = "start",
        }
        return true
    end
    mq.cmdf('/itemnotify in bank%d %d leftmouseup', bagIdx, slotIdx)
    mq.cmdf('/itemnotify in pack%d %d leftmouseup', ib, is_)
    state.lastPickup.bag, state.lastPickup.slot, state.lastPickup.source = nil, nil, nil
    state.lastPickupClearedAt = mq.gettime()
    if deps.transferStampPath then local f = io.open(deps.transferStampPath, "w"); if f then f:write(tostring(os.time())); f:close() end end
    if row then
        M.removeItemFromBankBySlot(bagIdx, slotIdx)
        M.addItemToInventory(ib, is_, row.name, row.id, row.value, row.totalValue, row.stackSize, row.type, row.nodrop, row.notrade, row.lore, row.quest, row.collectible, row.heirloom, row.attuneable, row.augSlots, row.icon)
        deps.setStatusMessage(string.format("Moved to inventory: %s", row.name or "item"))
    end
    return true
end

local MOVE_QTY_WINDOW_TIMEOUT_MS = 2000

--- Advance move state machine one step per frame (task 1.3). Call from main_loop when pendingMoveAction is set. Clears state.pendingMoveAction when done or on failure.
function M.advanceMoveStateMachine(now)
    now = now or (mq.gettime and mq.gettime() or 0)
    local action = state.pendingMoveAction
    if not action or not action.source then return end
    local T = constants.TIMING
    local MEDIUM_MS = T.ITEM_OPS_DELAY_MEDIUM_MS
    local SHORT_MS = T.ITEM_OPS_DELAY_SHORT_MS
    local qty = (action.qty and action.qty > 0) and action.qty or 1
    local phase = action.phase or "start"

    if phase == "start" then
        local w = mq.TLO and mq.TLO.Window and mq.TLO.Window("QuantityWnd")
        if w and w.Open and w.Open() then
            mq.cmd('/notify QuantityWnd QTYW_Cancel_Button leftmouseup')
            action.phase = "close_qty_delay"
            action.enteredAt = now
            return
        end
        action.phase = "pickup"
        return
    end

    if phase == "close_qty_delay" then
        if (now - (action.enteredAt or 0)) < MEDIUM_MS then return end
        action.phase = "pickup"
        return
    end

    if phase == "pickup" then
        if action.source == "inv" then
            mq.cmdf('/itemnotify in pack%d %d leftmouseup', action.bag, action.slot)
        else
            mq.cmdf('/itemnotify in bank%d %d leftmouseup', action.bag, action.slot)
        end
        if qty > 1 then
            action.phase = "wait_qty_window"
            action.enteredAt = now
        else
            action.phase = "pickup_delay"
            action.enteredAt = now
        end
        return
    end

    if phase == "pickup_delay" then
        if (now - (action.enteredAt or 0)) < SHORT_MS then return end
        action.phase = "drop"
        return
    end

    if phase == "wait_qty_window" then
        local qtyWnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("QuantityWnd")
        if qtyWnd and qtyWnd.Open and qtyWnd.Open() then
            mq.cmd(string.format('/notify QuantityWnd QTYW_Slider newvalue %d', qty))
            action.phase = "qty_accept_delay"
            action.enteredAt = now
            return
        end
        if (now - (action.enteredAt or 0)) >= MOVE_QTY_WINDOW_TIMEOUT_MS then
            state.pendingMoveAction = nil
            deps.setStatusMessage("Quantity window did not open.")
            if deps.hasItemOnCursor and deps.hasItemOnCursor() then mq.cmd('/autoinv') end
            return
        end
        return
    end

    if phase == "qty_accept_delay" then
        if (now - (action.enteredAt or 0)) < MEDIUM_MS then return end
        mq.cmd('/notify QuantityWnd QTYW_Accept_Button leftmouseup')
        action.phase = "qty_close_delay"
        action.enteredAt = now
        return
    end

    if phase == "qty_close_delay" then
        if (now - (action.enteredAt or 0)) < SHORT_MS then return end
        action.phase = "drop"
        return
    end

    if phase == "drop" then
        if deps.hasItemOnCursor and not deps.hasItemOnCursor() then
            state.pendingMoveAction = nil
            deps.setStatusMessage("Move failed; no item on cursor.")
            return
        end
        if action.source == "inv" then
            mq.cmdf('/itemnotify in bank%d %d leftmouseup', action.destBag, action.destSlot)
        else
            mq.cmdf('/itemnotify in pack%d %d leftmouseup', action.destBag, action.destSlot)
        end
        state.lastPickup.bag, state.lastPickup.slot, state.lastPickup.source = nil, nil, nil
        state.lastPickupClearedAt = mq.gettime()
        if deps.transferStampPath then local f = io.open(deps.transferStampPath, "w"); if f then f:write(tostring(os.time())); f:close() end end
        action.phase = "done"
        return
    end

    if phase == "done" then
        local row = action.row
        if action.source == "inv" then
            M.removeItemFromInventoryBySlot(action.bag, action.slot)
            M.removeItemFromSellItemsBySlot(action.bag, action.slot)
            if row then
                if action.mergeIntoExisting then
                    addQtyToBankStack(action.destBag, action.destSlot, action.qty or row.stackSize or 1, row.value)
                else
                    M.addItemToBank(action.destBag, action.destSlot, row.name, row.id, row.value, row.totalValue, row.stackSize, row.type, row.nodrop, row.notrade, row.lore, row.quest, row.collectible, row.heirloom, row.attuneable, row.augSlots, row.weight, row.clicky or 0, row.container or 0, row.icon)
                end
            end
            deps.setStatusMessage(row and string.format("Moved to bank: %s", row.name or "item") or "Moved to bank")
            if deps.rescanInventoryBags then deps.rescanInventoryBags({ action.bag }) end
        else
            M.removeItemFromBankBySlot(action.bag, action.slot)
            if row then M.addItemToInventory(action.destBag, action.destSlot, row.name, row.id, row.value, row.totalValue, row.stackSize, row.type, row.nodrop, row.notrade, row.lore, row.quest, row.collectible, row.heirloom, row.attuneable, row.augSlots, row.icon) end
            deps.setStatusMessage(row and string.format("Moved to inventory: %s", row.name or "item") or "Moved to inventory")
            if deps.rescanInventoryBags then deps.rescanInventoryBags({ action.destBag }) end
        end
        state.pendingMoveAction = nil
    end
end

-- ============================================================================
-- Phase 4: shared pickup/drop/hide helpers for item-table views
-- ============================================================================

--- Return true if this row should be hidden (item is on cursor or just picked up from this slot).
--- Do not hide when quantity picker is open for this slot (stack pickup): wait until quantity is selected and taken.
function M.shouldHideRowForCursor(item, source)
    if not item or not source then return false end
    local pq = state.pendingQuantityPickup
    if pq and pq.bag == item.bag and pq.slot == item.slot and pq.source == source then
        return false  -- waiting for quantity selection; keep row visible so user sees the stack
    end
    local lp = state.lastPickup
    if not lp or lp.source ~= source then return false end
    if lp.bag ~= item.bag or lp.slot ~= item.slot then return false end
    return true
end

--- Initiate pickup from a slot (inv or bank). Sets lastPickup and runs /itemnotify. Call from view on left-click when no cursor.
--- Blocked for ACTIVATION_GUARD_MS after an unexpected cursor (click-through protection).
function M.pickupFromSlot(bag, slot, source)
    if not bag or not slot or (source ~= "inv" and source ~= "bank") then return end
    local now = mq.gettime()
    if state.activationGuardUntil and now < state.activationGuardUntil then
        if deps.setStatusMessage then deps.setStatusMessage("Please wait...") end
        return
    end
    state.lastPickup.bag = bag
    state.lastPickup.slot = slot
    state.lastPickup.source = source
    state.lastPickupSetThisFrame = true
    if source == "inv" then
        mq.cmdf('/itemnotify in pack%d %d leftmouseup', bag, slot)
    else
        mq.cmdf('/itemnotify in bank%d %d leftmouseup', bag, slot)
    end
end

--- Drop cursor item into a slot (inv or bank). Clears lastPickup, invalidates cache, schedules deferred scan for inv.
function M.dropAtSlot(bag, slot, source)
    if not bag or not slot or (source ~= "inv" and source ~= "bank") then return end
    if source == "inv" then
        mq.cmdf('/itemnotify in pack%d %d leftmouseup', bag, slot)
    else
        mq.cmdf('/itemnotify in bank%d %d leftmouseup', bag, slot)
    end
    state.lastPickup.bag, state.lastPickup.slot, state.lastPickup.source = nil, nil, nil
    state.lastPickupClearedAt = mq.gettime()
    deps.invalidateSortCache(source == "inv" and "inv" or "bank")
    if source == "inv" then
        if deps.rescanInventoryBags then deps.rescanInventoryBags({ bag }) end
        deps.uiState.deferredInventoryScanAt = mq.gettime() + constants.TIMING.DEFERRED_SCAN_DELAY_MS
        if deps.setStatusMessage then deps.setStatusMessage("Dropped in pack") end
    end
end

--- Put item on cursor into first free inventory slot. Clears lastPickup so "put back" is no longer to previous location.
--- Returns true if cursor had item and a free slot was found and used.
function M.putCursorInBags()
    if not M.hasItemOnCursor() then return false end
    local ib, is_ = findFirstFreeInvSlot()
    if not ib or not is_ then
        deps.setStatusMessage("No free inventory slot")
        return false
    end
    mq.cmdf('/itemnotify in pack%d %d leftmouseup', ib, is_)
    state.lastPickup.bag, state.lastPickup.slot, state.lastPickup.source = nil, nil, nil
    state.lastPickupClearedAt = mq.gettime()
    deps.setStatusMessage("Put in bags")
    if deps.rescanInventoryBags then deps.rescanInventoryBags({ ib }) end
    -- Deferred scan so list shows new item after game applies move (immediate scan may run before client updates)
    deps.uiState.deferredInventoryScanAt = mq.gettime() + constants.TIMING.DEFERRED_SCAN_DELAY_MS
    return true
end

function M.removeItemFromCursor()
    if not M.hasItemOnCursor() then return false end
    local lp = state.lastPickup
    if lp and (lp.bag ~= nil or lp.slot ~= nil) and lp.slot ~= nil then
        if lp.source == "bank" then
            mq.cmdf('/itemnotify in bank%d %d leftmouseup', lp.bag, lp.slot)
        elseif lp.source == "equipped" then
            local slotName = deps.getEquipmentSlotNameForItemNotify and deps.getEquipmentSlotNameForItemNotify(lp.slot)
            if slotName then
                mq.cmdf('/itemnotify %s leftmouseup', slotName)
            else
                mq.cmd('/autoinv')
            end
        else
            mq.cmdf('/itemnotify in pack%d %d leftmouseup', lp.bag, lp.slot)
        end
        state.lastPickup.bag, state.lastPickup.slot, state.lastPickup.source = nil, nil, nil
        state.lastPickupClearedAt = mq.gettime()
    else
        mq.cmd('/autoinv')
    end
    return true
end

-- ============================================================================
-- Destroy item (inventory only; runs from main loop via pendingDestroyAction)
-- Non-blocking state machine (task 1.3): main_loop calls advanceDestroyStateMachine(now).
-- ============================================================================

local DESTROY_QTY_WINDOW_TIMEOUT_MS = 2000

--- Advance destroy state machine one step per frame (task 1.3). Call from main_loop when pendingDestroyAction is set. Clears state.pendingDestroyAction when done or on failure.
function M.advanceDestroyStateMachine(now)
    now = now or (mq.gettime and mq.gettime() or 0)
    local action = state.pendingDestroyAction
    if not action or not action.bag or not action.slot then return end
    local T = constants.TIMING
    local MEDIUM_MS = T.ITEM_OPS_DELAY_MEDIUM_MS
    local SHORT_MS = T.ITEM_OPS_DELAY_SHORT_MS
    local qty = (action.qty and action.qty > 0) and math.floor(action.qty) or 1
    local phase = action.phase or "start"
    action.phase = phase

    if phase == "start" then
        local w = mq.TLO and mq.TLO.Window and mq.TLO.Window("QuantityWnd")
        if w and w.Open and w.Open() then
            mq.cmd('/notify QuantityWnd QTYW_Cancel_Button leftmouseup')
            action.phase = "close_qty_delay"
            action.enteredAt = now
            return
        end
        action.phase = "pickup"
        return
    end

    if phase == "close_qty_delay" then
        if (now - (action.enteredAt or 0)) < MEDIUM_MS then return end
        action.phase = "pickup"
        return
    end

    if phase == "pickup" then
        mq.cmdf('/itemnotify in pack%d %d leftmouseup', action.bag, action.slot)
        if qty > 1 then
            action.phase = "wait_qty_window"
            action.enteredAt = now
        else
            action.phase = "pickup_delay"
            action.enteredAt = now
        end
        return
    end

    if phase == "pickup_delay" then
        if (now - (action.enteredAt or 0)) < SHORT_MS then return end
        action.phase = "confirm_destroy"
        return
    end

    if phase == "wait_qty_window" then
        local qtyWnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("QuantityWnd")
        if qtyWnd and qtyWnd.Open and qtyWnd.Open() then
            mq.cmd(string.format('/notify QuantityWnd QTYW_Slider newvalue %d', qty))
            action.phase = "qty_accept_delay"
            action.enteredAt = now
            return
        end
        if (now - (action.enteredAt or 0)) >= DESTROY_QTY_WINDOW_TIMEOUT_MS then
            state.pendingDestroyAction = nil
            deps.setStatusMessage("Quantity window did not open; destroy cancelled.")
            if deps.hasItemOnCursor and deps.hasItemOnCursor() then mq.cmd('/autoinv') end
            return
        end
        return
    end

    if phase == "qty_accept_delay" then
        if (now - (action.enteredAt or 0)) < MEDIUM_MS then return end
        mq.cmd('/notify QuantityWnd QTYW_Accept_Button leftmouseup')
        action.phase = "qty_close_delay"
        action.enteredAt = now
        return
    end

    if phase == "qty_close_delay" then
        if (now - (action.enteredAt or 0)) < SHORT_MS then return end
        action.phase = "confirm_destroy"
        return
    end

    if phase == "confirm_destroy" then
        mq.cmd('/destroy')
        state.lastPickup.bag, state.lastPickup.slot, state.lastPickup.source = nil, nil, nil
        state.lastPickupClearedAt = mq.gettime()
        M.reduceStackOrRemoveBySlot(action.bag, action.slot, qty)
        if deps.storage and deps.inventoryItems then deps.storage.saveInventory(deps.inventoryItems) end
        if deps.storage and deps.storage.writeSellCache and deps.sellItems then deps.storage.writeSellCache(deps.sellItems) end
        if deps.rescanInventoryBags then deps.rescanInventoryBags({ action.bag }) end
        local itemName = action.name
        local msg = itemName and (#itemName > 0) and ("Destroyed: " .. itemName) or "Destroyed item"
        if qty > 1 then msg = msg .. string.format(" (x%d)", qty) end
        deps.setStatusMessage(msg)
        state.pendingDestroyAction = nil
    end
end

return M
