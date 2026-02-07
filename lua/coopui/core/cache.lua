--[[
    CoopUI Cache System
    Multi-tier caching with granular invalidation and statistics

    Part of CoopUI — Shared infrastructure for all CoopUI components

    Tiers (TTL in milliseconds, uses mq.gettime()):
    - L1 (Hot): Current view items, sorted lists (60s TTL, 100 items)
    - L2 (Warm): Spell names/descriptions, recent queries (300s TTL, 500 items)
    - L3 (Cold): Historical data, snapshots (no TTL, 2000 items)

    Usage:
        local cache = require('coopui.core.cache')

        -- Store in cache
        cache.set('inventory:items', items, { tier = 'L1', ttl = 60 })
        cache.set('sort:inventory:Name:asc', sortedItems, { tier = 'L2' })

        -- Retrieve from cache
        local items = cache.get('inventory:items')
        if not items then
            items = scanInventory()
            cache.set('inventory:items', items)
        end

        -- Invalidate specific keys
        cache.invalidate('inventory:items')

        -- Invalidate by pattern
        cache.invalidatePattern('sort:inventory:*')

        -- Warm cache (pre-load data)
        cache.warm('bank:items', loadBankSnapshot())

        -- Get statistics
        local stats = cache.stats()
        print('Hit rate:', stats.hitRate)
--]]

local mq = require('mq')

local Cache = {
    _L1 = {},  -- { key = { value, timestamp, hits, tier } }
    _L2 = {},
    _L3 = {},
    _stats = {
        hits = 0,
        misses = 0,
        sets = 0,
        evictions = 0,
        invalidations = 0,
    },
    _config = {
        L1 = { maxSize = 100, ttl = 60000 },      -- 60 seconds (ms)
        L2 = { maxSize = 500, ttl = 300000 },     -- 5 minutes (ms)
        L3 = { maxSize = 2000, ttl = nil },        -- No expiry
    },
    _debug = false,
}

-- ============================================================================
-- Internal Helpers (must be defined before Cache methods that reference them)
-- ============================================================================

--- Check if entry is expired
local function _isExpired(entry, ttl)
    if not ttl then return false end  -- No TTL = never expires
    local age = mq.gettime() - entry.timestamp
    return age > ttl
end

--- Count keys in table
local function _countKeys(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

--- Get tier data table
local function _getTierData(tier)
    if tier == 'L1' then return Cache._L1
    elseif tier == 'L2' then return Cache._L2
    elseif tier == 'L3' then return Cache._L3
    else error('Invalid tier: ' .. tostring(tier)) end
end

--- Promote entry to higher tier
local function _promote(key, entry, toTier)
    local tierData = _getTierData(toTier)

    -- Remove from current tier
    if entry.tier == 'L1' then Cache._L1[key] = nil
    elseif entry.tier == 'L2' then Cache._L2[key] = nil
    elseif entry.tier == 'L3' then Cache._L3[key] = nil
    end

    -- Add to new tier
    entry.tier = toTier
    entry.timestamp = mq.gettime()  -- Reset timestamp
    tierData[key] = entry

    if Cache._debug then
        print(string.format('[Cache] PROMOTE: %s -> %s', key, toTier))
    end
end

--- Evict least recently used entry
local function _evictLRU(tierData)
    local oldestKey, oldestTime = nil, math.huge

    for key, entry in pairs(tierData) do
        if entry.timestamp < oldestTime then
            oldestTime = entry.timestamp
            oldestKey = key
        end
    end

    if oldestKey then
        tierData[oldestKey] = nil
        Cache._stats.evictions = Cache._stats.evictions + 1

        if Cache._debug then
            print(string.format('[Cache] EVICT: %s', oldestKey))
        end
    end
end

--- Convert value to string for logging
local function _valueToString(value)
    local t = type(value)
    if t == 'table' then
        local count = 0
        for _ in pairs(value) do count = count + 1 end
        return string.format('table{%d}', count)
    else
        return tostring(value)
    end
end

-- ============================================================================
-- Cache API
-- ============================================================================

--- Get value from cache
-- @param key string Cache key
-- @return any The cached value, or nil if not found/expired
function Cache.get(key)
    if type(key) ~= 'string' then
        error('Cache.get: key must be string')
    end

    -- Check L1 first (hottest)
    local entry = Cache._L1[key]
    if entry and not _isExpired(entry, Cache._config.L1.ttl) then
        entry.hits = entry.hits + 1
        Cache._stats.hits = Cache._stats.hits + 1

        if Cache._debug then
            print(string.format('[Cache] L1 HIT: %s (hits=%d)', key, entry.hits))
        end

        return entry.value
    end

    -- Check L2
    entry = Cache._L2[key]
    if entry and not _isExpired(entry, Cache._config.L2.ttl) then
        entry.hits = entry.hits + 1
        Cache._stats.hits = Cache._stats.hits + 1

        -- Promote to L1 if frequently accessed
        if entry.hits >= 3 then
            _promote(key, entry, 'L1')
        end

        if Cache._debug then
            print(string.format('[Cache] L2 HIT: %s (hits=%d)', key, entry.hits))
        end

        return entry.value
    end

    -- Check L3
    entry = Cache._L3[key]
    if entry then  -- L3 has no TTL
        entry.hits = entry.hits + 1
        Cache._stats.hits = Cache._stats.hits + 1

        if Cache._debug then
            print(string.format('[Cache] L3 HIT: %s (hits=%d)', key, entry.hits))
        end

        return entry.value
    end

    -- Cache miss
    Cache._stats.misses = Cache._stats.misses + 1

    if Cache._debug then
        print(string.format('[Cache] MISS: %s', key))
    end

    return nil
end

--- Set value in cache
-- @param key string Cache key
-- @param value any The value to cache
-- @param options table Optional { tier = 'L1'|'L2'|'L3', ttl = number }
function Cache.set(key, value, options)
    if type(key) ~= 'string' then
        error('Cache.set: key must be string')
    end

    options = options or {}
    local tier = options.tier or 'L1'
    local ttl = options.ttl

    -- Create entry
    local entry = {
        value = value,
        timestamp = mq.gettime(),
        hits = 0,
        tier = tier,
    }

    -- Get target tier
    local tierData = _getTierData(tier)
    local config = Cache._config[tier]

    -- Evict if at capacity
    if _countKeys(tierData) >= config.maxSize then
        _evictLRU(tierData)
    end

    -- Store in tier
    tierData[key] = entry
    Cache._stats.sets = Cache._stats.sets + 1

    if Cache._debug then
        print(string.format('[Cache] SET: %s -> %s (tier=%s)', key, _valueToString(value), tier))
    end
end

--- Invalidate a specific cache key
-- @param key string Cache key to invalidate
-- @return boolean True if key was found and invalidated
function Cache.invalidate(key)
    if type(key) ~= 'string' then
        error('Cache.invalidate: key must be string')
    end

    local found = false

    if Cache._L1[key] then
        Cache._L1[key] = nil
        found = true
    end
    if Cache._L2[key] then
        Cache._L2[key] = nil
        found = true
    end
    if Cache._L3[key] then
        Cache._L3[key] = nil
        found = true
    end

    if found then
        Cache._stats.invalidations = Cache._stats.invalidations + 1

        if Cache._debug then
            print(string.format('[Cache] INVALIDATE: %s', key))
        end
    end

    return found
end

--- Invalidate all keys matching a pattern
-- @param pattern string Lua pattern (e.g., 'sort:inventory:.*')
-- @return number Count of keys invalidated
function Cache.invalidatePattern(pattern)
    if type(pattern) ~= 'string' then
        error('Cache.invalidatePattern: pattern must be string')
    end

    local count = 0

    -- Check all tiers
    for tier, tierData in pairs({L1 = Cache._L1, L2 = Cache._L2, L3 = Cache._L3}) do
        for key, _ in pairs(tierData) do
            if key:match(pattern) then
                tierData[key] = nil
                count = count + 1
            end
        end
    end

    if count > 0 then
        Cache._stats.invalidations = Cache._stats.invalidations + count

        if Cache._debug then
            print(string.format('[Cache] INVALIDATE PATTERN: %s (%d keys)', pattern, count))
        end
    end

    return count
end

--- Warm cache with data (pre-load for fast access)
-- @param key string Cache key
-- @param value any The value to cache
-- @param tier string Optional tier ('L1', 'L2', 'L3'), defaults to 'L2'
function Cache.warm(key, value, tier)
    tier = tier or 'L2'
    Cache.set(key, value, { tier = tier })

    if Cache._debug then
        print(string.format('[Cache] WARM: %s (tier=%s)', key, tier))
    end
end

--- Clear all cache tiers or specific tier
-- @param tier string Optional tier to clear ('L1', 'L2', 'L3'), or nil for all
function Cache.clear(tier)
    if tier then
        local tierData = _getTierData(tier)
        for k in pairs(tierData) do
            tierData[k] = nil
        end

        if Cache._debug then
            print(string.format('[Cache] CLEAR: %s', tier))
        end
    else
        Cache._L1 = {}
        Cache._L2 = {}
        Cache._L3 = {}

        if Cache._debug then
            print('[Cache] CLEAR: All tiers')
        end
    end
end

--- Get cache statistics
-- @return table { hits, misses, hitRate, size, tierSizes, evictions, invalidations }
function Cache.stats()
    local total = Cache._stats.hits + Cache._stats.misses
    local hitRate = total > 0 and (Cache._stats.hits / total) or 0

    return {
        hits = Cache._stats.hits,
        misses = Cache._stats.misses,
        hitRate = hitRate,
        hitRatePercent = string.format('%.1f%%', hitRate * 100),
        size = _countKeys(Cache._L1) + _countKeys(Cache._L2) + _countKeys(Cache._L3),
        tierSizes = {
            L1 = _countKeys(Cache._L1),
            L2 = _countKeys(Cache._L2),
            L3 = _countKeys(Cache._L3),
        },
        evictions = Cache._stats.evictions,
        invalidations = Cache._stats.invalidations,
    }
end

--- Reset statistics
function Cache.resetStats()
    Cache._stats = {
        hits = 0,
        misses = 0,
        sets = 0,
        evictions = 0,
        invalidations = 0,
    }

    if Cache._debug then
        print('[Cache] RESET STATS')
    end
end

--- Configure cache tiers
-- @param tierConfig table { L1 = { maxSize, ttl }, L2 = {...}, L3 = {...} }
function Cache.configure(tierConfig)
    for tier, config in pairs(tierConfig) do
        if Cache._config[tier] then
            if config.maxSize then Cache._config[tier].maxSize = config.maxSize end
            if config.ttl ~= nil then Cache._config[tier].ttl = config.ttl end
        end
    end

    if Cache._debug then
        print('[Cache] CONFIGURE: Updated tier settings')
    end
end

--- Enable/disable debug logging
-- @param enabled boolean True to enable debug output
function Cache.setDebug(enabled)
    Cache._debug = enabled
end

--- Clean up expired entries from all tiers
-- @return number Count of entries removed
function Cache.cleanup()
    local removed = 0

    -- L1 cleanup
    for key, entry in pairs(Cache._L1) do
        if _isExpired(entry, Cache._config.L1.ttl) then
            Cache._L1[key] = nil
            removed = removed + 1
        end
    end

    -- L2 cleanup
    for key, entry in pairs(Cache._L2) do
        if _isExpired(entry, Cache._config.L2.ttl) then
            Cache._L2[key] = nil
            removed = removed + 1
        end
    end

    -- L3 has no TTL, no cleanup needed

    if Cache._debug and removed > 0 then
        print(string.format('[Cache] CLEANUP: Removed %d expired entries', removed))
    end

    return removed
end

return Cache
