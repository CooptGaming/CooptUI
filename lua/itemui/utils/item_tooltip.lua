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

local TOOLTIP_MIN_WIDTH = 540

function ItemTooltip.beginItemTooltip()
    -- SetNextWindowSize before BeginTooltip can cause issues in some ImGui bindings; make it optional
    if ImGui.SetNextWindowSize then
        local ok = pcall(function()
            ImGui.SetNextWindowSize(ImVec2(TOOLTIP_MIN_WIDTH, 0), ImGuiCond.Always)
        end)
        if not ok then
            -- ignore: tooltip will use default size
        end
    end
    ImGui.BeginTooltip()
end

-- Slot index (0-22) to display name
local SLOT_DISPLAY_NAMES = {
    [0] = "Charm", [1] = "Ear", [2] = "Head", [3] = "Face", [4] = "Ear",
    [5] = "Neck", [6] = "Shoulder", [7] = "Arms", [8] = "Back", [9] = "Wrist",
    [10] = "Wrist", [11] = "Ranged", [12] = "Hands", [13] = "Primary", [14] = "Secondary",
    [15] = "Ring", [16] = "Ring", [17] = "Chest", [18] = "Legs", [19] = "Feet",
    [20] = "Waist", [21] = "Power", [22] = "Ammo",
}

local function slotToDisplayName(s)
    if s == nil or s == "" then return nil end
    local n = tonumber(s)
    if n ~= nil and SLOT_DISPLAY_NAMES[n] then return SLOT_DISPLAY_NAMES[n] end
    local str = tostring(s):lower():gsub("^%l", string.upper)
    return (str ~= "") and str or nil
end

local function slotStringToDisplay(str)
    if not str or str == "" then return str end
    local seen = {}
    local parts = {}
    for token in tostring(str):gmatch("[^,%s]+") do
        local name = slotToDisplayName(token)
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

--- Class/race/slot from item TLO (pass existing it to avoid re-resolving). Returns clsStr, raceStr, slotStr.
local function getItemClassRaceSlotFromIt(it)
    local clsStr, raceStr, slotStr = "", "", ""
    if not it or not it.ID or it.ID() == 0 then return clsStr, raceStr, slotStr end
    local function add(parts, fn, n)
        if not n or n <= 0 then return end
        for i = 1, n do local v = fn(i); if v and v ~= "" then parts[#parts + 1] = v end end
        if #parts == 0 then for i = 0, n - 1 do local v = fn(i); if v and v ~= "" then parts[#parts + 1] = v end end end
    end
    local nClass = it.Classes and it.Classes()
    if nClass and nClass > 0 then
        if nClass >= 16 then clsStr = "All"
        else local p = {}; add(p, function(i) local c = it.Class and it.Class(i); return c and tostring(c) or "" end, nClass); clsStr = table.concat(p, " ") end
    end
    local nRace = it.Races and it.Races()
    if nRace and nRace > 0 then
        if nRace >= 15 then raceStr = "All"
        else local p = {}; add(p, function(i) local r = it.Race and it.Race(i); return r and tostring(r) or "" end, nRace); raceStr = table.concat(p, " ") end
    end
    local nSlots = it.WornSlots and it.WornSlots()
    if nSlots and nSlots > 0 then
        if nSlots >= 20 then slotStr = "All"
        else local p = {}; add(p, function(i) local s = it.WornSlot and it.WornSlot(i); return s and slotToDisplayName(tostring(s)) or "" end, nSlots); slotStr = table.concat(p, ", ") end
    end
    return clsStr, raceStr, slotStr
end

--- Class/race/slot from bag/slot/source (resolves TLO then calls getItemClassRaceSlotFromIt).
local function getItemClassRaceSlotFromTLO(bag, slot, source)
    local it = getItemTLO(bag, slot, source)
    return getItemClassRaceSlotFromIt(it)
end

-- Augment slot type ID to display name (in-game style)
local AUG_TYPE_NAMES = {
    [1] = "General: Single", [2] = "Armor: General", [3] = "Armor: Visible", [4] = "Weapon: General",
    [5] = "Weapon: Secondary", [6] = "General: Raid", [7] = "General: Group", [8] = "Energeian Power Source",
    [20] = "Ornamentation",
}

--- Use shared getItemTLO from item_helpers (single place for bank vs inv TLO resolution).
local function getItemTLO(bag, slot, source)
    return itemHelpers.getItemTLO(bag, slot, source)
end

--- Core: build augment slot lines from item TLO (pass it to avoid re-resolving). Returns table of "Slot N, type X (TypeName): empty|name".
--- Tries AugSlot(i) first; fallback AugSlot1..6. Never break on nil slot so other slots still show when TLO shape differs.
local function getAugmentSlotLinesFromIt(it, augSlots)
    if not it or not it.ID or it.ID() == 0 then return nil end
    if (augSlots or 0) == 0 then return nil end
    local lines = {}
    for i = 1, 6 do
        local typ, augName = 0, "empty"
        -- Prefer AugSlot(i) (augtype) when available; coerce Type to number (may be string or function)
        local okAug, aug = pcall(function() return it.AugSlot and it.AugSlot(i) end)
        if okAug and aug then
            local t = (type(aug.Type) == "function" and aug.Type()) or aug.Type
            typ = tonumber(t) or tonumber(tostring(t)) or 0
            if aug.Name then
                local nOk, nVal = pcall(function() return type(aug.Name) == "function" and aug.Name() or aug.Name end)
                if nOk and nVal and tostring(nVal) ~= "" then augName = tostring(nVal) end
            end
        end
        if typ == 0 then
            -- Fallback: AugSlot1..6 (type int) and Item(i) for name
            local acc = it["AugSlot" .. i]
            if acc ~= nil then
                typ = tonumber(type(acc) == "function" and acc() or acc) or 0
                if typ > 0 then
                    local ok, itemN = pcall(function() return it.Item and it.Item(i) end)
                    if ok and itemN and itemN.Name then
                        local nameOk, nameVal = pcall(function() return itemN.Name() end)
                        if nameOk and nameVal and tostring(nameVal) ~= "" then augName = tostring(nameVal) end
                    end
                end
            else
                -- AugSlot# property missing; reuse first AugSlot(i) result if we have it to avoid second TLO call
                if okAug and aug then
                    local t = (type(aug.Type) == "function" and aug.Type()) or aug.Type
                    typ = tonumber(t) or tonumber(tostring(t)) or 0
                    if typ > 0 then
                        local ok, itemN = pcall(function() return it.Item and it.Item(i) end)
                        if ok and itemN and itemN.Name then
                            local nameOk, nameVal = pcall(function() return itemN.Name() end)
                            if nameOk and nameVal and tostring(nameVal) ~= "" then augName = tostring(nameVal) end
                        end
                    end
                else
                    okAug, aug = pcall(function() return it.AugSlot and it.AugSlot(i) end)
                    if okAug and aug then
                        local t = (type(aug.Type) == "function" and aug.Type()) or aug.Type
                        typ = tonumber(t) or tonumber(tostring(t)) or 0
                        if typ > 0 then
                            local ok, itemN = pcall(function() return it.Item and it.Item(i) end)
                            if ok and itemN and itemN.Name then
                                local nameOk, nameVal = pcall(function() return itemN.Name() end)
                                if nameOk and nameVal and tostring(nameVal) ~= "" then augName = tostring(nameVal) end
                            end
                        end
                    end
                end
            end
        end
        if typ > 0 then
            if not augName or augName == "" or tostring(augName):lower() == "null" then augName = "empty" end
            local typeName = AUG_TYPE_NAMES[typ] or ("Type " .. tostring(typ))
            lines[#lines + 1] = string.format("Slot %d, type %d (%s): %s", i, typ, typeName, augName)
        end
    end
    return #lines > 0 and lines or nil
end

--- Augment slot lines from bag/slot/source (resolves TLO then calls getAugmentSlotLinesFromIt).
local function getAugmentSlotLines(bag, slot, source, augSlots)
    local it = getItemTLO(bag, slot, source)
    return getAugmentSlotLinesFromIt(it, augSlots)
end

--- Ornament name from item TLO. Tries it.Ornament.Name(); if missing/errors (e.g. no Ornament member), uses augment slot with type 20 (Ornamentation).
--- Uses AugSlot(i) when AugSlot# property is nil so ornament shows on TLOs that only expose the method.
local function getOrnamentNameFromIt(it)
    if not it or not it.ID or it.ID() == 0 then return nil end
    local ok, name = pcall(function()
        if it.Ornament and it.Ornament.Name then return it.Ornament.Name() end
        return nil
    end)
    if ok and name and tostring(name) ~= "" then return tostring(name) end
    -- Fallback: type 20 = Ornamentation; try AugSlot# then AugSlot(i)
    for i = 1, 6 do
        local typ = 0
        local acc = it["AugSlot" .. i]
        if acc ~= nil then
            typ = tonumber(type(acc) == "function" and acc() or acc) or 0
        else
            local okAug, aug = pcall(function() return it.AugSlot and it.AugSlot(i) end)
            if okAug and aug then
                local t = (type(aug.Type) == "function" and aug.Type()) or aug.Type
                typ = tonumber(t) or tonumber(tostring(t)) or 0
            end
        end
        if typ == 20 then
            local ok2, itemN = pcall(function() return it.Item and it.Item(i) end)
            if ok2 and itemN and itemN.Name then
                local nameOk, nameVal = pcall(function() return itemN.Name() end)
                if nameOk and nameVal and tostring(nameVal) ~= "" then return tostring(nameVal) end
            end
            return "empty"
        end
    end
    return nil
end

--- Build a compact list of only non-nil values (so row count = longest column's value count, no placeholders in longest col).
local function compactCol(c)
    local t = {}
    for i = 1, 256 do if c[i] ~= nil then t[#t + 1] = c[i] end end
    return t
end

--- Returns true if the current player can use the item (class, race, deity, level).
local function canPlayerUseItem(item, source)
    local Me = mq.TLO and mq.TLO.Me
    if not Me or not Me.Level then return true end
    local myLevel = tonumber(Me.Level()) or 0
    local reqLevel = (item.requiredLevel and item.requiredLevel > 0) and item.requiredLevel or nil
    if reqLevel and myLevel < reqLevel then return false end
    local myDeity = Me.Deity and Me.Deity() and tostring(Me.Deity()):lower() or ""
    if item.deity and item.deity ~= "" then
        local allowed = false
        for part in (tostring(item.deity):lower()):gmatch("%S+") do
            if part == myDeity then allowed = true break end
        end
        if not allowed then return false end
    end
    local myClass = Me.Class and tostring(Me.Class() or ""):lower() or ""
    local myRace = Me.Race and tostring(Me.Race() or ""):lower() or ""
    if item.class and item.class ~= "" and item.class:lower() ~= "all" then
        local ok = false
        for part in (tostring(item.class):lower()):gmatch("%S+") do
            if part == myClass then ok = true break end
        end
        if not ok then return false end
    end
    if item.race and item.race ~= "" and item.race:lower() ~= "all" then
        local ok = false
        for part in (tostring(item.race):lower()):gmatch("%S+") do
            if part == myRace then ok = true break end
        end
        if not ok then return false end
    end
    return true
end

--- Render full item tooltip matching in-game Item Display. Shows every property.
--- Runs content in pcall so binding/API errors do not leave tooltip stack inconsistent.
function ItemTooltip.renderStatsTooltip(item, ctx, opts)
    if not item then return end
    opts = opts or {}
    local source = opts.source or (item and item.source) or "inv"
    -- Use bag/slot from item or opts so tooltip works when getItemStatsForTooltip returns an object without bag/slot
    local bag = item.bag ~= nil and item.bag or opts.bag
    local slot = item.slot ~= nil and item.slot or opts.slot

    local function render()
    -- Resolve item TLO once per hover (quick); use for class/race/slot, ornament, and augment lines.
    local it = (bag ~= nil and slot ~= nil and source) and getItemTLO(bag, slot, source) or nil
    local itValid = it and it.ID and it.ID() ~= 0

    -- ---- Header: Name, ID, Type (like in-game Description) ----
    local nameColor = ImVec4(0.45, 0.85, 0.45, 1.0)
    if not canPlayerUseItem(item, source) then
        nameColor = ImVec4(0.95, 0.35, 0.35, 1.0)
    end
    ImGui.TextColored(nameColor, item.name or "—")
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

    -- ---- Class, Race, Slot, Deity, Ornament, Augment slots, Container (top section, above Item info) ----
    local cls, race, slotStr = "—", "—", ""
    if itValid then
        local ok, c, r, s = pcall(getItemClassRaceSlotFromIt, it)
        if ok then
            if c and c ~= "" then cls = c end
            if r and r ~= "" then race = r end
            if s and s ~= "" then slotStr = s end
        end
    else
        local ok, c, r, s = pcall(getItemClassRaceSlotFromTLO, bag, slot, source)
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
    -- Ornament first (match Item Display: Appearance then sockets). Uses type-20 slot when .Ornament missing.
    if itValid then
        local ornamentName = getOrnamentNameFromIt(it)
        if ornamentName and ornamentName ~= "" then
            ImGui.Spacing()
            ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "Ornament")
            ImGui.Text(ornamentName)
            ImGui.Spacing()
        end
    end
    -- Augmentation slots (standard): Slot N, type X (TypeName): empty|name
    local augLines = itValid and getAugmentSlotLinesFromIt(it, item.augSlots) or ((bag ~= nil and slot ~= nil and source) and getAugmentSlotLines(bag, slot, source, item.augSlots) or nil)
    if augLines and #augLines > 0 then
        ImGui.Spacing()
        ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "Augmentation slots (standard)")
        ImGui.Spacing()
        for _, line in ipairs(augLines) do ImGui.Text(line) end
        ImGui.Spacing()
    elseif item.augSlots and item.augSlots > 0 then
        ImGui.Text("Augment slots: " .. tostring(item.augSlots))
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
    end

    -- ---- All Stats: Primary (base+heroic), Resistances, Combat/utility ----
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
    -- Order combat stats to match in-game Item Display right column, then remaining
    local combat = {
        cl(item.attack, "Attack"),
        cl(item.hpRegen, "HP Regen"),
        cl(item.manaRegen, "Mana Regen"),
        cl(item.enduranceRegen, "End Regen"),
        cl(item.combatEffects, "Combat Eff"),
        cl(item.damageShield, "Dmg Shield"),
        cl(item.damageShieldMitigation, "Dmg Shld Mit"),
        cl(item.accuracy, "Accuracy"),
        cl(item.strikeThrough, "Strike Thr"),
        cl(item.healAmount, "Heal Amount"),
        cl(item.spellDamage, "Spell Dmg"),
        cl(item.spellShield, "Spell Shield"),
        cl(item.shielding, "Shielding"),
        cl(item.dotShielding, "DoT Shield"),
        cl(item.avoidance, "Avoidance"),
        cl(item.stunResist, "Stun Resist"),
        cl(item.clairvoyance, "Clairvoyance"),
        cl(item.haste, "Haste"),
        cl(item.luck, "Luck"),
        cl(item.purity, "Purity"),
    }
    local hasAnyStat = false
    for _, v in ipairs(attrs) do if v then hasAnyStat = true break end end
    for _, v in ipairs(resists) do if v then hasAnyStat = true break end end
    for _, v in ipairs(combat) do if v then hasAnyStat = true break end end
    if hasAnyStat then
        -- Values at top, placeholders at bottom. Use compact columns (non-nil only) so row count = longest column's value count (no placeholders in longest col).
        local placeholder = " "
        local a, r, c = compactCol(attrs), compactCol(resists), compactCol(combat)
        local maxRows = math.max(#a, #r, #c)
        local statsFlat = {}
        for row = 1, maxRows do
            statsFlat[#statsFlat + 1] = a[row] or placeholder
            statsFlat[#statsFlat + 1] = r[row] or placeholder
            statsFlat[#statsFlat + 1] = c[row] or placeholder
        end
        ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "All Stats")
        ImGui.Spacing()
        ImGui.Columns(3, "##StatsCols", false)
        ImGui.SetColumnWidth(0, colW1)
        ImGui.SetColumnWidth(1, colW2)
        ImGui.SetColumnWidth(2, colW3)
        for i = 1, #statsFlat do
            if statsFlat[i] ~= placeholder then ImGui.Text(statsFlat[i]) end
            ImGui.NextColumn()
        end
        ImGui.Columns(1)
        ImGui.Spacing()
    end

    -- ---- Item effects: in-game style "Effect: SpellName (Worn)" / "Focus Effect: SpellName", with Cast/Recast for clicky ----
    if ctx and ctx.getItemSpellId and ctx.getSpellName then
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
        local effects = {}
        for _, key in ipairs({"Clicky", "Worn", "Proc", "Focus", "Spell"}) do
            local id = ctx.getItemSpellId(item, key)
            if id and id > 0 then
                local spellName = ctx.getSpellName(id)
                if spellName and spellName ~= "" then
                    local desc = (ctx.getSpellDescription and ctx.getSpellDescription(id)) or ""
                    local castTime = (key == "Clicky" and ctx.getSpellCastTime and ctx.getSpellCastTime(id)) or nil
                    local recastTime = (key == "Clicky" and ctx.getSpellRecastTime and ctx.getSpellRecastTime(id)) or nil
                    effects[#effects + 1] = { key = key, spellName = spellName, desc = desc, castTime = castTime, recastTime = recastTime }
                end
            end
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
    end -- close render()
    local ok = pcall(render)
    if not ok then
        ImGui.Text("Item stats")
    end
end

return ItemTooltip
