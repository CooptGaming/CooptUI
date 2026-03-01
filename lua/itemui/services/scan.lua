--[[
    ItemUI Scan Service
    Inventory, bank, sell, and loot scanning. Uses env (init) for all dependencies
    to avoid 60-upvalue limit and keep init.lua under the 200-local limit.
    Call scan.init(env) once from init.lua, then use scan.scanInventory(), etc.
    When MQ2CoOptUI plugin is loaded, uses plugin batch scan (Task 6.4).
--]]

local mq = require('mq')
local pluginShim = require('itemui.services.plugin_shim')

local M = {}
local env

function M.init(e)
    env = e
end

-- Fingerprint helpers (use env.scanState.lastBagFingerprints)
local function buildBagFingerprint(bagNum)
    local parts = {}
    local Me = mq.TLO and mq.TLO.Me
    local pack = Me and Me.Inventory and Me.Inventory("pack" .. bagNum)
    if pack and pack.Container then
        local bagSize = pack.Container()
        if bagSize and bagSize > 0 then
            for slotNum = 1, bagSize do
                local item = pack.Item and pack.Item(slotNum)
                local id = (item and item.ID and item.ID()) or 0
                local stack = (item and item.Stack and item.Stack()) or 0
                if id == 0 then stack = 0 end
                parts[#parts + 1] = string.format("%d,%d,%d", slotNum, id, stack)
            end
        end
    end
    return table.concat(parts, "|")
end

local function buildInventoryFingerprint()
    local parts = {}
    local lastBagFingerprints = env.scanState.lastBagFingerprints
    for bagNum = 1, 10 do
        local bagFp = buildBagFingerprint(bagNum)
        lastBagFingerprints[bagNum] = bagFp
        parts[#parts + 1] = string.format("b%d:%s", bagNum, bagFp)
    end
    return table.concat(parts, "|")
end

-- Lightweight version: concatenates already-stored per-bag fingerprints (no TLO calls)
-- Used after targetedRescanBags where getChangedBags() already updated changed bag fingerprints
local function buildInventoryFingerprintFromCache()
    local parts = {}
    local lastBagFingerprints = env.scanState.lastBagFingerprints
    for bagNum = 1, 10 do
        parts[#parts + 1] = string.format("b%d:%s", bagNum, lastBagFingerprints[bagNum] or "")
    end
    return table.concat(parts, "|")
end

local function getChangedBags()
    local changed = {}
    local lastBagFingerprints = env.scanState.lastBagFingerprints
    for bagNum = 1, 10 do
        local currentFp = buildBagFingerprint(bagNum)
        local lastFp = lastBagFingerprints[bagNum] or ""
        if currentFp ~= lastFp then
            table.insert(changed, bagNum)
            -- Update in-place so we don't rebuild for unchanged bags later
            lastBagFingerprints[bagNum] = currentFp
        end
    end
    return changed
end

--- Update lastBagFingerprints for the given bags only. Used before targetedRescanBags when caller knows which bags changed.
local function updateFingerprintsForBags(bagList)
    if not bagList or #bagList == 0 then return end
    local lastBagFingerprints = env.scanState.lastBagFingerprints
    for _, bagNum in ipairs(bagList) do
        lastBagFingerprints[bagNum] = buildBagFingerprint(bagNum)
    end
end

-- Inventory scan
function M.scanInventory()
    local t0 = mq.gettime()
    local inventoryItems = env.inventoryItems
    env.invalidateSortCache("inv")
    env.invalidateTimerReadyCache()
    if env.perfCache.loreHaveCache then env.perfCache.loreHaveCache = {} end
    -- Preserve acquiredSeq by bag:slot before clear (full scan rebuilds new item refs)
    local acquiredMap = {}
    for _, it in ipairs(inventoryItems) do
        if it.acquiredSeq then acquiredMap[it.bag .. ":" .. it.slot] = it.acquiredSeq end
    end
    -- Clear and repopulate
    for i = #inventoryItems, 1, -1 do inventoryItems[i] = nil end
    local usedPlugin = false
    local itemsMod = pluginShim.items()
    if itemsMod and itemsMod.scanInventory then
        local ok, pluginItems = pcall(itemsMod.scanInventory, itemsMod)
        if ok and pluginItems and type(pluginItems) == "table" then
            for _, it in ipairs(pluginItems) do
                if it and (it.bag or it.slot) then
                    it.source = it.source or "inv"
                    table.insert(inventoryItems, it)
                end
            end
            usedPlugin = true
        end
    end
    if not usedPlugin then
        local seen = {}
        local buildItemFromMQ = env.buildItemFromMQ
        local Me = mq.TLO and mq.TLO.Me
        if Me and Me.Inventory then
            for bagNum = 1, 10 do
                local pack = Me.Inventory("pack" .. bagNum)
                if pack and pack.Container and pack.Container() then
                    local bagSize = pack.Container()
                    for slotNum = 1, bagSize do
                        local key = bagNum .. ":" .. slotNum
                        if not seen[key] then
                            seen[key] = true
                            local item = pack.Item and pack.Item(slotNum)
                            local it = buildItemFromMQ(item, bagNum, slotNum)
                            if it then table.insert(inventoryItems, it) end
                        end
                    end
                end
            end
        end
    end
    local scanState = env.scanState
    for _, it in ipairs(inventoryItems) do
        it.acquiredSeq = acquiredMap[it.bag .. ":" .. it.slot]
        if not it.acquiredSeq then
            it.acquiredSeq = scanState.nextAcquiredSeq
            scanState.nextAcquiredSeq = scanState.nextAcquiredSeq + 1
        end
    end
    local scanMs = mq.gettime() - t0
    env.perfCache.lastScanTimeInv = mq.gettime()
    local saveMs = 0
    local now = mq.gettime()
    local shouldPersist = (scanState.lastPersistSaveTime == 0) or ((now - scanState.lastPersistSaveTime) >= env.C.PERSIST_SAVE_INTERVAL_MS)
    if shouldPersist and mq.TLO.Me and mq.TLO.Me.Name and mq.TLO.Me.Name() ~= "" and #inventoryItems > 0 then
        local t1 = mq.gettime()
        env.storage.ensureCharFolderExists()
        env.computeAndAttachSellStatus(inventoryItems)
        env.storage.saveInventory(inventoryItems)
        env.storage.writeSellCache(inventoryItems)
        saveMs = mq.gettime() - t1
        scanState.lastPersistSaveTime = now
    end
    if env.C.PROFILE_ENABLED and (scanMs >= env.C.PROFILE_THRESHOLD_MS or saveMs >= env.C.PROFILE_THRESHOLD_MS) then
        local src = usedPlugin and " (plugin)" or ""
        print(string.format("\ag[CoOpt UI Profile]\ax scanInventory: scan=%d ms, save=%d ms (%d items)%s", scanMs, saveMs, #inventoryItems, src))
    end
    scanState.lastInventoryFingerprint = buildInventoryFingerprint()
    if env.invalidateTooltipCache then env.invalidateTooltipCache() end
    if env.buildAugmentIndex then env.buildAugmentIndex() end
end

-- Incremental scan state (internal to this module)
local incrementalScanState = {
    active = false,
    currentBag = 1,
    newItems = {},
    seen = {},
    startTime = 0,
    bagsPerFrame = 2,
}

function M.startIncrementalScan()
    incrementalScanState.active = true
    incrementalScanState.currentBag = 1
    incrementalScanState.newItems = {}
    incrementalScanState.seen = {}
    incrementalScanState.startTime = mq.gettime()
    env.invalidateSortCache("inv")
    env.invalidateTimerReadyCache()
end

function M.processIncrementalScan()
    if not incrementalScanState.active then return true end
    local inventoryItems = env.inventoryItems
    local buildItemFromMQ = env.buildItemFromMQ
    local bagsScanned = 0
    local Me = mq.TLO and mq.TLO.Me
    if not Me or not Me.Inventory then incrementalScanState.active = false; return true end
    while incrementalScanState.currentBag <= 10 and bagsScanned < incrementalScanState.bagsPerFrame do
        local bagNum = incrementalScanState.currentBag
        local pack = Me.Inventory("pack" .. bagNum)
        if pack and pack.Container and pack.Container() then
            local bagSize = pack.Container()
            for slotNum = 1, bagSize do
                local key = bagNum .. ":" .. slotNum
                if not incrementalScanState.seen[key] then
                    incrementalScanState.seen[key] = true
                    local item = pack.Item and pack.Item(slotNum)
                    local it = buildItemFromMQ(item, bagNum, slotNum)
                    if it then table.insert(incrementalScanState.newItems, it) end
                end
            end
        end
        incrementalScanState.currentBag = incrementalScanState.currentBag + 1
        bagsScanned = bagsScanned + 1
    end
    local acquiredMap = {}
    for _, it in ipairs(inventoryItems) do
        if it.acquiredSeq then acquiredMap[it.bag .. ":" .. it.slot] = it.acquiredSeq end
    end
    for i = #inventoryItems, 1, -1 do inventoryItems[i] = nil end
    for _, it in ipairs(incrementalScanState.newItems) do
        table.insert(inventoryItems, it)
    end
    local scanState = env.scanState
    for _, it in ipairs(inventoryItems) do
        it.acquiredSeq = acquiredMap[it.bag .. ":" .. it.slot]
        if not it.acquiredSeq then
            it.acquiredSeq = scanState.nextAcquiredSeq
            scanState.nextAcquiredSeq = scanState.nextAcquiredSeq + 1
        end
    end
    if incrementalScanState.currentBag > 10 then
        local scanMs = mq.gettime() - incrementalScanState.startTime
        env.perfCache.lastScanTimeInv = mq.gettime()
        local saveMs = 0
        if mq.TLO.Me and mq.TLO.Me.Name and mq.TLO.Me.Name() ~= "" and #inventoryItems > 0 then
            local t1 = mq.gettime()
            env.storage.ensureCharFolderExists()
            env.computeAndAttachSellStatus(inventoryItems)
            env.storage.saveInventory(inventoryItems)
            env.storage.writeSellCache(inventoryItems)
            saveMs = mq.gettime() - t1
        end
        if env.C.PROFILE_ENABLED and (scanMs >= env.C.PROFILE_THRESHOLD_MS or saveMs >= env.C.PROFILE_THRESHOLD_MS) then
            print(string.format("\ag[CoOpt UI Profile]\ax incrementalScanInventory: scan=%d ms, save=%d ms (%d items, %d bags/frame)",
                scanMs, saveMs, #inventoryItems, incrementalScanState.bagsPerFrame))
        end
        env.scanState.lastInventoryFingerprint = buildInventoryFingerprint()
        incrementalScanState.active = false
        return true
    end
    return false
end

local function targetedRescanBags(changedBags)
    if not changedBags or #changedBags == 0 then return end
    local t0 = mq.gettime()
    local inventoryItems = env.inventoryItems
    local buildItemFromMQ = env.buildItemFromMQ
    if env.perfCache.loreHaveCache then env.perfCache.loreHaveCache = {} end
    env.invalidateSortCache("inv")
    env.invalidateTimerReadyCache()
    -- Build O(1) lookup set for changed bag numbers
    local changedSet = {}
    for _, bagNum in ipairs(changedBags) do changedSet[bagNum] = true end
    -- Remove items from changed bags in-place (backward iteration)
    for i = #inventoryItems, 1, -1 do
        if changedSet[inventoryItems[i].bag] then
            table.remove(inventoryItems, i)
        end
    end
    -- Append rescanned items for changed bags
    local Me = mq.TLO and mq.TLO.Me
    for _, bagNum in ipairs(changedBags) do
        local pack = Me and Me.Inventory and Me.Inventory("pack" .. bagNum)
        if pack and pack.Container and pack.Container() then
            local bagSize = pack.Container()
            for slotNum = 1, bagSize do
                local item = pack.Item and pack.Item(slotNum)
                local it = buildItemFromMQ(item, bagNum, slotNum)
                if it then
                    it.acquiredSeq = env.scanState.nextAcquiredSeq
                    env.scanState.nextAcquiredSeq = env.scanState.nextAcquiredSeq + 1
                    inventoryItems[#inventoryItems + 1] = it
                end
            end
        end
    end
    local scanMs = mq.gettime() - t0
    if env.C.PROFILE_ENABLED and scanMs >= env.C.PROFILE_THRESHOLD_MS then
        print(string.format("\ag[CoOpt UI Profile]\ax targetedRescan: %d ms (%d bags, %d items)", scanMs, #changedBags, #inventoryItems))
    end
    -- Use cached fingerprints (getChangedBags already updated per-bag fingerprints in-place)
    env.scanState.lastInventoryFingerprint = buildInventoryFingerprintFromCache()
end

--- Rescan only the given inventory bags (1-based pack numbers). Updates fingerprints for those bags then runs targetedRescanBags.
--- Use when the caller knows which bags changed (e.g. after move, destroy, drop). For unknown bags use maybeScanInventory or scanInventory.
function M.rescanInventoryBags(bagList)
    if not bagList or #bagList == 0 then return end
    updateFingerprintsForBags(bagList)
    targetedRescanBags(bagList)
end

-- Bank scan
function M.scanBank()
    local bankItems = env.bankItems
    local bankCache = env.bankCache
    env.invalidateSortCache("bank")
    for i = #bankItems, 1, -1 do bankItems[i] = nil end
    local usedPlugin = false
    local itemsMod = pluginShim.items()
    if itemsMod and itemsMod.scanBank then
        local ok, pluginItems = pcall(itemsMod.scanBank, itemsMod)
        if ok and pluginItems and type(pluginItems) == "table" then
            for _, it in ipairs(pluginItems) do
                if it and (it.bag or it.slot) then
                    it.source = it.source or "bank"
                    table.insert(bankItems, it)
                end
            end
            usedPlugin = true
        end
    end
    if not usedPlugin then
        local Me = mq.TLO and mq.TLO.Me
        if not Me or not Me.Bank then return end
        local buildItemFromMQ = env.buildItemFromMQ
        local maxSlots = env.C.MAX_BANK_SLOTS or 24
        for bagNum = 1, maxSlots do
        local slot = Me.Bank(bagNum)
        if slot then
            local bagSize = (slot.Container and slot.Container()) or 0
            if bagSize and bagSize > 0 then
                for slotNum = 1, bagSize do
                    local item = slot.Item and slot.Item(slotNum)
                    -- MQ ItemSlot/ItemSlot2 are 0-based; convert to 1-based for storage (see docs/ITEM_INDEX_BASE.md)
                    local islot = item and (item.ItemSlot and item.ItemSlot()) or (bagNum - 1)
                    local islot2 = item and (item.ItemSlot2 and item.ItemSlot2()) or (slotNum - 1)
                    local it = buildItemFromMQ(item, (islot or (bagNum - 1)) + 1, (islot2 or (slotNum - 1)) + 1, "bank")
                    if it then table.insert(bankItems, it) end
                end
            elseif (slot.ID and slot.ID()) and slot.ID() > 0 then
                -- Single-item bank slot; ItemSlot/ItemSlot2 0-based -> 1-based (see docs/ITEM_INDEX_BASE.md)
                local islot = (slot.ItemSlot and slot.ItemSlot()) or (bagNum - 1)
                local islot2 = (slot.ItemSlot2 and slot.ItemSlot2()) or 0
                local it = buildItemFromMQ(slot, (islot or (bagNum - 1)) + 1, (islot2 or 0) + 1, "bank")
                if it then table.insert(bankItems, it) end
            end
        end
    end
    end
    env.scanState.lastScanTimeBank = mq.gettime()
    if #bankItems > 0 and env.computeAndAttachSellStatus then env.computeAndAttachSellStatus(bankItems) end
    if env.isBankWindowOpen() then
        for i = #bankCache, 1, -1 do bankCache[i] = nil end
        for _, it in ipairs(bankItems) do table.insert(bankCache, it) end
        env.perfCache.lastBankCacheTime = os.time()
        local now = mq.gettime()
        local scanState = env.scanState
        local shouldPersist = (scanState.lastPersistSaveTime == 0) or ((now - scanState.lastPersistSaveTime) >= env.C.PERSIST_SAVE_INTERVAL_MS)
        if shouldPersist and mq.TLO.Me and mq.TLO.Me.Name and mq.TLO.Me.Name() ~= "" then
            env.storage.ensureCharFolderExists()
            env.storage.saveBank(bankItems)
            scanState.lastPersistSaveTime = now
        end
    end
    if env.invalidateTooltipCache then env.invalidateTooltipCache() end
    if env.buildAugmentIndex then env.buildAugmentIndex() end
end

function M.ensureBankCacheFromStorage()
    if not env.isBankWindowOpen() and (#env.bankCache == 0) then
        local stored, _ = env.storage.loadBank()
        if stored and #stored > 0 then
            for i = #env.bankCache, 1, -1 do env.bankCache[i] = nil end
            for _, it in ipairs(stored) do
                it.source = it.source or "bank"
                table.insert(env.bankCache, it)
            end
            env.perfCache.lastBankCacheTime = os.time()
        end
    end
end

-- Sell items: lightweight copy of inventory items with sell-status fields attached
-- Uses flat copy (single-depth table) to avoid shared-reference issues between
-- sellItems and inventoryItems (shared refs caused doubling when both arrays
-- pointed to the same objects during concurrent scan/render cycles).
--
-- Atomic swap pattern: builds the new list into a local temp table first, then
-- replaces sellItems contents in one non-yielding block at the end. This prevents
-- reentrancy issues where MQ Lua yields to the ImGui render callback mid-loop,
-- render sees sellItems=0 (after clear), triggers a second scanSellItems, and the
-- first scan's continued appends double the list.
local scanSellItemsRunning = false

function M.scanSellItems()
    -- Reentrancy guard: if already scanning, bail out
    if scanSellItemsRunning then return end
    scanSellItemsRunning = true

    env.invalidateSortCache("sell")
    if not env.perfCache.sellConfigCache then env.loadSellConfigCache() end
    local sellItems = env.sellItems
    local inventoryItems = env.inventoryItems
    local willItemBeSold = env.willItemBeSold
    -- Reuse cached stored-inv-by-name (2s TTL) instead of full disk read per scan
    local storedByName = env.getStoredInvByName and env.getStoredInvByName() or {}
    -- Build into a local temp table (not visible to render callback)
    local newItems = {}
    for _, item in ipairs(inventoryItems) do
        -- Flat copy: all item fields are scalar (no nested tables), so shallow copy is sufficient
        local dup = {}
        for k, v in pairs(item) do dup[k] = v end
        -- Use single source of truth for granular flags (fixes augment bug)
        env.attachGranularFlags(dup, storedByName)
        local ws, reason = willItemBeSold(dup)
        dup.willSell, dup.sellReason = ws, reason
        newItems[#newItems + 1] = dup
    end
    -- Atomic swap: clear and repopulate in one non-yielding block
    for i = #sellItems, 1, -1 do sellItems[i] = nil end
    for i, v in ipairs(newItems) do sellItems[i] = v end

    if env.invalidateTooltipCache then env.invalidateTooltipCache() end
    scanSellItemsRunning = false
end

function M.loadSnapshotsFromDisk()
    local loaded = false
    local invItems, _, nextSeq = env.storage.loadInventory()
    if invItems and #invItems > 0 then
        for i = #env.inventoryItems, 1, -1 do env.inventoryItems[i] = nil end
        for _, it in ipairs(invItems) do table.insert(env.inventoryItems, it) end
        if nextSeq then env.scanState.nextAcquiredSeq = nextSeq end
        loaded = true
    end
    local bankItems_, bankSavedAt = env.storage.loadBank()
    if bankItems_ and #bankItems_ > 0 then
        for i = #env.bankCache, 1, -1 do env.bankCache[i] = nil end
        for _, it in ipairs(bankItems_) do
            it.source = it.source or "bank"
            table.insert(env.bankCache, it)
        end
        env.perfCache.lastBankCacheTime = bankSavedAt or 0
        loaded = true
    end
    return loaded
end

function M.maybeScanInventory(invOpen)
    local inventoryItems = env.inventoryItems
    if #inventoryItems == 0 then
        M.scanInventory()
        env.scanState.lastScanState.invOpen = invOpen
        return
    end
    local scanState = env.scanState
    local throttleMs = env.C and env.C.GET_CHANGED_BAGS_THROTTLE_MS or 600
    local now = mq.gettime()
    local skipFingerprint = false
    if scanState.inventoryBagsDirty then
        scanState.inventoryBagsDirty = false
    elseif throttleMs > 0 and (now - (scanState.lastGetChangedBagsTime or 0)) < throttleMs then
        skipFingerprint = true
    end
    local changedBags
    if skipFingerprint then
        changedBags = {}
    else
        scanState.lastGetChangedBagsTime = now
        changedBags = getChangedBags()
    end
    if #changedBags > 0 then
        if #changedBags >= 3 then
            M.scanInventory()
        else
            targetedRescanBags(changedBags)
        end
    end
    env.scanState.lastScanState.invOpen = invOpen
end

function M.maybeScanBank(bankOpen)
    if not bankOpen then
        env.scanState.lastScanState.bankOpen = false
        return
    end
    if #env.bankItems == 0 or env.scanState.lastScanState.bankOpen ~= bankOpen then
        M.scanBank()
        env.scanState.lastScanState.bankOpen = bankOpen
    end
end

function M.maybeScanSellItems(merchOpen)
    if #env.sellItems == 0 or env.scanState.lastScanState.merchOpen ~= merchOpen then
        M.scanSellItems()
        env.scanState.lastScanState.merchOpen = merchOpen
    end
end

-- Loot scan
function M.scanLootItems()
    local lootItems = env.lootItems
    for i = #lootItems, 1, -1 do lootItems[i] = nil end
    local corpse = mq.TLO and mq.TLO.Corpse
    local itemsCount = corpse and corpse.Items and corpse.Items()
    if not corpse or not itemsCount or (type(itemsCount) ~= "number") or itemsCount <= 0 then return end
    env.perfCache.lootConfigCache = env.perfCache.lootConfigCache or env.rules.loadLootConfigCache()
    local lootCache = env.perfCache.lootConfigCache
    -- Reroll List protection: merge aug/mythical list IDs and names so shouldItemBeLooted can skip them.
    if lootCache and env.getRerollListProtection then
        local r = env.getRerollListProtection()
        if r then lootCache.rerollListIdSet = r.idSet; lootCache.rerollListNameSet = r.nameSet end
    end
    for i = 1, itemsCount do
        local it = corpse.Item and corpse.Item(i)
        local itId = it and it.ID and it.ID()
        if it and itId and type(itId) == "number" and itId > 0 then
            local name = it.Name and it.Name() or ""
            local itemType = it.Type and it.Type() or ""
            local value = it.Value and it.Value() or 0
            local stackSize = it.Stack and it.Stack() or 1
            if stackSize < 1 then stackSize = 1 end
            local tribute = it.Tribute and it.Tribute() or 0
            local lore = it.Lore and it.Lore() or false
            local quest = it.Quest and it.Quest() or false
            local collectible = it.Collectible and it.Collectible() or false
            local heirloom = it.Heirloom and it.Heirloom() or false
            local attuneable = it.Attuneable and it.Attuneable() or false
            local wornSlots = env.getWornSlotsStringFromTLO and env.getWornSlotsStringFromTLO(it) or ""
            local augSlots = env.getAugSlotsCountFromTLO and env.getAugSlotsCountFromTLO(it) or 0
            local clicky = 0
            if it.Clicky and it.Clicky.Spell then
                local spellId = it.Clicky.Spell.ID
                if type(spellId) == "function" then spellId = spellId() end
                if spellId and type(spellId) == "number" and spellId > 0 then
                    local effType = it.Clicky.EffectType
                    if type(effType) == "function" then effType = effType() end
                    local isClicky = false
                    if type(effType) == "string" then
                        isClicky = effType:find("Click", 1, true) ~= nil
                    elseif type(effType) == "number" then
                        isClicky = (effType == 1 or effType == 4 or effType == 5)
                    end
                    if isClicky then clicky = spellId end
                end
            end
            local nodrop = false
            if it.NoDrop then nodrop = (type(it.NoDrop) == "function" and it.NoDrop()) or (it.NoDrop == true) end
            local itemData = { slot = i, id = itId, name = name, type = itemType, value = value, totalValue = value * stackSize,
                stackSize = stackSize, tribute = tribute, lore = lore, quest = quest, collectible = collectible,
                heirloom = heirloom, attuneable = attuneable, augSlots = augSlots, clicky = clicky, wornSlots = wornSlots, nodrop = nodrop }
            local shouldLoot, reason = env.rules.shouldItemBeLooted(itemData, lootCache)
            if lore then
                local loreCache = env.perfCache.loreHaveCache
                if loreCache and loreCache[name] then
                    reason = "LoreDup"
                    shouldLoot = false
                else
                    local findIt = mq.TLO.FindItem and mq.TLO.FindItem("=" .. name)
                    local findId = findIt and findIt.ID and findIt.ID()
                    if findIt and findId and type(findId) == "number" and findId > 0 then
                        if not loreCache then env.perfCache.loreHaveCache = {}; loreCache = env.perfCache.loreHaveCache end
                        loreCache[name] = true
                        reason = "LoreDup"
                        shouldLoot = false
                    end
                end
            end
            itemData.willLoot = shouldLoot
            itemData.lootReason = reason
            table.insert(lootItems, itemData)
        end
    end
    env.invalidateSortCache("loot")
end

function M.maybeScanLootItems(lootOpen)
    if not lootOpen then
        env.scanState.lastScanState.lootOpen = false
        for i = #env.lootItems, 1, -1 do env.lootItems[i] = nil end
        return
    end
    if #env.lootItems == 0 or env.scanState.lastScanState.lootOpen ~= lootOpen then
        M.scanLootItems()
        env.scanState.lastScanState.lootOpen = lootOpen
    end
end

return M
