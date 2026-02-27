--[[
    Error feedback: ring buffer of recent errors for diagnostic panel (Task 5.3).
    No UI here; main_window shows indicator and panel. Call recordError() from pcall
    sites and file_safe/layout/wiring/reroll/aa/macro_bridge/loot_ui as needed.
]]

local M = {}

local MAX_ERRORS = 20
local errors = {}

--- Record an error for the diagnostic panel.
--- @param source string Short label (e.g. "Layout", "Reroll", "AA Export")
--- @param message string Human-readable message
--- @param err string|nil Optional error detail (e.g. tostring(exception))
function M.recordError(source, message, err)
    local entry = {
        timestamp = os.time(),
        source = source or "Unknown",
        message = message or "No message",
        err = (err and tostring(err)) or "",
    }
    errors[#errors + 1] = entry
    while #errors > MAX_ERRORS do
        table.remove(errors, 1)
    end
end

--- Return a copy of recent errors (newest last).
function M.getErrors()
    local out = {}
    for i = 1, #errors do out[i] = errors[i] end
    return out
end

--- Number of errors in the buffer.
function M.getErrorCount()
    return #errors
end

--- Clear the error buffer (e.g. from diagnostic panel).
function M.clearErrors()
    for i = #errors, 1, -1 do errors[i] = nil end
end

return M
