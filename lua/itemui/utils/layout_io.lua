--[[ layout_io.lua: Layout INI file path, parse, and type conversion. No state, no deps init. ]]
local config = require('itemui.config')
local file_safe = require('itemui.utils.file_safe')
local constants = require('itemui.constants')

local LAYOUT_INI = constants.LAYOUT_INI
local LAYOUT_SECTION = constants.LAYOUT_SECTION

local M = {}

--- Get layout file path (ItemUI layout INI).
function M.getLayoutFilePath()
    return config.getConfigFile(LAYOUT_INI)
end

--- Parse entire layout INI once; returns all sections (avoids 3x file reads on loadLayoutConfig).
--- Uses safe read: on error or missing file returns empty sections so startup never throws.
function M.parseLayoutFileFull()
    local path = M.getLayoutFilePath()
    if not path then return { defaults = {}, layout = {}, columnVisibilityDefaults = {}, columnVisibility = {} } end
    local content = file_safe.safeReadAll(path)
    if not content or content == "" then return { defaults = {}, layout = {}, columnVisibilityDefaults = {}, columnVisibility = {} } end
    local sections = { defaults = {}, layout = {}, columnVisibilityDefaults = {}, columnVisibility = {} }
    local current = nil
    for line in (content .. "\n"):gmatch("(.-)\n") do
        line = line:match("^%s*(.-)%s*$")
        if line:match("^%[") then
            if line == "[Defaults]" then current = "defaults"
            elseif line == "[" .. LAYOUT_SECTION .. "]" then current = "layout"
            elseif line == "[ColumnVisibilityDefaults]" then current = "columnVisibilityDefaults"
            elseif line == "[ColumnVisibility]" then current = "columnVisibility"
            else current = nil end
        elseif current and line:find("=") then
            local k, v = line:match("^([^=]+)=(.*)$")
            if k and v then
                k = k:match("^%s*(.-)%s*$")
                v = v:match("^%s*(.-)%s*$")
                sections[current][k] = v
            end
        end
    end
    return sections
end

--- Parse entire layout INI once; returns map of key->value for [Layout] section only. Safe read: returns {} on error.
function M.parseLayoutFile()
    local path = M.getLayoutFilePath()
    if not path then return {} end
    local content = file_safe.safeReadAll(path)
    if not content or content == "" then return {} end
    local layout = {}
    local inLayout = false
    for line in (content .. "\n"):gmatch("(.-)\n") do
        line = line:match("^%s*(.-)%s*$")
        if line:match("^%[") then
            inLayout = (line == "[" .. LAYOUT_SECTION .. "]")
        elseif inLayout and line:find("=") then
            local k, v = line:match("^([^=]+)=(.*)$")
            if k and v then
                k = k:match("^%s*(.-)%s*$")
                v = v:match("^%s*(.-)%s*$")
                layout[k] = v
            end
        end
    end
    return layout
end

--- Load layout value from parsed layout with type conversion. Pure: no state.
function M.loadLayoutValue(layout, key, default)
    if not layout then return default end
    local val = layout[key]
    if not val or val == "" then return default end
    if key == "AlignToContext" or key == "UILocked" or key == "SuppressWhenLootMac" or key == "ConfirmBeforeDelete" or key == "ActivationGuardEnabled" then
        return (val == "1" or val == "true")
    end
    if key == "InvSortColumn" or key == "SellSortColumn" or key == "BankSortColumn" then return val end  -- string (column key)
    return tonumber(val) or default
end

return M
