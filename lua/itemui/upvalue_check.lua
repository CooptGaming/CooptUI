--[[
    ItemUI Upvalue CI Check
    Run to verify context.build() stays under Lua's 60 upvalue limit.
    Usage: lua itemui/upvalue_check.lua   (or from MQ: /lua run itemui.upvalue_check)
    Exit code: 0 if OK, 1 if over limit or error.
--]]

local context = require('itemui.context')

-- Minimal refs so context.build() can be counted (it closes over refs only)
context.init({ _dummy = true })

local ok, msg = context.checkUpvalueLimits()
if ok then
    print("[ItemUI] Upvalue check: " .. tostring(msg))
    if os and os.exit then os.exit(0) end
else
    print("[ItemUI] Upvalue check FAILED: " .. tostring(msg))
    if os and os.exit then os.exit(1) end
end
