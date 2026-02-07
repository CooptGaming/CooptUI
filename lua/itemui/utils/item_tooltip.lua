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

local function getItemClassRaceSlotInv(bag, slot)
    local clsStr, raceStr, slotStr = "", "", ""
    local pack = mq.TLO and mq.TLO.Me and mq.TLO.Me.Inventory and mq.TLO.Me.Inventory("pack" .. (bag or 0))
    if not pack then return clsStr, raceStr, slotStr end
    local it = pack.Item and pack.Item(slot or 0)
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

local function getItemClassRaceSlotBank(bankBag, bankSlot)
    local clsStr, raceStr, slotStr = "", "", ""
    local bn = mq.TLO and mq.TLO.Me and mq.TLO.Me.Bank and mq.TLO.Me.Bank(bankBag or 0)
    if not bn then return clsStr, raceStr, slotStr end
    local it = bn.Item and bn.Item(bankSlot or 0)
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
    local source = opts.source or "inv"

    local function render()
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

    -- ---- Class, Race, Slot, Deity, Augment slots, Container (top section, above Item info) ----
    local cls, race, slot = "—", "—", ""
    if item.bag ~= nil and item.slot ~= nil and source then
        local ok, c, r, s
        if source == "bank" then ok, c, r, s = pcall(getItemClassRaceSlotBank, item.bag, item.slot)
        else ok, c, r, s = pcall(getItemClassRaceSlotInv, item.bag, item.slot) end
        if ok then
            if c and c ~= "" then cls = c end
            if r and r ~= "" then race = r end
            if s and s ~= "" then slot = s end
        end
    end
    if cls == "—" and (item.class and item.class ~= "") then cls = item.class end
    if race == "—" and (item.race and item.race ~= "") then race = item.race end
    if (slot == "" or slot == "—") and (item.wornSlots and item.wornSlots ~= "") then slot = item.wornSlots end
    if cls and cls ~= "" and cls ~= "—" then ImGui.Text("Class: " .. tostring(cls)) end
    if race and race ~= "" and race ~= "—" then ImGui.Text("Race: " .. tostring(race)) end
    if item.deity and item.deity ~= "" then ImGui.Text("Deity: " .. tostring(item.deity)) end
    slot = slotStringToDisplay(slot)
    if slot and slot ~= "" and slot ~= "—" then ImGui.Text(slot) end
    if item.augSlots and item.augSlots > 0 then ImGui.Text("Augment slots: " .. tostring(item.augSlots)) end
    if item.container and item.container > 0 then
        local capStr = item.sizeCapacity and item.sizeCapacity > 0 and (SIZE_NAMES[item.sizeCapacity] or tostring(item.sizeCapacity)) or nil
        ImGui.Text("Container: " .. tostring(item.container) .. " slot" .. (item.container == 1 and "" or "s") .. (capStr and (" (" .. capStr .. ")") or ""))
    end
    ImGui.Spacing()

    -- ---- Item info: Size, AC, HP, Mana, End (and all other core fields) ----
    local colW1, colW2, colW3 = 145, 100, 110
    local L1, L2, L3 = "%-12s %s", "%-6s %s", "%-10s %s"
    local function cell1(t) if t then ImGui.Text(t) end end
    local function cell2(t) ImGui.NextColumn(); if t then ImGui.Text(t) end end
    local function cell3(t) ImGui.NextColumn(); if t then ImGui.Text(t) end end
    local function rowEnd() ImGui.NextColumn() end

    local hasItemInfo = formatSize(item) or (item.ac and item.ac ~= 0) or (item.hp and item.hp ~= 0) or (item.mana and item.mana ~= 0) or (item.endurance and item.endurance ~= 0) or (item.weight and item.weight ~= 0) or (item.damage and item.damage ~= 0) or (item.itemDelay and item.itemDelay ~= 0) or (item.requiredLevel and item.requiredLevel ~= 0) or (item.recommendedLevel and item.recommendedLevel ~= 0) or (item.dmgBonus and item.dmgBonus ~= 0) or (item.type and item.type ~= "") or (item.instrumentType and item.instrumentType ~= "") or (item.haste and item.haste ~= 0) or (item.charges and item.charges ~= 0) or (item.range and item.range ~= 0) or (item.skillModValue and item.skillModValue ~= 0) or (item.baneDMG and item.baneDMG ~= 0)
    if hasItemInfo then
        ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "Item info")
        ImGui.Spacing()
        ImGui.Columns(3, "##TooltipItemInfo", false)
        ImGui.SetColumnWidth(0, colW1)
        ImGui.SetColumnWidth(1, colW2)
        ImGui.SetColumnWidth(2, colW3)
        -- Row: Size, AC, HP
        cell1(formatSize(item) and string.format(L1, "Size:", formatSize(item)) or nil)
        cell2((item.ac and item.ac ~= 0) and string.format(L2, "AC:", tostring(item.ac)) or nil)
        cell3((item.hp and item.hp ~= 0) and string.format(L3, "HP:", tostring(item.hp)) or nil)
        rowEnd()
        -- Row: Weight, Mana, End
        local wStr = (item.weight and item.weight ~= 0) and (item.weight >= 10 and string.format("%.1f", item.weight / 10) or tostring(item.weight)) or nil
        cell1(wStr and string.format(L1, "Weight:", wStr) or nil)
        cell2((item.mana and item.mana ~= 0) and string.format(L2, "Mana:", tostring(item.mana)) or nil)
        cell3((item.endurance and item.endurance ~= 0) and string.format(L3, "End:", tostring(item.endurance)) or nil)
        rowEnd()
        -- Row: Req Level, Rec Level, Dmg/Delay
        cell1((item.requiredLevel and item.requiredLevel ~= 0) and string.format(L1, "Req Level:", tostring(item.requiredLevel)) or nil)
        cell2((item.recommendedLevel and item.recommendedLevel ~= 0) and string.format(L2, "Rec Level:", tostring(item.recommendedLevel)) or nil)
        cell3((item.damage and item.damage ~= 0) and string.format(L3, "Dmg:", tostring(item.damage)) or (item.itemDelay and item.itemDelay ~= 0) and string.format(L3, "Delay:", tostring(item.itemDelay)) or nil)
        rowEnd()
        cell1((item.dmgBonus and item.dmgBonus ~= 0) and string.format(L1, "Dmg Bon:", tostring(item.dmgBonus) .. (item.dmgBonusType and item.dmgBonusType ~= "" and item.dmgBonusType ~= "None" and (" " .. item.dmgBonusType) or "")) or nil)
        cell2(nil)
        cell3(nil)
        rowEnd()
        -- Skill, Instrument, Haste, Charges
        cell1((item.type and item.type ~= "") and string.format(L1, "Skill:", tostring(item.type)) or (item.instrumentType and item.instrumentType ~= "") and string.format(L1, "Instrument:", tostring(item.instrumentType) .. ((item.instrumentMod and item.instrumentMod ~= 0) and (" " .. tostring(item.instrumentMod)) or "")) or nil)
        cell2((item.haste and item.haste ~= 0) and string.format(L2, "Haste:", tostring(item.haste) .. "%") or nil)
        cell3((item.charges and item.charges ~= 0) and string.format(L3, "Charges:", (item.charges == -1) and "Unlimited" or tostring(item.charges)) or nil)
        rowEnd()
        cell1((item.range and item.range ~= 0) and string.format(L1, "Range:", tostring(item.range)) or nil)
        cell2((item.skillModValue and item.skillModValue ~= 0) and string.format(L2, "Skill Mod:", (item.skillModMax and item.skillModMax ~= 0) and (tostring(item.skillModValue) .. "/" .. tostring(item.skillModMax)) or tostring(item.skillModValue)) or nil)
        cell3((item.baneDMG and item.baneDMG ~= 0) and string.format(L3, "Bane:", tostring(item.baneDMG) .. (item.baneDMGType and item.baneDMGType ~= "" and (" " .. item.baneDMGType) or "")) or nil)
        rowEnd()
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
    local combat = {
        cl(item.attack, "Attack"),
        cl(item.hpRegen, "HP Regen"),
        cl(item.manaRegen, "Mana Regen"),
        cl(item.enduranceRegen, "End Regen"),
        cl(item.spellShield, "Spell Shield"),
        cl(item.shielding, "Shielding"),
        cl(item.damageShield, "Dmg Shield"),
        cl(item.dotShielding, "DoT Shield"),
        cl(item.damageShieldMitigation, "Dmg Shld Mit"),
        cl(item.avoidance, "Avoidance"),
        cl(item.accuracy, "Accuracy"),
        cl(item.stunResist, "Stun Resist"),
        cl(item.spellDamage, "Spell Dmg"),
        cl(item.clairvoyance, "Clairvoyance"),
        cl(item.haste, "Haste"),
        cl(item.strikeThrough, "Strike Through"),
        cl(item.combatEffects, "Combat Effects"),
        cl(item.healAmount, "Heal Amt"),
        cl(item.luck, "Luck"),
        cl(item.purity, "Purity"),
    }
    local hasAnyStat = false
    for _, v in ipairs(attrs) do if v then hasAnyStat = true break end end
    for _, v in ipairs(resists) do if v then hasAnyStat = true break end end
    for _, v in ipairs(combat) do if v then hasAnyStat = true break end end
    if hasAnyStat then
        ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "All Stats")
        ImGui.Spacing()
        ImGui.Columns(3, "##StatsCols", false)
        ImGui.SetColumnWidth(0, colW1)
        ImGui.SetColumnWidth(1, colW2)
        ImGui.SetColumnWidth(2, colW3)
        -- ImGui Columns places widgets row-by-row (col0, col1, col2, then next row).
        -- Output row-by-row so column 0 = attrs, column 1 = resists, column 2 = combat.
        local maxRows = math.max(#attrs, #resists, #combat)
        for row = 1, maxRows do
            if attrs[row] then ImGui.Text(attrs[row]) end
            ImGui.NextColumn()
            if resists[row] then ImGui.Text(resists[row]) end
            ImGui.NextColumn()
            if combat[row] then ImGui.Text(combat[row]) end
            ImGui.NextColumn()
        end
        ImGui.Columns(1)
        ImGui.Spacing()
    end

    -- ---- Item effects: in-game style "Effect: SpellName (Worn)" / "Focus Effect: SpellName" ----
    if ctx and ctx.getItemSpellId and ctx.getSpellName then
        local effectLabels = { Clicky = "Clicky", Worn = "Worn", Proc = "Proc", Focus = "Focus", Spell = "Spell" }
        local focusLabel = "Focus"
        local effects = {}
        for _, key in ipairs({"Clicky", "Worn", "Proc", "Focus", "Spell"}) do
            local id = ctx.getItemSpellId(item, key)
            if id and id > 0 then
                local spellName = ctx.getSpellName(id)
                if spellName and spellName ~= "" then
                    local desc = (ctx.getSpellDescription and ctx.getSpellDescription(id)) or ""
                    effects[#effects + 1] = { key = key, spellName = spellName, desc = desc }
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
