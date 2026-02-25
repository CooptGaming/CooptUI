--[[ item_tlo.lua: MQ item TLO resolution and property readers. No cache, no deps. ]]
local mq = require('mq')

local M = {}

--- Get item TLO for the given location. source = "bank" uses Me.Bank(bag).Item(slot), "corpse" uses Corpse.Item(slot),
--- "equipped" uses InvSlot(slot) for slot 0-22 (0-based equipment slots), else Me.Inventory("pack"..bag).Item(slot).
--- Bag and slot are 1-based (same as stored on item tables) for inv/bank. For corpse, bag is ignored and slot is corpse loot slot (1-based).
--- For equipped, bag is ignored and slot is 0-based equipment slot index (0-22). Returns nil if TLO not available.
function M.getItemTLO(bag, slot, source)
    if source == "bank" then
        local bn = mq.TLO and mq.TLO.Me and mq.TLO.Me.Bank and mq.TLO.Me.Bank(bag or 0)
        if not bn then return nil end
        return bn.Item and bn.Item(slot or 0)
    elseif source == "corpse" then
        local corpse = mq.TLO and mq.TLO.Corpse
        if not corpse or not corpse.Item then return nil end
        return corpse.Item(slot or 0)
    elseif source == "equipped" then
        local slotIndex = tonumber(slot)
        if slotIndex == nil or slotIndex < 0 or slotIndex > 22 then return nil end
        local Me = mq.TLO and mq.TLO.Me
        if not Me or not Me.Inventory then return nil end
        local function isItem(obj)
            if not obj or not obj.ID then return false end
            local ok, id = pcall(function() return obj.ID() end)
            return ok and id and id ~= 0
        end
        local ok1, direct = pcall(function()
            local inv = Me.Inventory(slotIndex)
            if isItem(inv) then return inv end
            return nil
        end)
        if ok1 and direct then return direct end
        local okB, invB = pcall(function() return Me.Inventory[slotIndex] end)
        if okB and invB and isItem(invB) then return invB end
        local slotNames = {
            [0] = "charm", [1] = "leftear", [2] = "head", [3] = "face", [4] = "rightear",
            [5] = "neck", [6] = "shoulder", [7] = "arms", [8] = "back", [9] = "leftwrist",
            [10] = "rightwrist", [11] = "ranged", [12] = "hands", [13] = "mainhand", [14] = "offhand",
            [15] = "leftfinger", [16] = "rightfinger", [17] = "chest", [18] = "legs", [19] = "feet",
            [20] = "waist", [21] = "powersource", [22] = "ammo",
        }
        local name = slotNames[slotIndex]
        if name then
            local ok2, byName = pcall(function()
                local inv = Me.Inventory(name)
                if isItem(inv) then return inv end
                return nil
            end)
            if ok2 and byName then return byName end
        end
        local ok3, slotObj = pcall(function()
            return mq.TLO and mq.TLO.InvSlot and mq.TLO.InvSlot(slotIndex)
        end)
        if not ok3 or not slotObj or not slotObj.Item then return nil end
        local item = nil
        if type(slotObj.Item) == "function" then
            local ok4, res = pcall(function() return slotObj.Item() end)
            if ok4 and res then item = res end
        else
            item = slotObj.Item
        end
        if not isItem(item) then return nil end
        return item
    else
        local pack = mq.TLO and mq.TLO.Me and mq.TLO.Me.Inventory and mq.TLO.Me.Inventory("pack" .. (bag or 0))
        if not pack then return nil end
        return pack.Item and pack.Item(slot or 0)
    end
end

--- Item lore text (flavor string) from item TLO. Returns string or nil. Safe to call with nil it.
function M.getItemLoreText(it)
    if not it then return nil end
    local ok, val = pcall(function()
        if it.LoreText and it.LoreText() and tostring(it.LoreText()):match("%S") then return tostring(it.LoreText()) end
        if it.Lore then
            local v = it.Lore()
            if type(v) == "string" and v:match("%S") then return v end
        end
        return nil
    end)
    return (ok and val and val ~= "") and val or nil
end

-- Slot index (0-22) to display name; WornSlots is count, WornSlot(N) returns Nth slot index.
local SLOT_DISPLAY_NAMES = {
    [0] = "Charm", [1] = "Ear", [2] = "Head", [3] = "Face", [4] = "Ear",
    [5] = "Neck", [6] = "Shoulder", [7] = "Arms", [8] = "Back", [9] = "Wrist",
    [10] = "Wrist", [11] = "Ranged", [12] = "Hands", [13] = "Primary", [14] = "Secondary",
    [15] = "Ring", [16] = "Ring", [17] = "Chest", [18] = "Legs", [19] = "Feet",
    [20] = "Waist", [21] = "Power", [22] = "Ammo",
}

-- Slot names for /itemnotify <name> leftmouseup (MQ2 equipment slot names).
local SLOT_NAMES_ITEMNOTIFY = {
    [0] = "charm", [1] = "leftear", [2] = "head", [3] = "face", [4] = "rightear",
    [5] = "neck", [6] = "shoulder", [7] = "arms", [8] = "back", [9] = "leftwrist",
    [10] = "rightwrist", [11] = "ranged", [12] = "hands", [13] = "mainhand", [14] = "offhand",
    [15] = "leftfinger", [16] = "rightfinger", [17] = "chest", [18] = "legs", [19] = "feet",
    [20] = "waist", [21] = "powersource", [22] = "ammo",
}

local function slotIndexToDisplayName(s)
    if s == nil or s == "" then return nil end
    local n = tonumber(s)
    if n ~= nil and SLOT_DISPLAY_NAMES[n] then return SLOT_DISPLAY_NAMES[n] end
    local str = tostring(s):lower():gsub("^%l", string.upper)
    return (str ~= "") and str or nil
end

--- Return display label for equipment slot 0-22 (e.g. "Primary", "Charm"). For Equipment Companion grid labels.
function M.getEquipmentSlotLabel(slotIndex)
    local n = tonumber(slotIndex)
    if n == nil or n < 0 or n > 22 then return nil end
    return SLOT_DISPLAY_NAMES[n]
end

--- Return MQ2 slot name for equipment slot 0-22 for use with /itemnotify <name> leftmouseup (pickup, equip, put-back).
function M.getEquipmentSlotNameForItemNotify(slotIndex)
    local n = tonumber(slotIndex)
    if n == nil or n < 0 or n > 22 then return nil end
    return SLOT_NAMES_ITEMNOTIFY[n]
end

--- Return display name for a single slot token (0-22 or name). Used by tooltip slotStringToDisplay.
function M.getSlotDisplayName(s)
    return slotIndexToDisplayName(s)
end

--- Build comma-separated list of slot names from item TLO. WornSlots() is the count; WornSlot(N) is the Nth slot.
function M.getWornSlotsStringFromTLO(it)
    if not it or not it.WornSlots or not it.WornSlot then return "" end
    local nSlots = it.WornSlots()
    if not nSlots or nSlots <= 0 then return "" end
    if nSlots >= 20 then return "All" end
    local seen, parts = {}, {}
    for i = 1, nSlots do
        local s = it.WornSlot(i)
        local name = s and slotIndexToDisplayName(tostring(s)) or ""
        if name ~= "" and not seen[name] then seen[name] = true; parts[#parts + 1] = name end
    end
    return (#parts > 0) and table.concat(parts, ", ") or ""
end

--- Get set of worn slot indices (0-22) for an item TLO. Returns table slotIndex -> true, or "all" if item can be worn in all slots (WornSlots >= 20).
function M.getWornSlotIndicesFromTLO(it)
    if not it or not it.WornSlots or not it.WornSlot then return {} end
    local nSlots = it.WornSlots()
    if not nSlots or nSlots <= 0 then return {} end
    if nSlots >= 20 then return "all" end
    local set = {}
    for i = 1, nSlots do
        local s = it.WornSlot(i)
        local idx = (s ~= nil and s ~= "") and tonumber(tostring(s)) or nil
        if idx ~= nil and idx >= 0 and idx <= 22 then set[idx] = true end
    end
    return set
end

--- Count augment slots: AugSlot1-6 return slot type (int); 0 = no slot, >0 = has slot.
function M.getAugSlotsCountFromTLO(it)
    if not it then return 0 end
    local n = 0
    for _, accessor in ipairs({ "AugSlot1", "AugSlot2", "AugSlot3", "AugSlot4", "AugSlot5", "AugSlot6" }) do
        local fn = it[accessor]
        if fn then
            local v = fn()
            if type(v) == "number" and v > 0 then n = n + 1 end
        end
    end
    return n
end

--- Get socket type for slot index (1-based). Tries AugSlot# then AugSlot(i).Type. Returns 0 if unknown.
function M.getSlotType(it, slotIndex)
    if not it then return 0 end
    local typ = 0
    local acc = it["AugSlot" .. slotIndex]
    if acc ~= nil then
        typ = tonumber(type(acc) == "function" and acc() or acc) or 0
    end
    if typ == 0 then
        local ok, aug = pcall(function() return it.AugSlot and it.AugSlot(slotIndex) end)
        if ok and aug then
            local t = (type(aug.Type) == "function" and aug.Type()) or aug.Type
            typ = tonumber(t) or tonumber(tostring(t)) or 0
        end
    end
    return typ
end

local ORNAMENT_SLOT_INDEX = 5
local ORNAMENT_SOCKET_TYPE = 20

--- True if item has ornament slot (slot 5, type 20). Used to exclude ornament from "standard" augment slot count in UI.
function M.itemHasOrnamentSlot(it)
    if not it then return false end
    return M.getSlotType(it, ORNAMENT_SLOT_INDEX) == ORNAMENT_SOCKET_TYPE
end

--- Return list of 1-based standard augment slot indices (1-4) that currently have an augment (it.Item(i) ID > 0).
function M.getFilledStandardAugmentSlotIndices(it)
    if not it or not it.Item then return {} end
    local out = {}
    for i = 1, 4 do
        local ok, sock = pcall(function() return it.Item(i) end)
        if ok and sock and sock.ID then
            local okId, idVal = pcall(function() return sock.ID() end)
            if not okId then idVal = (type(sock.ID) == "function" and sock.ID()) or sock.ID end
            local idNum = tonumber(idVal)
            if idNum and idNum > 0 then out[#out + 1] = i end
        end
    end
    return out
end

--- Count of standard augment slots (1-4 only) that actually have a socket type > 0.
function M.getStandardAugSlotsCountFromTLO(it)
    if not it then return 0 end
    local n = 0
    for i = 1, 4 do
        if M.getSlotType(it, i) > 0 then n = n + 1 end
    end
    return n
end

--- Get AugType from item TLO (for augmentation items). Returns number or 0.
function M.getAugTypeFromTLO(it)
    if not it or not it.AugType then return 0 end
    local ok, v = pcall(function() return it.AugType() end)
    if not ok or not v then return 0 end
    return tonumber(v) or 0
end

--- Get AugRestrictions from item TLO (for augmentation items). Returns int: 0=none, 1-15=single restriction (live EQ).
function M.getAugRestrictionsFromTLO(it)
    if not it or not it.AugRestrictions then return 0 end
    local ok, v = pcall(function() return it.AugRestrictions() end)
    if not ok or not v then return 0 end
    return tonumber(v) or 0
end

--- Classify parent item TLO as weapon/shield/armor and optional weapon subtype for augment restriction checks.
function M.parentItemClassify(it)
    if not it then return false, false, "" end
    local typeStr = ""
    if it.Type then
        local ok, v = pcall(function() return it.Type() end)
        if ok and v then typeStr = tostring(v):lower() end
    end
    local dmg = 0
    if it.Damage then local ok, v = pcall(function() return it.Damage() end); if ok and v then dmg = tonumber(v) or 0 end end
    local delay = 0
    if it.ItemDelay then local ok, v = pcall(function() return it.ItemDelay() end); if ok and v then delay = tonumber(v) or 0 end end
    local isWeapon = (dmg and dmg ~= 0) or (delay and delay ~= 0) or (typeStr ~= "" and (typeStr:find("piercing") or typeStr:find("slashing") or typeStr:find("1h") or typeStr:find("2h") or typeStr:find("ranged")))
    local isShield = typeStr ~= "" and typeStr:find("shield")
    return isWeapon, isShield, typeStr
end

--- Returns isWeapon (boolean), parentDamage (number), parentDelay (number) for ranking (e.g. augment damage as % of weapon).
function M.getParentWeaponInfo(it)
    if not it then return false, 0, 0 end
    local dmg, delay = 0, 0
    if it.Damage then local ok, v = pcall(function() return it.Damage() end); if ok and v then dmg = tonumber(v) or 0 end end
    if it.ItemDelay then local ok, v = pcall(function() return it.ItemDelay() end); if ok and v then delay = tonumber(v) or 0 end end
    local isWeapon = M.parentItemClassify(it)
    return isWeapon, dmg, delay
end

--- Build class and race display strings from item TLO (Classes()/Class(i), Races()/Race(i)).
function M.getClassRaceStringsFromTLO(it)
    if not it or not it.ID or it.ID() == 0 then return "", "" end
    local function add(parts, fn, n)
        if not n or n <= 0 then return end
        for i = 1, n do local v = fn(i); if v and v ~= "" then parts[#parts + 1] = tostring(v) end end
        if #parts == 0 then for i = 0, n - 1 do local v = fn(i); if v and v ~= "" then parts[#parts + 1] = tostring(v) end end end
    end
    local clsStr, raceStr = "", ""
    local nClass = it.Classes and it.Classes()
    if nClass and nClass > 0 then
        if nClass >= 16 then clsStr = "All"
        else local p = {}; add(p, function(i) local c = it.Class and it.Class(i); return c end, nClass); clsStr = table.concat(p, " ") end
    end
    local nRace = it.Races and it.Races()
    if nRace and nRace > 0 then
        if nRace >= 15 then raceStr = "All"
        else local p = {}; add(p, function(i) local r = it.Race and it.Race(i); return r end, nRace); raceStr = table.concat(p, " ") end
    end
    return clsStr, raceStr
end

--- Class, race, and slot display strings from item TLO. Returns clsStr, raceStr, slotStr (single call for tooltip).
function M.getClassRaceSlotFromTLO(it)
    local c, r = M.getClassRaceStringsFromTLO(it)
    local s = M.getWornSlotsStringFromTLO(it)
    return c, r, s
end

--- Build deity display string from item TLO (Deities()/Deity(i)). Returns "" if no deity restriction.
function M.getDeityStringFromTLO(it)
    if not it or not it.ID or it.ID() == 0 then return "" end
    local nDeities = it.Deities and it.Deities()
    if not nDeities or nDeities <= 0 then return "" end
    local parts = {}
    for i = 1, nDeities do
        local ok, v = pcall(function()
            local fn = it.Deity and it.Deity(i)
            return (type(fn) == "function" and fn()) or fn
        end)
        if ok and v and tostring(v) ~= "" and tostring(v):lower() ~= "null" then
            parts[#parts + 1] = tostring(v)
        end
    end
    if #parts == 0 then
        for i = 0, nDeities - 1 do
            local ok, v = pcall(function()
                local fn = it.Deity and it.Deity(i)
                return (type(fn) == "function" and fn()) or fn
            end)
            if ok and v and tostring(v) ~= "" and tostring(v):lower() ~= "null" then
                parts[#parts + 1] = tostring(v)
            end
        end
    end
    return (#parts > 0) and table.concat(parts, " ") or ""
end

return M
