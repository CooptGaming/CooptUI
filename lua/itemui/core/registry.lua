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

-- Cache for getEnabledModules/getDrawableModules/getTickableModules (Task 6.1). Invalidated when registry state changes.
local cacheDirty = true
local cachedEnabled, cachedDrawable, cachedTickable

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

function M.recordOpened(id)
    if not id or id == "" then return end
    local now = mq.gettime()
    local m = modules[id]
    if m then
        m.openedAt = now
    end
    if companionWindowOpenedAt then
        companionWindowOpenedAt[id] = now
    end
end

function M.register(spec)
    if not spec or not spec.id then return end
    cacheDirty = true
    local id = spec.id
    if not modules[id] then
        order[#order + 1] = id
    end
    -- displayOrder: optional number for button bar order (lower = left). Ignored if layoutConfig.CompanionButtonOrder is set.
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

local function rebuildModuleCaches()
    if not cacheDirty then return end
    local enabled, drawable, tickable = {}, {}, {}
    for _, id in ipairs(order) do
        local m = modules[id]
        if m and isEnabled(m.spec) then
            enabled[#enabled + 1] = setmetatable({
                id = m.spec.id,
                label = m.spec.label,
                buttonWidth = m.spec.buttonWidth or 60,
                tooltip = m.spec.tooltip or "",
                isOpen = function() return m.windowOpen end,
                shouldDraw = function() return m.windowShouldDraw end,
                render = m.spec.render,
            }, { __index = m.spec })
        end
        local allowed = (m and m.windowShouldDraw and m.spec.render) and (isEnabled(m.spec) or id == "config")
        if allowed then
            drawable[#drawable + 1] = setmetatable({
                id = m.spec.id,
                render = m.spec.render,
                shouldDraw = function() return m.windowShouldDraw end,
            }, { __index = m.spec })
        end
        if m and m.spec.onTick and type(m.spec.onTick) == "function" and isEnabled(m.spec) then
            tickable[#tickable + 1] = setmetatable({
                id = m.spec.id,
                onTick = m.spec.onTick,
            }, { __index = m.spec })
        end
    end
    cachedEnabled, cachedDrawable, cachedTickable = enabled, drawable, tickable
    cacheDirty = false
end

function M.getEnabledModules()
    rebuildModuleCaches()
    return cachedEnabled or {}
end

function M.toggleWindow(id)
    local m = modules[id]
    if not m then return end
    cacheDirty = true
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
    local bestId = M.getNewestOpen()
    if not bestId then return nil end
    M.closeWindow(bestId)
    return bestId
end

function M.closeWindow(id, cleanupFn)
    if not id or id == "" then return false end
    cacheDirty = true
    local m = modules[id]
    if m then
        m.windowOpen = false
        m.windowShouldDraw = false
        m.openedAt = nil
        if companionWindowOpenedAt then
            companionWindowOpenedAt[id] = nil
        end
        if m.spec.onClose and type(m.spec.onClose) == "function" then
            m.spec.onClose()
        end
    else
        if companionWindowOpenedAt then
            companionWindowOpenedAt[id] = nil
        end
    end
    if cleanupFn and type(cleanupFn) == "function" then
        cleanupFn(id)
    end
    return true
end

function M.getNewestOpen(isOpenFn)
    local bestId, bestT = nil, -1
    local opened = companionWindowOpenedAt or {}
    for id, openedAt in pairs(opened) do
        local t = tonumber(openedAt) or -1
        if t >= 0 then
            local m = modules[id]
            local isOpen = false
            if m then
                isOpen = m.windowShouldDraw == true
            elseif isOpenFn and type(isOpenFn) == "function" then
                isOpen = isOpenFn(id) == true
            end
            if isOpen and t > bestT then
                bestT = t
                bestId = id
            end
        end
    end
    return bestId
end

function M.getDrawableModules()
    rebuildModuleCaches()
    return cachedDrawable or {}
end

function M.getTickableModules()
    rebuildModuleCaches()
    return cachedTickable or {}
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
    cacheDirty = true
    local wasOpen = m.windowOpen
    m.windowOpen = windowOpen
    m.windowShouldDraw = windowShouldDraw
    if windowOpen and not wasOpen then
        -- Auto-record LIFO timestamp on closed→open transition so windows opened via
        -- state writes (e.g. augment utility opened from item display tooltip click)
        -- are correctly tracked by getMostRecentlyOpenedCompanion.
        M.recordOpened(id)
    elseif not windowOpen then
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

function M.isEnabled(id)
    local m = modules[id]
    return m and isEnabled(m.spec)
end

--- Close any companion window whose enableKey is 0 in layoutConfig (call after loadLayoutConfig).
function M.applyEnabledFromLayout(layoutConfig)
    if not layoutConfig then return end
    cacheDirty = true
    for _, id in ipairs(order) do
        local m = modules[id]
        if m and m.spec.enableKey then
            if (tonumber(layoutConfig[m.spec.enableKey]) or 1) == 0 then
                m.windowOpen = false
                m.windowShouldDraw = false
                m.openedAt = nil
                if companionWindowOpenedAt then companionWindowOpenedAt[id] = nil end
                if m.spec.onClose and type(m.spec.onClose) == "function" then
                    m.spec.onClose()
                end
            end
        end
    end
end

return M
