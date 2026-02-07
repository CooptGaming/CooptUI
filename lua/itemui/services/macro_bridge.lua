--[[
    Macro Bridge Service - Phase 5: Macro Integration Improvement
    
    Centralizes communication between ItemUI and macros (sell.mac, loot.mac).
    Provides event-based progress monitoring with throttled polling.
    
    Features:
    - Throttled file polling (500ms instead of every frame)
    - Event-based notifications (publish/subscribe)
    - Progress tracking with statistics
    - Config hot-reload detection
    - Failed item tracking
    
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

local MacroBridge = {
    -- Configuration
    config = {
        sellLogPath = nil,
        pollInterval = 500,  -- ms (reduced from every frame)
        debug = false
    },
    
    -- State tracking
    state = {
        lastPollTime = 0,
        sell = {
            running = false,
            lastRunning = false,
            progress = { total = 0, current = 0, remaining = 0 },
            smoothedFrac = 0,
            failedItems = {},
            failedCount = 0,
            startTime = 0,
            endTime = 0
        },
        loot = {
            running = false,
            lastRunning = false,
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

-- Initialize the service
function MacroBridge.init(config)
    MacroBridge.config.sellLogPath = config.sellLogPath
    MacroBridge.config.pollInterval = config.pollInterval or 500
    MacroBridge.config.debug = config.debug or false
    
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

-- Emit event to all subscribers
local function emit(event, data)
    log("Emit event: " .. event)
    if MacroBridge.subscribers[event] then
        for _, callback in ipairs(MacroBridge.subscribers[event]) do
            local ok, err = pcall(callback, data)
            if not ok then
                print(string.format("[MacroBridge] Error in %s callback: %s", event, tostring(err)))
            end
        end
    end
end

-- Check if macro is running
local function isMacroRunning(macroName)
    local macro = mq.TLO.Macro
    if not macro then return false end
    
    -- Check if Running is a valid function before calling
    local running = macro.Running and macro.Running()
    if not running then return false end
    
    -- Check if Name is a valid function before calling
    local name = macro.Name and macro.Name()
    if not name then return false end
    
    local mn = name:lower()
    return (mn == macroName or mn == macroName .. ".mac")
end

-- Read sell progress from INI file (safe: TLO.Ini can be nil during zone/load)
local function readSellProgress()
    if not MacroBridge.config.sellLogPath then return nil end
    local config = require('itemui.config')
    local progPath = MacroBridge.config.sellLogPath .. "\\sell_progress.ini"
    local totalStr = config.safeIniValueByPath(progPath, "Progress", "total", "0")
    local currentStr = config.safeIniValueByPath(progPath, "Progress", "current", "0")
    local remainingStr = config.safeIniValueByPath(progPath, "Progress", "remaining", "0")
    
    local total = tonumber(totalStr) or 0
    local current = tonumber(currentStr) or 0
    local remaining = tonumber(remainingStr) or 0
    
    return { total = total, current = current, remaining = remaining }
end

-- Read failed items from sell_failed.ini (safe INI read)
local function readFailedItems()
    if not MacroBridge.config.sellLogPath then return {}, 0 end
    local config = require('itemui.config')
    local failedPath = MacroBridge.config.sellLogPath .. "\\sell_failed.ini"
    local countStr = config.safeIniValueByPath(failedPath, "Failed", "count", "0")
    local count = tonumber(countStr) or 0
    
    local failedItems = {}
    if count > 0 then
        for i = 1, count do
            local itemName = config.safeIniValueByPath(failedPath, "Failed", tostring(i), "")
            if itemName and itemName ~= "" then
                table.insert(failedItems, itemName)
            end
        end
    end
    
    return failedItems, count
end

-- Write sell progress to INI file
function MacroBridge.writeSellProgress(total, current)
    if not MacroBridge.config.sellLogPath then return end
    
    local progPath = MacroBridge.config.sellLogPath .. "\\sell_progress.ini"
    local remaining = math.max(0, total - current)
    
    mq.cmdf('/ini "%s" Progress total %d', progPath, total)
    mq.cmdf('/ini "%s" Progress current %d', progPath, current)
    mq.cmdf('/ini "%s" Progress remaining %d', progPath, remaining)
    
    log(string.format("Wrote progress: %d/%d (remaining: %d)", current, total, remaining))
end

-- Get smoothed progress fraction (for progress bar animation)
function MacroBridge.getSmoothedProgress()
    return MacroBridge.state.sell.smoothedFrac
end

-- Get current sell progress data
function MacroBridge.getSellProgress()
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

-- Get loot macro state
function MacroBridge.getLootState()
    return {
        running = MacroBridge.state.loot.running
    }
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

-- Poll for macro state changes (throttled)
-- Call this from main loop
function MacroBridge.poll()
    local now = os.clock() * 1000  -- ms
    
    -- Throttle polling to configured interval
    if (now - MacroBridge.state.lastPollTime) < MacroBridge.config.pollInterval then
        return
    end
    MacroBridge.state.lastPollTime = now
    
    -- Check sell.mac state
    local sellRunning = isMacroRunning("sell")
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
    
    -- Check loot.mac state
    local lootRunning = isMacroRunning("loot")
    local wasLootRunning = MacroBridge.state.loot.lastRunning
    
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
