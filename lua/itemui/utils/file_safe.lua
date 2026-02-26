--[[
    ItemUI Safe File I/O
    Wraps file read/write in pcall so failures (permissions, disk full, missing path)
    do not throw and break the main loop. Use for storage and layout persistence.
--]]

local diagnostics_ok, diagnostics = pcall(require, 'itemui.core.diagnostics')
local M = {}

--- Write content to path. Returns true on success, false on error (logs once).
function M.safeWrite(path, content)
    if not path or type(path) ~= "string" or path == "" then
        return false
    end
    content = content or ""
    local ok, err = pcall(function()
        local f = io.open(path, "w")
        if not f then
            error("io.open failed")
        end
        f:write(content)
        f:close()
    end)
    if not ok then
        if print then
            print(string.format("\ar[ItemUI]\ax safeWrite failed: %s", path))
            if err and err ~= "io.open failed" then
                print(string.format("\ar[ItemUI]\ax %s", tostring(err)))
            end
        end
        if diagnostics_ok and diagnostics and diagnostics.recordError then
            diagnostics.recordError("File", "Write failed: " .. tostring(path), err)
        end
        return false
    end
    return true
end

--- Read entire file. Returns content string or nil on error (no log; caller may treat as empty).
function M.safeReadAll(path)
    if not path or type(path) ~= "string" or path == "" then
        return nil
    end
    local content = nil
    local ok = pcall(function()
        local f = io.open(path, "r")
        if not f then
            return
        end
        content = f:read("*all")
        f:close()
    end)
    if not ok or not content then
        return nil
    end
    return content
end

return M
