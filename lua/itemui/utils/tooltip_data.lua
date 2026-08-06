--[[ tooltip_data.lua: Tooltip data helpers, cache, and prepareTooltipContent. No ImGui. ]]
local itemHelpers = require('itemui.utils.item_helpers')
local itemCompare = require('itemui.utils.item_compare')
local tooltip_layout = require('itemui.utils.tooltip_layout')

local M = {}

-- Tooltip pre-computation cache (Task 3.4): keyed by (itemId, bag, slot, source, socketIndex); invalidate on scan
local tooltipCache = {}
local TOOLTIP_CACHE_MAX = 200

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

-- Shared helpers live in tooltip_layout (single definition; re-exported below for the api table)
local SIZE_NAMES = tooltip_layout.SIZE_NAMES
local formatSize = tooltip_layout.formatSize

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

--- Attribute line: "Label: base" or "Label: base+heroic" (defined in tooltip_layout)
local attrLine = tooltip_layout.attrLine

-- All numeric fields from STAT_TLO_MAP that augments can contribute to.
-- String-only fields (baneDMGType, dmgBonusType) are excluded. Used to merge socketed
-- augment stats into the parent item's tooltip (here and in tooltip_render).
local STAT_MERGE_FIELDS = {
    "ac", "hp", "mana", "endurance",
    "str", "sta", "agi", "dex", "int", "wis", "cha",
    "attack", "accuracy", "avoidance", "shielding", "haste",
    "damage", "itemDelay", "dmgBonus",
    "spellDamage", "strikeThrough", "damageShield", "combatEffects",
    "dotShielding", "hpRegen", "manaRegen", "enduranceRegen",
    "spellShield", "damageShieldMitigation", "stunResist", "clairvoyance", "healAmount",
    "heroicSTR", "heroicSTA", "heroicAGI", "heroicDEX", "heroicINT", "heroicWIS", "heroicCHA",
    "svMagic", "svFire", "svCold", "svPoison", "svDisease", "svCorruption",
    "heroicSvMagic", "heroicSvFire", "heroicSvCold", "heroicSvDisease", "heroicSvPoison", "heroicSvCorruption",
    "luck", "purity", "baneDMG", "skillModValue", "skillModMax",
}

-- Item effect kinds, in display order. Shared with tooltip_render.
local EFFECT_KEYS = {"Clicky", "Worn", "Proc", "Focus", "Spell"}

--- Append effect entries ({key, spellId, spellName, desc, castTime, recastTime}) from itm to ef.
--- No-op when ctx lacks the spell helpers. Shared by prepareTooltipContent and tooltip_render.
local function addEffectsFromItem(ctx, ef, itm, keys)
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
local function getAugmentSlotLinesFromIt(it, augSlots)
    local itId = it and it.ID and it.ID()
    if (tonumber(itId) or 0) == 0 then return nil end
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
        if typ ~= 20 then
            local typeNameForPrefix = (typ > 0) and (AUG_TYPE_NAMES[typ] or ("Type " .. tostring(typ))) or "empty"
            local prefix = string.format("Slot %d, type %d (%s): ", i, typ, typeNameForPrefix)
            -- socketType is carried (windows pass item 10) so the cursor ring can decide
            -- whether an empty socket accepts what you are holding WITHOUT re-reading the
            -- TLO per row per frame. It was already computed above and then discarded.
            lines[#lines + 1] = { iconId = iconId, text = line, prefix = prefix,
                                  augName = augName, slotIndex = i, socketType = typ }
        end
    end
    return lines
end

local function getAugmentSlotLines(bag, slot, source, augSlots)
    local it = itemHelpers.getItemTLO(bag, slot, source)
    return getAugmentSlotLinesFromIt(it, augSlots)
end

local function getSocketItemStats(it, bag, slot, source, socketIndex)
    if not it or not it.Item or not bag or not slot or not source or not socketIndex then return nil end
    local ok, socketTLO = pcall(function() return it.Item(socketIndex) end)
    local sockId = ok and socketTLO and socketTLO.ID and socketTLO.ID()
    if (tonumber(sockId) or 0) == 0 then return nil end
    return itemHelpers.buildItemFromMQ(socketTLO, bag, slot, source, socketIndex)
end

local function getOrnamentFromIt(it)
    local itId = it and it.ID and it.ID()
    if (tonumber(itId) or 0) == 0 then return nil end
    if itemHelpers.getSlotType(it, ORNAMENT_SLOT_INDEX) ~= 20 then
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

--- Count rows in each column to match the actual tooltip layout.
local function countTooltipRows(item, effects, parentIt, bag, slot, source, opts, itemInfoRows, statRows, augCount)
    local nameLen = item.name and #tostring(item.name) or 0
    local nameLines = nameLen > 0 and math.max(1, math.ceil(nameLen / tooltip_layout.CHARS_PER_LINE_NAME)) or 1
    local left = nameLines
    if item.id and item.id ~= 0 then left = left + 1 end
    if getTypeLine(item) then left = left + 1 end
    if (item.stackSizeMax and item.stackSizeMax > 1) or (item.stackSize and item.stackSize > 1) then left = left + 1 end
    left = left + 1
    left = left + 4
    local ornament = parentIt and not opts.socketIndex and getOrnamentFromIt(parentIt)
    if ornament and ornament.name then left = left + 4 end
    if item.container and item.container > 0 then left = left + 1 end
    left = left + 1
    if itemInfoRows > 0 then left = left + 2 + itemInfoRows end
    if statRows > 0 then left = left + 2 + statRows end
    local itemTypeLower = item.type and tostring(item.type):lower() or ""
    if itemTypeLower == "augmentation" then
        local slotIds = itemHelpers.getAugTypeSlotIds(item.augType or 0)
        local nSlot = (slotIds and #slotIds) or 0
        if nSlot > 0 then left = left + 2 + nSlot + 1 end
        if item.augRestrictions and item.augRestrictions > 0 then left = left + 2 end
    end
    if augCount > 0 then left = left + 3 + augCount end

    local right = 0
    if #effects > 0 then
        right = right + 2
        for _, e in ipairs(effects) do
            right = right + 1
            if e.key == "Clicky" and (e.castTime ~= nil or (e.recastTime ~= nil and e.recastTime > 0)) then
                if e.castTime ~= nil then right = right + 1 end
                if e.recastTime ~= nil and e.recastTime > 0 then right = right + 1 end
            end
            if e.desc and e.desc ~= "" then
                right = right + math.max(1, math.ceil(#e.desc / tooltip_layout.CHARS_PER_LINE_DESC)) + 1
            end
        end
        right = right + 1
    end
    if not opts.socketIndex then
        right = right + 2
        if item.id and item.id ~= 0 then right = right + 1 end
        if item.icon and item.icon ~= 0 then right = right + 1 end
        if (item.totalValue or item.value) and (item.totalValue or item.value) ~= 0 then right = right + 1 end
        if item.damage and item.damage ~= 0 and item.itemDelay and item.itemDelay ~= 0 then right = right + 1 end
        right = right + 1
        if bag and slot and source then right = right + 1 end
        right = right + 2
    end
    local spellInfoOrder = { "Clicky", "Proc", "Worn", "Focus" }
    local seenKey = {}
    for _, e in ipairs(effects) do seenKey[e.key] = true end
    for _, key in ipairs(spellInfoOrder) do
        if seenKey[key] then
            right = right + 1 + 1 + 5
        end
    end
    if (item.totalValue or item.value) and (item.totalValue or item.value) ~= 0 then right = right + 2 end
    if item.tribute and item.tribute ~= 0 then right = right + 2 end

    return left, right
end

--- Cache key for (item, opts): id/bag/slot/source/socketIndex — must stay in sync with how
--- prepareTooltipContent derives those values.
local function tooltipCacheKey(item, opts)
    local source = opts.source or (item and item.source) or "inv"
    local bag = item.bag ~= nil and item.bag or opts.bag
    local slot = item.slot ~= nil and item.slot or opts.slot
    local socketIndex = opts.socketIndex or 0
    local id = item.id or 0
    return tostring(id) .. "\0" .. tostring(bag or -1) .. "\0" .. tostring(slot or -1) .. "\0" .. tostring(source) .. "\0" .. tostring(socketIndex)
end

--- Pre-warm item, build effects, and estimate tooltip size. Returns effects, width, height.
function M.prepareTooltipContent(item, ctx, opts)
    if not item then return {}, tooltip_layout.TOOLTIP_MIN_WIDTH, 400 end
    opts = opts or {}
    local source = opts.source or (item and item.source) or "inv"
    local bag = item.bag ~= nil and item.bag or opts.bag
    local slot = item.slot ~= nil and item.slot or opts.slot
    local cacheKey = tooltipCacheKey(item, opts)
    local cached = tooltipCache[cacheKey]
    if cached then
        opts.tooltipColWidth = tooltip_layout.TOOLTIP_COL_WIDTH
        return cached.effects, cached.width, cached.height
    end
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
    local effects = {}
    addEffectsFromItem(ctx, effects, item, EFFECT_KEYS)
    -- Merge socket contributions once here (entry is cached until the next scan): effect
    -- entries plus augStats (summed numeric stats) and augLines (slot rows) consumed by
    -- tooltip_render, so an augmented-item hover does not re-walk AugSlot TLOs every frame.
    local augStats = nil
    if parentIt and bag ~= nil and slot ~= nil and source and not opts.socketIndex and (item.augSlots or 0) > 0 then
        augStats = {}
        for sockIdx = 1, item.augSlots do
            local socketItem = getSocketItemStats(parentIt, bag, slot, source, sockIdx)
            if socketItem then
                if sockIdx <= 5 then addEffectsFromItem(ctx, effects, socketItem, EFFECT_KEYS) end
                for _, field in ipairs(STAT_MERGE_FIELDS) do
                    local v = tonumber(socketItem[field])
                    if v and v ~= 0 then augStats[field] = (augStats[field] or 0) + v end
                end
            end
        end
    end
    -- false = computed and none (lets tooltip_render skip its live fallback entirely)
    local augLines = getAugmentSlotLinesFromIt(it, item.augSlots) or false
    -- Ornament slot (windows pass 19a): slot 5, type 20, kept out of augLines by design —
    -- cached separately so Item Display's AUGMENTS section can render it without a TLO walk.
    local ornamentLine = nil
    if it and not opts.socketIndex and itemHelpers.itemHasOrnamentSlot(it) then
        local augName, iconId = "empty", 0
        local okN, nVal = pcall(function()
            local itemN = it.Item and it.Item(ORNAMENT_SLOT_INDEX)
            return itemN and itemN.Name and itemN.Name()
        end)
        if okN and nVal and tostring(nVal) ~= "" and tostring(nVal):lower() ~= "null" then
            augName = tostring(nVal)
            local okI, ico = pcall(function()
                local itemN = it.Item and it.Item(ORNAMENT_SLOT_INDEX)
                return itemN and itemN.Icon and itemN.Icon()
            end)
            if okI and ico then iconId = tonumber(ico) or 0 end
        end
        ornamentLine = { iconId = iconId, augName = augName, slotIndex = ORNAMENT_SLOT_INDEX, typ = 20 }
    end
    -- MOCKUP_score_surfaces A: the score line, computed once per cache entry so the
    -- tooltip's EXACT sizing and its content always agree. "~" by contract (ballpark);
    -- whatever the model cannot price is NAMED in the unscored line, capped at two
    -- names + a count so one line stays one line. No class answer (headless, or the
    -- TLO not up yet) = no score line at all.
    local scoreInfo = nil
    do
        local cls = itemHelpers.getPlayerClassShortName and itemHelpers.getPlayerClassShortName()
        if cls then
            local effNames = {}
            for _, e in ipairs(effects) do
                if e.spellName and (e.key == "Worn" or e.key == "Focus" or e.key == "Clicky" or e.key == "Proc") then
                    effNames[#effNames + 1] = e.spellName
                end
            end
            local okS, total, brk = pcall(itemCompare.scoreForClass, item, cls,
                { augStats = augStats, effects = effNames })
            if okS and type(total) == "number" then
                local un = (brk and brk.unscored) or {}
                local unscoredLine = nil
                if #un > 0 then
                    local shown = {}
                    for i = 1, math.min(2, #un) do shown[#shown + 1] = tostring(un[i]) end
                    unscoredLine = "unscored: " .. table.concat(shown, " . ")
                    if #un > 2 then
                        unscoredLine = unscoredLine .. string.format(" +%d more", #un - 2)
                    end
                end
                scoreInfo = { total = total, unscoredLine = unscoredLine }
            end
        end
    end
    local itemInfoRows = tooltip_layout.getItemInfoRowCount(item)
    local statRows = tooltip_layout.getStatRowCount(item)
    local augCount = (parentIt and itemHelpers.getStandardAugSlotsCountFromTLO(parentIt)) or ((item.augSlots or 0) > 0 and (itemHelpers.itemHasOrnamentSlot(it or parentIt) and math.min(AUGMENT_SLOT_COUNT, (item.augSlots or 0) - 1) or math.min(AUGMENT_SLOT_COUNT, item.augSlots or 0)) or 0)
    if augCount < 0 then augCount = 0 end
    local leftRows, rightRows = countTooltipRows(item, effects, parentIt, bag, slot, source, opts, itemInfoRows, statRows, augCount)
    -- The score line(s) pay for their own height - added to the row count BEFORE the
    -- size is computed, the same contract every other tooltip row lives under. RIGHT
    -- rows: the line renders at the bottom of column 2 (inside the column child -
    -- drawn after the children it sat past the window edge, the field's clipped
    -- green number).
    if scoreInfo then
        rightRows = rightRows + 1 + (scoreInfo.unscoredLine and 1 or 0)
    end
    local width, height = tooltip_layout.computeTooltipSize(leftRows, rightRows)
    opts.tooltipColWidth = tooltip_layout.TOOLTIP_COL_WIDTH
    tooltipCache[cacheKey] = { effects = effects, width = width, height = height, augStats = augStats, augLines = augLines, ornamentLine = ornamentLine, scoreInfo = scoreInfo }
    if TOOLTIP_CACHE_MAX > 0 then
        local n = 0
        for _ in pairs(tooltipCache) do n = n + 1; if n > TOOLTIP_CACHE_MAX then break end end
        if n > TOOLTIP_CACHE_MAX then tooltipCache = {} end
    end
    return effects, width, height
end

function M.invalidateTooltipCache()
    tooltipCache = {}
end

--- Return the scan-invalidated cache entry for (item, opts), or nil when absent.
--- Read-only accessor for tooltip_render: entry.augStats and entry.augLines (false = none)
--- avoid re-walking socket TLOs every frame; callers fall back to live compute when nil.
function M.getCachedTooltipEntry(item, opts)
    if not item then return nil end
    return tooltipCache[tooltipCacheKey(item, opts or {})]
end

--- Test seam: plant a cache entry under the same key the render path will look up.
--- Headless suites can't run the TLO socket walk that normally fills the cache, and the
--- socket-row render code deserves coverage (a dead aug row shipped once).
function M._seedTooltipCacheForTests(item, opts, entry)
    if not item then return end
    tooltipCache[tooltipCacheKey(item, opts or {})] = entry
end

-- Exports for item_tooltip api table and tooltip_render
M.getTypeLine = getTypeLine
M.formatSize = formatSize
M.attrLine = attrLine
M.slotStringToDisplay = slotStringToDisplay
M.getSocketItemStats = getSocketItemStats
M.getOrnamentFromIt = getOrnamentFromIt
M.getAugmentSlotLinesFromIt = getAugmentSlotLinesFromIt
M.getAugmentSlotLines = getAugmentSlotLines
M.ORNAMENT_SLOT_INDEX = ORNAMENT_SLOT_INDEX
M.AUG_TYPE_NAMES = AUG_TYPE_NAMES
M.AUG_RESTRICTION_NAMES = AUG_RESTRICTION_NAMES
M.SIZE_NAMES = SIZE_NAMES
M.STAT_MERGE_FIELDS = STAT_MERGE_FIELDS
M.EFFECT_KEYS = EFFECT_KEYS
M.addEffectsFromItem = addEffectsFromItem

return M
