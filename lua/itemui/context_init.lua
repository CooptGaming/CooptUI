--[[
    Context init: wires the dependency map into itemui.context.
    init(refs) calls context.init(refs). app.lua builds refs and passes them here.
]]

local context = require('itemui.context')

local M = {}

function M.init(refs)
    context.init(refs)
end

return M
