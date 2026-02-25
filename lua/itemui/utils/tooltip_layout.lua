--[[
    Tooltip layout: sizing constants and row counting for item tooltips (Task 6.3 Phase B).
    Used by item_tooltip.lua to size the tooltip window and count rows for height estimation.
--]]

local M = {}

-- Sizing constants (two-column layout)
M.TOOLTIP_MIN_WIDTH = 760
M.TOOLTIP_COL_WIDTH = 380
M.TOOLTIP_LINE_HEIGHT = 18
M.TOOLTIP_PADDING = 20
M.CHARS_PER_LINE_NAME = 48
M.CHARS_PER_LINE_DESC = 52

local SIZE_NAMES = { [1] = "SMALL", [2] = "MEDIUM", [3] = "LARGE", [4] = "GIANT" }
local function formatSize(item)
    if not item or not item.size then return nil end
    return SIZE_NAMES[item.size] or tostring(item.size)
end

--- Attribute line: "Label: base" or "Label: base+heroic"
local function attrLine(base, heroic, label)
    local b, h = base or 0, heroic or 0
    if b == 0 and h == 0 then return nil end
    if h > 0 then return string.format("%s: %d+%d", label, b, h) end
    return string.format("%s: %d", label, b)
end

--- Build a compact list of only non-nil values (so row count = longest column's value count).
function M.compactCol(c)
    local t = {}
    for i = 1, 256 do if c[i] ~= nil then t[#t + 1] = c[i] end end
    return t
end
local function compactCol(c) return M.compactCol(c) end  -- for internal use

--- Row count for Item info block (same structure as render).
function M.getItemInfoRowCount(item)
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
function M.getStatRowCount(item)
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

--- Compute tooltip width and height from left/right column row counts.
function M.computeTooltipSize(leftRows, rightRows)
    local lineCount = math.max(leftRows, rightRows)
    local height = math.max(300, lineCount * M.TOOLTIP_LINE_HEIGHT + M.TOOLTIP_PADDING)
    return M.TOOLTIP_MIN_WIDTH, height
end

--- Set tooltip window size for the next BeginTooltip.
function M.beginItemTooltip(width, height)
    if ImGui.SetNextWindowSize and width and height and width > 0 and height > 0 then
        local ok = pcall(function()
            ImGui.SetNextWindowSize(ImVec2(width, height), ImGuiCond.Always)
        end)
        if not ok then
            pcall(function() ImGui.SetNextWindowSize(ImVec2(M.TOOLTIP_MIN_WIDTH, 0), ImGuiCond.Always) end)
        end
    end
    ImGui.BeginTooltip()
end

return M
