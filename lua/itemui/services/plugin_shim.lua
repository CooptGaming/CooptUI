--[[
    Plugin Shim (Task 6.1)
    Single point of plugin detection and fallback routing for MQ2CoOptUI.
    When the plugin is absent, all capability accessors return nil and callers use Lua fallback.
--]]

local mq = require('mq')
local constants = require('itemui.constants')

local M = {}
local plugin = nil
local detected = false

function M.init()
    if detected then return end
    detected = true
    -- MQ may register the Lua module as plugin.MQ2CoOptUI or plugin.CoOptUI (MQ2 prefix stripped)
    local mod
    local reqErr = nil
    local ok1, m1 = pcall(require, "plugin.MQ2CoOptUI")
    if ok1 and m1 and type(m1) == "table" then
        mod = m1
    else
        if not ok1 and m1 then reqErr = tostring(m1) end
        local ok2, m2 = pcall(require, "plugin.CoOptUI")
        if ok2 and m2 and type(m2) == "table" then
            mod = m2
        elseif not ok2 and m2 and not reqErr then
            reqErr = tostring(m2)
        end
    end
    if mod then
        local apiVer = mq.TLO.CoOptUI and mq.TLO.CoOptUI.APIVersion and mq.TLO.CoOptUI.APIVersion()
        local requiredVer = (constants and constants.PLUGIN_REQUIRED_API_VERSION) or 1
        if apiVer and apiVer >= requiredVer then
            plugin = mod
            local verStr = (mq.TLO.CoOptUI and mq.TLO.CoOptUI.Version and mq.TLO.CoOptUI.Version()) or "?"
            print(string.format("\ag[CoOpt UI]\ax Plugin MQ2CoOptUI v%s loaded (API %d) — using plugin for scan, IPC, INI, window ops.", tostring(verStr), tonumber(apiVer) or 0))
        else
            print(string.format("\ay[CoOpt UI]\ax Plugin API version mismatch (have %s, need %d). Using Lua fallback.",
                tostring(apiVer or "nil"), requiredVer))
        end
    elseif mq.TLO.CoOptUI and mq.TLO.CoOptUI.Version then
        -- TLO exists but Lua module not found — plugin may not expose CreateLuaModule yet
        print("\ay[CoOpt UI]\ax CoOptUI TLO present but Lua module not found. Using Lua fallback. (Plugin may need CreateLuaModule.)")
        if reqErr and reqErr ~= "" then
            print("\ay[CoOpt UI]\ax require error: " .. reqErr)
        end
        -- Show which DLL path is actually loaded (so user can replace the right file)
        for i = 1, 32 do
            local p = mq.TLO.Plugin(i)
            if not p then break end
            local name = p.Name and p.Name()
            if name and (name:find("MQ2CoOptUI") or name:find("CoOptUI%.dll")) then
                print("\ay[CoOpt UI]\ax Loaded plugin path: " .. tostring(name))
                break
            end
        end
    end
end

function M.isLoaded()
    return plugin ~= nil
end

function M.get()
    return plugin
end

-- Capability accessors (return nil if plugin absent)
function M.ipc()    return plugin and plugin.ipc    end
function M.window() return plugin and plugin.window end
function M.items()  return plugin and plugin.items end
function M.loot()   return plugin and plugin.loot  end
function M.ini()    return plugin and plugin.ini   end

return M
