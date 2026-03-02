--[[
    Script consume verification: count "[timestamp] You gained 1 alternate currency." chat lines.
    Main loop does one consume, waits for this message (or timeout), then does the next.
]]

local mq = require('mq')

local M = {}
local deps

local EVENT_NAME = "ItemUIScriptConsumeGained"
-- Match EQ chat: "[timestamp] You gained 1 alternate currency."
local LINE_PATTERN = "#*#gained#*#alternate currency#*#"

local function onGainedAlternateCurrency()
    local uiState = deps and deps.uiState
    if not uiState or not uiState.pendingScriptConsume then return end
    local ps = uiState.pendingScriptConsume
    ps.verifiedFromChat = (ps.verifiedFromChat or 0) + 1
end

function M.init(d)
    deps = d
    local ok, err = pcall(function()
        mq.event(EVENT_NAME, LINE_PATTERN, onGainedAlternateCurrency)
    end)
    if not ok and deps and deps.diagnostics then
        deps.diagnostics.recordError("script_consume_events", "Event registration failed", tostring(err or "unknown"))
    end
end

return M
