--[[
    Macro Bridge Service - Phase 5: Macro Integration Improvement (Task 4.4: Decouple)
    
    Centralizes communication between ItemUI and macros (sell.mac, loot.mac).
    IPC protocol (versioned): [Protocol] Version=1 in all IPC INI files; readers treat
    missing version as 1; if Version > IPC_PROTOCOL_VERSION return safe defaults.
    
    Features:
    - Throttled file polling (500ms instead of every frame)
    - Event-based notifications (publish/subscribe)
    - Progress tracking with statistics
    - Failed item tracking
    - Public API: isSellMacroRunning(), isLootMacroRunning(), getSellFailed(), pollLootProgress(), getLootSession()
    
    Usage:
        local macroBridge = require('itemui.services.macro_bridge')
        
        -- Initialize
        macroBridge.init({
            sellLogPath = "path/to/logs",
            pollInterval = 500  -- ms
        })
        
        -- Subscribe to events
        macroBridge.subscribe('sell:progress', function(data)
            print('Sell progress:', data.current, '/', data.total)
        end)
        
        macroBridge.subscribe('sell:complete', function(data)
            print('Sell complete! Failed:', data.failedCount)
        end)
        
        -- Poll in main loop
        macroBridge.poll()
        
        -- Write progress (from Auto Sell button)
        macroBridge.writeSellProgress(totalItems, 0)
--]]

local mq = require('mq')
local constants = require('itemui.constants')
local item_name = require('itemui.utils.item_name')
local coopuiPlugin = require('itemui.utils.coopui_plugin')

local IPC_PROTOCOL_VERSION = (constants.TIMING and constants.TIMING.IPC_PROTOCOL_VERSION) or 1

local MacroBridge = {
    -- Configuration
    config = {
        sellLogPath = nil,
        getLootConfigFile = nil,
        pollInterval = 500,  -- ms (reduced from every frame)
        debug = false
    },
    
    -- State tracking
    state = {
        lastPollTime = 0,
        lastLootProgressPollTime = 0,
        sell = {
            running = false,
            lastRunning = false,
            progress = { total = 0, current = 0, remaining = 0 },
            smoothedFrac = 0,
            failedItems = {},
            failedCount = 0,
            startTime = 0,
            endTime = 0,
            lastProgressFileReadTime = 0  -- for file-based fallback when macro name not detected
        },
        loot = {
            running = false,
            lastRunning = false,
            progress = { corpsesLooted = 0, totalCorpses = 0, currentCorpse = "" },
            startTime = 0,
            endTime = 0
        }
    },
    
    -- Event subscribers
    subscribers = {},
    
    -- Statistics
    stats = {
        sell = {
            totalRuns = 0,
            totalItemsSold = 0,
            totalItemsFailed = 0,
            avgItemsPerRun = 0,
            avgDurationMs = 0,
            lastRunDurationMs = 0
        },
        loot = {
            totalRuns = 0,
            lastRunDurationMs = 0,
            avgDurationMs = 0
        }
    }
}

-- Debug logging
local function log(msg)
    if MacroBridge.config.debug then
        print(string.format("[MacroBridge] %s", msg))
    end
end

-- Resolve sell log path at use-time when nil (so bridge works if init was called before MacroQuest.Path was set)
local function getSellLogPath()
    if MacroBridge.config.sellLogPath and MacroBridge.config.sellLogPath ~= "" then
        return MacroBridge.config.sellLogPath
    end
    local p = mq.TLO and mq.TLO.MacroQuest and mq.TLO.MacroQuest.Path and mq.TLO.MacroQuest.Path()
    if p and p ~= "" then
        MacroBridge.config.sellLogPath = (p:gsub("/", "\\")) .. "\\Macros\\logs\\item_management"
        return MacroBridge.config.sellLogPath
    end
    return nil
end

-- Initialize the service. Clears subscribers to prevent accumulation on script reload.
function MacroBridge.init(config)
    MacroBridge.config.sellLogPath = config.sellLogPath
    MacroBridge.config.getLootConfigFile = config.getLootConfigFile
    MacroBridge.config.pollInterval = config.pollInterval or 500
    MacroBridge.config.debug = config.debug or false
    MacroBridge.clearSubscribers()
    log("Initialized with pollInterval=" .. MacroBridge.config.pollInterval .. "ms")
end

-- Enable/disable debug logging
function MacroBridge.setDebug(enabled)
    MacroBridge.config.debug = enabled
end

-- Subscribe to events
-- Events: 'sell:started', 'sell:progress', 'sell:complete', 'loot:started', 'loot:complete'
function MacroBridge.subscribe(event, callback)
    if not MacroBridge.subscribers[event] then
        MacroBridge.subscribers[event] = {}
    end
    table.insert(MacroBridge.subscribers[event], callback)
    log("Subscribed to event: " .. event)
end

-- Unsubscribe a specific callback from an event.
function MacroBridge.unsubscribe(event, callback)
    local list = MacroBridge.subscribers[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == callback then
            table.remove(list, i)
        end
    end
end

-- Clear all subscribers (called on init to prevent accumulation on script reload).
function MacroBridge.clearSubscribers()
    MacroBridge.subscribers = {}
end

-- Emit event to all subscribers. Erroring callbacks are removed from the list.
local function emit(event, data)
    log("Emit event: " .. event)
    local list = MacroBridge.subscribers[event]
    if not list then return end
    local toRemove = nil
    for i, callback in ipairs(list) do
        local ok, err = pcall(callback, data)
        if not ok then
            print(string.format("[MacroBridge] Error in %s callback: %s", event, tostring(err)))
            local diag = require('itemui.core.diagnostics')
            diag.recordError("MacroBridge", "Callback error: " .. tostring(event), err)
            if not toRemove then toRemove = {} end
            toRemove[#toRemove + 1] = i
        end
    end
    if toRemove then
        for i = #toRemove, 1, -1 do
            table.remove(list, toRemove[i])
        end
    end
end

-- Check if macro is running (Name() may return "sell", "sell.mac", or path like "Macros/sell.mac")
local function isMacroRunning(macroName)
    -- Check if Running is a valid function before calling
    local macro = mq.TLO and mq.TLO.Macro
    if not macro then return false end
    -- Check if Name is a valid function before calling
    
    local running = macro.Running and macro.Running()
    if not running then return false end
    
    local name = macro.Name and macro.Name()
    if not name or name == "" then return false end
    
    local base = name:match("([^/\\]+)$") or name
    local mn = base:lower()
    return (mn == macroName or mn == macroName .. ".mac")
end

-- Read sell progress from INI file (safe: TLO.Ini can be nil during zone/load). Versioned: if Protocol.Version > IPC_PROTOCOL_VERSION return nil.
local function readSellProgress()
    local basePath = getSellLogPath()
    if not basePath then return nil end
    local config = require('itemui.config')
    local progPath = basePath .. "\\sell_progress.ini"
    local verStr = config.safeIniValueByPath(progPath, "Protocol", "Version", "1")
    local ver = tonumber(verStr) or 1
    if ver > IPC_PROTOCOL_VERSION then return nil end
    local totalStr = config.safeIniValueByPath(progPath, "Progress", "total", "0")
    local currentStr = config.safeIniValueByPath(progPath, "Progress", "current", "0")
    local remainingStr = config.safeIniValueByPath(progPath, "Progress", "remaining", "0")
    local total = tonumber(totalStr) or 0
    local current = tonumber(currentStr) or 0
    local remaining = tonumber(remainingStr) or 0
    return { total = total, current = current, remaining = remaining }
end

-- Read failed items from sell_failed.ini (safe INI read). Keys are item1, item2, ... (match sell.mac). Versioned: if Protocol.Version > IPC_PROTOCOL_VERSION return {}, 0.
local function readFailedItems()
    local basePath = getSellLogPath()
    if not basePath then return {}, 0 end
    local config = require('itemui.config')
    local failedPath = basePath .. "\\sell_failed.ini"
    local verStr = config.safeIniValueByPath(failedPath, "Protocol", "Version", "1")
    local ver = tonumber(verStr) or 1
    if ver > IPC_PROTOCOL_VERSION then return {}, 0 end
    local countStr = config.safeIniValueByPath(failedPath, "Failed", "count", "0")
    local count = tonumber(countStr) or 0
    local failedItems = {}
    if count > 0 then
        for i = 1, count do
            local itemName = config.safeIniValueByPath(failedPath, "Failed", "item" .. i, "")
            if itemName and itemName ~= "" then
                table.insert(failedItems, itemName)
            end
        end
    end
    return failedItems, count
end

-- Write sell progress to INI file (includes [Protocol] Version=1 for versioned IPC)
function MacroBridge.writeSellProgress(total, current)
    local basePath = getSellLogPath()
    if not basePath then return end
    local progPath = basePath .. "\\sell_progress.ini"
    local remaining = math.max(0, total - current)
    mq.cmdf('/ini "%s" Protocol Version 1', progPath)
    mq.cmdf('/ini "%s" Progress total %d', progPath, total)
    mq.cmdf('/ini "%s" Progress current %d', progPath, current)
    mq.cmdf('/ini "%s" Progress remaining %d', progPath, remaining)
    log(string.format("Wrote progress: %d/%d (remaining: %d)", current, total, remaining))
end

-- Get smoothed progress fraction (for progress bar animation)
function MacroBridge.getSmoothedProgress()
    return MacroBridge.state.sell.smoothedFrac
end

-- Get current sell progress data (read from INI when sell macro running so progress bar gets fresh data every frame).
-- File-based fallback: when live macro check fails, read INI periodically; if total>0 and current<total, treat as running so progress bar shows.
function MacroBridge.getSellProgress()
    local liveRunning = isMacroRunning("sell")
    if liveRunning then
        MacroBridge.state.sell.running = true
        local progress = readSellProgress()
        if progress then
            MacroBridge.state.sell.progress = progress
            local targetFrac = (progress.total > 0) and math.min(1, math.max(0, progress.current / progress.total)) or 0
            local lerpSpeed = 0.35
            MacroBridge.state.sell.smoothedFrac = MacroBridge.state.sell.smoothedFrac + (targetFrac - MacroBridge.state.sell.smoothedFrac) * lerpSpeed
            MacroBridge.state.sell.smoothedFrac = math.min(1, math.max(0, MacroBridge.state.sell.smoothedFrac))
        end
    else
        -- Fallback: show bar from file when macro name not detected (e.g. different MQ2 or invocation)
        local t = os.clock() * 1000
        if (t - (MacroBridge.state.sell.lastProgressFileReadTime or 0)) >= 150 then
            MacroBridge.state.sell.lastProgressFileReadTime = t
            local progress = readSellProgress()
            if progress and progress.total > 0 then
                MacroBridge.state.sell.progress = progress
                if progress.current < progress.total then
                    MacroBridge.state.sell.running = true
                    local targetFrac = math.min(1, math.max(0, progress.current / progress.total))
                    local lerpSpeed = 0.35
                    MacroBridge.state.sell.smoothedFrac = MacroBridge.state.sell.smoothedFrac + (targetFrac - MacroBridge.state.sell.smoothedFrac) * lerpSpeed
                    MacroBridge.state.sell.smoothedFrac = math.min(1, math.max(0, MacroBridge.state.sell.smoothedFrac))
                else
                    MacroBridge.state.sell.running = false
                end
            end
        end
    end
    return {
        running = MacroBridge.state.sell.running,
        total = MacroBridge.state.sell.progress.total,
        current = MacroBridge.state.sell.progress.current,
        remaining = MacroBridge.state.sell.progress.remaining,
        smoothedFrac = MacroBridge.state.sell.smoothedFrac,
        failedItems = MacroBridge.state.sell.failedItems,
        failedCount = MacroBridge.state.sell.failedCount
    }
end

-- Clear sell state so progress bar and consumers don't see stale running/smoothedFrac (Issue 1)
function MacroBridge.clearSellState()
    MacroBridge.state.sell.running = false
    MacroBridge.state.sell.smoothedFrac = 0
    MacroBridge.state.sell.progress = { total = 0, current = 0, remaining = 0 }
end

-- Get loot macro state
function MacroBridge.getLootState()
    return {
        running = MacroBridge.state.loot.running
    }
end

-- Public API (Task 4.4): macro running checks
function MacroBridge.isSellMacroRunning()
    return isMacroRunning("sell")
end

function MacroBridge.isLootMacroRunning()
    return isMacroRunning("loot")
end

-- Public API: get failed items (read from INI when sell macro not running so phase 4 gets fresh data; cache when running)
function MacroBridge.getSellFailed()
    if isMacroRunning("sell") then
        return MacroBridge.state.sell.failedItems, MacroBridge.state.sell.failedCount
    end
    local failedItems, failedCount = readFailedItems()
    MacroBridge.state.sell.failedItems = failedItems
    MacroBridge.state.sell.failedCount = failedCount
    return failedItems, failedCount
end

-- Public API: throttled read of loot_progress.ini; returns corpsesLooted, totalCorpses, currentCorpse
function MacroBridge.pollLootProgress()
    local getLootConfigFile = MacroBridge.config.getLootConfigFile
    if not getLootConfigFile then
        local c = require('itemui.config')
        getLootConfigFile = c.getLootConfigFile
    end
    if not getLootConfigFile then
        local p = MacroBridge.state.loot.progress
        return p.corpsesLooted, p.totalCorpses, p.currentCorpse
    end
    local now = os.clock() * 1000
    local interval = MacroBridge.config.pollInterval
    if (now - MacroBridge.state.lastLootProgressPollTime) >= interval then
        MacroBridge.state.lastLootProgressPollTime = now
        local progPath = getLootConfigFile("loot_progress.ini")
        if progPath and progPath ~= "" then
            local config = require('itemui.config')
            if config.readLootProgressSection then
                local corpses, total, current = config.readLootProgressSection(progPath)
                MacroBridge.state.loot.progress = {
                    corpsesLooted = corpses or 0,
                    totalCorpses = total or 0,
                    currentCorpse = current or ""
                }
            end
        end
    end
    local p = MacroBridge.state.loot.progress
    return p.corpsesLooted, p.totalCorpses, p.currentCorpse
end

-- Public API: read loot_session.ini (no throttle; caller enforces LOOT_SESSION_READ_DELAY_MS). Returns table: count, items (array of {name, value, tribute}), totalValue, tributeValue, bestItemName, bestItemValue. Versioned: if Protocol.Version > supported return empty.
-- When MQ2CoOptUI plugin is loaded, uses ini.readSection for one read per section (fast); otherwise falls back to per-key safeIniValueByPath.
function MacroBridge.getLootSession()
    local getLootConfigFile = MacroBridge.config.getLootConfigFile
    if not getLootConfigFile then
        local c = require('itemui.config')
        getLootConfigFile = c.getLootConfigFile
    end
    if not getLootConfigFile then return { count = 0, items = {}, totalValue = 0, tributeValue = 0, bestItemName = "", bestItemValue = 0 } end
    local sessionPath = getLootConfigFile("loot_session.ini")
    if not sessionPath or sessionPath == "" then return { count = 0, items = {}, totalValue = 0, tributeValue = 0, bestItemName = "", bestItemValue = 0 } end
    local config = require('itemui.config')
    local empty = { count = 0, items = {}, totalValue = 0, tributeValue = 0, bestItemName = "", bestItemValue = 0 }
    local ini = MacroBridge.getPluginIni()
    if ini and ini.readSection then
        local protocol = ini.readSection(sessionPath, "Protocol")
        local verStr = (protocol and protocol.Version) or "1"
        local ver = tonumber(verStr) or 1
        if ver > IPC_PROTOCOL_VERSION then return empty end
        local itemsSec = ini.readSection(sessionPath, "Items")
        local countStr = (itemsSec and itemsSec.count) or "0"
        local count = tonumber(countStr) or 0
        local items = {}
        if count > 0 then
            local valuesSec = ini.readSection(sessionPath, "ItemValues")
            local tributesSec = ini.readSection(sessionPath, "ItemTributes")
            for i = 1, count do
                local key = tostring(i)
                local rawName = (itemsSec and itemsSec[key]) or ""
                local name = item_name.normalizeItemName(rawName)
                if name ~= "" then
                    local valStr = (valuesSec and valuesSec[key]) or "0"
                    local tribStr = (tributesSec and tributesSec[key]) or "0"
                    table.insert(items, {
                        name = name,
                        value = tonumber(valStr) or 0,
                        tribute = tonumber(tribStr) or 0
                    })
                end
            end
        end
        local summary = ini.readSection(sessionPath, "Summary")
        local sv = (summary and summary.totalValue) or "0"
        local tv = (summary and summary.tributeValue) or "0"
        local rawBest = (summary and summary.bestItemName) or ""
        local bestNorm = item_name.normalizeItemName(rawBest)
        return {
            count = count,
            items = items,
            totalValue = tonumber(sv) or 0,
            tributeValue = tonumber(tv) or 0,
            bestItemName = (bestNorm ~= "" and bestNorm) or rawBest,
            bestItemValue = tonumber((summary and summary.bestItemValue) or "0") or 0
        }
    end
    -- Fallback: no plugin or no readSection (per-key reads)
    local verStr = config.safeIniValueByPath(sessionPath, "Protocol", "Version", "1")
    local ver = tonumber(verStr) or 1
    if ver > IPC_PROTOCOL_VERSION then return empty end
    local countStr = config.safeIniValueByPath(sessionPath, "Items", "count", "0")
    local count = tonumber(countStr) or 0
    local items = {}
    if count > 0 then
        for i = 1, count do
            local rawName = config.safeIniValueByPath(sessionPath, "Items", tostring(i), "")
            local name = item_name.normalizeItemName(rawName)
            if name ~= "" then
                local valStr = config.safeIniValueByPath(sessionPath, "ItemValues", tostring(i), "0")
                local tribStr = config.safeIniValueByPath(sessionPath, "ItemTributes", tostring(i), "0")
                table.insert(items, {
                    name = name,
                    value = tonumber(valStr) or 0,
                    tribute = tonumber(tribStr) or 0
                })
            end
        end
    end
    local sv = config.safeIniValueByPath(sessionPath, "Summary", "totalValue", "0")
    local tv = config.safeIniValueByPath(sessionPath, "Summary", "tributeValue", "0")
    local rawBest = config.safeIniValueByPath(sessionPath, "Summary", "bestItemName", "") or ""
    local bestNorm = item_name.normalizeItemName(rawBest)
    return {
        count = count,
        items = items,
        totalValue = tonumber(sv) or 0,
        tributeValue = tonumber(tv) or 0,
        bestItemName = (bestNorm ~= "" and bestNorm) or rawBest,
        bestItemValue = tonumber(config.safeIniValueByPath(sessionPath, "Summary", "bestItemValue", "0")) or 0
    }
end

-- IPC event streaming (Phase 9): delegates to shared plugin loader.
local function getIPC() return coopuiPlugin.getIPC() end

--- Return true when the CoOptUI plugin IPC channel is loaded and available.
--- Used by phase5_lootMacro to skip INI-based progress polling when IPC is driving the bar.
function MacroBridge.isIPCAvailable()
    return getIPC() ~= nil
end

--- Return plugin ini table (readSection, read) when MQ2CoOptUI is loaded; nil otherwise. Used for bulk INI reads to avoid per-key TLO cost.
function MacroBridge.getPluginIni()
    return coopuiPlugin.getINI()
end

-- Drain high-frequency IPC channels at frame rate (called every tick from main_loop)
-- Process loot_start before loot_item so the run-start clear doesn't wipe items we just added.
function MacroBridge.drainIPCFast(uiState, getSellStatusForItem, LOOT_HISTORY_MAX)
    local ipc = getIPC()
    if not ipc then return end

    local starts = ipc.receiveAll("loot_start")
    if starts and #starts > 0 then
        uiState.lootUIOpen = true
        uiState.lootRunFinished = false
        uiState.lootRunLootedItems = {}
        uiState.lootRunLootedList = {}
        uiState.lootRunTotalValue = 0
        uiState.lootRunTributeValue = 0
        uiState.lootRunBestItemName = ""
        uiState.lootRunBestItemValue = 0
        uiState.lootProgressTarget = 0
        uiState.lootRunCorpsesLooted = 0
        uiState.lootRunTotalCorpses = 0
        uiState.lootRunCurrentCorpse = ""
    end

    local realTime = (uiState.enableRealTimeLoot == true)
    local items = ipc.receiveAll("loot_item")
    if items and #items > 0 and realTime then
        if not uiState.lootRunLootedItems then uiState.lootRunLootedItems = {} end
        if not uiState.lootRunLootedList then uiState.lootRunLootedList = {} end
        if uiState.enableLootHistory and not uiState.lootHistory then uiState.lootHistory = {} end
        for _, msg in ipairs(items) do
            local rawName, valStr, tribStr = msg:match("^([^|]+)|([^|]+)|(.+)$")
            local name = item_name.normalizeItemName(rawName)
            if name ~= "" then
                local value = tonumber(valStr) or 0
                local tribute = tonumber(tribStr) or 0
                local statusText, willSell = "—", false
                if getSellStatusForItem then
                    -- Pass value/tribute so sell rules (minSellValue, HighValue) evaluate correctly.
                    statusText, willSell = getSellStatusForItem({ name = name, value = value, tribute = tribute })
                    if statusText == "" then statusText = "—" end
                end
                table.insert(uiState.lootRunLootedList, name)
                table.insert(uiState.lootRunLootedItems, {
                    name = name, value = value, tribute = tribute,
                    statusText = statusText, willSell = willSell
                })
                if uiState.enableLootHistory then
                    table.insert(uiState.lootHistory, {
                        name = name, value = value,
                        statusText = statusText, willSell = willSell
                    })
                    while #uiState.lootHistory > LOOT_HISTORY_MAX do
                        table.remove(uiState.lootHistory, 1)
                    end
                end
                uiState.lootRunTotalValue = (uiState.lootRunTotalValue or 0) + value
                uiState.lootRunTributeValue = (uiState.lootRunTributeValue or 0) + tribute
                if value > (uiState.lootRunBestItemValue or 0) then
                    uiState.lootRunBestItemValue = value
                    uiState.lootRunBestItemName = name
                end
            end
        end
    end

    local skips = ipc.receiveAll("loot_skip")
    if skips and #skips > 0 and realTime and (uiState.enableSkipHistory == true) then
        if not uiState.skipHistory then uiState.skipHistory = {} end
        for _, msg in ipairs(skips) do
            local rawName, reason = msg:match("^([^|]+)|(.+)$")
            local name = item_name.normalizeItemName(rawName)
            if name ~= "" then
                table.insert(uiState.skipHistory, {
                    name = name, reason = reason or ""
                })
                while #uiState.skipHistory > LOOT_HISTORY_MAX do
                    table.remove(uiState.skipHistory, 1)
                end
            end
        end
    end

    local progress = ipc.receiveAll("loot_progress")
    if progress and #progress > 0 then
        local last = progress[#progress]
        local looted, total, corpse = last:match("^([^|]+)|([^|]+)|(.*)$")
        if looted then
            -- Store the authoritative count as the target; the displayed value is advanced
            -- toward it by at most +1 per tick (below) so the bar increments one corpse at a
            -- time instead of jumping when multiple messages queue up between drains.
            uiState.lootProgressTarget = tonumber(looted) or 0
            uiState.lootRunTotalCorpses = tonumber(total) or 0
            uiState.lootRunCurrentCorpse = corpse or ""
        end
    end
    -- Advance displayed progress toward target one step per tick.
    local lpt = uiState.lootProgressTarget or 0
    local lpc = uiState.lootRunCorpsesLooted or 0
    if lpc < lpt then uiState.lootRunCorpsesLooted = lpc + 1 end

    -- sell_start: reset per-run sold list (mirrors loot_start / lootRunLootedItems).
    local sellStarts = ipc.receiveAll("sell_start")
    if sellStarts and #sellStarts > 0 then
        uiState.sellRunSoldItems = {}
    end

    -- Drain sell_item: real-time per-item sell results (mirrors loot_item pattern).
    -- sell.mac sends "ItemName|ItemValue|StackSize" on each successful sale.
    local soldItems = ipc.receiveAll("sell_item")
    if soldItems and #soldItems > 0 then
        if not uiState.sellRunSoldItems then uiState.sellRunSoldItems = {} end
        for _, msg in ipairs(soldItems) do
            local name, valStr, stackStr = msg:match("^([^|]+)|([^|]+)|(.+)$")
            if name and name ~= "" then
                table.insert(uiState.sellRunSoldItems, {
                    name = name,
                    value = tonumber(valStr) or 0,
                    stackSize = tonumber(stackStr) or 1,
                })
            end
        end
    end

    local ends = ipc.receiveAll("loot_end")
    if ends and #ends > 0 then
        local last = ends[#ends]
        local parts = {}
        for p in (last .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = p end
        if #parts >= 6 then
            uiState.lootRunTotalValue = tonumber(parts[3]) or uiState.lootRunTotalValue
            uiState.lootRunTributeValue = tonumber(parts[4]) or uiState.lootRunTributeValue
            if parts[5] ~= "" then uiState.lootRunBestItemName = item_name.normalizeItemName(parts[5]) end
            uiState.lootRunBestItemValue = tonumber(parts[6]) or uiState.lootRunBestItemValue
        end
        uiState.lootRunFinished = true
    end
end

-- Get statistics
function MacroBridge.getStats()
    return {
        sell = MacroBridge.stats.sell,
        loot = MacroBridge.stats.loot
    }
end

-- Reset statistics
function MacroBridge.resetStats()
    MacroBridge.stats.sell = {
        totalRuns = 0,
        totalItemsSold = 0,
        totalItemsFailed = 0,
        avgItemsPerRun = 0,
        avgDurationMs = 0,
        lastRunDurationMs = 0
    }
    MacroBridge.stats.loot = {
        totalRuns = 0,
        lastRunDurationMs = 0,
        avgDurationMs = 0
    }
    log("Statistics reset")
end

-- Read loot_progress.ini Progress/line; return true if first field is "1" (macro running). Used for file-based loot finish detection.
local function readLootProgressRunning()
    local getLootConfigFile = MacroBridge.config.getLootConfigFile
    if not getLootConfigFile then
        local c = require('itemui.config')
        getLootConfigFile = c.getLootConfigFile
    end
    if not getLootConfigFile then return false end
    local progPath = getLootConfigFile("loot_progress.ini")
    if not progPath or progPath == "" then return false end
    local config = require('itemui.config')
    local line = config.safeIniValueByPath(progPath, "Progress", "line", "")
    if not line or line == "" then return false end
    local running = (line .. "##"):match("^(.-)##")
    return running == "1"
end

-- Poll for macro state changes (throttled)
-- Call this from main loop
-- Uses file-based fallback: if Macro.Name() doesn't match "sell", we still detect running from sell_progress.ini (total>0, current<total)
function MacroBridge.poll()
    local now = os.clock() * 1000  -- ms
    
    -- Throttle polling to configured interval
    if (now - MacroBridge.state.lastPollTime) < MacroBridge.config.pollInterval then
        return
    end
    MacroBridge.state.lastPollTime = now
    
    -- Check sell.mac state: live TLO only for "running" so bar hides when macro ends (Issue 1)
    local liveSellRunning = isMacroRunning("sell")
    local sellRunning = liveSellRunning
    local wasRunning = MacroBridge.state.sell.lastRunning
    
    if sellRunning and not wasRunning then
        -- Sell macro just started
        MacroBridge.state.sell.running = true
        MacroBridge.state.sell.startTime = now
        MacroBridge.state.sell.smoothedFrac = 0
        emit('sell:started', { startTime = now })
        log("Sell macro started")
        
    elseif not sellRunning and wasRunning then
        -- Sell macro just finished
        MacroBridge.state.sell.running = false
        MacroBridge.state.sell.endTime = now
        MacroBridge.state.sell.smoothedFrac = 0
        
        -- Read failed items
        local failedItems, failedCount = readFailedItems()
        MacroBridge.state.sell.failedItems = failedItems
        MacroBridge.state.sell.failedCount = failedCount
        
        -- Update statistics
        local duration = now - MacroBridge.state.sell.startTime
        local itemsSold = MacroBridge.state.sell.progress.total - failedCount
        
        MacroBridge.stats.sell.totalRuns = MacroBridge.stats.sell.totalRuns + 1
        MacroBridge.stats.sell.totalItemsSold = MacroBridge.stats.sell.totalItemsSold + itemsSold
        MacroBridge.stats.sell.totalItemsFailed = MacroBridge.stats.sell.totalItemsFailed + failedCount
        MacroBridge.stats.sell.lastRunDurationMs = duration
        
        -- Calculate averages
        local runs = MacroBridge.stats.sell.totalRuns
        MacroBridge.stats.sell.avgItemsPerRun = MacroBridge.stats.sell.totalItemsSold / runs
        MacroBridge.stats.sell.avgDurationMs = (MacroBridge.stats.sell.avgDurationMs * (runs - 1) + duration) / runs
        
        emit('sell:complete', {
            endTime = now,
            durationMs = duration,
            itemsSold = itemsSold,
            failedItems = failedItems,
            failedCount = failedCount,
            needsInventoryScan = true  -- Signal to caller to rescan
        })
        log(string.format("Sell macro complete: %d items sold, %d failed, %.1fs duration", 
            itemsSold, failedCount, duration / 1000))
        
    elseif sellRunning then
        -- Sell macro is running - read progress
        local progress = readSellProgress()
        if progress then
            local changed = (progress.total ~= MacroBridge.state.sell.progress.total or
                           progress.current ~= MacroBridge.state.sell.progress.current or
                           progress.remaining ~= MacroBridge.state.sell.progress.remaining)
            
            if changed then
                MacroBridge.state.sell.progress = progress
                
                -- Smooth progress bar animation
                local targetFrac = (progress.total > 0) and math.min(1, math.max(0, progress.current / progress.total)) or 0
                local lerpSpeed = 0.35  -- higher = faster catch-up
                MacroBridge.state.sell.smoothedFrac = MacroBridge.state.sell.smoothedFrac + (targetFrac - MacroBridge.state.sell.smoothedFrac) * lerpSpeed
                MacroBridge.state.sell.smoothedFrac = math.min(1, math.max(0, MacroBridge.state.sell.smoothedFrac))
                
                emit('sell:progress', {
                    total = progress.total,
                    current = progress.current,
                    remaining = progress.remaining,
                    percent = targetFrac * 100
                })
            end
        end
    end
    
    MacroBridge.state.sell.lastRunning = sellRunning
    
    -- Drain sell IPC channels (supplements INI polling; higher priority when plugin loaded)
    local ipc = getIPC()
    if ipc then
        local sp = ipc.receiveAll("sell_progress")
        if sp and #sp > 0 then
            local last = sp[#sp]
            local cur, tot, rem = last:match("^([^|]+)|([^|]+)|(.+)$")
            if cur then
                MacroBridge.state.sell.progress = {
                    total = tonumber(tot) or 0,
                    current = tonumber(cur) or 0,
                    remaining = tonumber(rem) or 0
                }
                MacroBridge.state.sell.running = true
            end
        end
        local sf = ipc.receiveAll("sell_failed")
        if sf and #sf > 0 then
            for _, msg in ipairs(sf) do
                table.insert(MacroBridge.state.sell.failedItems, msg)
                MacroBridge.state.sell.failedCount = MacroBridge.state.sell.failedCount + 1
            end
        end
        local se = ipc.receiveAll("sell_end")
        if se and #se > 0 then
            MacroBridge.state.sell.running = false
        end
    end
    
    -- Check loot.mac state: live TLO first, then fallback to loot_progress.ini Progress/line (running##...) so UI works when macro name isn't detected
    local liveLootRunning = isMacroRunning("loot")
    local lootRunning = liveLootRunning or readLootProgressRunning()
    local wasLootRunning = MacroBridge.state.loot.lastRunning
    
    if lootRunning then
        -- Update loot progress cache when loot macro is running (same throttle as poll)
        local getLootConfigFile = MacroBridge.config.getLootConfigFile
        if getLootConfigFile then
            local progPath = getLootConfigFile("loot_progress.ini")
            if progPath and progPath ~= "" then
                local cfg = require('itemui.config')
                if cfg.readLootProgressSection then
                    local corpses, total, current = cfg.readLootProgressSection(progPath)
                    MacroBridge.state.loot.progress = {
                        corpsesLooted = corpses or 0,
                        totalCorpses = total or 0,
                        currentCorpse = current or ""
                    }
                end
            end
        end
    end
    if lootRunning and not wasLootRunning then
        -- Loot macro just started
        MacroBridge.state.loot.running = true
        MacroBridge.state.loot.startTime = now
        emit('loot:started', { startTime = now })
        log("Loot macro started")
        
    elseif not lootRunning and wasLootRunning then
        -- Loot macro just finished
        MacroBridge.state.loot.running = false
        MacroBridge.state.loot.endTime = now
        
        local duration = now - MacroBridge.state.loot.startTime
        
        MacroBridge.stats.loot.totalRuns = MacroBridge.stats.loot.totalRuns + 1
        MacroBridge.stats.loot.lastRunDurationMs = duration
        
        -- Calculate average
        local runs = MacroBridge.stats.loot.totalRuns
        MacroBridge.stats.loot.avgDurationMs = (MacroBridge.stats.loot.avgDurationMs * (runs - 1) + duration) / runs
        
        emit('loot:complete', {
            endTime = now,
            durationMs = duration,
            needsInventoryScan = true  -- Signal to caller to rescan
        })
        log(string.format("Loot macro complete: %.1fs duration", duration / 1000))
    end
    
    MacroBridge.state.loot.lastRunning = lootRunning
end

return MacroBridge
