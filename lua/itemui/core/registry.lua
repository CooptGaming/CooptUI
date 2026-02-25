--[[
    Module Registry — Task 4.1 (MASTER_PLAN.md)
    Leaf module: only require('mq') and require('itemui.constants').
    Owns window lifecycle state (windowOpen, windowShouldDraw, openedAt) per registered module.
    init(opts) receives layoutConfig and companionWindowOpenedAt for enable checks and LIFO dual-write.
]]

local mq = require('mq')

local M = {}

local layoutConfig
local companionWindowOpenedAt

-- id -> { spec, windowOpen, windowShouldDraw, openedAt }
local modules = {}
local order = {}  -- registration order for stable iteration

function M.init(opts)
    layoutConfig = opts and opts.layoutConfig
    companionWindowOpenedAt = opts and opts.companionWindowOpenedAt
end

local function getState(id)
    local m = modules[id]
    if not m then return nil end
    return m.windowOpen, m.windowShouldDraw, m.openedAt
end

local function isEnabled(spec)
    if not spec.enableKey then return true end
    if not layoutConfig then return true end
    return (tonumber(layoutConfig[spec.enableKey]) or 1) ~= 0
end

function M.register(spec)
    if not spec or not spec.id then return end
    local id = spec.id
    if not modules[id] then
        order[#order + 1] = id
    end
    modules[id] = {
        spec = spec,
        windowOpen = false,
        windowShouldDraw = false,
        openedAt = nil,
    }
    local m = modules[id]
    local function isOpen()
        return m.windowOpen
    end
    local function shouldDraw()
        return m.windowShouldDraw
    end
    return setmetatable({
        id = spec.id,
        label = spec.label,
        buttonWidth = spec.buttonWidth or 60,
        tooltip = spec.tooltip or "",
        layoutKeys = spec.layoutKeys,
        enableKey = spec.enableKey,
        onOpen = spec.onOpen,
        onClose = spec.onClose,
        onTick = spec.onTick,
        render = spec.render,
        isOpen = isOpen,
        shouldDraw = shouldDraw,
    }, { __index = m.spec })
end

function M.getEnabledModules()
    local out = {}
    for _, id in ipairs(order) do
        local m = modules[id]
        if m and isEnabled(m.spec) then
            out[#out + 1] = setmetatable({
                id = m.spec.id,
                label = m.spec.label,
                buttonWidth = m.spec.buttonWidth or 60,
                tooltip = m.spec.tooltip or "",
                isOpen = function() return m.windowOpen end,
                shouldDraw = function() return m.windowShouldDraw end,
                render = m.spec.render,
            }, { __index = m.spec })
        end
    end
    return out
end

function M.toggleWindow(id)
    local m = modules[id]
    if not m then return end
    m.windowOpen = not m.windowOpen
    m.windowShouldDraw = m.windowOpen
    if m.windowOpen then
        m.openedAt = mq.gettime()
        if companionWindowOpenedAt then
            companionWindowOpenedAt[id] = m.openedAt
        end
        if m.spec.onOpen and type(m.spec.onOpen) == "function" then
            m.spec.onOpen()
        end
    else
        m.openedAt = nil
        if companionWindowOpenedAt then
            companionWindowOpenedAt[id] = nil
        end
        if m.spec.onClose and type(m.spec.onClose) == "function" then
            m.spec.onClose()
        end
    end
end

function M.closeNewestOpen()
    local bestId, bestT = nil, -1
    for _, id in ipairs(order) do
        local m = modules[id]
        if m and m.windowShouldDraw and m.openedAt and m.openedAt > bestT then
            bestT = m.openedAt
            bestId = id
        end
    end
    if not bestId then return nil end
    local m = modules[bestId]
    m.windowOpen = false
    m.windowShouldDraw = false
    m.openedAt = nil
    if companionWindowOpenedAt then
        companionWindowOpenedAt[bestId] = nil
    end
    if m.spec.onClose and type(m.spec.onClose) == "function" then
        m.spec.onClose()
    end
    return bestId
end

function M.getDrawableModules()
    local out = {}
    for _, id in ipairs(order) do
        local m = modules[id]
        if m and m.windowShouldDraw and m.spec.render then
            out[#out + 1] = setmetatable({
                id = m.spec.id,
                render = m.spec.render,
                shouldDraw = function() return m.windowShouldDraw end,
            }, { __index = m.spec })
        end
    end
    return out
end

function M.getTickableModules()
    local out = {}
    for _, id in ipairs(order) do
        local m = modules[id]
        if m and m.spec.onTick and type(m.spec.onTick) == "function" and isEnabled(m.spec) then
            out[#out + 1] = setmetatable({
                id = m.spec.id,
                onTick = m.spec.onTick,
            }, { __index = m.spec })
        end
    end
    return out
end

function M.getWindowState(id)
    local m = modules[id]
    if not m then
        return { windowOpen = false, windowShouldDraw = false }
    end
    return {
        windowOpen = m.windowOpen,
        windowShouldDraw = m.windowShouldDraw,
    }
end

function M.setWindowState(id, windowOpen, windowShouldDraw)
    local m = modules[id]
    if not m then return end
    m.windowOpen = windowOpen
    m.windowShouldDraw = windowShouldDraw
    if not windowOpen then
        m.openedAt = nil
        if companionWindowOpenedAt then
            companionWindowOpenedAt[id] = nil
        end
        if m.spec.onClose and type(m.spec.onClose) == "function" then
            m.spec.onClose()
        end
    end
end

function M.shouldDraw(id)
    local m = modules[id]
    return m and m.windowShouldDraw
end

function M.isOpen(id)
    local m = modules[id]
    return m and m.windowOpen
end

function M.isRegistered(id)
    return modules[id] ~= nil
end

return M
