--[[
    ItemUI - Window State Utilities
    EQ window open/close queries and helpers.
    Part of CoopUI — EverQuest EMU Companion
--]]

local mq = require('mq')

local M = {}

function M.isBankWindowOpen()
    local w = mq.TLO and mq.TLO.Window and mq.TLO.Window("BigBankWnd")
    return w and w.Open and w.Open() or false
end

function M.isMerchantWindowOpen()
    local w = mq.TLO and mq.TLO.Window and mq.TLO.Window("MerchantWnd")
    return w and w.Open and w.Open() or false
end

function M.isLootWindowOpen()
    local w = mq.TLO and mq.TLO.Window and mq.TLO.Window("LootWnd")
    return w and w.Open and w.Open() or false
end

--- Close the default EQ inventory window (and bags) if open.
function M.closeGameInventoryIfOpen()
    local invWnd = mq.TLO and mq.TLO.Window and mq.TLO.Window("InventoryWindow")
    if invWnd and invWnd.Open and invWnd.Open() then
        mq.cmd("/keypress inventory")
    end
end

return M
