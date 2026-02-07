--[[
    ItemUI Config Module
    INI read/write, list parsing, and path helpers for sell_config, shared_config, loot_config.
    Chunked list read/write to avoid MQ macro 2048 character buffer limit.
--]]

local mq = require('mq')

-- MQ macro variables have 2048 char limit; keep chunks safely under
local MAX_INI_CHUNK_LEN = 2000

local basePath = (mq.TLO and mq.TLO.MacroQuest and mq.TLO.MacroQuest.Path and mq.TLO.MacroQuest.Path()) and mq.TLO.MacroQuest.Path() or ""
local CONFIG_PATH = basePath ~= "" and (basePath .. '/Macros/sell_config') or ""
local SHARED_CONFIG_PATH = basePath ~= "" and (basePath .. '/Macros/shared_config') or ""
local LOOT_CONFIG_PATH = basePath ~= "" and (basePath .. '/Macros/loot_config') or ""
local CHARS_PATH = basePath ~= "" and (CONFIG_PATH .. '/Chars') or ""

local function getConfigFile(f)
    return CONFIG_PATH ~= "" and (CONFIG_PATH .. '/' .. f) or nil
end

local function getSharedConfigFile(f)
    return SHARED_CONFIG_PATH ~= "" and (SHARED_CONFIG_PATH .. '/' .. f) or nil
end

local function getLootConfigFile(f)
    return LOOT_CONFIG_PATH ~= "" and (LOOT_CONFIG_PATH .. '/' .. f) or nil
end

local function getCharStoragePath(charName, filename)
    if CHARS_PATH == "" or not charName or charName == "" then return nil end
    local charFolder = CHARS_PATH .. '/' .. (charName:gsub("[^%w_%-]", "_"))
    return filename and (charFolder .. '/' .. filename) or charFolder
end

--- Safe INI read: TLO.Ini can be nil during zone transitions/loading. Returns default on any nil or error.
--- path: full path to INI file; section/key: INI section and key names.
function safeIniValueByPath(path, section, key, default)
    if not path or path == "" or not section or not key then return default or "" end
    local ok, v = pcall(function()
        local ini = mq.TLO and mq.TLO.Ini
        if not ini or not ini.File then return nil end
        local f = ini.File(path)
        if not f or not f.Section then return nil end
        local s = f.Section(section)
        if not s or not s.Key then return nil end
        local k = s.Key(key)
        return (k and k.Value and k.Value()) or nil
    end)
    return (ok and v and v ~= "") and v or (default or "")
end

local function readINIValue(file, section, key, default)
    local path = getConfigFile(file)
    if not path then return default or "" end
    return safeIniValueByPath(path, section, key, default)
end

local function readSharedINIValue(file, section, key, default)
    local path = getSharedConfigFile(file)
    if not path then return default or "" end
    return safeIniValueByPath(path, section, key, default)
end

local function readLootINIValue(file, section, key, default)
    local path = getLootConfigFile(file)
    if not path then return default or "" end
    return safeIniValueByPath(path, section, key, default)
end

local function writeINIValue(file, section, key, value)
    local path = getConfigFile(file)
    if path then mq.cmdf('/ini "%s" "%s" "%s" "%s"', path, section, key, value) end
end

local function writeSharedINIValue(file, section, key, value)
    local path = getSharedConfigFile(file)
    if path then mq.cmdf('/ini "%s" "%s" "%s" "%s"', path, section, key, value) end
end

local function writeLootINIValue(file, section, key, value)
    local path = getLootConfigFile(file)
    if path then mq.cmdf('/ini "%s" "%s" "%s" "%s"', path, section, key, value) end
end

local MAX_CHUNKS = 20  -- Safety limit to prevent infinite loops from corrupt data

--- Read a list value that may be chunked across key, key2, key3... (avoids 2048 limit)
local function readListValue(file, section, key, default, getPathFn)
    getPathFn = getPathFn or getConfigFile
    local path = getPathFn(file)
    if not path then return default or "" end
    local parts = {}
    local i = 1
    local baseKey = key:match("^(.-)%d*$") or key
    while i <= MAX_CHUNKS do
        local k = (i == 1) and baseKey or (baseKey .. i)
        local v = safeIniValueByPath(path, section, k, nil)
        if not v or v == "" then break end
        parts[#parts + 1] = v
        i = i + 1
    end
    if #parts == 0 then return default or "" end
    return table.concat(parts, "/")
end

--- Write a list value, chunking if over MAX_INI_CHUNK_LEN (avoids 2048 limit)
local function writeListValue(file, section, key, value, getPathFn)
    getPathFn = getPathFn or getConfigFile
    local path = getPathFn(file)
    if not path then return end
    local baseKey = key:match("^(.-)%d*$") or key
    if not value or value == "" then
        mq.cmdf('/ini "%s" "%s" "%s" ""', path, section, baseKey)
        local i = 2
        while i <= MAX_CHUNKS do
            local k = baseKey .. i
            local v = safeIniValueByPath(path, section, k, nil)
            if not v or v == "" then break end
            mq.cmdf('/ini "%s" "%s" "%s" ""', path, section, k)
            i = i + 1
        end
        return
    end
    if #value <= MAX_INI_CHUNK_LEN then
        mq.cmdf('/ini "%s" "%s" "%s" "%s"', path, section, baseKey, value)
        local i = 2
        while i <= MAX_CHUNKS do
            local k = baseKey .. i
            local v = safeIniValueByPath(path, section, k, nil)
            if not v or v == "" then break end
            mq.cmdf('/ini "%s" "%s" "%s" ""', path, section, k)
            i = i + 1
        end
        return
    end
    local chunks = {}
    local pos = 1
    while pos <= #value do
        local chunkEnd = math.min(pos + MAX_INI_CHUNK_LEN - 1, #value)
        local chunk = value:sub(pos, chunkEnd)
        if chunkEnd < #value then
            local lastSlash = chunk:reverse():find("/")
            if lastSlash then
                chunkEnd = pos + (#chunk - lastSlash)
                chunk = value:sub(pos, chunkEnd)
            end
        end
        chunks[#chunks + 1] = chunk
        pos = chunkEnd + 1
    end
    for i, chunk in ipairs(chunks) do
        local k = (i == 1) and baseKey or (baseKey .. i)
        mq.cmdf('/ini "%s" "%s" "%s" "%s"', path, section, k, chunk)
    end
    local i = #chunks + 1
    while i <= MAX_CHUNKS do
        local k = baseKey .. i
        local v = safeIniValueByPath(path, section, k, nil)
        if not v or v == "" then break end
        mq.cmdf('/ini "%s" "%s" "%s" ""', path, section, k)
        i = i + 1
    end
end

--- Read list value from shared config (chunked)
local function readSharedListValue(file, section, key, default)
    return readListValue(file, section, key, default, getSharedConfigFile)
end

--- Read list value from loot config (chunked)
local function readLootListValue(file, section, key, default)
    return readListValue(file, section, key, default, getLootConfigFile)
end

--- Write list value to shared config (chunked if needed)
local function writeSharedListValue(file, section, key, value)
    return writeListValue(file, section, key, value, getSharedConfigFile)
end

--- Write list value to loot config (chunked if needed)
local function writeLootListValue(file, section, key, value)
    return writeListValue(file, section, key, value, getLootConfigFile)
end

--- Filter out null/nil placeholders that shouldn't be in filter lists
local function isValidFilterEntry(x)
    if not x or x == "" then return false end
    local lower = x:lower()
    if lower == "null" or lower == "nil" then return false end
    return true
end

local function parseList(str)
    local t = {}
    if str and str ~= "" then
        for s in str:gmatch("([^/]+)") do
            local x = s:match("^%s*(.-)%s*$")
            if isValidFilterEntry(x) then t[#t + 1] = x end
        end
    end
    return t
end

local function joinList(t)
    if not t or #t == 0 then return "" end
    local filtered = {}
    for _, v in ipairs(t) do
        if isValidFilterEntry(v) then filtered[#filtered + 1] = v end
    end
    return #filtered > 0 and table.concat(filtered, "/") or ""
end

local function sanitizeItemName(name)
    if not name then return nil end
    name = name:match("^%s*(.-)%s*$")
    if name == "" then return nil end
    name = name:gsub("/", "")
    name = name:gsub("%c", "")
    name = name:match("^%s*(.-)%s*$")
    return name ~= "" and name or nil
end

return {
    -- Paths
    CONFIG_PATH = CONFIG_PATH,
    safeIniValueByPath = safeIniValueByPath,
    MAX_INI_CHUNK_LEN = MAX_INI_CHUNK_LEN,
    SHARED_CONFIG_PATH = SHARED_CONFIG_PATH,
    LOOT_CONFIG_PATH = LOOT_CONFIG_PATH,
    CHARS_PATH = CHARS_PATH,
    getConfigFile = getConfigFile,
    getSharedConfigFile = getSharedConfigFile,
    getLootConfigFile = getLootConfigFile,
    getCharStoragePath = getCharStoragePath,
    -- INI read/write
    readINIValue = readINIValue,
    readSharedINIValue = readSharedINIValue,
    readLootINIValue = readLootINIValue,
    writeINIValue = writeINIValue,
    writeSharedINIValue = writeSharedINIValue,
    writeLootINIValue = writeLootINIValue,
    readListValue = readListValue,
    readSharedListValue = readSharedListValue,
    readLootListValue = readLootListValue,
    writeListValue = writeListValue,
    writeSharedListValue = writeSharedListValue,
    writeLootListValue = writeLootListValue,
    -- List helpers
    parseList = parseList,
    joinList = joinList,
    sanitizeItemName = sanitizeItemName,
}
