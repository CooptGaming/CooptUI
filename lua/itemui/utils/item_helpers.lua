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
    luck = 'Luck', purity = 'Purity',
}

--- Ordered list of all stat field names (for batch iteration)
local STAT_FIELDS = {}
for field, _ in pairs(STAT_TLO_MAP) do STAT_FIELDS[#STAT_FIELDS + 1] = field end

--- Fast lookup: is this key a lazy stat field?
local STAT_FIELDS_SET = {}
for _, f in ipairs(STAT_FIELDS) do STAT_FIELDS_SET[f] = true end

--- String-type stat fields (default to "" not 0)
local STAT_STRING_FIELDS = { baneDMGType = true, dmgBonusType = true }

--- Descriptive/tooltip-only fields: lazy-loaded on first access (batch) to reduce scan TLO cost.
--- Ordered list for batch iteration; string fields use "" as default.
local DESCRIPTIVE_FIELDS = {
    "tribute", "size", "sizeCapacity", "container", "stackSizeMax",
    "norent", "magic", "prestige", "tradeskills",
    "requiredLevel", "recommendedLevel", "instrumentType", "instrumentMod",
    "class", "race", "deity",
}
local DESCRIPTIVE_FIELDS_SET = {}
for _, f in ipairs(DESCRIPTIVE_FIELDS) do DESCRIPTIVE_FIELDS_SET[f] = true end
local DESCRIPTIVE_STRING_FIELDS = { class = true, race = true, deity = true, instrumentType = true }

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
        -- Equipment slots 0-22 (0-based). Try Me.Inventory(slot) first (returns item); else InvSlot(slot).Item (property or method).
        local slotIndex = tonumber(slot)
        if slotIndex == nil or slotIndex < 0 or slotIndex > 22 then return nil end
        local Me = mq.TLO and mq.TLO.Me
        if not Me or not Me.Inventory then return nil end
        -- 1) Me.Inventory(slotIndex) or Me.Inventory[slotIndex] or Me.Inventory(slotName) may return the item directly
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
        -- Some Lua bindings use Me.Inventory[slotIndex] (bracket index)
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
        -- 2) InvSlot(slotIndex): .Item may be property or method
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

--- Strip XML/STML-like tags so description text displays without raw markup. Leaves placeholder tokens (#1, @2, etc.) as-is.
function M.stripDescriptionMarkup(str)
    if not str or str == "" then return str end
    return (tostring(str):gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

--- True if string contains description placeholders: %z, #n, @n, $n or lone $.
local function hasPlaceholders(str)
    if not str or str == "" then return false end
    local s = tostring(str)
    return s:find("%%z") or s:find("#%d+") or s:find("@%d+") or s:find("$%d*")
end

--- Format spell duration (ticks, 6 sec per tick) as H:MM:SS for %z placeholder.
local function formatDurationTicks(ticks)
    local t = tonumber(ticks)
    if not t or t < 0 then return "" end
    local seconds = math.floor(t * 6)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    return string.format("%d:%02d:%02d", h, m, s)
end

--- Build substitution table for description placeholders from spell TLO. Returns table or nil on error.
--- Keys: #n, @n, $n (1-based effect index), $ (same as $1), %z (formatted duration).
--- For proc damage (Attrib 0): @n uses Max(n) when non-zero; #n uses formula 22 + spell_level*2 capped by Max when Attrib=0.
local function buildDescriptionSubstitutionTable(spell)
    if not spell then return nil end
    local t = {}
    local ok, numEffects = pcall(function()
        local n = spell.NumEffects and spell.NumEffects()
        return (n and tonumber(n)) or 0
    end)
    if not ok or not numEffects then numEffects = 0 end
    local spellLevel
    ok, spellLevel = pcall(function()
        local fn = spell.Level and spell.Level()
        return fn and tonumber(fn)
    end)
    if not ok or not spellLevel then spellLevel = 28 end
    for n = 1, numEffects do
        local attr
        ok, attr = pcall(function()
            local fn = spell.Attrib and spell.Attrib(n)
            return fn and fn()
        end)
        local attribNum = (ok and attr ~= nil) and tonumber(attr) or nil
        local b, b2, maxVal
        ok, b = pcall(function()
            local fn = spell.Base and spell.Base(n)
            return fn and fn()
        end)
        ok, b2 = pcall(function()
            local fn = spell.Base2 and spell.Base2(n)
            return fn and fn()
        end)
        ok, maxVal = pcall(function()
            local fn = spell.Max and spell.Max(n)
            return fn and fn()
        end)
        local numMax = (ok and maxVal ~= nil) and tonumber(maxVal) or nil
        -- #n: for damage/heal (Attrib 0) use formula 22 + spell_level*2 capped by Max; else Base with abs.
        local dispB
        if attribNum == 0 and numMax and numMax > 0 then
            local formulaVal = 22 + spellLevel * 2
            formulaVal = math.min(numMax, math.max(0, formulaVal))
            dispB = tostring(formulaVal)
            t["#" .. n] = dispB
        else
            local numB = tonumber(b)
            dispB = (numB ~= nil) and tostring(math.abs(numB)) or (b ~= nil and tostring(b) or "")
            t["#" .. n] = (ok and b ~= nil) and dispB or ""
        end
        -- @n and $n: use Max(n) when non-zero (proc damage), else Base2(n).
        local s2
        if numMax and numMax ~= 0 then
            s2 = tostring(math.abs(numMax))
        else
            local numB2 = tonumber(b2)
            s2 = (ok and b2 ~= nil) and ((numB2 ~= nil) and tostring(math.abs(numB2)) or tostring(b2)) or ""
        end
        t["@" .. n] = s2
        t["$" .. n] = s2
    end
    if t["$1"] ~= nil then t["$"] = t["$1"] else t["$"] = "" end
    local rawDuration
    ok, rawDuration = pcall(function()
        return spell.Duration and spell.Duration()
    end)
    if ok and rawDuration ~= nil then
        t["%z"] = formatDurationTicks(rawDuration)
    else
        t["%z"] = ""
    end
    return t
end

--- Replace placeholder keys in str with values from subst. Keys replaced longest-first so $1 before $.
local function applyDescriptionSubstitution(str, subst)
    if not str or not subst then return str end
    local keys = {}
    for k in pairs(subst) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return #a > #b end)
    local out = tostring(str)
    for _, key in ipairs(keys) do
        local val = subst[key]
        if val ~= nil then
            -- Escape all Lua pattern magic so key is matched literally (e.g. $ must not mean end-of-string).
            local pattern = key:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
            out = out:gsub(pattern, val)
        end
    end
    return out
end

function M.getSpellDescription(id)
    if not id or id <= 0 then return nil end
    local cacheKey = 'spell:desc:' .. id
    local desc = Cache.get(cacheKey)
    if desc ~= nil then return desc end
    local s = (mq.TLO and mq.TLO.Spell and mq.TLO.Spell(id)) or nil
    desc = s and s.Description and s.Description() or ""
    desc = M.stripDescriptionMarkup(desc) or desc
    local placeholderParserEnabled = true
    if placeholderParserEnabled and hasPlaceholders(desc) and s then
        local ok, subst = pcall(buildDescriptionSubstitutionTable, s)
        if ok and subst and next(subst) then
            desc = applyDescriptionSubstitution(desc, subst)
        end
    end
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

--- Spell duration (raw from TLO; often ticks). Returns nil if not available. Cached.
function M.getSpellDuration(id)
    if not id or id <= 0 then return nil end
    local cacheKey = 'spell:duration:' .. id
    local val = Cache.get(cacheKey)
    if val ~= nil then return val end
    local s = (mq.TLO and mq.TLO.Spell and mq.TLO.Spell(id)) or nil
    if not s or not s.Duration then return nil end
    local ok, raw = pcall(function() return s.Duration() end)
    if not ok or raw == nil then return nil end
    local n = tonumber(raw)
    if n then Cache.set(cacheKey, n, { tier = 'L2' }); return n end
    return nil
end

--- Spell recovery time (e.g. after fizzle). Returns nil if not available. Cached.
function M.getSpellRecoveryTime(id)
    if not id or id <= 0 then return nil end
    local cacheKey = 'spell:recoverytime:' .. id
    local val = Cache.get(cacheKey)
    if val ~= nil then return val end
    local s = (mq.TLO and mq.TLO.Spell and mq.TLO.Spell(id)) or nil
    if not s then return nil end
    local fn = s.RecoveryTime or s.FizzleTime
    if not fn then return nil end
    local ok, raw = pcall(function() return fn() end)
    if not ok or raw == nil then return nil end
    local n = tonumber(raw)
    if n then Cache.set(cacheKey, n, { tier = 'L2' }); return n end
    return nil
end

--- Spell range. Returns nil if not available. Cached.
function M.getSpellRange(id)
    if not id or id <= 0 then return nil end
    local cacheKey = 'spell:range:' .. id
    local val = Cache.get(cacheKey)
    if val ~= nil then return val end
    local s = (mq.TLO and mq.TLO.Spell and mq.TLO.Spell(id)) or nil
    if not s or not s.Range then return nil end
    local ok, raw = pcall(function() return s.Range() end)
    if not ok or raw == nil then return nil end
    local n = tonumber(raw)
    if n then Cache.set(cacheKey, n, { tier = 'L2' }); return n end
    return nil
end

--- Item lore text (flavor string) from item TLO. Returns string or nil. Safe to call with nil it.
--- Tries LoreText() then Lore() if it returns a string; does not cache (caller may cache per tooltip).
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
--- When item.socketIndex is set (e.g. augment/ornament link tooltip), resolves parent TLO then parent.Item(socketIndex).
function M.getItemSpellId(item, prop)
    if not item or not prop then return 0 end
    local key = prop:lower()
    if item[key] ~= nil then return item[key] or 0 end
    local src = rawget(item, "source") or "inv"
    local slotItem = M.getItemTLO(item.bag, item.slot, src)
    if not slotItem then item[key] = 0; return 0 end
    local sock = rawget(item, "socketIndex")
    if sock and slotItem.Item then
        local ok, si = pcall(function() return slotItem.Item(sock) end)
        if ok and si and si.ID and si.ID() ~= 0 then slotItem = si end
    end
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

--- Return display label for equipment slot 0-22 (e.g. "Primary", "Charm"). For Equipment Companion grid labels.
function M.getEquipmentSlotLabel(slotIndex)
    local n = tonumber(slotIndex)
    if n == nil or n < 0 or n > 22 then return nil end
    return SLOT_DISPLAY_NAMES[n]
end

-- Slot names for /itemnotify <name> leftmouseup (MQ2 equipment slot names).
local SLOT_NAMES_ITEMNOTIFY = {
    [0] = "charm", [1] = "leftear", [2] = "head", [3] = "face", [4] = "rightear",
    [5] = "neck", [6] = "shoulder", [7] = "arms", [8] = "back", [9] = "leftwrist",
    [10] = "rightwrist", [11] = "ranged", [12] = "hands", [13] = "mainhand", [14] = "offhand",
    [15] = "leftfinger", [16] = "rightfinger", [17] = "chest", [18] = "legs", [19] = "feet",
    [20] = "waist", [21] = "powersource", [22] = "ammo",
}

--- Return MQ2 slot name for equipment slot 0-22 for use with /itemnotify <name> leftmouseup (pickup, equip, put-back).
function M.getEquipmentSlotNameForItemNotify(slotIndex)
    local n = tonumber(slotIndex)
    if n == nil or n < 0 or n > 22 then return nil end
    return SLOT_NAMES_ITEMNOTIFY[n]
end

local function slotIndexToDisplayName(s)
    if s == nil or s == "" then return nil end
    local n = tonumber(s)
    if n ~= nil and SLOT_DISPLAY_NAMES[n] then return SLOT_DISPLAY_NAMES[n] end
    local str = tostring(s):lower():gsub("^%l", string.upper)
    return (str ~= "") and str or nil
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

--- True if the augment's worn-slot restriction allows the parent item. Augment can restrict which equipment slot
--- the parent item is worn in (e.g. "Legs Only", "Wrist Only"). Parent must be wearable in at least one slot
--- that the augment allows; if augment allows "All", any parent is ok.
function M.augmentWornSlotAllowsParent(parentIt, augIt)
    if not parentIt then return false end
    local augSlots = M.getWornSlotIndicesFromTLO(augIt)
    if augSlots == "all" then return true end
    if type(augSlots) ~= "table" or not next(augSlots) then return true end
    local parentSlots = M.getWornSlotIndicesFromTLO(parentIt)
    if parentSlots == "all" then return true end
    if type(parentSlots) ~= "table" or not next(parentSlots) then return false end
    for idx, _ in pairs(parentSlots) do
        if augSlots[idx] then return true end
    end
    return false
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

--- Ornament slot index (1-based) and socket type per AUGMENT_SOCKET_UI_DESIGN. Slot 5 = Ornamentation (type 20).
local ORNAMENT_SLOT_INDEX = 5
local ORNAMENT_SOCKET_TYPE = 20

--- True if item has ornament slot (slot 5, type 20). Used to exclude ornament from "standard" augment slot count in UI.
function M.itemHasOrnamentSlot(it)
    if not it then return false end
    return M.getSlotType(it, ORNAMENT_SLOT_INDEX) == ORNAMENT_SOCKET_TYPE
end

--- Return list of 1-based standard augment slot indices (1-4) that currently have an augment (it.Item(i) ID > 0).
--- Used by Augment Utility "Remove All" to know which slots to queue. Slots 1-4 only; ornament (5) excluded.
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

--- Count of standard augment slots (1-4 only) that actually have a socket type > 0. Iterates slots 1-4 and
--- counts only those with getSlotType(it, i) > 0, so we never show phantom "Slot N, type 0 (empty)" rows when
--- the game reports extra AugSlotN or when ornament (slot 5) is not reported as type 20. Ornament add/remove
--- can be supported later as a separate flow (slot 5, type 20) since it behaves differently from augments.
function M.getStandardAugSlotsCountFromTLO(it)
    if not it then return 0 end
    local n = 0
    for i = 1, 4 do
        if M.getSlotType(it, i) > 0 then n = n + 1 end
    end
    return n
end

--- Get AugType from item TLO (for augmentation items). Returns number or 0. Used to match augment to socket type.
function M.getAugTypeFromTLO(it)
    if not it or not it.AugType then return 0 end
    local ok, v = pcall(function() return it.AugType() end)
    if not ok or not v then return 0 end
    return tonumber(v) or 0
end

--- Get AugRestrictions from item TLO (for augmentation items). Returns int: 0=none, 1-15=single restriction (live EQ).
--- If callers see values >15 or default Item Display shows multiple restriction lines for one item, decode as bitmask (bits 1-15 → restriction names, OR in augmentRestrictionAllowsParent).
function M.getAugRestrictionsFromTLO(it)
    if not it or not it.AugRestrictions then return 0 end
    local ok, v = pcall(function() return it.AugRestrictions() end)
    if not ok or not v then return 0 end
    return tonumber(v) or 0
end

--- Expand AugType (bitmask or single type) to list of slot type IDs (1-based). Used for "This augment fits in slot types" display.
function M.getAugTypeSlotIds(augType)
    if not augType or augType <= 0 then return {} end
    local list = {}
    local bit32 = bit32
    for slotId = 1, 24 do
        local bit = (bit32 and bit32.lshift and bit32.lshift(1, slotId - 1)) or (2 ^ (slotId - 1))
        local set = (augType == slotId) or (bit32 and bit32.band and bit32.band(augType, bit) ~= 0)
        if set then list[#list + 1] = slotId end
    end
    return list
end

--- Classify parent item TLO as weapon/shield/armor and optional weapon subtype for augment restriction checks.
--- Returns isWeapon (boolean), isShield (boolean), typeLower (string).
local function parentItemClassify(it)
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
    local isWeapon = parentItemClassify(it)
    return isWeapon, dmg, delay
end

--- Returns baseStatKeys, heroicStatKeys for augment ranking (single source of truth with STAT_TLO_MAP).
function M.getStatKeysForRanking()
    local baseKeys, heroicKeys = {}, {}
    for field, _ in pairs(STAT_TLO_MAP) do
        if STAT_STRING_FIELDS[field] then
            -- skip string-only fields for numeric sum
        elseif field:sub(1, 7) == "heroic" then
            heroicKeys[#heroicKeys + 1] = field
        else
            baseKeys[#baseKeys + 1] = field
        end
    end
    return baseKeys, heroicKeys
end

--- True if the augment's AugRestrictions allow the parent item. Restriction 0 = none; 1 = Armor Only;
--- 2 = Weapons Only; 3 = One-Handed Weapons Only; 4 = 2H Weapons Only; 5-12 = specific weapon types;
--- 13 = Shields Only; 14 = 1H Slash/1H Blunt/H2H; 15 = 1H Blunt/H2H. IDs match AUG_RESTRICTION_NAMES in item_tooltip.
--- If AugRestrictions is ever a bitmask, allow parent when any set bit allows it (OR logic).
function M.augmentRestrictionAllowsParent(parentIt, augRestrictionId)
    if not augRestrictionId or augRestrictionId == 0 then return true end
    if not parentIt then return false end
    local isWeapon, isShield, typeLower = parentItemClassify(parentIt)
    -- 1 = Armor Only: parent must not be weapon (armor or shield ok)
    if augRestrictionId == 1 then return not isWeapon end
    -- 2 = Weapons Only
    if augRestrictionId == 2 then return isWeapon end
    -- 13 = Shields Only
    if augRestrictionId == 13 then return isShield end
    -- 3-12, 14-15: weapon subtype; parent must be weapon and type string match (IDs match live EQ)
    if augRestrictionId >= 3 and augRestrictionId <= 15 then
        if not isWeapon then return false end
        if not typeLower or typeLower == "" then return false end
        if augRestrictionId == 3 then return typeLower:find("1h", 1, true) end  -- One-Handed Weapons Only (any 1H)
        if augRestrictionId == 4 then return typeLower:find("2h", 1, true) end  -- 2H Weapons Only (any 2H)
        if augRestrictionId == 5 then return typeLower:find("1h", 1, true) and typeLower:find("slashing", 1, true) end
        if augRestrictionId == 6 then return typeLower:find("1h", 1, true) and typeLower:find("blunt", 1, true) end
        if augRestrictionId == 7 then return typeLower:find("piercing", 1, true) end
        if augRestrictionId == 8 then return typeLower:find("hand to hand", 1, true) or typeLower:find("h2h", 1, true) end
        if augRestrictionId == 9 then return typeLower:find("2h", 1, true) and typeLower:find("slashing", 1, true) end
        if augRestrictionId == 10 then return typeLower:find("2h", 1, true) and typeLower:find("blunt", 1, true) end
        if augRestrictionId == 11 then return typeLower:find("2h", 1, true) and typeLower:find("piercing", 1, true) end
        if augRestrictionId == 12 then return typeLower:find("ranged", 1, true) end
        if augRestrictionId == 14 then return (typeLower:find("1h", 1, true) and (typeLower:find("slashing", 1, true) or typeLower:find("blunt", 1, true))) or typeLower:find("hand to hand", 1, true) or typeLower:find("h2h", 1, true) end
        if augRestrictionId == 15 then return (typeLower:find("1h", 1, true) and typeLower:find("blunt", 1, true)) or typeLower:find("hand to hand", 1, true) or typeLower:find("h2h", 1, true) end
        return true
    end
    return true
end

--- Check if an augment item (with augType from TLO) fits the given socket type.
--- Socket type is from parent item's AugSlotN; augType is augmentation slot type mask from the augment.
function M.augmentFitsSocket(augType, socketType)
    if not socketType or socketType <= 0 then return false end
    if not augType or augType <= 0 then return false end
    -- AugType can be a single type or a bitmask; try both
    if augType == socketType then return true end
    -- Bitmask: socket type 1 = bit 0, etc. (Lua 5.1 has no <<; use bit32 or 2^n)
    local bit
    if bit32 and bit32.lshift then
        bit = bit32.lshift(1, socketType - 1)
    else
        bit = 2 ^ (socketType - 1)
    end
    if bit32 and bit32.band and bit32.band(augType, bit) ~= 0 then return true end
    return false
end

--- Build list of compatible augments for a given item and slot from inventory + bank.
--- An augment is recommended only if (1) it can fit the open slot, then (2) it passes all qualifications.
--- parentItem must have bag, slot, source; slotIndex is 1-based (1-6, ornament 5 optional).
--- canUseFilter: optional function(itemRow) -> boolean; when provided, only augments that pass
--- (class, race, deity, level for current player) are included.
--- Returns array of item tables (same shape as scan) that are type Augmentation and fully compatible.
function M.getCompatibleAugments(parentItem, bag, slot, source, slotIndex, inventoryItems, bankItemsOrCache, canUseFilter)
    if not parentItem or not slotIndex or slotIndex < 1 or slotIndex > 6 then return {} end
    local b, s, src = bag or parentItem.bag, slot or parentItem.slot, source or parentItem.source or "inv"
    local it = M.getItemTLO(b, s, src)
    if not it or not it.ID or it.ID() == 0 then return {} end
    local socketType = M.getSlotType(it, slotIndex)
    if not socketType or socketType <= 0 then return {} end
    local candidates = {}
    local function addCandidate(itemRow)
        if not itemRow or (itemRow.type or ""):lower() ~= "augmentation" then return end
        local augIt = M.getItemTLO(itemRow.bag, itemRow.slot, itemRow.source or "inv")
        if not augIt or not augIt.AugType then return end
        local augId = (type(augIt.ID) == "function" and augIt.ID()) or augIt.ID
        if not augId or augId == 0 then return end
        -- Step 1: Can it actually fit into the open slot? (socket type must match)
        local augType = M.getAugTypeFromTLO(augIt)
        if not M.augmentFitsSocket(augType, socketType) then return end
        -- Step 2: Qualifications (restrictions, equipment slot, character use)
        local augRestrictions = M.getAugRestrictionsFromTLO(augIt)
        if not M.augmentRestrictionAllowsParent(it, augRestrictions) then return end
        if not M.augmentWornSlotAllowsParent(it, augIt) then return end
        if type(canUseFilter) == "function" and not canUseFilter(itemRow) then return end
        candidates[#candidates + 1] = itemRow
    end
    if inventoryItems then
        for _, row in ipairs(inventoryItems) do addCandidate(row) end
    end
    if bankItemsOrCache then
        for _, row in ipairs(bankItemsOrCache) do addCandidate(row) end
    end
    return candidates
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

--- Extract core item properties from MQ item TLO (per iteminfo.mac).
--- Scan captures only: name, id, value, stackSize, type, weight, icon, and 7 sell/loot boolean flags.
--- Stat/combat, wornSlots, augSlots, and descriptive/tooltip fields are lazy-loaded on first access via __index.
--- Optional 5th arg socketIndex: when set, item is the socket TLO (e.g. parentIt.Item(5)); __index resolves
--- parent via getItemTLO(bag,slot,source) then it.Item(socketIndex) for lazy stats. Used for augment/ornament link tooltips.
function M.buildItemFromMQ(item, bag, slot, source, socketIndex)
    if not item or not item.ID or not item.ID() or item.ID() == 0 then return nil end
    local iv = item.Value and item.Value() or 0
    local ss = item.Stack and item.Stack() or 1
    if ss < 1 then ss = 1 end
    local base = {
        bag = bag, slot = slot,
        source = source or "inv",
        socketIndex = socketIndex,
        name = item.Name and item.Name() or "",
        id = item.ID and item.ID() or 0,
        value = iv, totalValue = iv * ss, stackSize = ss,
        type = item.Type and item.Type() or "",
        weight = item.Weight and item.Weight() or 0,
        icon = item.Icon and item.Icon() or 0,
        nodrop = item.NoDrop and item.NoDrop() or false,
        notrade = item.NoTrade and item.NoTrade() or false,
        lore = item.Lore and item.Lore() or false,
        attuneable = item.Attuneable and item.Attuneable() or false,
        heirloom = item.Heirloom and item.Heirloom() or false,
        collectible = item.Collectible and item.Collectible() or false,
        quest = item.Quest and item.Quest() or false,
    }
    -- Lazy-load: wornSlots, augSlots, and stat fields on first access (use getItemTLO so bank uses Me.Bank)
    setmetatable(base, { __index = function(t, k)
        local b, s = t.bag, t.slot
        local src = rawget(t, "source") or "inv"
        local sock = rawget(t, "socketIndex")
        local it = M.getItemTLO(b, s, src)
        if sock and it and it.Item then it = it.Item(sock) end
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
        if k == "augType" then
            local itemType = rawget(t, "type") or ""
            if (itemType):lower() ~= "augmentation" then return nil end
            local v = (it and M.getAugTypeFromTLO(it)) or 0
            rawset(t, "augType", v)
            return v
        end
        if k == "augRestrictions" then
            local itemType = rawget(t, "type") or ""
            if (itemType):lower() ~= "augmentation" then return nil end
            local v = (it and M.getAugRestrictionsFromTLO(it)) or 0
            rawset(t, "augRestrictions", v)
            return v
        end
        -- Descriptive/tooltip-only fields: batch-load on first access to any of them
        if DESCRIPTIVE_FIELDS_SET[k] then
            if rawget(t, "_descriptive_loaded") then return rawget(t, k) end
            if it and it.ID and it.ID() ~= 0 then
                local clsStr, raceStr = M.getClassRaceStringsFromTLO(it)
                local deityStr = M.getDeityStringFromTLO(it)
                rawset(t, "tribute", it.Tribute and it.Tribute() or 0)
                rawset(t, "size", it.Size and it.Size() or 0)
                rawset(t, "sizeCapacity", it.SizeCapacity and it.SizeCapacity() or 0)
                rawset(t, "container", it.Container and it.Container() or 0)
                rawset(t, "stackSizeMax", it.StackSize and it.StackSize() or rawget(t, "stackSize") or 1)
                rawset(t, "norent", it.NoRent and it.NoRent() or false)
                rawset(t, "magic", it.Magic and it.Magic() or false)
                rawset(t, "prestige", it.Prestige and it.Prestige() or false)
                rawset(t, "tradeskills", it.Tradeskills and it.Tradeskills() or false)
                rawset(t, "requiredLevel", it.RequiredLevel and it.RequiredLevel() or 0)
                rawset(t, "recommendedLevel", it.RecommendedLevel and it.RecommendedLevel() or 0)
                rawset(t, "instrumentType", it.InstrumentType and it.InstrumentType() or "")
                rawset(t, "instrumentMod", it.InstrumentMod and it.InstrumentMod() or 0)
                rawset(t, "class", clsStr or "")
                rawset(t, "race", raceStr or "")
                rawset(t, "deity", deityStr or "")
            else
                rawset(t, "_tlo_unavailable", true)
                rawset(t, "tribute", 0) rawset(t, "size", 0) rawset(t, "sizeCapacity", 0) rawset(t, "container", 0)
                rawset(t, "stackSizeMax", rawget(t, "stackSize") or 1)
                rawset(t, "norent", false) rawset(t, "magic", false) rawset(t, "prestige", false) rawset(t, "tradeskills", false)
                rawset(t, "requiredLevel", 0) rawset(t, "recommendedLevel", 0) rawset(t, "instrumentMod", 0)
                rawset(t, "instrumentType", "") rawset(t, "class", "") rawset(t, "race", "") rawset(t, "deity", "")
            end
            rawset(t, "_descriptive_loaded", true)
            return rawget(t, k)
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
