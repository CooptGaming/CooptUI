--[[
    score_weights.lua — the DATA behind scoreForClass (UPGRADE_SCORE.md model, built
    2026-08-04). PURE DATA MODULE: no requires, no functions beyond the return, nothing
    here executes. Tuning is an EDIT TO THIS FILE, never a code change — that is the
    file's whole reason to exist, per the model doc: "these numbers are content/balance
    calls... they ship as a data table, so tuning is an edit, not a build."

    UNITS: 1 HP = 1 point. Every weight is HP-equivalent per unit of the thing weighed
    (per stat point, per percent, per proc, per tier). Sources, in trust order: the
    server's exact heroic exchange rates (heroic_stats.php), the field digest
    (docs/PERKY_PROGRESSION.md), design's archetype tables (UPGRADE_SCORE.md), and —
    for the effect-family per-unit numbers — BALLPARK SEEDS awaiting the calibration
    pass (score the user's equipped set, tune where his judgment disagrees).

    HOW TO EXTEND when new data comes in:
      * a new worn/focus/clicky NAME: add a row to effects.byName (line + value).
      * a new effect FAMILY: add a row to effects.lines (stacking + per-archetype
        perUnit or flat), then byName/pattern rows that map names into it.
      * a stacking correction from !effects in-game: flip that line's `stacking`.
      * a discovered cap: set lines.<line>.cap (units) or statCaps.<stat>.
      * a class that deviates from its archetype: add classOverrides.<CLS> with just
        the keys that differ (deep-merged over the archetype).
]]

return {
    version = 1,

    -- Upgrade detection: best-in-bags must beat equipped by this factor before it
    -- counts ("N upgrades in bags" churn guard). User undecided; calibration tunes.
    sidegradeMargin = 1.05,

    -- Damage-class proc pricing: procRate x W.dps x this factor.
    procDpsFactor = 0.5,

    -- Class -> archetype. A new server class slots in by picking a base.
    classes = {
        WAR = "TANK", PAL = "TANK", SHD = "TANK",
        MNK = "MELEE", ROG = "MELEE", BER = "MELEE", BST = "MELEE",
        CLR = "PRIEST", DRU = "PRIEST", SHM = "PRIEST",
        NEC = "CASTER", WIZ = "CASTER", MAG = "CASTER", ENC = "CASTER",
        RNG = "HYBRID", BRD = "HYBRID",
    },

    -- Archetype weight tables (UPGRADE_SCORE.md). stats keys match the item row
    -- fields item_compare reads (item_helpers STAT_TLO_MAP names).
    archetypes = {
        TANK = {
            stats = {
                hp = 1.0, ac = 4.0, mana = 0, endurance = 0.5, attack = 1.5,
                haste = 8.0, hpRegen = 3.0, manaRegen = 0,
                -- Shielding is first-class on this server (the flagged defensive
                -- stat) and cap-aware from day one - see statCaps below.
                shielding = 12,
                -- Item-stat riders: small non-zero rows (scoring them 0 would
                -- misrank whole item families here).
                spellShield = 1.0, dotShielding = 1.0, avoidance = 2.0,
                damageShield = 1.5, combatEffects = 1.0, accuracy = 1.5,
                stunResist = 1.0,
            },
            dps = 10,
            -- Priced from heroic_stats.php exchange rates, not guessed:
            -- hSta: 10 HP + 0.5 regen per 10 pts -> 10x1.0 + 0.05x3.0 = 10.15/pt.
            -- hStr: 1 melee dmg + 1 shield AC per 10 -> ~0.1 dmg + 0.1x4.0 = 0.55.
            -- hAgi: 1 avoidance AC per 10 -> 0.1x4.0 = 0.40.
            -- Field note (digest): mature TANK/MELEE builds chase hStr - if the
            -- calibration pass disagrees with ~0.55, re-check the exchange rate,
            -- not the weight.
            heroics = {
                heroicSTA = 10.15, heroicSTR = 0.55, heroicAGI = 0.40,
                heroicDEX = 0.05, heroicINT = 0, heroicWIS = 0, heroicCHA = 0,
            },
            resist = 0.3,   -- per point of any sv* (cap-then-ignore folklore; small)
            clickies = { heal = 60, nuke = 20, buff = 50, travel = 80 },
        },
        MELEE = {
            stats = {
                hp = 1.0, ac = 2.0, mana = 0, endurance = 0.8, attack = 2.5,
                haste = 12.0, hpRegen = 2.0, manaRegen = 0,
                shielding = 6,
                spellShield = 0.5, dotShielding = 0.5, avoidance = 1.5,
                damageShield = 1.0, combatEffects = 2.0, accuracy = 2.0,
                stunResist = 0.5,
            },
            dps = 15,
            heroics = {
                heroicSTA = 10.10, heroicSTR = 0.45, heroicAGI = 0.20,
                heroicDEX = 0.10, heroicINT = 0, heroicWIS = 0, heroicCHA = 0,
            },
            resist = 0.3,
            clickies = { heal = 60, nuke = 20, buff = 50, travel = 80 },
        },
        PRIEST = {
            stats = {
                hp = 1.0, ac = 1.5, mana = 1.0, endurance = 0, attack = 0,
                haste = 0, hpRegen = 2.0, manaRegen = 8.0,
                shielding = 4,
                spellShield = 1.0, dotShielding = 1.0, avoidance = 1.0,
                damageShield = 0.5, combatEffects = 0.5, accuracy = 0.5,
                stunResist = 1.0,
                -- hWis converts 1:1 to heal amount on this server (cap 4000).
                healAmount = 2.0, spellDamage = 0.5,
            },
            dps = 3,
            heroics = {
                heroicSTA = 10.10, heroicSTR = 0.05, heroicAGI = 0.15,
                heroicDEX = 0.05, heroicINT = 0.2, heroicWIS = 2.0, heroicCHA = 0,
            },
            resist = 0.3,
            clickies = { heal = 40, nuke = 30, buff = 50, travel = 80 },
        },
        CASTER = {
            stats = {
                hp = 0.8, ac = 1.0, mana = 1.2, endurance = 0, attack = 0,
                haste = 0, hpRegen = 2.0, manaRegen = 10.0,
                shielding = 2,
                spellShield = 1.0, dotShielding = 1.0, avoidance = 1.0,
                damageShield = 0.5, combatEffects = 0.5, accuracy = 0.5,
                stunResist = 1.0,
                -- hInt converts 1:1 to spell damage (cap 2000).
                spellDamage = 2.0, healAmount = 0,
            },
            dps = 3,
            heroics = {
                heroicSTA = 8.10, heroicSTR = 0.05, heroicAGI = 0.10,
                heroicDEX = 0.05, heroicINT = 2.0, heroicWIS = 0.2, heroicCHA = 0,
            },
            resist = 0.3,
            clickies = { heal = 40, nuke = 40, buff = 50, travel = 80 },
        },
        HYBRID = {
            stats = {
                hp = 1.0, ac = 2.0, mana = 0.6, endurance = 0.5, attack = 2.0,
                haste = 10.0, hpRegen = 2.0, manaRegen = 4.0,
                shielding = 6,
                spellShield = 0.5, dotShielding = 0.5, avoidance = 1.5,
                damageShield = 1.0, combatEffects = 1.5, accuracy = 1.5,
                stunResist = 0.5,
                spellDamage = 0.5, healAmount = 0.5,
            },
            dps = 12,
            heroics = {
                heroicSTA = 10.10, heroicSTR = 0.35, heroicAGI = 0.20,
                -- hDex: 1 archery/throw dmg per 10 - real for RNG (see override).
                heroicDEX = 0.10, heroicINT = 0.1, heroicWIS = 0.3, heroicCHA = 0,
            },
            resist = 0.3,
            clickies = { heal = 50, nuke = 30, buff = 50, travel = 80 },
        },
    },

    -- Per-class deltas over the archetype (deep-merged, only the keys that differ).
    classOverrides = {
        -- PAL/SHD hybrid casting (design's original note).
        PAL = { heroics = { heroicWIS = 1.0, heroicINT = 0.2 } },
        SHD = { heroics = { heroicINT = 1.0, heroicWIS = 0.2 } },
        -- Rangers actually shoot: the archery exchange rate is worth full price.
        RNG = { heroics = { heroicDEX = 1.0 } },
    },

    -- Stat caps (units of the stat). additive_capped stats score only remaining
    -- headroom when the caller provides context.statUsed. nil = cap unknown -
    -- !effects in-game is the way to learn it; write it here when known.
    statCaps = {
        shielding = nil,   -- "capped melee shielding is real and reachable" (digest)
    },

    effects = {
        -- Effect FAMILIES. stacking: "highest" (best copy of the line wins - a
        -- duplicate scores 0 in context), "additive_capped" (scores up to remaining
        -- cap headroom), "additive" (always adds). perUnit = HP-eq per unit (percent
        -- point or tier) by archetype; flat = HP-eq per instance by archetype.
        -- The perUnit/flat numbers are CALIBRATION SEEDS - ballpark by design.
        lines = {
            dodge        = { stacking = "highest", perUnit = { TANK = 8, MELEE = 6, PRIEST = 3, CASTER = 2, HYBRID = 6 } },
            parry        = { stacking = "highest", perUnit = { TANK = 6, MELEE = 5, PRIEST = 2, CASTER = 1, HYBRID = 5 } },
            riposte      = { stacking = "highest", perUnit = { TANK = 6, MELEE = 6, PRIEST = 1, CASTER = 0.5, HYBRID = 5 } },
            block        = { stacking = "highest", perUnit = { TANK = 6, MELEE = 4, PRIEST = 2, CASTER = 1, HYBRID = 4 } },
            doubleAttack = { stacking = "highest", perUnit = { TANK = 10, MELEE = 15, PRIEST = 2, CASTER = 1, HYBRID = 12 } },
            -- Combat effects (Cleave family) stack additively per the field research.
            cleave       = { stacking = "additive", perUnit = { TANK = 8, MELEE = 12, PRIEST = 1, CASTER = 1, HYBRID = 10 } },
            defenseSkill = { stacking = "highest", perUnit = { TANK = 12, MELEE = 8, PRIEST = 4, CASTER = 3, HYBRID = 8 } },
            dotFocus     = { stacking = "highest", perUnit = { TANK = 0.5, MELEE = 0.5, PRIEST = 2, CASTER = 3, HYBRID = 1.5 } },
            spellHaste   = { stacking = "highest", perUnit = { TANK = 0, MELEE = 0, PRIEST = 40, CASTER = 50, HYBRID = 25 } },
            hateMod      = { stacking = "highest", flat = { TANK = 100, MELEE = 0, PRIEST = 0, CASTER = 0, HYBRID = 0 } },
            defensiveProc = { stacking = "additive", flat = { TANK = 150, MELEE = 80, PRIEST = 60, CASTER = 40, HYBRID = 80 } },
            lifetap      = { stacking = "additive", flat = { TANK = 200, MELEE = 120, PRIEST = 40, CASTER = 30, HYBRID = 100 } },
            skillPackage = { stacking = "highest", flat = { TANK = 50, MELEE = 50, PRIEST = 30, CASTER = 20, HYBRID = 40 } },
            -- Flowing Thought and server variants: additive across items WITH a cap
            -- (upstream cap 15 worn; server may differ - it is data). Priced through
            -- the manaRegen stat weight, not its own perUnit (pattern rows below).
            ftManaRegen  = { stacking = "additive_capped", cap = 15, stat = "manaRegen" },
            -- Field families 08-17 (worn-tracker round: the user's own gear named
            -- these). Units are the TIER from the ranked name unless said otherwise;
            -- all perUnit numbers are calibration seeds like everything above.
            -- "Improve(d) (All) Damage N" - the classic spell-damage focus line.
            improvedDamage = { stacking = "highest", perUnit = { TANK = 2, MELEE = 2, PRIEST = 25, CASTER = 45, HYBRID = 20 } },
            -- "Improve(d) (All) Healing N" - its healing sibling.
            improvedHealing = { stacking = "highest", perUnit = { TANK = 3, MELEE = 0, PRIEST = 45, CASTER = 4, HYBRID = 15 } },
            -- "Detrimental/Beneficial Haste N" carries PERCENT cast reduction in the
            -- name (field: "Detrimental Haste 23 L100" = 23 percent), so its units are
            -- percent - a SEPARATE line from tier-ranked spellHaste on purpose: forcing
            -- both into one unit would be a guess. If !effects shows the game treats
            -- them as one stacking family, merge them here with a real conversion.
            castHaste = { stacking = "highest", perUnit = { TANK = 0, MELEE = 0, PRIEST = 11, CASTER = 14, HYBRID = 7 } },
        },

        -- Exact effect-name -> family + units. Site-verified seeds where known
        -- (docs/PERKY_PROGRESSION.md carries the item ids); grow this from tooltip
        -- effect names as the field reports them.
        byName = {
            ["Minor Pious Shield Effect"]        = { line = "defensiveProc", value = 1 },
            ["Pious Shield"]                     = { line = "defensiveProc", value = 1 },
            ["Scream of Death"]                  = { line = "defensiveProc", value = 1 },
            ["Shield of Despair"]                = { line = "lifetap", value = 1 },
            ["Putrid Skin Drain"]                = { line = "defensiveProc", value = 1 },
            ["Ancient: High Priest's Bulwark"]   = { line = "defensiveProc", value = 1 },
            ["WAR All Hate Mod"]                 = { line = "hateMod", value = 1 },
            ["Everlasting Breath"]               = { clicky = "travel" },
        },

        -- Name patterns (checked after byName misses). The captured group is parsed
        -- as digits OR roman numerals; value = capture x multiplier. `stat` rows
        -- price through the archetype stat weight; `line` rows through the family.
        patterns = {
            { pattern = "^Flowing Thought ([IVXLC%d]+)$", line = "ftManaRegen", multiplier = 1 },
            { pattern = "^FT([%d]+)$",                    line = "ftManaRegen", multiplier = 1 },
            { pattern = "^Spell Haste ([IVXLC%d]+)$",     line = "spellHaste", multiplier = 1 },
            { pattern = "^Myrmidon's Skill ([IVXLC%d]+)$", line = "skillPackage", multiplier = 1 },
            { pattern = "^All DoT Damage ([%d]+)$",       line = "dotFocus", multiplier = 1 },
            -- Field families 08-17. "Improved <defense skill> N" rides the matching
            -- skill line; "Ferocity N" is the double/triple-attack worn line (its own
            -- description says so); "Cleave N - 150" keeps a trailing rating after the
            -- tier, so that pattern is deliberately not end-anchored.
            { pattern = "^Improved Dodge ([IVXLC%d]+)$",   line = "dodge", multiplier = 1 },
            { pattern = "^Improved Parry ([IVXLC%d]+)$",   line = "parry", multiplier = 1 },
            { pattern = "^Improved Riposte ([IVXLC%d]+)$", line = "riposte", multiplier = 1 },
            { pattern = "^Improved Block ([IVXLC%d]+)$",   line = "block", multiplier = 1 },
            { pattern = "^Ferocity ([IVXLC%d]+)$",         line = "doubleAttack", multiplier = 1 },
            { pattern = "^Cleave ([IVXLC%d]+)",            line = "cleave", multiplier = 1 },
            { pattern = "^Improve All Damage ([IVXLC%d]+)$",  line = "improvedDamage", multiplier = 1 },
            { pattern = "^Improved Damage ([IVXLC%d]+)$",     line = "improvedDamage", multiplier = 1 },
            { pattern = "^Improve All Healing ([IVXLC%d]+)$", line = "improvedHealing", multiplier = 1 },
            { pattern = "^Improved Healing ([IVXLC%d]+)$",    line = "improvedHealing", multiplier = 1 },
            { pattern = "^Detrimental Haste ([%d]+)",      line = "castHaste", multiplier = 1 },
            { pattern = "^Beneficial Haste ([%d]+)",       line = "castHaste", multiplier = 1 },
        },
    },
}
