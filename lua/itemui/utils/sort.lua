--[[
    Sort Utilities
    
    Extracted from init.lua for Phase 7 modularization.
    Provides sort value helpers and comparator builder.
--]]

require('ImGui')

local Sort = {}

function Sort.init(deps)
    Sort.getItemSpellId = deps.getItemSpellId
    Sort.getSpellName = deps.getSpellName
    Sort.getStatusForSort = deps.getStatusForSort  -- (item) -> display status string for Inventory Status column sort
end

-- Sell table columns: 1=Icon, 2=Action, 3=Name, 4=Status, 5=Value, 6=Stack, 7=Type (sortable are 3-7)
function Sort.getSellSortVal(item, col)
    if not item then return "" end
    if col == 3 then return tostring(item.name or ""):lower()
    elseif col == 4 then return tostring(item.sellReason or ""):lower()
    elseif col == 5 then return tonumber(item.totalValue) or 0
    elseif col == 6 then return tonumber(item.stackSize) or 0
    elseif col == 7 then return tostring(item.type or ""):lower()
    end
    return ""
end

local function getInvSortVal(item, col)
    if not item then return "" end
    if col == 1 then return tostring(item.name or ""):lower()
    elseif col == 2 then return tonumber(item.totalValue) or 0
    elseif col == 3 then return tonumber(item.weight) or 0
    elseif col == 4 then return tostring(item.type or ""):lower()
    elseif col == 5 then return tonumber(item.bag) or 0
    elseif col == 6 then
        if item.clicky and item.clicky > 0 then
            local spellName = Sort.getSpellName(item.clicky) or ""
            return tostring(spellName):lower()
        else
            return "zzz_no_clicky"
        end
    end
    return ""
end

function Sort.getBankSortVal(item, col)
    if not item then return "" end
    if col == 1 then return tostring(item.name or ""):lower()
    elseif col == 2 then return tonumber(item.bag) or 0
    elseif col == 3 then return tonumber(item.slot) or 0
    elseif col == 4 then return tonumber(item.totalValue) or 0
    elseif col == 5 then return tonumber(item.stackSize) or 0
    elseif col == 6 then return tostring(item.type or ""):lower()
    end
    return ""
end

function Sort.getSortValByKey(item, colKey, view)
    if not item then return "" end
    local key = colKey or ""
    if key == "Name" then return tostring(item.name or ""):lower()
    elseif key == "Value" then return tonumber(item.totalValue) or 0
    elseif key == "Weight" then return tonumber(item.weight) or 0
    elseif key == "Type" then return tostring(item.type or ""):lower()
    elseif key == "Bag" then return tonumber(item.bag) or 0
    elseif key == "Slot" then return tonumber(item.slot) or 0
    elseif key == "Stack" then return tonumber(item.stackSize) or 0
    elseif key == "StackSizeMax" then return tonumber(item.stackSizeMax) or 0
    elseif key == "ID" then return tonumber(item.id) or 0
    elseif key == "Icon" then return tonumber(item.icon) or 0
    elseif key == "AugSlots" then return tonumber(item.augSlots) or 0
    elseif key == "Container" then return tonumber(item.container) or 0
    elseif key == "Size" then return tonumber(item.size) or 0
    elseif key == "SizeCapacity" then return tonumber(item.sizeCapacity) or 0
    elseif key == "Tribute" then return tonumber(item.tribute) or 0
    elseif key == "RequiredLevel" then return tonumber(item.requiredLevel) or 0
    elseif key == "RecommendedLevel" then return tonumber(item.recommendedLevel) or 0
    elseif key == "InstrumentMod" then return tonumber(item.instrumentMod) or 0
    elseif key == "NoDrop" then return item.nodrop and "1" or "0"
    elseif key == "NoTrade" then return item.notrade and "1" or "0"
    elseif key == "NoRent" then return item.norent and "1" or "0"
    elseif key == "Lore" then return item.lore and "1" or "0"
    elseif key == "Magic" then return item.magic and "1" or "0"
    elseif key == "Quest" then return item.quest and "1" or "0"
    elseif key == "Collectible" then return item.collectible and "1" or "0"
    elseif key == "Heirloom" then return item.heirloom and "1" or "0"
    elseif key == "Prestige" then return item.prestige and "1" or "0"
    elseif key == "Attuneable" then return item.attuneable and "1" or "0"
    elseif key == "Tradeskills" then return item.tradeskills and "1" or "0"
    elseif key == "Class" then return tostring(item.class or ""):lower()
    elseif key == "Race" then return tostring(item.race or ""):lower()
    elseif key == "WornSlots" then return tostring(item.wornSlots or ""):lower()
    elseif key == "InstrumentType" then return tostring(item.instrumentType or ""):lower()
    elseif key == "Proc" then
        local pid = Sort.getItemSpellId(item, "Proc")
        if pid > 0 then return (Sort.getSpellName(pid) or ""):lower()
        else return "zzz_no_proc" end
    elseif key == "Focus" then
        local fid = Sort.getItemSpellId(item, "Focus")
        if fid > 0 then return (Sort.getSpellName(fid) or ""):lower()
        else return "zzz_no_focus" end
    elseif key == "Spell" then
        local sid = Sort.getItemSpellId(item, "Spell")
        if sid > 0 then return (Sort.getSpellName(sid) or ""):lower()
        else return "zzz_no_spell" end
    elseif key == "Worn" then
        local wid = Sort.getItemSpellId(item, "Worn")
        if wid > 0 then return (Sort.getSpellName(wid) or ""):lower()
        else return "zzz_no_worn" end
    elseif key == "Acquired" then return tonumber(item.acquiredSeq) or 0
    elseif key == "Status" then
        -- Sort alphabetically by displayed status text
        if view == "Sell" then
            local reason = tostring(item.sellReason or ""):lower()
            if reason == "epic" then return "epicquest" end
            return reason
        elseif view == "Inventory" or view == "Bank" then
            if Sort.getStatusForSort then
                local displayStatus = Sort.getStatusForSort(item) or ""
                return tostring(displayStatus):lower()
            end
            return ""
        end
    elseif key == "Clicky" then
        local cid = Sort.getItemSpellId(item, "Clicky")
        if cid > 0 then
            return (Sort.getSpellName(cid) or ""):lower()
        else
            return "zzz_no_clicky"
        end
    end
    return ""
end

--- Pre-compute sort keys (Schwartzian transform): O(n) key computations instead of O(n*log(n)).
--- Returns decorated array of {item, key} pairs. Call Sort.undecorate() after table.sort to restore.
function Sort.precomputeKeys(items, colKey, view)
    local decorated = {}
    for i, item in ipairs(items) do
        decorated[i] = { item = item, key = Sort.getSortValByKey(item, colKey, view) }
    end
    return decorated
end

--- Undecorate: extract items back from {item, key} pairs into the original array.
function Sort.undecorate(decorated, target)
    for i = #target, 1, -1 do target[i] = nil end
    for i, pair in ipairs(decorated) do target[i] = pair.item end
    return target
end

--- Stable sort tie-breaker: when primary keys are equal, order by bag/slot so relative order is preserved.
local function tieBreak(a, b, dir)
    local ta = (a.bag or 0) * 1000 + (a.slot or 0)
    local tb = (b.bag or 0) * 1000 + (b.slot or 0)
    if dir == ImGuiSortDirection.Ascending then return ta < tb else return ta > tb end
end

function Sort.makeComparator(getValFunc, col, dir, numericCols)
    return function(a, b)
        if not a or not b then return false end
        local av, bv = getValFunc(a, col), getValFunc(b, col)
        local isNumeric = false
        for _, nc in ipairs(numericCols) do
            if col == nc then isNumeric = true; break end
        end
        if isNumeric then
            local an, bn = tonumber(av) or 0, tonumber(bv) or 0
            if an ~= bn then
                if dir == ImGuiSortDirection.Ascending then return an < bn else return an > bn end
            end
            return tieBreak(a, b, dir)
        else
            local as, bs = tostring(av or ""), tostring(bv or "")
            if as ~= bs then
                if dir == ImGuiSortDirection.Ascending then return as < bs else return as > bs end
            end
            return tieBreak(a, b, dir)
        end
    end
end

return Sort
