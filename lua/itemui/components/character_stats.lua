--[[
    ItemUI - Character Stats Panel Component
    Renders the left-side character stats panel with HP/MP/EN, AC/ATK, stats, resists, money, AA scripts.
    Part of CoOpt UI — EverQuest EMU Companion
--]]

local mq = require('mq')
require('ImGui')
local constants = require('itemui.constants')
local theme = require('itemui.utils.theme')

local M = {}
local deps  -- set by init()

function M.init(d)
    deps = d
end

-- ============================================================================
-- TLO Query Cache — refresh every STATS_CACHE_TTL_MS instead of every frame
-- ============================================================================

local CACHE_TTL = constants.TIMING.STATS_CACHE_TTL_MS
local cachedStats = nil
local cacheTime = 0

-- ============================================================================
-- Class display: 3-letter abbreviation + optional server subclasses
-- ============================================================================

local CLASS_TO_ABBREV = {
    ["warrior"] = "WAR", ["cleric"] = "CLR", ["paladin"] = "PAL", ["ranger"] = "RNG",
    ["shadow knight"] = "SHD", ["druid"] = "DRU", ["monk"] = "MNK", ["rogue"] = "ROG",
    ["bard"] = "BRD", ["shaman"] = "SHM", ["necromancer"] = "NEC", ["wizard"] = "WIZ",
    ["magician"] = "MAG", ["enchanter"] = "ENC", ["beastlord"] = "BST", ["berserker"] = "BER",
}

local function classAbbrev(className)
    if not className or className == "" then return nil end
    local key = tostring(className):lower():gsub("^%s+", ""):gsub("%s+$", "")
    return CLASS_TO_ABBREV[key]
end

local function getClassDisplayString(Me)
    local primary = Me.Class and Me.Class()
    local abbrev = classAbbrev(primary)
    local primaryStr = abbrev and abbrev or (tostring(primary or "?"):gsub("^%s+", ""):gsub("%s+$", ""))
    local subclasses = {}
    local seen = {}
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
    "Script of Rebirthed Memories", "Enhanced Script of Rebirthed Memories", "Rare Script of Rebirthed Memories", "Epic Script of Rebirthed Memories", "Legendary Script of Rebirthed Memories",
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
-- TLO Query + Cache
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

local function refreshStats()
    local Me = mq.TLO and mq.TLO.Me
    if not Me then return nil end

    return {
        playerName = (Me.Name and Me.Name()) or "?",
        playerLevel = (Me.Level and Me.Level()) or 0,
        classStr = getClassDisplayString(Me),
        hp = Me.CurrentHPs() or 0,
        maxHP = Me.MaxHPs() or 0,
        mana = Me.CurrentMana() or 0,
        maxMana = Me.MaxMana() or 0,
        endur = Me.CurrentEndurance() or 0,
        maxEndur = Me.MaxEndurance() or 0,
        exp = Me.PctExp() or 0,
        aaPointsTotal = Me.AAPointsTotal() or 0,
        haste = Me.Haste() or 0,
        isMoving = Me.Moving() or false,
        movementSpeed = (Me.Moving() and Me.Moving()) and math.floor((Me.Speed() or 0) + 0.5) or 0,
        platinum = Me.Platinum() or 0,
        gold = Me.Gold() or 0,
        silver = Me.Silver() or 0,
        copper = Me.Copper() or 0,
        str = Me.STR() or 0,
        sta = Me.STA() or 0,
        int = Me.INT() or 0,
        wis = Me.WIS() or 0,
        dex = Me.DEX() or 0,
        cha = Me.CHA() or 0,
        magicResist = Me.svMagic() or 0,
        fireResist = Me.svFire() or 0,
        coldResist = Me.svCold() or 0,
        diseaseResist = Me.svDisease() or 0,
        poisonResist = Me.svPoison() or 0,
        corruptionResist = Me.svCorruption() or 0,
        displayedAC = getWindowText("InventoryWindow/IW_StatPage/IWS_CurrentArmorClass") or
                      getWindowText("InventoryWindow/IW_ACNumber") or "N/A",
        displayedATK = getWindowText("InventoryWindow/IW_StatPage/IWS_CurrentAttack") or
                       getWindowText("InventoryWindow/IW_ATKNumber") or "N/A",
        displayedWeight = getWindowText("InventoryWindow/IW_StatPage/IWS_CurrentWeight") or
                          getWindowText("InventoryWindow/IW_CurrentWeight") or "N/A",
        displayedMaxWeight = getWindowText("InventoryWindow/IW_StatPage/IWS_MaxWeight") or
                             getWindowText("InventoryWindow/IW_MaxWeight") or "N/A",
    }
end

-- ============================================================================
-- Render
-- ============================================================================

function M.render()
    local now = mq.gettime()
    if not cachedStats or (now - cacheTime) > CACHE_TTL then
        cachedStats = refreshStats()
        cacheTime = now
    end

    local s = cachedStats
    if not s then return end

    local C = theme.Colors
    local tv = theme.ToVec4

    ImGui.BeginChild("CharacterStats", ImVec2(constants.UI.CHARACTER_STATS_PANEL_WIDTH, -deps.FOOTER_HEIGHT), true, ImGuiWindowFlags.NoScrollbar)

    ImGui.SetWindowFontScale(0.95)

    local headerText = string.format("%s (%s) %s", s.playerName, s.playerLevel, s.classStr)
    ImGui.TextColored(tv(C.Header), headerText)
    ImGui.Separator()

    ImGui.TextColored(tv(C.HP), "HP:")
    ImGui.SameLine(50)
    ImGui.Text(string.format("%d / %d", s.hp, s.maxHP))

    ImGui.TextColored(tv(C.MP), "MP:")
    ImGui.SameLine(50)
    ImGui.Text(string.format("%d / %d", s.mana, s.maxMana))

    ImGui.TextColored(tv(C.Endurance), "EN:")
    ImGui.SameLine(50)
    ImGui.Text(string.format("%d / %d", s.endur, s.maxEndur))

    ImGui.TextColored(tv(C.Combat), "AC:")
    ImGui.SameLine(50)
    ImGui.Text(tostring(s.displayedAC))

    ImGui.TextColored(tv(C.Combat), "ATK:")
    ImGui.SameLine(50)
    ImGui.Text(tostring(s.displayedATK))

    ImGui.TextColored(tv(C.Utility), "Haste:")
    ImGui.SameLine(50)
    ImGui.Text(string.format("%d%%", s.haste))

    ImGui.TextColored(tv(C.Utility), "Speed:")
    ImGui.SameLine(50)
    ImGui.Text(string.format("%d%%", s.movementSpeed))

    ImGui.Separator()

    ImGui.Text("EXP:")
    ImGui.SameLine(50)
    ImGui.Text(string.format("%.1f%%", s.exp))

    ImGui.Text("AAs:")
    ImGui.SameLine(50)
    ImGui.Text(tostring(s.aaPointsTotal))

    ImGui.Separator()

    ImGui.TextColored(tv(C.SectionHead), "Stats:")
    ImGui.Text("STR:")
    ImGui.SameLine(50)
    ImGui.Text(tostring(s.str))
    ImGui.SameLine(90)
    ImGui.Text("STA:")
    ImGui.SameLine(constants.UI.CHARACTER_STATS_SAMELINE_FIRST)
    ImGui.Text(tostring(s.sta))

    ImGui.Text("INT:")
    ImGui.SameLine(50)
    ImGui.Text(tostring(s.int))
    ImGui.SameLine(90)
    ImGui.Text("WIS:")
    ImGui.SameLine(constants.UI.CHARACTER_STATS_SAMELINE_FIRST)
    ImGui.Text(tostring(s.wis))

    ImGui.Text("DEX:")
    ImGui.SameLine(50)
    ImGui.Text(tostring(s.dex))
    ImGui.SameLine(90)
    ImGui.Text("CHA:")
    ImGui.SameLine(constants.UI.CHARACTER_STATS_SAMELINE_FIRST)
    ImGui.Text(tostring(s.cha))

    ImGui.Separator()

    ImGui.TextColored(tv(C.SectionHead), "Resist:")
    ImGui.Text("Poison:")
    ImGui.SameLine(65)
    ImGui.Text(tostring(s.poisonResist))
    ImGui.SameLine(95)
    ImGui.Text("Magic:")
    ImGui.SameLine(constants.UI.CHARACTER_STATS_SAMELINE_SECOND)
    ImGui.Text(tostring(s.magicResist))

    ImGui.Text("Fire:")
    ImGui.SameLine(65)
    ImGui.Text(tostring(s.fireResist))
    ImGui.SameLine(95)
    ImGui.Text("Disease:")
    ImGui.SameLine(constants.UI.CHARACTER_STATS_SAMELINE_SECOND)
    ImGui.Text(tostring(s.diseaseResist))

    ImGui.Text("Corrupt:")
    ImGui.SameLine(65)
    ImGui.Text(tostring(s.corruptionResist))
    ImGui.SameLine(95)
    ImGui.Text("Cold:")
    ImGui.SameLine(constants.UI.CHARACTER_STATS_SAMELINE_SECOND)
    ImGui.Text(tostring(s.coldResist))

    ImGui.Separator()

    ImGui.TextColored(tv(C.SectionHead), "WEIGHT:")
    ImGui.Text(string.format("%s / %s", tostring(s.displayedWeight), tostring(s.displayedMaxWeight)))

    ImGui.Separator()

    ImGui.TextColored(tv(C.SectionHead), "Money:")
    local moneyStr = ""
    if s.platinum > 0 then
        moneyStr = moneyStr .. string.format("%dp ", s.platinum)
    end
    if s.gold > 0 or s.platinum > 0 then
        moneyStr = moneyStr .. string.format("%dg ", s.gold)
    end
    if s.silver > 0 or s.gold > 0 or s.platinum > 0 then
        moneyStr = moneyStr .. string.format("%ds ", s.silver)
    end
    moneyStr = moneyStr .. string.format("%dc", s.copper)
    ImGui.Text(moneyStr)

    -- AA Scripts (Lost/Planar)
    ImGui.Separator()
    ImGui.TextColored(tv(C.SectionHead), "Scripts:")
    ImGui.SameLine()
    if ImGui.SmallButton("Pop-out Tracker") then mq.cmd('/scripttracker show') end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Open AA Script Tracker window (run /lua run scripttracker first if needed)"); ImGui.EndTooltip() end
    local scriptData = getScriptCountsFromInventory(deps.inventoryItems)
    ImGui.SetWindowFontScale(0.85)
    ImGui.Text("")
    ImGui.SameLine(48)
    ImGui.TextColored(tv(C.Muted), "Cnt")
    ImGui.SameLine(78)
    ImGui.TextColored(tv(C.Muted), "AA")
    for _, row in ipairs(scriptData.rows) do
        ImGui.Text(row.label .. ":")
        ImGui.SameLine(48)
        ImGui.Text(tostring(row.count))
        ImGui.SameLine(78)
        ImGui.Text(tostring(row.aa))
    end
    ImGui.TextColored(tv(C.Highlight), "Total: " .. tostring(scriptData.totalAA) .. " AA")
    ImGui.SetWindowFontScale(0.95)

    ImGui.SetWindowFontScale(1.0)

    ImGui.EndChild()
end

return M
