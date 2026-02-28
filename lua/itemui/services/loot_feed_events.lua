--[[
    Loot Feed Events (Task 7.8) — real-time loot feed via mq.event().
    Listens for [ItemUI Loot] name|value|tribute lines echoed by loot.mac.
    Current-tab display is deferred until macro completes (session read); events
    only append to Loot History so that tab updates as items are looted. Processed
    in main_loop's mq.doevents(). Progress bar and end-of-run session read via bridge.
]]

local mq = require('mq')

local M = {}
local deps
local diagnostics

-- Pattern: [ItemUI Loot] name|value|tribute (value and tribute are numbers; name may not contain |)
local EVENT_NAME = "ItemUILootItem"
local LINE_PATTERN = "#*#[ItemUI Loot] #*#"

local function onLootItemLine(line)
    if not line or type(line) ~= "string" then return end
    local payload = line:match("%[ItemUI Loot%]%s*(.+)$")
    if not payload or payload == "" then return end
    local parts = {}
    for part in (payload .. "|"):gmatch("(.-)|") do
        parts[#parts + 1] = part
    end
    if #parts < 3 then return end
    local name = (parts[1] and parts[1]:match("^%s*(.-)%s*$")) or ""
    if name == "" then return end
    local value = tonumber(parts[2]) or 0
    local tribute = tonumber(parts[3]) or 0

    local uiState = deps and deps.uiState
    local getSellStatusForItem = deps and deps.getSellStatusForItem
    local LOOT_HISTORY_MAX = (deps and deps.LOOT_HISTORY_MAX) or 200
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
    table.insert(hist, { name = name, value = value, statusText = statusText, willSell = willSell })
    while #hist > LOOT_HISTORY_MAX do table.remove(hist, 1) end
end

function M.init(d)
    deps = d
    diagnostics = require('itemui.core.diagnostics')
    local ok, err = pcall(function()
        mq.event(EVENT_NAME, LINE_PATTERN, onLootItemLine)
    end)
    if not ok and diagnostics then
        diagnostics.recordError("loot_feed_events", "Event registration failed", tostring(err or "unknown"))
    end
end

return M
