--[[
    Welcome environment manifest (Task 8.2).
    Validates MQ path, config dirs, and layout INI so the tutorial can run without red validation.
]]

local mq = require('mq')
local M = {}

-- Manifest of checks: id, label, and optional fix (create dir / minimal file).
M.manifest = {
    { id = "mq_path",       label = "MacroQuest path" },
    { id = "sell_config",   label = "Sell config folder" },
    { id = "shared_config", label = "Shared config folder" },
    { id = "loot_config",   label = "Loot config folder" },
    { id = "itemui_layout", label = "Layout INI" },
}

local function getBasePath()
    local p = mq.TLO and mq.TLO.MacroQuest and mq.TLO.MacroQuest.Path and mq.TLO.MacroQuest.Path()
    if not p or p == "" then return nil end
    return (p:gsub("/", "\\")):gsub("\\+$", "")
end

local function ensureDir(dirPath)
    if not dirPath or dirPath == "" then return false end
    if not os or not os.execute then return false end
    dirPath = dirPath:gsub("/", "\\")
    os.execute('mkdir "' .. dirPath:gsub('"', '\\"') .. '" 2>nul')
    return true
end

local function dirExists(path)
    if not path or not io or not io.popen then return false end
    local f = io.popen('if exist "' .. path:gsub('"', '\\"') .. '\\" echo 1')
    local s = f and f:read("*a")
    f = f and f:close()
    return s and s:match("1")
end

local function fileExists(path)
    if not path or path == "" then return false end
    local f = io and io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

--- Run validation once. Returns list of { id = string, status = "ok"|"created"|"failed", message = string }.
function M.validate()
    local results = {}
    local base = getBasePath()
    -- MQ path
    if base and base ~= "" then
        results[#results + 1] = { id = "mq_path", status = "ok", message = "Path set" }
    else
        results[#results + 1] = { id = "mq_path", status = "failed", message = "MacroQuest path not available" }
    end
    -- Config dirs (create if missing)
    for _, id in ipairs({ "sell_config", "shared_config", "loot_config" }) do
        local sub = (id == "sell_config") and "Macros\\sell_config" or (id == "shared_config") and "Macros\\shared_config" or "Macros\\loot_config"
        local full = base and (base .. "\\" .. sub) or ""
        if full == "" then
            results[#results + 1] = { id = id, status = "failed", message = "Skip (no MQ path)" }
        elseif dirExists(full) then
            results[#results + 1] = { id = id, status = "ok", message = "Present" }
        else
            ensureDir(full)
            if dirExists(full) then
                results[#results + 1] = { id = id, status = "created", message = "Created" }
            else
                results[#results + 1] = { id = id, status = "failed", message = "Could not create" }
            end
        end
    end
    -- itemui_layout.ini
    local layoutPath = base and (base .. "\\Macros\\sell_config\\itemui_layout.ini") or ""
    if layoutPath == "" then
        results[#results + 1] = { id = "itemui_layout", status = "failed", message = "Skip (no MQ path)" }
    elseif fileExists(layoutPath) then
        results[#results + 1] = { id = "itemui_layout", status = "ok", message = "Present" }
    else
        local dir = layoutPath:match("^(.+)\\[^\\]+$")
        if dir and dirExists(dir) then
            local f = io and io.open(layoutPath, "w")
            if f then
                f:write("[Layout]\n")
                f:close()
                results[#results + 1] = { id = "itemui_layout", status = "created", message = "Created minimal INI" }
            else
                results[#results + 1] = { id = "itemui_layout", status = "failed", message = "Could not create" }
            end
        else
            results[#results + 1] = { id = "itemui_layout", status = "failed", message = "Sell config folder missing" }
        end
    end
    return results
end

return M
