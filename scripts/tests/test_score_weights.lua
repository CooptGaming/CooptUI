-- scoreForClass suite - pins the UPGRADE_SCORE model plumbing (2026-08-04): the
-- data-driven weight resolution, the exchange-rate heroic pricing, the weapon dps
-- path, and above all the STACKING structure the field research made load-bearing:
--   * "highest" lines score 0 in context when a better/equal copy of the line is
--     already worn (wherever it lives - item, buff, or set bonus);
--   * "additive_capped" lines score only remaining cap headroom;
--   * capped STATS (shielding) score only headroom when context carries statUsed;
--   * unrecognized effects are LISTED as unscored, never guessed at.
-- Also: class overrides deep-merge over archetypes, ranked names parse digits AND
-- roman numerals, augments ride the same table as items, garbage input returns nil.

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
local function near(a, b) return math.abs(a - b) < 0.001 end

-- item_compare is pure (no mq); score_weights is pure data. No stubs needed.
local compare = require('itemui.utils.item_compare')
local weights = require('itemui.utils.score_weights')

-- ---------------------------------------------------------------- resolution
do
    for cls, arch in pairs(weights.classes) do
        local t = compare.scoreForClass({ hp = 1 }, cls)
        check('class resolves: ' .. cls .. ' (' .. arch .. ')', t ~= nil)
    end
    check('unknown class -> nil', compare.scoreForClass({ hp = 1 }, 'XXX') == nil)
    check('nil item -> nil', compare.scoreForClass(nil, 'WAR') == nil)
end

-- ---------------------------------------------------------------- stats math
do
    local t, b = compare.scoreForClass({ hp = 100, ac = 50 }, 'WAR')
    -- TANK: 100x1.0 + 50x4.0 = 300
    check('TANK hp+ac hand-check (300)', near(t, 300), t)
    check('breakdown carries archetype', b.archetype == 'TANK')

    local t2 = compare.scoreForClass({ hp = 100, ac = 50 }, 'WIZ')
    -- CASTER: 100x0.8 + 50x1.0 = 130
    check('CASTER same item scores differently (130)', near(t2, 130), t2)

    -- Aug-inclusive: socket stats ride the same quantity compare() uses.
    local t3 = compare.scoreForClass({ hp = 100 }, 'WAR', { augStats = { hp = 50 } })
    check('augStats add in (150)', near(t3, 150), t3)

    -- Shielding is first-class: TANK 5 shielding = 60.
    local t4 = compare.scoreForClass({ shielding = 5 }, 'WAR')
    check('shielding first-class (60)', near(t4, 60), t4)

    -- Resists small-positive: 60 total sv* x 0.3 = 18.
    local _, b5 = compare.scoreForClass({ svMagic = 30, svFire = 30 }, 'WAR')
    check('resists priced small-positive (18)', near(b5.resists, 18), b5.resists)
end

-- ---------------------------------------------------------------- heroics
do
    -- Exchange-rate pricing: TANK hSta 10 -> 101.5; hStr 10 -> 5.5.
    local _, b = compare.scoreForClass({ heroicSTA = 10, heroicSTR = 10 }, 'WAR')
    check('hSta priced from exchange rate (101.5)', near(b.heroics, 101.5 + 5.5), b.heroics)

    -- Class override deep-merge: RNG hDex 1.0 vs HYBRID base 0.10; BRD stays base.
    local _, bRng = compare.scoreForClass({ heroicDEX = 10 }, 'RNG')
    local _, bBrd = compare.scoreForClass({ heroicDEX = 10 }, 'BRD')
    check('RNG override lifts hDex (10)', near(bRng.heroics, 10), bRng.heroics)
    check('BRD keeps archetype hDex (1)', near(bBrd.heroics, 1), bBrd.heroics)

    -- Override merge must not lose unrelated keys: PAL hSta still archetype 10.15.
    local _, bPal = compare.scoreForClass({ heroicSTA = 10, heroicWIS = 10 }, 'PAL')
    check('PAL merge keeps hSta + adds hWis (111.5)', near(bPal.heroics, 101.5 + 10), bPal.heroics)
end

-- ---------------------------------------------------------------- weapon path
do
    local t, b = compare.scoreForClass({ damage = 50, itemDelay = 25, hp = 10 }, 'MNK')
    -- ratio 2.0 -> dps 20 -> MELEE 20x15 = 300; hp 10x1.0 = 10.
    check('weapon dps path (300)', near(b.dps, 300), b.dps)
    check('weapon riders still count (total 310)', near(t, 310), t)

    -- Unrecognized proc WITH a rate prices as damage-class: 2 x 15 x 0.5 = 15.
    local _, b2 = compare.scoreForClass({ damage = 50, itemDelay = 25 }, 'MNK',
        { procName = 'Unknown Smite', procRate = 2 })
    check('rated proc prices via dps factor (15)', near(b2.effects, 15), b2.effects)
    check('rated proc is not unscored', #b2.unscored == 0)

    -- Recognized proc name scores via its family instead: TANK defensiveProc 150.
    local _, b3 = compare.scoreForClass({ damage = 50, itemDelay = 25 }, 'WAR',
        { procName = 'Pious Shield' })
    check('named proc scores via family (150)', near(b3.effects, 150), b3.effects)

    -- Rateless unknown proc -> unscored, never guessed.
    local _, b4 = compare.scoreForClass({ damage = 50, itemDelay = 25 }, 'MNK',
        { procName = 'Mystery Proc' })
    check('rateless unknown proc listed unscored', b4.unscored[1] == 'Mystery Proc')
end

-- ---------------------------------------------------------------- effects + stacking
do
    -- Percent family: dodge 70% TANK -> 70x8 = 560 (magnitude in the table, no
    -- parsing). Registered here the way the field will: one byName data row.
    weights.effects.byName['Dodging Gem'] = { line = 'dodge', value = 70 }
    local _, b = compare.scoreForClass({}, 'WAR', { effects = { 'Dodging Gem' } })
    check('percent family scores (560)', near(b.effects, 560), b.effects)

    -- highest + context: an equal-or-better copy worn anywhere zeroes it.
    local _, b2 = compare.scoreForClass({}, 'WAR',
        { effects = { 'Dodging Gem' }, context = { wornLines = { dodge = 70 } } })
    check('highest line zeroed by equal worn copy', near(b2.effects, 0), b2.effects)
    local _, b3 = compare.scoreForClass({}, 'WAR',
        { effects = { 'Dodging Gem' }, context = { wornLines = { dodge = 30 } } })
    check('highest line scores past a weaker copy (560)', near(b3.effects, 560), b3.effects)
    weights.effects.byName['Dodging Gem'] = nil

    -- Ranked-name magnitude: FT pattern prices through the manaRegen stat weight.
    -- CLR (PRIEST): Flowing Thought III -> 3 x 8.0 = 24.
    local _, b4 = compare.scoreForClass({}, 'CLR', { effects = { 'Flowing Thought III' } })
    check('FT roman numeral prices via manaRegen (24)', near(b4.effects, 24), b4.effects)
    local _, b5 = compare.scoreForClass({}, 'CLR', { effects = { 'FT5' } })
    check('FT digit form prices too (40)', near(b5.effects, 40), b5.effects)

    -- additive_capped: cap 15, 13 used -> FT5 scores only 2 units (16).
    local _, b6 = compare.scoreForClass({}, 'CLR',
        { effects = { 'FT5' }, context = { lineUsed = { ftManaRegen = 13 } } })
    check('capped line scores headroom only (16)', near(b6.effects, 16), b6.effects)

    -- Pattern magnitude: All DoT Damage 60 for a CASTER -> 60x3 = 180.
    local _, b7 = compare.scoreForClass({}, 'NEC', { effects = { 'All DoT Damage 60' } })
    check('pattern magnitude scores (180)', near(b7.effects, 180), b7.effects)

    -- Field families 08-17 (worn-tracker round), one pin per pattern shape:
    -- Ferocity rides doubleAttack (TANK 10 x IX = 90); Cleave tolerates the
    -- " - 150" rating suffix (TANK 8 x XI = 88); Improve All Damage is the
    -- spell-damage focus (CASTER 45 x II = 90); Detrimental Haste carries
    -- PERCENT units in its name (CASTER 14 x 23 = 322); Improved Dodge rides
    -- the dodge line (TANK 8 x XII = 96).
    local _, f1 = compare.scoreForClass({}, 'WAR', { effects = { 'Ferocity IX' } })
    check('Ferocity prices via doubleAttack (90)', near(f1.effects, 90), f1.effects)
    local _, f2 = compare.scoreForClass({}, 'WAR', { effects = { 'Cleave XI - 150' } })
    check('Cleave suffix form prices via tier (88)', near(f2.effects, 88), f2.effects)
    local _, f3 = compare.scoreForClass({}, 'WIZ', { effects = { 'Improve All Damage II' } })
    check('Improve All Damage prices (90)', near(f3.effects, 90), f3.effects)
    local _, f4 = compare.scoreForClass({}, 'WIZ', { effects = { 'Detrimental Haste 23 L100' } })
    check('Detrimental Haste percent units (322)', near(f4.effects, 322), f4.effects)
    local _, f5 = compare.scoreForClass({}, 'WAR', { effects = { 'Improved Dodge XII' } })
    check('Improved Dodge rides dodge line (96)', near(f5.effects, 96), f5.effects)

    -- Clicky family: travel flat 80.
    local _, b8 = compare.scoreForClass({}, 'WAR', { effects = { 'Everlasting Breath' } })
    check('clicky family flat (80)', near(b8.effects, 80), b8.effects)

    -- Unknown effect -> unscored list, effects total untouched.
    local _, b9 = compare.scoreForClass({}, 'WAR', { effects = { 'Totally New Effect' } })
    check('unknown effect listed unscored', b9.unscored[1] == 'Totally New Effect')
    check('unknown effect scores 0', near(b9.effects, 0), b9.effects)
end

-- ---------------------------------------------------------------- capped stat context
do
    -- Shielding cap unknown by default (nil) - full value scores.
    local t1 = compare.scoreForClass({ shielding = 5 }, 'WAR',
        { context = { statUsed = { shielding = 30 } } })
    check('nil statCap ignores statUsed (60)', near(t1, 60), t1)

    -- With a cap set in data, only headroom scores.
    weights.statCaps.shielding = 35
    local t2 = compare.scoreForClass({ shielding = 5 }, 'WAR',
        { context = { statUsed = { shielding = 33 } } })
    check('capped stat scores headroom only (24)', near(t2, 24), t2)
    local t3 = compare.scoreForClass({ shielding = 5 }, 'WAR',
        { context = { statUsed = { shielding = 40 } } })
    check('over cap scores 0', near(t3, 0), t3)
    weights.statCaps.shielding = nil
end

-- ---------------------------------------------------------------- augments ride along
do
    -- An augment is a pure stat block: same weights, no second system.
    local t = compare.scoreForClass({ hp = 40, ac = 10, type = 'Augmentation' }, 'WAR')
    check('augment scores via the same table (80)', near(t, 80), t)
end

print(string.format('%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
