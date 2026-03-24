--[[
    Main loop service: 10-phase tick for ItemUI.
    init(deps) stores dependencies; tick(now) runs one iteration (phases 1-10 + delay + doevents).
    P0-01: Sell macro finish uses deferred scan (no mq.delay in loop).
]]

local mq = require('mq')
local constants = require('itemui.constants')
local lootFeedEvents = require('itemui.services.loot_feed_events')
local scriptConsumeEvents = require('itemui.services.script_consume_events')
local ItemDisplayView = require('itemui.views.item_display')
local item_name = require('itemui.utils.item_name')
local soundService = require('itemui.services.sound')
local dbgSell = require('itemui.core.debug').channel('Sell')
local dbgLoot = require('itemui.core.debug').channel('Loot')
local dbgAugment = require('itemui.core.debug').channel('Augment')

local d  -- deps, set by init()

local function getItemDisplayState()
    return ItemDisplayView.getState()
end

local function resolveAugmentQueueStep(queueType)
    local uiState, scanInventory, isBankWindowOpen, scanBank, refreshActiveItemDisplayTab, setStatusMessage, buildAugmentIndex, deferredScanNeeded =
        d.uiState, d.scanInventory, d.isBankWindowOpen, d.scanBank, d.refreshActiveItemDisplayTab, d.setStatusMessage, d.buildAugmentIndex, d.deferredScanNeeded
    if queueType == "optimize" then
        if uiState.optimizeQueue and uiState.optimizeQueue.steps and #uiState.optimizeQueue.steps > 0 then
            local oq = uiState.optimizeQueue
            local step = table.remove(oq.steps, 1)
            if step and step.slotIndex and step.augmentItem then
                local itemDisplayState = getItemDisplayState()
                local tab = (itemDisplayState.itemDisplayTabs and itemDisplayState.itemDisplayActiveTabIndex and itemDisplayState.itemDisplayTabs[itemDisplayState.itemDisplayActiveTabIndex]) or nil
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
            scanInventory(true)
            if isBankWindowOpen() then scanBank(true) end
            if buildAugmentIndex then buildAugmentIndex() end
            if deferredScanNeeded then deferredScanNeeded.inventory = false; deferredScanNeeded.bank = false end
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
            scanInventory(true)
            if isBankWindowOpen() then scanBank(true) end
            if buildAugmentIndex then buildAugmentIndex() end
            if deferredScanNeeded then deferredScanNeeded.inventory = false; deferredScanNeeded.bank = false end
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

-- True when the item on cursor is from a known ItemUI source (we initiated the pickup). Guard runs only when unknown.
local function isCursorFromKnownSource(uiState)
    if not uiState then return false end
    local lp = uiState.lastPickup
    if lp and (lp.bag ~= nil or lp.slot ~= nil) then return true end
    if uiState.pendingRerollAdd then return true end
    if uiState.pendingDestroyAction then return true end
    if uiState.pendingMoveAction then return true end
    if uiState.pendingInsertAugment then return true end
    if uiState.pendingRemoveAugment then return true end
    if uiState.pendingQuantityAction then return true end
    if uiState.pendingQuantityPickup then return true end
    if uiState.pendingAugRollComplete then return true end
    if uiState.pendingEquipAction then return true end
    if uiState.waitingForInsertCursorClear or uiState.waitingForRemoveCursorPopulated then return true end
    local q = uiState.cursorActionQueue
    if q and #q > 0 and q[1] then
        local t = q[1].type
        if t == "reroll_add" or t == "destroy" or t == "equip" then return true end
    end
    return false
end

-- Phase 1b: Click-through protection — only when option on and item on cursor from non-known source (e.g. game-window click).
local function phase1b_activationGuard(now)
    local uiState, hasItemOnCursor, setStatusMessage = d.uiState, d.hasItemOnCursor, d.setStatusMessage
    if not uiState then return end
    if not (d.layoutConfig and d.layoutConfig.ActivationGuardEnabled ~= false) then return end
    if not hasItemOnCursor or not hasItemOnCursor() then return end
    if isCursorFromKnownSource(uiState) then return end
    local C = constants.TIMING
    local guardMs = C and C.ACTIVATION_GUARD_MS or 450
    local graceMs = C and C.UNEXPECTED_CURSOR_GRACE_MS or 500
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
    -- Skip I/O while loot macro is running to avoid per-corpse save lag.
    local lootMacState = d.lootMacState
    if lootMacState and lootMacState.lastRunning then return end
    -- After loot ends, hold off for LOOT_PERSIST_COOLDOWN_MS so the post-loot inventory
    -- scan and sell-status attachment can complete before we hit disk again.
    local lootFinishedAt = lootMacState and lootMacState.finishedAt or 0
    if lootFinishedAt > 0 and (now - lootFinishedAt) < C.LOOT_PERSIST_COOLDOWN_MS then return end
    if (now - scanState.lastPersistSaveTime) >= C.PERSIST_SAVE_INTERVAL_MS then
        local charName = (mq.TLO and mq.TLO.Me and mq.TLO.Me.Name and mq.TLO.Me.Name()) or ""
        if charName ~= "" then
            storage.ensureCharFolderExists()
            if #sellItems > 0 then
                storage.saveInventory(sellItems)
                storage.writeSellCache(sellItems)
            elseif #inventoryItems > 0 then
                if not scanState.sellStatusAttachedAt then
                    computeAndAttachSellStatus(inventoryItems)
                    scanState.sellStatusAttachedAt = now
                end
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

-- Phase 3: Auto-sell request processing (dispatches by sellMode: macro or lua)
local function phase3_autoSellRequest()
    local uiState, runSellMacro = d.uiState, d.runSellMacro
    if uiState.autoSellRequested then
        uiState.autoSellRequested = false
        runSellMacro()
    end
end

-- Phase 4: Sell macro finish detection + failed items (via macro bridge; P0-01: deferred scan, no mq.delay)
-- Use bridge running state (includes file-based fallback) so we detect finish and schedule inventory refresh even when Macro.Name() doesn't match
local function phase4_sellMacroFinish(now)
    local uiState, sellMacState, setStatusMessage, C = d.uiState, d.sellMacState, d.setStatusMessage, d.C
    local macroBridge = d.macroBridge
    -- Use live TLO only so bar hides when macro process ends (Issue 1)
    local sellMacRunning = (macroBridge and macroBridge.isSellMacroRunning and macroBridge.isSellMacroRunning())
    if sellMacState.lastRunning and not sellMacRunning then
        -- Clear bridge sell state so no consumer sees stale running/smoothedFrac
        if macroBridge and macroBridge.clearSellState then macroBridge.clearSellState() end
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
                soundService.play("sell_failed")
            else
                setStatusMessage("Sell complete. Inventory refreshed.")
                soundService.play("sell_complete")
            end
        else
            setStatusMessage("Sell complete. Inventory refreshed.")
            soundService.play("sell_complete")
        end
        dbgSell.log("Sell macro finished - inventory refreshed")
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
        dbgLoot.log("Loot macro started - opening Loot UI")
        uiState.lootUIOpen = true
        uiState.lootRunFinished = false
        uiState.lootRunLootedItems = {}
        uiState.lootRunLootedList = {}
        uiState.lootRunTotalValue = 0
        uiState.lootRunTributeValue = 0
        uiState.lootRunBestItemName = ""
        uiState.lootRunBestItemValue = 0
        d.recordCompanionWindowOpened("loot")
    end
    if lootMacState.lastRunning and not lootMacRunning then
        dbgLoot.log("Loot macro finished - scheduling inventory scan and session read")
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
                        soundService.play("mythical_alert")
                    end
                else
                    uiState.lootMythicalDecisionStartAt = nil
                end
                uiState.lootUIOpen = true
                d.recordCompanionWindowOpened("loot")
            end
        end
    end
    -- ========================================================================
    -- Chunked end-of-loot session processing
    -- Spreads INI reads and item merge across multiple frames to avoid stutter.
    -- Phase A: read session INI (one frame)
    -- Phase B: merge items N per tick (chunked)
    -- Phase C: read skip history + apply summary (one frame, fast with plugin bulk read)
    -- ========================================================================
    local SESSION_MERGE_PER_TICK = 20  -- items to merge per frame during chunked drain

    local sessionReadDelay = constants.TIMING.LOOT_SESSION_READ_DELAY_MS or 80
    -- Phase A: Read session INI once, store raw data for chunked merge.
    -- When IPC is active, drainIPCFast already populated lootRunLootedItems in real-time
    -- and loot_end already set summary totals — skip the expensive INI read + merge entirely.
    if lootLoopRefs.pendingSession and (now - (lootLoopRefs.pendingSessionAt or 0)) >= sessionReadDelay then
        lootLoopRefs.pendingSession = nil
        lootLoopRefs.pendingSessionAt = 0
        local ipcActive = macroBridge and macroBridge.isIPCAvailable and macroBridge.isIPCAvailable()
        local alreadyHaveItems = uiState.lootRunLootedItems and #uiState.lootRunLootedItems > 0
        if ipcActive and alreadyHaveItems then
            -- IPC already populated everything — skip straight to Phase C (skip history + history saves)
            lootLoopRefs.sessionMerge = nil
            lootLoopRefs.pendingSessionFinish = { session = nil }
        elseif uiState.lootUIOpen and macroBridge and macroBridge.getLootSession then
            local session = macroBridge.getLootSession()
            if session and session.count and session.count > 0 then
                -- Build seen-set from existing items (fast: just a hash table build)
                local existing = uiState.lootRunLootedItems or {}
                local seen = {}
                for _, row in ipairs(existing) do
                    local n = item_name.normalizeItemName(row.name)
                    if n ~= "" then seen[n] = true end
                end
                -- Store chunked merge state; actual item processing happens in Phase B below
                lootLoopRefs.sessionMerge = {
                    items = session.items or {},
                    idx = 1,
                    existing = existing,
                    seen = seen,
                    session = session,  -- keep summary for Phase C
                }
                uiState.lootRunLootedList = uiState.lootRunLootedList or {}
                uiState.lootRunLootedItems = existing
            else
                -- No items; skip to Phase C immediately
                lootLoopRefs.sessionMerge = nil
                lootLoopRefs.pendingSessionFinish = { session = session }
            end
        else
            lootLoopRefs.sessionMerge = nil
            lootLoopRefs.pendingSessionFinish = { session = nil }
        end
    end

    -- Phase B: Merge session items in chunks (SESSION_MERGE_PER_TICK per frame)
    if lootLoopRefs.sessionMerge then
        local sm = lootLoopRefs.sessionMerge
        local items = sm.items
        local existing = sm.existing
        local seen = sm.seen
        local count = 0
        while sm.idx <= #items and count < SESSION_MERGE_PER_TICK do
            local row = items[sm.idx]
            sm.idx = sm.idx + 1
            count = count + 1
            local name = item_name.normalizeItemName(row.name)
            if name ~= "" and not seen[name] then
                seen[name] = true
                table.insert(uiState.lootRunLootedList, name)
                local entry = {
                    name = name,
                    value = row.value or 0,
                    tribute = row.tribute or 0,
                    statusText = "—",
                    willSell = false
                }
                table.insert(existing, entry)
                local histEntry = nil
                if uiState.enableLootHistory then
                    if not uiState.lootHistory then loadLootHistoryFromFile() end
                    if not uiState.lootHistory then uiState.lootHistory = {} end
                    histEntry = { name = name, value = row.value or 0, statusText = "—", willSell = false }
                    table.insert(uiState.lootHistory, histEntry)
                end
                -- Queue sell-status lookup so it drains across ticks (avoids per-session burst)
                if getSellStatusForItem then
                    uiState.pendingLootSellStatus = uiState.pendingLootSellStatus or {}
                    table.insert(uiState.pendingLootSellStatus, { entry = entry, histEntry = histEntry })
                end
            end
        end
        -- Check if merge is done
        if sm.idx > #items then
            lootLoopRefs.pendingSessionFinish = { session = sm.session }
            lootLoopRefs.sessionMerge = nil
        end
    end

    -- Phase C: Apply session summary + read skip history (once, after merge completes)
    if lootLoopRefs.pendingSessionFinish then
        local finish = lootLoopRefs.pendingSessionFinish
        lootLoopRefs.pendingSessionFinish = nil
        local session = finish.session
        if uiState.lootUIOpen then
            if uiState.enableSkipHistory then
            local skippedPath = config.getLootConfigFile and config.getLootConfigFile("loot_skipped.ini")
            if skippedPath and skippedPath ~= "" then
                local skipCount = 0
                local skippedSec = nil
                if macroBridge and macroBridge.getPluginIni then
                    local ini = macroBridge.getPluginIni()
                    if ini and ini.readSection then
                        skippedSec = ini.readSection(skippedPath, "Skipped")
                        if skippedSec and skippedSec.count then skipCount = tonumber(skippedSec.count) or 0 end
                    end
                end
                if skippedSec == nil then
                    local skipCountStr = config.safeIniValueByPath(skippedPath, "Skipped", "count", "0")
                    skipCount = tonumber(skipCountStr) or 0
                end
                if skipCount > 0 then
                    if not uiState.skipHistory and loadSkipHistoryFromFile then loadSkipHistoryFromFile() end
                    if not uiState.skipHistory then uiState.skipHistory = {} end
                    if skippedSec then
                        for j = 1, skipCount do
                            local raw = skippedSec[tostring(j)] or ""
                            if raw and raw ~= "" then
                                local rawName, reason = raw:match("^([^%^]*)%^?(.*)$")
                                local name = item_name.normalizeItemName(rawName or raw)
                                if name ~= "" then table.insert(uiState.skipHistory, { name = name, reason = reason or "" }) end
                            end
                        end
                    else
                        for j = 1, skipCount do
                            local raw = config.safeIniValueByPath(skippedPath, "Skipped", tostring(j), "")
                            if raw and raw ~= "" then
                                local rawName, reason = raw:match("^([^%^]*)%^?(.*)$")
                                local name = item_name.normalizeItemName(rawName or raw)
                                if name ~= "" then table.insert(uiState.skipHistory, { name = name, reason = reason or "" }) end
                            end
                        end
                    end
                    while #uiState.skipHistory > LOOT_HISTORY_MAX do table.remove(uiState.skipHistory, 1) end
                    lootLoopRefs.saveSkipAt = now + lootLoopRefs.deferMs
                end
            end
            end
            -- Session summary (authoritative totals from macro) and loot history cap
            if session then
                uiState.lootRunTotalValue = session.totalValue or 0
                uiState.lootRunTributeValue = session.tributeValue or 0
                local bestNameNorm = item_name.normalizeItemName(session.bestItemName or "")
                uiState.lootRunBestItemName = (bestNameNorm ~= "" and bestNameNorm) or (session.bestItemName or "")
                uiState.lootRunBestItemValue = session.bestItemValue or 0
                if uiState.enableLootHistory and uiState.lootHistory then
                    while #uiState.lootHistory > LOOT_HISTORY_MAX do table.remove(uiState.lootHistory, 1) end
                    lootLoopRefs.saveHistoryAt = now + lootLoopRefs.deferMs
                end
            end
            uiState.lootRunFinished = true
        end
    end
    local pollInterval = lootMacRunning and lootLoopRefs.pollMs or (lootLoopRefs.pollMsIdle or 1000)
    if (lootMacRunning or uiState.lootUIOpen) and (now - lootLoopRefs.pollAt) >= pollInterval then
        lootLoopRefs.pollAt = now
        -- Only use INI-based progress poll when IPC is not active. When IPC is available,
        -- drainIPCFast (runs after phase5) manages lootRunCorpsesLooted with one-step
        -- smoothing. Overriding here would break the smooth increment or cause jumps.
        local useIPCProgress = macroBridge and macroBridge.isIPCAvailable and macroBridge.isIPCAvailable()
        if not useIPCProgress and macroBridge and macroBridge.pollLootProgress then
            local corpses, total, current = macroBridge.pollLootProgress()
            uiState.lootRunCorpsesLooted = corpses
            uiState.lootRunTotalCorpses = total
            uiState.lootRunCurrentCorpse = current or ""
        end
        -- Read mythical alert whenever we poll (macro running or Loot UI open) so test mode and in-run pause both show and wait.
        -- Task 6.2: short-circuit when itemName empty and lootMythicalAlert already nil to avoid 5 INI reads per poll.
        local alertPath = config.getLootConfigFile and config.getLootConfigFile("loot_mythical_alert.ini")
        if alertPath and alertPath ~= "" then
            local itemName = config.safeIniValueByPath(alertPath, "Alert", "itemName", "")
            if (not itemName or itemName == "") and not uiState.lootMythicalAlert then
                -- Skip: no mythical item and already nil
            else
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
                            soundService.play("mythical_alert")
                        end
                        uiState.lootUIOpen = true
                        d.recordCompanionWindowOpened("loot")
                    else
                        uiState.lootMythicalDecisionStartAt = nil
                    end
                else
                    uiState.lootMythicalAlert = nil
                    uiState.lootMythicalDecisionStartAt = nil
                end
            end
        end
    end
    lootMacState.lastRunning = lootMacRunning
end

-- Phase 6: Deferred history saves (only when the corresponding feature is enabled)
local function phase6_deferredHistorySaves(now)
    local lootLoopRefs = d.lootLoopRefs
    local uiState = d.uiState
    if lootLoopRefs.saveHistoryAt > 0 and now >= lootLoopRefs.saveHistoryAt and (uiState and uiState.enableLootHistory == true) then
        lootLoopRefs.saveHistoryAt = 0
        lootLoopRefs.saveLootHistory()
    end
    if lootLoopRefs.saveSkipAt > 0 and now >= lootLoopRefs.saveSkipAt and (uiState and uiState.enableSkipHistory == true) then
        lootLoopRefs.saveSkipAt = 0
        lootLoopRefs.saveSkipHistory()
    end
end

-- p7 helper: quantity picker state machine (no mq.delay). Risk R5: 2000ms timeout.
local function handleQuantityAction(now)
    local uiState, setStatusMessage = d.uiState, d.setStatusMessage
    if not uiState or not uiState.pendingQuantityAction then return end
    local action = uiState.pendingQuantityAction
    local phase = action.phase or "pickup"
    local timeoutMs = (constants.TIMING and constants.TIMING.QUANTITY_PICKER_TIMEOUT_MS) or 2000
    if phase == "pickup" then
        uiState.lastPickup.bag = action.pickup.bag
        uiState.lastPickup.slot = action.pickup.slot
        uiState.lastPickup.source = action.pickup.source
        if action.pickup.source == "bank" then
            mq.cmdf('/itemnotify in bank%d %d leftmouseup', action.pickup.bag, action.pickup.slot)
        else
            mq.cmdf('/itemnotify in pack%d %d leftmouseup', action.pickup.bag, action.pickup.slot)
        end
        action.phase = "wait_qty_wnd"
        action.startedAt = now
        return
    end
    if phase == "wait_qty_wnd" then
        if (now - (action.startedAt or 0)) >= timeoutMs then
            setStatusMessage("Quantity picker timed out.")
            uiState.pendingQuantityAction = nil
            return
        end
        local w = mq.TLO and mq.TLO.Window and mq.TLO.Window("QuantityWnd")
        if w and w.Open and w.Open() then
            mq.cmd(string.format('/notify QuantityWnd QTYW_Slider newvalue %d', action.qty or 1))
            mq.cmd('/notify QuantityWnd QTYW_Accept_Button leftmouseup')
            uiState.pendingQuantityAction = nil
        end
    end
end

-- p7 helper: script item (Alt Currency) sequential right-click consumption FSM.
local function handleScriptConsume(now)
    local uiState, itemOps, setStatusMessage = d.uiState, d.itemOps, d.setStatusMessage
    if not uiState then return end
    -- dequeue next if idle
    if not uiState.pendingScriptConsume then
        local q = uiState.pendingScriptConsumeQueue or {}
        if #q > 0 then
            uiState.pendingScriptConsume = table.remove(q, 1)
            uiState.pendingScriptConsumeQueue = q
        end
    end
    if not uiState.pendingScriptConsume then return end
    local ps = uiState.pendingScriptConsume
    local delayMs = (constants.TIMING and constants.TIMING.SCRIPT_CONSUME_DELAY_MS) or 300
    local confirmTimeoutMs = (constants.TIMING and constants.TIMING.SCRIPT_CONSUME_CONFIRM_TIMEOUT_MS) or 2000
    local verified = ps.verifiedFromChat or 0
    local function finishConsume(src, n, msg)
        uiState.pendingScriptConsume = nil
        local q = uiState.pendingScriptConsumeQueue or {}
        if #q > 0 then
            uiState.pendingScriptConsume = table.remove(q, 1)
            uiState.pendingScriptConsumeQueue = q
        end
        if setStatusMessage then setStatusMessage(msg) end
        if d.storage then
            if src == "inv" then
                if d.inventoryItems then d.storage.saveInventory(d.inventoryItems) end
                if d.storage.writeSellCache and d.sellItems then d.storage.writeSellCache(d.sellItems) end
            elseif src == "bank" and d.bankItems then
                d.storage.saveBank(d.bankItems)
            end
        end
    end
    if ps.waitingForConfirm then
        local gotConfirm = verified >= ps.consumedSoFar
        local timedOut = (ps.confirmUntil and now >= ps.confirmUntil)
        if gotConfirm or timedOut then
            ps.waitingForConfirm = nil
            ps.confirmUntil = nil
            if ps.consumedSoFar >= ps.totalToConsume then
                finishConsume(ps.source, ps.consumedSoFar, string.format("Added %d to Alt Currency.", ps.consumedSoFar))
            else
                ps.nextClickAt = now + delayMs
                if setStatusMessage then setStatusMessage(string.format("Alt Currency: %d / %d", ps.consumedSoFar, ps.totalToConsume)) end
            end
        end
    else
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
                finishConsume(ps.source, ps.consumedSoFar, string.format("Added %d to Alt Currency; item moved or depleted.", ps.consumedSoFar))
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
                ps.waitingForConfirm = true
                ps.confirmUntil = now + confirmTimeoutMs
                if ps.consumedSoFar >= ps.totalToConsume then
                    if setStatusMessage then setStatusMessage(string.format("Verifying %d / %d...", ps.consumedSoFar, ps.totalToConsume)) end
                else
                    if setStatusMessage then setStatusMessage(string.format("Alt Currency: %d / %d (waiting for confirm)...", ps.consumedSoFar, ps.totalToConsume)) end
                end
            end
        end
    end
end

-- p8 helper: augment insert/remove confirmation dialog FSM timeouts.
local function handleAugmentConfirmationTimeouts(now)
    local uiState, augmentOps, hasItemOnCursor, setStatusMessage = d.uiState, d.augmentOps, d.hasItemOnCursor, d.setStatusMessage
    if not uiState then return end
    local T = constants.TIMING
    local AUGMENT_CURSOR_CLEAR_TIMEOUT_MS    = T.AUGMENT_CURSOR_CLEAR_TIMEOUT_MS
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
        if hasItemOnCursor() then
            setStatusMessage("Insert may have failed; check cursor.")
        else
            resolveAugmentQueueStep("optimize")
            if not (uiState.optimizeQueue and uiState.optimizeQueue.steps and #uiState.optimizeQueue.steps > 0) then
                setStatusMessage("Insert complete.")
            end
        end
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
            if not (uiState.optimizeQueue and uiState.optimizeQueue.steps and #uiState.optimizeQueue.steps > 0) then
                setStatusMessage("Insert complete.")
            end
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
end

-- p7 helper: sell queue processing (macro bridge sell queue and batch sell advance).
local function handleManualSellQueue(now)
    local processSellQueue, sellBatch = d.processSellQueue, d.sellBatch
    processSellQueue(now)
    if sellBatch and sellBatch.advance then sellBatch.advance(now) end
end

-- p7 helper: all quantity-related state (picker FSM, script consume, pending pickup watchdog).
local function handleQuantityPicker(now)
    local uiState, hasItemOnCursor, setStatusMessage = d.uiState, d.hasItemOnCursor, d.setStatusMessage
    -- Task 6.5: quantity picker state machine (no mq.delay); 2000ms timeout per Risk R5
    handleQuantityAction(now)
    -- Script items (Alt Currency): sequential right-click consumption; one use per tick, delay between each.
    -- After each right-click: update in-memory lists so UI shows real-time decrement.
    -- On completion or halt: persist (saveInventory/writeSellCache for inv, saveBank for bank).
    handleScriptConsume(now)
    local pq = uiState.pendingQuantityPickup
    if pq and type(pq) == "table" then
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
                if pq.source == "bank" then
                    local bn = Me and Me.Bank and Me.Bank(pq.bag)
                    local sz = bn and bn.Container and bn.Container()
                    local it = (bn and sz and sz > 0) and (bn.Item and bn.Item(pq.slot)) or bn
                    itemExists = it and it.ID and it.ID() and it.ID() > 0
                else
                    local pack = Me and Me.Inventory and Me.Inventory("pack" .. pq.bag)
                    local it = pack and pack.Item and pack.Item(pq.slot)
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

-- p7 helper: destroy item state machine.
local function handleDestroyQueue(now)
    local uiState, itemOps = d.uiState, d.itemOps
    if uiState.pendingDestroyAction then
        uiState.pendingQuantityPickup = nil
        uiState.pendingQuantityPickupTimeoutAt = nil
        uiState.quantityPickerValue = ""
        itemOps.advanceDestroyStateMachine(now)
    end
end

-- p7 helper: move action, reroll bank-to-bag moves, and augment queue (remove/insert).
local function handleMoveAction(now)
    local uiState, itemOps, augmentOps, hasItemOnCursor = d.uiState, d.itemOps, d.augmentOps, d.hasItemOnCursor
    if uiState.pendingMoveAction then
        uiState.pendingQuantityPickup = nil
        uiState.pendingQuantityPickupTimeoutAt = nil
        uiState.quantityPickerValue = ""
        itemOps.advanceMoveStateMachine(now)
    end
    -- Reroll bank-to-bag: one move per tick (so each item lands before the next); stack moves set pendingMoveAction
    -- and are completed in the block above. Only when no move is in flight do we start the next or trigger the roll.
    if uiState.pendingRerollBankMoves and not uiState.pendingMoveAction then
        local pm = uiState.pendingRerollBankMoves
        local items = pm.items or {}
        local idx = pm.nextIndex or 1
        if d.isBankWindowOpen and not d.isBankWindowOpen() then
            uiState.pendingRerollBankMoves = nil
            if d.rerollService and d.rerollService.resumeLocationCache then d.rerollService.resumeLocationCache() end
            if d.setStatusMessage then d.setStatusMessage("Bank closed; roll cancelled.") end
        elseif idx <= #items then
            local one = items[idx]
            if one and one.bag and one.slot then
                local ok = d.itemOps.moveBankToInv(one.bag, one.slot)
                pm.nextIndex = idx + 1
                if not ok then
                    if d.setStatusMessage then d.setStatusMessage("Move from bank failed; roll cancelled.") end
                    uiState.pendingRerollBankMoves = nil
                    if d.rerollService and d.rerollService.resumeLocationCache then d.rerollService.resumeLocationCache() end
                end
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
                    uiState.rerollPendingScan = true
                    uiState.rerollPendingScanAt = now
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
    -- Task 6.4: augment insert/remove are state machines; advance each tick, do not clear and call once
    if uiState.pendingRemoveAugment then
        augmentOps.advanceRemove(now)
    end
    if uiState.optimizeQueue and uiState.optimizeQueue.steps and #uiState.optimizeQueue.steps > 0
        and not uiState.pendingInsertAugment and not uiState.waitingForInsertConfirmation and not uiState.waitingForInsertCursorClear
        and not hasItemOnCursor() then
        local oq = uiState.optimizeQueue
        local step = table.remove(oq.steps, 1)
        if step and step.slotIndex and step.augmentItem then
            local itemDisplayState = getItemDisplayState()
            local tab = (itemDisplayState.itemDisplayTabs and itemDisplayState.itemDisplayActiveTabIndex and itemDisplayState.itemDisplayTabs[itemDisplayState.itemDisplayActiveTabIndex]) or nil
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
    end
    if uiState.pendingInsertAugment then
        getItemDisplayState().itemDisplayAugmentSlotActive = nil
        augmentOps.advanceInsert(now)
    end
end

-- Phase 7: Sell queue + quantity picker + destroy + move + augment queue start (remove all/optimize pop + execute)
local function phase7_sellQueueQuantityDestroyMoveAugment(now)
    if not d.uiState then return end
    handleManualSellQueue(now)
    handleQuantityPicker(now)
    handleDestroyQueue(now)
    handleMoveAction(now)
end

-- p8 helper: Capture window open/close state, set derived dirty flags. Returns ws table for this tick.
-- Does NOT commit last-state (that is done at the end of handleAutoShowHide).
local function trackWindowStateChanges(now)
    local uiState, scanState = d.uiState, d.scanState
    local isBankWindowOpen, isMerchantWindowOpen, isLootWindowOpen = d.isBankWindowOpen, d.isMerchantWindowOpen, d.isLootWindowOpen
    local bankCache, computeAndAttachSellStatus = d.bankCache, d.computeAndAttachSellStatus
    -- Decrement force-apply layout frames after revert (so positions/sizes re-apply from layoutConfig)
    if uiState.layoutRevertedApplyFrames and uiState.layoutRevertedApplyFrames > 0 then
        uiState.layoutRevertedApplyFrames = uiState.layoutRevertedApplyFrames - 1
    end
    local invWndLoop = mq.TLO and mq.TLO.Window and mq.TLO.Window("InventoryWindow")
    local invOpen = (invWndLoop and invWndLoop.Open and invWndLoop.Open()) or false
    local bankOpen = isBankWindowOpen()
    local merchOpen = isMerchantWindowOpen()
    local lootOpen = isLootWindowOpen()
    local lastBankWindowState = d.getLastBankWindowState()
    local lastLootWindowState = d.getLastLootWindowState()
    local lastInventoryWindowState = d.getLastInventoryWindowState()
    local lastMerchantState = d.getLastMerchantState()
    local bankJustOpened = bankOpen and not lastBankWindowState
    local lootJustClosed = lastLootWindowState and not lootOpen
    local invJustOpened = invOpen and not lastInventoryWindowState
    local shouldDraw = d.getShouldDraw()
    if lootOpen or lootJustClosed then scanState.inventoryBagsDirty = true end
    -- When bank just opened, apply sell status (incl. RerollList) to bankCache so initial display matches reroll list before deferred scan runs.
    if bankJustOpened and bankCache and #bankCache > 0 and computeAndAttachSellStatus then
        computeAndAttachSellStatus(bankCache)
    end
    return {
        invOpen               = invOpen,
        bankOpen              = bankOpen,
        merchOpen             = merchOpen,
        lootOpen              = lootOpen,
        bankJustOpened        = bankJustOpened,
        lootJustClosed        = lootJustClosed,
        invJustOpened         = invJustOpened,
        lastInventoryWindowState = lastInventoryWindowState,
        lastBankWindowState   = lastBankWindowState,
        lastMerchantState     = lastMerchantState,
        lastLootWindowState   = lastLootWindowState,
        shouldDraw            = shouldDraw,
        shouldDrawBefore      = shouldDraw,
    }
end

-- p8 helper: Execute pending deferred scans (deferredScanNeeded flags, stat rescan, sell config refresh).
local function runDeferredScans(now, ws)
    local deferredScanNeeded, perfCache, uiState, scanState = d.deferredScanNeeded, d.perfCache, d.uiState, d.scanState
    local maybeScanInventory, maybeScanBank, maybeScanSellItems = d.maybeScanInventory, d.maybeScanBank, d.maybeScanSellItems
    local rescanInventoryBags = d.rescanInventoryBags
    local inventoryItems, sellItems, bankItems = d.inventoryItems, d.sellItems, d.bankItems
    local computeAndAttachSellStatus, sellStatusService = d.computeAndAttachSellStatus, d.sellStatusService
    if deferredScanNeeded.inventory then maybeScanInventory(ws.invOpen); deferredScanNeeded.inventory = false end
    if deferredScanNeeded.bank then maybeScanBank(ws.bankOpen); deferredScanNeeded.bank = false end
    if deferredScanNeeded.sell then maybeScanSellItems(ws.merchOpen); deferredScanNeeded.sell = false end
    -- MASTER_PLAN 2.6: targeted rescan for bags that had _statsPending (e.g. ID was 0 during batch)
    if uiState.pendingStatRescanBags and next(uiState.pendingStatRescanBags) and rescanInventoryBags then
        local bags = {}
        for b in pairs(uiState.pendingStatRescanBags) do bags[#bags + 1] = b end
        rescanInventoryBags(bags)
        uiState.pendingStatRescanBags = {}
    end
    if perfCache.sellConfigPendingRefresh then
        if perfCache.sellConfigCache then sellStatusService.invalidateSellConfigCache() end
        if not scanState.sellStatusAttachedAt then
            computeAndAttachSellStatus(inventoryItems)
            if sellItems and #sellItems > 0 then computeAndAttachSellStatus(sellItems) end
            if bankItems and #bankItems > 0 then computeAndAttachSellStatus(bankItems) end
            scanState.sellStatusAttachedAt = now
        end
        perfCache.sellConfigPendingRefresh = false
    end
end

-- p8 helper: Auto-show/hide UI on window transitions, handle pending scans, loot events, commit last-state.
local function handleAutoShowHide(now, ws)
    local uiState, scanState, C = d.uiState, d.scanState, d.C
    local inventoryItems, sellItems, bankItems, bankCache = d.inventoryItems, d.sellItems, d.bankItems, d.bankCache
    local sellMacState, lootMacState = d.sellMacState, d.lootMacState
    local isBankWindowOpen, isMerchantWindowOpen, isLootWindowOpen = d.isBankWindowOpen, d.isMerchantWindowOpen, d.isLootWindowOpen
    local maybeScanBank, scanInventory, scanSellItems = d.maybeScanBank, d.scanInventory, d.scanSellItems
    local computeAndAttachSellStatus = d.computeAndAttachSellStatus
    local deferredScanNeeded = d.deferredScanNeeded
    local invalidateSortCache, flushLayoutSave, loadLayoutConfig, recordCompanionWindowOpened = d.invalidateSortCache, d.flushLayoutSave, d.loadLayoutConfig, d.recordCompanionWindowOpened
    local storage = d.storage
    local STATS_TAB_PRIME_MS = d.STATS_TAB_PRIME_MS
    local getStatsTabPrimeState, setStatsTabPrimeState = d.getStatsTabPrimeState, d.setStatsTabPrimeState
    local getStatsTabPrimeAt, setStatsTabPrimeAt = d.getStatsTabPrimeAt, d.setStatsTabPrimeAt
    local getStatsTabPrimedThisSession, setStatsTabPrimedThisSession = d.getStatsTabPrimedThisSession, d.setStatsTabPrimedThisSession
    local setShouldDraw, setOpen = d.setShouldDraw, d.setOpen
    local clearLootItems = d.clearLootItems
    -- Unpack window state from ws (computed once per tick by trackWindowStateChanges)
    local invOpen               = ws.invOpen
    local bankOpen              = ws.bankOpen
    local merchOpen             = ws.merchOpen
    local lootOpen              = ws.lootOpen
    local bankJustOpened        = ws.bankJustOpened
    local lootJustClosed        = ws.lootJustClosed
    local invJustOpened         = ws.invJustOpened
    local lastInventoryWindowState = ws.lastInventoryWindowState
    local lastBankWindowState   = ws.lastBankWindowState
    local lastMerchantState     = ws.lastMerchantState
    local lastLootWindowState   = ws.lastLootWindowState
    local shouldDraw            = ws.shouldDraw
    local shouldDrawBefore      = ws.shouldDrawBefore

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
            -- Use incremental scan (2 bags/frame across 5 frames) instead of full scanInventory
            -- to avoid a single-frame stutter after looting many corpses.
            if d.startIncrementalScan then
                d.startIncrementalScan()
            else
                scanInventory()
            end
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
    -- Reroll manager: quick refresh after roll finishes so count updates and next roll doesn't use stale items.
    if uiState.rerollPendingScan and uiState.rerollPendingScanAt then
        local elapsed = now - uiState.rerollPendingScanAt
        if elapsed >= (C.REROLL_PENDING_SCAN_DELAY_MS or 500) then
            scanInventory()
            if bankOpen then maybeScanBank(bankOpen) end
            invalidateSortCache("inv")
            uiState.rerollPendingScan = false
            uiState.rerollPendingScanAt = 0
            -- Resume location cache now that scan is done (was paused during roll)
            if d.rerollService and d.rerollService.resumeLocationCache then d.rerollService.resumeLocationCache() end
        end
    end
    if shouldAutoShowInv or bankJustOpened or (merchOpen and not lastMerchantState) then
        if not shouldDraw and not uiState.userClosedViaKeybind then
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
                -- Defer bank scan to next frame so CoOpt UI opens instantly without blocking.
                deferredScanNeeded.bank = true
                deferredScanNeeded.inventory = invOpen
                deferredScanNeeded.sell = merchOpen
            elseif merchOpen and not lastMerchantState then
                -- Defer scans to next frame so sell window opens instantly (no blocking scan on open).
                deferredScanNeeded.inventory = invOpen
                deferredScanNeeded.sell = true
                deferredScanNeeded.bank = bankOpen
            else
                -- Defer inventory scan to next frame so CoOpt UI opens instantly without blocking.
                deferredScanNeeded.inventory = invOpen
                deferredScanNeeded.bank = bankOpen
                deferredScanNeeded.sell = merchOpen
            end
        end
    end
    -- Merchant just opened while companion already visible (e.g. from bank): defer scans so we don't block this frame.
    if (merchOpen and not lastMerchantState) and shouldDraw then
        deferredScanNeeded.inventory = invOpen
        deferredScanNeeded.sell = true
    end
    if bankOpen and not shouldDraw and not uiState.userClosedViaKeybind then
        setShouldDraw(true)
        setOpen(true)
        loadLayoutConfig()
        uiState.bankWindowOpen = true
        uiState.bankWindowShouldDraw = true
        uiState.equipmentWindowOpen = true
        uiState.equipmentWindowShouldDraw = true
        recordCompanionWindowOpened("bank")
        recordCompanionWindowOpened("equipment")
        -- Defer bank scan to next frame so CoOpt UI opens instantly without blocking.
        deferredScanNeeded.bank = true
        deferredScanNeeded.inventory = invOpen
        deferredScanNeeded.sell = merchOpen
    end
    if lootMacRunning and lootJustClosed then
        setShouldDraw(false)
        setOpen(false)
        uiState.configWindowOpen = false
        if invOpen then mq.cmd('/keypress inventory') end
    end
    -- Inventory just closed: defer saves across multiple frames to avoid stutter.
    -- Guard: skip when loot macro is active or recently finished (prevents spurious saves
    -- triggered by the macro or its cleanup closing the inventory window at loot end).
    local lootFinishedAt = lootMacState and lootMacState.finishedAt or 0
    local lootRecentlyFinished = lootFinishedAt > 0 and (now - lootFinishedAt) < C.LOOT_PERSIST_COOLDOWN_MS
    if lastInventoryWindowState and not invOpen and not lootMacRunning and not lootRecentlyFinished then
        uiState.userClosedViaKeybind = false
        mq.cmd('/keypress CLOSE_INV_BAGS')
        storage.ensureCharFolderExists()
        -- Queue saves to spread across frames (1 disk write per tick instead of 3-4 in one frame)
        local saveQueue = uiState._deferredCloseSaves or {}
        if #sellItems > 0 then
            saveQueue[#saveQueue + 1] = function() storage.saveInventory(sellItems) end
            saveQueue[#saveQueue + 1] = function() storage.writeSellCache(sellItems) end
        else
            saveQueue[#saveQueue + 1] = function() computeAndAttachSellStatus(inventoryItems); storage.saveInventory(inventoryItems) end
            saveQueue[#saveQueue + 1] = function() storage.writeSellCache(inventoryItems) end
        end
        local bankToSave = bankOpen and bankItems or bankCache
        if bankToSave and #bankToSave > 0 then
            saveQueue[#saveQueue + 1] = function() storage.saveBank(bankToSave) end
        end
        saveQueue[#saveQueue + 1] = function() flushLayoutSave() end
        uiState._deferredCloseSaves = saveQueue
        setShouldDraw(false)
        setOpen(false)
        uiState.configWindowOpen = false
    end
    if bankJustOpened and shouldDrawBefore then
        uiState.bankWindowOpen = true
        uiState.bankWindowShouldDraw = true
        -- Defer bank scan to next frame so companion renders immediately without blocking.
        deferredScanNeeded.bank = true
    elseif bankJustOpened then
        uiState.bankWindowOpen = true
        uiState.bankWindowShouldDraw = true
    end
    if lastInventoryWindowState and not invOpen then scanState.lastScanState.invOpen = false end
    if lastBankWindowState and not bankOpen then
        scanState.lastScanState.bankOpen = false
        uiState.userClosedViaKeybind = false
    end
    if lastMerchantState and not merchOpen then
        scanState.lastScanState.merchOpen = false
        uiState.userClosedViaKeybind = false
    end
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
        -- Scan corpse loot items here (main-loop tick) instead of from the render callback.
        -- maybeScanLootItems guards internally: only scans when items are empty or state changes.
        if d.maybeScanLootItems then d.maybeScanLootItems(true) end
    end
    if lastLootWindowState and not lootOpenNow then
        scanState.lastScanState.lootOpen = false
        if clearLootItems then clearLootItems() end
    end
    -- Commit last-state for next tick's open/close edge detection.
    d.setLastInventoryWindowState(invOpen)
    d.setLastBankWindowState(bankOpen)
    d.setLastMerchantState(merchOpen)
    d.setLastLootWindowState(lootOpenNow)
end

-- Phase 8: Window state, deferred scans, auto-show/hide, stats tab priming, loot/sell pending scan (P0-01), augment timeouts
local function phase8_windowStateDeferredScansAutoShowAugmentTimeouts(now)
    local ws = trackWindowStateChanges(now)
    runDeferredScans(now, ws)
    handleAutoShowHide(now, ws)
    -- Augment insert/remove confirmation dialog FSM timeouts.
    handleAugmentConfirmationTimeouts(now)
end

-- Phase 0: Unified cursor-action queue drain. Runs every tick before phase7/phase8b.
-- Dequeues and starts the next destroy or reroll-add action when the cursor is free
-- and no cursor-based action is currently in flight.
local function phase0_cursorActionQueue(now)
    local uiState, hasItemOnCursor, setStatusMessage = d.uiState, d.hasItemOnCursor, d.setStatusMessage
    local q = uiState.cursorActionQueue
    if not q or #q == 0 then return end
    -- Any cursor-based action still running? Wait for it.
    if uiState.pendingDestroyAction then return end
    if uiState.pendingRerollAdd then return end
    if uiState.pendingMoveAction then return end
    if uiState.pendingEquipAction then return end
    -- Cursor must be clear before starting the next pickup.
    if hasItemOnCursor and hasItemOnCursor() then return end
    local next = table.remove(q, 1)
    if not next then return end
    local remaining = #q
    if next.type == "destroy" then
        uiState.pendingDestroyAction = { bag = next.bag, slot = next.slot, name = next.name, qty = next.qty }
        uiState.pendingDestroy = nil
        uiState.destroyQuantityValue = ""
        uiState.destroyQuantityMax = 1
        if setStatusMessage and remaining > 0 then
            setStatusMessage(string.format("Deleting... (%d queued)", remaining))
        end
    elseif next.type == "reroll_add" then
        local req = next.payload
        uiState.pendingRerollAdd = req
        if d.pickupFromSlot then d.pickupFromSlot(req.bag, req.slot, req.source) end
        if setStatusMessage then
            setStatusMessage(remaining > 0
                and string.format("Adding to list... (%d queued)", remaining)
                or "Adding to list...")
        end
    elseif next.type == "equip" then
        local preClear = next.preClearSlots or {}
        local initialPhase = (#preClear > 0) and "pre_clear_pickup" or "pickup"
        uiState.pendingEquipAction = {
            bag = next.bag, slot = next.slot, targetSlot = next.targetSlot,
            name = next.name, attuneable = next.attuneable,
            preClearSlots = preClear,
            preClearIdx   = 1,
            phase = initialPhase, phaseEnteredAt = now
        }
        if setStatusMessage then setStatusMessage("Equipping: " .. (next.name or "") .. "…") end
    end
end

-- Phase 8b: Pending reroll add (pickup -> send !augadd/!mythicaladd -> put back immediately)
-- Hybrid fire-and-forget: optimistically add to cache, send command, put item back and free
-- cursor immediately. Background ack listener rolls back on timeout (REROLL_BG_ACK_TIMEOUT_MS).
-- Queue management is handled by phase0_cursorActionQueue — phase8b only drives the current action.
local REROLL_ADD_PICKUP_TIMEOUT_MS = 800
local REROLL_BG_ACK_TIMEOUT_MS = 5000  -- background ack timeout; longer is fine since it doesn't block UI
local _bgAckPending = {}  -- { { itemId, list, sentAt, syncState, itemName }, ... }

local function phase8b_pendingRerollAdd(now)
    local uiState, hasItemOnCursor, removeItemFromCursor, setStatusMessage, invalidateSellConfigCache, invalidateLootConfigCache, rerollService, computeAndAttachSellStatus, inventoryItems, bankItems =
        d.uiState, d.hasItemOnCursor, d.removeItemFromCursor, d.setStatusMessage, d.invalidateSellConfigCache, d.invalidateLootConfigCache, d.rerollService, d.computeAndAttachSellStatus, d.inventoryItems, d.bankItems
    local rerollState = rerollService and rerollService.getState and rerollService.getState() or {}

    -- Background ack drain: check for timed-out background acks and roll back
    for i = #_bgAckPending, 1, -1 do
        local bg = _bgAckPending[i]
        if bg.acked then
            -- Server confirmed — handle sync bookkeeping if needed
            if bg.syncState then
                rerollService.removeFromPending(bg.list, bg.itemId)
                rerollService.addEntryToList(bg.list, bg.itemId, bg.itemName or "")
                bg.syncState.syncedCount = (bg.syncState.syncedCount or 0) + 1
                bg.syncState.nextIndex = (bg.syncState.nextIndex or 0) + 1
                if bg.syncState.nextIndex > #(bg.syncState.entries or {}) then
                    local sc, fc = bg.syncState.syncedCount or 0, bg.syncState.failedCount or 0
                    rerollState.pendingRerollSync = nil
                    if setStatusMessage then setStatusMessage(string.format("Sync done: %d synced, %d failed.", sc, fc)) end
                else
                    if setStatusMessage then setStatusMessage(string.format("Syncing %d/%d...", bg.syncState.nextIndex, bg.syncState.totalCount or 0)) end
                end
            end
            table.remove(_bgAckPending, i)
        elseif (now - bg.sentAt) > REROLL_BG_ACK_TIMEOUT_MS then
            -- Timed out — roll back optimistic cache add
            if not bg.syncState and rerollService.removeEntryFromCache then
                rerollService.removeEntryFromCache(bg.list, bg.itemId)
            end
            if bg.syncState then
                -- Don't abort entire sync; record failure and advance to next item
                bg.syncState.failedCount = (bg.syncState.failedCount or 0) + 1
                local fi = bg.syncState.failedItems or {}
                fi[#fi + 1] = { id = bg.itemId, name = bg.itemName or "", reason = "Server timeout" }
                bg.syncState.failedItems = fi
                bg.syncState.nextIndex = (bg.syncState.nextIndex or 0) + 1
                if bg.syncState.nextIndex > #(bg.syncState.entries or {}) then
                    local sc, fc = bg.syncState.syncedCount or 0, bg.syncState.failedCount or 0
                    rerollState.pendingRerollSync = nil
                    if setStatusMessage then setStatusMessage(string.format("Sync done: %d synced, %d failed.", sc, fc)) end
                else
                    if setStatusMessage then setStatusMessage(string.format("Syncing %d/%d (1 failed)...", bg.syncState.nextIndex, bg.syncState.totalCount or 0)) end
                end
            else
                if setStatusMessage then setStatusMessage("Server did not confirm add; list reverted.") end
            end
            if invalidateSellConfigCache then invalidateSellConfigCache() end
            if invalidateLootConfigCache then invalidateLootConfigCache() end
            if computeAndAttachSellStatus and inventoryItems and #inventoryItems > 0 then computeAndAttachSellStatus(inventoryItems) end
            if computeAndAttachSellStatus and bankItems and #bankItems > 0 then computeAndAttachSellStatus(bankItems) end
            table.remove(_bgAckPending, i)
        end
    end

    -- Sync pending: start next item when cursor is free and no add in flight.
    -- Skip items not in inventory (record as failed) and continue to next.
    if not uiState.pendingRerollAdd and rerollState.pendingRerollSync and hasItemOnCursor and not hasItemOnCursor() then
        local sync = rerollState.pendingRerollSync
        -- Advance past any items not found in inventory
        while sync and sync.nextIndex <= #(sync.entries or {}) do
            local idx = sync.nextIndex
            local entry = sync.entries[idx]
            if not entry then
                sync.nextIndex = idx + 1
            elseif not inventoryItems then
                rerollState.pendingRerollSync = nil
                break
            else
                local bag, slot, src = nil, nil, "inv"
                for _, inv in ipairs(inventoryItems) do
                    if (inv.id or inv.ID) == entry.id then bag, slot = inv.bag, inv.slot; break end
                end
                if bag and slot then
                    -- Found in inventory — start pickup flow
                    uiState.pendingRerollAdd = {
                        list = sync.list, bag = bag, slot = slot, source = src,
                        itemId = entry.id, itemName = entry.name or "", step = "pickup",
                        syncState = sync,
                    }
                    if d.pickupFromSlot then d.pickupFromSlot(bag, slot, src) end
                    if setStatusMessage then setStatusMessage(string.format("Syncing %d/%d...", idx, sync.totalCount or 0)) end
                    break
                else
                    -- Item not in inventory — record as failed, skip to next
                    sync.failedCount = (sync.failedCount or 0) + 1
                    local fi = sync.failedItems or {}
                    fi[#fi + 1] = { id = entry.id, name = entry.name or "", reason = "Not in inventory" }
                    sync.failedItems = fi
                    sync.nextIndex = idx + 1
                    if setStatusMessage then setStatusMessage(string.format("Syncing %d/%d (%s not found)...", idx, sync.totalCount or 0, entry.name or tostring(entry.id))) end
                end
            end
        end
        -- Check if we've exhausted all entries after skipping
        if rerollState.pendingRerollSync and rerollState.pendingRerollSync.nextIndex > #(rerollState.pendingRerollSync.entries or {}) then
            local sc, fc = rerollState.pendingRerollSync.syncedCount or 0, rerollState.pendingRerollSync.failedCount or 0
            rerollState.pendingRerollSync = nil
            if setStatusMessage then setStatusMessage(string.format("Sync done: %d synced, %d failed.", sc, fc)) end
        end
    end

    local pending = uiState.pendingRerollAdd
    if not pending or not rerollService then return end
    local lp = d.uiState.lastPickup

    if pending.step == "pickup" then
        if not pending.pickupStartedAt then pending.pickupStartedAt = now end
        local hasCursor = (d.hasItemOnCursorWithTLOFallback and d.hasItemOnCursorWithTLOFallback()) or false
        local lb, ls = tonumber(lp and lp.bag) or (lp and lp.bag), tonumber(lp and lp.slot) or (lp and lp.slot)
        local pb, ps = tonumber(pending.bag) or pending.bag, tonumber(pending.slot) or pending.slot
        if hasCursor and lp and lb == pb and ls == ps and (lp.source or "") == (pending.source or "") then
            -- Optimistically add to cache
            if not pending.syncState then
                rerollService.addEntryToList(pending.list, pending.itemId, pending.itemName or "")
            end
            -- Send the command
            local cmd = (pending.list == "aug") and (constants.REROLL and constants.REROLL.COMMAND_AUG_ADD or "!augadd") or (constants.REROLL and constants.REROLL.COMMAND_MYTHICAL_ADD or "!mythicaladd")
            mq.cmd("/say " .. cmd)
            -- Register background ack listener (fires asynchronously when server confirms)
            local bgEntry = { itemId = pending.itemId, list = pending.list, sentAt = now, syncState = pending.syncState, itemName = pending.itemName or "", acked = false }
            _bgAckPending[#_bgAckPending + 1] = bgEntry
            rerollService.setPendingAddAck(pending.itemId, function()
                bgEntry.acked = true
            end)
            -- Immediately put item back and free cursor — don't wait for ack
            if removeItemFromCursor then removeItemFromCursor() end
            uiState.pendingRerollAdd = nil
            -- Invalidate caches now so UI updates immediately
            if invalidateSellConfigCache then invalidateSellConfigCache() end
            if invalidateLootConfigCache then invalidateLootConfigCache() end
            if computeAndAttachSellStatus and inventoryItems and #inventoryItems > 0 then computeAndAttachSellStatus(inventoryItems) end
            if computeAndAttachSellStatus and bankItems and #bankItems > 0 then computeAndAttachSellStatus(bankItems) end
            if not pending.syncState then
                local q = uiState.cursorActionQueue or {}
                local queueMsg = #q > 0 and string.format(" (%d queued)", #q) or ""
                if setStatusMessage then setStatusMessage("Added to list." .. queueMsg) end
            end
        elseif pending.pickupStartedAt and (now - pending.pickupStartedAt) > REROLL_ADD_PICKUP_TIMEOUT_MS then
            -- Pickup failed
            if removeItemFromCursor then removeItemFromCursor() end
            uiState.pendingRerollAdd = nil
            if pending.syncState then
                -- Don't abort entire sync; record failure and advance to next item
                local sync = pending.syncState
                sync.failedCount = (sync.failedCount or 0) + 1
                local fi = sync.failedItems or {}
                fi[#fi + 1] = { id = pending.itemId, name = pending.itemName or "", reason = "Pickup timeout" }
                sync.failedItems = fi
                sync.nextIndex = (sync.nextIndex or 0) + 1
                if sync.nextIndex > #(sync.entries or {}) then
                    local sc, fc = sync.syncedCount or 0, sync.failedCount or 0
                    rerollState.pendingRerollSync = nil
                    if setStatusMessage then setStatusMessage(string.format("Sync done: %d synced, %d failed.", sc, fc)) end
                else
                    if setStatusMessage then setStatusMessage(string.format("Syncing %d/%d (1 pickup failed)...", sync.nextIndex, sync.totalCount or 0)) end
                end
            else
                local q = uiState.cursorActionQueue or {}
                local queueMsg = #q > 0 and string.format(" (%d queued)", #q) or ""
                if setStatusMessage then setStatusMessage("Add failed (pickup timeout)." .. queueMsg) end
            end
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
        if d.rerollService and d.rerollService.resumeLocationCache then d.rerollService.resumeLocationCache() end
        return
    end
    if not hasItemOnCursor() then return end
    local itemOps = d.itemOps
    local name = (itemOps and itemOps.getCursorItemName and itemOps.getCursorItemName()) or (mq.TLO.Cursor and mq.TLO.Cursor.Name and mq.TLO.Cursor.Name()) or ""
    if name and name ~= "" then
        dbgAugment.log("Augment roll result: " .. name)
        local link = (itemOps and itemOps.getCursorItemLink and itemOps.getCursorItemLink()) or (mq.TLO.Cursor and (mq.TLO.Cursor.Link and mq.TLO.Cursor.Link() or mq.TLO.Cursor.ItemLink and mq.TLO.Cursor.ItemLink())) or nil
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
    -- Schedule reroll quick refresh so count updates and next roll doesn't use stale items.
    uiState.rerollPendingScan = true
    uiState.rerollPendingScanAt = now
end

-- Phase 9: Debounced layout save, cache cleanup, debug log flush
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
    local dbg = require('itemui.core.debug')
    if dbg and dbg.flushLogFile then dbg.flushLogFile() end
end

-- Phase 10: Loop delay and doevents
local function phase10_loopDelay()
    local getShouldDraw, C = d.getShouldDraw, d.C
    mq.delay(getShouldDraw() and C.LOOP_DELAY_VISIBLE_MS or C.LOOP_DELAY_HIDDEN_MS)
    mq.doevents()
end

-- Phase for equip action state machine:
--   [pre_clear_pickup → pre_clear_settle] × N slots → pickup → settle_pickup → settle_place → wait_autoinv → done
--   pre_clear phases iterate ea.preClearSlots (e.g. {"offhand","mainhand"} for primary-only items).
--   Each slot: pick up via /itemnotify, wait for cursor, /autoinventory if needed, advance to next.
--   settle_place polls cursor each tick: accepts attunement dialog, detects cursor-clear success,
--   or autoinventories a displaced item → wait_autoinv.
local EQUIP_SETTLE_PICKUP_MS    = 200   -- Reduced from 350; wait after issuing pickup before checking cursor
local EQUIP_PICKUP_TIMEOUT_MS   = 3000  -- give up if item never reaches cursor
local EQUIP_PRE_CLEAR_SETTLE_MS     = 200   -- Reduced from 350; wait after /itemnotify <slot> before checking cursor
local EQUIP_PRE_CLEAR_PRE_SETTLE_MS = 100   -- Reduced from 150; min wait before issuing next /itemnotify (let previous autoinv land)
local EQUIP_PRE_CLEAR_TIMEOUT_MS    = 5000  -- abort pre-clear phase if slot never clears (bags full?)
local EQUIP_MIN_SETTLE_PLACE_MS = 80    -- Reduced from 100; minimum dwell in settle_place before any action
local EQUIP_PLACE_TIMEOUT_MS    = 5000  -- safety timeout for settle_place
local EQUIP_AUTOINV_SETTLE_MS   = 150   -- Reduced from 250; wait after /autoinventory before declaring done
local EQUIP_DISPLACED_ITEM_MS  = 250   -- Reduced from 400 (was hard-coded); cursor still has item → displaced; send to bags
local function phaseEquipAction(now)
    local uiState = d.uiState
    if not uiState then return end
    local ea = uiState.pendingEquipAction
    if not ea then return end
    local setStatus = d.setStatusMessage

    -- PRE_CLEAR_PICKUP: pick up the current slot in the pre-clear list.
    -- Safe when slot is empty — cursor stays clear, autoinventory is skipped in settle.
    -- Minimum pre-wait (EQUIP_PRE_CLEAR_PRE_SETTLE_MS) ensures any previous /autoinventory
    -- has fully landed at the game-engine level before we issue the next /itemnotify.
    if ea.phase == "pre_clear_pickup" then
        if not ea.preClearPreWaitAt then
            ea.preClearPreWaitAt = now
            return
        end
        if (now - ea.preClearPreWaitAt) < EQUIP_PRE_CLEAR_PRE_SETTLE_MS then return end
        local slotName = (ea.preClearSlots or {})[ea.preClearIdx or 1]
        if slotName then
            mq.cmdf('/itemnotify %s leftmouseup', slotName)
        end
        ea.phase = "pre_clear_settle"
        ea.phaseEnteredAt = now
        ea.preClearPreWaitAt   = nil
        ea.preClearSentAutoinv = nil
        ea.preClearAutoinvAt   = nil
        return
    end

    -- PRE_CLEAR_SETTLE: wait for item on cursor, autoinventory it, then confirm cursor is
    -- actually clear before advancing — no time-based fallthrough.
    -- Safety abort after EQUIP_PRE_CLEAR_TIMEOUT_MS (e.g. bags full).
    if ea.phase == "pre_clear_settle" then
        if (now - ea.phaseEnteredAt) < EQUIP_PRE_CLEAR_SETTLE_MS then return end
        if d.hasItemOnCursor and d.hasItemOnCursor() then
            -- Abort if stuck too long (bags full, item can't be stowed)
            if (now - ea.phaseEnteredAt) > EQUIP_PRE_CLEAR_TIMEOUT_MS then
                if setStatus then setStatus("Equip failed: could not clear slot (bags full?)") end
                uiState.pendingEquipAction = nil
                return
            end
            if not ea.preClearSentAutoinv then
                mq.cmd('/autoinventory')
                ea.preClearSentAutoinv = true
                ea.preClearAutoinvAt   = now
            end
            -- Keep polling every tick until cursor is confirmed clear.
            -- Do NOT fall through on a time-based assumption — that causes the race condition
            -- where EQ interprets the next /itemnotify as "equip cursor item" instead of
            -- "pick up from slot".
            return
        end
        -- Cursor confirmed clear; advance to next slot or to pickup phase
        ea.preClearSentAutoinv = nil
        ea.preClearAutoinvAt   = nil
        ea.preClearIdx = (ea.preClearIdx or 1) + 1
        local slots = ea.preClearSlots or {}
        if ea.preClearIdx <= #slots then
            ea.phase = "pre_clear_pickup"   -- more slots to clear
        else
            ea.phase = "pickup"             -- all clear, pick up the item to equip
        end
        ea.phaseEnteredAt = now
        return
    end

    -- PICKUP: pick up the item we want to equip (sets lastPickup guard)
    if ea.phase == "pickup" then
        if d.pickupFromSlot then d.pickupFromSlot(ea.bag, ea.slot, "inv") end
        ea.phase = "settle_pickup"
        ea.phaseEnteredAt = now
        return
    end

    -- SETTLE_PICKUP: wait for item to appear on cursor; timeout aborts
    if ea.phase == "settle_pickup" then
        if (now - ea.phaseEnteredAt) < EQUIP_SETTLE_PICKUP_MS then return end
        if d.hasItemOnCursor and not d.hasItemOnCursor() then
            if (now - ea.phaseEnteredAt) > EQUIP_PICKUP_TIMEOUT_MS then
                if setStatus then setStatus("Equip failed: could not pick up '" .. (ea.name or "") .. "'.") end
                uiState.pendingEquipAction = nil
            end
            return
        end
        -- Item on cursor — place it on the target equipment slot
        mq.cmdf('/itemnotify %s leftmouseup', ea.targetSlot)
        ea.phase = "settle_place"
        ea.phaseEnteredAt = now
        return
    end

    -- SETTLE_PLACE: per-tick poll after placing item on slot.
    --   • Accept attunement confirmation dialog if it appears.
    --   • Cursor clear → equip succeeded, done.
    --   • Cursor still has item after 400 ms → displaced item; autoinventory → wait_autoinv.
    --   • Safety timeout at EQUIP_PLACE_TIMEOUT_MS.
    if ea.phase == "settle_place" then
        local elapsed = now - ea.phaseEnteredAt
        -- Safety timeout
        if elapsed > EQUIP_PLACE_TIMEOUT_MS then
            if d.hasItemOnCursor and d.hasItemOnCursor() then mq.cmd('/autoinventory') end
            if setStatus then setStatus("Equipped (timeout): " .. (ea.name or "")) end
            uiState.pendingEquipAction = nil
            if d.refreshEquipmentCache then d.refreshEquipmentCache() end
            return
        end
        -- Enforce minimum settle before doing anything
        if elapsed < EQUIP_MIN_SETTLE_PLACE_MS then return end
        -- Check for attunement confirmation dialog and accept it
        local dlgOpen = false
        do
            local ok, dlg = pcall(function() return mq.TLO.Window and mq.TLO.Window("ConfirmationDialogWnd") end)
            dlgOpen = ok and dlg and dlg.Open and dlg.Open()
        end
        if dlgOpen then
            mq.cmd('/notify ConfirmationDialogWnd Yes_Button leftmouseup')
            -- Stay in settle_place; cursor will clear once the game processes the equip
            return
        end
        -- Check cursor state
        local hasCursor = d.hasItemOnCursor and d.hasItemOnCursor()
        if not hasCursor then
            -- Cursor is clear — equip succeeded
            if setStatus then setStatus("Equipped: " .. (ea.name or "")) end
            uiState.pendingEquipAction = nil
            if d.refreshEquipmentCache then d.refreshEquipmentCache() end
            return
        end
        -- Item still on cursor after sufficient dwell → displaced item; send to bags
        if elapsed >= EQUIP_DISPLACED_ITEM_MS then
            mq.cmd('/autoinventory')
            ea.phase = "wait_autoinv"
            ea.phaseEnteredAt = now
        end
        return
    end

    -- WAIT_AUTOINV: short dwell after /autoinventory before declaring done
    if ea.phase == "wait_autoinv" then
        if (now - ea.phaseEnteredAt) < EQUIP_AUTOINV_SETTLE_MS then return end
        if setStatus then setStatus("Equipped: " .. (ea.name or "")) end
        uiState.pendingEquipAction = nil
        if d.refreshEquipmentCache then d.refreshEquipmentCache() end
        return
    end
end

-- Phase 5b: Drain deferred loot sell-status (15/tick to avoid burst stutter)
local SELL_STATUS_DRAIN_PER_TICK = 15
local function phase5b_lootSellStatusDrain()
    local pending = d.uiState and d.uiState.pendingLootSellStatus
    if not pending or #pending == 0 then return end
    local getSellStatus = d.getSellStatusForItem
    if not getSellStatus then return end
    local count = math.min(SELL_STATUS_DRAIN_PER_TICK, #pending)
    for _ = 1, count do
        local job = table.remove(pending, 1)
        local st, ws = getSellStatus({ name = job.entry.name })
        if st == "" then st = "—" end
        job.entry.statusText = st
        job.entry.willSell = ws
        if job.histEntry then
            job.histEntry.statusText = st
            job.histEntry.willSell = ws
        end
    end
end

local M = {}

function M.init(deps)
    d = deps
    lootFeedEvents.init(d)
    scriptConsumeEvents.init(d)
end

function M.tick(now)
    if d.macroBridge and d.macroBridge.poll then d.macroBridge.poll() end
    phase1_statusExpiry(now)
    phase1b_activationGuard(now)
    phase0_cursorActionQueue(now)
    phase2_periodicPersist(now)
    phase3_autoSellRequest()
    phase4_sellMacroFinish(now)
    phase5_lootMacro(now)
    phaseEquipAction(now)
    -- Drain IPC after phase 5 so run-start clear in phase 5 doesn't wipe items we just drained
    if d.macroBridge and d.macroBridge.drainIPCFast then
        d.macroBridge.drainIPCFast(d.uiState, d.getSellStatusForItem, d.LOOT_HISTORY_MAX)
    end
    phase5b_lootSellStatusDrain()
    phase6_deferredHistorySaves(now)
    -- Drain deferred close-saves (1 per tick to spread disk I/O across frames)
    local closeSaves = d.uiState and d.uiState._deferredCloseSaves
    if closeSaves and #closeSaves > 0 then
        local fn = table.remove(closeSaves, 1)
        if fn then pcall(fn) end
        if #closeSaves == 0 then d.uiState._deferredCloseSaves = nil end
    end
    -- Advance incremental inventory scan (2 bags/frame; used after loot to avoid stutter)
    if d.processIncrementalScan then d.processIncrementalScan() end
    phase7_sellQueueQuantityDestroyMoveAugment(now)
    phase8_windowStateDeferredScansAutoShowAugmentTimeouts(now)
    phase8b_pendingRerollAdd(now)
    if d.rerollService and d.rerollService.checkListRequestTimeout then d.rerollService.checkListRequestTimeout(now) end
    phase8c_pendingAugRollComplete(now)
    phase9_layoutSaveCacheCleanup(now)
    phase10_loopDelay()
end

return M
