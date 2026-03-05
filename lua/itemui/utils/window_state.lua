--[[
    ItemUI - Window State Utilities
    EQ window open/close queries and helpers.
    Part of CoOpt UI — EverQuest EMU Companion
    Phase D: uses coopui.window.isWindowOpen when plugin is loaded (TLO fallback).
--]]

local mq = require('mq')

local M = {}

-- Cache plugin window table when available (nil or table with isWindowOpen).
local function getPluginWindow()
    if M._pluginWindow ~= nil then return M._pluginWindow end
    local ok, mod = pcall(require, "plugin.MQ2CoOptUI")
    local w = (ok and mod and type(mod) == "table" and mod.window and type(mod.window.isWindowOpen) == "function") and mod.window or nil
    M._pluginWindow = w
    return w
end

local function isWindowOpen(name)
    local plugin = getPluginWindow()
    if plugin then return plugin.isWindowOpen(name) end
    local w = mq.TLO and mq.TLO.Window and mq.TLO.Window(name)
    return w and w.Open and w.Open() or false
end

function M.isBankWindowOpen()
    return isWindowOpen("BigBankWnd")
end

function M.isMerchantWindowOpen()
    return isWindowOpen("MerchantWnd")
end

function M.isLootWindowOpen()
    return isWindowOpen("LootWnd")
end

--- True if the game inventory window is open (one of the 4 main windows supported by plugin).
function M.isInventoryWindowOpen()
    return isWindowOpen("InventoryWindow")
end

--- Close the default EQ inventory window (and bags) if open.
function M.closeGameInventoryIfOpen()
    if M.isInventoryWindowOpen() then
        mq.cmd("/keypress inventory")
    end
end

--- Close the default EQ bank window if open.
function M.closeGameBankIfOpen()
    if isWindowOpen("BigBankWnd") then
        mq.cmd("/invoke ${Window[BigBankWnd].DoClose}")
    end
end

--- Close the default EQ merchant window if open (for clean close when leaving sell view).
function M.closeGameMerchantIfOpen()
    if isWindowOpen("MerchantWnd") then
        -- Use DoClose (MQ window method); more reliable than /notify on some clients/custom UIs
        mq.cmd("/invoke ${Window[MerchantWnd].DoClose}")
    end
end

return M
