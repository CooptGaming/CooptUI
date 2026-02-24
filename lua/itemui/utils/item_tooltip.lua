--[[
    Item stats tooltip: matches in-game Item Display (Description) for all items.
    Shows every property: name, ID, type, class/race/slot, augment slots, item info,
    primary stats (base+heroic), resistances, combat/utility stats, item effects, value.
    Used by Inventory, Bank, Sell, and Augments views on icon hover.
    opts.source = "inv" (default) or "bank" for Class/Race/Slot TLO when not cached.
--]]

local mq = require('mq')
require('ImGui')
local ItemUtils = require('mq.ItemUtils')
local itemHelpers = require('itemui.utils.item_helpers')

local ItemTooltip = {}

local TOOLTIP_MIN_WIDTH = 760  -- two columns full layout
local TOOLTIP_COL_WIDTH = 380  -- each column at full width
local TOOLTIP_COMPACT_WIDTH = 560  -- narrower for items with less content
local TOOLTIP_COMPACT_COL = 280   -- column width when compact
local TOOLTIP_LINE_HEIGHT = 18   -- ensure stats and spell info rows fit
local TOOLTIP_PADDING = 20       -- margin so bottom content isn't cut off
local TOOLTIP_EXTRA_ROWS = 4     -- buffer so all stats/effects are visible (no truncation)
-- Approximate chars per line for row counting (column width ~380px)
local CHARS_PER_LINE_NAME = 48
local CHARS_PER_LINE_DESC = 52

--- Set tooltip window size for the next BeginTooltip. Call with (width, height) from prepareTooltipContent so each item gets correct size (no reuse of previous tooltip size).
function ItemTooltip.beginItemTooltip(width, height)
    if ImGui.SetNextWindowSize and width and height and width > 0 and height > 0 then
        local ok = pcall(function()
            ImGui.SetNextWindowSize(ImVec2(width, height), ImGuiCond.Always)
        end)
        if not ok then
            -- fallback: minimum width so two columns fit
            pcall(function() ImGui.SetNextWindowSize(ImVec2(TOOLTIP_MIN_WIDTH, 0), ImGuiCond.Always) end)
        end
    end
    ImGui.BeginTooltip()
end

local function slotStringToDisplay(str)
    if not str or str == "" then return str end
    local seen = {}
    local parts = {}
    for token in tostring(str):gmatch("[^,%s]+") do
        local name = itemHelpers.getSlotDisplayName(token)
        if name and not seen[name] then seen[name] = true; parts[#parts + 1] = name end
    end
    return (#parts > 0) and table.concat(parts, ", ") or str
end

local SIZE_NAMES = { [1] = "SMALL", [2] = "MEDIUM", [3] = "LARGE", [4] = "GIANT" }
local function formatSize(item)
    if not item or not item.size then return nil end
    return SIZE_NAMES[item.size] or tostring(item.size)
end

--- Build type line: flags (Magic, Lore, etc.) and item type (e.g. Augmentation), like in-game.
local function getTypeLine(item)
    local parts = {}
    if item.magic then parts[#parts + 1] = "Magic" end
    if item.lore then parts[#parts + 1] = "Lore" end
    if item.nodrop then parts[#parts + 1] = "No Drop" end
    if item.notrade then parts[#parts + 1] = "No Trade" end
    if item.norent then parts[#parts + 1] = "No Rent" end
    if item.quest then parts[#parts + 1] = "Quest" end
    if item.collectible then parts[#parts + 1] = "Collectible" end
    if item.heirloom then parts[#parts + 1] = "Heirloom" end
    if item.prestige then parts[#parts + 1] = "Prestige" end
    if item.attuneable then parts[#parts + 1] = "Attuneable" end
    if item.tradeskills then parts[#parts + 1] = "Tradeskills" end
    if item.type and item.type ~= "" then parts[#parts + 1] = item.type end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

--- Attribute line: "Label: base" or "Label: base+heroic"
local function attrLine(base, heroic, label)
    local b, h = base or 0, heroic or 0
    if b == 0 and h == 0 then return nil end
    if h > 0 then return string.format("%s: %d+%d", label, b, h) end
    return string.format("%s: %d", label, b)
end

-- Augment slot type ID to display name (in-game style). Extended to match default Item Display.
local AUG_TYPE_NAMES = {
    [1] = "General: Single", [2] = "General: Multiple Stat", [3] = "Armor: Visible", [4] = "Weapon: General",
    [5] = "Weapon: Secondary", [6] = "General: Raid", [7] = "General: Group", [8] = "General: Raid",
    [9] = "Energeian", [10] = "Crafted: Common", [11] = "Crafted: Group", [12] = "Crafted: Raid",
    [13] = "Energeiac: Group", [14] = "Energeiac: Raid", [15] = "Crafted: Common", [16] = "Crafted: Group",
    [17] = "Crafted: Raid", [18] = "Type 18", [19] = "Type 19",
    [20] = "Ornamentation",
}

-- Augment restriction ID to display text (0 = no restriction, omit).
-- IDs match live EQ / default Item Display. If value is ever a bitmask, decode via bit and join names (see comment near "Restriction " fallback).
local AUG_RESTRICTION_NAMES = {
    [1] = "Armor Only", [2] = "Weapons Only", [3] = "One-Handed Weapons Only", [4] = "2H Weapons Only",
    [5] = "1H Slashing", [6] = "1H Blunt", [7] = "Piercing", [8] = "Hand to Hand",
    [9] = "2H Slashing", [10] = "2H Blunt", [11] = "2H Piercing", [12] = "Ranged",
    [13] = "Shields Only", [14] = "1H Slashing, 1H Blunt, or Hand to Hand", [15] = "1H Blunt or Hand to Hand",
}

-- Slot layout: 1-4 = augment slots, 5 = ornament (type 20). All 1-based per ITEM_INDEX_BASE.
local ORNAMENT_SLOT_INDEX = 5
local AUGMENT_SLOT_COUNT = 4

--- Core: build augment slot lines from item TLO (slots 1-4 only; slot 5 is ornament, shown separately).
--- Uses itemHelpers.getStandardAugSlotsCountFromTLO(it) when available so CoOpt Item Display and tooltips
--- never show phantom slots (e.g. "Slot 3" when item only has slots 1, 2 and ornament). Fallback: augSlots - 1 if ornament.
--- Returns { iconId, text } per row. Uses itemHelpers.getSlotType for type; name/icon from AugSlot(i).Name or Item(i). All indices 1-based.
local function getAugmentSlotLinesFromIt(it, augSlots)
    if not it or not it.ID or it.ID() == 0 then return nil end
    local numSlots = (it and itemHelpers.getStandardAugSlotsCountFromTLO(it)) or 0
    if numSlots == 0 then
        local hasOrnament = itemHelpers.itemHasOrnamentSlot(it)
        local raw = (augSlots or 0)
        numSlots = math.min(AUGMENT_SLOT_COUNT, hasOrnament and (raw - 1) or raw)
    end
    if numSlots < 1 then return nil end
    local lines = {}
    for i = 1, numSlots do
        local typ = itemHelpers.getSlotType(it, i)
        local augName = "empty"
        if typ > 0 then
            local okAug, aug = pcall(function() return it.AugSlot and it.AugSlot(i) end)
            if okAug and aug and aug.Name then
                local nOk, nVal = pcall(function() return type(aug.Name) == "function" and aug.Name() or aug.Name end)
                if nOk and nVal and tostring(nVal) ~= "" then augName = tostring(nVal) end
            end
            if augName == "empty" then
                local ok, itemN = pcall(function() return it.Item and it.Item(i) end)
                if ok and itemN and itemN.Name then
                    local nameOk, nameVal = pcall(function() return itemN.Name() end)
                    if nameOk and nameVal and tostring(nameVal) ~= "" then augName = tostring(nameVal) end
                end
            end
            if augName == "" or tostring(augName):lower() == "null" then augName = "empty" end
        end
        local line, iconId
        if typ > 0 then
            local typeName = AUG_TYPE_NAMES[typ] or ("Type " .. tostring(typ))
            line = string.format("Slot %d, type %d (%s): %s", i, typ, typeName, augName)
            iconId = 0
            if augName ~= "empty" then
                local okI, ico = pcall(function()
                    local itemN = it.Item and it.Item(i)
                    return itemN and itemN.Icon and itemN.Icon()
                end)
                if okI and ico then iconId = tonumber(ico) or 0 end
            end
        else
            line = string.format("Slot %d: empty", i)
            iconId = 0
        end
        -- Defensive: type 20 is ornament (slot 5); we only iterate 1-4 so this should not trigger.
        if typ ~= 20 then
            local typeNameForPrefix = (typ > 0) and (AUG_TYPE_NAMES[typ] or ("Type " .. tostring(typ))) or "empty"
            local prefix = string.format("Slot %d, type %d (%s): ", i, typ, typeNameForPrefix)
            lines[#lines + 1] = { iconId = iconId, text = line, prefix = prefix, augName = augName, slotIndex = i }
        end
    end
    return lines
end

--- Augment slot lines from bag/slot/source (resolves TLO then calls getAugmentSlotLinesFromIt).
local function getAugmentSlotLines(bag, slot, source, augSlots)
    local it = itemHelpers.getItemTLO(bag, slot, source)
    return getAugmentSlotLinesFromIt(it, augSlots)
end

--- Build item stats table for the item in socket socketIndex of parent at (bag, slot, source). Used for link tooltips.
local function getSocketItemStats(it, bag, slot, source, socketIndex)
    if not it or not it.Item or not bag or not slot or not source or not socketIndex then return nil end
    local ok, socketTLO = pcall(function() return it.Item(socketIndex) end)
    if not ok or not socketTLO or not socketTLO.ID or socketTLO.ID() == 0 then return nil end
    return itemHelpers.buildItemFromMQ(socketTLO, bag, slot, source, socketIndex)
end

--- Ornament name from item TLO. See getOrnamentFromIt: slot 5 type 20 first, then it.Ornament fallback.
local function getOrnamentNameFromIt(it)
    local o = getOrnamentFromIt(it)
    return o and o.name or nil
end

--- Ornament name and icon from item TLO. Returns { name = string, iconId = number } or nil.
--- Primary: slot 5 (1-based per ITEM_INDEX_BASE) is ornament (type 20). Get name/icon from Item(5).
local function getOrnamentFromIt(it)
    if not it or not it.ID or it.ID() == 0 then return nil end
    if itemHelpers.getSlotType(it, ORNAMENT_SLOT_INDEX) ~= 20 then
        -- Fallback: it.Ornament when slot 5 does not report type 20.
        local okO, ornamentObj = pcall(function() return it.Ornament end)
        if okO and ornamentObj then
            local okN, nameVal = pcall(function()
                return ornamentObj.Name and (type(ornamentObj.Name) == "function" and ornamentObj.Name() or ornamentObj.Name)
            end)
            local name = (okN and nameVal and tostring(nameVal) ~= "") and tostring(nameVal) or "empty"
            return { name = name, iconId = 0 }
        end
        return nil
    end
    local nameVal, iconId = "empty", 0
    local ok2, itemN = pcall(function() return it.Item and it.Item(ORNAMENT_SLOT_INDEX) end)
    if ok2 and itemN then
        if itemN.Name then
            local nameOk, nv = pcall(function() return itemN.Name() end)
            if nameOk and nv and tostring(nv) ~= "" then nameVal = tostring(nv) end
        end
        if itemN.Icon then
            local iconOk, ico = pcall(function() return itemN.Icon() end)
            if iconOk and ico then iconId = tonumber(ico) or 0 end
        end
    end
    return { name = nameVal, iconId = iconId }
end

--- Build a compact list of only non-nil values (so row count = longest column's value count, no placeholders in longest col).
local function compactCol(c)
    local t = {}
    for i = 1, 256 do if c[i] ~= nil then t[#t + 1] = c[i] end end
    return t
end

--- Row count for Item info block (same structure as render).
local function getItemInfoRowCount(item)
    local L1, L2, L3 = "%-12s %s", "%-6s %s", "%-10s %s"
    local leftCol, midCol, rightCol = {}, {}, {}
    local wStr = (item.weight and item.weight ~= 0) and (item.weight >= 10 and string.format("%.1f", item.weight / 10) or tostring(item.weight)) or nil
    if formatSize(item) then leftCol[#leftCol + 1] = string.format(L1, "Size:", formatSize(item)) end
    if wStr then leftCol[#leftCol + 1] = string.format(L1, "Weight:", wStr) end
    if item.requiredLevel and item.requiredLevel ~= 0 then leftCol[#leftCol + 1] = string.format(L1, "Req Level:", tostring(item.requiredLevel)) end
    if item.recommendedLevel and item.recommendedLevel ~= 0 then leftCol[#leftCol + 1] = string.format(L1, "Rec Level:", tostring(item.recommendedLevel)) end
    if item.type and item.type ~= "" then leftCol[#leftCol + 1] = string.format(L1, "Skill:", tostring(item.type)) end
    if item.instrumentType and item.instrumentType ~= "" then leftCol[#leftCol + 1] = string.format(L1, "Instrument:", tostring(item.instrumentType) .. ((item.instrumentMod and item.instrumentMod ~= 0) and (" " .. tostring(item.instrumentMod)) or "")) end
    if item.range and item.range ~= 0 then leftCol[#leftCol + 1] = string.format(L1, "Range:", tostring(item.range)) end
    if item.charges and item.charges ~= 0 then leftCol[#leftCol + 1] = string.format(L1, "Charges:", (item.charges == -1) and "Unlimited" or tostring(item.charges)) end
    if item.skillModValue and item.skillModValue ~= 0 then leftCol[#leftCol + 1] = string.format(L1, "Skill Mod:", (item.skillModMax and item.skillModMax ~= 0) and (tostring(item.skillModValue) .. "/" .. tostring(item.skillModMax)) or tostring(item.skillModValue)) end
    if item.baneDMG and item.baneDMG ~= 0 then leftCol[#leftCol + 1] = string.format(L1, "Bane:", tostring(item.baneDMG) .. (item.baneDMGType and item.baneDMGType ~= "" and (" " .. item.baneDMGType) or "")) end
    if item.ac and item.ac ~= 0 then midCol[#midCol + 1] = string.format(L2, "AC:", tostring(item.ac)) end
    if item.hp and item.hp ~= 0 then midCol[#midCol + 1] = string.format(L2, "HP:", tostring(item.hp)) end
    if item.mana and item.mana ~= 0 then midCol[#midCol + 1] = string.format(L2, "Mana:", tostring(item.mana)) end
    if item.endurance and item.endurance ~= 0 then midCol[#midCol + 1] = string.format(L2, "End:", tostring(item.endurance)) end
    if item.haste and item.haste ~= 0 then midCol[#midCol + 1] = string.format(L2, "Haste:", tostring(item.haste) .. "%") end
    if item.purity and item.purity ~= 0 then midCol[#midCol + 1] = string.format(L2, "Purity:", tostring(item.purity)) end
    local isWeapon = (item.damage and item.damage ~= 0) or (item.itemDelay and item.itemDelay ~= 0) or (item.type and item.type ~= "" and (item.type:lower():find("piercing") or item.type:lower():find("slashing") or item.type:lower():find("1h") or item.type:lower():find("2h") or item.type:lower():find("ranged")))
    if isWeapon then
        rightCol[#rightCol + 1] = string.format(L3, "Base Dmg:", tostring(item.damage or 0))
        rightCol[#rightCol + 1] = string.format(L3, "Delay:", tostring(item.itemDelay or 0))
        rightCol[#rightCol + 1] = string.format(L3, "Dmg Bon:", tostring(item.dmgBonus or 0) .. (item.dmgBonusType and item.dmgBonusType ~= "" and item.dmgBonusType ~= "None" and (" " .. item.dmgBonusType) or ""))
    else
        if item.damage and item.damage ~= 0 then rightCol[#rightCol + 1] = string.format(L3, "Base Dmg:", tostring(item.damage)) end
        if item.itemDelay and item.itemDelay ~= 0 then rightCol[#rightCol + 1] = string.format(L3, "Delay:", tostring(item.itemDelay)) end
        if item.dmgBonus and item.dmgBonus ~= 0 then rightCol[#rightCol + 1] = string.format(L3, "Dmg Bon:", tostring(item.dmgBonus) .. (item.dmgBonusType and item.dmgBonusType ~= "" and item.dmgBonusType ~= "None" and (" " .. item.dmgBonusType) or "")) end
    end
    if #leftCol == 0 and #midCol == 0 and #rightCol == 0 then return 0 end
    return math.max(#leftCol, #midCol, #rightCol)
end

--- Row count for All Stats block (same structure as render).
local function getStatRowCount(item)
    local attrs = {
        attrLine(item.str, item.heroicSTR, "Strength"),
        attrLine(item.sta, item.heroicSTA, "Stamina"),
        attrLine(item.int, item.heroicINT, "Intelligence"),
        attrLine(item.wis, item.heroicWIS, "Wisdom"),
        attrLine(item.agi, item.heroicAGI, "Agility"),
        attrLine(item.dex, item.heroicDEX, "Dexterity"),
        attrLine(item.cha, item.heroicCHA, "Charisma"),
    }
    local function resistLine(b, h, label)
        b, h = b or 0, h or 0
        if b == 0 and h == 0 then return nil end
        if h > 0 then return string.format("%s: %d+%d", label, b, h) end
        return string.format("%s: %d", label, b)
    end
    local resists = {
        resistLine(item.svMagic, item.heroicSvMagic, "Magic"),
        resistLine(item.svFire, item.heroicSvFire, "Fire"),
        resistLine(item.svCold, item.heroicSvCold, "Cold"),
        resistLine(item.svDisease, item.heroicSvDisease, "Disease"),
        resistLine(item.svPoison, item.heroicSvPoison, "Poison"),
        resistLine(item.svCorruption, item.heroicSvCorruption, "Corruption"),
    }
    local function cl(val, label) if (val or 0) ~= 0 then return string.format("%s: %d", label, val) end return nil end
    local combat = {
        cl(item.attack, "Attack"), cl(item.hpRegen, "HP Regen"), cl(item.manaRegen, "Mana Regen"),
        cl(item.enduranceRegen, "End Regen"), cl(item.combatEffects, "Combat Eff"), cl(item.damageShield, "Dmg Shield"),
        cl(item.damageShieldMitigation, "Dmg Shld Mit"), cl(item.accuracy, "Accuracy"), cl(item.strikeThrough, "Strike Thr"),
        cl(item.healAmount, "Heal Amount"), cl(item.spellDamage, "Spell Dmg"), cl(item.spellShield, "Spell Shield"),
        cl(item.shielding, "Shielding"), cl(item.dotShielding, "DoT Shield"), cl(item.avoidance, "Avoidance"),
        cl(item.stunResist, "Stun Resist"), cl(item.clairvoyance, "Clairvoyance"),
        cl(item.luck, "Luck"),
    }
    local hasAny = false
    for _, v in ipairs(attrs) do if v then hasAny = true break end end
    for _, v in ipairs(resists) do if v then hasAny = true break end end
    for _, v in ipairs(combat) do if v then hasAny = true break end end
    if not hasAny then return 0 end
    local a, r, c = compactCol(attrs), compactCol(resists), compactCol(combat)
    return math.max(#a, #r, #c)
end

--- Count rows in each column to match the actual tooltip layout. Returns leftRows, rightRows so height can fit the longer column.
local function countTooltipRows(item, effects, parentIt, bag, slot, source, opts, itemInfoRows, statRows, augCount)
    -- Column 1: header (icon+name share first line; name may wrap), ID, type, stack, spacing
    local nameLen = item.name and #tostring(item.name) or 0
    local nameLines = nameLen > 0 and math.max(1, math.ceil(nameLen / CHARS_PER_LINE_NAME)) or 1
    local left = nameLines
    if item.id and item.id ~= 0 then left = left + 1 end
    if getTypeLine(item) then left = left + 1 end
    if (item.stackSizeMax and item.stackSizeMax > 1) or (item.stackSize and item.stackSize > 1) then left = left + 1 end
    left = left + 1 -- spacing
    -- Class, Race, Deity, Slot (up to 4 lines)
    left = left + 4
    -- Ornament block: 0 or Spacing + "Ornament" + icon+name + Spacing = 4
    local ornament = parentIt and not opts.socketIndex and getOrnamentFromIt(parentIt)
    if ornament and ornament.name then left = left + 4 end
    -- Container
    if item.container and item.container > 0 then left = left + 1 end
    left = left + 1 -- spacing before Item info
    -- Item info section: header + spacing + rows
    if itemInfoRows > 0 then left = left + 2 + itemInfoRows end
    -- All Stats section: header + spacing + rows
    if statRows > 0 then left = left + 2 + statRows end
    -- Augment item only: "This Augmentation fits in slot types" + restrictions line
    local itemTypeLower = item.type and tostring(item.type):lower() or ""
    if itemTypeLower == "augmentation" then
        local slotIds = itemHelpers.getAugTypeSlotIds(item.augType or 0)
        local nSlot = (slotIds and #slotIds) or 0
        if nSlot > 0 then left = left + 2 + nSlot + 1 end  -- spacing + header + spacing + lines + spacing
        if item.augRestrictions and item.augRestrictions > 0 then left = left + 2 end  -- restrictions line + spacing
    end
    -- Augmentation slots (parent item): spacing + header + spacing + aug lines + spacing
    if augCount > 0 then left = left + 3 + augCount end

    -- Column 2: Item effects (header + spacing + per-effect lines), Item information, Spell Info blocks, Value, Tribute
    local right = 0
    if #effects > 0 then
        right = right + 2 -- "Item effects" + Spacing
        for _, e in ipairs(effects) do
            right = right + 1 -- label
            if e.key == "Clicky" and (e.castTime ~= nil or (e.recastTime ~= nil and e.recastTime > 0)) then
                if e.castTime ~= nil then right = right + 1 end
                if e.recastTime ~= nil and e.recastTime > 0 then right = right + 1 end
            end
            if e.desc and e.desc ~= "" then
                right = right + math.max(1, math.ceil(#e.desc / CHARS_PER_LINE_DESC)) + 1 -- TextWrapped + Spacing
            end
        end
        right = right + 1 -- trailing Spacing
    end
    -- Item information block (only when not socket tooltip)
    if not opts.socketIndex then
        right = right + 2 -- Spacing + "Item information"
        if item.id and item.id ~= 0 then right = right + 1 end
        if item.icon and item.icon ~= 0 then right = right + 1 end
        if (item.totalValue or item.value) and (item.totalValue or item.value) ~= 0 then right = right + 1 end
        if item.damage and item.damage ~= 0 and item.itemDelay and item.itemDelay ~= 0 then right = right + 1 end
        right = right + 1 -- Lore or Timer (one line)
        if bag and slot and source then right = right + 1 end -- Timer line
        right = right + 2 -- PopStyleColor + Spacing
    end
    -- Spell Info blocks: one per effect type (Clicky, Proc, Worn, Focus)
    local spellInfoOrder = { "Clicky", "Proc", "Worn", "Focus" }
    local seenKey = {}
    for _, e in ipairs(effects) do seenKey[e.key] = true end
    for _, key in ipairs(spellInfoOrder) do
        if seenKey[key] then
            right = right + 1 + 1 + 5 -- Spacing + header + (ID, Duration, Recovery, Recast, Range)
        end
    end
    -- Value
    if (item.totalValue or item.value) and (item.totalValue or item.value) ~= 0 then right = right + 2 end
    -- Tribute
    if item.tribute and item.tribute ~= 0 then right = right + 2 end

    return left, right
end

--- Pre-warm item, build effects, and estimate tooltip size so each hover gets correct width/height (no reuse of previous item's size).
--- Returns: effects (table), width (number), height (number). Pass opts.effects = effects into renderStatsTooltip to avoid building effects twice.
function ItemTooltip.prepareTooltipContent(item, ctx, opts)
    if not item then return {}, TOOLTIP_MIN_WIDTH, 400 end
    opts = opts or {}
    local source = opts.source or (item and item.source) or "inv"
    local bag = item.bag ~= nil and item.bag or opts.bag
    local slot = item.slot ~= nil and item.slot or opts.slot
    -- Pre-warm lazy fields
    if bag and slot and source then
        local _ = item.augSlots
        _ = item.wornSlots
        _ = item.ac
        if (item.type and tostring(item.type):lower()) == "augmentation" then
            _ = item.augType
            _ = item.augRestrictions
        end
    end
    local it = (bag and slot and source) and itemHelpers.getItemTLO(bag, slot, source) or nil
    local parentIt = it
    if it and opts.socketIndex and it.Item then
        local ok, sockIt = pcall(function() return it.Item(opts.socketIndex) end)
        if ok and sockIt then it = sockIt end
    end
    local effectKeys = {"Clicky", "Worn", "Proc", "Focus", "Spell"}
    local effects = {}
    local function addEffectsFromItem(ef, itm, keys)
        if not ctx or not ctx.getItemSpellId or not ctx.getSpellName then return end
        for _, key in ipairs(keys) do
            local id = ctx.getItemSpellId(itm, key)
            if id and id > 0 then
                local spellName = ctx.getSpellName(id)
                if spellName and spellName ~= "" then
                    local desc = (ctx.getSpellDescription and ctx.getSpellDescription(id)) or ""
                    local castTime = (key == "Clicky" and ctx.getSpellCastTime and ctx.getSpellCastTime(id)) or nil
                    local recastTime = (key == "Clicky" and ctx.getSpellRecastTime and ctx.getSpellRecastTime(id)) or nil
                    ef[#ef + 1] = { key = key, spellId = id, spellName = spellName, desc = desc, castTime = castTime, recastTime = recastTime }
                end
            end
        end
    end
    if ctx and ctx.getItemSpellId and ctx.getSpellName then
        addEffectsFromItem(effects, item, effectKeys)
        if parentIt and bag and slot and source and not opts.socketIndex and (item.augSlots or 0) > 0 then
            for socketIndex = 1, math.min(5, item.augSlots or 0) do
                local socketItem = getSocketItemStats(parentIt, bag, slot, source, socketIndex)
                if socketItem then addEffectsFromItem(effects, socketItem, effectKeys) end
            end
        end
    end
    local itemInfoRows = getItemInfoRowCount(item)
    local statRows = getStatRowCount(item)
    local augCount = (parentIt and itemHelpers.getStandardAugSlotsCountFromTLO(parentIt)) or ((item.augSlots or 0) > 0 and (itemHelpers.itemHasOrnamentSlot(it or parentIt) and math.min(AUGMENT_SLOT_COUNT, (item.augSlots or 0) - 1) or math.min(AUGMENT_SLOT_COUNT, item.augSlots or 0)) or 0)
    if augCount < 0 then augCount = 0 end
    local leftRows, rightRows = countTooltipRows(item, effects, parentIt, bag, slot, source, opts, itemInfoRows, statRows, augCount)
    -- Use the longer column and add buffer so all stats and spell info are visible (no cut-off)
    local lineCount = math.max(leftRows, rightRows) + TOOLTIP_EXTRA_ROWS
    local height = math.max(300, lineCount * TOOLTIP_LINE_HEIGHT + TOOLTIP_PADDING)
    -- Use narrower width for items with less content (no effects, no augs, few rows)
    local totalRows = leftRows + rightRows
    local useCompact = (#effects == 0 and augCount == 0 and totalRows < 26)
    local width = useCompact and TOOLTIP_COMPACT_WIDTH or TOOLTIP_MIN_WIDTH
    opts.tooltipColWidth = useCompact and TOOLTIP_COMPACT_COL or TOOLTIP_COL_WIDTH
    return effects, width, height
end

--- Returns true if the current player can use the item (class, race, deity, level).
--- Used internally for name color; use getCanUseInfo for canUse + reason.
local function canPlayerUseItem(item, source)
    local info = ItemTooltip.getCanUseInfo(item, source)
    return info.canUse
end

--- Returns { canUse = boolean, reason = string|nil } for the current player and item.
--- reason is only set when canUse is false (e.g. "Requires level 85", "Requires Bard").
function ItemTooltip.getCanUseInfo(item, source)
    local result = { canUse = true, reason = nil }
    if not item then return result end
    source = source or (item.source) or "inv"
    local Me = mq.TLO and mq.TLO.Me
    if not Me or not Me.Level then return result end
    local myLevel = tonumber(Me.Level()) or 0
    local reqLevel = (item.requiredLevel and item.requiredLevel > 0) and item.requiredLevel or nil
    if reqLevel and myLevel < reqLevel then
        result.canUse = false
        result.reason = "Requires level " .. tostring(reqLevel)
        return result
    end
    local myDeity = Me.Deity and Me.Deity() and tostring(Me.Deity()):lower() or ""
    if item.deity and item.deity ~= "" then
        local allowed = false
        for part in (tostring(item.deity):lower()):gmatch("%S+") do
            if part == myDeity then allowed = true break end
        end
        if not allowed then
            result.canUse = false
            result.reason = "Requires deity: " .. tostring(item.deity)
            return result
        end
    end
    local myClass = Me.Class and tostring(Me.Class() or ""):lower() or ""
    local myRace = Me.Race and tostring(Me.Race() or ""):lower() or ""
    if item.class and item.class ~= "" and item.class:lower() ~= "all" then
        local ok = false
        for part in (tostring(item.class):lower()):gmatch("%S+") do
            if part == myClass then ok = true break end
        end
        if not ok then
            result.canUse = false
            result.reason = "Requires class: " .. tostring(item.class)
            return result
        end
    end
    if item.race and item.race ~= "" and item.race:lower() ~= "all" then
        local ok = false
        for part in (tostring(item.race):lower()):gmatch("%S+") do
            if part == myRace then ok = true break end
        end
        if not ok then
            result.canUse = false
            result.reason = "Requires race: " .. tostring(item.race)
            return result
        end
    end
    return result
end

--- Render item display content (two-column layout: header/stats/augs in col1, effects/info/spell/value in col2).
--- Used by both the on-hover tooltip and the CoOpt Item Display window. Does not call BeginTooltip/EndTooltip.
function ItemTooltip.renderItemDisplayContent(item, ctx, opts)
    if not item then return end
    opts = opts or {}
    local source = opts.source or (item and item.source) or "inv"
    local bag = item.bag ~= nil and item.bag or opts.bag
    local slot = item.slot ~= nil and item.slot or opts.slot
    -- Pre-warm lazy item fields when not using pre-built effects (so layout isn't affected by mid-draw TLO/cache)
    if not opts.effects and item and (bag ~= nil and slot ~= nil and source) then
        local _ = item.augSlots
        _ = item.wornSlots
        _ = item.ac
    end
    -- Every socket row: [24x24 icon area] + SameLine + text (replicate default UI layout).
    -- Filled: draw item icon; empty: draw reserved 24x24 so rows align. See AUGMENT_SOCKET_UI_DESIGN.md.
    local function drawSocketIcon(iconId)
        if iconId and iconId > 0 and ctx and ctx.drawItemIcon then
            pcall(function() ctx.drawItemIcon(iconId) end)
        elseif ctx and ctx.drawEmptySlotIcon then
            pcall(function() ctx.drawEmptySlotIcon() end)
        else
            ImGui.Dummy(ImVec2(24, 24))
        end
    end

    -- Resolve item TLO once per hover (quick); use for class/race/slot, ornament, and augment lines.
    local it = (bag ~= nil and slot ~= nil and source) and itemHelpers.getItemTLO(bag, slot, source) or nil
    local parentIt = it
    if it and opts.socketIndex and it.Item then
        local ok, sockIt = pcall(function() return it.Item(opts.socketIndex) end)
        if ok and sockIt then it = sockIt end
    end
    local itValid = it and it.ID and it.ID() ~= 0
    -- Link color for augment/ornament names (hover shows socketed item tooltip).
    local linkColor = ImVec4(0.4, 0.7, 1.0, 1.0)
    local effects = {}

    local function renderSpellInfoBlock(spellId, headerColor, headerText)
        if not spellId or spellId <= 0 or not ctx then return end
        ImGui.Spacing()
        ImGui.TextColored(headerColor, headerText)
        ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.65, 0.65, 0.7, 1.0))
        ImGui.Text("ID: " .. tostring(spellId))
        if ctx.getSpellDuration then
            local dur = ctx.getSpellDuration(spellId)
            if dur ~= nil then ImGui.Text("Duration: " .. tostring(dur)) end
        end
        if ctx.getSpellRecoveryTime then
            local rec = ctx.getSpellRecoveryTime(spellId)
            if rec ~= nil then ImGui.Text("RecoveryTime: " .. string.format("%.2f", rec)) end
        end
        if ctx.getSpellRecastTime then
            local rt = ctx.getSpellRecastTime(spellId)
            if rt ~= nil then ImGui.Text("RecastTime: " .. string.format("%.2f", rt)) end
        end
        if ctx.getSpellRange then
            local rng = ctx.getSpellRange(spellId)
            if rng ~= nil and rng ~= 0 then ImGui.Text("Range: " .. tostring(rng)) end
        end
        ImGui.PopStyleColor()
    end

    local effectKeys = {"Clicky", "Worn", "Proc", "Focus", "Spell"}
    local function addEffectsFromItem(ef, it, keys)
        if not ctx or not ctx.getItemSpellId or not ctx.getSpellName then return end
        for _, key in ipairs(keys) do
            local id = ctx.getItemSpellId(it, key)
            if id and id > 0 then
                local spellName = ctx.getSpellName(id)
                if spellName and spellName ~= "" then
                    local desc = (ctx.getSpellDescription and ctx.getSpellDescription(id)) or ""
                    local castTime = (key == "Clicky" and ctx.getSpellCastTime and ctx.getSpellCastTime(id)) or nil
                    local recastTime = (key == "Clicky" and ctx.getSpellRecastTime and ctx.getSpellRecastTime(id)) or nil
                    ef[#ef + 1] = { key = key, spellId = id, spellName = spellName, desc = desc, castTime = castTime, recastTime = recastTime }
                end
            end
        end
    end
    if opts.effects then
        effects = opts.effects
    elseif ctx and ctx.getItemSpellId and ctx.getSpellName then
        effects = {}
        addEffectsFromItem(effects, item, effectKeys)
        if parentIt and bag and slot and source and not opts.socketIndex and (item.augSlots or 0) > 0 then
            for socketIndex = 1, math.min(5, item.augSlots or 0) do
                local socketItem = getSocketItemStats(parentIt, bag, slot, source, socketIndex)
                if socketItem then addEffectsFromItem(effects, socketItem, effectKeys) end
            end
        end
    end

    local colW = (opts.tooltipColWidth and opts.tooltipColWidth > 0) and opts.tooltipColWidth or TOOLTIP_COL_WIDTH
    ImGui.Columns(2, "##TooltipCols", false)
    ImGui.SetColumnWidth(0, colW)
    ImGui.SetColumnWidth(1, colW)
    if ImGui.BeginChild then
        ImGui.BeginChild("##TooltipCol1", ImVec2(colW, 0), false)
    end

    -- ---- Column 1: Header (name, ID, type) then Class, Race, Slot, Deity, Ornament, Container, Item info, All Stats, Augmentation slots ----
    local nameColor = ImVec4(0.45, 0.85, 0.45, 1.0)
    if not canPlayerUseItem(item, source) then
        nameColor = ImVec4(0.95, 0.35, 0.35, 1.0)
    end
    local headerIconSize = 32
    if ctx and ctx.drawItemIcon and item.icon and item.icon > 0 then
        pcall(function() ctx.drawItemIcon(item.icon, headerIconSize) end)
        ImGui.SameLine()
    end
    ImGui.PushStyleColor(ImGuiCol.Text, nameColor)
    ImGui.TextWrapped(item.name or "—")
    ImGui.PopStyleColor()
    if item.id and item.id ~= 0 then
        ImGui.TextColored(ImVec4(0.55, 0.55, 0.6, 1.0), "ID: " .. tostring(item.id))
    end
    local typeLine = getTypeLine(item)
    if typeLine then ImGui.Text(typeLine) end
    if (item.stackSizeMax and item.stackSizeMax > 1) or (item.stackSize and item.stackSize > 1) then
        local stackStr = "Stack: " .. tostring(item.stackSize or 1)
        if item.stackSizeMax and item.stackSizeMax > 0 then stackStr = stackStr .. " / " .. tostring(item.stackSizeMax) end
        ImGui.Text(stackStr)
    end
    ImGui.Spacing()

    -- Class, Race, Slot, Deity, Ornament, Container, Item info, All Stats, Augmentation slots
    local cls, race, slotStr = "—", "—", ""
    if itValid then
        local ok, c, r, s = pcall(itemHelpers.getClassRaceSlotFromTLO, it)
        if ok then
            if c and c ~= "" then cls = c end
            if r and r ~= "" then race = r end
            if s and s ~= "" then slotStr = s end
        end
    else
        local ok, c, r, s = pcall(itemHelpers.getClassRaceSlotFromTLO, itemHelpers.getItemTLO(bag, slot, source))
        if ok then
            if c and c ~= "" then cls = c end
            if r and r ~= "" then race = r end
            if s and s ~= "" then slotStr = s end
        end
    end
    if cls == "—" and (item.class and item.class ~= "") then cls = item.class end
    if race == "—" and (item.race and item.race ~= "") then race = item.race end
    if (slotStr == "" or slotStr == "—") and (item.wornSlots and item.wornSlots ~= "") then slotStr = item.wornSlots end
    if cls and cls ~= "" and cls ~= "—" then ImGui.Text("Class: " .. tostring(cls)) end
    if race and race ~= "" and race ~= "—" then ImGui.Text("Race: " .. tostring(race)) end
    if item.deity and item.deity ~= "" then ImGui.Text("Deity: " .. tostring(item.deity)) end
    slotStr = slotStringToDisplay(slotStr)
    if slotStr and slotStr ~= "" and slotStr ~= "—" then ImGui.Text(slotStr) end
    -- Ornament first (match Item Display: IDW_Appearance_Socket_*). Same row layout: [24x24] + text. Name is a link when filled.
    if itValid then
        local ornament = getOrnamentFromIt(it)
        if ornament and ornament.name then
            ImGui.Spacing()
            ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "Ornament")
            drawSocketIcon(ornament.iconId)
            ImGui.SameLine()
            if ornament.name ~= "empty" and parentIt and not opts.socketIndex then
                ImGui.TextColored(linkColor, ornament.name)
                if ImGui.IsItemHovered() then
                    local socketItem = getSocketItemStats(parentIt, bag, slot, source, ORNAMENT_SLOT_INDEX)
                    if socketItem then
                        local socketOpts = { source = source, bag = bag, slot = slot, socketIndex = ORNAMENT_SLOT_INDEX }
                        local nestEffects, nestW, nestH = ItemTooltip.prepareTooltipContent(socketItem, ctx, socketOpts)
                        socketOpts.effects = nestEffects
                        ItemTooltip.beginItemTooltip(nestW, nestH)
                        ItemTooltip.renderStatsTooltip(socketItem, ctx, socketOpts)
                        ImGui.EndTooltip()
                    end
                end
            else
                ImGui.Text(ornament.name)
            end
            ImGui.Spacing()
        end
    end
    if item.container and item.container > 0 then
        local capStr = item.sizeCapacity and item.sizeCapacity > 0 and (SIZE_NAMES[item.sizeCapacity] or tostring(item.sizeCapacity)) or nil
        ImGui.Text("Container: " .. tostring(item.container) .. " slot" .. (item.container == 1 and "" or "s") .. (capStr and (" (" .. capStr .. ")") or ""))
    end
    ImGui.Spacing()

    -- ---- Item info: in-game layout = Left (Size/Weight/Req/Skill) | Middle (AC/HP/Mana/End/Haste) | Right (Base Dmg, Delay, Dmg Bon) ----
    local colW1, colW2, colW3 = 145, 100, 110
    local L1, L2, L3 = "%-12s %s", "%-6s %s", "%-10s %s"
    local leftCol, midCol, rightCol = {}, {}, {}
    local wStr = (item.weight and item.weight ~= 0) and (item.weight >= 10 and string.format("%.1f", item.weight / 10) or tostring(item.weight)) or nil
    if formatSize(item) then leftCol[#leftCol + 1] = string.format(L1, "Size:", formatSize(item)) end
    if wStr then leftCol[#leftCol + 1] = string.format(L1, "Weight:", wStr) end
    if item.requiredLevel and item.requiredLevel ~= 0 then leftCol[#leftCol + 1] = string.format(L1, "Req Level:", tostring(item.requiredLevel)) end
    if item.recommendedLevel and item.recommendedLevel ~= 0 then leftCol[#leftCol + 1] = string.format(L1, "Rec Level:", tostring(item.recommendedLevel)) end
    if item.type and item.type ~= "" then leftCol[#leftCol + 1] = string.format(L1, "Skill:", tostring(item.type)) end
    if item.instrumentType and item.instrumentType ~= "" then leftCol[#leftCol + 1] = string.format(L1, "Instrument:", tostring(item.instrumentType) .. ((item.instrumentMod and item.instrumentMod ~= 0) and (" " .. tostring(item.instrumentMod)) or "")) end
    if item.range and item.range ~= 0 then leftCol[#leftCol + 1] = string.format(L1, "Range:", tostring(item.range)) end
    if item.charges and item.charges ~= 0 then leftCol[#leftCol + 1] = string.format(L1, "Charges:", (item.charges == -1) and "Unlimited" or tostring(item.charges)) end
    if item.skillModValue and item.skillModValue ~= 0 then leftCol[#leftCol + 1] = string.format(L1, "Skill Mod:", (item.skillModMax and item.skillModMax ~= 0) and (tostring(item.skillModValue) .. "/" .. tostring(item.skillModMax)) or tostring(item.skillModValue)) end
    if item.baneDMG and item.baneDMG ~= 0 then leftCol[#leftCol + 1] = string.format(L1, "Bane:", tostring(item.baneDMG) .. (item.baneDMGType and item.baneDMGType ~= "" and (" " .. item.baneDMGType) or "")) end
    if item.ac and item.ac ~= 0 then midCol[#midCol + 1] = string.format(L2, "AC:", tostring(item.ac)) end
    if item.hp and item.hp ~= 0 then midCol[#midCol + 1] = string.format(L2, "HP:", tostring(item.hp)) end
    if item.mana and item.mana ~= 0 then midCol[#midCol + 1] = string.format(L2, "Mana:", tostring(item.mana)) end
    if item.endurance and item.endurance ~= 0 then midCol[#midCol + 1] = string.format(L2, "End:", tostring(item.endurance)) end
    if item.haste and item.haste ~= 0 then midCol[#midCol + 1] = string.format(L2, "Haste:", tostring(item.haste) .. "%") end
    if item.purity and item.purity ~= 0 then midCol[#midCol + 1] = string.format(L2, "Purity:", tostring(item.purity)) end
    -- Weapon block: always show Base Dmg, Delay, Dmg Bon when item has weapon stats (match in-game Item Display)
    local isWeapon = (item.damage and item.damage ~= 0) or (item.itemDelay and item.itemDelay ~= 0) or (item.type and item.type ~= "" and (item.type:lower():find("piercing") or item.type:lower():find("slashing") or item.type:lower():find("1h") or item.type:lower():find("2h") or item.type:lower():find("ranged")))
    if isWeapon then
        rightCol[#rightCol + 1] = string.format(L3, "Base Dmg:", tostring(item.damage or 0))
        rightCol[#rightCol + 1] = string.format(L3, "Delay:", tostring(item.itemDelay or 0))
        rightCol[#rightCol + 1] = string.format(L3, "Dmg Bon:", tostring(item.dmgBonus or 0) .. (item.dmgBonusType and item.dmgBonusType ~= "" and item.dmgBonusType ~= "None" and (" " .. item.dmgBonusType) or ""))
    else
        if item.damage and item.damage ~= 0 then rightCol[#rightCol + 1] = string.format(L3, "Base Dmg:", tostring(item.damage)) end
        if item.itemDelay and item.itemDelay ~= 0 then rightCol[#rightCol + 1] = string.format(L3, "Delay:", tostring(item.itemDelay)) end
        if item.dmgBonus and item.dmgBonus ~= 0 then rightCol[#rightCol + 1] = string.format(L3, "Dmg Bon:", tostring(item.dmgBonus) .. (item.dmgBonusType and item.dmgBonusType ~= "" and item.dmgBonusType ~= "None" and (" " .. item.dmgBonusType) or "")) end
    end
    local hasItemInfo = #leftCol > 0 or #midCol > 0 or #rightCol > 0
    if hasItemInfo then
        -- Flat list in item-display order (row-major: each row = left, mid, right; use placeholder for empty)
        local placeholder = " "
        local maxRows = math.max(#leftCol, #midCol, #rightCol)
        local itemInfoFlat = {}
        for row = 1, maxRows do
            itemInfoFlat[#itemInfoFlat + 1] = leftCol[row] or placeholder
            itemInfoFlat[#itemInfoFlat + 1] = midCol[row] or placeholder
            itemInfoFlat[#itemInfoFlat + 1] = rightCol[row] or placeholder
        end
        ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "Item info")
        ImGui.Spacing()
        ImGui.Columns(3, "##TooltipItemInfo", false)
        ImGui.SetColumnWidth(0, colW1)
        ImGui.SetColumnWidth(1, colW2)
        ImGui.SetColumnWidth(2, colW3)
        for i = 1, #itemInfoFlat do
            ImGui.Text(itemInfoFlat[i])
            ImGui.NextColumn()
        end
        ImGui.Columns(1)
        ImGui.Spacing()
        -- Restore 2-column layout so remaining column 1 content stays left
        ImGui.Columns(2, "##TooltipCols", false)
        ImGui.SetColumnWidth(0, colW)
        ImGui.SetColumnWidth(1, colW)
    end

    -- ---- All Stats: Primary (base+heroic), Resistances, Combat/utility ----
    local itemTypeLower = (item.type and tostring(item.type):lower()) or ""
    -- For augments: re-fetch Shielding, DamShield, HPRegen from TLO and rawset on this table so they always show.
    -- (Some augments e.g. Barbed Dragon Bones, Jade Prism had stats in TLO but not in the table we render from.)
    -- If more augment stats are missing in future, add that TLO name here and use rawget/fallback in combat array.
    if itemTypeLower == "augmentation" and bag and slot and source then
        local it = itemHelpers.getItemTLO(bag, slot, source)
        if it and it.ID and it.ID() and it.ID() ~= 0 then
            local try = function(tlo, name)
                local acc = tlo[name] or tlo[name:lower()]
                if acc and type(acc) == "function" then local ok, v = pcall(acc); if ok and v then return v end end
                return nil
            end
            local v1 = try(it, "Shielding")
            local v2 = try(it, "DamShield")
            local v3 = try(it, "HPRegen")
            if v1 ~= nil then rawset(item, "shielding", tonumber(v1) or v1) end
            if v2 ~= nil then rawset(item, "damageShield", tonumber(v2) or v2) end
            if v3 ~= nil then rawset(item, "hpRegen", tonumber(v3) or v3) end
        end
    end
    local attrs = {
        attrLine(item.str, item.heroicSTR, "Strength"),
        attrLine(item.sta, item.heroicSTA, "Stamina"),
        attrLine(item.int, item.heroicINT, "Intelligence"),
        attrLine(item.wis, item.heroicWIS, "Wisdom"),
        attrLine(item.agi, item.heroicAGI, "Agility"),
        attrLine(item.dex, item.heroicDEX, "Dexterity"),
        attrLine(item.cha, item.heroicCHA, "Charisma"),
    }
    local function resistLine(b, h, label)
        b, h = b or 0, h or 0
        if b == 0 and h == 0 then return nil end
        if h > 0 then return string.format("%s: %d+%d", label, b, h) end
        return string.format("%s: %d", label, b)
    end
    local resists = {
        resistLine(item.svMagic, item.heroicSvMagic, "Magic"),
        resistLine(item.svFire, item.heroicSvFire, "Fire"),
        resistLine(item.svCold, item.heroicSvCold, "Cold"),
        resistLine(item.svDisease, item.heroicSvDisease, "Disease"),
        resistLine(item.svPoison, item.heroicSvPoison, "Poison"),
        resistLine(item.svCorruption, item.heroicSvCorruption, "Corruption"),
    }
    local function cl(val, label) if (tonumber(val) or 0) ~= 0 then return string.format("%s: %d", label, tonumber(val) or val or 0) end return nil end
    -- Prefer raw table values for augment stats (batch stores here; ensure we read same table)
    local sh = rawget(item, "shielding")
    local ds = rawget(item, "damageShield")
    local hr = rawget(item, "hpRegen")
    if sh == nil then sh = item.shielding end
    if ds == nil then ds = item.damageShield end
    if hr == nil then hr = item.hpRegen end
    -- Order combat stats to match in-game Item Display right column, then remaining
    local combat = {
        cl(item.attack, "Attack"),
        cl(hr, "HP Regen"),
        cl(item.manaRegen, "Mana Regen"),
        cl(item.enduranceRegen, "End Regen"),
        cl(item.combatEffects, "Combat Eff"),
        cl(ds, "Dmg Shield"),
        cl(item.damageShieldMitigation, "Dmg Shld Mit"),
        cl(item.accuracy, "Accuracy"),
        cl(item.strikeThrough, "Strike Thr"),
        cl(item.healAmount, "Heal Amount"),
        cl(item.spellDamage, "Spell Dmg"),
        cl(item.spellShield, "Spell Shield"),
        cl(sh, "Shielding"),
        cl(item.dotShielding, "DoT Shield"),
        cl(item.avoidance, "Avoidance"),
        cl(item.stunResist, "Stun Resist"),
        cl(item.clairvoyance, "Clairvoyance"),
        cl(item.luck, "Luck"),
    }
    local hasAnyStat = false
    for _, v in ipairs(attrs) do if v then hasAnyStat = true break end end
    for _, v in ipairs(resists) do if v then hasAnyStat = true break end end
    for _, v in ipairs(combat) do if v then hasAnyStat = true break end end
    -- Augments with only combat stats (e.g. Shielding, Dmg Shield, HP Regen): ensure we show them even if hasAnyStat missed
    local augmentSparseStats = itemTypeLower == "augmentation" and ((tonumber(sh) or 0) ~= 0 or (tonumber(ds) or 0) ~= 0 or (tonumber(hr) or 0) ~= 0)
    if augmentSparseStats and not hasAnyStat then hasAnyStat = true end
    if hasAnyStat then
        local placeholder = " "
        local a, r, c = compactCol(attrs), compactCol(resists), compactCol(combat)
        -- Only use single-column when literally only combat has content (so we don't hide attrs/resists on other items)
        local onlyCombat = (#a == 0 and #r == 0 and #c > 0)
        ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "All Stats")
        ImGui.Spacing()
        if onlyCombat then
            for _, line in ipairs(c) do ImGui.Text(line) end
        else
            local maxRows = math.max(#a, #r, #c)
            local statsFlat = {}
            for row = 1, maxRows do
                statsFlat[#statsFlat + 1] = a[row] or placeholder
                statsFlat[#statsFlat + 1] = r[row] or placeholder
                statsFlat[#statsFlat + 1] = c[row] or placeholder
            end
            ImGui.Columns(3, "##StatsCols", false)
            ImGui.SetColumnWidth(0, colW1)
            ImGui.SetColumnWidth(1, colW2)
            ImGui.SetColumnWidth(2, colW3)
            for i = 1, #statsFlat do
                if statsFlat[i] ~= placeholder then ImGui.Text(statsFlat[i]) end
                ImGui.NextColumn()
            end
            ImGui.Columns(1)
        end
        ImGui.Spacing()
        -- Restore 2-column layout so Augmentation slots and then column 2 stay correct
        ImGui.Columns(2, "##TooltipCols", false)
        ImGui.SetColumnWidth(0, colW)
        ImGui.SetColumnWidth(1, colW)
    end

    -- ---- Augment item only: "This Augmentation fits in slot types" and Restrictions ----
    itemTypeLower = (item.type and tostring(item.type):lower()) or ""
    if itemTypeLower == "augmentation" then
        local at = item.augType or 0
        if at and at > 0 then
            local slotIds = itemHelpers.getAugTypeSlotIds(at)
            if slotIds and #slotIds > 0 then
                ImGui.Spacing()
                ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "This Augmentation fits in slot types")
                ImGui.Spacing()
                for _, sid in ipairs(slotIds) do
                    local name = AUG_TYPE_NAMES[sid] or ("Type " .. tostring(sid))
                    ImGui.Text(string.format("%d (%s)", sid, name))
                end
                ImGui.Spacing()
            end
        end
        -- AugRestrictions: single ID 1-15 (live EQ). If you see "Restriction N" for N>15 or N not in 1-15,
        -- or the default Item Display shows multiple restriction lines for one augment, add a bitmask decoder:
        -- loop bits 1..15, collect AUG_RESTRICTION_NAMES[i] for each set bit, then join with ", ".
        local ar = item.augRestrictions
        if ar and ar > 0 then
            local restrText = AUG_RESTRICTION_NAMES[ar] or ("Restriction " .. tostring(ar))
            ImGui.TextColored(ImVec4(0.85, 0.7, 0.4, 1.0), "Restrictions: " .. restrText)
            ImGui.Spacing()
        end
    end

    -- ---- Augmentation slots (own section in column 1: between All Stats and Item effects) ----
    local augLines = itValid and getAugmentSlotLinesFromIt(it, item.augSlots) or ((bag ~= nil and slot ~= nil and source) and getAugmentSlotLines(bag, slot, source, item.augSlots) or nil)
    if augLines and #augLines > 0 then
        ImGui.Spacing()
        ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "Augmentation slots (standard)")
        ImGui.Spacing()
        local isItemDisplayWin = opts.isItemDisplayWindow and ctx and ctx.uiState
        for _, row in ipairs(augLines) do
            if type(row) == "table" and row.text then
                local prefix = row.prefix or ""
                local augName = (type(row.augName) == "string") and row.augName or ""
                local isEmpty = (augName == "empty" or augName == "")
                ImGui.PushID("AugSlot" .. tostring(row.slotIndex or 0) .. "_" .. tostring(bag or "") .. "_" .. tostring(slot or ""))
                drawSocketIcon(row.iconId)
                -- Icon hover and click (Item Display only): hover = tooltip; left-click = open Augment Utility to this socket (add or replace); filled right-click = remove
                if isItemDisplayWin and row.slotIndex and bag and slot and source and ctx.uiState then
                    if ImGui.IsItemHovered() then
                        if not isEmpty then
                            local socketItem = getSocketItemStats(parentIt, bag, slot, source, row.slotIndex)
                            if socketItem then
                                local socketOpts = { source = source, bag = bag, slot = slot, socketIndex = row.slotIndex }
                                local nestEffects, nestW, nestH = ItemTooltip.prepareTooltipContent(socketItem, ctx, socketOpts)
                                socketOpts.effects = nestEffects
                                ItemTooltip.beginItemTooltip(nestW, nestH)
                                ItemTooltip.renderStatsTooltip(socketItem, ctx, socketOpts)
                                ImGui.Spacing()
                                ImGui.TextColored(ImVec4(0.7, 0.6, 0.5, 1.0), "Left-click: open Augment Utility to this socket (replace augment)")
                                ImGui.TextColored(ImVec4(0.7, 0.6, 0.5, 1.0), "Right-click: remove augment")
                                ImGui.EndTooltip()
                            end
                        else
                            ImGui.BeginTooltip()
                            ImGui.Text((prefix ~= "" and prefix or ("Slot " .. tostring(row.slotIndex))) .. "Empty.")
                            ImGui.Text("Left-click to open Augment Utility and add an augment.")
                            ImGui.EndTooltip()
                        end
                    end
                    if ImGui.IsItemClicked(ImGuiMouseButton.Left) then
                        ctx.uiState.augmentUtilitySlotIndex = row.slotIndex
                        ctx.uiState.augmentUtilityWindowOpen = true
                        ctx.uiState.augmentUtilityWindowShouldDraw = true
                    end
                    if not isEmpty and ctx.removeAugment and ImGui.IsItemClicked(ImGuiMouseButton.Right) then
                        ctx.removeAugment(bag, slot, source, row.slotIndex)
                    end
                end
                ImGui.SameLine()
                if prefix ~= "" then ImGui.Text(prefix); ImGui.SameLine() end
                if augName ~= "empty" and parentIt and not opts.socketIndex and row.slotIndex then
                    ImGui.TextColored(linkColor, augName)
                    if ImGui.IsItemHovered() then
                        local socketItem = getSocketItemStats(parentIt, bag, slot, source, row.slotIndex)
                        if socketItem then
                            local socketOpts = { source = source, bag = bag, slot = slot, socketIndex = row.slotIndex }
                            local nestEffects, nestW, nestH = ItemTooltip.prepareTooltipContent(socketItem, ctx, socketOpts)
                            socketOpts.effects = nestEffects
                            ItemTooltip.beginItemTooltip(nestW, nestH)
                            ItemTooltip.renderStatsTooltip(socketItem, ctx, socketOpts)
                            ImGui.EndTooltip()
                        end
                    end
                else
                    ImGui.Text(augName ~= "" and augName or row.text)
                end
                ImGui.PopID()
            else
                ImGui.Text((type(row) == "table" and row.text) or tostring(row))
            end
        end
        ImGui.Spacing()
    elseif item.augSlots and item.augSlots > 0 then
        ImGui.Spacing()
        ImGui.Text("Augment slots: " .. tostring(item.augSlots))
        ImGui.Spacing()
    end

    if ImGui.EndChild then ImGui.EndChild() end
    ImGui.NextColumn()
    if ImGui.BeginChild then
        ImGui.BeginChild("##TooltipCol2", ImVec2(colW, 0), false)
    end

    -- ---- Column 2: Item effects, Item information, Spell Info blocks, Value & Tribute ----
    local effectLabels = { Clicky = "Clicky", Worn = "Worn", Proc = "Proc", Focus = "Focus", Spell = "Spell" }
    local focusLabel = "Focus"
    local function formatRecastDelay(sec)
        if sec == nil or sec < 0 then return nil end
        local s = math.floor(sec + 0.5)
        if s < 60 then return s == 1 and "1 second" or (s .. " seconds") end
        local m = math.floor(s / 60)
        local r = s % 60
        if r == 0 then return m == 1 and "1 minute" or (m .. " minutes") end
        local ms = m == 1 and "1 minute" or (m .. " minutes")
        local rs = r == 1 and "1 second" or (r .. " seconds")
        return ms .. " and " .. rs
    end
    if #effects > 0 then
        ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "Item effects")
        ImGui.Spacing()
        for _, e in ipairs(effects) do
                local label
                if e.key == focusLabel then
                    label = "Focus Effect: " .. e.spellName
                else
                    label = "Effect: " .. e.spellName .. " (" .. effectLabels[e.key] .. ")"
                end
                ImGui.Text(label)
                if e.key == "Clicky" and (e.castTime ~= nil or (e.recastTime ~= nil and e.recastTime > 0)) then
                    ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.65, 0.65, 0.7, 1.0))
                    if e.castTime ~= nil then
                        local ct = e.castTime
                        local ctStr = (ct == math.floor(ct)) and tostring(math.floor(ct)) or string.format("%.1f", ct)
                        ImGui.Text("Casting Time: " .. ctStr)
                    end
                    if e.recastTime ~= nil and e.recastTime > 0 then
                        ImGui.Text("Recast Delay: " .. formatRecastDelay(e.recastTime))
                    end
                    ImGui.PopStyleColor()
                end
                if e.desc and e.desc ~= "" then
                    ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.65, 0.65, 0.7, 1.0))
                    ImGui.TextWrapped(e.desc)
                    ImGui.PopStyleColor()
                    ImGui.Spacing()
                end
        end
        ImGui.Spacing()
    end

    -- ---- Item information (blue block: section 2; Item ID, Icon ID, Value, Ratio, Lore, Timer) ----
    local infoBlue = ImVec4(0.45, 0.7, 1.0, 1.0)
    local infoGreen = ImVec4(0.4, 0.9, 0.4, 1.0)
    if not opts.socketIndex then
        ImGui.Spacing()
        ImGui.TextColored(infoBlue, "Item information")
        ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.6, 0.75, 0.95, 1.0))
        if item.id and item.id ~= 0 then ImGui.Text("Item ID: " .. tostring(item.id)) end
        if item.icon and item.icon ~= 0 then ImGui.Text("Icon ID: " .. tostring(item.icon)) end
        local val = item.totalValue or item.value
        if val and val ~= 0 then
            local valStr = (ItemUtils and ItemUtils.formatValue) and ItemUtils.formatValue(val) or tostring(val)
            ImGui.Text("Value: " .. valStr)
        end
        if item.damage and item.damage ~= 0 and item.itemDelay and item.itemDelay ~= 0 then
            local ratio = item.damage / item.itemDelay
            ImGui.Text("Ratio: " .. string.format("%.3f", ratio))
        end
        if itValid and ctx and ctx.getItemLoreText then
            local loreStr = ctx.getItemLoreText(it)
            if loreStr and loreStr ~= "" then ImGui.TextWrapped("Item Lore: " .. loreStr) end
        end
        if bag and slot and source and ctx and ctx.getTimerReady then
            local ready = ctx.getTimerReady(bag, slot, source)
            if ready == nil or ready == 0 then
                ImGui.PopStyleColor()
                ImGui.TextColored(infoGreen, "Item Timer: Ready")
                ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.6, 0.75, 0.95, 1.0))
            else
                ImGui.Text("Item Timer: " .. tostring(math.floor(ready + 0.5)) .. "s")
            end
        end
        ImGui.PopStyleColor()
        ImGui.Spacing()
    end

    -- ---- Spell Info blocks (sections 3-6): Clicky, Proc, Worn, Focus — only if effect present ----
    if #effects > 0 then
        local spellInfoOrder = { "Clicky", "Proc", "Worn", "Focus" }
        local spellInfoColors = {
            Clicky = ImVec4(0.4, 0.9, 0.4, 1.0),
            Proc   = ImVec4(0.9, 0.65, 0.2, 1.0),
            Worn   = ImVec4(0.9, 0.9, 0.4, 1.0),
            Focus  = ImVec4(0.5, 0.75, 1.0, 1.0),
        }
        for _, key in ipairs(spellInfoOrder) do
            for _, e in ipairs(effects) do
                if e.key == key and e.spellId and e.spellName then
                    renderSpellInfoBlock(e.spellId, spellInfoColors[key], "Spell Info for " .. key .. " effect: " .. e.spellName)
                    break
                end
            end
        end
    end

    -- ---- Value, Tribute ----
    local val = item.totalValue or item.value
    if val and val ~= 0 then
        ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "Value")
        local valStr = (ItemUtils and ItemUtils.formatValue) and ItemUtils.formatValue(val) or tostring(val)
        ImGui.Text(valStr)
    end
    if item.tribute and item.tribute ~= 0 then
        ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "Tribute")
        ImGui.Text(tostring(item.tribute))
    end

    if ImGui.EndChild then ImGui.EndChild() end
    ImGui.Columns(1)
end

--- Render full item tooltip matching in-game Item Display. Shows every property.
--- Runs content in pcall so binding/API errors do not leave tooltip stack inconsistent.
--- Caller must call BeginTooltip before and EndTooltip after.
function ItemTooltip.renderStatsTooltip(item, ctx, opts)
    if not item then return end
    opts = opts or {}
    local ok = pcall(function() ItemTooltip.renderItemDisplayContent(item, ctx, opts) end)
    if not ok then
        ImGui.Text("Item stats")
    end
end

return ItemTooltip
