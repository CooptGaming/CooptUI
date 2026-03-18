--[[
    CoOpt UI — Shared plugin loader utility.
    Single cached require for MQ2CoOptUI (falls back to legacy CoopUIHelper).
    All consumers use these accessors instead of duplicating pcall/require logic.
    Pattern: one-shot detection per session; result cached as module-level var.
--]]

local _plugin = nil      -- false = checked and unavailable; table = loaded module
local _ipc    = nil
local _ini    = nil
local _window = nil
local _cursor = nil
local _items  = nil

--- Return the full plugin module table, or nil if unavailable.
local function getPlugin()
    if _plugin ~= nil then return _plugin or nil end
    local ok, mod = pcall(require, "plugin.MQ2CoOptUI")
    if not ok or not mod or type(mod) ~= "table" then
        ok, mod = pcall(require, "plugin.CoopUIHelper")
    end
    _plugin = (ok and mod and type(mod) == "table") and mod or false
    return _plugin or nil
end

--- Return plugin IPC sub-module (ipc.receiveAll, send, etc.) or nil.
local function getIPC()
    if _ipc ~= nil then return _ipc or nil end
    local p = getPlugin()
    _ipc = (p and p.ipc and type(p.ipc.receiveAll) == "function") and p.ipc or false
    return _ipc or nil
end

--- Return plugin INI sub-module (readSection, read) or nil.
local function getINI()
    if _ini ~= nil then return _ini or nil end
    local p = getPlugin()
    _ini = (p and p.ini and type(p.ini.readSection) == "function") and p.ini or false
    return _ini or nil
end

--- Return plugin window sub-module (isWindowOpen) or nil.
local function getWindow()
    if _window ~= nil then return _window or nil end
    local p = getPlugin()
    _window = (p and p.window and type(p.window.isWindowOpen) == "function") and p.window or false
    return _window or nil
end

--- Return plugin cursor sub-module or nil.
local function getCursor()
    if _cursor ~= nil then return _cursor or nil end
    local p = getPlugin()
    _cursor = (p and p.cursor) and p.cursor or false
    return _cursor or nil
end

--- Return plugin items sub-module or nil.
local function getItems()
    if _items ~= nil then return _items or nil end
    local p = getPlugin()
    _items = (p and p.items) and p.items or false
    return _items or nil
end

return {
    getPlugin = getPlugin,
    getIPC    = getIPC,
    getINI    = getINI,
    getWindow = getWindow,
    getCursor = getCursor,
    getItems  = getItems,
}
