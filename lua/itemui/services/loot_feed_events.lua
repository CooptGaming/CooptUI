--[[
    Loot Feed Events (Task 7.8) — real-time loot feed via mq.event().
    Listens for [ItemUI Loot] name|value|tribute lines echoed by loot.mac.
    Current-tab display is deferred until macro completes (session read); events
    only append to Loot History so that tab updates as items are looted. Processed
    in main_loop's mq.doevents(). Progress bar and end-of-run session read via bridge.
]]

local mq = require('mq')
local item_name = require('itemui.utils.item_name')
local coopuiPlugin = require('itemui.utils.coopui_plugin')
local dbg = require('itemui.core.debug').channel('Loot')

local M = {}
local deps
local diagnostics

-- Pattern: [ItemUI Loot] name|value|tribute (value and tribute are numbers; name may not contain |)
local EVENT_NAME = "ItemUILootItem"
local LINE_PATTERN = "#*#[ItemUI Loot] #*#"

local function isPluginIpcAvailable()
    return coopuiPlugin.getIPC() ~= nil
end

local function onLootItemLine(line)
    if not line or type(line) ~= "string" then return end
    local payload = line:match("%[ItemUI Loot%]%s*(.+)$")
    if not payload or payload == "" then return end
    local parts = {}
    for part in (payload .. "|"):gmatch("(.-)|") do
        parts[#parts + 1] = part
    end
    if #parts < 3 then return end
    local name = item_name.normalizeItemName(parts[1])
    if name == "" then return end
    local value = tonumber(parts[2]) or 0
    local tribute = tonumber(parts[3]) or 0

    local uiState = deps and deps.uiState
    local getSellStatusForItem = deps and deps.getSellStatusForItem
    local LOOT_HISTORY_MAX = (deps and deps.LOOT_HISTORY_MAX) or 100
    if not uiState then return end

    local statusText, willSell = "—", false
    if getSellStatusForItem then
        statusText, willSell = getSellStatusForItem({ name = name })
        if statusText == "" then statusText = "—" end
    end

    -- Current tab is populated only when macro completes (session read); events only update Loot History
    local hist = uiState.lootHistory
    if not hist then
        hist = {}
        uiState.lootHistory = hist
    end
    dbg.log(string.format("Loot feed: %s | value=%d | sell=%s", name, value, statusText))
    table.insert(hist, { name = name, value = value, statusText = statusText, willSell = willSell })
    local over = #hist - LOOT_HISTORY_MAX
    if over > 0 then
        table.move(hist, over + 1, #hist, 1)
        for i = #hist - over + 1, #hist do hist[i] = nil end
    end
end

function M.init(d)
    deps = d
    diagnostics = require('itemui.core.diagnostics')
    -- When plugin IPC is available, avoid registering echo-based loot feed to
    -- prevent dual ingestion (IPC + mq.event) and reduce per-item overhead.
    if isPluginIpcAvailable() then return end
    local ok, err = pcall(function()
        mq.event(EVENT_NAME, LINE_PATTERN, onLootItemLine)
    end)
    if not ok and diagnostics then
        diagnostics.recordError("loot_feed_events", "Event registration failed", tostring(err or "unknown"))
    end
end

return M
