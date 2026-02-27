--[[
    ItemUI - Sell Batch Service (Task 7.4)
    Native Lua batch sell state machine. Replaces sell.mac when sellMode=lua.
    Non-blocking: one step per frame, no mq.delay() in loop.
    Progress and failures written to sellMacState for existing UI.
--]]

local mq = require('mq')
local constants = require('itemui.constants')

local M = {}
local deps

-- Batch state held in module (nil when idle)
local batchState = nil

-- wait_sold: time-based cap and settle (Task 7.4 fix — no 180-frame ~5s freeze)
local WAIT_SOLD_SETTLE_MS = 150   -- minimum time in wait_sold before accepting completion
local WAIT_SOLD_TIMEOUT_MS = 1500 -- max time in wait_sold before retry/fail (was 180 frames ~5.94s)
local WAIT_SOLD_FRAME_CAP = 120   -- fallback frame cap (~4s at 33ms/frame) if time check were wrong

-- Resolve sell log directory (same as macro_bridge)
local function getSellLogPath()
    if deps and deps.perfCache and deps.perfCache.sellLogPath and deps.perfCache.sellLogPath ~= "" then
        return deps.perfCache.sellLogPath
    end
    local p = mq.TLO and mq.TLO.MacroQuest and mq.TLO.MacroQuest.Path and mq.TLO.MacroQuest.Path()
    if p and p ~= "" then
        return (p:gsub("/", "\\")) .. "\\Macros\\logs\\item_management"
    end
    return nil
end

-- Append one line to sell_history.log when enableSellHistoryLog is on. No mkdir — folder must already exist.
-- Format: [Date Time12] SELL: ItemName (Value: N, Reason: reason). Only called when getSellHistoryLogEnabled().
local function logSellHistory(itemName, itemValue, reason)
    local basePath = getSellLogPath()
    if not basePath then return end
    local logPath = basePath .. "\\sell_history.log"
    local dateStr = os.date("%m/%d/%Y")
    local timeStr = os.date("%I:%M:%S %p")
    local line = string.format("[%s %s] SELL: %s (Value: %s, Reason: %s)\n", dateStr, timeStr, itemName or "", tostring(itemValue or 0), reason or "")
    local f = io.open(logPath, "a")
    if f then
        f:write(line)
        f:close()
    end
    -- If open fails (e.g. folder missing), skip silently — no mkdir, no console spam.
end

-- Load sell_value.ini timing (sellWaitTicks, sellRetries, sellMaxTimeoutSeconds)
local function loadSellTiming()
    local config = deps and deps.config
    if not config or not config.readINIValue then
        return { sellWaitTicks = 18, sellRetries = 4, sellMaxTimeoutSeconds = 60 }
    end
    local ticks = tonumber(config.readINIValue("sell_value.ini", "Settings", "sellWaitTicks", "18")) or 18
    local retries = tonumber(config.readINIValue("sell_value.ini", "Settings", "sellRetries", "4")) or 4
    local timeout = tonumber(config.readINIValue("sell_value.ini", "Settings", "sellMaxTimeoutSeconds", "60")) or 60
    return { sellWaitTicks = ticks, sellRetries = retries, sellMaxTimeoutSeconds = timeout }
end

-- Optional: write each sold item to sell_history.log (sell_flags.ini enableSellHistoryLog=TRUE). Default FALSE to avoid I/O delays.
local function getSellHistoryLogEnabled()
    local config = deps and deps.config
    if not config or not config.readINIValue then return false end
    local v = (config.readINIValue("sell_flags.ini", "Settings", "enableSellHistoryLog", "FALSE") or ""):upper()
    return (v == "TRUE" or v == "1")
end

-- Issue 5: optional console log per sold item (sell_flags.ini sellVerboseLog=TRUE)
local function getSellVerboseLog()
    local config = deps and deps.config
    if not config or not config.readINIValue then return false end
    local v = (config.readINIValue("sell_flags.ini", "Settings", "sellVerboseLog", "FALSE") or ""):upper()
    return (v == "TRUE" or v == "1")
end

function M.init(d)
    deps = d
end

--- Return true if a Lua sell batch is currently running.
function M.isRunning()
    return batchState ~= nil
end

--- Start a batch sell. Call with list of items that have willSell == true (bag order).
--- Does not write sell_cache.ini or start macro. Returns false if already running or merchant closed.
function M.startBatch(itemsToSell)
    if batchState ~= nil then
        if deps.setStatusMessage then deps.setStatusMessage("Sell already in progress.") end
        return false
    end
    if not deps.isMerchantWindowOpen() then
        if deps.setStatusMessage then deps.setStatusMessage("Open a merchant to sell.") end
        return false
    end
    if not itemsToSell or #itemsToSell == 0 then
        if deps.setStatusMessage then deps.setStatusMessage("No items to sell.") end
        return false
    end

    local queue = {}
    for _, it in ipairs(itemsToSell) do
        if it.willSell and it.bag and it.slot then
            queue[#queue + 1] = {
                bag = it.bag,
                slot = it.slot,
                name = it.name or "",
                id = it.id,
                value = it.value or 0,
                totalValue = it.totalValue or it.value or 0,
                stackSize = (it.stackSize and it.stackSize > 0) and it.stackSize or 1,
                sellReason = it.sellReason or "Sell",
            }
        end
    end
    if #queue == 0 then
        if deps.setStatusMessage then deps.setStatusMessage("No items to sell.") end
        return false
    end
    table.sort(queue, function(a, b) if a.bag ~= b.bag then return a.bag < b.bag end return a.slot < b.slot end)

    local timing = loadSellTiming()
    local T = constants.TIMING
    batchState = {
        queue = queue,
        queueIndex = 1,
        totalToSell = #queue,
        soldCount = 0,
        failedCount = 0,
        failedItems = {},
        current = nil,
        startedAt = mq.gettime and mq.gettime() or 0,
        luaRunning = true,
        timing = timing,
    }
    local sellMacState = deps.sellMacState
    if sellMacState then
        sellMacState.luaRunning = true
        sellMacState.total = batchState.totalToSell
        sellMacState.current = 0
        sellMacState.remaining = batchState.totalToSell
        sellMacState.smoothedFrac = 0
        sellMacState.failedItems = {}
        sellMacState.failedCount = 0
    end
    if deps.setStatusMessage then deps.setStatusMessage("Selling...") end
    return true
end

--- Advance batch state machine one step. Call every frame from main_loop phase 7.
function M.advance(now)
    now = now or (mq.gettime and mq.gettime() or 0)
    if batchState == nil then return end

    local sellMacState = deps.sellMacState
    local timing = batchState.timing
    local WAIT_SELECTED_SETTLE_MS = 33  -- single-frame minimum before accepting label match (Issue 4)
    local sellRetries = (timing.sellRetries or 4)
    local timeoutSec = (timing.sellMaxTimeoutSeconds or 60) * 1000

    -- Merchant closed: abort batch
    if not deps.isMerchantWindowOpen() then
        batchState = nil
        if sellMacState then
            sellMacState.luaRunning = false
            sellMacState.pendingScan = true
            sellMacState.finishedAt = now
        end
        if deps.setStatusMessage then deps.setStatusMessage("Merchant closed; sell cancelled.") end
        if deps.scanState then deps.scanState.inventoryBagsDirty = true end
        return
    end

    -- Ensure current item is loaded
    if batchState.current == nil then
        if batchState.queueIndex > batchState.totalToSell then
            -- Done
            batchState.luaRunning = false
            if sellMacState then
                sellMacState.luaRunning = false
                sellMacState.current = batchState.soldCount
                sellMacState.remaining = 0
                sellMacState.smoothedFrac = 1
                sellMacState.failedItems = batchState.failedItems
                sellMacState.failedCount = batchState.failedCount
                sellMacState.pendingScan = true
                sellMacState.finishedAt = now
                sellMacState.showFailedUntil = (batchState.failedCount and batchState.failedCount > 0) and (now + (deps.C and deps.C.SELL_FAILED_DISPLAY_MS or 15000)) or 0
            end
            if deps.setStatusMessage then
                if batchState.failedCount and batchState.failedCount > 0 then
                    deps.setStatusMessage(string.format("Sell complete. %d sold, %d failed.", batchState.soldCount, batchState.failedCount))
                else
                    deps.setStatusMessage("Sell complete. Inventory refreshed.")
                end
            end
            if deps.scanState then deps.scanState.inventoryBagsDirty = true end
            batchState = nil
            return
        end
        local entry = batchState.queue[batchState.queueIndex]
        if not entry then
            batchState.current = nil
            batchState.queueIndex = batchState.queueIndex + 1
            return
        end
        batchState.current = {
            phase = "wait_selected",
            item = { name = entry.name, bag = entry.bag, slot = entry.slot, id = entry.id, totalValue = entry.totalValue, stackSize = entry.stackSize, sellReason = entry.sellReason },
            enteredAt = now,
            pollCount = 0,
            attempt = 1,
            itemStartedAt = now,
        }
        mq.cmdf('/itemnotify in pack%d %d leftmouseup', entry.bag, entry.slot)
    end

    local cur = batchState.current
    local itemName, bagNum, slotNum = cur.item.name, cur.item.bag, cur.item.slot
    local Me = mq.TLO and mq.TLO.Me
    local pack = Me and Me.Inventory and Me.Inventory("pack" .. bagNum)

    -- Per-item timeout
    if (now - cur.itemStartedAt) >= timeoutSec then
        batchState.failedCount = batchState.failedCount + 1
        batchState.failedItems[#batchState.failedItems + 1] = itemName
        batchState.current = nil
        batchState.queueIndex = batchState.queueIndex + 1
        if sellMacState then
            sellMacState.current = batchState.soldCount
            sellMacState.remaining = batchState.totalToSell - batchState.soldCount - batchState.failedCount
            sellMacState.smoothedFrac = (batchState.soldCount + batchState.failedCount) / batchState.totalToSell
        end
        return
    end

    if cur.phase == "wait_selected" then
        local wnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("MerchantWnd/MW_SelectedItemLabel")
        local sel = (wnd and wnd.Text and wnd.Text()) or ""
        local elapsed = now - cur.enteredAt
        if sel == itemName and elapsed >= WAIT_SELECTED_SETTLE_MS then
            mq.cmd('/nomodkey /shiftkey /notify MerchantWnd MW_Sell_Button leftmouseup')
            cur.phase = "wait_sold"
            cur.enteredAt = now
            cur.pollCount = 0
            return
        end
        cur.pollCount = (cur.pollCount or 0) + 1
        if cur.pollCount >= 10 then
            if cur.attempt <= sellRetries then
                cur.attempt = cur.attempt + 1
                cur.phase = "wait_selected"
                cur.enteredAt = now
                cur.pollCount = 0
                mq.cmdf('/itemnotify in pack%d %d leftmouseup', bagNum, slotNum)
            else
                batchState.failedCount = batchState.failedCount + 1
                batchState.failedItems[#batchState.failedItems + 1] = itemName
                batchState.current = nil
                batchState.queueIndex = batchState.queueIndex + 1
                if sellMacState then
                    sellMacState.current = batchState.soldCount
                    sellMacState.remaining = batchState.totalToSell - batchState.soldCount - batchState.failedCount
                    sellMacState.smoothedFrac = (batchState.soldCount + batchState.failedCount) / batchState.totalToSell
                end
            end
        end
        return
    end

    if cur.phase == "wait_sold" then
        local elapsed = now - cur.enteredAt
        local slotItem = pack and pack.Item and pack.Item(slotNum)
        local slotId = (slotItem and slotItem.ID and slotItem.ID()) or 0
        local itemGone = (not slotItem or not slotItem.ID or slotId == 0)
        -- After settle: itemGone alone is sufficient (label may not clear on some clients). Task 7.4.
        local settled = elapsed >= WAIT_SOLD_SETTLE_MS
        local complete = settled and itemGone
        if complete then
            local io = deps.itemOps
            if io and io.removeItemFromInventoryBySlot then io.removeItemFromInventoryBySlot(bagNum, slotNum) end
            if io and io.removeItemFromSellItemsBySlot then io.removeItemFromSellItemsBySlot(bagNum, slotNum) end
            if getSellHistoryLogEnabled() then logSellHistory(itemName, cur.item.totalValue, cur.item.sellReason) end
            if getSellVerboseLog() then
                print(string.format("\ag[ItemUI]\ax [LUA SELL] %s x%d (Value: %s) - %s", itemName or "", cur.item.stackSize or 1, tostring(cur.item.totalValue or 0), cur.item.sellReason or "Sold"))
            end
            batchState.soldCount = batchState.soldCount + 1
            batchState.current = nil
            batchState.queueIndex = batchState.queueIndex + 1
            if sellMacState then
                sellMacState.current = batchState.soldCount
                sellMacState.remaining = batchState.totalToSell - batchState.soldCount
                sellMacState.smoothedFrac = batchState.soldCount / batchState.totalToSell
            end
            return
        end
        -- Time-based timeout (was 180 frames ~5.94s). Fallback frame cap as safeguard.
        cur.pollCount = (cur.pollCount or 0) + 1
        local timedOut = elapsed >= WAIT_SOLD_TIMEOUT_MS or cur.pollCount >= WAIT_SOLD_FRAME_CAP
        if timedOut then
            if cur.attempt <= sellRetries then
                cur.attempt = cur.attempt + 1
                cur.phase = "wait_selected"
                cur.enteredAt = now
                cur.pollCount = 0
                mq.cmdf('/itemnotify in pack%d %d leftmouseup', bagNum, slotNum)
            else
                batchState.failedCount = batchState.failedCount + 1
                batchState.failedItems[#batchState.failedItems + 1] = itemName
                batchState.current = nil
                batchState.queueIndex = batchState.queueIndex + 1
                if sellMacState then
                    sellMacState.current = batchState.soldCount
                    sellMacState.remaining = batchState.totalToSell - batchState.soldCount - batchState.failedCount
                    sellMacState.smoothedFrac = (batchState.soldCount + batchState.failedCount) / batchState.totalToSell
                end
            end
        end
        return
    end
end

return M
