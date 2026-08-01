--[[ layout_io.lua: Layout INI file path, parse, and type conversion. No state, no deps init. ]]
local config = require('itemui.config')
local file_safe = require('itemui.utils.file_safe')
local constants = require('itemui.constants')

local LAYOUT_INI = constants.LAYOUT_INI
local LAYOUT_SECTION = constants.LAYOUT_SECTION

local M = {}

--- Keys whose value is a plain string (mode names, edge names, CSV lists). Checked by
--- loadLayoutValue before its numeric fallthrough.
local STRING_KEYS = {
    UIMode = true,          -- classic | bars
    DockPosition = true,    -- top | bottom
    DockChat = true,        -- hidden | collapsed | peek
    DockSegments = true,    -- CSV: segment ids, in order
    DockBottomStyle = true, -- menus | buttons
    DockButtons = true,     -- CSV: launcher ids, in order (DockBottomStyle = "buttons" only)
    ZoneAssign = true,      -- CSV: moduleId:zone pairs (user overrides of the registry's zone)
    WindowAttach = true,    -- CSV: moduleId:target:edge:align tuples
    LayoutPreset = true,    -- active preset name
    UserPlaced = true,      -- CSV: module ids the user dragged; zones skip them until Re-tidy
    Keybinds = true,        -- CSV: bindId:combo pairs (spec §10); empty combo = unbound
    ChatSendTo = true,      -- say | group | raid | guild | tell | bca (19c's channel picker)
}
-- DockLaunchers / DockNative were written by phase 1 but never consumed by anything (the
-- bottom-bar menus are registry-driven, and the native list is a phase-3 acceptance
-- criterion). Dropped in phase 4; the regenerating [Layout] writer strips stale copies.

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

--- Parse an arbitrary INI file into { [sectionName] = {key=value,...} } for every section
--- whose [Name] matches the given Lua pattern (nil = all sections). Pure; safe read (missing
--- or unreadable file returns {}). Section order is preserved in the companion list return.
--- Built for itemui_presets.ini ([Preset:<name>] sections), but generic on purpose — the
--- layout INI's own parser above recognizes a fixed set and drops the rest by design.
function M.parseSectionsMatching(path, pattern)
    local out, order = {}, {}
    if not path then return out, order end
    local content = file_safe.safeReadAll(path)
    if not content or content == "" then return out, order end
    local current = nil
    for line in (content .. "\n"):gmatch("(.-)\n") do
        line = line:match("^%s*(.-)%s*$")
        local header = line:match("^%[(.-)%]$")
        if header then
            if pattern == nil or header:find(pattern) then
                current = header
                if not out[current] then
                    out[current] = {}
                    order[#order + 1] = current
                end
            else
                current = nil
            end
        elseif current and line:find("=") then
            local k, v = line:match("^([^=]+)=(.*)$")
            if k and v then
                out[current][k:match("^%s*(.-)%s*$")] = v:match("^%s*(.-)%s*$")
            end
        end
    end
    return out, order
end

--- Load layout value from parsed layout with type conversion. Pure: no state.
function M.loadLayoutValue(layout, key, default)
    if not layout then return default end
    local val = layout[key]
    if not val or val == "" then return default end
    if key == "AlignToContext" or key == "UILocked" or key == "SuppressWhenLootMac" or key == "ConfirmBeforeDelete" or key == "ActivationGuardEnabled"
        or key == "EnableRealTimeLoot" or key == "EnableLootHistory" or key == "EnableSkipHistory"
        or key == "NativeMerchantStrip" or key == "NativeHoverTooltip"
        or key == "NativeItemDisplayReplace"
        or key == "DockTop" or key == "DockBottom" then
        return (val == "1" or val == "true")
    end
    if key == "InvSortColumn" or key == "SellSortColumn" or key == "BankSortColumn" or key == "AASortColumn" then return val end  -- string (column key)
    if key == "PinnedWindows" then return val end  -- string (comma-joined window ids)
    -- Dock/bars string keys. These MUST be listed here: the fallthrough below is
    -- `tonumber(val) or default`, so an unlisted string key writes to the INI correctly,
    -- is present in the file, and still reads back as its default forever.
    if STRING_KEYS[key] then return val end
    if key == "ItemUIToggleKey" then return (layout[key] ~= nil) and layout[key] or default end  -- keybinding; empty = no bind
    return tonumber(val) or default
end

return M
