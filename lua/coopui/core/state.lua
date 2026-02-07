--[[
    CoopUI State Management
    Unified state with reactive updates via event system

    Part of CoopUI — Shared infrastructure for all CoopUI components

    Usage:
        local state = require('coopui.core.state')

        -- Initialize state
        state.init({
            inventory = { items = {}, scanTime = 0 },
            ui = { windowOpen = false, currentView = 'inventory' }
        })

        -- Get state
        local items = state.get('inventory.items')
        local isOpen = state.get('ui.windowOpen')

        -- Set state (triggers events)
        state.set('inventory.items', newItems)  -- Emits 'state:inventory.items'

        -- Subscribe to state changes
        state.watch('inventory.items', function(newValue, oldValue)
            print('Items changed:', #newValue)
        end)

        -- Batch updates (single event at end)
        state.batch(function()
            state.set('ui.windowOpen', true)
            state.set('ui.currentView', 'sell')
        end)  -- Emits 'state:batch' with all changes
--]]

local events = require('coopui.core.events')

local State = {
    _data = {},           -- The actual state data
    _watchers = {},       -- { path = { id1 = callback } }
    _nextWatcherId = 1,
    _batchMode = false,   -- True during batch()
    _batchChanges = {},   -- Changes accumulated during batch
    _debug = false,       -- Set to true for state logging
}

--- Initialize state with default values
-- @param initialState table The initial state structure
function State.init(initialState)
    State._data = initialState or {}

    if State._debug then
        print('[State] Initialized with', _countKeys(State._data), 'top-level keys')
    end
end

--- Get a value from state using dot notation
-- @param path string Dot-separated path (e.g., 'inventory.items' or 'ui.windowOpen')
-- @return any The value at the path, or nil if not found
function State.get(path)
    if type(path) ~= 'string' then
        error('State.get: path must be string')
    end

    local parts = _splitPath(path)
    local current = State._data

    for _, key in ipairs(parts) do
        if type(current) ~= 'table' then
            return nil
        end
        current = current[key]
    end

    return current
end

--- Set a value in state (triggers watchers and events)
-- @param path string Dot-separated path
-- @param value any The new value
-- @param silent boolean Optional - if true, don't trigger watchers/events
function State.set(path, value, silent)
    if type(path) ~= 'string' then
        error('State.set: path must be string')
    end

    local oldValue = State.get(path)

    -- Don't trigger if value unchanged (shallow equality)
    if oldValue == value then
        return
    end

    -- Navigate to parent and set value
    local parts = _splitPath(path)
    local current = State._data

    for i = 1, #parts - 1 do
        local key = parts[i]
        if type(current[key]) ~= 'table' then
            current[key] = {}
        end
        current = current[key]
    end

    local finalKey = parts[#parts]
    current[finalKey] = value

    if State._debug then
        print(string.format('[State] Set "%s" = %s', path, _valueToString(value)))
    end

    if not silent then
        if State._batchMode then
            -- Accumulate change for batch event
            table.insert(State._batchChanges, { path = path, oldValue = oldValue, newValue = value })
        else
            -- Trigger immediately
            _notifyChange(path, value, oldValue)
        end
    end
end

--- Watch a state path for changes
-- @param path string Dot-separated path to watch
-- @param callback function Called with (newValue, oldValue, path)
-- @return number Watcher ID (use with unwatch)
function State.watch(path, callback)
    if type(path) ~= 'string' or type(callback) ~= 'function' then
        error('State.watch: path must be string, callback must be function')
    end

    if not State._watchers[path] then
        State._watchers[path] = {}
    end

    local id = State._nextWatcherId
    State._nextWatcherId = State._nextWatcherId + 1
    State._watchers[path][id] = callback

    if State._debug then
        print(string.format('[State] Watching "%s" (id=%d)', path, id))
    end

    return id
end

--- Stop watching a state path
-- @param path string The path being watched
-- @param id number The watcher ID from watch()
function State.unwatch(path, id)
    if not State._watchers[path] then
        return
    end

    State._watchers[path][id] = nil

    if State._debug then
        print(string.format('[State] Unwatching "%s" (id=%d)', path, id))
    end

    -- Clean up empty watcher tables
    local hasWatchers = false
    for _ in pairs(State._watchers[path]) do
        hasWatchers = true
        break
    end
    if not hasWatchers then
        State._watchers[path] = nil
    end
end

--- Batch multiple state changes (single event at end)
-- @param fn function Function that performs multiple set() calls
function State.batch(fn)
    if type(fn) ~= 'function' then
        error('State.batch: fn must be function')
    end

    State._batchMode = true
    State._batchChanges = {}

    local ok, err = pcall(fn)

    State._batchMode = false

    if not ok then
        State._batchChanges = {}
        error('State.batch: ' .. tostring(err))
    end

    -- Emit batch event with all changes
    if #State._batchChanges > 0 then
        events.emit('state:batch', { changes = State._batchChanges })

        -- Notify individual watchers for each change
        for _, change in ipairs(State._batchChanges) do
            _notifyChange(change.path, change.newValue, change.oldValue)
        end

        if State._debug then
            print(string.format('[State] Batch complete: %d changes', #State._batchChanges))
        end
    end

    State._batchChanges = {}
end

--- Reset state to initial values or clear entirely
-- @param newState table Optional new state (if nil, clears all)
function State.reset(newState)
    State._data = newState or {}

    -- Clear all watchers
    State._watchers = {}

    events.emit('state:reset', { state = State._data })

    if State._debug then
        print('[State] Reset')
    end
end

--- Get entire state tree (shallow copy)
-- @return table Copy of state data
function State.getAll()
    local copy = {}
    for k, v in pairs(State._data) do
        copy[k] = v
    end
    return copy
end

--- Check if a path exists in state
-- @param path string Dot-separated path
-- @return boolean True if path exists
function State.has(path)
    return State.get(path) ~= nil
end

--- Delete a value from state
-- @param path string Dot-separated path
function State.delete(path)
    local parts = _splitPath(path)
    local current = State._data

    for i = 1, #parts - 1 do
        local key = parts[i]
        if type(current) ~= 'table' or not current[key] then
            return  -- Path doesn't exist
        end
        current = current[key]
    end

    local finalKey = parts[#parts]
    local oldValue = current[finalKey]
    current[finalKey] = nil

    if not State._batchMode then
        _notifyChange(path, nil, oldValue)
    else
        table.insert(State._batchChanges, { path = path, oldValue = oldValue, newValue = nil })
    end

    if State._debug then
        print(string.format('[State] Deleted "%s"', path))
    end
end

--- Enable/disable debug logging
-- @param enabled boolean True to enable debug output
function State.setDebug(enabled)
    State._debug = enabled
end

--- Get statistics about state
-- @return table { paths: number, watchers: number, dataSize: number }
function State.stats()
    local pathCount = _countPaths(State._data)
    local watcherCount = 0

    for _, watchers in pairs(State._watchers) do
        for _ in pairs(watchers) do
            watcherCount = watcherCount + 1
        end
    end

    return {
        paths = pathCount,
        watchers = watcherCount,
        watchedPaths = _countKeys(State._watchers),
    }
end

-- ============================================================================
-- Internal Helpers
-- ============================================================================

--- Split dot-separated path into array
local function _splitPath(path)
    local parts = {}
    for part in path:gmatch('[^.]+') do
        table.insert(parts, part)
    end
    return parts
end

--- Notify watchers and emit event for a change
local function _notifyChange(path, newValue, oldValue)
    -- Emit event for this specific path
    events.emit('state:' .. path, { path = path, oldValue = oldValue, newValue = newValue })

    -- Notify watchers
    if State._watchers[path] then
        for _, callback in pairs(State._watchers[path]) do
            local ok, err = pcall(callback, newValue, oldValue, path)
            if not ok then
                print(string.format('[State] Error in watcher for "%s": %s', path, tostring(err)))
            end
        end
    end
end

--- Count keys in a table
local function _countKeys(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

--- Count all paths in nested table
local function _countPaths(t, depth)
    depth = depth or 0
    if depth > 10 then return 1 end  -- Prevent infinite recursion

    local count = 0
    for _, v in pairs(t) do
        count = count + 1
        if type(v) == 'table' then
            count = count + _countPaths(v, depth + 1)
        end
    end
    return count
end

--- Convert value to string for logging
local function _valueToString(value)
    local t = type(value)
    if t == 'nil' then return 'nil'
    elseif t == 'boolean' then return tostring(value)
    elseif t == 'number' then return tostring(value)
    elseif t == 'string' then return '"' .. value .. '"'
    elseif t == 'table' then
        local count = 0
        for _ in pairs(value) do count = count + 1 end
        return string.format('table{%d}', count)
    else
        return t
    end
end

return State
