--[[
    upgrade_scan.lua — the cached compare walk behind "N upgrades in bags"
    (MOCKUP_score_surfaces B; the walk equipment.lua's band comment deferred to).

    Driven by the Equipment view: it calls M.tick(deps) every frame the window is
    open, and the walk advances TIME-BOXED (the aa_data pump lesson: chunk by wall
    clock, never by item count - lazy stat fields resolve through the TLO on first
    touch and a whole-bag walk in one frame is a hitch). Results swap in only at
    completion (stale-while-revalidate), so the band never flickers mid-walk.

    What a candidate must pass BEFORE scoring (UPGRADE_SCORE.md): usable by
    class/race/deity/level (deps.canUse - the tooltip layer's own gate), and it must
    actually FIT a worn slot (WornSlot TLO read, once per item per walk). Scoring is
    scoreForClass on the row's stats - the v1 walk does not resolve per-item effect
    names (that is a per-item spell-TLO cost the band's ballpark "~" does not need);
    the tooltip and Aug Utility surfaces, which have effect names in hand, do.

    An empty slot loses to anything usable that fits it (score > 0); a dressed slot
    needs best-in-bags > equipped x sidegradeMargin (the churn guard, data in
    score_weights). pct is nil for the empty-slot case - "~+inf%" is not a number
    anyone wants printed.
]]

local mq = require('mq')
local itemHelpers = require('itemui.utils.item_helpers')
local itemCompare = require('itemui.utils.item_compare')
local weights = require('itemui.utils.score_weights')

local M = {}

local WALK_BUDGET_MS = 6

-- Published result (swap-in at completion only).
local result = { count = 0, bySlot = {}, equippedScore = {}, wornLines = {}, at = 0 }
-- In-progress walk state, nil when idle.
local walk = nil
local lastKey = nil

local function classShortName()
    return itemHelpers.getPlayerClassShortName()
end

--- Cheap change key: inventory size + equipped ids. A bag shuffle that swaps equal
--- counts of the same items misses this key - acceptable for a "~" band stat; the
--- next equip/scan change re-walks.
local function buildKey(deps)
    local inv = deps.inventoryItems or {}
    local parts = { tostring(#inv) }
    local cache = deps.equipmentCache or {}
    for i = 1, 23 do
        local e = cache[i]
        parts[#parts + 1] = tostring(e and e.id or 0)
    end
    return table.concat(parts, "|")
end

--- Worn-lines context from the equipped set: for every equipped item's Worn/Focus
--- effect name that resolves to a scored line, keep the best units per line. This is
--- what zeroes a duplicate "highest" family everywhere the context is passed.
local function buildWornLines(deps)
    local lines = {}
    if not (deps.getItemSpellId and deps.getSpellName) then return lines end
    local cache = deps.equipmentCache or {}
    for i = 1, 23 do
        local e = cache[i]
        if e then
            for _, kind in ipairs({ "Worn", "Focus" }) do
                local okId, id = pcall(deps.getItemSpellId, e, kind)
                if okId and id and id > 0 then
                    local okN, nm = pcall(deps.getSpellName, id)
                    if okN and nm and nm ~= "" then
                        local line, units = itemCompare.resolveEffectLine(tostring(nm))
                        if line and line ~= "clicky" and type(units) == "number" then
                            if not lines[line] or units > lines[line] then lines[line] = units end
                        end
                    end
                end
            end
        end
    end
    return lines
end

function M.invalidate()
    lastKey = nil
end

--- Advance the walk. Call every frame the Equipment window renders; no-ops when the
--- published result is fresh and nothing changed.
function M.tick(deps)
    if not deps then return end
    local now = mq.gettime()
    if not walk then
        -- One walk per state: re-walk only when inventory count or an equipped id
        -- changes (or after invalidate()). Item stats are static, so an unchanged
        -- key has nothing new to say.
        local key = buildKey(deps)
        if key == lastKey then return end
        local cls = classShortName()
        if not cls then return end
        walk = {
            key = key, cls = cls, phase = "equipped", cursor = 0,
            equippedScore = {}, bySlot = {}, wornLines = buildWornLines(deps),
        }
    end
    local t0 = now
    if walk.phase == "equipped" then
        local cache = deps.equipmentCache or {}
        while walk.cursor <= 22 do
            local slotIndex = walk.cursor
            local e = cache[slotIndex + 1]
            if e then
                local ok, total = pcall(itemCompare.scoreForClass, e, walk.cls)
                walk.equippedScore[slotIndex] = (ok and type(total) == "number") and total or 0
            else
                walk.equippedScore[slotIndex] = 0
            end
            walk.cursor = walk.cursor + 1
            if (mq.gettime() - t0) >= WALK_BUDGET_MS then return end
        end
        walk.phase = "bags"
        walk.cursor = 1
        return
    end
    -- bags phase
    local inv = deps.inventoryItems or {}
    local margin = weights.sidegradeMargin or 1.05
    while walk.cursor <= #inv do
        local row = inv[walk.cursor]
        walk.cursor = walk.cursor + 1
        if row and row.id and row.id ~= 0 then
            local usable = true
            if deps.canUse then
                local okU, u = pcall(deps.canUse, row)
                usable = okU and u or false
            end
            if usable then
                -- Fit: the WornSlot read, once per item per walk, via the row's TLO.
                local fits = nil
                pcall(function()
                    local it = itemHelpers.getItemTLO(row.bag, row.slot, row.source or "inv")
                    if it then fits = itemHelpers.getWornSlotIndicesFromTLO(it) end
                end)
                if fits and (fits == "all" or next(fits)) then
                    local okS, total = pcall(itemCompare.scoreForClass, row, walk.cls)
                    local score = (okS and type(total) == "number") and total or 0
                    if score > 0 then
                        local function consider(slotIndex)
                            local eq = walk.equippedScore[slotIndex] or 0
                            local beats = (eq <= 0) or (score > eq * margin)
                            if not beats then return end
                            local pct = (eq > 0) and math.floor((score / eq - 1) * 100 + 0.5) or nil
                            local cur = walk.bySlot[slotIndex]
                            local better = not cur or score > (cur.score or 0)
                            if better then
                                walk.bySlot[slotIndex] = {
                                    name = row.name, bag = row.bag, slot = row.slot,
                                    score = score, pct = pct,
                                }
                            end
                        end
                        if fits == "all" then
                            for s = 0, 22 do consider(s) end
                        else
                            for s in pairs(fits) do consider(s) end
                        end
                    end
                end
            end
        end
        if (mq.gettime() - t0) >= WALK_BUDGET_MS then return end
    end
    -- Complete: swap in.
    local count = 0
    for _ in pairs(walk.bySlot) do count = count + 1 end
    result = {
        count = count, bySlot = walk.bySlot, equippedScore = walk.equippedScore,
        wornLines = walk.wornLines, at = mq.gettime(),
    }
    lastKey = walk.key
    walk = nil
end

--- Published result: { count, bySlot = { [slotIndex] = {name,bag,slot,score,pct} },
--- equippedScore = { [slotIndex] = n }, wornLines = { [line] = units }, at }.
function M.getResult()
    return result
end

function M.isWalking()
    return walk ~= nil
end

return M
