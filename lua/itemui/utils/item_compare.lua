--[[
    item_compare.lua — Pure comparison engine for the Item Display "verdict" card (design
    pass 3e/10e(d): lead with a verdict, then the detail).

    PURE MODULE: no ImGui, no TLO, no requires beyond stdlib. Callers (item_display.lua) resolve
    `item` and `equipped` as plain tables and are responsible for making sure the numeric fields
    this module reads are already loaded — buildItemFromMQ's stat fields are lazy behind a
    metatable, so a caller that hasn't forced e.g. `local _ = item.ac` first will still work
    (this module just sees whatever the table already holds), but reading a field for the first
    time from in here would silently do nothing since this module never touches item.bag/slot/
    source at all. Item Display already prewarms both sides before calling M.compare (equipment
    probes prewarm themselves — see getItemStatsForTooltipRef in app.lua).
]]

local M = {}

-- Display order for the stat tile row: hp, ac, mana, haste, attack. Augs (filled/total) is
-- appended after these five as a 6th, non-delta tile — see appendAugsRow below.
local STAT_ORDER = {
    { key = "hp",     label = "HP" },
    { key = "ac",     label = "AC" },
    { key = "mana",   label = "Mana" },
    { key = "haste",  label = "Haste", suffix = "%" },
    { key = "attack", label = "Attack" },
}

-- Stats that count toward the upgrade/downgrade verdict score. Haste is deliberately excluded
-- from the score itself and used only to break a 0 score tie (see scoreVerdict).
local VERDICT_KEYS = { "hp", "ac", "attack", "mana" }

local function toNum(v)
    return tonumber(v)
end

--- Build the ordered stat rows: {key, label, value, delta, suffix}. A row is included only
--- when at least one side has a NON-ZERO value for that stat (buildItemFromMQ defaults every
--- stat field to 0, not nil, so a nil-check alone would put an "HP 0" tile on every item).
--- delta is nil whenever there is no equipped item to compare against; value is always the
--- candidate item's own stat (0 when absent but the equipped counterpart is non-zero, so the
--- row still lines up against a real delta).
local function buildStatRows(item, equipped)
    local rows = {}
    local hasEquipped = equipped ~= nil
    for _, spec in ipairs(STAT_ORDER) do
        local itemVal = item and toNum(item[spec.key])
        local eqVal = hasEquipped and toNum(equipped[spec.key]) or nil
        local iv = itemVal or 0
        local ev = eqVal or 0
        if iv ~= 0 or ev ~= 0 then
            local delta = hasEquipped and (iv - ev) or nil
            rows[#rows + 1] = { key = spec.key, label = spec.label, value = iv, delta = delta, suffix = spec.suffix }
        end
    end
    return rows, hasEquipped
end

--- Append the Augs filled/total row when the item carries augsTotal > 0. Filled-slot counting
--- needs a live TLO walk (which stat, is it slot's augType filled) that only the view layer can
--- do — item_display.lua attaches item.augsFilled/item.augsTotal before calling M.compare; this
--- module only ever reads plain numbers off the tables it's handed.
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

--- Score the four primary stats (hp, ac, attack, mana) by summing their raw deltas; haste only
--- breaks a 0 score tie. This is a deliberately simple heuristic (no per-point weighting, e.g.
--- an AC point and an HP point count the same) — see M.scoreForClass below for where a real,
--- class-aware weighting is meant to land later. Returns "upgrade" | "downgrade" | "sidegrade".
local function scoreVerdict(rows)
    local rowByKey = {}
    for _, r in ipairs(rows) do rowByKey[r.key] = r end
    local score = 0
    for _, key in ipairs(VERDICT_KEYS) do
        local r = rowByKey[key]
        if r and r.delta then score = score + r.delta end
    end
    if score > 0 then return "upgrade" end
    if score < 0 then return "downgrade" end
    local hasteRow = rowByKey.haste
    local hasteDelta = (hasteRow and hasteRow.delta) or 0
    if hasteDelta > 0 then return "upgrade" end
    if hasteDelta < 0 then return "downgrade" end
    return "sidegrade"
end

--- Top-3 non-zero deltas by magnitude, signed: "+412 HP +18 AC -6 Mana". Ties keep stat-row
--- order (stable sort) so output is deterministic. Augs never contributes (isRatio rows carry
--- no delta).
local function buildSummary(rows)
    local candidates = {}
    for i, r in ipairs(rows) do
        if r.delta and r.delta ~= 0 then
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
        parts[#parts + 1] = string.format("%+d%s %s", r.delta, r.suffix or "", r.label)
    end
    return table.concat(parts, " ")
end

--- M.compare(item, equipped) -> { rows, verdict, summary }
---   rows    ordered {key, label, value, delta, suffix, isRatio} for the tile grid.
---   verdict "upgrade" | "downgrade" | "sidegrade" | "none" (nil equipped = "none").
---   summary top-3-by-magnitude signed delta string ("" when there's nothing to compare, or
---           every shared stat is unchanged).
--- Nil-safe: item and/or equipped may be nil, and any field on either may be nil/missing.
function M.compare(item, equipped)
    local rows, hasEquipped = buildStatRows(item, equipped)
    appendAugsRow(rows, item)
    local verdict = hasEquipped and scoreVerdict(rows) or "none"
    local summary = hasEquipped and buildSummary(rows) or ""
    return { rows = rows, verdict = verdict, summary = summary }
end

--[[
    STUB — future class-aware item score (not implemented; M.scoreForClass always returns nil).

    M.scoreForClass(item, classShortName) is meant to eventually return a single normalized
    "how good is this item for <class>" number so the verdict box (and any future gear-optimizer
    tooling) can rank candidates without needing a specific equipped comparison item.

    Intended design:
      - Reuse buildStatRows' normalized stat rows (hp/ac/mana/haste/attack, plus whichever
        secondary stats get added later) as the substrate. The work this module already does —
        pulling comparable numbers off two item tables into a flat, ordered row list — is exactly
        the shape a scorer needs; it only has to add per-class weights over those same rows.
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
