-- worn_effects suite - pins the one walk behind the Effects window's Worn tracker
-- AND the score context (upgrade_scan + Aug Utility both delegate here, 2026-08-17):
--   * lines[line] is the BEST worn units (the scoreForClass context contract),
--     never the total;
--   * "highest" lines flag every non-best copy wasted (equal copies are
--     duplicates, lower copies are beaten) - the "aren't we stacking up" answer;
--   * "additive_capped" lines report the over-cap excess;
--   * unrecognized names land in `untracked` (the calibration feed), never
--     silently dropped;
--   * the walk survives nil/missing accessors and empty caches.

local repo = os.getenv('COOPT_REPO') or 'C:/Claude/CooptUI'
package.path = repo .. '/lua/?.lua;' .. repo .. '/lua/?/init.lua;'
    .. repo .. '/scripts/tests/?.lua;' .. package.path

local pass, fail = 0, 0
local function check(name, cond, extra)
    if cond then
        pass = pass + 1
        print('PASS: ' .. name)
    else
        fail = fail + 1
        print('FAIL: ' .. name .. (extra and ('  -> ' .. tostring(extra)) or ''))
    end
end

local wornEffects = require('itemui.utils.worn_effects')

-- Spell-id space: names chosen from score_weights byName/patterns so the REAL
-- resolveEffectLine places them (no stubbed resolution - drift here is the bug).
local NAMES = {
    [101] = "Spell Haste V",       -- spellHaste, highest, 5
    [102] = "Spell Haste III",     -- spellHaste, 3
    [103] = "Flowing Thought X",   -- ftManaRegen, additive_capped cap 15, 10
    [104] = "FT10",                -- ftManaRegen, 10
    [105] = "Pious Shield",        -- defensiveProc, additive, 1
    [106] = "Mystery Aura IX",     -- resolves to nothing -> untracked
    [107] = "Ferocity IX",         -- doubleAttack (08-17 field family), 9
}

local function item(name, id, spells)
    return { id = id, name = name, spells = spells or {} }
end

-- cache[i] holds slot i-1 (the equipment cache convention).
local cache = {}
cache[2]  = item("Earring of Alacrity", 11, { Worn = 101 })   -- slot 1, Spell Haste V
cache[3]  = item("Helm of Alacrity", 12, { Worn = 101 })      -- slot 2, Spell Haste V (duplicate)
cache[18] = item("Vest of Alacrity", 13, { Worn = 102 })      -- slot 17, Spell Haste III (beaten)
cache[6]  = item("Torc of Thought", 14, { Focus = 103 })      -- slot 5, FT 10
cache[10] = item("Band of Thought", 15, { Worn = 104 })       -- slot 9, FT 10 (total 20 / cap 15)
cache[14] = item("Pious Blade", 16, { Worn = 105 })           -- slot 13, defensiveProc
cache[15] = item("Mystery Buckler", 17, { Worn = 106 })       -- slot 14, untracked
cache[13] = item("Gauntlets of Fury", 18, { Worn = 107 })     -- slot 12, doubleAttack 9

local src = {
    equipmentCache = cache,
    getItemSpellId = function(it, kind) return (it.spells and it.spells[kind]) or 0 end,
    getSpellName = function(id) return NAMES[id] end,
}

local built = wornEffects.build(src)

-- ---------------------------------------------------------------- context map
do
    check('spellHaste line carries BEST (5), not total', built.lines.spellHaste == 5, built.lines.spellHaste)
    check('ftManaRegen line carries BEST (10), not total', built.lines.ftManaRegen == 10, built.lines.ftManaRegen)
    check('defensiveProc line present (1)', built.lines.defensiveProc == 1, built.lines.defensiveProc)
    check('Ferocity resolves to doubleAttack (9)', built.lines.doubleAttack == 9, built.lines.doubleAttack)
    check('untracked name never enters lines', built.lines.mystery == nil)
end

-- ---------------------------------------------------------------- groups
do
    check('four groups', #built.groups == 4, #built.groups)
    check('groups sorted by display name', built.groups[1].line == 'defensiveProc'
        and built.groups[2].line == 'doubleAttack'
        and built.groups[3].line == 'ftManaRegen' and built.groups[4].line == 'spellHaste')
    check('display names are human labels', built.groups[1].displayName == 'Defensive Proc'
        and built.groups[2].displayName == 'Double Attack'
        and built.groups[3].displayName == 'Flowing Thought'
        and built.groups[4].displayName == 'Spell Haste')

    local sh = built.groups[4]
    check('spellHaste stacking highest', sh.stacking == 'highest')
    check('spellHaste best 5 total 13', sh.best == 5 and sh.total == 13, sh.total)
    check('spellHaste wastedCount 2', sh.wastedCount == 2, sh.wastedCount)
    check('entries sorted units desc, slot asc among equals',
        sh.entries[1].slotIndex == 1 and sh.entries[2].slotIndex == 2 and sh.entries[3].slotIndex == 17)
    check('winner not wasted', not sh.entries[1].wasted)
    check('equal copy is a duplicate', sh.entries[2].wasted
        and sh.entries[2].wastedWhy:find('duplicate of Earring of Alacrity', 1, true) ~= nil, sh.entries[2].wastedWhy)
    check('lower copy is beaten', sh.entries[3].wasted
        and sh.entries[3].wastedWhy:find('beaten by Earring of Alacrity', 1, true) ~= nil, sh.entries[3].wastedWhy)
    check('slot names ride along', sh.entries[1].slotName == 'Left Ear' and sh.entries[3].slotName == 'Chest')

    local ft = built.groups[3]
    check('ft stacking additive_capped cap 15', ft.stacking == 'additive_capped' and ft.cap == 15)
    check('ft total 20, overCap 5', ft.total == 20 and ft.overCap == 5, ft.overCap)
    check('ft copies not individually wasted', not ft.entries[1].wasted and not ft.entries[2].wasted)

    local dp = built.groups[1]
    check('additive line: no waste, no overCap', dp.wastedCount == 0 and dp.overCap == nil)

    local da = built.groups[2]
    check('single-copy highest line: no waste', da.best == 9 and da.wastedCount == 0)
end

-- ---------------------------------------------------------------- untracked + summary
do
    check('untracked carries the mystery name', #built.untracked == 1
        and built.untracked[1].effName == 'Mystery Aura IX'
        and built.untracked[1].itemName == 'Mystery Buckler', built.untracked[1] and built.untracked[1].effName)
    local overlapped, overCap = wornEffects.wasteSummary(built)
    check('wasteSummary 2 overlapped, 5 over cap', overlapped == 2 and overCap == 5,
        tostring(overlapped) .. '/' .. tostring(overCap))
end

-- ---------------------------------------------------------------- fingerprint + safety
do
    local fp1 = wornEffects.fingerprint(cache)
    cache[3].id = 999
    local fp2 = wornEffects.fingerprint(cache)
    check('fingerprint moves with an equipped id', fp1 ~= fp2)

    local empty = wornEffects.build({ equipmentCache = {},
        getItemSpellId = src.getItemSpellId, getSpellName = src.getSpellName })
    check('empty cache -> empty result', #empty.groups == 0 and #empty.untracked == 0 and next(empty.lines) == nil)
    local nilBuild = wornEffects.build(nil)
    check('nil src survives', #nilBuild.groups == 0)
    local noAcc = wornEffects.build({ equipmentCache = cache })
    check('missing accessors survive', #noAcc.groups == 0)
    local throwing = wornEffects.build({ equipmentCache = cache,
        getItemSpellId = function() error('boom') end, getSpellName = src.getSpellName })
    check('throwing accessor survives', #throwing.groups == 0)
end

print(string.format('%d passed, %d failed', pass, fail))
if fail > 0 then os.exit(1) end
