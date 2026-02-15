--[[
    ItemUI - Item Helper Utilities
    Status messages, currency formatting, spell caching, item building.
    Part of CoOpt UI — EverQuest EMU Companion
--]]

local mq = require('mq')
local Cache = require('itemui.core.cache')

local M = {}
local deps  -- set by init()

function M.init(d)
    deps = d
end

-- ============================================================================
-- Lazy-loaded stat fields: deferred from scan to first tooltip/summary access.
-- First access to any stat field triggers batch-loading ALL stats via TLO.
-- ============================================================================

--- Mapping: Lua field name → TLO accessor name
local STAT_TLO_MAP = {
    -- Primary stats
    ac = 'AC', hp = 'HP', mana = 'Mana', endurance = 'Endurance',
    str = 'STR', sta = 'STA', agi = 'AGI', dex = 'DEX',
    int = 'INT', wis = 'WIS', cha = 'CHA',
    -- Combat stats
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
    -- Heroic stats
    heroicSTR = 'HeroicSTR', heroicSTA = 'HeroicSTA', heroicAGI = 'HeroicAGI',
    heroicDEX = 'HeroicDEX', heroicINT = 'HeroicINT', heroicWIS = 'HeroicWIS',
    heroicCHA = 'HeroicCHA',
    -- Resistances (base)
    svMagic = 'svMagic', svFire = 'svFire', svCold = 'svCold',
    svPoison = 'svPoison', svDisease = 'svDisease', svCorruption = 'svCorruption',
    -- Resistances (heroic)
    heroicSvMagic = 'HeroicSvMagic', heroicSvFire = 'HeroicSvFire',
    heroicSvCold = 'HeroicSvCold', heroicSvDisease = 'HeroicSvDisease',
    heroicSvPoison = 'HeroicSvPoison', heroicSvCorruption = 'HeroicSvCorruption',
    -- Item info (tooltip-only)
    charges = 'Charges', range = 'Range',
    skillModValue = 'SkillModValue', skillModMax = 'SkillModMax',
    baneDMG = 'BaneDMG', baneDMGType = 'BaneDMGType',
    deity = 'Deity', luck = 'Luck', purity = 'Purity',
}

--- Ordered list of all stat field names (for batch iteration)
local STAT_FIELDS = {}
for field, _ in pairs(STAT_TLO_MAP) do STAT_FIELDS[#STAT_FIELDS + 1] = field end

--- Fast lookup: is this key a lazy stat field?
local STAT_FIELDS_SET = {}
for _, f in ipairs(STAT_FIELDS) do STAT_FIELDS_SET[f] = true end

--- String-type stat fields (default to "" not 0)
local STAT_STRING_FIELDS = { deity = true, baneDMGType = true, dmgBonusType = true }

--- Get item TLO for the given location. source = "bank" uses Me.Bank(bag).Item(slot), else Me.Inventory("pack"..bag).Item(slot).
--- Bag and slot are 1-based (same as stored on item tables). Returns nil if TLO not available.
function M.getItemTLO(bag, slot, source)
    if source == "bank" then
        local bn = mq.TLO and mq.TLO.Me and mq.TLO.Me.Bank and mq.TLO.Me.Bank(bag or 0)
        if not bn then return nil end
        return bn.Item and bn.Item(slot or 0)
    else
        local pack = mq.TLO and mq.TLO.Me and mq.TLO.Me.Inventory and mq.TLO.Me.Inventory("pack" .. (bag or 0))
        if not pack then return nil end
        return pack.Item and pack.Item(slot or 0)
    end
end

--- Set in-UI status (Keep/Junk, moves, sell). Safe: trims, coerces to string, truncates.
function M.setStatusMessage(msg)
    if msg == nil then return end
    msg = (type(msg) == "string" and msg:match("^%s*(.-)%s*$")) or tostring(msg)
    if msg == "" then return end
    if #msg > deps.C.STATUS_MSG_MAX_LEN then
        msg = msg:sub(1, deps.C.STATUS_MSG_MAX_LEN - 3) .. "..."
    end
    deps.uiState.statusMessage = msg
    deps.uiState.statusMessageTime = mq.gettime()
end

--- Format copper value to readable currency string
function M.formatCurrency(copper)
    if not copper or copper == 0 then return "0c" end
    copper = math.floor(copper)

    local plat = math.floor(copper / 1000)
    local gold = math.floor((copper % 1000) / 100)
    local silver = math.floor((copper % 100) / 10)
    local c = copper % 10

    local parts = {}
    if plat > 0 then table.insert(parts, string.format("%dp", plat)) end
    if gold > 0 then table.insert(parts, string.format("%dg", gold)) end
    if silver > 0 then table.insert(parts, string.format("%ds", silver)) end
    if c > 0 or #parts == 0 then table.insert(parts, string.format("%dc", c)) end

    return table.concat(parts, " ")
end

function M.getSpellName(id)
    if not id or id <= 0 then return nil end
    local cacheKey = 'spell:name:' .. id
    local name = Cache.get(cacheKey)
    if name ~= nil then return name end
    local s = (mq.TLO and mq.TLO.Spell and mq.TLO.Spell(id)) or nil
    name = s and s.Name and s.Name() or "Unknown"
    Cache.set(cacheKey, name, { tier = 'L2' })
    return name
end

function M.getSpellDescription(id)
    if not id or id <= 0 then return nil end
    local cacheKey = 'spell:desc:' .. id
    local desc = Cache.get(cacheKey)
    if desc ~= nil then return desc end
    local s = (mq.TLO and mq.TLO.Spell and mq.TLO.Spell(id)) or nil
    desc = s and s.Description and s.Description() or ""
    Cache.set(cacheKey, desc, { tier = 'L2' })
    return desc
end

--- Spell cast time in seconds (for clicky display). Returns nil if not available.
--- Normalizes raw TLO value (may be ms or tenths) to seconds to match in-game display.
function M.getSpellCastTime(id)
    if not id or id <= 0 then return nil end
    local cacheKey = 'spell:casttime:' .. id
    local val = Cache.get(cacheKey)
    if val ~= nil then return val end
    local s = (mq.TLO and mq.TLO.Spell and mq.TLO.Spell(id)) or nil
    if not s then return nil end
    local ct = s.CastTime and s.CastTime()
    if ct == nil then return nil end
    local raw = tonumber(ct)
    if not raw then return nil end
    local sec = raw
    if raw >= 1000 then sec = raw / 1000
    elseif raw >= 10 then sec = raw / 10
    end
    Cache.set(cacheKey, sec, { tier = 'L2' })
    return sec
end

--- Spell recast time in seconds (for clicky display). Returns nil if not available.
function M.getSpellRecastTime(id)
    if not id or id <= 0 then return nil end
    local cacheKey = 'spell:recasttime:' .. id
    local val = Cache.get(cacheKey)
    if val ~= nil then return val end
    local s = (mq.TLO and mq.TLO.Spell and mq.TLO.Spell(id)) or nil
    if not s or not s.RecastTime then return nil end
    local rt = s.RecastTime()
    local sec = tonumber(rt)
    if sec then Cache.set(cacheKey, sec, { tier = 'L2' }); return sec end
    return nil
end

--- Build a compact stats summary string for an item (AC, HP, mana, attributes, etc.).
function M.getItemStatsSummary(item)
    if not item then return "" end
    local parts = {}
    if (item.ac or 0) ~= 0 then parts[#parts + 1] = string.format("%d AC", item.ac) end
    if (item.hp or 0) ~= 0 then parts[#parts + 1] = string.format("%d HP", item.hp) end
    if (item.mana or 0) ~= 0 then parts[#parts + 1] = string.format("%d Mana", item.mana) end
    if (item.endurance or 0) ~= 0 then parts[#parts + 1] = string.format("%d End", item.endurance) end
    local function addStat(abbr, val) if (val or 0) ~= 0 then parts[#parts + 1] = string.format("%d %s", val, abbr) end end
    addStat("STR", item.str); addStat("STA", item.sta); addStat("AGI", item.agi); addStat("DEX", item.dex)
    addStat("INT", item.int); addStat("WIS", item.wis); addStat("CHA", item.cha)
    if (item.attack or 0) ~= 0 then parts[#parts + 1] = string.format("%d Atk", item.attack) end
    if (item.accuracy or 0) ~= 0 then parts[#parts + 1] = string.format("%d Acc", item.accuracy) end
    if (item.avoidance or 0) ~= 0 then parts[#parts + 1] = string.format("%d Avoid", item.avoidance) end
    if (item.shielding or 0) ~= 0 then parts[#parts + 1] = string.format("%d Shield", item.shielding) end
    if (item.haste or 0) ~= 0 then parts[#parts + 1] = string.format("%d Haste", item.haste) end
    if (item.spellDamage or 0) ~= 0 then parts[#parts + 1] = string.format("%d SD", item.spellDamage) end
    if (item.strikeThrough or 0) ~= 0 then parts[#parts + 1] = string.format("%d ST", item.strikeThrough) end
    if (item.damageShield or 0) ~= 0 then parts[#parts + 1] = string.format("%d DS", item.damageShield) end
    if (item.combatEffects or 0) ~= 0 then parts[#parts + 1] = string.format("%d CE", item.combatEffects) end
    if (item.hpRegen or 0) ~= 0 then parts[#parts + 1] = string.format("%d HP Regen", item.hpRegen) end
    if (item.manaRegen or 0) ~= 0 then parts[#parts + 1] = string.format("%d Mana Regen", item.manaRegen) end
    addStat("HSTR", item.heroicSTR); addStat("HSTA", item.heroicSTA); addStat("HAGI", item.heroicAGI)
    addStat("HDEX", item.heroicDEX); addStat("HINT", item.heroicINT); addStat("HWIS", item.heroicWIS); addStat("HCHA", item.heroicCHA)
    if (item.svMagic or 0) ~= 0 then parts[#parts + 1] = string.format("%d SvM", item.svMagic) end
    if (item.svFire or 0) ~= 0 then parts[#parts + 1] = string.format("%d SvF", item.svFire) end
    if (item.svCold or 0) ~= 0 then parts[#parts + 1] = string.format("%d SvC", item.svCold) end
    if (item.svPoison or 0) ~= 0 then parts[#parts + 1] = string.format("%d SvP", item.svPoison) end
    if (item.svDisease or 0) ~= 0 then parts[#parts + 1] = string.format("%d SvD", item.svDisease) end
    if (item.svCorruption or 0) ~= 0 then parts[#parts + 1] = string.format("%d SvCorr", item.svCorruption) end
    return table.concat(parts, ", ")
end

--- Lazy spell ID fetch: defers 5 TLO calls per item from scan to first display. Uses item.source for bank vs inv.
function M.getItemSpellId(item, prop)
    if not item or not prop then return 0 end
    local key = prop:lower()
    if item[key] ~= nil then return item[key] or 0 end
    local src = rawget(item, "source") or "inv"
    local slotItem = M.getItemTLO(item.bag, item.slot, src)
    if not slotItem then item[key] = 0; return 0 end
    local spellObj = slotItem and slotItem[prop]
    if not spellObj then item[key] = 0; return 0 end
    local id = 0
    if spellObj.SpellID then id = spellObj.SpellID() or 0 end
    if (not id or id == 0) and spellObj.Spell and spellObj.Spell.ID then id = spellObj.Spell.ID() or 0 end
    item[key] = (id and id > 0) and id or 0
    return item[key]
end

--- TimerReady cache: TTL 1.5s (cooldowns in seconds; reduces TLO calls ~33%). Optional source "bank" | "inv" (default inv).
function M.getTimerReady(bag, slot, source)
    if not bag or not slot then return 0 end
    source = source or "inv"
    local key = source .. "_" .. bag .. "_" .. slot
    local now = mq.gettime()
    local entry = deps.perfCache.timerReadyCache[key]
    if entry and (now - entry.at) < deps.C.TIMER_READY_CACHE_TTL_MS then
        return entry.ready or 0
    end
    local itemTLO = M.getItemTLO(bag, slot, source)
    local ready = (itemTLO and itemTLO.TimerReady and itemTLO.TimerReady()) or 0
    deps.perfCache.timerReadyCache[key] = { ready = ready, at = now }
    return ready
end

-- Slot index (0-22) to display name; WornSlots is count, WornSlot(N) returns Nth slot index.
local SLOT_DISPLAY_NAMES = {
    [0] = "Charm", [1] = "Ear", [2] = "Head", [3] = "Face", [4] = "Ear",
    [5] = "Neck", [6] = "Shoulder", [7] = "Arms", [8] = "Back", [9] = "Wrist",
    [10] = "Wrist", [11] = "Ranged", [12] = "Hands", [13] = "Primary", [14] = "Secondary",
    [15] = "Ring", [16] = "Ring", [17] = "Chest", [18] = "Legs", [19] = "Feet",
    [20] = "Waist", [21] = "Power", [22] = "Ammo",
}
local function slotIndexToDisplayName(s)
    if s == nil or s == "" then return nil end
    local n = tonumber(s)
    if n ~= nil and SLOT_DISPLAY_NAMES[n] then return SLOT_DISPLAY_NAMES[n] end
    local str = tostring(s):lower():gsub("^%l", string.upper)
    return (str ~= "") and str or nil
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

--- Extract core item properties from MQ item TLO (per iteminfo.mac).
--- Stat/combat/resistance fields are lazy-loaded on first access via metatable __index.
--- wornSlots and augSlots are also lazy-loaded to reduce scan TLO cost (WornSlot N + AugSlot1-6 per item).
--- This reduces scan from ~76 to ~30 TLO calls per item; stats/wornSlots/augSlots load on first use.
--- Optional 4th arg source: "inv" (default) or "bank"; stored on item and used by __index to resolve TLO.
function M.buildItemFromMQ(item, bag, slot, source)
    if not item or not item.ID or not item.ID() or item.ID() == 0 then return nil end
    local iv = item.Value and item.Value() or 0
    local ss = item.Stack and item.Stack() or 1
    if ss < 1 then ss = 1 end
    local stackSizeMax = item.StackSize and item.StackSize() or ss
    local clsStr, raceStr = M.getClassRaceStringsFromTLO(item)
    local base = {
        bag = bag, slot = slot,
        source = source or "inv",
        name = item.Name and item.Name() or "",
        id = item.ID and item.ID() or 0,
        value = iv, totalValue = iv * ss, stackSize = ss, stackSizeMax = stackSizeMax,
        type = item.Type and item.Type() or "",
        weight = item.Weight and item.Weight() or 0,
        icon = item.Icon and item.Icon() or 0,
        tribute = item.Tribute and item.Tribute() or 0,
        size = item.Size and item.Size() or 0,
        sizeCapacity = item.SizeCapacity and item.SizeCapacity() or 0,
        container = item.Container and item.Container() or 0,
        nodrop = item.NoDrop and item.NoDrop() or false,
        notrade = item.NoTrade and item.NoTrade() or false,
        norent = item.NoRent and item.NoRent() or false,
        lore = item.Lore and item.Lore() or false,
        magic = item.Magic and item.Magic() or false,
        attuneable = item.Attuneable and item.Attuneable() or false,
        heirloom = item.Heirloom and item.Heirloom() or false,
        prestige = item.Prestige and item.Prestige() or false,
        collectible = item.Collectible and item.Collectible() or false,
        quest = item.Quest and item.Quest() or false,
        tradeskills = item.Tradeskills and item.Tradeskills() or false,
        class = clsStr,
        race = raceStr,
        requiredLevel = item.RequiredLevel and item.RequiredLevel() or 0,
        recommendedLevel = item.RecommendedLevel and item.RecommendedLevel() or 0,
        instrumentType = item.InstrumentType and item.InstrumentType() or "",
        instrumentMod = item.InstrumentMod and item.InstrumentMod() or 0,
    }
    -- Lazy-load: wornSlots, augSlots, and stat fields on first access (use getItemTLO so bank uses Me.Bank)
    setmetatable(base, { __index = function(t, k)
        local b, s = t.bag, t.slot
        local src = rawget(t, "source") or "inv"
        local it = M.getItemTLO(b, s, src)
        if k == "wornSlots" then
            local v = (it and M.getWornSlotsStringFromTLO(it)) or ""
            if not it or not it.ID or it.ID() == 0 then rawset(t, "_tlo_unavailable", true) end
            rawset(t, "wornSlots", v)
            return v
        end
        if k == "augSlots" then
            local v = (it and M.getAugSlotsCountFromTLO(it)) or 0
            if not it or not it.ID or it.ID() == 0 then rawset(t, "_tlo_unavailable", true) end
            rawset(t, "augSlots", v)
            return v
        end
        if not STAT_FIELDS_SET[k] then return nil end
        -- Batch-load all stat fields from TLO (Me/Inventory can be nil during zone/load)
        if it and it.ID and it.ID() ~= 0 then
            for _, field in ipairs(STAT_FIELDS) do
                local tloName = STAT_TLO_MAP[field]
                local accessor = it[tloName]
                if accessor then
                    local val = accessor()
                    if STAT_STRING_FIELDS[field] then
                        rawset(t, field, val or "")
                    else
                        rawset(t, field, val or 0)
                    end
                else
                    rawset(t, field, STAT_STRING_FIELDS[field] and "" or 0)
                end
            end
        else
            -- Item no longer in slot (moved/sold) or TLO unavailable (e.g. bank closed); set defaults and mark unavailable
            rawset(t, "_tlo_unavailable", true)
            for _, field in ipairs(STAT_FIELDS) do
                rawset(t, field, STAT_STRING_FIELDS[field] and "" or 0)
            end
        end
        return rawget(t, k)
    end })
    return base
end

return M
