--[[
    ItemUI - Augment stat load debug script
    Emulates the exact process the bag scan/tooltip uses to load item stats from TLO.
    Run in-game:
      /lua run itemui/test_augment_stat_debug <bag> <slot>   -- same path as CoOpt UI (e.g. 1 18)
      /lua run itemui/test_augment_stat_debug cursor         -- use item on cursor (for comparison)
    Get bag/slot from CoOpt UI: "Source: Inventory | Bag N, Slot M".
    Compare: run on an augment that shows stats (e.g. Silk Cosgrove Leg Seal) then on one that
    doesn't (e.g. Barbed Dragon Bones, Jade Prism) and diff the output.
--]]

local mq = require('mq')
local itemHelpers = require('itemui.utils.item_helpers')

-- Same map as item_helpers so we emulate exact resolution order
local STAT_TLO_MAP = {
    ac = 'AC', hp = 'HP', mana = 'Mana', endurance = 'Endurance',
    str = 'STR', sta = 'STA', agi = 'AGI', dex = 'DEX',
    int = 'INT', wis = 'WIS', cha = 'CHA',
    attack = 'Attack', accuracy = 'Accuracy', avoidance = 'Avoidance',
    shielding = 'Shielding', haste = 'Haste',
    damage = 'Damage', itemDelay = 'ItemDelay',
    dmgBonus = 'DMGBonus', dmgBonusType = 'DMGBonusType',
    spellDamage = 'SpellDamage', strikeThrough = 'StrikeThrough',
    damageShield = 'DamShield', combatEffects = 'CombatEffects',
    dotShielding = 'DoTShielding', hpRegen = 'HPRegen',
    manaRegen = 'ManaRegen', enduranceRegen = 'EnduranceRegen',
    spellShield = 'SpellShield', damageShieldMitigation = 'DamageShieldMitigation',
    stunResist = 'StunResist', clairvoyance = 'Clairvoyance', healAmount = 'HealAmount',
    heroicSTR = 'HeroicSTR', heroicSTA = 'HeroicSTA', heroicAGI = 'HeroicAGI',
    heroicDEX = 'HeroicDEX', heroicINT = 'HeroicINT', heroicWIS = 'HeroicWIS',
    heroicCHA = 'HeroicCHA',
    svMagic = 'svMagic', svFire = 'svFire', svCold = 'svCold',
    svPoison = 'svPoison', svDisease = 'svDisease', svCorruption = 'svCorruption',
    heroicSvMagic = 'HeroicSvMagic', heroicSvFire = 'HeroicSvFire',
    heroicSvCold = 'HeroicSvCold', heroicSvDisease = 'HeroicSvDisease',
    heroicSvPoison = 'HeroicSvPoison', heroicSvCorruption = 'HeroicSvCorruption',
    charges = 'Charges', range = 'Range',
    skillModValue = 'SkillModValue', skillModMax = 'SkillModMax',
    baneDMG = 'BaneDMG', baneDMGType = 'BaneDMGType',
    luck = 'Luck', purity = 'Purity',
}
local STAT_FIELDS = {}
for field, _ in pairs(STAT_TLO_MAP) do STAT_FIELDS[#STAT_FIELDS + 1] = field end

local HIGHLIGHT_FIELDS = { shielding = true, damageShield = true, hpRegen = true }

local function getStatAccessor(it, tloName, fieldName)
    if not it then return nil, nil end
    local a = it[tloName]
    if a then return a, "primary" end
    local lower = tloName:lower()
    if lower ~= tloName then
        a = it[lower]
        if a then return a, "lower" end
    end
    a = it[fieldName]
    if a then return a, "field" end
    return nil, nil
end

local function safeCall(accessor)
    if not accessor then return nil, "no accessor" end
    if type(accessor) ~= "function" then
        return accessor, "ok (not fn)"
    end
    local ok, val = pcall(accessor)
    if not ok then return nil, "throw: " .. tostring(val):sub(1, 120) end
    return val, "ok"
end

local function runTest(it, tloLabel)
    if not it then
        print("[FAIL] No TLO provided")
        return
    end
    print("\n========================================")
    print("ItemUI Augment Stat Debug (same path as bag scan)")
    print("========================================")
    print("TLO: " .. (tloLabel or "?"))

    local okId, id = pcall(function() return it.ID() end)
    local okName, name = pcall(function() return it.Name and it.Name() end)
    local okType, typ = pcall(function() return it.Type and it.Type() end)
    id = okId and id or "?"
    name = (okName and name and tostring(name)) or "?"
    typ = (okType and typ and tostring(typ)) or "?"

    print(string.format("\n--- Item: ID=%s  Name=%s  Type=%s ---\n", tostring(id), name, typ))

    print("--- Stat resolution (field | TLO name | accessor source | value or error) ---")
    local nonZero = {}
    for i, field in ipairs(STAT_FIELDS) do
        local tloName = STAT_TLO_MAP[field]
        local accessor, source = getStatAccessor(it, tloName, field)
        local val, status
        if accessor then
            val, status = safeCall(accessor)
            if status == "ok" or status == "ok (not fn)" then
                local v = (val ~= nil and val ~= "") and tostring(val) or "0/empty"
                if val and val ~= 0 and val ~= "" then nonZero[#nonZero + 1] = field .. "=" .. tostring(val) end
                status = v
            end
        else
            val, status = nil, "no accessor (primary/lower/field all nil)"
        end
        local mark = HIGHLIGHT_FIELDS[field] and " ***" or ""
        print(string.format("  %3d  %-22s  %-12s  %-8s  %s%s", i, field, tloName, source or "—", tostring(status), mark))
    end

    print("\n--- Non-zero stats (what would show in All Stats) ---")
    if #nonZero == 0 then
        print("  (none)")
    else
        for _, s in ipairs(nonZero) do print("  " .. s) end
    end

    print("\n========================================")
    print("End debug")
    print("========================================\n")
end

-- Main
local args = { ... }
local it, tloLabel
if args[1] == "cursor" then
    local Cursor = mq.TLO and mq.TLO.Cursor
    if not Cursor or not Cursor.ID then
        print("[ItemUI stat debug] Cursor TLO not available.")
        return
    end
    local ok, id = pcall(function() return Cursor.ID() end)
    if not ok or not id or id == 0 then
        print("[ItemUI stat debug] No item on cursor. Put an augment on cursor and run: /lua run itemui/test_augment_stat_debug cursor")
        return
    end
    it = Cursor
    tloLabel = "Cursor (comparison only; CoOpt UI uses Inventory path)"
elseif args[1] and args[2] then
    local bag = tonumber(args[1])
    local slot = tonumber(args[2])
    if not bag or not slot then
        print("Usage: /lua run itemui/test_augment_stat_debug cursor   OR   /lua run itemui/test_augment_stat_debug <bag> <slot>")
        return
    end
    it = itemHelpers.getItemTLO(bag, slot, "inv")
    tloLabel = string.format('Me.Inventory("pack%d").Item(%d)  [inv]', bag, slot)
    if not it then
        print("[ItemUI stat debug] getItemTLO returned nil for bag=" .. tostring(bag) .. " slot=" .. tostring(slot))
        return
    end
else
    print("Usage: /lua run itemui/test_augment_stat_debug cursor")
    print("       /lua run itemui/test_augment_stat_debug <bag> <slot>")
    print("Example: /lua run itemui/test_augment_stat_debug 1 18")
    print("Get bag/slot from CoOpt UI (e.g. Source: Inventory | Bag 1, Slot 18)")
    return
end

runTest(it, tloLabel)
