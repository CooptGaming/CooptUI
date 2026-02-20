--[[
    Table cache and sorted-list helper (Phase 3).
    Shared sort + cache-valid logic for Inventory, Sell, and Bank item tables.
    Call getSortedList() with cache slot, filtered list, sort key/dir, validity opts, view name, and sortColumns.
--]]

require('ImGui')

local M = {}

--- Return sorted list for a view, using perfCache slot when valid or recomputing and storing.
--- @param cache table perfCache.inv, perfCache.sell, or perfCache.bank
--- @param filtered table array of items (may be mutated in place when recomputing)
--- @param sortKey string|number column key (string) or Sell column index (3-7)
--- @param sortDir number ImGuiSortDirection
--- @param validity table { filter, hidingSlot, fullListLen, nFiltered?, scanTime?, showOnly? }
--- @param viewName string "Inventory" | "Sell" | "Bank"
--- @param sortColumns table ctx.sortColumns (precomputeKeys, undecorate, isNumericColumn, getSellSortVal, makeComparator)
--- @return table sorted array (either cache.sorted or filtered after sort)
function M.getSortedList(cache, filtered, sortKey, sortDir, validity, viewName, sortColumns)
    if not cache or not sortColumns then return filtered end
    if sortKey == "" or (type(sortKey) == "number" and (sortKey < 3 or sortKey > 7)) then return filtered end

    local nFiltered = #filtered
    local valid = cache.key == sortKey and cache.dir == sortDir and cache.filter == validity.filter
        and cache.hidingSlot == validity.hidingSlot and cache.n == validity.fullListLen
        and #(cache.sorted or {}) > 0
    if validity.scanTime ~= nil then valid = valid and cache.scanTime == validity.scanTime end
    if validity.nFiltered ~= nil then valid = valid and cache.nFiltered == validity.nFiltered end
    if validity.showOnly ~= nil then valid = valid and cache.showOnly == validity.showOnly end

    if valid then
        return cache.sorted
    end

    -- Recompute: sort filtered in place and update cache
    local Sort = sortColumns
    local dir = sortDir or ImGuiSortDirection.Ascending

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
    if validity.scanTime ~= nil then cache.scanTime = validity.scanTime end
    if validity.showOnly ~= nil then cache.showOnly = validity.showOnly end

    return filtered
end

return M
