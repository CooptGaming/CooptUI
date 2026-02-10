--[[
    ItemUI - Character Stats Panel Component
    Renders the left-side character stats panel with HP/MP/EN, AC/ATK, stats, resists, money, AA scripts.
    Part of CoopUI — EverQuest EMU Companion
--]]

local mq = require('mq')
require('ImGui')

local M = {}
local deps  -- set by init()

function M.init(d)
    deps = d
end

-- ============================================================================
-- Class display: 3-letter abbreviation + optional server subclasses
-- ============================================================================

local CLASS_TO_ABBREV = {
    ["warrior"] = "WAR", ["cleric"] = "CLR", ["paladin"] = "PAL", ["ranger"] = "RNG",
    ["shadow knight"] = "SHD", ["druid"] = "DRU", ["monk"] = "MNK", ["rogue"] = "ROG",
    ["bard"] = "BRD", ["shaman"] = "SHM", ["necromancer"] = "NEC", ["wizard"] = "WIZ",
    ["magician"] = "MAG", ["enchanter"] = "ENC", ["beastlord"] = "BST", ["berserker"] = "BER",
}

--- Return 3-letter class abbreviation for display; nil if unknown.
local function classAbbrev(className)
    if not className or className == "" then return nil end
    local key = tostring(className):lower():gsub("^%s+", ""):gsub("%s+$", "")
    return CLASS_TO_ABBREV[key]
end

--- Build primary + optional subclass string. Tries server-specific TLOs for tagged/alt classes.
local function getClassDisplayString(Me)
    local primary = Me.Class and Me.Class()
    local abbrev = classAbbrev(primary)
    local primaryStr = abbrev and abbrev or (tostring(primary or "?"):gsub("^%s+", ""):gsub("%s+$", ""))
    local subclasses = {}
    local seen = {}
    -- Server may expose tagged/alt classes via custom TLOs; try common names without failing
    for _, tloName in ipairs({ "AltClass", "SecondaryClass", "SubClass", "TaggedClasses", "ExtraClasses" }) do
        local fn = Me[tloName]
        if type(fn) == "function" then
            local ok, val = pcall(function() return fn() end)
            if ok and val and tostring(val):len() > 0 then
                local s = tostring(val):lower():gsub("^%s+", ""):gsub("%s+$", "")
                if s ~= "" then
                    for part in s:gmatch("[^,;|]+") do
                        part = part:gsub("^%s+", ""):gsub("%s+$", "")
                        if part ~= "" then
                            local a = classAbbrev(part) or part:sub(1, 3):upper()
                            if a and a ~= primaryStr and not seen[a] then
                                seen[a] = true
                                subclasses[#subclasses + 1] = a
                            end
                        end
                    end
                end
            end
        end
    end
    if #subclasses > 0 then
        return primaryStr .. " (" .. table.concat(subclasses, ", ") .. ")"
    end
    return primaryStr
end

-- ============================================================================
-- AA Script Counting (Lost Memories + Planar Power)
-- ============================================================================

local SCRIPT_AA_RARITIES = {
    { label = "Norm", tierKey = "normal", aa = 1 },
    { label = "Enh", tierKey = "enhanced", aa = 2 },
    { label = "Rare", tierKey = "rare", aa = 3 },
    { label = "Epic", tierKey = "epic", aa = 4 },
    { label = "Leg", tierKey = "legendary", aa = 5 },
}
local SCRIPT_AA_FULL_NAMES = {
    "Script of Lost Memories", "Enhanced Script of Lost Memories", "Rare Script of Lost Memories", "Epic Script of Lost Memories", "Legendary Script of Lost Memories",
    "Script of Planar Power", "Enhanced Script of Planar Power", "Rare Script of Planar Power", "Epic Script of Planar Power", "Legendary Script of Planar Power",
}
local SCRIPT_AA_BY_NAME = {}
do
    local aaByTier = { normal = 1, enhanced = 2, rare = 3, epic = 4, legendary = 5 }
    for _, name in ipairs(SCRIPT_AA_FULL_NAMES) do
        local tier = "normal"
        if name:find("^Enhanced ") then tier = "enhanced"
        elseif name:find("^Rare ") then tier = "rare"
        elseif name:find("^Epic ") then tier = "epic"
        elseif name:find("^Legendary ") then tier = "legendary"
        end
        SCRIPT_AA_BY_NAME[name] = aaByTier[tier]
    end
end

local function getScriptCountsFromInventory(items)
    local byTier = { normal = 0, enhanced = 0, rare = 0, epic = 0, legendary = 0 }
    local totalAA = 0
    for _, it in ipairs(items or {}) do
        local name = it.name or ""
        local aa = SCRIPT_AA_BY_NAME[name]
        if aa then
            local stack = (it.stackSize and it.stackSize > 0) and it.stackSize or 1
            local tier = "normal"
            if name:find("^Enhanced ") then tier = "enhanced"
            elseif name:find("^Rare ") then tier = "rare"
            elseif name:find("^Epic ") then tier = "epic"
            elseif name:find("^Legendary ") then tier = "legendary"
            end
            byTier[tier] = byTier[tier] + stack
            totalAA = totalAA + aa * stack
        end
    end
    local rows = {}
    for _, r in ipairs(SCRIPT_AA_RARITIES) do
        local count = byTier[r.tierKey] or 0
        rows[#rows + 1] = { label = r.label, count = count, aa = r.aa * count }
    end
    return { rows = rows, totalAA = totalAA }
end

-- ============================================================================
-- Render
-- ============================================================================

local function getWindowText(path)
    local success, text = pcall(function()
        local wnd = mq.TLO and mq.TLO.Window and mq.TLO.Window(path)
        if wnd and wnd.Open and wnd.Open() then
            return wnd.Text and wnd.Text()
        end
        return nil
    end)
    return success and text or nil
end

function M.render()
    local Me = mq.TLO and mq.TLO.Me
    if not Me then
        -- TLO.Me can be nil during zone transitions / loading
        return
    end

    local displayedAC = getWindowText("InventoryWindow/IW_StatPage/IWS_CurrentArmorClass") or
                        getWindowText("InventoryWindow/IW_ACNumber") or "N/A"
    local displayedATK = getWindowText("InventoryWindow/IW_StatPage/IWS_CurrentAttack") or
                         getWindowText("InventoryWindow/IW_ATKNumber") or "N/A"
    local displayedWeight = getWindowText("InventoryWindow/IW_StatPage/IWS_CurrentWeight") or
                            getWindowText("InventoryWindow/IW_CurrentWeight") or "N/A"
    local displayedMaxWeight = getWindowText("InventoryWindow/IW_StatPage/IWS_MaxWeight") or
                               getWindowText("InventoryWindow/IW_MaxWeight") or "N/A"

    local hp = Me.CurrentHPs() or 0
    local maxHP = Me.MaxHPs() or 0
    local mana = Me.CurrentMana() or 0
    local maxMana = Me.MaxMana() or 0
    local endur = Me.CurrentEndurance() or 0
    local maxEndur = Me.MaxEndurance() or 0
    local exp = Me.PctExp() or 0
    local aaPointsTotal = Me.AAPointsTotal() or 0
    local haste = Me.Haste() or 0
    local isMoving = Me.Moving() or false
    local movementSpeed = isMoving and math.floor((Me.Speed() or 0) + 0.5) or 0

    local platinum = Me.Platinum() or 0
    local gold = Me.Gold() or 0
    local silver = Me.Silver() or 0
    local copper = Me.Copper() or 0

    local str = Me.STR() or 0
    local sta = Me.STA() or 0
    local int = Me.INT() or 0
    local wis = Me.WIS() or 0
    local dex = Me.DEX() or 0
    local cha = Me.CHA() or 0

    local magicResist = Me.svMagic() or 0
    local fireResist = Me.svFire() or 0
    local coldResist = Me.svCold() or 0
    local diseaseResist = Me.svDisease() or 0
    local poisonResist = Me.svPoison() or 0
    local corruptionResist = Me.svCorruption() or 0

    ImGui.BeginChild("CharacterStats", ImVec2(180, -deps.FOOTER_HEIGHT), true, ImGuiWindowFlags.NoScrollbar)

    ImGui.SetWindowFontScale(0.95)

    local playerName = (Me.Name and Me.Name()) and Me.Name() or "?"
    local playerLevel = (Me.Level and Me.Level()) and Me.Level() or 0
    local classStr = getClassDisplayString(Me)
    local headerText = string.format("%s (%s) %s", playerName, playerLevel, classStr)
    ImGui.TextColored(ImVec4(0.4, 0.8, 1, 1), headerText)
    ImGui.Separator()

    ImGui.TextColored(ImVec4(0.9, 0.3, 0.3, 1), "HP:")
    ImGui.SameLine(50)
    ImGui.Text(string.format("%d / %d", hp, maxHP))

    ImGui.TextColored(ImVec4(0.3, 0.5, 0.9, 1), "MP:")
    ImGui.SameLine(50)
    ImGui.Text(string.format("%d / %d", mana, maxMana))

    ImGui.TextColored(ImVec4(0.5, 0.7, 0.3, 1), "EN:")
    ImGui.SameLine(50)
    ImGui.Text(string.format("%d / %d", endur, maxEndur))

    ImGui.TextColored(ImVec4(0.8, 0.6, 0.2, 1), "AC:")
    ImGui.SameLine(50)
    ImGui.Text(tostring(displayedAC))

    ImGui.TextColored(ImVec4(0.8, 0.6, 0.2, 1), "ATK:")
    ImGui.SameLine(50)
    ImGui.Text(tostring(displayedATK))

    ImGui.TextColored(ImVec4(0.6, 0.8, 0.6, 1), "Haste:")
    ImGui.SameLine(50)
    ImGui.Text(string.format("%d%%", haste))

    ImGui.TextColored(ImVec4(0.6, 0.8, 0.6, 1), "Speed:")
    ImGui.SameLine(50)
    ImGui.Text(string.format("%d%%", movementSpeed))

    ImGui.Separator()

    ImGui.Text("EXP:")
    ImGui.SameLine(50)
    ImGui.Text(string.format("%.1f%%", exp))

    ImGui.Text("AAs:")
    ImGui.SameLine(50)
    ImGui.Text(tostring(aaPointsTotal))

    ImGui.Separator()

    ImGui.TextColored(ImVec4(0.85, 0.85, 0.7, 1), "Stats:")
    ImGui.Text("STR:")
    ImGui.SameLine(50)
    ImGui.Text(tostring(str))
    ImGui.SameLine(90)
    ImGui.Text("STA:")
    ImGui.SameLine(130)
    ImGui.Text(tostring(sta))

    ImGui.Text("INT:")
    ImGui.SameLine(50)
    ImGui.Text(tostring(int))
    ImGui.SameLine(90)
    ImGui.Text("WIS:")
    ImGui.SameLine(130)
    ImGui.Text(tostring(wis))

    ImGui.Text("DEX:")
    ImGui.SameLine(50)
    ImGui.Text(tostring(dex))
    ImGui.SameLine(90)
    ImGui.Text("CHA:")
    ImGui.SameLine(130)
    ImGui.Text(tostring(cha))

    ImGui.Separator()

    ImGui.TextColored(ImVec4(0.85, 0.85, 0.7, 1), "Resist:")
    ImGui.Text("Poison:")
    ImGui.SameLine(65)
    ImGui.Text(tostring(poisonResist))
    ImGui.SameLine(95)
    ImGui.Text("Magic:")
    ImGui.SameLine(155)
    ImGui.Text(tostring(magicResist))

    ImGui.Text("Fire:")
    ImGui.SameLine(65)
    ImGui.Text(tostring(fireResist))
    ImGui.SameLine(95)
    ImGui.Text("Disease:")
    ImGui.SameLine(155)
    ImGui.Text(tostring(diseaseResist))

    ImGui.Text("Corrupt:")
    ImGui.SameLine(65)
    ImGui.Text(tostring(corruptionResist))
    ImGui.SameLine(95)
    ImGui.Text("Cold:")
    ImGui.SameLine(155)
    ImGui.Text(tostring(coldResist))

    ImGui.Separator()

    ImGui.TextColored(ImVec4(0.85, 0.85, 0.7, 1), "WEIGHT:")
    ImGui.Text(string.format("%s / %s", tostring(displayedWeight), tostring(displayedMaxWeight)))

    ImGui.Separator()

    ImGui.TextColored(ImVec4(0.85, 0.85, 0.7, 1), "Money:")
    local moneyStr = ""
    if platinum > 0 then
        moneyStr = moneyStr .. string.format("%dp ", platinum)
    end
    if gold > 0 or platinum > 0 then
        moneyStr = moneyStr .. string.format("%dg ", gold)
    end
    if silver > 0 or gold > 0 or platinum > 0 then
        moneyStr = moneyStr .. string.format("%ds ", silver)
    end
    moneyStr = moneyStr .. string.format("%dc", copper)
    ImGui.Text(moneyStr)

    -- AA Scripts (Lost/Planar)
    ImGui.Separator()
    ImGui.TextColored(ImVec4(0.85, 0.85, 0.7, 1), "Scripts:")
    ImGui.SameLine()
    if ImGui.SmallButton("Pop-out Tracker") then mq.cmd('/scripttracker show') end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Open AA Script Tracker window (run /lua run scripttracker first if needed)"); ImGui.EndTooltip() end
    local scriptData = getScriptCountsFromInventory(deps.inventoryItems)
    ImGui.SetWindowFontScale(0.85)
    ImGui.Text("")
    ImGui.SameLine(48)
    ImGui.TextColored(ImVec4(0.6, 0.6, 0.6, 1), "Cnt")
    ImGui.SameLine(78)
    ImGui.TextColored(ImVec4(0.6, 0.6, 0.6, 1), "AA")
    for _, row in ipairs(scriptData.rows) do
        ImGui.Text(row.label .. ":")
        ImGui.SameLine(48)
        ImGui.Text(tostring(row.count))
        ImGui.SameLine(78)
        ImGui.Text(tostring(row.aa))
    end
    ImGui.TextColored(ImVec4(0.9, 0.85, 0.4, 1), "Total: " .. tostring(scriptData.totalAA) .. " AA")
    ImGui.SetWindowFontScale(0.95)

    ImGui.SetWindowFontScale(1.0)

    ImGui.EndChild()
end

return M
