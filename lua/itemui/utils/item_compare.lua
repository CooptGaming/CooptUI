--[[
    item_compare.lua — Pure comparison engine for the Item Display verdict card (design
    pass 3e, extended by the windows pass 18a: type-aware strip, aug-inclusive totals,
    heroic rank).

    PURE MODULE: no ImGui, no TLO, no requires beyond stdlib and the pure-DATA weight
    table (utils/score_weights.lua - it executes nothing). Callers (item_display.lua)
    resolve `item` and `equipped` as plain tables and are responsible for making sure the
    numeric fields this module reads are already loaded — buildItemFromMQ's stat fields are
    lazy behind a metatable, so a caller that hasn't forced e.g. `local _ = item.ac` first
    will still work (this module just sees whatever the table already holds), but reading a
    field for the first time from in here would silently do nothing since this module never
    touches item.bag/slot/source at all.

    AUG-INCLUSIVE TOTALS (§0.1 resolution): the old card compared bare-item fields while
    the stat dump below it showed item+augs — same table, two formulas, the 1493-vs-1764
    confusion. compare() now takes opts.augStats / opts.equippedAugStats (the summed socket
    contributions tooltip_data already computes and caches) and every row value, delta,
    verdict and summary is computed on the SAME quantity: what the item delivers as-is,
    augs included. Callers that pass no opts get bare-vs-bare, exactly the old behaviour.

    TYPE-AWARE STRIP (18a): a weapon (damage>0 and itemDelay>0) gets the cells that decide
    a weapon — dmg, delay, ratio, dps, proc, attack, hp, heroic. Everything else gets the
    general set — hp, mana, endurance, ac, haste, regen, augs, heroic (augs omitted for
    augment-type items: they have no sockets). The last cell is always HEROIC, the rank —
    the summed primary heroics — and it renders as "—" when zero (kit rule: zero is —),
    which the zeroAsDash flag tells the view.

    Row flags the view must honour:
      betterWhenLower  delay: a negative delta is the good direction (green).
      isFloat          ratio: format deltas %+.1f, not %+d.
      isText           proc: value is a name; note carries "rate N"; no delta ever.
      zeroAsDash       heroic: render a 0 value as "—", never "0".
      isRatio          augs: "2/5" string, no delta (pre-existing).
]]

local M = {}

-- The general strip (jewelry/armor/anything non-weapon), in display order.
local GENERAL_ORDER = {
    { key = "hp",        label = "HP" },
    { key = "mana",      label = "Mana" },
    { key = "endurance", label = "End" },
    { key = "ac",        label = "AC" },
    { key = "haste",     label = "Haste", suffix = "%" },
    { key = "hpRegen",   label = "Regen" },
}

-- The weapon strip. delay's good direction is DOWN; ratio/dps are computed, not fields.
local WEAPON_ORDER = {
    { key = "damage",    label = "Dmg" },
    { key = "itemDelay", label = "Delay", betterWhenLower = true },
    -- ratio, dps, proc are inserted by buildWeaponRows
    { key = "attack",    label = "Attack" },
    { key = "hp",        label = "HP" },
}

-- Stats that count toward the non-weapon verdict score. Haste breaks 0 ties only.
local VERDICT_KEYS = { "hp", "ac", "attack", "mana" }

-- The heroic rank sums the seven primary heroics (resist-heroics deliberately excluded —
-- they'd swamp the rank on resist gear without saying anything about power).
local HEROIC_KEYS = { "heroicSTR", "heroicSTA", "heroicAGI", "heroicDEX", "heroicINT",
                      "heroicWIS", "heroicCHA" }

local function toNum(v)
    return tonumber(v)
end

--- Effective (aug-inclusive) value of one field: table value + summed socket contribution.
local function effVal(tbl, aug, key)
    local base = (tbl and toNum(tbl[key])) or 0
    local extra = (aug and toNum(aug[key])) or 0
    return base + extra
end

local function heroicRank(tbl, aug)
    if not tbl then return 0 end
    local sum = 0
    for _, k in ipairs(HEROIC_KEYS) do
        sum = sum + effVal(tbl, aug, k)
    end
    return sum
end

--- True when the table describes a weapon: it swings (damage and delay both non-zero).
local function isWeapon(tbl, aug)
    return effVal(tbl, aug, "damage") > 0 and effVal(tbl, aug, "itemDelay") > 0
end

local function pushRow(rows, spec, iv, ev, hasEquipped)
    if iv ~= 0 or ev ~= 0 then
        local delta = hasEquipped and (iv - ev) or nil
        rows[#rows + 1] = {
            key = spec.key, label = spec.label, value = iv, delta = delta,
            suffix = spec.suffix, betterWhenLower = spec.betterWhenLower,
            isFloat = spec.isFloat,
        }
    end
end

--- The general strip rows. A row is included only when at least one side has a non-zero
--- value (buildItemFromMQ defaults stat fields to 0, not nil, so a nil-check alone would
--- put an "HP 0" tile on every item); value is always the candidate's own (aug-inclusive)
--- number, 0 when only the equipped side has the stat, so the row still lines up.
local function buildGeneralRows(item, equipped, itemAug, eqAug)
    local rows = {}
    local hasEquipped = equipped ~= nil
    for _, spec in ipairs(GENERAL_ORDER) do
        pushRow(rows, spec,
            effVal(item, itemAug, spec.key),
            hasEquipped and effVal(equipped, eqAug, spec.key) or 0,
            hasEquipped)
    end
    return rows, hasEquipped
end

local function round1(x)
    return math.floor(x * 10 + 0.5) / 10
end

--- The weapon strip rows: dmg, delay, ratio (dmg/delay), dps (ratio×10), proc, attack, hp.
--- ratio/dps deltas exist only when the equipped side is also a weapon — a sword against
--- an empty hand has nothing honest to be a ratio delta against.
local function buildWeaponRows(item, equipped, itemAug, eqAug, opts)
    local rows = {}
    local hasEquipped = equipped ~= nil
    local eqIsWeapon = hasEquipped and isWeapon(equipped, eqAug)

    local iDmg, iDel = effVal(item, itemAug, "damage"), effVal(item, itemAug, "itemDelay")
    local eDmg, eDel = 0, 0
    if eqIsWeapon then
        eDmg, eDel = effVal(equipped, eqAug, "damage"), effVal(equipped, eqAug, "itemDelay")
    end

    pushRow(rows, WEAPON_ORDER[1], iDmg, eDmg, hasEquipped)
    pushRow(rows, WEAPON_ORDER[2], iDel, eDel, hasEquipped and eqIsWeapon)

    local iRatio = (iDel > 0) and round1(iDmg / iDel) or 0
    local eRatio = (eDel > 0) and round1(eDmg / eDel) or 0
    rows[#rows + 1] = {
        key = "ratio", label = "Ratio", value = iRatio,
        delta = eqIsWeapon and round1(iRatio - eRatio) or nil, isFloat = true,
    }
    rows[#rows + 1] = {
        key = "dps", label = "DPS", value = math.floor(iRatio * 10 + 0.5),
        delta = eqIsWeapon and (math.floor(iRatio * 10 + 0.5) - math.floor(eRatio * 10 + 0.5)) or nil,
    }

    if opts and opts.procName and opts.procName ~= "" then
        rows[#rows + 1] = {
            key = "proc", label = "Proc", value = tostring(opts.procName), isText = true,
            note = opts.procRate and ("rate " .. tostring(opts.procRate)) or nil,
        }
    end

    pushRow(rows, WEAPON_ORDER[3], effVal(item, itemAug, "attack"),
        hasEquipped and effVal(equipped, eqAug, "attack") or 0, hasEquipped)
    pushRow(rows, WEAPON_ORDER[4], effVal(item, itemAug, "hp"),
        hasEquipped and effVal(equipped, eqAug, "hp") or 0, hasEquipped)
    return rows, hasEquipped
end

--- Append the Augs filled/total row when the item carries augsTotal > 0. Filled-slot
--- counting needs a live TLO walk only the view layer can do — item_display.lua attaches
--- item.augsFilled/item.augsTotal before calling M.compare.
local function appendAugsRow(rows, item)
    local total = item and toNum(item.augsTotal)
    if not total or total <= 0 then return end
    local filled = (item and toNum(item.augsFilled)) or 0
    rows[#rows + 1] = {
        key = "augs", label = "Augs",
        value = string.format("%d/%d", filled, total),
        delta = nil, isRatio = true,
    }
end

--- The rank cell, always last (18a: "the last one is the rank"). Always included —
--- zeroAsDash makes an all-zero rank render as "—" instead of vanishing or reading "0".
local function appendHeroicRow(rows, item, equipped, itemAug, eqAug, hasEquipped)
    local iv = heroicRank(item, itemAug)
    local ev = hasEquipped and heroicRank(equipped, eqAug) or 0
    rows[#rows + 1] = {
        key = "heroic", label = "Heroic", value = iv,
        delta = hasEquipped and (iv - ev) or nil,
        zeroAsDash = true,
    }
end

--- Non-weapon verdict: sum the four primary deltas; haste breaks a 0 tie. Deliberately
--- unweighted (an AC point counts like an HP point) — M.scoreForClass is where real
--- weighting is meant to land. Computed from VALUES, not from the visible rows: the
--- general strip no longer shows an Attack tile (18a), but an attack delta still counts.
local function scoreVerdict(item, equipped, itemAug, eqAug)
    local score = 0
    for _, key in ipairs(VERDICT_KEYS) do
        score = score + (effVal(item, itemAug, key) - effVal(equipped, eqAug, key))
    end
    if score > 0 then return "upgrade" end
    if score < 0 then return "downgrade" end
    local hasteDelta = effVal(item, itemAug, "haste") - effVal(equipped, eqAug, "haste")
    if hasteDelta > 0 then return "upgrade" end
    if hasteDelta < 0 then return "downgrade" end
    return "sidegrade"
end

--- Weapon verdict: DPS decides — it is what a weapon is for. Equal DPS falls through to
--- the stat sum so two same-speed swords still rank by their rider stats.
local function scoreWeaponVerdict(rows, item, equipped, itemAug, eqAug)
    for _, r in ipairs(rows) do
        if r.key == "dps" and r.delta and r.delta ~= 0 then
            return r.delta > 0 and "upgrade" or "downgrade"
        end
    end
    return scoreVerdict(item, equipped, itemAug, eqAug)
end

--- Top-3 non-zero deltas by magnitude (stable on ties), heroic appended when it moved:
--- "+48 Dmg -3 Delay +1.7 Ratio +8 Heroic". Text/ratio-display rows never contribute.
local function buildSummary(rows)
    local candidates = {}
    local heroicRow = nil
    for i, r in ipairs(rows) do
        if r.key == "heroic" then
            heroicRow = r
        elseif r.delta and r.delta ~= 0 then
            candidates[#candidates + 1] = { row = r, order = i }
        end
    end
    table.sort(candidates, function(a, b)
        local am, bm = math.abs(a.row.delta), math.abs(b.row.delta)
        if am ~= bm then return am > bm end
        return a.order < b.order
    end)
    local parts = {}
    for i = 1, math.min(3, #candidates) do
        local r = candidates[i].row
        if r.isFloat then
            parts[#parts + 1] = string.format("%+.1f%s %s", r.delta, r.suffix or "", r.label)
        else
            parts[#parts + 1] = string.format("%+d%s %s", r.delta, r.suffix or "", r.label)
        end
    end
    if heroicRow and heroicRow.delta and heroicRow.delta ~= 0 then
        parts[#parts + 1] = string.format("%+d Heroic", heroicRow.delta)
    end
    return table.concat(parts, " ")
end

--- M.compare(item, equipped, opts) -> { rows, verdict, summary, strip }
---   rows    ordered tiles {key, label, value, delta, suffix, flags…} for the grid.
---   verdict "upgrade" | "downgrade" | "sidegrade" | "none" (nil equipped = "none").
---   summary top-3-by-magnitude signed delta string (+ heroic when it moved).
---   strip   "weapon" | "general" — which cell set was chosen.
---   opts    optional: augStats / equippedAugStats (summed socket stats — makes every
---           number aug-inclusive), procName / procRate (weapon proc cell).
--- Nil-safe: item/equipped/opts may be nil, and any field on any of them may be missing.
function M.compare(item, equipped, opts)
    opts = opts or {}
    local itemAug = opts.augStats
    local eqAug = opts.equippedAugStats

    local rows, hasEquipped, strip
    if isWeapon(item, itemAug) then
        strip = "weapon"
        rows, hasEquipped = buildWeaponRows(item, equipped, itemAug, eqAug, opts)
    else
        strip = "general"
        rows, hasEquipped = buildGeneralRows(item, equipped, itemAug, eqAug)
        local itemType = item and tostring(item.type or ""):match("^%s*(.-)%s*$") or ""
        if itemType ~= "Augmentation" then
            appendAugsRow(rows, item)
        end
    end
    appendHeroicRow(rows, item, equipped, itemAug, eqAug, hasEquipped)

    local verdict
    if not hasEquipped then
        verdict = "none"
    elseif strip == "weapon" then
        verdict = scoreWeaponVerdict(rows, item, equipped, itemAug, eqAug)
    else
        verdict = scoreVerdict(item, equipped, itemAug, eqAug)
    end
    local summary = hasEquipped and buildSummary(rows) or ""
    return { rows = rows, verdict = verdict, summary = summary, strip = strip }
end

-- ===========================================================================
-- scoreForClass — the UPGRADE_SCORE model (2026-08-04). One absolute HP-equivalent
-- number for "how good is this item for <class>", weights and effect families all
-- DATA in utils/score_weights.lua so new field intel is a table edit, not a build.
-- Absolute, not delta (the stub's original rule): candidates rank against each
-- other; upgrade detection compares two absolute scores; the verdict card's delta
-- math above stays separate and unweighted.
-- ===========================================================================

local weights = require('itemui.utils.score_weights')

local RESIST_KEYS = { "svMagic", "svFire", "svCold", "svPoison", "svDisease", "svCorruption" }

-- "VIII" / "IX" / "12" -> number. Ranked effect names carry magnitude as digits or
-- roman numerals; both price the same way.
local ROMAN = { I = 1, V = 5, X = 10, L = 50, C = 100 }
local function parseUnits(s)
    if not s or s == "" then return nil end
    local n = tonumber(s)
    if n then return n end
    local total, prev = 0, 0
    for i = #s, 1, -1 do
        local v = ROMAN[s:sub(i, i)]
        if not v then return nil end
        if v < prev then total = total - v else total = total + v; prev = v end
    end
    if total > 0 then return total end
    return nil
end

--- Class -> merged weight set. classOverrides carry only the keys that differ and
--- deep-merge over the archetype (stats/heroics/clickies key-wise, scalars replace).
local function resolveWeights(classShortName)
    local cls = tostring(classShortName or ""):upper()
    local archName = weights.classes[cls]
    local arch = archName and weights.archetypes[archName]
    if not arch then return nil end
    local over = weights.classOverrides and weights.classOverrides[cls]
    if not over then return arch, archName end
    local merged = {
        stats = {}, heroics = {}, clickies = {},
        dps = over.dps or arch.dps,
        resist = over.resist or arch.resist,
    }
    for _, part in ipairs({ "stats", "heroics", "clickies" }) do
        for k, v in pairs(arch[part] or {}) do merged[part][k] = v end
        for k, v in pairs(over[part] or {}) do merged[part][k] = v end
    end
    return merged, archName
end

--- Resolve an effect NAME to its scored family: -> line, units, stacking | "clicky",
--- family | nil when unrecognized. Public because the set-aware consumers need it too:
--- the upgrade walk builds its worn-lines context from equipped effect names, and the
--- Aug Utility prints "dodge already worn (higher)" by asking the same question the
--- scorer asks.
function M.resolveEffectLine(name)
    if not name or name == "" then return nil end
    local eff = weights.effects.byName[name]
    if eff then
        if eff.clicky then return "clicky", eff.clicky, nil end
        local spec = weights.effects.lines[eff.line]
        return eff.line, eff.value or 1, spec and spec.stacking or nil
    end
    for _, p in ipairs(weights.effects.patterns) do
        local cap = name:match(p.pattern)
        if cap then
            local n = parseUnits(cap)
            if n then
                local line = p.line
                local spec = weights.effects.lines[line]
                return line, n * (p.multiplier or 1), spec and spec.stacking or nil
            end
        end
    end
    return nil
end

--- One effect name -> HP-eq, or nil when unrecognized (the caller LISTS those as
--- unscored - an honest zero beats a wrong guess, and the unscored list is how new
--- names get found and added to the data table).
--- Stacking is applied against opts.context:
---   highest:         context.wornLines[line] >= units -> 0 (a better or equal copy
---                    of the line is already worn - or supplied by a buff/set bonus;
---                    the context does not care where the best copy lives).
---   additive_capped: scores only min(units, cap - context.lineUsed[line]).
---   additive:        always full.
--- No context = raw item score (candidates ranking against each other).
local function scoreEffectName(name, archName, W, context)
    local line, units = M.resolveEffectLine(name)
    if line == "clicky" then
        return (W.clickies and W.clickies[units]) or 0
    end
    if not line then return nil end
    local spec = weights.effects.lines[line]
    if not spec then return nil end
    local usable = units
    if spec.stacking == "highest" then
        local best = context and context.wornLines and context.wornLines[line]
        if best and best >= units then usable = 0 end
    elseif spec.stacking == "additive_capped" and spec.cap then
        local used = (context and context.lineUsed and context.lineUsed[line]) or 0
        local headroom = spec.cap - used
        if headroom < 0 then headroom = 0 end
        if usable > headroom then usable = headroom end
    end
    if usable <= 0 then return 0 end
    if spec.stat then
        return usable * ((W.stats and W.stats[spec.stat]) or 0)
    elseif spec.perUnit then
        return usable * (spec.perUnit[archName] or 0)
    elseif spec.flat then
        return usable * (spec.flat[archName] or 0)
    end
    return 0
end

--- M.scoreForClass(item, classShortName, opts) -> total, breakdown | nil
--- One absolute HP-equivalent score for ranking candidates. nil for a nil item or a
--- class no table knows (the old stub's contract for garbage input).
---   opts.augStats   summed socket stats - same aug-inclusive quantity compare() uses.
---   opts.effects    array of effect names (or {name=...} tables) - worn/focus/clicky
---                   names as the tooltip layer surfaces them (EFFECT_KEYS order).
---   opts.procName / opts.procRate  the weapon proc: a recognized name scores via its
---                   family; otherwise a damage-class proc prices at
---                   procRate x W.dps x procDpsFactor; a rateless unknown is unscored.
---   opts.context    set-awareness for upgrade detection: wornLines[line]=best worn
---                   units, lineUsed[line]=cap units consumed, statUsed[stat]=current
---                   total for capped stats (shielding). Omit for raw ranking.
--- breakdown = { archetype, stats, heroics, dps, effects, resists, unscored={names} }
--- - the calibration pass reads it, and any surface must print the unscored list
--- rather than pretend those effects are worth 0 by judgment.
function M.scoreForClass(item, classShortName, opts)
    if not item then return nil end
    local W, archName = resolveWeights(classShortName)
    if not W then return nil end
    opts = opts or {}
    local aug = opts.augStats
    local context = opts.context
    local b = { archetype = archName, stats = 0, heroics = 0, dps = 0, effects = 0,
                resists = 0, unscored = {} }

    for key, w in pairs(W.stats or {}) do
        if w ~= 0 then
            local v = effVal(item, aug, key)
            if v ~= 0 then
                local cap = weights.statCaps and weights.statCaps[key]
                local used = cap and context and context.statUsed and context.statUsed[key]
                if cap and used then
                    local headroom = cap - used
                    if headroom < 0 then headroom = 0 end
                    if v > headroom then v = headroom end
                end
                b.stats = b.stats + v * w
            end
        end
    end
    for key, w in pairs(W.heroics or {}) do
        if w ~= 0 then
            b.heroics = b.heroics + effVal(item, aug, key) * w
        end
    end
    local rw = W.resist or 0
    if rw ~= 0 then
        for _, key in ipairs(RESIST_KEYS) do
            b.resists = b.resists + effVal(item, aug, key) * rw
        end
    end
    if isWeapon(item, aug) then
        local dmg, del = effVal(item, aug, "damage"), effVal(item, aug, "itemDelay")
        b.dps = math.floor((dmg / del) * 10 + 0.5) * (W.dps or 0)
    end
    if opts.procName and opts.procName ~= "" then
        local hpEq = scoreEffectName(tostring(opts.procName), archName, W, context)
        if hpEq ~= nil then
            b.effects = b.effects + hpEq
        else
            local rate = tonumber(opts.procRate)
            if rate and rate > 0 then
                b.effects = b.effects + rate * (W.dps or 0) * (weights.procDpsFactor or 0.5)
            else
                b.unscored[#b.unscored + 1] = tostring(opts.procName)
            end
        end
    end
    for _, e in ipairs(opts.effects or {}) do
        local name = (type(e) == "table") and e.name or e
        if name and name ~= "" then
            local hpEq = scoreEffectName(tostring(name), archName, W, context)
            if hpEq ~= nil then
                b.effects = b.effects + hpEq
            else
                b.unscored[#b.unscored + 1] = tostring(name)
            end
        end
    end

    local total = b.stats + b.heroics + b.dps + b.effects + b.resists
    return total, b
end

return M
