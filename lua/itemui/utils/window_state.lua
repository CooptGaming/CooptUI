--[[
    ItemUI - Window State Utilities
    EQ window open/close queries and helpers.
    Part of CoOpt UI — EverQuest EMU Companion
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

--- Close the default EQ merchant window if open (for clean close when leaving sell view).
function M.closeGameMerchantIfOpen()
    local w = mq.TLO and mq.TLO.Window and mq.TLO.Window("MerchantWnd")
    if w and w.Open and w.Open() then
        -- Use DoClose (MQ window method); more reliable than /notify on some clients/custom UIs
        mq.cmd("/invoke ${Window[MerchantWnd].DoClose}")
    end
end

return M
