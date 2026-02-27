--[[
    Default layout bundle: first-run application and revert support.
    Reads from bundled default_layout/ (e.g. lua/itemui/default_layout/).
    Layout only — does not touch user data (inventory, lists, filters, etc.).
    PATCHER: Place default_layout/ at lua/itemui/default_layout/ so this module finds it.
]]

local mq = require('mq')
local file_safe = require('itemui.utils.file_safe')
local config = require('itemui.config')

local M = {}

local LAYOUT_INI = "itemui_layout.ini"
local OVERLAY_SNIPPET = "overlay_snippet.ini"
local MANIFEST = "layout_manifest.json"
local VERSION_MARKER = "default_layout_version.txt"
local OVERLAY_INI = "MacroQuest_Overlay.ini"
local BAK_RETENTION_DAYS = 7
local BAK_TIMESTAMP_SUFFIX = ".ts"

--- Path to MQ root (MacroQuest.Path); nil if not available.
function M.getMQRoot()
    local p = mq.TLO and mq.TLO.MacroQuest and mq.TLO.MacroQuest.Path and mq.TLO.MacroQuest.Path()
    if not p or p == "" then return nil end
    return (p:gsub("/", "\\"))
end

--- Path to bundled default_layout folder: MQ root/lua/itemui/default_layout/
function M.getBundledDefaultLayoutPath()
    local root = M.getMQRoot()
    if not root then return nil end
    return root .. "\\lua\\itemui\\default_layout"
end

--- True if user has an existing layout (itemui_layout.ini exists and has content).
--- Hardened: .bak with content => true; file unreadable => true; file missing or empty/whitespace => false.
function M.hasExistingLayout()
    local path = config.getConfigFile(LAYOUT_INI)
    if not path or path == "" then return false end
    path = path:gsub("/", "\\")
    local backupPath = path .. ".bak"
    local bakContent = file_safe.safeReadAll(backupPath)
    if bakContent and #bakContent:gsub("%s", "") > 0 then
        return true
    end
    local f = io.open(path, "r")
    if not f then
        return false
    end
    local content = f:read("*all")
    f:close()
    if content == nil then
        return true
    end
    return #content:gsub("%s", "") > 0
end

--- Read version token from layout_manifest.json in bundled default_layout. Returns nil if not found.
function M.getBundledDefaultVersionToken()
    local base = M.getBundledDefaultLayoutPath()
    if not base then return nil end
    local path = base .. "\\" .. MANIFEST
    local content = file_safe.safeReadAll(path)
    if not content or content == "" then return nil end
    local v = content:match('"versionToken"%s*:%s*"([^"]*)"')
    return v
end

--- Remove .bak and its timestamp file if the backup is older than BAK_RETENTION_DAYS (R10).
local function removeBackupIfOlderThanRetention(backupPath)
    if not backupPath or backupPath == "" then return end
    local tsPath = backupPath .. BAK_TIMESTAMP_SUFFIX
    local tsContent = file_safe.safeReadAll(tsPath)
    if not tsContent or tsContent == "" then return end
    local ts = tonumber(tsContent:match("^%s*(%d+)%s*$"))
    if not ts then return end
    local now = os.time()
    if now - ts >= BAK_RETENTION_DAYS * 24 * 3600 then
        pcall(function() os.remove(backupPath) end)
        pcall(function() os.remove(tsPath) end)
    end
end

--- Read applied default version from Macros/sell_config/default_layout_version.txt
function M.getAppliedDefaultVersion()
    local path = config.getConfigFile(VERSION_MARKER)
    if not path then return nil end
    local content = file_safe.safeReadAll(path)
    if not content then return nil end
    return content:match("^%s*(.-)%s*$")
end

--- Copy bundled default layout to user config. Only layout files; no user data.
--- Returns (success, errorMessage). On failure, does not leave partial state (backup/restore).
function M.applyBundledDefaultLayout()
    local root = M.getMQRoot()
    local base = M.getBundledDefaultLayoutPath()
    if not root or not base then
        return false, "MacroQuest path not available."
    end
    local layoutSrc = base .. "\\" .. LAYOUT_INI
    local layoutContent = file_safe.safeReadAll(layoutSrc)
    if not layoutContent or layoutContent == "" then
        return false, "Bundled default layout not found (missing itemui_layout.ini)."
    end
    local layoutDest = config.getConfigFile(LAYOUT_INI)
    if not layoutDest or layoutDest == "" then
        return false, "Config path not available (Macros/sell_config)."
    end
    layoutDest = layoutDest:gsub("/", "\\")
    local sellConfigPath = layoutDest:match("^(.+)\\[^\\]+$") or layoutDest
    local backupPath = layoutDest .. ".bak"
    removeBackupIfOlderThanRetention(backupPath)
    local existing = file_safe.safeReadAll(layoutDest)
    if existing and existing ~= "" then
        if not file_safe.safeWrite(backupPath, existing) then
            return false, "Could not create backup of current layout."
        end
        file_safe.safeWrite(backupPath .. BAK_TIMESTAMP_SUFFIX, tostring(os.time()))
    end
    if not file_safe.safeWrite(layoutDest, layoutContent) then
        if existing and existing ~= "" then file_safe.safeWrite(layoutDest, existing) end
        return false, "Could not write layout file."
    end
    -- Append overlay snippet to config/MacroQuest_Overlay.ini (ImGui uses last occurrence)
    local snippetPath = base .. "\\" .. OVERLAY_SNIPPET
    local snippetContent = file_safe.safeReadAll(snippetPath)
    if snippetContent and snippetContent:match("%S") then
        local configDir = root .. "\\config"
        local overlayPath = configDir .. "\\" .. OVERLAY_INI
        local overlayContent = file_safe.safeReadAll(overlayPath) or ""
        overlayContent = overlayContent:gsub("%s+$", "") .. "\n\n" .. snippetContent:gsub("^%s+", ""):gsub("%s+$", "")
        if not file_safe.safeWrite(overlayPath, overlayContent) then
            -- Non-fatal: layout INI is already applied; overlay is best-effort
        end
    end
    -- Write version marker from manifest
    local versionToken = M.getBundledDefaultVersionToken()
    if versionToken then
        local versionPath = sellConfigPath .. "\\" .. VERSION_MARKER
        file_safe.safeWrite(versionPath, versionToken)
    end
    -- R10: do not delete .bak on success; it is removed only after BAK_RETENTION_DAYS
    return true
end

--- Revert to bundled default: same as applyBundledDefaultLayout but used when user explicitly chooses Revert.
--- Backup/restore on failure is handled inside applyBundledDefaultLayout.
function M.revertToBundledDefaultLayout()
    return M.applyBundledDefaultLayout()
end

return M
