--[[
    CoOpt UI standardized debug framework (Task 8.1).
    Export debug.channel(name) -> { log, warn, error }. Enable/disable via INI [Debug]; optional rolling log file.
]]

local mq = require('mq')
local M = {}

local LAYOUT_INI = "itemui_layout.ini"
local DEBUG_SECTION = "Debug"
local LOG_SUBDIR = "logs"
local LOG_FILENAME = "coopui_debug.log"
local LOG_BAK_FILENAME = "coopui_debug.log.bak"
local ROTATE_SIZE = 1024 * 1024  -- 1MB

local config
local function getConfig()
    if not config then config = require('itemui.config') end
    return config
end

local function getMQRoot()
    local p = mq.TLO and mq.TLO.MacroQuest and mq.TLO.MacroQuest.Path and mq.TLO.MacroQuest.Path()
    if not p or p == "" then return nil end
    return (p:gsub("/", "\\"))
end

-- Cache channel enabled state so hot paths (e.g. sell per item) don't read INI every log call.
local channelEnabledCache = {}

local function isChannelEnabled(channelName)
    if channelEnabledCache[channelName] ~= nil then
        return channelEnabledCache[channelName]
    end
    local cfg = getConfig()
    local v = cfg.readINIValue(LAYOUT_INI, DEBUG_SECTION, channelName, "0")
    local enabled = (v == "1" or v == "true" or v == "TRUE" or v == "yes")
    channelEnabledCache[channelName] = enabled
    return enabled
end

local function setChannelEnabled(channelName, enabled)
    local cfg = getConfig()
    cfg.writeINIValue(LAYOUT_INI, DEBUG_SECTION, channelName, enabled and "1" or "0")
    channelEnabledCache[channelName] = enabled
end

local function getLogFilePath()
    local root = getMQRoot()
    if not root then return nil end
    return root .. "\\" .. LOG_SUBDIR:gsub("/", "\\") .. "\\" .. LOG_FILENAME
end

-- Buffered log lines; flushed from main loop so sell/other hot paths don't block on file I/O.
local logLineBuffer = {}
-- Buffered echo lines; /echo can block so we drain from main loop instead of calling from hot path.
local echoLineBuffer = {}
local ECHO_DRAIN_PER_TICK = 8

-- Log directory: checked once per session, never spawns a subprocess.
local _logDirReady = false

local function ensureLogDirOnce()
    if _logDirReady then return end
    _logDirReady = true  -- set first so we never retry on failure
    local root = getMQRoot()
    if not root then return end
    local dir = root .. "\\" .. LOG_SUBDIR:gsub("/", "\\")
    -- Probe with a marker write (pure Lua I/O, no subprocess).
    local marker = dir .. "\\.mkdir"
    local f = io.open(marker, "w")
    if f then
        f:close()
        pcall(os.remove, marker)
        return  -- directory exists
    end
    -- Directory missing — create it once. This is the ONLY os.execute in the module
    -- and it runs at most once per session (not per tick).
    if os and os.execute then
        pcall(os.execute, 'mkdir "' .. dir:gsub('"', '\\"') .. '" 2>nul')
    end
end

local function rotateIfNeeded(path)
    if not path or not io or not io.open then return end
    pcall(function()
        local f = io.open(path, "rb")
        if not f then return end
        local size = 0
        if f.seek then size = f:seek("end") or 0 end
        f:close()
        if size >= ROTATE_SIZE then
            local bak = path:gsub("%.log$", ".log.bak")
            if os.remove then pcall(os.remove, bak) end
            if os.rename then os.rename(path, bak) end
        end
    end)
end

local function appendToLogFile(line)
    if not line or line == "" then return end
    logLineBuffer[#logLineBuffer + 1] = line
end

local function queueEcho(line)
    if not line or line == "" then return end
    echoLineBuffer[#echoLineBuffer + 1] = line
end

--- Flush buffered log lines and drain echo buffer. Call once per tick from main loop so debug logging doesn't block sell/hot paths.
function M.flushLogFile()
    local drained = 0
    while #echoLineBuffer > 0 and drained < ECHO_DRAIN_PER_TICK do
        local line = table.remove(echoLineBuffer, 1)
        if line and mq.cmdf then pcall(mq.cmdf, "/echo %s", line) end
        drained = drained + 1
    end
    if #logLineBuffer == 0 then return end
    local path = getLogFilePath()
    if not path then logLineBuffer = {}; return end
    ensureLogDirOnce()
    rotateIfNeeded(path)
    pcall(function()
        local f = io.open(path, "a")
        if f then
            for i = 1, #logLineBuffer do
                f:write(logLineBuffer[i])
                f:write("\n")
            end
            f:close()
        end
    end)
    logLineBuffer = {}
end

local function formatTime()
    if os and os.date then
        return os.date("%Y-%m-%d %H:%M:%S")
    end
    return ""
end

--- Returns a channel object with log(msg), warn(msg), error(msg). When disabled, methods are no-ops.
function M.channel(name)
    local chan = name or "Default"
    return {
        log = function(msg)
            if not isChannelEnabled(chan) then return end
            local line = string.format("\\ag[CoOpt Debug: %s]\\ax %s", chan, tostring(msg))
            queueEcho(line)
            appendToLogFile(string.format("[%s] %s: %s", formatTime(), chan, tostring(msg):gsub("[\r\n]", " ")))
        end,
        warn = function(msg)
            if not isChannelEnabled(chan) then return end
            local line = string.format("\\ay[CoOpt Debug: %s]\\ax warn: %s", chan, tostring(msg))
            queueEcho(line)
            appendToLogFile(string.format("[%s] %s WARN: %s", formatTime(), chan, tostring(msg):gsub("[\r\n]", " ")))
        end,
        error = function(msg)
            if not isChannelEnabled(chan) then return end
            local line = string.format("\\ar[CoOpt Debug: %s]\\ax %s", chan, tostring(msg))
            queueEcho(line)
            appendToLogFile(string.format("[%s] %s ERROR: %s", formatTime(), chan, tostring(msg):gsub("[\r\n]", " ")))
        end,
    }
end

--- List of known channel names for Settings UI toggles.
M.knownChannels = { "Sell", "Loot", "Augment", "MacroBridge", "Layout", "Scan", "ItemOps" }

M.isChannelEnabled = isChannelEnabled
M.setChannelEnabled = setChannelEnabled

-- ---------------------------------------------------------------------------
-- Performance profiling toggle (INI-backed, same section as debug channels)
-- Keys: ProfileEnabled (0/1), ProfileThresholdMs (integer)
-- ---------------------------------------------------------------------------
local PROFILE_ENABLED_KEY = "ProfileEnabled"
local PROFILE_THRESHOLD_KEY = "ProfileThresholdMs"
local _profileEnabledCache = nil
local _profileThresholdCache = nil

function M.isProfileEnabled()
    if _profileEnabledCache ~= nil then return _profileEnabledCache end
    local cfg = getConfig()
    local v = cfg.readINIValue(LAYOUT_INI, DEBUG_SECTION, PROFILE_ENABLED_KEY, "0")
    _profileEnabledCache = (v == "1" or v == "true" or v == "TRUE" or v == "yes")
    return _profileEnabledCache
end

function M.setProfileEnabled(enabled)
    local cfg = getConfig()
    cfg.writeINIValue(LAYOUT_INI, DEBUG_SECTION, PROFILE_ENABLED_KEY, enabled and "1" or "0")
    _profileEnabledCache = enabled
end

function M.getProfileThresholdMs()
    if _profileThresholdCache ~= nil then return _profileThresholdCache end
    local cfg = getConfig()
    local v = cfg.readINIValue(LAYOUT_INI, DEBUG_SECTION, PROFILE_THRESHOLD_KEY, "30")
    local n = tonumber(v) or 30
    _profileThresholdCache = math.max(1, n)
    return _profileThresholdCache
end

function M.setProfileThresholdMs(ms)
    local cfg = getConfig()
    ms = math.max(1, math.floor(tonumber(ms) or 30))
    cfg.writeINIValue(LAYOUT_INI, DEBUG_SECTION, PROFILE_THRESHOLD_KEY, tostring(ms))
    _profileThresholdCache = ms
end

return M
