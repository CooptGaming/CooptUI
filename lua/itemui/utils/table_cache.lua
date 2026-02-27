--[[
    Table cache and sorted-list helper (Phase 3).
    Shared sort + cache-valid logic for Inventory, Sell, and Bank item tables.
    Call getSortedList() with cache slot, filtered list, sort key/dir, validity opts, view name, and sortColumns.
--]]

require('ImGui')

local M = {}

local function bagSlotKey(item)
    return (item and (item.bag or 0)) .. ":" .. (item and (item.slot or 0) or 0)
end

--- Return true if a should sort before b (same contract as comparator used in full sort).
local function lessThan(Sort, viewName, sortKey, sortDir, a, b)
    if not a or not b then return false end
    local dir = sortDir or ImGuiSortDirection.Ascending
    if viewName == "Sell" and type(sortKey) == "number" and sortKey >= 3 and sortKey <= 7 then
        local comp = Sort.makeComparator and Sort.makeComparator(Sort.getSellSortVal, sortKey, dir, { 5, 6 })
        return comp and comp(a, b)
    end
    local keyStr = type(sortKey) == "string" and sortKey or "Name"
    local isNumeric = Sort.isNumericColumn and Sort.isNumericColumn(keyStr)
    local av = Sort.getSortValByKey and Sort.getSortValByKey(a, keyStr, viewName) or ""
    local bv = Sort.getSortValByKey and Sort.getSortValByKey(b, keyStr, viewName) or ""
    if isNumeric then
        local an, bn = tonumber(av) or 0, tonumber(bv) or 0
        if an ~= bn then
            if dir == ImGuiSortDirection.Ascending then return an < bn else return an > bn end
        end
    else
        local as, bs = tostring(av or ""), tostring(bv or "")
        if as ~= bs then
            if dir == ImGuiSortDirection.Ascending then return as < bs else return as > bs end
        end
    end
    local ta = (a.bag or 0) * 1000 + (a.slot or 0)
    local tb = (b.bag or 0) * 1000 + (b.slot or 0)
    if dir == ImGuiSortDirection.Ascending then return ta < tb else return ta > tb end
end

--- Binary search: return lowest index i such that lessThan(newItem, cache.sorted[i]) (insert before i).
local function binarySearchInsertIndex(Sort, viewName, sortKey, sortDir, sorted, newItem)
    local lo, hi = 1, #sorted + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if lessThan(Sort, viewName, sortKey, sortDir, newItem, sorted[mid]) then
            hi = mid
        else
            lo = mid + 1
        end
    end
    return lo
end

--- Return sorted list for a view, using perfCache slot when valid or recomputing and storing.
--- When cache is invalid and only one item added/removed/modified, updates cache.sorted incrementally instead of full re-sort.
--- @param cache table perfCache.inv, perfCache.sell, or perfCache.bank
--- @param filtered table array of items (may be mutated in place when recomputing)
--- @param sortKey string|number column key (string) or Sell column index (3-7)
--- @param sortDir number ImGuiSortDirection
--- @param validity table { filter, hidingSlot, fullListLen, nFiltered?, scanTime?, showOnly? }
--- @param viewName string "Inventory" | "Sell" | "Bank"
--- @param sortColumns table ctx.sortColumns (precomputeKeys, undecorate, isNumericColumn, getSellSortVal, makeComparator, getSortValByKey)
--- @return table sorted array (either cache.sorted or filtered after sort)
function M.getSortedList(cache, filtered, sortKey, sortDir, validity, viewName, sortColumns)
    if not cache or not sortColumns then return filtered end
    if sortKey == "" or (type(sortKey) == "number" and (sortKey < 3 or sortKey > 7)) then return filtered end

    local nFiltered = #filtered
    local valid = (cache._invalid ~= true) and cache.key == sortKey and cache.dir == sortDir and cache.filter == validity.filter
        and cache.hidingSlot == validity.hidingSlot and cache.n == validity.fullListLen
        and #(cache.sorted or {}) > 0
    if validity.scanTime ~= nil then valid = valid and cache.scanTime == validity.scanTime end
    if validity.nFiltered ~= nil then valid = valid and cache.nFiltered == validity.nFiltered end
    if validity.showOnly ~= nil then valid = valid and cache.showOnly == validity.showOnly end

    if valid then
        return cache.sorted
    end

    local Sort = sortColumns
    local dir = sortDir or ImGuiSortDirection.Ascending
    local oldN = cache.n
    local oldNFiltered = cache.nFiltered or 0
    local deltaFull = validity.fullListLen - (oldN or 0)
    local deltaFiltered = nFiltered - oldNFiltered

    -- Try incremental update when same sort/filter context and exactly one add/remove/modify
    local sameContext = (cache.sorted and #cache.sorted > 0)
        and cache.key == sortKey and cache.dir == sortDir and cache.filter == validity.filter and cache.hidingSlot == validity.hidingSlot
        and (validity.scanTime == nil or cache.scanTime == validity.scanTime)
        and (validity.nFiltered == nil or true)  -- nFiltered checked via deltaFiltered
        and (validity.showOnly == nil or cache.showOnly == validity.showOnly)
    if sameContext and deltaFull >= -1 and deltaFull <= 1 and deltaFiltered >= -1 and deltaFiltered <= 1 then
        local newMap = {}
        for _, item in ipairs(filtered) do newMap[bagSlotKey(item)] = item end
        local oldSet = {}
        for _, item in ipairs(cache.sorted) do oldSet[bagSlotKey(item)] = true end

        local removedIdx, removedItem = nil, nil
        for i, item in ipairs(cache.sorted) do
            if not newMap[bagSlotKey(item)] then removedIdx = i; removedItem = item; break end
        end
        local addedItem = nil
        for _, item in ipairs(filtered) do
            if not oldSet[bagSlotKey(item)] then addedItem = item; break end
        end

        -- One remove
        if deltaFiltered == -1 and deltaFull == -1 and removedIdx and not addedItem then
            table.remove(cache.sorted, removedIdx)
            cache.n = validity.fullListLen
            cache.nFiltered = nFiltered
            cache._invalid = false
            return cache.sorted
        end

        -- One add
        if deltaFiltered == 1 and deltaFull == 1 and addedItem and not removedIdx then
            local idx = binarySearchInsertIndex(Sort, viewName, sortKey, sortDir, cache.sorted, addedItem)
            table.insert(cache.sorted, idx, addedItem)
            cache.n = validity.fullListLen
            cache.nFiltered = nFiltered
            cache._invalid = false
            return cache.sorted
        end

        -- One modify: same count, one bag:slot has different ref (e.g. stack size changed)
        if deltaFiltered == 0 and deltaFull == 0 and not removedIdx and not addedItem then
            local modIdx = nil
            for i, item in ipairs(cache.sorted) do
                local k = bagSlotKey(item)
                local newItem = newMap[k]
                if newItem and newItem ~= item then modIdx = i; break end
            end
            if modIdx then
                local newItem = newMap[bagSlotKey(cache.sorted[modIdx])]
                table.remove(cache.sorted, modIdx)
                local idx = binarySearchInsertIndex(Sort, viewName, sortKey, sortDir, cache.sorted, newItem)
                table.insert(cache.sorted, idx, newItem)
                cache.n = validity.fullListLen
                cache.nFiltered = nFiltered
                cache._invalid = false
                return cache.sorted
            end
        end
    end

    -- Recompute: full sort filtered in place and update cache
    if viewName == "Sell" and type(sortKey) == "number" and sortKey >= 3 and sortKey <= 7 then
        local comp = Sort.makeComparator and Sort.makeComparator(Sort.getSellSortVal, sortKey, dir, { 5, 6 })
        if comp then
            table.sort(filtered, comp)
        end
    else
        local keyStr = type(sortKey) == "string" and sortKey or "Name"
        local isNumeric = Sort.isNumericColumn and Sort.isNumericColumn(keyStr)
        local decorated = Sort.precomputeKeys and Sort.precomputeKeys(filtered, keyStr, viewName)
        if decorated then
            table.sort(decorated, function(a, b)
                local av, bv = a.key, b.key
                if isNumeric then
                    local an, bn = tonumber(av) or 0, tonumber(bv) or 0
                    if an ~= bn then
                        if dir == ImGuiSortDirection.Ascending then return an < bn else return an > bn end
                    end
                    local ta = (a.item and ((a.item.bag or 0) * 1000 + (a.item.slot or 0))) or 0
                    local tb = (b.item and ((b.item.bag or 0) * 1000 + (b.item.slot or 0))) or 0
                    if dir == ImGuiSortDirection.Ascending then return ta < tb else return ta > tb end
                else
                    local as, bs = tostring(av or ""), tostring(bv or "")
                    if as ~= bs then
                        if dir == ImGuiSortDirection.Ascending then return as < bs else return as > bs end
                    end
                    local ta = (a.item and ((a.item.bag or 0) * 1000 + (a.item.slot or 0))) or 0
                    local tb = (b.item and ((b.item.bag or 0) * 1000 + (b.item.slot or 0))) or 0
                    if dir == ImGuiSortDirection.Ascending then return ta < tb else return ta > tb end
                end
            end)
            Sort.undecorate(decorated, filtered)
        end
    end

    cache.key = sortKey
    cache.dir = sortDir
    cache.filter = validity.filter
    cache.n = validity.fullListLen
    cache.nFiltered = nFiltered
    cache.sorted = filtered
    cache.hidingSlot = validity.hidingSlot
    cache._invalid = false
    if validity.scanTime ~= nil then cache.scanTime = validity.scanTime end
    if validity.showOnly ~= nil then cache.showOnly = validity.showOnly end

    return filtered
end

return M
