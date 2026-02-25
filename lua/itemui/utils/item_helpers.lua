--[[
    ItemUI - Item Helper Utilities
    Status messages, currency formatting, spell caching, item building.
    Part of CoOpt UI — EverQuest EMU Companion
--]]

local mq = require('mq')
local Cache = require('itemui.core.cache')
local item_tlo = require('itemui.utils.item_tlo')
local augment_helpers = require('itemui.utils.augment_helpers')

local M = {}
local deps  -- set by init()

-- Delegate TLO resolution and property readers to item_tlo (extraction 6)
M.getItemTLO = item_tlo.getItemTLO
M.getItemLoreText = item_tlo.getItemLoreText
M.getEquipmentSlotLabel = item_tlo.getEquipmentSlotLabel
M.getEquipmentSlotNameForItemNotify = item_tlo.getEquipmentSlotNameForItemNotify
M.getSlotDisplayName = item_tlo.getSlotDisplayName
M.getWornSlotsStringFromTLO = item_tlo.getWornSlotsStringFromTLO
M.getWornSlotIndicesFromTLO = item_tlo.getWornSlotIndicesFromTLO
M.getAugSlotsCountFromTLO = item_tlo.getAugSlotsCountFromTLO
M.getSlotType = item_tlo.getSlotType
M.itemHasOrnamentSlot = item_tlo.itemHasOrnamentSlot
M.getFilledStandardAugmentSlotIndices = item_tlo.getFilledStandardAugmentSlotIndices
M.getStandardAugSlotsCountFromTLO = item_tlo.getStandardAugSlotsCountFromTLO
M.getAugTypeFromTLO = item_tlo.getAugTypeFromTLO
M.getAugRestrictionsFromTLO = item_tlo.getAugRestrictionsFromTLO
M.getParentWeaponInfo = item_tlo.getParentWeaponInfo
M.getClassRaceStringsFromTLO = item_tlo.getClassRaceStringsFromTLO
M.getClassRaceSlotFromTLO = item_tlo.getClassRaceSlotFromTLO
M.getDeityStringFromTLO = item_tlo.getDeityStringFromTLO
M.parentItemClassify = item_tlo.parentItemClassify

-- Delegate augment compatibility to augment_helpers (extraction 7)
M.getAugTypeSlotIds = augment_helpers.getAugTypeSlotIds
M.augmentWornSlotAllowsParent = augment_helpers.augmentWornSlotAllowsParent
M.augmentWornSlotAllowsParentWithCachedAugSlots = augment_helpers.augmentWornSlotAllowsParentWithCachedAugSlots
M.augmentRestrictionAllowsParent = augment_helpers.augmentRestrictionAllowsParent
M.buildAugmentIndex = augment_helpers.buildAugmentIndex
M.augmentFitsSocket = augment_helpers.augmentFitsSocket
M.getCompatibleAugments = augment_helpers.getCompatibleAugments

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

--- When true, getSpellDescription asserts no unresolved # @ $ % tokens remain after substitution (MASTER_PLAN 2.6).
local STML_DEBUG_ASSERT = false

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
        if STML_DEBUG_ASSERT and desc and desc:find("[#@$%%]") then
            error("STML: unresolved placeholder in description (spell id " .. tostring(id) .. ")")
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
--- Normalizes raw TLO value (may be ms or deciseconds) to seconds, same as getSpellCastTime.
function M.getSpellRecastTime(id)
    if not id or id <= 0 then return nil end
    local cacheKey = 'spell:recasttime:' .. id
    local val = Cache.get(cacheKey)
    if val ~= nil then return val end
    local s = (mq.TLO and mq.TLO.Spell and mq.TLO.Spell(id)) or nil
    if not s or not s.RecastTime then return nil end
    local rt = s.RecastTime()
    local raw = tonumber(rt)
    if not raw then return nil end
    local sec = raw
    if raw >= 1000 then sec = raw / 1000
    elseif raw >= 10 then sec = raw / 10
    end
    Cache.set(cacheKey, sec, { tier = 'L2' })
    return sec
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
--- When ready > 0, updates the max recast cache for this slot so we can show "recast delay = countdown start".
function M.getTimerReady(bag, slot, source)
    if not bag or not slot then return 0 end
    source = source or "inv"
    local key = source .. "_" .. bag .. "_" .. slot
    local now = mq.gettime()
    local entry = deps.perfCache.timerReadyCache[key]
    if entry and (now - entry.at) < deps.C.TIMER_READY_CACHE_TTL_MS then
        local ready = entry.ready or 0
        if ready > 0 and deps.perfCache.timerReadyMaxCache then
            local m = deps.perfCache.timerReadyMaxCache[key]
            if not m or ready > m then deps.perfCache.timerReadyMaxCache[key] = ready end
        end
        return ready
    end
    local itemTLO = M.getItemTLO(bag, slot, source)
    local ready = (itemTLO and itemTLO.TimerReady and itemTLO.TimerReady()) or 0
    deps.perfCache.timerReadyCache[key] = { ready = ready, at = now }
    if ready > 0 and deps.perfCache.timerReadyMaxCache then
        local m = deps.perfCache.timerReadyMaxCache[key]
        if not m or ready > m then deps.perfCache.timerReadyMaxCache[key] = ready end
    end
    return ready
end

--- Max cooldown (seconds) observed for this slot — the value the countdown starts at when you click. Nil until we've seen the item on cooldown.
function M.getMaxRecastForSlot(bag, slot, source)
    if not bag or not slot or not deps.perfCache or not deps.perfCache.timerReadyMaxCache then return nil end
    source = source or "inv"
    local key = source .. "_" .. bag .. "_" .. slot
    return deps.perfCache.timerReadyMaxCache[key]
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
            -- If TLO unavailable or item ID zero (e.g. zone transition), mark pending and do not commit zeroed stats (MASTER_PLAN 2.6)
            if not it or not it.ID or it.ID() == 0 then
                rawset(t, "_statsPending", true)
                return DESCRIPTIVE_STRING_FIELDS[k] and "" or 0
            end
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
            end
            rawset(t, "_descriptive_loaded", true)
            return rawget(t, k)
        end
        if not STAT_FIELDS_SET[k] then return nil end
        -- Batch-load all stat fields from TLO. If ID zero, mark pending and do not commit zeroed stats (MASTER_PLAN 2.6)
        if not it or not it.ID or it.ID() == 0 then
            rawset(t, "_statsPending", true)
            return STAT_STRING_FIELDS[k] and "" or 0
        end
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
        end
        return rawget(t, k)
    end })
    return base
end

return M
