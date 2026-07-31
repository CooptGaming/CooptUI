--[[
    item_compare.lua — Pure comparison engine for the Item Display verdict card (design
    pass 3e, extended by the windows pass 18a: type-aware strip, aug-inclusive totals,
    heroic rank).

    PURE MODULE: no ImGui, no TLO, no requires beyond stdlib. Callers (item_display.lua)
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

--[[
    STUB — future class-aware item score (not implemented; M.scoreForClass always returns nil).

    M.scoreForClass(item, classShortName) is meant to eventually return a single normalized
    "how good is this item for <class>" number so the verdict box (and any future gear-optimizer
    tooling) can rank candidates without needing a specific equipped comparison item.

    Intended design:
      - Reuse the normalized stat rows (general + weapon cell sets above) as the substrate. The
        work this module already does — pulling comparable numbers off two item tables into a
        flat, ordered row list — is exactly the shape a scorer needs; it only has to add
        per-class weights over those same rows.
      - Maintain a per-class weight table keyed by the class short names ItemUI already uses
        elsewhere (see ConfigFilters.classLabel callers), e.g.
            WAR = { ac = 4, hp = 2, attack = 2, mana = 0, haste = 1 },
            CLR = { mana = 3, hp = 2, ac = 1, attack = 0, haste = 0 },
        one entry per playable class.
      - score = sum(weight[row.key] * row.value) over the ITEM's own rows (not deltas — this is
        an absolute score for ranking candidates against each other, independent of what's
        currently equipped; the verdict box's delta-based upgrade/downgrade math stays separate).
      - Class weights are a content/balance decision (what a Paladin needs vs. what a Wizard
        needs) and are deliberately deferred; this stub only reserves the call shape so a future
        pass can fill it in without reworking the row-extraction plumbing above.
]]
function M.scoreForClass(item, classShortName)
    return nil
end

return M
