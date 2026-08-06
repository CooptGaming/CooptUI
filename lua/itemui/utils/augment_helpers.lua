--[[ augment_helpers.lua: Augment compatibility (socket type, restrictions, worn slot, index, getCompatibleAugments). ]]
local item_tlo = require('itemui.utils.item_tlo')
-- Lazy-load item_tooltip to avoid circular require: item_helpers -> augment_helpers -> item_tooltip -> item_helpers

local M = {}

--- Expand AugType (bitmask or single type) to list of slot type IDs (1-based). Used for "This augment fits in slot types" display.
function M.getAugTypeSlotIds(augType)
    if not augType or augType <= 0 then return {} end
    local list = {}
    local bit32 = bit32
    for slotId = 1, 24 do
        local bit = (bit32 and bit32.lshift and bit32.lshift(1, slotId - 1)) or (2 ^ (slotId - 1))
        local set = (augType == slotId) or (bit32 and bit32.band and bit32.band(augType, bit) ~= 0)
        if set then list[#list + 1] = slotId end
    end
    return list
end

--- True if the augment's worn-slot restriction allows the parent item. Augment can restrict which equipment slot
--- the parent item is worn in (e.g. "Legs Only", "Wrist Only"). Parent must be wearable in at least one slot
--- that the augment allows; if augment allows "All", any parent is ok.
function M.augmentWornSlotAllowsParent(parentIt, augIt)
    if not parentIt then return false end
    local augSlots = item_tlo.getWornSlotIndicesFromTLO(augIt)
    if augSlots == "all" then return true end
    if type(augSlots) ~= "table" or not next(augSlots) then return true end
    local parentSlots = item_tlo.getWornSlotIndicesFromTLO(parentIt)
    if parentSlots == "all" then return true end
    if type(parentSlots) ~= "table" or not next(parentSlots) then return false end
    for idx, _ in pairs(parentSlots) do
        if augSlots[idx] then return true end
    end
    return false
end

--- Same as augmentWornSlotAllowsParent but uses pre-fetched augment worn-slot set (from index) instead of augIt TLO.
function M.augmentWornSlotAllowsParentWithCachedAugSlots(parentIt, augWornSlotSet)
    if not parentIt then return false end
    if augWornSlotSet == "all" then return true end
    if type(augWornSlotSet) ~= "table" or not next(augWornSlotSet) then return true end
    local parentSlots = item_tlo.getWornSlotIndicesFromTLO(parentIt)
    if parentSlots == "all" then return true end
    if type(parentSlots) ~= "table" or not next(parentSlots) then return false end
    for idx, _ in pairs(parentSlots) do
        if augWornSlotSet[idx] then return true end
    end
    return false
end

--- True if the augment's AugRestrictions allow the parent item. Restriction 0 = none; 1 = Armor Only;
--- 2 = Weapons Only; 3 = One-Handed Weapons Only; 4 = 2H Weapons Only; 5-12 = specific weapon types;
--- 13 = Shields Only; 14 = 1H Slash/1H Blunt/H2H; 15 = 1H Blunt/H2H. IDs match AUG_RESTRICTION_NAMES in item_tooltip.
--- If AugRestrictions is ever a bitmask, allow parent when any set bit allows it (OR logic).
function M.augmentRestrictionAllowsParent(parentIt, augRestrictionId)
    if not augRestrictionId or augRestrictionId == 0 then return true end
    if not parentIt then return false end
    local isWeapon, isShield, typeLower = item_tlo.parentItemClassify(parentIt)
    if augRestrictionId == 1 then return not isWeapon end
    if augRestrictionId == 2 then return isWeapon end
    if augRestrictionId == 13 then return isShield end
    if augRestrictionId >= 3 and augRestrictionId <= 15 then
        if not isWeapon then return false end
        if not typeLower or typeLower == "" then return false end
        if augRestrictionId == 3 then return typeLower:find("1h", 1, true) end
        if augRestrictionId == 4 then return typeLower:find("2h", 1, true) end
        if augRestrictionId == 5 then return typeLower:find("1h", 1, true) and typeLower:find("slashing", 1, true) end
        if augRestrictionId == 6 then return typeLower:find("1h", 1, true) and typeLower:find("blunt", 1, true) end
        if augRestrictionId == 7 then return typeLower:find("piercing", 1, true) end
        if augRestrictionId == 8 then return typeLower:find("hand to hand", 1, true) or typeLower:find("h2h", 1, true) end
        if augRestrictionId == 9 then return typeLower:find("2h", 1, true) and typeLower:find("slashing", 1, true) end
        if augRestrictionId == 10 then return typeLower:find("2h", 1, true) and typeLower:find("blunt", 1, true) end
        if augRestrictionId == 11 then return typeLower:find("2h", 1, true) and typeLower:find("piercing", 1, true) end
        if augRestrictionId == 12 then return typeLower:find("ranged", 1, true) end
        if augRestrictionId == 14 then return (typeLower:find("1h", 1, true) and (typeLower:find("slashing", 1, true) or typeLower:find("blunt", 1, true))) or typeLower:find("hand to hand", 1, true) or typeLower:find("h2h", 1, true) end
        if augRestrictionId == 15 then return (typeLower:find("1h", 1, true) and typeLower:find("blunt", 1, true)) or typeLower:find("hand to hand", 1, true) or typeLower:find("h2h", 1, true) end
        return true
    end
    return true
end

-- Augment compatibility index (Task 3.5): built at scan time; each entry
-- { itemRow, augType, augRestrictions, wornSlotIndices }. Declared here rather than
-- below because the census helpers that follow close over it.
local augmentIndex = {}

--- augType -> index entry, so a view holding only an item row can recover the augType the
--- scan already resolved instead of re-reading the TLO per row per frame.
function M.getIndexedAugType(row)
    if not row then return nil end
    for _, e in ipairs(augmentIndex) do
        local r = e.itemRow
        if r == row then return e.augType end
        if r and r.name == row.name and (r.id or 0) == (row.id or row.ID or 0) then return e.augType end
    end
    return nil
end

--- How many of the sockets you are WEARING this augment could go into. Pure arithmetic
--- over dock_state's published census — no TLO reads on the render path (windows pass
--- item 9). Returns nil when the census has not landed yet, which is what the caller
--- degrades on; 0 is a real answer meaning "nothing you wear takes this".
function M.countFittingWornSockets(augType, wornSockets)
    if not (wornSockets and wornSockets.byType) then return nil end
    if not augType or augType <= 0 then return 0 end
    local n = 0
    for socketType, count in pairs(wornSockets.byType) do
        if M.augmentFitsSocket(augType, socketType) then n = n + count end
    end
    return n
end

--- The line itself, one definition so every surface words it identically.
---   census landed, n > 0  ->  "fits 3 of your slots"   (singular stays parallel: a row
---                             that changes shape at n=1 is harder to scan down a column)
---   census landed, n == 0 ->  "fits nothing you wear"  (a conclusion, not "fits 0 of
---                             your slots", which invites a recount)
---   no census yet         ->  today's "types 1, 3" exactly. No spinner, no "counting...",
---                             no dash: each row upgrades in place the frame the census
---                             lands, and a user who never notices the swap lost nothing.
function M.fitsWornLine(augType, wornSockets)
    local n = M.countFittingWornSockets(augType, wornSockets)
    if n == nil then
        local slots = M.getAugTypeSlotIds(tonumber(augType) or 0)
        if #slots == 0 then return "" end
        if #slots == 1 then return string.format("type %d", slots[1]) end
        local ids = {}
        for i = 1, math.min(#slots, 4) do ids[#ids + 1] = tostring(slots[i]) end
        return "types " .. table.concat(ids, ", ") .. ((#slots > 4) and "..." or "")
    end
    if n == 0 then return "fits nothing you wear" end
    return string.format("fits %d of your slots", n)
end

--- Worn slot names accepting this augment, for the hover. Only once the census has run —
--- there is no tooltip before that, rather than an empty one.
function M.fittingWornSlotNames(augType, wornSockets)
    if not (wornSockets and wornSockets.places) then return nil end
    local seen, out = {}, {}
    for _, p in ipairs(wornSockets.places) do
        if M.augmentFitsSocket(augType, p.type) and not seen[p.slot] then
            seen[p.slot] = true
            out[#out + 1] = p.slot
        end
    end
    if #out == 0 then return nil end
    return table.concat(out, ", ")
end

--- Build augment index from inventory + bank for O(N) getCompatibleAugments with no per-augment TLO calls.
--- Call after scanInventory or scanBank so index stays current.
function M.buildAugmentIndex(inventoryItems, bankItemsOrCache)
    augmentIndex = {}
    if not inventoryItems and not bankItemsOrCache then return end
    local seen = {}  -- (bag, slot, source) -> true; skip same slot twice
    local seenByIdName = {}  -- (id, name) -> true; prevent duplicates across inventory AND bank
    local function addFromList(list, fromBank)
        if not list then return end
        for _, row in ipairs(list) do
            local key = tostring(row.bag or 0) .. "_" .. tostring(row.slot or 0) .. "_" .. (row.source or "inv")
            if seen[key] then goto next end
            seen[key] = true
            -- Dedup by ID+name: prevents duplicates when augment moves between slots
            -- (stale scan data may show same augment at old and new location)
            local idName = tostring(row.id or 0) .. "_" .. tostring(row.name or ""):gsub("%s+", " ")
            if seenByIdName[idName] then goto next end
            -- Ornaments must pass this gate too (field: "no available ornaments are
            -- displayed"): their item TYPE is not always "Augmentation" - ornament
            -- rows can carry an "...Ornamentation"-style type - and the type filter
            -- silently excluded them from the index. Anything ornament-typed with a
            -- real AugType joins; the socket-type fit below decides where it goes.
            local rowType = (row.type or ""):lower()
            if rowType == "augmentation" or rowType:find("ornament", 1, true) then
                local src = row.source or "inv"
                local augIt = item_tlo.getItemTLO(row.bag, row.slot, src)
                if augIt and augIt.AugType then
                    local augType = item_tlo.getAugTypeFromTLO(augIt)
                    if augType and augType > 0 then
                        local augRestrictions = item_tlo.getAugRestrictionsFromTLO(augIt)
                        local wornSlotIndices = item_tlo.getWornSlotIndicesFromTLO(augIt)
                        -- Eagerly load class/race/deity so canUseFilter works even if
                        -- the augment moves later and TLO fallback fails.
                        local _ = row.class  -- triggers lazy-load of descriptive fields
                        augmentIndex[#augmentIndex + 1] = {
                            itemRow = row,
                            augType = augType,
                            augRestrictions = augRestrictions or 0,
                            wornSlotIndices = wornSlotIndices,
                        }
                        seenByIdName[idName] = true
                    end
                end
            end
            ::next::
        end
    end
    addFromList(inventoryItems, false)
    addFromList(bankItemsOrCache, true)
end

--- Check if an augment item (with augType from TLO) fits the given socket type.
--- Socket type is from parent item's AugSlotN; augType is augmentation slot type mask from the augment.
function M.augmentFitsSocket(augType, socketType)
    if not socketType or socketType <= 0 then return false end
    if not augType or augType <= 0 then return false end
    if augType == socketType then return true end
    local bit
    if bit32 and bit32.lshift then
        bit = bit32.lshift(1, socketType - 1)
    else
        bit = 2 ^ (socketType - 1)
    end
    if bit32 and bit32.band and bit32.band(augType, bit) ~= 0 then return true end
    return false
end

--- Build list of compatible augments for a given item and slot from inventory + bank.
--- Uses pre-computed augment index when available (Task 3.5): O(N) filtered lookup with no per-augment TLO calls.
--- parentItem must have bag, slot, source; slotIndex is 1-based (1-6, ornament 5 optional).
--- canUseFilter: optional function(itemRow) -> boolean; when provided, only augments that pass
--- (class, race, deity, level for current player) are included.
--- Returns array of item tables (same shape as scan) that are type Augmentation and fully compatible.
function M.getCompatibleAugments(parentItem, bag, slot, source, slotIndex, inventoryItems, bankItemsOrCache, canUseFilter)
    if not parentItem or not slotIndex or slotIndex < 1 or slotIndex > 6 then return {} end
    local b, s, src = bag or parentItem.bag, slot or parentItem.slot, source or parentItem.source or "inv"
    local it = item_tlo.getItemTLO(b, s, src)
    if not it or not it.ID or it.ID() == 0 then return {} end
    local socketType = item_tlo.getSlotType(it, slotIndex)
    if not socketType or socketType <= 0 then return {} end
    -- ORNAMENT sockets (type 20/21) bypass the string-typed index entirely. Two
    -- rounds of guessing ornament TYPE STRINGS have missed in the field ("no
    -- available ornaments are displayed"), so this path asks the only authority:
    -- every bag/bank row's own TLO AugType, probed directly, once per rebuild
    -- (the rebuild is cache-keyed - this never runs per frame). Worn-slot
    -- restriction checks are deliberately skipped for appearance sockets; the
    -- game gates the insert, and a slightly-generous list beats an empty one.
    -- When the result is STILL empty, one console line states the probe counts
    -- so the field can name the mismatch instead of reporting another blank.
    if socketType == 20 or socketType == 21 then
        local out, seenIdName = {}, {}
        local probed, withType, fit = 0, 0, 0
        local function probe(list)
            if not list then return end
            for _, row in ipairs(list) do
                if row and row.id and row.id ~= 0 and row.bag and row.slot then
                    probed = probed + 1
                    local augIt = item_tlo.getItemTLO(row.bag, row.slot, row.source or "inv")
                    if augIt then
                        local at = item_tlo.getAugTypeFromTLO(augIt)
                        if at and at > 0 then
                            withType = withType + 1
                            if M.augmentFitsSocket(at, socketType)
                                and M.augmentRestrictionAllowsParent(it, item_tlo.getAugRestrictionsFromTLO(augIt)) then
                                fit = fit + 1
                                local dedup = tostring(row.id) .. "_" .. (row.name or "")
                                if not seenIdName[dedup]
                                    and not (type(canUseFilter) == "function" and not canUseFilter(row)) then
                                    seenIdName[dedup] = true
                                    out[#out + 1] = row
                                end
                            end
                        end
                    end
                end
            end
        end
        probe(inventoryItems)
        probe(bankItemsOrCache)
        if #out == 0 then
            pcall(function()
                print(string.format(
                    "[CoOpt] ornament scan: %d rows probed . %d carry an AugType . %d fit socket type %d. If an ornament IS in your bags, its AugType is not matching - tell the build its name.",
                    probed, withType, fit, socketType))
            end)
        end
        return out
    end
    local candidates = {}
    if #augmentIndex == 0 and (inventoryItems or bankItemsOrCache) then
        M.buildAugmentIndex(inventoryItems, bankItemsOrCache)
    end
    if #augmentIndex > 0 then
        local seenId = {}  -- dedup by id+name in results (stale index after remove)
        for _, entry in ipairs(augmentIndex) do
            local itemRow = entry.itemRow
            -- Bank-closed: never show bank-only augments when bank window is closed
            if not bankItemsOrCache and (itemRow.source or "inv") == "bank" then goto continue end
            if not M.augmentFitsSocket(entry.augType, socketType) then goto continue end
            if not M.augmentRestrictionAllowsParent(it, entry.augRestrictions) then goto continue end
            if not M.augmentWornSlotAllowsParentWithCachedAugSlots(it, entry.wornSlotIndices) then goto continue end
            -- canUseFilter: class/race/deity/level check (controlled by "Only show usable by me" checkbox)
            if type(canUseFilter) == "function" and not canUseFilter(itemRow) then goto continue end
            -- Dedup: same augment ID+name only appears once in results
            local dedupKey = tostring(itemRow.id or 0) .. "_" .. (itemRow.name or "")
            if seenId[dedupKey] then goto continue end
            seenId[dedupKey] = true
            candidates[#candidates + 1] = itemRow
            ::continue::
        end
        return candidates
    end
    local function addCandidate(itemRow)
        if not itemRow then return end
        -- Same broadened gate as the index build: ornament-typed rows are candidates.
        local rowType = (itemRow.type or ""):lower()
        if rowType ~= "augmentation" and not rowType:find("ornament", 1, true) then return end
        local augIt = item_tlo.getItemTLO(itemRow.bag, itemRow.slot, itemRow.source or "inv")
        if not augIt or not augIt.AugType then return end
        local augId = (type(augIt.ID) == "function" and augIt.ID()) or augIt.ID
        if not augId or augId == 0 then return end
        local augType = item_tlo.getAugTypeFromTLO(augIt)
        if not M.augmentFitsSocket(augType, socketType) then return end
        local augRestrictions = item_tlo.getAugRestrictionsFromTLO(augIt)
        if not M.augmentRestrictionAllowsParent(it, augRestrictions) then return end
        if not M.augmentWornSlotAllowsParent(it, augIt) then return end
        -- canUseFilter: class/race/deity/level check (controlled by "Only show usable by me" checkbox)
        if type(canUseFilter) == "function" and not canUseFilter(itemRow) then return end
        candidates[#candidates + 1] = itemRow
    end
    if inventoryItems then
        for _, row in ipairs(inventoryItems) do addCandidate(row) end
    end
    if bankItemsOrCache then
        for _, row in ipairs(bankItemsOrCache) do addCandidate(row) end
    end
    return candidates
end

return M
