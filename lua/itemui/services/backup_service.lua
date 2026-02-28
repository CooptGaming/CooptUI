--[[
    Full settings backup and restore (Task 8.3).
    Export: package folder with manifest. Import: copy to MQ root with .bak backup before overwrite.
    In scope: Macros/sell_config, shared_config, loot_config (.ini and .lua). Out of scope: Lua source, macros, binaries.

    Defaults process: To update shipped defaults, configure a clean CoOpt UI instance as desired,
    run Export from Settings > Advanced > Backup & Restore, then place the resulting package
    in the repo defaults/ folder. Welcome (8.2) and patcher (3.5) can apply this package on first run.
]]

local mq = require('mq')
local M = {}
local config
local function getConfig()
    if not config then config = require('itemui.config') end
    return config
end

local SCHEMA_VERSION = 1
local MANIFEST_FILENAME = "coopui_backup_manifest.json"
local BAK_FOLDER = "coopui_backup_restore.bak"

local function getMQRoot()
    local p = mq.TLO and mq.TLO.MacroQuest and mq.TLO.MacroQuest.Path and mq.TLO.MacroQuest.Path()
    if not p or p == "" then return nil end
    return (p:gsub("/", "\\"))
end

local function collectRelativePaths(root, relBase, extList)
    local out = {}
    local function scan(dir, base)
        local ok, entries = pcall(function()
            local t = {}
            if not io or not io.popen then return t end
            local h = io.popen('dir /b /s "' .. dir:gsub('"', '\\"') .. '" 2>nul')
            if not h then return t end
            for line in h:lines() do
                local full = line:gsub("/", "\\")
                if full:sub(1, #root) == root then
                    local rel = full:sub(#root + 2)
                    local ext = rel:match("%.(%w+)$")
                    if ext and (ext == "ini" or ext == "lua") then
                        t[#t + 1] = rel
                    end
                end
            end
            h:close()
            return t
        end)
        if ok and entries then
            for _, rel in ipairs(entries) do out[#out + 1] = rel end
        else
            -- Fallback: no dir/popen, use known files from config paths
            local cfg = getConfig()
            if relBase == "Macros\\sell_config" then
                for _, f in ipairs({ "itemui_layout.ini", "sell_flags.ini", "sell_value.ini", "keep_list.lua", "junk_list.lua" }) do
                    out[#out + 1] = relBase .. "\\" .. f
                end
            elseif relBase == "Macros\\shared_config" then
                for _, f in ipairs({ "epic_classes.ini" }) do out[#out + 1] = relBase .. "\\" .. f end
            elseif relBase == "Macros\\loot_config" then
                for _, f in ipairs({ "loot_flags.ini", "loot_value.ini", "always_loot_list.lua", "skip_list.lua" }) do out[#out + 1] = relBase .. "\\" .. f end
            end
        end
        return out
    end
    local subDir = root .. "\\" .. (relBase:gsub("/", "\\"))
    scan(subDir, relBase)
    return out
end

local function safeReadAll(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function safeWriteAll(path, content)
    local dir = path:match("^(.+)\\[^\\]+$")
    if dir and os and os.execute then
        pcall(function() os.execute('mkdir "' .. dir:gsub('"', '\\"') .. '" 2>nul') end)
    end
    local f = io.open(path, "wb")
    if not f then return false, "could not write " .. path end
    f:write(content or "")
    f:close()
    return true
end

--- Build file list under sell_config, shared_config, loot_config (ini + lua only).
local function listInScopeFiles(root)
    root = root:gsub("/", "\\")
    local files = {}
    local seen = {}
    for _, base in ipairs({ "Macros\\sell_config", "Macros\\shared_config", "Macros\\loot_config" }) do
        local sub = root .. "\\" .. base
        local ok, list = pcall(function()
            local L = {}
            local h = io.popen('dir /b /s "' .. sub:gsub('"', '\\"') .. '" 2>nul')
            if h then
                for line in h:lines() do
                    local full = line:gsub("/", "\\")
                    if full:sub(1, #root) == root then
                        local rel = full:sub(#root + 2)
                        local ext = rel:match("%.(%w+)$")
                        if ext and (ext:lower() == "ini" or ext:lower() == "lua") and not seen[rel] then
                            seen[rel] = true
                            L[#L + 1] = rel
                        end
                    end
                end
                h:close()
            end
            return L
        end)
        if ok and list then
            for _, rel in ipairs(list) do files[#files + 1] = rel end
        end
    end
    if #files == 0 then
        -- Minimal list when dir fails
        for _, rel in ipairs({
            "Macros\\sell_config\\itemui_layout.ini",
            "Macros\\sell_config\\sell_flags.ini",
            "Macros\\sell_config\\sell_value.ini",
            "Macros\\shared_config\\epic_classes.ini",
            "Macros\\loot_config\\loot_flags.ini",
            "Macros\\loot_config\\loot_value.ini",
        }) do
            if not seen[rel] then files[#files + 1] = rel end
        end
    end
    return files
end

--- Export package to outputPath (folder). Creates manifest and copies in-scope files.
function M.exportPackage(outputPath)
    local root = getMQRoot()
    if not root then return false, "MacroQuest path not available" end
    outputPath = (outputPath or ""):gsub("/", "\\")
    if outputPath == "" then return false, "No output path" end
    local files = listInScopeFiles(root)
    local manifest = { schemaVersion = SCHEMA_VERSION, files = {} }
    for _, rel in ipairs(files) do
        manifest.files[#manifest.files + 1] = { relativePath = rel }
    end
    local manifestJson = "{\"schemaVersion\":" .. tostring(SCHEMA_VERSION) .. ",\"files\":["
    for i, e in ipairs(manifest.files) do
        if i > 1 then manifestJson = manifestJson .. "," end
        manifestJson = manifestJson .. "{\"relativePath\":\"" .. (e.relativePath:gsub("\\", "\\\\"):gsub('"', '\\"')) .. "\"}"
    end
    manifestJson = manifestJson .. "]}"
    local manifestOutPath = outputPath .. "\\" .. MANIFEST_FILENAME
    local ok, err = safeWriteAll(manifestOutPath, manifestJson)
    if not ok then return false, err end
    for _, rel in ipairs(files) do
        local src = root .. "\\" .. rel
        local content = safeReadAll(src)
        if content then
            local dst = outputPath .. "\\" .. rel
            ok, err = safeWriteAll(dst, content)
            if not ok then return false, err end
        end
    end
    return true, #files
end

--- Import package from inputPath. Backs up existing files to BAK_FOLDER, then copies from package.
function M.importPackage(inputPath)
    local root = getMQRoot()
    if not root then return false, "MacroQuest path not available" end
    inputPath = (inputPath or ""):gsub("/", "\\")
    if inputPath == "" then return false, "No input path" end
    local manifestPath = inputPath .. "\\" .. MANIFEST_FILENAME
    local raw = safeReadAll(manifestPath)
    if not raw or raw == "" then return false, "Manifest not found or empty" end
    local schemaVersion = tonumber(raw:match('"schemaVersion"%s*:%s*(%d+)'))
    if not schemaVersion or schemaVersion > SCHEMA_VERSION then
        return false, "Unsupported or unknown manifest schema"
    end
    local files = {}
    for rel in raw:gmatch('"relativePath"%s*:%s*"([^"]+)"') do
        rel = rel:gsub("\\\\", "\\")
        files[#files + 1] = rel
    end
    local bakRoot = root .. "\\" .. (BAK_FOLDER:gsub("/", "\\"))
    local manifestContent = safeReadAll(inputPath .. "\\" .. MANIFEST_FILENAME)
    if manifestContent then safeWriteAll(bakRoot .. "\\" .. MANIFEST_FILENAME, manifestContent) end
    local failures = {}
    for _, rel in ipairs(files) do
        local src = inputPath .. "\\" .. rel
        local dst = root .. "\\" .. rel
        local content = safeReadAll(src)
        if not content then
            failures[#failures + 1] = rel .. " (read failed)"
        else
            local existing = safeReadAll(dst)
            if existing and #existing > 0 then
                local bakPath = bakRoot .. "\\" .. rel
                safeWriteAll(bakPath, existing)
            end
            local ok, err = safeWriteAll(dst, content)
            if not ok then failures[#failures + 1] = rel .. " (" .. tostring(err) .. ")" end
        end
    end
    if #failures > 0 then
        return false, "Some files failed: " .. table.concat(failures, "; ")
    end
    return true, #files
end

--- Returns true if a previous import created a .bak folder we can restore from.
function M.hasRestoreBackup()
    local root = getMQRoot()
    if not root then return false end
    local bakPath = root .. "\\" .. (BAK_FOLDER:gsub("/", "\\")) .. "\\. "
    local f = io.open(bakPath, "r")
    if f then f:close(); return true end
    return false
end

--- Restore from coopui_backup_restore.bak into live paths (reverse of import backup).
function M.restoreFromBackup()
    local root = getMQRoot()
    if not root then return false, "MacroQuest path not available" end
    local bakRoot = root .. "\\" .. (BAK_FOLDER:gsub("/", "\\"))
    local manifestPath = bakRoot .. "\\" .. MANIFEST_FILENAME
    local raw = safeReadAll(manifestPath)
    local files = {}
    if raw and raw ~= "" then
        for rel in raw:gmatch('"relativePath"%s*:%s*"([^"]+)"') do
            rel = rel:gsub("\\\\", "\\")
            files[#files + 1] = rel
        end
    end
    if #files == 0 then
        local h = io.popen('dir /b /s "' .. bakRoot:gsub('"', '\\"') .. '" 2>nul')
        if h then
            for line in h:lines() do
                local full = line:gsub("/", "\\")
                if full:sub(1, #bakRoot) == bakRoot then
                    local rel = full:sub(#bakRoot + 2)
                    if rel ~= "\\" .. MANIFEST_FILENAME and (rel:match("%.ini$") or rel:match("%.lua$")) then
                        files[#files + 1] = rel
                    end
                end
            end
            h:close()
        end
    end
    local failures = {}
    for _, rel in ipairs(files) do
        local src = bakRoot .. "\\" .. rel
        local dst = root .. "\\" .. rel
        local content = safeReadAll(src)
        if content then
            local ok, err = safeWriteAll(dst, content)
            if not ok then failures[#failures + 1] = rel end
        end
    end
    if #failures > 0 then
        return false, "Some restores failed: " .. table.concat(failures, "; ")
    end
    return true, #files
end

--- Preview: list relative paths that would be overwritten by importing from inputPath.
function M.previewImport(inputPath)
    local root = getMQRoot()
    if not root then return nil, "MacroQuest path not available" end
    inputPath = (inputPath or ""):gsub("/", "\\")
    local manifestPath = inputPath .. "\\" .. MANIFEST_FILENAME
    local raw = safeReadAll(manifestPath)
    if not raw or raw == "" then return nil, "Manifest not found" end
    local wouldOverwrite = {}
    for rel in raw:gmatch('"relativePath"%s*:%s*"([^"]+)"') do
        rel = rel:gsub("\\\\", "\\")
        local dst = root .. "\\" .. rel
        local f = io.open(dst, "r")
        if f then
            f:close()
            wouldOverwrite[#wouldOverwrite + 1] = rel
        end
    end
    return wouldOverwrite
end

M.BAK_FOLDER = BAK_FOLDER
return M
