--[[
    test_item_compare.lua — headless suite for utils/item_compare.lua.

    Pure module (no ImGui, no TLO, no requires beyond stdlib) — no stubs needed at all, just
    require and call. Verifies upgrade/downgrade/sidegrade/none verdicts, summary formatting +
    top-3 selection, nil-field tolerance, the augs row, and empty-vs-empty.

    Run:  COOPT_REPO=C:/Claude/CooptUI <luajit> scripts/tests/test_item_compare.lua
]]

local repo = os.getenv('COOPT_REPO') or 'C:/Claude/CooptUI'
package.path = repo .. '/lua/?.lua;' .. repo .. '/lua/?/init.lua;' .. package.path

local pass, fail = 0, 0
local function check(name, cond, extra)
    if cond then pass = pass + 1; print('PASS: ' .. name)
    else fail = fail + 1; print('FAIL: ' .. name .. '  -> ' .. tostring(extra)) end
end

local ItemCompare = require('itemui.utils.item_compare')

--- Find a row by key in a compare() result's rows list, or nil.
local function rowByKey(rows, key)
    for _, r in ipairs(rows) do
        if r.key == key then return r end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- 1. nil equipped -> verdict "none"; item's own non-zero stats still show (no delta).
-- ---------------------------------------------------------------------------
do
    local item = { hp = 1764, ac = 123, mana = 0, haste = 0, attack = 14 }
    local result = ItemCompare.compare(item, nil)
    check('nil equipped -> verdict none', result.verdict == 'none', result.verdict)
    check('nil equipped -> summary empty', result.summary == '', result.summary)
    local hpRow = rowByKey(result.rows, 'hp')
    check('nil equipped -> hp row present with item value', hpRow and hpRow.value == 1764, hpRow and hpRow.value)
    check('nil equipped -> hp row delta nil', hpRow and hpRow.delta == nil, hpRow and hpRow.delta)
    local acRow = rowByKey(result.rows, 'ac')
    check('nil equipped -> ac row present', acRow and acRow.value == 123, acRow and acRow.value)
    -- mana and haste are 0 on the item and there's no equipped counterpart -> not "present".
    check('nil equipped -> zero mana row omitted', rowByKey(result.rows, 'mana') == nil)
    check('nil equipped -> zero haste row omitted', rowByKey(result.rows, 'haste') == nil)
end

-- ---------------------------------------------------------------------------
-- 2. Upgrade: matches the design mock's own numbers (HP 1764 +412, AC 123 +18, Mana 1077 -6,
--    Haste 9% =, Attack 14 +3) -> verdict upgrade, summary picks the top 3 by magnitude.
-- ---------------------------------------------------------------------------
do
    local item     = { hp = 1764, ac = 123, mana = 1077, haste = 9, attack = 14 }
    local equipped = { hp = 1352, ac = 105, mana = 1083, haste = 9, attack = 11 }
    local result = ItemCompare.compare(item, equipped)
    check('upgrade verdict', result.verdict == 'upgrade', result.verdict)
    check('upgrade summary top-3 by magnitude', result.summary == '+412 HP +18 AC -6 Mana', result.summary)
    local hasteRow = rowByKey(result.rows, 'haste')
    check('haste delta is zero (=)', hasteRow and hasteRow.delta == 0, hasteRow and hasteRow.delta)
    -- 18a: the general strip has no Attack tile — but attack still scores the verdict
    -- (asserted separately below).
    check('attack row absent from general strip', rowByKey(result.rows, 'attack') == nil)
    local manaRow = rowByKey(result.rows, 'mana')
    check('mana delta is -6', manaRow and manaRow.delta == -6, manaRow and manaRow.delta)
end

-- ---------------------------------------------------------------------------
-- 3. Downgrade: every primary stat worse.
-- ---------------------------------------------------------------------------
do
    local item     = { hp = 900, ac = 80, mana = 500, attack = 8 }
    local equipped = { hp = 1200, ac = 110, mana = 600, attack = 12 }
    local result = ItemCompare.compare(item, equipped)
    check('downgrade verdict', result.verdict == 'downgrade', result.verdict)
    check('downgrade summary signed correctly', result.summary:find('-300 HP', 1, true) ~= nil, result.summary)
end

-- ---------------------------------------------------------------------------
-- 4. Sidegrade: all deltas exactly zero (identical stats).
-- ---------------------------------------------------------------------------
do
    local item     = { hp = 500, ac = 50, mana = 200, haste = 5, attack = 6 }
    local equipped = { hp = 500, ac = 50, mana = 200, haste = 5, attack = 6 }
    local result = ItemCompare.compare(item, equipped)
    check('all-equal-stats -> sidegrade', result.verdict == 'sidegrade', result.verdict)
    check('all-equal-stats -> empty summary', result.summary == '', result.summary)
end

-- ---------------------------------------------------------------------------
-- 5. Sidegrade via haste tiebreak: primary-stat score sums to 0 but not every row is 0, and
--    haste itself is also 0 -> still sidegrade (no tiebreak signal either).
-- ---------------------------------------------------------------------------
do
    -- Clean 0-sum case: +50 hp, -50 ac (VERDICT_KEYS are hp, ac, attack, mana), mana/attack flat.
    local item     = { hp = 550, ac = 50, mana = 100, haste = 5, attack = 10 }
    local equipped = { hp = 500, ac = 100, mana = 100, haste = 5, attack = 10 }
    local result = ItemCompare.compare(item, equipped)
    -- hp delta +50, ac delta -50 -> score 0; haste delta 0 -> sidegrade.
    check('balanced-to-zero score with zero haste -> sidegrade', result.verdict == 'sidegrade', result.verdict)
end

-- ---------------------------------------------------------------------------
-- 6. Haste tiebreak actually breaks a 0 score.
-- ---------------------------------------------------------------------------
do
    local item     = { hp = 550, ac = 50, mana = 100, haste = 10, attack = 10 }
    local equipped = { hp = 500, ac = 100, mana = 100, haste = 5, attack = 10 }
    local result = ItemCompare.compare(item, equipped)
    check('0 score + positive haste delta -> upgrade', result.verdict == 'upgrade', result.verdict)

    local item2     = { hp = 550, ac = 50, mana = 100, haste = 2, attack = 10 }
    local result2 = ItemCompare.compare(item2, equipped)
    check('0 score + negative haste delta -> downgrade', result2.verdict == 'downgrade', result2.verdict)
end

-- ---------------------------------------------------------------------------
-- 7. Augs row: present only when item.augsTotal > 0; formatted "filled/total"; never
--    contributes a delta or a summary entry.
-- ---------------------------------------------------------------------------
do
    local item = { hp = 100, augsTotal = 3, augsFilled = 2 }
    local result = ItemCompare.compare(item, { hp = 50 })
    local augsRow = rowByKey(result.rows, 'augs')
    check('augs row present with augsTotal > 0', augsRow ~= nil, result.rows)
    check('augs row formatted filled/total', augsRow and augsRow.value == '2/3', augsRow and augsRow.value)
    check('augs row has no delta', augsRow and augsRow.delta == nil, augsRow and augsRow.delta)
    check('augs row marked isRatio', augsRow and augsRow.isRatio == true, augsRow and augsRow.isRatio)
    check('augs never appears in summary', not result.summary:find('Augs', 1, true), result.summary)

    local itemNoAugs = { hp = 100 }
    local result2 = ItemCompare.compare(itemNoAugs, { hp = 50 })
    check('no augsTotal -> no augs row', rowByKey(result2.rows, 'augs') == nil)

    local itemZeroAugs = { hp = 100, augsTotal = 0, augsFilled = 0 }
    local result3 = ItemCompare.compare(itemZeroAugs, { hp = 50 })
    check('augsTotal == 0 -> no augs row', rowByKey(result3.rows, 'augs') == nil)
end

-- ---------------------------------------------------------------------------
-- 8. Nil-field tolerance: sparse tables, unknown keys, non-numeric junk -- must never error.
-- ---------------------------------------------------------------------------
do
    local ok1, result1 = pcall(ItemCompare.compare, {}, {})
    check('empty-vs-empty does not error', ok1, result1)
    -- The heroic rank cell is always last and always present (18a); zero renders as "—".
    check('empty-vs-empty -> only the heroic rank row', ok1 and #result1.rows == 1
        and result1.rows[1].key == 'heroic' and result1.rows[1].zeroAsDash == true
        and result1.rows[1].value == 0, ok1 and #result1.rows)
    check('empty-vs-empty -> sidegrade (both present, all zero)', ok1 and result1.verdict == 'sidegrade', ok1 and result1.verdict)

    local ok2, result2 = pcall(ItemCompare.compare, nil, nil)
    check('nil item and nil equipped does not error', ok2, result2)
    check('nil item and nil equipped -> verdict none', ok2 and result2.verdict == 'none', ok2 and result2.verdict)
    check('nil item and nil equipped -> only the heroic rank row', ok2 and #result2.rows == 1
        and result2.rows[1].key == 'heroic', ok2 and #result2.rows)

    local ok3, result3 = pcall(ItemCompare.compare, { hp = 'not a number', ac = 50 }, { hp = 10 })
    check('non-numeric stat field does not error', ok3, result3)
    local acRow = ok3 and rowByKey(result3.rows, 'ac')
    check('non-numeric hp is ignored, ac still works', acRow and acRow.value == 50, acRow)

    local ok4 = pcall(ItemCompare.compare, "not a table", { hp = 10 })
    check('non-table item does not error', ok4)
end

-- ---------------------------------------------------------------------------
-- 9. scoreForClass stub: always nil, never errors, regardless of input shape.
-- ---------------------------------------------------------------------------
do
    check('scoreForClass stub returns nil', ItemCompare.scoreForClass({ hp = 100 }, 'WAR') == nil)
    local ok = pcall(ItemCompare.scoreForClass, nil, nil)
    check('scoreForClass stub tolerates nil args', ok)
end

-- ---------------------------------------------------------------------------
-- 10. Windows pass v2: aug-inclusive totals (§0.1 — one number everywhere).
-- ---------------------------------------------------------------------------
do
    -- The 1493/1764 earring: bare 1493 HP + 271 from three augs = 1764 everywhere.
    local item     = { hp = 1493, ac = 102, mana = 896 }
    local equipped = { hp = 700,  ac = 48,  mana = 770 }
    local result = ItemCompare.compare(item, equipped, {
        augStats = { hp = 271, ac = 21, mana = 181 },
        equippedAugStats = { hp = 4 },
    })
    local hpRow = rowByKey(result.rows, 'hp')
    check('totals: tile value is aug-inclusive', hpRow and hpRow.value == 1764, hpRow and hpRow.value)
    check('totals: delta uses both sides aug-inclusive', hpRow and hpRow.delta == 1764 - 704, hpRow and hpRow.delta)
    check('totals: no-opts call still bare (back-compat)',
        rowByKey(ItemCompare.compare(item, equipped).rows, 'hp').value == 1493)
end

-- ---------------------------------------------------------------------------
-- 11. Windows pass v2: attack still scores the verdict without a visible row.
-- ---------------------------------------------------------------------------
do
    local item     = { hp = 100, attack = 14 }
    local equipped = { hp = 100, attack = 11 }
    local result = ItemCompare.compare(item, equipped)
    check('verdict counts attack with no attack tile', result.verdict == 'upgrade', result.verdict)
    check('general strip chosen', result.strip == 'general', result.strip)
end

-- ---------------------------------------------------------------------------
-- 12. Windows pass v2: the weapon strip (18a) — dmg/delay/ratio/dps/proc cells.
-- ---------------------------------------------------------------------------
do
    -- 18a's own numbers: 512/45 vs 464/48 -> ratio 11.4 vs 9.7, dps 114 vs 97.
    local item     = { damage = 512, itemDelay = 45, attack = 62, hp = 2140 }
    local equipped = { damage = 464, itemDelay = 48, attack = 53, hp = 2200 }
    local result = ItemCompare.compare(item, equipped, { procName = 'Pacify', procRate = 120 })
    check('weapon strip chosen', result.strip == 'weapon', result.strip)
    local dmg = rowByKey(result.rows, 'damage')
    check('weapon: dmg row +48', dmg and dmg.value == 512 and dmg.delta == 48, dmg and dmg.delta)
    local delay = rowByKey(result.rows, 'itemDelay')
    check('weapon: delay row -3, flagged betterWhenLower', delay and delay.delta == -3
        and delay.betterWhenLower == true, delay and delay.delta)
    local ratio = rowByKey(result.rows, 'ratio')
    check('weapon: ratio 11.4 (+1.7), isFloat', ratio and ratio.value == 11.4
        and ratio.delta == 1.7 and ratio.isFloat == true,
        ratio and (tostring(ratio.value) .. '/' .. tostring(ratio.delta)))
    local dps = rowByKey(result.rows, 'dps')
    check('weapon: dps 114 (+17)', dps and dps.value == 114 and dps.delta == 17,
        dps and (tostring(dps.value) .. '/' .. tostring(dps.delta)))
    local proc = rowByKey(result.rows, 'proc')
    check('weapon: proc cell is text with rate note', proc and proc.isText == true
        and proc.value == 'Pacify' and proc.note == 'rate 120', proc and proc.note)
    check('weapon: verdict decided by dps', result.verdict == 'upgrade', result.verdict)
    check('weapon: summary leads with the biggest mover and appends nothing heroic',
        result.summary:find('+48', 1, true) ~= nil, result.summary)

    -- DPS dominates: a big HP loss cannot flip a weapon with better dps.
    local hpTrade = ItemCompare.compare(
        { damage = 512, itemDelay = 45, hp = 100 },
        { damage = 464, itemDelay = 48, hp = 900 })
    check('weapon: dps beats an hp loss', hpTrade.verdict == 'upgrade', hpTrade.verdict)

    -- Equal dps falls through to the stat sum.
    local tie = ItemCompare.compare(
        { damage = 100, itemDelay = 20, hp = 50 },
        { damage = 100, itemDelay = 20, hp = 900 })
    check('weapon: equal dps falls back to stats', tie.verdict == 'downgrade', tie.verdict)

    -- Weapon vs a non-weapon equipped side: ratio/dps have no honest delta.
    local vsEmptyHand = ItemCompare.compare(
        { damage = 100, itemDelay = 20 }, { hp = 10 })
    local r2 = rowByKey(vsEmptyHand.rows, 'ratio')
    check('weapon vs non-weapon: ratio delta nil', r2 and r2.delta == nil, r2 and r2.delta)
end

-- ---------------------------------------------------------------------------
-- 13. Windows pass v2: the heroic rank cell (always last, — at zero, aug-aware).
-- ---------------------------------------------------------------------------
do
    local item     = { hp = 10, heroicSTR = 20, heroicWIS = 15 }
    local equipped = { hp = 10, heroicSTR = 25, heroicWIS = 18 }
    local result = ItemCompare.compare(item, equipped, { augStats = { heroicSTA = 8 } })
    local last = result.rows[#result.rows]
    check('heroic: last row is the rank', last and last.key == 'heroic', last and last.key)
    check('heroic: rank sums primaries incl. augs', last and last.value == 43, last and last.value)
    check('heroic: delta vs equipped rank', last and last.delta == 0, last and last.delta)
    check('heroic: zeroAsDash flagged', last and last.zeroAsDash == true)
    check('heroic: nonzero delta lands in the summary',
        ItemCompare.compare({ heroicSTR = 8 }, { hp = 0 }).rows ~= nil
        and ItemCompare.compare({ hp = 5, heroicSTR = 8 }, { hp = 5 }).summary:find('+8 Heroic', 1, true) ~= nil,
        ItemCompare.compare({ hp = 5, heroicSTR = 8 }, { hp = 5 }).summary)
end

-- ---------------------------------------------------------------------------
-- 14. Windows pass v2: augment-type items get no Augs cell; endurance/regen rows exist.
-- ---------------------------------------------------------------------------
do
    local aug = { type = 'Augmentation', hp = 30, augsTotal = 0 }
    local r = ItemCompare.compare(aug, nil)
    check('augment subject: no augs row', rowByKey(r.rows, 'augs') == nil)

    local jewel = { hp = 100, endurance = 1417, hpRegen = 8, augsTotal = 3, augsFilled = 3 }
    local r2 = ItemCompare.compare(jewel, nil)
    local endRow = rowByKey(r2.rows, 'endurance')
    local regenRow = rowByKey(r2.rows, 'hpRegen')
    local augsRow = rowByKey(r2.rows, 'augs')
    check('general strip: End cell present', endRow and endRow.value == 1417, endRow and endRow.value)
    check('general strip: Regen cell present', regenRow and regenRow.value == 8, regenRow and regenRow.value)
    check('general strip: Augs 3/3 ratio row', augsRow and augsRow.value == '3/3', augsRow and augsRow.value)
end

print(string.format('\n%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
