--[[ augment_helpers.lua: Augment compatibility (socket type, restrictions, worn slot, index, getCompatibleAugments). ]]
local item_tlo = require('itemui.utils.item_tlo')

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

-- Augment compatibility index (Task 3.5): built at scan time; each entry { itemRow, augType, augRestrictions, wornSlotIndices }.
local augmentIndex = {}

--- Build augment index from inventory + bank for O(N) getCompatibleAugments with no per-augment TLO calls.
--- Call after scanInventory or scanBank so index stays current.
function M.buildAugmentIndex(inventoryItems, bankItemsOrCache)
    augmentIndex = {}
    if not inventoryItems and not bankItemsOrCache then return end
    local function addFromList(list)
        if not list then return end
        for _, row in ipairs(list) do
            if (row.type or ""):lower() == "augmentation" then
                local src = row.source or "inv"
                local augIt = item_tlo.getItemTLO(row.bag, row.slot, src)
                if augIt and augIt.AugType then
                    local augType = item_tlo.getAugTypeFromTLO(augIt)
                    if augType and augType > 0 then
                        local augRestrictions = item_tlo.getAugRestrictionsFromTLO(augIt)
                        local wornSlotIndices = item_tlo.getWornSlotIndicesFromTLO(augIt)
                        augmentIndex[#augmentIndex + 1] = {
                            itemRow = row,
                            augType = augType,
                            augRestrictions = augRestrictions or 0,
                            wornSlotIndices = wornSlotIndices,
                        }
                    end
                end
            end
        end
    end
    addFromList(inventoryItems)
    addFromList(bankItemsOrCache)
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
    local candidates = {}
    if #augmentIndex == 0 and (inventoryItems or bankItemsOrCache) then
        M.buildAugmentIndex(inventoryItems, bankItemsOrCache)
    end
    if #augmentIndex > 0 then
        for _, entry in ipairs(augmentIndex) do
            local itemRow = entry.itemRow
            if not M.augmentFitsSocket(entry.augType, socketType) then goto continue end
            if not M.augmentRestrictionAllowsParent(it, entry.augRestrictions) then goto continue end
            if not M.augmentWornSlotAllowsParentWithCachedAugSlots(it, entry.wornSlotIndices) then goto continue end
            if type(canUseFilter) == "function" and not canUseFilter(itemRow) then goto continue end
            candidates[#candidates + 1] = itemRow
            ::continue::
        end
        return candidates
    end
    local function addCandidate(itemRow)
        if not itemRow or (itemRow.type or ""):lower() ~= "augmentation" then return end
        local augIt = item_tlo.getItemTLO(itemRow.bag, itemRow.slot, itemRow.source or "inv")
        if not augIt or not augIt.AugType then return end
        local augId = (type(augIt.ID) == "function" and augIt.ID()) or augIt.ID
        if not augId or augId == 0 then return end
        local augType = item_tlo.getAugTypeFromTLO(augIt)
        if not M.augmentFitsSocket(augType, socketType) then return end
        local augRestrictions = item_tlo.getAugRestrictionsFromTLO(augIt)
        if not M.augmentRestrictionAllowsParent(it, augRestrictions) then return end
        if not M.augmentWornSlotAllowsParent(it, augIt) then return end
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
