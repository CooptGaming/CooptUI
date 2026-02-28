--[[
    CoOpt UI Backup & Restore (Task 8.3).
    Export: copy sell_config, shared_config, loot_config INI files to a folder.
    Import: copy from folder into config dirs, backing up existing files to coopui_backup_restore.bak first.
]]

local config = require('itemui.config')
local mq = require('mq')

local BAK_SUBDIR = "coopui_backup_restore.bak"

-- Manifest: { dir = "sell_config"|"shared_config"|"loot_config", file = "name.ini" }
-- Paths in export/import folder use subdirs: exportPath/sell_config/..., exportPath/shared_config/..., exportPath/loot_config/...
local MANIFEST = {
    { dir = "sell_config", file = "itemui_layout.ini" },
    { dir = "sell_config", file = "sell_flags.ini" },
    { dir = "sell_config", file = "sell_value.ini" },
    { dir = "sell_config", file = "sell_keep_exact.ini" },
    { dir = "sell_config", file = "sell_keep_contains.ini" },
    { dir = "sell_config", file = "sell_keep_types.ini" },
    { dir = "sell_config", file = "sell_always_sell_exact.ini" },
    { dir = "sell_config", file = "sell_always_sell_contains.ini" },
    { dir = "sell_config", file = "sell_protected_types.ini" },
    { dir = "sell_config", file = "sell_augment_always_sell_exact.ini" },
    { dir = "sell_config", file = "itemui_filter_presets.ini" },
    { dir = "sell_config", file = "itemui_last_filters.ini" },
    { dir = "shared_config", file = "valuable_exact.ini" },
    { dir = "shared_config", file = "valuable_contains.ini" },
    { dir = "shared_config", file = "valuable_types.ini" },
    { dir = "shared_config", file = "epic_classes.ini" },
    { dir = "shared_config", file = "epic_items_resolved.ini" },
    { dir = "loot_config", file = "loot_flags.ini" },
    { dir = "loot_config", file = "loot_value.ini" },
    { dir = "loot_config", file = "loot_sorting.ini" },
    { dir = "loot_config", file = "loot_always_exact.ini" },
    { dir = "loot_config", file = "loot_always_contains.ini" },
    { dir = "loot_config", file = "loot_always_types.ini" },
    { dir = "loot_config", file = "loot_skip_exact.ini" },
    { dir = "loot_config", file = "loot_skip_contains.ini" },
    { dir = "loot_config", file = "loot_skip_types.ini" },
    { dir = "loot_config", file = "loot_augment_skip_exact.ini" },
}

local function getPath(dir, file)
    if dir == "sell_config" then return config.getConfigFile(file)
    elseif dir == "shared_config" then return config.getSharedConfigFile(file)
    elseif dir == "loot_config" then return config.getLootConfigFile(file)
    end
    return nil
end

local function normalizePath(p)
    if not p or p == "" then return "" end
    return (p:gsub("/", "\\")):gsub("\\+$", "")
end

local function ensureDir(dirPath)
    if not dirPath or dirPath == "" then return false end
    dirPath = normalizePath(dirPath)
    if os and os.execute then
        -- Create parent path; simple approach: create each segment.
        local parts = {}
        for part in (dirPath:gsub("\\", "\0") .. "\0"):gmatch("(.-)%z") do
            if part ~= "" then parts[#parts + 1] = part end
        end
        local acc = ""
        for i = 1, #parts do
            if i == 1 and (parts[1]:match("^[A-Za-z]:$") or parts[1] == "") then
                acc = parts[1]
            else
                acc = acc == "" and parts[i] or (acc .. "\\" .. parts[i])
                os.execute('mkdir "' .. acc:gsub('"', '\\"') .. '" 2>nul')
            end
        end
        return true
    end
    return false
end

local function copyFile(src, dst)
    if not src or not dst or not io or not io.open then return false, "io not available" end
    local f = io.open(src, "rb")
    if not f then return false, "cannot read source" end
    local content = f:read("*a")
    f:close()
    if not content then return false, "read failed" end
    local dir = dst:match("^(.+)\\[^\\]+$")
    if dir and dir ~= "" then ensureDir(dir) end
    local out = io.open(dst, "wb")
    if not out then return false, "cannot write destination" end
    out:write(content)
    out:close()
    return true
end

local function fileExists(path)
    if not path or path == "" then return false end
    local f = io and io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

--- Export all manifest files to exportPath. Creates sell_config/, shared_config/, loot_config/ under exportPath.
--- Returns ok, countOrError.
function exportPackage(exportPath)
    if not exportPath or exportPath == "" then return false, "Export path is empty" end
    local root = normalizePath(exportPath)
    local count = 0
    for _, e in ipairs(MANIFEST) do
        local src = getPath(e.dir, e.file)
        if src and fileExists(src) then
            local dst = root .. "\\" .. e.dir .. "\\" .. e.file
            local ok, err = copyFile(src, dst)
            if not ok then return false, err or "copy failed" end
            count = count + 1
        end
    end
    return true, count
end

--- Return path to the .bak folder (under sell_config).
local function getBakRoot()
    local base = mq.TLO and mq.TLO.MacroQuest and mq.TLO.MacroQuest.Path and mq.TLO.MacroQuest.Path()
    if not base or base == "" then return nil end
    base = (base:gsub("/", "\\")):gsub("\\+$", "")
    return base .. "\\Macros\\sell_config\\" .. BAK_SUBDIR
end

--- Check if a previous import created a backup (so we can offer Restore Previous).
function hasRestoreBackup()
    local bakRoot = getBakRoot()
    if not bakRoot then return false end
    return fileExists(bakRoot .. "\\sell_config\\itemui_layout.ini") or fileExists(bakRoot .. "\\shared_config\\valuable_exact.ini") or fileExists(bakRoot .. "\\loot_config\\loot_flags.ini")
end

--- Restore from .bak into live config. Returns ok, countOrError.
function restoreFromBackup()
    local bakRoot = getBakRoot()
    if not bakRoot or not fileExists(bakRoot) then return false, "No backup found" end
    local count = 0
    for _, e in ipairs(MANIFEST) do
        local bakFile = bakRoot .. "\\" .. e.dir .. "\\" .. e.file
        if fileExists(bakFile) then
            local dst = getPath(e.dir, e.file)
            if dst then
                local ok, err = copyFile(bakFile, dst)
                if not ok then return false, err or "restore copy failed" end
                count = count + 1
            end
        end
    end
    return true, count
end

--- Preview import: list relative paths that would be overwritten. Returns list of "dir/file" or nil, error.
function previewImport(importPath)
    if not importPath or importPath == "" then return nil, "Import path is empty" end
    local root = normalizePath(importPath)
    local list = {}
    for _, e in ipairs(MANIFEST) do
        local src = root .. "\\" .. e.dir .. "\\" .. e.file
        if fileExists(src) then
            list[#list + 1] = e.dir .. "\\" .. e.file
        end
    end
    return list
end

--- Import from folder: backup existing files to .bak then copy from importPath. Returns ok, countOrError.
function importPackage(importPath)
    if not importPath or importPath == "" then return false, "Import path is empty" end
    local root = normalizePath(importPath)
    local bakRoot = getBakRoot()
    if not bakRoot then return false, "MQ path not available" end
    for _, e in ipairs(MANIFEST) do
        local dst = getPath(e.dir, e.file)
        if dst and fileExists(dst) then
            local bakFile = bakRoot .. "\\" .. e.dir .. "\\" .. e.file
            ensureDir(bakFile:match("^(.+)\\[^\\]+$"))
            copyFile(dst, bakFile)
        end
    end
    local count = 0
    for _, e in ipairs(MANIFEST) do
        local src = root .. "\\" .. e.dir .. "\\" .. e.file
        if fileExists(src) then
            local dst = getPath(e.dir, e.file)
            if dst then
                ensureDir(dst:match("^(.+)\\[^\\]+$"))
                local ok, err = copyFile(src, dst)
                if not ok then return false, err or "import copy failed" end
                count = count + 1
            end
        end
    end
    return true, count
end

return {
    exportPackage = exportPackage,
    importPackage = importPackage,
    hasRestoreBackup = hasRestoreBackup,
    restoreFromBackup = restoreFromBackup,
    previewImport = previewImport,
}
