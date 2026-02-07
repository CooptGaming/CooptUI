--[[
    ItemUI Event Bus
    Simple event system for decoupled module communication
    
    Usage:
        local events = require('itemui.core.events')
        
        -- Subscribe to events
        local id = events.on('inventory:changed', function(data)
            print('Inventory changed:', data.itemCount)
        end)
        
        -- Emit events
        events.emit('inventory:changed', { itemCount = 80 })
        
        -- Unsubscribe
        events.off('inventory:changed', id)
        
        -- One-time listener
        events.once('ui:opened', function() print('UI opened!') end)
--]]

local Events = {
    _listeners = {},  -- { eventName = { id1 = callback, id2 = callback } }
    _nextId = 1,
    _debug = false,   -- Set to true for event logging
}

--- Subscribe to an event
-- @param eventName string The event name (e.g., 'inventory:changed')
-- @param callback function The callback to invoke when event fires
-- @return number Subscription ID (use for unsubscribe)
function Events.on(eventName, callback)
    if type(eventName) ~= 'string' or type(callback) ~= 'function' then
        error('Events.on: eventName must be string, callback must be function')
    end
    
    if not Events._listeners[eventName] then
        Events._listeners[eventName] = {}
    end
    
    local id = Events._nextId
    Events._nextId = Events._nextId + 1
    Events._listeners[eventName][id] = callback
    
    if Events._debug then
        print(string.format('[Events] Subscribed to "%s" (id=%d)', eventName, id))
    end
    
    return id
end

--- Subscribe to an event (one-time only)
-- @param eventName string The event name
-- @param callback function The callback to invoke once
-- @return number Subscription ID
function Events.once(eventName, callback)
    if type(eventName) ~= 'string' or type(callback) ~= 'function' then
        error('Events.once: eventName must be string, callback must be function')
    end
    
    local id
    id = Events.on(eventName, function(...)
        Events.off(eventName, id)
        callback(...)
    end)
    
    return id
end

--- Unsubscribe from an event
-- @param eventName string The event name
-- @param id number The subscription ID returned by on() or once()
function Events.off(eventName, id)
    if not Events._listeners[eventName] then
        return
    end
    
    Events._listeners[eventName][id] = nil
    
    if Events._debug then
        print(string.format('[Events] Unsubscribed from "%s" (id=%d)', eventName, id))
    end
    
    -- Clean up empty listener tables
    local hasListeners = false
    for _ in pairs(Events._listeners[eventName]) do
        hasListeners = true
        break
    end
    if not hasListeners then
        Events._listeners[eventName] = nil
    end
end

--- Emit an event to all subscribers
-- @param eventName string The event name
-- @param data any Optional data to pass to callbacks (typically a table)
function Events.emit(eventName, data)
    if not Events._listeners[eventName] then
        return
    end
    
    if Events._debug then
        local dataStr = type(data) == 'table' and string.format('{%d fields}', #data) or tostring(data)
        print(string.format('[Events] Emit "%s" data=%s', eventName, dataStr))
    end
    
    -- Copy listener list to avoid issues if callback modifies listeners
    local listeners = {}
    for id, callback in pairs(Events._listeners[eventName]) do
        listeners[id] = callback
    end
    
    -- Invoke all callbacks
    for id, callback in pairs(listeners) do
        local ok, err = pcall(callback, data)
        if not ok then
            print(string.format('[Events] Error in listener for "%s" (id=%d): %s', eventName, id, tostring(err)))
        end
    end
end

--- Clear all listeners for an event (or all events if no eventName given)
-- @param eventName string Optional event name (if nil, clears all events)
function Events.clear(eventName)
    if eventName then
        Events._listeners[eventName] = nil
        if Events._debug then
            print(string.format('[Events] Cleared all listeners for "%s"', eventName))
        end
    else
        Events._listeners = {}
        if Events._debug then
            print('[Events] Cleared all listeners for all events')
        end
    end
end

--- Get count of active listeners for an event
-- @param eventName string The event name
-- @return number Count of active listeners
function Events.listenerCount(eventName)
    if not Events._listeners[eventName] then
        return 0
    end
    
    local count = 0
    for _ in pairs(Events._listeners[eventName]) do
        count = count + 1
    end
    return count
end

--- Get list of all active event names
-- @return table Array of event names that have listeners
function Events.eventNames()
    local names = {}
    for name, _ in pairs(Events._listeners) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

--- Enable/disable debug logging
-- @param enabled boolean True to enable debug output
function Events.setDebug(enabled)
    Events._debug = enabled
end

--- Get statistics about event system
-- @return table { totalEvents: number, totalListeners: number, events: { name: string, count: number }[] }
function Events.stats()
    local totalListeners = 0
    local eventStats = {}
    
    for name, listeners in pairs(Events._listeners) do
        local count = 0
        for _ in pairs(listeners) do
            count = count + 1
        end
        totalListeners = totalListeners + count
        table.insert(eventStats, { name = name, count = count })
    end
    
    table.sort(eventStats, function(a, b)
        if a.count == b.count then
            return a.name < b.name
        end
        return a.count > b.count
    end)
    
    return {
        totalEvents = #eventStats,
        totalListeners = totalListeners,
        events = eventStats
    }
end

return Events
