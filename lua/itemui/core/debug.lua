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

local logLineBuffer = {}
local echoLineBuffer = {}
local ECHO_DRAIN_PER_TICK = 8

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
    rotateIfNeeded(path)
    pcall(function()
        local dir = path:match("^(.+)\\[^\\]+$")
        if dir and os and os.execute then
            os.execute('mkdir "' .. dir:gsub('"', '\\"') .. '" 2>nul')
        end
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

M.knownChannels = { "Sell", "Loot", "Augment", "MacroBridge", "Tutorial", "Registry", "Scan", "ItemOps" }
M.isChannelEnabled = isChannelEnabled
M.setChannelEnabled = setChannelEnabled

return M
