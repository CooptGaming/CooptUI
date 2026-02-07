--[[
    ItemUI Context
    Single registry + buildViewContext/extendContext for view modules.
    Keeps build() under Lua's 60 upvalue limit by closing only over refs.
    Usage: context.init(refs) once from init.lua, then context.build(), context.extend(ctx).
--]]

local M = {}
local refs

function M.init(r)
    refs = r
end

function M.build()
    return setmetatable({}, { __index = refs })
end

function M.extend(ctx)
    return ctx
end

--- Return upvalue count for a function (requires debug library).
function M.getUpvalueCount(fn)
    if not debug or not debug.getupvalue then return nil end
    local count = 0
    while true do
        local name = debug.getupvalue(fn, count + 1)
        if not name then break end
        count = count + 1
    end
    return count
end

--- Log upvalue count for build/extend when UPVALUE_DEBUG is true.
function M.logUpvalueCounts(C)
    if not C or not C.UPVALUE_DEBUG then return end
    local n = M.getUpvalueCount(M.build)
    if n then
        print(string.format("[ItemUI] Upvalue count for buildViewContext: %d", n))
        if n >= 60 then
            print(string.format("[ItemUI] WARNING: buildViewContext has %d upvalues (limit 60)", n))
        end
    end
    n = M.getUpvalueCount(M.extend)
    if n then
        print(string.format("[ItemUI] Upvalue count for extendContext: %d", n))
        if n >= 60 then
            print(string.format("[ItemUI] WARNING: extendContext has %d upvalues (limit 60)", n))
        end
    end
end

--- CI check: returns true if build() is under 60 upvalues, else false + message.
function M.checkUpvalueLimits()
    local count = M.getUpvalueCount(M.build)
    if not count then
        return true, "debug.getupvalue not available (skip)"
    end
    if count >= 60 then
        return false, string.format("buildViewContext has %d upvalues (Lua limit 60)", count)
    end
    return true, string.format("buildViewContext upvalues: %d (OK)", count)
end

return M
