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

return M
