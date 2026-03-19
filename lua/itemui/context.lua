--[[
    ItemUI Context
    Single registry + cached proxy for view modules.
    Keeps build() under Lua's 60 upvalue limit by closing only over refs.
    Usage: context.init(refs) once from app.lua, then context.build() each frame.
--]]

local M = {}
local refs
local proxy  -- reused every frame; safe because it's read-only via __index

function M.init(r)
    refs = r
    proxy = nil  -- reset on re-init so stale proxy isn't used across reloads
end

function M.build()
    if not proxy then
        proxy = setmetatable({}, { __index = refs })
    end
    return proxy
end

return M
