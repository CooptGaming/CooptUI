--[[
    Welcome process environment manifest and validation (Task 8.2).
    Defines required paths; validates or creates defaults before tutorial steps.
]]

local mq = require('mq')
local M = {}
local config
local function getConfig()
    if not config then config = require('itemui.config') end
    return config
end

local dbg = pcall(function() return require('itemui.core.debug').channel('Welcome') end) and require('itemui.core.debug').channel('Welcome') or nil

--- Manifest entry: path (relative to MQ root), type, canGenerate, label.
local MANIFEST = {
    { path = "Macros/sell_config",     type = "folder", canGenerate = true,  label = "Sell config folder (Macros/sell_config)" },
    { path = "Macros/shared_config",   type = "folder", canGenerate = true,  label = "Shared config folder (Macros/shared_config)" },
    { path = "Macros/loot_config",     type = "folder", canGenerate = true,  label = "Loot config folder (Macros/loot_config)" },
    { path = "Macros/sell_config/itemui_layout.ini", type = "ini", canGenerate = true, label = "Layout INI (itemui_layout.ini)" },
    { path = "Macros/sell_config/sell_flags.ini",     type = "ini", canGenerate = true, label = "Sell flags (sell_flags.ini)" },
    { path = "Macros/loot_config/loot_flags.ini",     type = "ini", canGenerate = true, label = "Loot flags (loot_flags.ini)" },
}

local function getMQRoot()
    local p = mq.TLO and mq.TLO.MacroQuest and mq.TLO.MacroQuest.Path and mq.TLO.MacroQuest.Path()
    if not p or p == "" then return nil end
    return (p:gsub("/", "\\"))
end

local function fullPath(relPath)
    local root = getMQRoot()
    if not root then return nil end
    return root .. "\\" .. (relPath:gsub("/", "\\"))
end

local function ensureDir(path)
    if not path or path == "" then return false, "empty path" end
    local ok, err = pcall(function()
        if os and os.execute then
            os.execute('mkdir "' .. path:gsub('"', '\\"') .. '" 2>nul')
        end
    end)
    if not ok then return false, tostring(err) end
    local f = io.open(path .. "\\.", "r")
    if f then f:close(); return true end
    return false, "directory could not be created or is not writable"
end

local function ensureIni(path, defaultContent)
    defaultContent = defaultContent or "[Settings]\r\n"
    local dir = path:match("^(.+)\\[^\\]+$")
    if dir and os and os.execute then
        pcall(function() os.execute('mkdir "' .. dir:gsub('"', '\\"') .. '" 2>nul') end)
    end
    local f = io.open(path, "r")
    if f then f:close(); return true end
    f = io.open(path, "w")
    if not f then return false, "could not create file (permission or path)" end
    f:write(defaultContent)
    f:close()
    return true
end

--- Run validation. Returns list of { path, label, status = "valid"|"generated"|"failed", message? }.
function M.validate()
    local root = getMQRoot()
    local results = {}
    if not root then
        results[#results + 1] = { path = "", label = "MacroQuest path", status = "failed", message = "MacroQuest path not available. Run from in-game." }
        return results
    end
    for _, entry in ipairs(MANIFEST) do
        local full = fullPath(entry.path)
        local label = entry.label or entry.path
        local exists = false
        if entry.type == "folder" then
            local f = io.open(full .. "\\.", "r")
            exists = f and true or false
            if f then f:close() end
        else
            local f = io.open(full, "r")
            exists = f and true or false
            if f then f:close() end
        end
        if exists then
            results[#results + 1] = { path = entry.path, label = label, status = "valid" }
            if dbg and dbg.log then dbg.log("Valid: " .. entry.path) end
        elseif entry.canGenerate then
            local ok, err
            if entry.type == "folder" then
                ok, err = ensureDir(full)
            else
                ok, err = ensureIni(full)
            end
            if ok then
                results[#results + 1] = { path = entry.path, label = label, status = "generated" }
                if dbg and dbg.log then dbg.log("Generated: " .. entry.path) end
            else
                results[#results + 1] = { path = entry.path, label = label, status = "failed", message = err or "creation failed" }
                if dbg and dbg.error then dbg.error("Failed: " .. entry.path .. " - " .. tostring(err)) end
            end
        else
            results[#results + 1] = { path = entry.path, label = label, status = "failed", message = "Missing and cannot be auto-generated. Create manually or run from correct MQ root." }
        end
    end
    return results
end

M.MANIFEST = MANIFEST
return M
