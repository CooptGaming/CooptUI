--[[
    Main loop service: 10-phase tick for ItemUI.
    init(deps) stores dependencies; tick(now) runs one iteration (phases 1-10 + delay + doevents).
    P0-01: Sell macro finish uses deferred scan (no mq.delay in loop).
]]

local mq = require('mq')
local constants = require('itemui.constants')

local d  -- deps, set by init()

local function resolveAugmentQueueStep(queueType)
    local uiState, scanInventory, isBankWindowOpen, scanBank, refreshActiveItemDisplayTab, setStatusMessage =
        d.uiState, d.scanInventory, d.isBankWindowOpen, d.scanBank, d.refreshActiveItemDisplayTab, d.setStatusMessage
    if queueType == "optimize" then
        if uiState.optimizeQueue and uiState.optimizeQueue.steps and #uiState.optimizeQueue.steps > 0 then
            local oq = uiState.optimizeQueue
            local step = table.remove(oq.steps, 1)
            if step and step.slotIndex and step.augmentItem then
                local tab = (uiState.itemDisplayTabs and uiState.itemDisplayActiveTabIndex and uiState.itemDisplayTabs[uiState.itemDisplayActiveTabIndex]) or nil
                local targetItem = (tab and tab.item) and { id = tab.item.id or tab.item.ID, name = tab.item.name or tab.item.Name } or { id = 0, name = "" }
                uiState.pendingInsertAugment = {
                    targetItem = targetItem,
                    targetBag = oq.targetLoc.bag,
                    targetSlot = oq.targetLoc.slot,
                    targetSource = oq.targetLoc.source or "inv",
                    augmentItem = step.augmentItem,
                    slotIndex = step.slotIndex,
                }
            end
            if #oq.steps == 0 then uiState.optimizeQueue = nil end
        else
            local hadOptimize = (uiState.optimizeQueue ~= nil)
            if uiState.optimizeQueue then uiState.optimizeQueue = nil end
            scanInventory()
            if isBankWindowOpen() then scanBank() end
            refreshActiveItemDisplayTab()
            if hadOptimize and setStatusMessage then setStatusMessage("Optimize complete.") end
        end
    elseif queueType == "removeAll" then
        if uiState.removeAllQueue and uiState.removeAllQueue.slotIndices and #uiState.removeAllQueue.slotIndices > 0 then
            local q = uiState.removeAllQueue
            local slotIndex = table.remove(q.slotIndices, 1)
            uiState.pendingRemoveAugment = { bag = q.bag, slot = q.slot, source = q.source, slotIndex = slotIndex }
            if #q.slotIndices == 0 then uiState.removeAllQueue = nil end
        else
            local hadRemoveAll = (uiState.removeAllQueue ~= nil)
            if uiState.removeAllQueue then uiState.removeAllQueue = nil end
            scanInventory()
            if isBankWindowOpen() then scanBank() end
            refreshActiveItemDisplayTab()
            if hadRemoveAll and setStatusMessage then setStatusMessage("Remove all done.") end
        end
    end
end

-- Phase 1: Status message expiry
local function phase1_statusExpiry(now)
    local uiState, C = d.uiState, d.C
    if uiState.statusMessage ~= "" and (now - uiState.statusMessageTime) > (C.STATUS_MSG_SECS * 1000) then
        uiState.statusMessage = ""
    end
end

-- Phase 1b: Click-through protection — item on cursor we didn't initiate (e.g. focus click went to game)
-- Auto-bag and block new pickups for ACTIVATION_GUARD_MS to prevent rapid pickup/bag cycles.
local function phase1b_activationGuard(now)
    local uiState, hasItemOnCursor, setStatusMessage = d.uiState, d.hasItemOnCursor, d.setStatusMessage
    local C = constants.TIMING
    local guardMs = C and C.ACTIVATION_GUARD_MS or 450
    local graceMs = C and C.UNEXPECTED_CURSOR_GRACE_MS or 200
    if not hasItemOnCursor or not hasItemOnCursor() then return end
    local lp = uiState.lastPickup
    if lp and (lp.bag ~= nil or lp.slot ~= nil) then return end
    local clearedAt = uiState.lastPickupClearedAt or 0
    if (now - clearedAt) <= graceMs then return end
    mq.cmd('/autoinv')
    uiState.activationGuardUntil = now + guardMs
    uiState.lastPickupClearedAt = now
    local delayMs = (constants.TIMING and constants.TIMING.DEFERRED_SCAN_DELAY_MS) or 120
    uiState.deferredInventoryScanAt = now + delayMs
    if setStatusMessage then setStatusMessage("Put in bags (click-through protection)") end
end

-- Phase 2: Periodic persist (inventory/bank so data survives game close/crash)
local function phase2_periodicPersist(now)
    local C, scanState, storage, computeAndAttachSellStatus, isBankWindowOpen = d.C, d.scanState, d.storage, d.computeAndAttachSellStatus, d.isBankWindowOpen
    local inventoryItems, sellItems, bankItems, bankCache = d.inventoryItems, d.sellItems, d.bankItems, d.bankCache
    if (now - scanState.lastPersistSaveTime) >= C.PERSIST_SAVE_INTERVAL_MS then
        local charName = (mq.TLO and mq.TLO.Me and mq.TLO.Me.Name and mq.TLO.Me.Name()) or ""
        if charName ~= "" then
            storage.ensureCharFolderExists()
            if #sellItems > 0 then
                storage.saveInventory(sellItems)
                storage.writeSellCache(sellItems)
            elseif #inventoryItems > 0 then
                computeAndAttachSellStatus(inventoryItems)
                storage.saveInventory(inventoryItems)
                storage.writeSellCache(inventoryItems)
            end
            local bankToSave = (isBankWindowOpen() and bankItems and #bankItems > 0) and bankItems or bankCache
            if bankToSave and #bankToSave > 0 then
                storage.saveBank(bankToSave)
            end
            scanState.lastPersistSaveTime = now
        end
    end
end

-- Phase 3: Auto-sell request processing
local function phase3_autoSellRequest()
    local uiState, runSellMacro, setStatusMessage = d.uiState, d.runSellMacro, d.setStatusMessage
    if uiState.autoSellRequested then
        uiState.autoSellRequested = false
        runSellMacro()
        setStatusMessage("Running sell macro...")
    end
end

-- Phase 4: Sell macro finish detection + failed items (via macro bridge; P0-01: deferred scan, no mq.delay)
-- Use bridge running state (includes file-based fallback) so we detect finish and schedule inventory refresh even when Macro.Name() doesn't match
local function phase4_sellMacroFinish(now)
    local uiState, sellMacState, setStatusMessage, C = d.uiState, d.sellMacState, d.setStatusMessage, d.C
    local macroBridge = d.macroBridge
    local prog = (macroBridge and macroBridge.getSellProgress and macroBridge.getSellProgress()) or {}
    local sellMacRunning = (macroBridge and macroBridge.isSellMacroRunning and macroBridge.isSellMacroRunning()) or (prog.running == true)
    if sellMacState.lastRunning and not sellMacRunning then
        sellMacState.smoothedFrac = 0
        sellMacState.pendingScan = true
        sellMacState.finishedAt = now
        sellMacState.failedItems = {}
        sellMacState.failedCount = 0
        if macroBridge and macroBridge.getSellFailed then
            local failedItems, failedCount = macroBridge.getSellFailed()
            if failedCount and failedCount > 0 then
                sellMacState.failedCount = failedCount
                sellMacState.failedItems = failedItems or {}
                sellMacState.showFailedUntil = now + C.SELL_FAILED_DISPLAY_MS
                uiState.statusMessage = ""
            else
                setStatusMessage("Sell complete. Inventory refreshed.")
            end
        else
            setStatusMessage("Sell complete. Inventory refreshed.")
        end
        print("\ag[ItemUI]\ax Sell macro finished - inventory refreshed")
    end
    sellMacState.lastRunning = sellMacRunning
end

-- Phase 5: Loot macro management (progress, mythical alerts, session, deferred scan; via macro bridge)
-- Use bridge running state (includes file-based fallback from loot_progress.ini) so we detect finish and populate tables/history even when Macro.Name() doesn't match
local function phase5_lootMacro(now)
    local uiState, lootMacState, lootLoopRefs, config, getSellStatusForItem, loadLootHistoryFromFile, loadSkipHistoryFromFile =
        d.uiState, d.lootMacState, d.lootLoopRefs, d.config, d.getSellStatusForItem, d.loadLootHistoryFromFile, d.loadSkipHistoryFromFile
    local LOOT_HISTORY_MAX = d.LOOT_HISTORY_MAX
    local macroBridge = d.macroBridge
    local lootState = (macroBridge and macroBridge.getLootState and macroBridge.getLootState()) or {}
    local lootMacRunning = (macroBridge and macroBridge.isLootMacroRunning and macroBridge.isLootMacroRunning()) or (lootState.running == true)
    if lootMacRunning and not lootMacState.lastRunning and not uiState.suppressWhenLootMac then
        uiState.lootUIOpen = true
        uiState.lootRunFinished = false
        d.recordCompanionWindowOpened("loot")
    end
    if lootMacState.lastRunning and not lootMacRunning then
        lootMacState.pendingScan = true
        lootMacState.finishedAt = now
        d.scanState.inventoryBagsDirty = true
        lootLoopRefs.pendingSession = true
        lootLoopRefs.pendingSessionAt = now
        local alertPath = config.getLootConfigFile and config.getLootConfigFile("loot_mythical_alert.ini")
        if alertPath and alertPath ~= "" then
            local itemName = config.safeIniValueByPath(alertPath, "Alert", "itemName", "")
            if itemName and itemName ~= "" then
                local decision = config.safeIniValueByPath(alertPath, "Alert", "decision", "") or "pending"
                local iconStr = config.safeIniValueByPath(alertPath, "Alert", "iconId", "") or "0"
                local prevName = uiState.lootMythicalAlert and uiState.lootMythicalAlert.itemName
                uiState.lootMythicalAlert = {
                    itemName = itemName,
                    corpseName = config.safeIniValueByPath(alertPath, "Alert", "corpseName", "") or "",
                    decision = decision,
                    itemLink = config.safeIniValueByPath(alertPath, "Alert", "itemLink", "") or "",
                    timestamp = config.safeIniValueByPath(alertPath, "Alert", "timestamp", "") or "",
                    iconId = tonumber(iconStr) or 0
                }
                if decision == "pending" then
                    if not prevName or prevName ~= itemName then
                        uiState.lootMythicalDecisionStartAt = os.time and os.time() or 0
                    end
                else
                    uiState.lootMythicalDecisionStartAt = nil
                end
                uiState.lootUIOpen = true
                d.recordCompanionWindowOpened("loot")
            end
        end
    end
    local sessionReadDelay = constants.TIMING.LOOT_SESSION_READ_DELAY_MS or 150
    if lootLoopRefs.pendingSession and (now - (lootLoopRefs.pendingSessionAt or 0)) >= sessionReadDelay then
        lootLoopRefs.pendingSession = nil
        lootLoopRefs.pendingSessionAt = 0
        local session = nil
        if uiState.lootUIOpen and macroBridge and macroBridge.getLootSession then
            session = macroBridge.getLootSession()
            if session and session.count and session.count > 0 then
                uiState.lootRunLootedList = {}
                uiState.lootRunLootedItems = {}
                for i, row in ipairs(session.items or {}) do
                    local name = row.name
                    if name and name ~= "" then
                        table.insert(uiState.lootRunLootedList, name)
                        local statusText, willSell = "—", false
                        if getSellStatusForItem and i <= lootLoopRefs.sellStatusCap then
                            statusText, willSell = getSellStatusForItem({ name = name })
                            if statusText == "" then statusText = "—" end
                        end
                        table.insert(uiState.lootRunLootedItems, {
                            name = name,
                            value = row.value or 0,
                            tribute = row.tribute or 0,
                            statusText = statusText,
                            willSell = willSell
                        })
                    end
                end
            end
        end
        if uiState.lootUIOpen then
            local skippedPath = config.getLootConfigFile and config.getLootConfigFile("loot_skipped.ini")
            if skippedPath and skippedPath ~= "" then
                local skipCountStr = config.safeIniValueByPath(skippedPath, "Skipped", "count", "0")
                local skipCount = tonumber(skipCountStr) or 0
                if skipCount > 0 then
                    if not uiState.skipHistory and loadSkipHistoryFromFile then loadSkipHistoryFromFile() end
                    if not uiState.skipHistory then uiState.skipHistory = {} end
                    for j = 1, skipCount do
                        local raw = config.safeIniValueByPath(skippedPath, "Skipped", tostring(j), "")
                        if raw and raw ~= "" then
                            local name, reason = raw:match("^([^%^]*)%^?(.*)$")
                            table.insert(uiState.skipHistory, { name = name or raw, reason = reason or "" })
                        end
                    end
                    while #uiState.skipHistory > LOOT_HISTORY_MAX do table.remove(uiState.skipHistory, 1) end
                    lootLoopRefs.saveSkipAt = now + lootLoopRefs.deferMs
                end
            end
            -- Populate session summary and loot history whenever we have session (not only when skipped path exists)
            if session then
                uiState.lootRunTotalValue = session.totalValue or 0
                uiState.lootRunTributeValue = session.tributeValue or 0
                uiState.lootRunBestItemName = session.bestItemName or ""
                uiState.lootRunBestItemValue = session.bestItemValue or 0
                if not uiState.lootHistory then loadLootHistoryFromFile() end
                if not uiState.lootHistory then uiState.lootHistory = {} end
                for _, row in ipairs(uiState.lootRunLootedItems or {}) do
                    table.insert(uiState.lootHistory, { name = row.name, value = row.value, statusText = row.statusText, willSell = row.willSell })
                end
                while #uiState.lootHistory > LOOT_HISTORY_MAX do table.remove(uiState.lootHistory, 1) end
                lootLoopRefs.saveHistoryAt = now + lootLoopRefs.deferMs
            end
            uiState.lootRunFinished = true
        end
    end
    local pollInterval = lootMacRunning and lootLoopRefs.pollMs or (lootLoopRefs.pollMsIdle or 1000)
    if (lootMacRunning or uiState.lootUIOpen) and (now - lootLoopRefs.pollAt) >= pollInterval then
        lootLoopRefs.pollAt = now
        if macroBridge and macroBridge.pollLootProgress then
            local corpses, total, current = macroBridge.pollLootProgress()
            uiState.lootRunCorpsesLooted = corpses
            uiState.lootRunTotalCorpses = total
            uiState.lootRunCurrentCorpse = current or ""
        end
        if lootMacRunning then
            local alertPath = config.getLootConfigFile and config.getLootConfigFile("loot_mythical_alert.ini")
            if alertPath and alertPath ~= "" then
                local itemName = config.safeIniValueByPath(alertPath, "Alert", "itemName", "")
                if itemName and itemName ~= "" then
                    local decision = config.safeIniValueByPath(alertPath, "Alert", "decision", "") or "pending"
                    local iconStr = config.safeIniValueByPath(alertPath, "Alert", "iconId", "") or "0"
                    local prevName = uiState.lootMythicalAlert and uiState.lootMythicalAlert.itemName
                    uiState.lootMythicalAlert = {
                        itemName = itemName,
                        corpseName = config.safeIniValueByPath(alertPath, "Alert", "corpseName", "") or "",
                        decision = decision,
                        itemLink = config.safeIniValueByPath(alertPath, "Alert", "itemLink", "") or "",
                        timestamp = config.safeIniValueByPath(alertPath, "Alert", "timestamp", "") or "",
                        iconId = tonumber(iconStr) or 0
                    }
                    if decision == "pending" then
                        if not prevName or prevName ~= itemName then
                            uiState.lootMythicalDecisionStartAt = os.time and os.time() or 0
                        end
                    else
                        uiState.lootMythicalDecisionStartAt = nil
                    end
                    uiState.lootUIOpen = true
                    d.recordCompanionWindowOpened("loot")
                else
                    uiState.lootMythicalAlert = nil
                    uiState.lootMythicalDecisionStartAt = nil
                end
            end
        end
    end
    lootMacState.lastRunning = lootMacRunning
end

-- Phase 6: Deferred history saves
local function phase6_deferredHistorySaves(now)
    local lootLoopRefs = d.lootLoopRefs
    if lootLoopRefs.saveHistoryAt > 0 and now >= lootLoopRefs.saveHistoryAt then
        lootLoopRefs.saveHistoryAt = 0
        lootLoopRefs.saveLootHistory()
    end
    if lootLoopRefs.saveSkipAt > 0 and now >= lootLoopRefs.saveSkipAt then
        lootLoopRefs.saveSkipAt = 0
        lootLoopRefs.saveSkipHistory()
    end
end

-- Phase 7: Sell queue + quantity picker + destroy + move + augment queue start (remove all/optimize pop + execute)
local function phase7_sellQueueQuantityDestroyMoveAugment(now)
    local uiState, processSellQueue, itemOps, augmentOps, hasItemOnCursor, setStatusMessage = d.uiState, d.processSellQueue, d.itemOps, d.augmentOps, d.hasItemOnCursor, d.setStatusMessage
    processSellQueue()
    if uiState.pendingQuantityAction then
        local action = uiState.pendingQuantityAction
        -- Set lastPickup so activation guard (phase 1b) does not treat this as unexpected cursor
        uiState.lastPickup.bag = action.pickup.bag
        uiState.lastPickup.slot = action.pickup.slot
        uiState.lastPickup.source = action.pickup.source
        if action.pickup.source == "bank" then
            mq.cmdf('/itemnotify in bank%d %d leftmouseup', action.pickup.bag, action.pickup.slot)
        else
            mq.cmdf('/itemnotify in pack%d %d leftmouseup', action.pickup.bag, action.pickup.slot)
        end
        mq.delay(300, function()
            local w = mq.TLO and mq.TLO.Window and mq.TLO.Window("QuantityWnd")
            return w and w.Open and w.Open()
        end)
        local qtyWndOpen = (function()
            local w = mq.TLO and mq.TLO.Window and mq.TLO.Window("QuantityWnd")
            return w and w.Open and w.Open()
        end)()
        if qtyWndOpen then
            mq.cmd(string.format('/notify QuantityWnd QTYW_Slider newvalue %d', action.qty))
            mq.delay(150)
            mq.cmd('/notify QuantityWnd QTYW_Accept_Button leftmouseup')
        end
        -- Clear only after quantity flow completes so main_window does not clear lastPickup during the delay
        uiState.pendingQuantityAction = nil
    end
    -- Script items (Alt Currency): sequential right-click consumption; one use per tick, delay between each.
    -- After each right-click: update in-memory lists (reduceStackOrRemoveBySlot / reduceStackOrRemoveBySlotBank) so UI shows real-time decrement.
    -- On completion or halt: persist with same pattern as performDestroyItem (saveInventory/writeSellCache for inv, saveBank for bank).
    if uiState.pendingScriptConsume then
        local ps = uiState.pendingScriptConsume
        local delayMs = (constants.TIMING and constants.TIMING.SCRIPT_CONSUME_DELAY_MS) or 300
        local shouldFire = (ps.nextClickAt > 0 and now >= ps.nextClickAt) or (ps.nextClickAt == 0 and ps.consumedSoFar == 0)
        if shouldFire then
            local Me = mq.TLO and mq.TLO.Me
            local stack = 0
            if ps.source == "bank" then
                local bn = Me and Me.Bank and Me.Bank(ps.bag)
                local it = bn and bn.Item and bn.Item(ps.slot)
                stack = (it and it.Stack and it.Stack()) or 0
            else
                local pack = Me and Me.Inventory and Me.Inventory("pack" .. ps.bag)
                local it = pack and pack.Item and pack.Item(ps.slot)
                stack = (it and it.Stack and it.Stack()) or 0
            end
            if stack < 1 then
                local n = ps.consumedSoFar
                local src = ps.source
                uiState.pendingScriptConsume = nil
                if setStatusMessage then setStatusMessage(string.format("Added %d to Alt Currency; item moved or depleted.", n)) end
                if d.storage then
                    if src == "inv" then
                        if d.inventoryItems then d.storage.saveInventory(d.inventoryItems) end
                        if d.storage.writeSellCache and d.sellItems then d.storage.writeSellCache(d.sellItems) end
                    elseif src == "bank" and d.bankItems then
                        d.storage.saveBank(d.bankItems)
                    end
                end
            else
                if ps.source == "bank" then
                    mq.cmdf('/itemnotify in bank%d %d rightmouseup', ps.bag, ps.slot)
                else
                    mq.cmdf('/itemnotify in pack%d %d rightmouseup', ps.bag, ps.slot)
                end
                ps.consumedSoFar = ps.consumedSoFar + 1
                if ps.source == "bank" then
                    itemOps.reduceStackOrRemoveBySlotBank(ps.bag, ps.slot, 1)
                else
                    itemOps.reduceStackOrRemoveBySlot(ps.bag, ps.slot, 1)
                end
                if ps.consumedSoFar >= ps.totalToConsume then
                    local src = ps.source
                    uiState.pendingScriptConsume = nil
                    if setStatusMessage then setStatusMessage(string.format("Added %d to Alt Currency.", ps.consumedSoFar)) end
                    if d.storage then
                        if src == "inv" then
                            if d.inventoryItems then d.storage.saveInventory(d.inventoryItems) end
                            if d.storage.writeSellCache and d.sellItems then d.storage.writeSellCache(d.sellItems) end
                        elseif src == "bank" and d.bankItems then
                            d.storage.saveBank(d.bankItems)
                        end
                    end
                else
                    ps.nextClickAt = now + delayMs
                    if setStatusMessage then setStatusMessage(string.format("Alt Currency: %d / %d", ps.consumedSoFar, ps.totalToConsume)) end
                end
            end
        end
    end
    if uiState.pendingDestroyAction then
        local pd = uiState.pendingDestroyAction
        uiState.pendingDestroyAction = nil
        uiState.pendingQuantityPickup = nil
        uiState.pendingQuantityPickupTimeoutAt = nil
        uiState.quantityPickerValue = ""
        itemOps.performDestroyItem(pd.bag, pd.slot, pd.name, pd.qty)
    end
    if uiState.pendingMoveAction then
        uiState.pendingQuantityPickup = nil
        uiState.pendingQuantityPickupTimeoutAt = nil
        uiState.quantityPickerValue = ""
        itemOps.executeMoveAction(uiState.pendingMoveAction)
        uiState.pendingMoveAction = nil
    end
    -- Reroll bank-to-bag: one move per tick (so each item lands before the next); stack moves set pendingMoveAction
    -- and are completed in the block above. Only when no move is in flight do we start the next or trigger the roll.
    if uiState.pendingRerollBankMoves and not uiState.pendingMoveAction then
        local pm = uiState.pendingRerollBankMoves
        local items = pm.items or {}
        local idx = pm.nextIndex or 1
        if d.isBankWindowOpen and not d.isBankWindowOpen() then
            uiState.pendingRerollBankMoves = nil
            if d.setStatusMessage then d.setStatusMessage("Bank closed; roll cancelled.") end
        elseif idx <= #items then
            local one = items[idx]
            if one and one.bag and one.slot then
                local ok = d.itemOps.moveBankToInv(one.bag, one.slot)
                pm.nextIndex = idx + 1
                if not ok and d.setStatusMessage then d.setStatusMessage("Move from bank failed; roll cancelled.") end
                if not ok then uiState.pendingRerollBankMoves = nil end
            else
                pm.nextIndex = idx + 1
            end
        end
        if pm.nextIndex and pm.nextIndex > #items then
            uiState.pendingRerollBankMoves = nil
            if d.rerollService then
                if pm.list == "aug" then
                    d.rerollService.augRoll()
                    uiState.pendingAugRollComplete = true
                    uiState.pendingAugRollCompleteAt = now
                else
                    d.rerollService.mythicalRoll()
                end
            end
            if d.setStatusMessage then d.setStatusMessage("Roll sent.") end
        end
    end
    if uiState.removeAllQueue and uiState.removeAllQueue.slotIndices and #uiState.removeAllQueue.slotIndices > 0
        and not uiState.pendingRemoveAugment and not uiState.waitingForRemoveConfirmation and not uiState.waitingForRemoveCursorPopulated then
        local q = uiState.removeAllQueue
        local slotIndex = table.remove(q.slotIndices, 1)
        uiState.pendingRemoveAugment = { bag = q.bag, slot = q.slot, source = q.source, slotIndex = slotIndex }
        if #q.slotIndices == 0 then uiState.removeAllQueue = nil end
    end
    if uiState.pendingRemoveAugment then
        local ra = uiState.pendingRemoveAugment
        uiState.pendingRemoveAugment = nil
        augmentOps.removeAugment(ra.bag, ra.slot, ra.source, ra.slotIndex)
        uiState.removeConfirmationSetAt = mq.gettime()
    end
    if uiState.optimizeQueue and uiState.optimizeQueue.steps and #uiState.optimizeQueue.steps > 0
        and not uiState.pendingInsertAugment and not uiState.waitingForInsertConfirmation and not uiState.waitingForInsertCursorClear then
        local oq = uiState.optimizeQueue
        local step = table.remove(oq.steps, 1)
        if step and step.slotIndex and step.augmentItem then
            local tab = (uiState.itemDisplayTabs and uiState.itemDisplayActiveTabIndex and uiState.itemDisplayTabs[uiState.itemDisplayActiveTabIndex]) or nil
            local targetItem = (tab and tab.item) and { id = tab.item.id or tab.item.ID, name = tab.item.name or tab.item.Name } or { id = 0, name = "" }
            uiState.pendingInsertAugment = {
                targetItem = targetItem,
                targetBag = oq.targetLoc.bag,
                targetSlot = oq.targetLoc.slot,
                targetSource = oq.targetLoc.source or "inv",
                augmentItem = step.augmentItem,
                slotIndex = step.slotIndex,
            }
            uiState.insertConfirmationSetAt = mq.gettime()
        end
    end
    if uiState.pendingInsertAugment then
        local pa = uiState.pendingInsertAugment
        uiState.pendingInsertAugment = nil
        uiState.itemDisplayAugmentSlotActive = nil
        augmentOps.insertAugment(pa.targetItem, pa.augmentItem, pa.slotIndex, pa.targetBag, pa.targetSlot, pa.targetSource)
        uiState.insertConfirmationSetAt = mq.gettime()
    end
    if uiState.pendingQuantityPickup then
        local nowQ = mq.gettime()
        if uiState.pendingQuantityPickupTimeoutAt and nowQ >= uiState.pendingQuantityPickupTimeoutAt then
            uiState.pendingQuantityPickup = nil
            uiState.pendingQuantityPickupTimeoutAt = nil
            uiState.quantityPickerValue = ""
            setStatusMessage("Quantity picker cancelled")
        else
            local qtyWnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("QuantityWnd")
            local qtyWndOpen = qtyWnd and qtyWnd.Open and qtyWnd.Open() or false
            local hasCursor = hasItemOnCursor()
            if not qtyWndOpen and not hasCursor then
                local itemExists = false
                local Me = mq.TLO and mq.TLO.Me
                if uiState.pendingQuantityPickup.source == "bank" then
                    local bn = Me and Me.Bank and Me.Bank(uiState.pendingQuantityPickup.bag)
                    local sz = bn and bn.Container and bn.Container()
                    local it = (bn and sz and sz > 0) and (bn.Item and bn.Item(uiState.pendingQuantityPickup.slot)) or bn
                    itemExists = it and it.ID and it.ID() and it.ID() > 0
                else
                    local pack = Me and Me.Inventory and Me.Inventory("pack" .. uiState.pendingQuantityPickup.bag)
                    local it = pack and pack.Item and pack.Item(uiState.pendingQuantityPickup.slot)
                    itemExists = it and it.ID and it.ID() and it.ID() > 0
                end
                if not itemExists then
                    uiState.pendingQuantityPickup = nil
                    uiState.pendingQuantityPickupTimeoutAt = nil
                    uiState.quantityPickerValue = ""
                end
            elseif hasCursor then
                uiState.pendingQuantityPickup = nil
                uiState.pendingQuantityPickupTimeoutAt = nil
                uiState.quantityPickerValue = ""
            end
        end
    end
end

-- Phase 8: Window state, deferred scans, auto-show/hide, stats tab priming, loot/sell pending scan (P0-01), augment timeouts
local function phase8_windowStateDeferredScansAutoShowAugmentTimeouts(now)
    local uiState, scanState, deferredScanNeeded, perfCache, C = d.uiState, d.scanState, d.deferredScanNeeded, d.perfCache, d.C
    local inventoryItems, sellItems, bankItems, bankCache = d.inventoryItems, d.sellItems, d.bankItems, d.bankCache
    local sellMacState, lootMacState = d.sellMacState, d.lootMacState
    local isBankWindowOpen, isMerchantWindowOpen, isLootWindowOpen = d.isBankWindowOpen, d.isMerchantWindowOpen, d.isLootWindowOpen
    local maybeScanInventory, maybeScanBank, maybeScanSellItems = d.maybeScanInventory, d.maybeScanBank, d.maybeScanSellItems
    local computeAndAttachSellStatus, sellStatusService, scanInventory, scanSellItems = d.computeAndAttachSellStatus, d.sellStatusService, d.scanInventory, d.scanSellItems
    local rescanInventoryBags = d.rescanInventoryBags
    local invalidateSortCache, flushLayoutSave, loadLayoutConfig, recordCompanionWindowOpened = d.invalidateSortCache, d.flushLayoutSave, d.loadLayoutConfig, d.recordCompanionWindowOpened
    local storage, augmentOps, hasItemOnCursor, setStatusMessage = d.storage, d.augmentOps, d.hasItemOnCursor, d.setStatusMessage
    local saveLayoutToFileImmediate = d.saveLayoutToFileImmediate
    local STATS_TAB_PRIME_MS = d.STATS_TAB_PRIME_MS
    local getLastInventoryWindowState, setLastInventoryWindowState = d.getLastInventoryWindowState, d.setLastInventoryWindowState
    local getLastBankWindowState, setLastBankWindowState = d.getLastBankWindowState, d.setLastBankWindowState
    local getLastMerchantState, setLastMerchantState = d.getLastMerchantState, d.setLastMerchantState
    local getLastLootWindowState, setLastLootWindowState = d.getLastLootWindowState, d.setLastLootWindowState
    local getShouldDraw, setShouldDraw = d.getShouldDraw, d.setShouldDraw
    local getOpen, setOpen = d.getOpen, d.setOpen
    local getStatsTabPrimeState, setStatsTabPrimeState = d.getStatsTabPrimeState, d.setStatsTabPrimeState
    local getStatsTabPrimeAt, setStatsTabPrimeAt = d.getStatsTabPrimeAt, d.setStatsTabPrimeAt
    local getStatsTabPrimedThisSession, setStatsTabPrimedThisSession = d.getStatsTabPrimedThisSession, d.setStatsTabPrimedThisSession
    local clearLootItems = d.clearLootItems

    -- Decrement force-apply layout frames after revert (so positions/sizes re-apply from layoutConfig)
    if uiState.layoutRevertedApplyFrames and uiState.layoutRevertedApplyFrames > 0 then
        uiState.layoutRevertedApplyFrames = uiState.layoutRevertedApplyFrames - 1
    end
    local invWndLoop = mq.TLO and mq.TLO.Window and mq.TLO.Window("InventoryWindow")
    local invOpen = (invWndLoop and invWndLoop.Open and invWndLoop.Open()) or false
    local bankOpen = isBankWindowOpen()
    local merchOpen = isMerchantWindowOpen()
    local lootOpen = isLootWindowOpen()
    local lastBankWindowState = getLastBankWindowState()
    local lastLootWindowState = getLastLootWindowState()
    local bankJustOpened = bankOpen and not lastBankWindowState
    local lootJustClosed = lastLootWindowState and not lootOpen
    if lootOpen or lootJustClosed then scanState.inventoryBagsDirty = true end
    local shouldDraw = getShouldDraw()
    local shouldDrawBefore = shouldDraw
    local lastInventoryWindowState = getLastInventoryWindowState()
    local lastMerchantState = getLastMerchantState()

    if deferredScanNeeded.inventory then maybeScanInventory(invOpen); deferredScanNeeded.inventory = false end
    if deferredScanNeeded.bank then maybeScanBank(bankOpen); deferredScanNeeded.bank = false end
    if deferredScanNeeded.sell then maybeScanSellItems(merchOpen); deferredScanNeeded.sell = false end
    -- MASTER_PLAN 2.6: targeted rescan for bags that had _statsPending (e.g. ID was 0 during batch)
    if uiState.pendingStatRescanBags and next(uiState.pendingStatRescanBags) and rescanInventoryBags then
        local bags = {}
        for b in pairs(uiState.pendingStatRescanBags) do bags[#bags + 1] = b end
        rescanInventoryBags(bags)
        uiState.pendingStatRescanBags = {}
    end
    if perfCache.sellConfigPendingRefresh then
        if perfCache.sellConfigCache then sellStatusService.invalidateSellConfigCache() end
        computeAndAttachSellStatus(inventoryItems)
        if sellItems and #sellItems > 0 then computeAndAttachSellStatus(sellItems) end
        if bankItems and #bankItems > 0 then computeAndAttachSellStatus(bankItems) end
        perfCache.sellConfigPendingRefresh = false
    end

    local invJustOpened = invOpen and not lastInventoryWindowState
    local statsTabPrimedThisSession = getStatsTabPrimedThisSession()
    if invJustOpened and invOpen and not statsTabPrimedThisSession then
        mq.cmd('/notify InventoryWindow IW_Subwindows tabselect 2')
        setStatsTabPrimeState('shown')
        setStatsTabPrimeAt(now)
        setStatsTabPrimedThisSession(true)
    end
    local statsTabPrimeState = getStatsTabPrimeState()
    local statsTabPrimeAt = getStatsTabPrimeAt()
    if statsTabPrimeState == 'shown' and invOpen and (now - statsTabPrimeAt) >= STATS_TAB_PRIME_MS then
        mq.cmd('/notify InventoryWindow IW_Subwindows tabselect 1')
        setStatsTabPrimeState(nil)
    end
    if lastInventoryWindowState and not invOpen then setStatsTabPrimeState(nil) end

    local lootMacName = ((mq.TLO and mq.TLO.Macro and mq.TLO.Macro.Name and (mq.TLO.Macro.Name() or "")) or ""):lower()
    local lootMacRunning = (lootMacName == "loot" or lootMacName == "loot.mac")
    if invJustOpened and invOpen and not (lootOpen or lootMacRunning) then
        mq.cmd('/keypress OPEN_INV_BAGS')
    end
    if (lootOpen or lootMacRunning) and shouldDraw then
        flushLayoutSave()
        setShouldDraw(false)
        setOpen(false)
        uiState.configWindowOpen = false
        if invOpen then mq.cmd('/keypress inventory') end
    end
    local shouldAutoShowInv = invJustOpened and not (lootOpen or lootMacRunning)
    if lootMacState.pendingScan then
        local userOpening = shouldAutoShowInv or bankJustOpened or (merchOpen and not lastMerchantState) or shouldDraw
        local elapsed = now - (lootMacState.finishedAt or 0)
        if not userOpening and elapsed >= C.LOOT_PENDING_SCAN_DELAY_MS then
            scanInventory()
            invalidateSortCache("inv")
            lootMacState.pendingScan = false
        end
    end
    -- P0-01: Deferred sell macro finish scan (no mq.delay in loop). Only clear pendingScan after we actually scan.
    if sellMacState.pendingScan then
        local elapsed = now - (sellMacState.finishedAt or 0)
        if elapsed >= C.SELL_PENDING_SCAN_DELAY_MS then
            scanInventory()
            if isMerchantWindowOpen() then scanSellItems() end
            invalidateSortCache("inv"); invalidateSortCache("sell")
            sellMacState.pendingScan = false
        end
    end
    if shouldAutoShowInv or bankJustOpened or (merchOpen and not lastMerchantState) then
        if not shouldDraw then
            setShouldDraw(true)
            setOpen(true)
            loadLayoutConfig()
            uiState.bankWindowOpen = bankJustOpened
            uiState.bankWindowShouldDraw = uiState.bankWindowOpen
            if bankJustOpened then recordCompanionWindowOpened("bank") end
            uiState.equipmentWindowOpen = true
            uiState.equipmentWindowShouldDraw = true
            recordCompanionWindowOpened("equipment")
            if bankJustOpened then
                maybeScanBank(bankOpen)
                deferredScanNeeded.inventory = invOpen
                deferredScanNeeded.sell = merchOpen
            elseif merchOpen and not lastMerchantState then
                maybeScanInventory(invOpen)
                deferredScanNeeded.sell = true
                deferredScanNeeded.bank = bankOpen
            else
                maybeScanInventory(invOpen)
                deferredScanNeeded.bank = bankOpen
                deferredScanNeeded.sell = merchOpen
            end
        end
    end
    if bankOpen and not shouldDraw then
        setShouldDraw(true)
        setOpen(true)
        loadLayoutConfig()
        uiState.bankWindowOpen = true
        uiState.bankWindowShouldDraw = true
        uiState.equipmentWindowOpen = true
        uiState.equipmentWindowShouldDraw = true
        recordCompanionWindowOpened("bank")
        recordCompanionWindowOpened("equipment")
        maybeScanBank(bankOpen)
        deferredScanNeeded.inventory = invOpen
        deferredScanNeeded.sell = merchOpen
    end
    if lootMacRunning and lootJustClosed then
        setShouldDraw(false)
        setOpen(false)
        uiState.configWindowOpen = false
        if invOpen then mq.cmd('/keypress inventory') end
    end
    if lastInventoryWindowState and not invOpen then
        mq.cmd('/keypress CLOSE_INV_BAGS')
        storage.ensureCharFolderExists()
        if #sellItems > 0 then
            storage.saveInventory(sellItems)
            storage.writeSellCache(sellItems)
        else
            computeAndAttachSellStatus(inventoryItems)
            storage.saveInventory(inventoryItems)
            storage.writeSellCache(inventoryItems)
        end
        local bankToSave = bankOpen and bankItems or bankCache
        if bankToSave and #bankToSave > 0 then storage.saveBank(bankToSave) end
        flushLayoutSave()
        setShouldDraw(false)
        setOpen(false)
        uiState.configWindowOpen = false
    end
    if bankJustOpened and shouldDrawBefore then
        uiState.bankWindowOpen = true
        uiState.bankWindowShouldDraw = true
        maybeScanBank(bankOpen)
    elseif bankJustOpened then
        uiState.bankWindowOpen = true
        uiState.bankWindowShouldDraw = true
    end
    if lastInventoryWindowState and not invOpen then scanState.lastScanState.invOpen = false end
    if lastBankWindowState and not bankOpen then scanState.lastScanState.bankOpen = false end
    if lastMerchantState and not merchOpen then scanState.lastScanState.merchOpen = false end
    local lootOpenNow = isLootWindowOpen()
    local lootJustOpened = lootOpenNow and not lastLootWindowState
    if lootJustOpened then
        local mn = ((mq.TLO and mq.TLO.Macro and mq.TLO.Macro.Name and (mq.TLO.Macro.Name() or "")) or ""):lower()
        local lootMacRunning2 = (mn == "loot" or mn == "loot.mac")
        if not lootMacRunning2 and not uiState.suppressWhenLootMac then
            uiState.lootUIOpen = true
            recordCompanionWindowOpened("loot")
        end
    end
    if lootOpenNow then
        local confirmWnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("ConfirmationDialogBox")
        if confirmWnd and confirmWnd.Open and confirmWnd.Open() then
            mq.cmd('/notify ConfirmationDialogBox CD_Yes_Button leftmouseup')
        end
    end

    local T = constants.TIMING
    local AUGMENT_CURSOR_CLEAR_TIMEOUT_MS = T.AUGMENT_CURSOR_CLEAR_TIMEOUT_MS
    local AUGMENT_CURSOR_POPULATED_TIMEOUT_MS = T.AUGMENT_CURSOR_POPULATED_TIMEOUT_MS
    local AUGMENT_INSERT_NO_CONFIRM_FALLBACK_MS = T.AUGMENT_INSERT_NO_CONFIRM_FALLBACK_MS
    local AUGMENT_REMOVE_NO_CONFIRM_FALLBACK_MS = T.AUGMENT_REMOVE_NO_CONFIRM_FALLBACK_MS
    local itemDisplayOpen = augmentOps.isItemDisplayWindowOpen and augmentOps.isItemDisplayWindowOpen()
    if uiState.waitingForInsertCursorClear and not itemDisplayOpen then
        uiState.waitingForInsertCursorClear = false
        uiState.insertCursorClearTimeoutAt = nil
        uiState.insertConfirmationSetAt = nil
    end
    if uiState.waitingForRemoveCursorPopulated and not itemDisplayOpen then
        uiState.waitingForRemoveCursorPopulated = false
        uiState.removeCursorPopulatedTimeoutAt = nil
        uiState.removeConfirmationSetAt = nil
    end
    local confirmDialogOpen = false
    do
        local confirmWnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("ConfirmationDialogBox")
        confirmDialogOpen = confirmWnd and confirmWnd.Open and confirmWnd.Open()
    end
    if uiState.waitingForRemoveConfirmation and confirmDialogOpen then
        mq.cmd('/notify ConfirmationDialogBox CD_Yes_Button leftmouseup')
        uiState.waitingForRemoveConfirmation = false
        uiState.removeConfirmationSetAt = nil
        uiState.waitingForRemoveCursorPopulated = true
        uiState.removeCursorPopulatedTimeoutAt = mq.gettime()
    end
    if uiState.waitingForInsertConfirmation and confirmDialogOpen then
        mq.cmd('/notify ConfirmationDialogBox CD_Yes_Button leftmouseup')
        uiState.waitingForInsertConfirmation = false
        uiState.insertConfirmationSetAt = nil
        uiState.waitingForInsertCursorClear = true
        uiState.insertCursorClearTimeoutAt = mq.gettime()
    end
    if uiState.waitingForInsertConfirmation and not confirmDialogOpen and uiState.insertConfirmationSetAt and (now - uiState.insertConfirmationSetAt) > AUGMENT_INSERT_NO_CONFIRM_FALLBACK_MS then
        if augmentOps.closeItemDisplayWindow then augmentOps.closeItemDisplayWindow() end
        if hasItemOnCursor() then setStatusMessage("Insert may have failed; check cursor.") end
        uiState.waitingForInsertConfirmation = false
        uiState.insertConfirmationSetAt = nil
    end
    if uiState.waitingForRemoveConfirmation and not confirmDialogOpen and uiState.removeConfirmationSetAt and (now - uiState.removeConfirmationSetAt) > AUGMENT_REMOVE_NO_CONFIRM_FALLBACK_MS then
        if augmentOps.closeItemDisplayWindow then augmentOps.closeItemDisplayWindow() end
        if hasItemOnCursor() then mq.cmd('/autoinv') end
        uiState.waitingForRemoveConfirmation = false
        uiState.removeConfirmationSetAt = nil
        uiState.waitingForRemoveCursorPopulated = false
        uiState.removeCursorPopulatedTimeoutAt = nil
    end
    if uiState.waitingForInsertCursorClear then
        if (uiState.insertCursorClearTimeoutAt and (now - uiState.insertCursorClearTimeoutAt) > AUGMENT_CURSOR_CLEAR_TIMEOUT_MS) then
            if augmentOps.closeItemDisplayWindow then augmentOps.closeItemDisplayWindow() end
            setStatusMessage("Insert timed out; check cursor.")
            uiState.waitingForInsertCursorClear = false
            uiState.insertCursorClearTimeoutAt = nil
            uiState.insertConfirmationSetAt = nil
            resolveAugmentQueueStep("optimize")
        elseif not hasItemOnCursor() then
            if augmentOps.closeItemDisplayWindow then augmentOps.closeItemDisplayWindow() end
            uiState.waitingForInsertCursorClear = false
            uiState.insertCursorClearTimeoutAt = nil
            uiState.insertConfirmationSetAt = nil
            resolveAugmentQueueStep("optimize")
        end
    end
    if uiState.waitingForRemoveCursorPopulated then
        if (uiState.removeCursorPopulatedTimeoutAt and (now - uiState.removeCursorPopulatedTimeoutAt) > AUGMENT_CURSOR_POPULATED_TIMEOUT_MS) then
            if augmentOps.closeItemDisplayWindow then augmentOps.closeItemDisplayWindow() end
            setStatusMessage("Remove timed out; check cursor.")
            uiState.waitingForRemoveCursorPopulated = false
            uiState.removeCursorPopulatedTimeoutAt = nil
            uiState.removeConfirmationSetAt = nil
            resolveAugmentQueueStep("removeAll")
        elseif hasItemOnCursor() then
            if augmentOps.closeItemDisplayWindow then augmentOps.closeItemDisplayWindow() end
            mq.cmd('/autoinv')
            uiState.waitingForRemoveCursorPopulated = false
            uiState.removeCursorPopulatedTimeoutAt = nil
            uiState.removeConfirmationSetAt = nil
            resolveAugmentQueueStep("removeAll")
        end
    end
    if lastLootWindowState and not lootOpenNow then
        scanState.lastScanState.lootOpen = false
        if clearLootItems then clearLootItems() end
    end
    setLastInventoryWindowState(invOpen)
    setLastBankWindowState(bankOpen)
    setLastMerchantState(merchOpen)
    setLastLootWindowState(lootOpenNow)
end

-- Phase 8b: Pending reroll add (pickup -> send !augadd/!mythicaladd -> wait for ack or timeout -> put back)
-- Optimistic: add to cache as soon as we send; on timeout roll back cache and notify.
local REROLL_ADD_ACK_TIMEOUT_MS = 3000
local function phase8b_pendingRerollAdd(now)
    local uiState, hasItemOnCursor, removeItemFromCursor, setStatusMessage, invalidateSellConfigCache, invalidateLootConfigCache, rerollService, computeAndAttachSellStatus, inventoryItems, bankItems =
        d.uiState, d.hasItemOnCursor, d.removeItemFromCursor, d.setStatusMessage, d.invalidateSellConfigCache, d.invalidateLootConfigCache, d.rerollService, d.computeAndAttachSellStatus, d.inventoryItems, d.bankItems
    local pending = uiState.pendingRerollAdd
    if not pending or not rerollService then return end
    local lp = d.uiState.lastPickup
    local function finish(success)
        rerollService.clearPendingAddAck()
        if removeItemFromCursor then removeItemFromCursor() end
        uiState.pendingRerollAdd = nil
        if invalidateSellConfigCache then invalidateSellConfigCache() end
        if invalidateLootConfigCache then invalidateLootConfigCache() end
        if computeAndAttachSellStatus and inventoryItems and #inventoryItems > 0 then computeAndAttachSellStatus(inventoryItems) end
        if computeAndAttachSellStatus and bankItems and #bankItems > 0 then computeAndAttachSellStatus(bankItems) end
        if setStatusMessage then setStatusMessage(success and "Added to list." or "Add failed or timed out; list reverted.") end
    end
    if pending.step == "pickup" then
        if hasItemOnCursor() and lp and lp.bag == pending.bag and lp.slot == pending.slot and lp.source == pending.source then
            -- Optimistic: update cache immediately so UI shows new state without waiting for server
            rerollService.addEntryToList(pending.list, pending.itemId, pending.itemName or "")
            local cmd = (pending.list == "aug") and (constants.REROLL and constants.REROLL.COMMAND_AUG_ADD or "!augadd") or (constants.REROLL and constants.REROLL.COMMAND_MYTHICAL_ADD or "!mythicaladd")
            mq.cmd("/say " .. cmd)
            pending.step = "sent"
            pending.sentAt = now
            rerollService.setPendingAddAck(pending.itemId, function() finish(true) end)
        end
        return
    end
    if pending.step == "sent" then
        if pending.sentAt and (now - pending.sentAt) > REROLL_ADD_ACK_TIMEOUT_MS then
            if rerollService.removeEntryFromCache then rerollService.removeEntryFromCache(pending.list, pending.itemId) end
            finish(false)
        end
    end
end

-- Phase 8c: After augment roll confirm — poll for item on cursor, print name/link, autoinv, then refresh inventory.
local AUG_ROLL_COMPLETE_TIMEOUT_MS = 15000
local function phase8c_pendingAugRollComplete(now)
    local uiState, hasItemOnCursor = d.uiState, d.hasItemOnCursor
    if not uiState.pendingAugRollComplete then return end
    if uiState.pendingAugRollCompleteAt and (now - uiState.pendingAugRollCompleteAt) > AUG_ROLL_COMPLETE_TIMEOUT_MS then
        uiState.pendingAugRollComplete = nil
        uiState.pendingAugRollCompleteAt = nil
        return
    end
    if not hasItemOnCursor() then return end
    local cur = mq.TLO and mq.TLO.Cursor
    local name = (cur and cur.Name and cur.Name()) or ""
    if name and name ~= "" then
        print("\ag[ItemUI]\ax Augment roll result: " .. name)
        local link = (cur and cur.Link and cur.Link()) or (cur and cur.ItemLink and cur.ItemLink()) or nil
        if link and link ~= "" then
            mq.cmdf("/guild %s", link)
        else
            mq.cmdf("/guild %s", name)
        end
    end
    uiState.lastPickup.bag, uiState.lastPickup.slot, uiState.lastPickup.source = nil, nil, nil
    mq.cmd("/autoinv")
    local delayMs = (constants.TIMING and constants.TIMING.DEFERRED_SCAN_DELAY_MS) or 120
    uiState.deferredInventoryScanAt = now + delayMs
    uiState.pendingAugRollComplete = nil
    uiState.pendingAugRollCompleteAt = nil
end

-- Phase 9: Debounced layout save, cache cleanup
local function phase9_layoutSaveCacheCleanup(now)
    local perfCache, saveLayoutToFileImmediate, Cache = d.perfCache, d.saveLayoutToFileImmediate, d.Cache
    if perfCache.layoutDirty and (now - perfCache.layoutSaveScheduledAt) >= perfCache.layoutSaveDebounceMs then
        perfCache.layoutDirty = false
        saveLayoutToFileImmediate()
    end
    if not perfCache.lastCacheCleanup or (now - perfCache.lastCacheCleanup) >= constants.TIMING.CACHE_CLEANUP_INTERVAL_MS then
        perfCache.lastCacheCleanup = now
        Cache.cleanup()
    end
end

-- Phase 10: Loop delay and doevents
local function phase10_loopDelay()
    local getShouldDraw, C = d.getShouldDraw, d.C
    mq.delay(getShouldDraw() and C.LOOP_DELAY_VISIBLE_MS or C.LOOP_DELAY_HIDDEN_MS)
    mq.doevents()
end

local M = {}

function M.init(deps)
    d = deps
end

function M.tick(now)
    if d.macroBridge and d.macroBridge.poll then d.macroBridge.poll() end
    phase1_statusExpiry(now)
    phase1b_activationGuard(now)
    phase2_periodicPersist(now)
    phase3_autoSellRequest()
    phase4_sellMacroFinish(now)
    phase5_lootMacro(now)
    phase6_deferredHistorySaves(now)
    phase7_sellQueueQuantityDestroyMoveAugment(now)
    phase8_windowStateDeferredScansAutoShowAugmentTimeouts(now)
    phase8b_pendingRerollAdd(now)
    phase8c_pendingAugRollComplete(now)
    phase9_layoutSaveCacheCleanup(now)
    phase10_loopDelay()
end

return M
