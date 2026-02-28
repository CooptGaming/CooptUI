--[[
    Plugin shim — single point of plugin detection and fallback (Task 6.1).
    require("plugin.MQ2CoOptUI") is tried once; all capability access goes through here.
--]]

local mq = require('mq')
local constants = require('itemui.constants')

local M = {}
local plugin = nil
local detected = false

function M.init()
    if detected then return end
    local ok, mod = pcall(require, "plugin.MQ2CoOptUI")
    if ok and mod and type(mod) == "table" then
        local apiVer = mq.TLO.CoOptUI and mq.TLO.CoOptUI.APIVersion and mq.TLO.CoOptUI.APIVersion()
        local requiredVer = constants.PLUGIN_REQUIRED_API_VERSION or 1
        if apiVer and apiVer >= requiredVer then
            plugin = mod
            print("\ag[CoOpt UI]\ax Plugin MQ2CoOptUI v" ..
                (mq.TLO.CoOptUI.Version and mq.TLO.CoOptUI.Version() or "?") ..
                " loaded (API " .. tostring(apiVer) .. ")")
        else
            print("\ay[CoOpt UI]\ax Plugin API version mismatch (have " ..
                tostring(apiVer) .. ", need " .. tostring(requiredVer) ..
                "). Using Lua fallback.")
        end
    end
    detected = true
end

function M.isLoaded()
    return plugin ~= nil
end

function M.get()
    return plugin
end

function M.ipc()    return plugin and plugin.ipc    end
function M.window() return plugin and plugin.window end
function M.items()  return plugin and plugin.items  end
function M.loot()   return plugin and plugin.loot   end
function M.ini()    return plugin and plugin.ini    end

return M
