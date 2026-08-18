--[[
    worn_effects.lua — the one walk that answers "which worn/focus effect lines does
    the equipped set carry, and which copies actually apply?"

    Three consumers, one truth (the socket_list lockdown pattern):
      * the Effects window's Worn section (the tracker: shows every line, its
        stacking rule, and which copies are WASTED — the "make sure we aren't
        stacking up" surface);
      * upgrade_scan's walk context;
      * Aug Utility's candidate/Optimize context.
    The context map (lines[line] = best worn units) is exactly what
    scoreForClass's opts.context.wornLines consumes, so what the tracker SHOWS
    and what the ranking DEDUCTS can never drift apart.

    Pure module: no mq require. The walk reads equipment only through the
    accessors the caller passes (src.equipmentCache, src.getItemSpellId,
    src.getSpellName — the same key names app.lua's ctx and upgrade_scan's deps
    both already carry), every call pcall-guarded, so the headless suite can
    drive it with plain tables.

    Stacking semantics per the 08-04 field ruling (worn effects split BY LINE):
      highest          only the largest copy of the line applies; every other
                       copy is wasted — the thing the tracker exists to catch.
      additive_capped  copies sum, the cap eats the excess (total > cap shows
                       as "N over cap").
      additive         copies sum, nothing wasted.
    Names that resolve to no line are listed under `untracked` rather than
    silently dropped — the unscored-list philosophy: an honest gap is how new
    names get found and added to score_weights.
]]

local itemCompare = require('itemui.utils.item_compare')
local weights = require('itemui.utils.score_weights')

local M = {}

-- 0-based equipment slot -> display name (paper-doll vocabulary, EQUI_Inventory order).
M.SLOT_NAMES = {
    [0] = "Charm", "Left Ear", "Head", "Face", "Right Ear", "Neck", "Shoulders",
    "Arms", "Back", "Left Wrist", "Right Wrist", "Ranged", "Hands", "Primary",
    "Secondary", "Left Ring", "Right Ring", "Chest", "Legs", "Feet", "Waist",
    "Power Source", "Ammo",
}

--- Cheap identity for cache keying: the equipped ids, joined. Same shape the
--- Aug Utility fingerprint and upgrade_scan's change key already use.
function M.fingerprint(equipmentCache)
    local cache = equipmentCache or {}
    local parts = {}
    for i = 1, 23 do
        local e = cache[i]
        parts[i] = e and tostring(e.id or 0) or "0"
    end
    return table.concat(parts, ",")
end

--- The walk. src = { equipmentCache, getItemSpellId(item, kind), getSpellName(id) }.
--- Returns {
---   lines     = { [line] = best worn units }           -- scoreForClass context, verbatim
---   groups    = sorted array of {
---                 line, stacking, cap,                  -- cap only when the line has one
---                 best, total, wastedCount, overCap,    -- overCap only when total > cap
---                 entries = units-desc array of {
---                   units, effName, itemName, slotIndex, slotName, kind,
---                   wasted, wastedWhy },
---               }
---   untracked = array of { effName, itemName, slotName, kind }  -- no line resolves
--- }
function M.build(src)
    local out = { lines = {}, groups = {}, untracked = {} }
    if not src then return out end
    local cache = src.equipmentCache or {}
    local getSpellId, getSpellName = src.getItemSpellId, src.getSpellName
    if not (getSpellId and getSpellName) then return out end

    local byLine = {}
    for i = 1, 23 do
        local e = cache[i]
        if e then
            local slotIndex = i - 1
            local itemName = tostring(e.name or "?")
            for _, kind in ipairs({ "Worn", "Focus" }) do
                local okId, id = pcall(getSpellId, e, kind)
                if okId and id and id > 0 then
                    local okN, nm = pcall(getSpellName, id)
                    if okN and nm and nm ~= "" and nm ~= "Unknown" then
                        local line, units = itemCompare.resolveEffectLine(tostring(nm))
                        if line and line ~= "clicky" and type(units) == "number" then
                            local g = byLine[line]
                            if not g then
                                local spec = weights.effects.lines[line] or {}
                                g = { line = line, stacking = spec.stacking or "highest",
                                      cap = spec.cap, entries = {} }
                                byLine[line] = g
                            end
                            g.entries[#g.entries + 1] = {
                                units = units, effName = tostring(nm), itemName = itemName,
                                slotIndex = slotIndex,
                                slotName = M.SLOT_NAMES[slotIndex] or tostring(slotIndex),
                                kind = kind,
                            }
                        elseif not line then
                            out.untracked[#out.untracked + 1] = {
                                effName = tostring(nm), itemName = itemName,
                                slotName = M.SLOT_NAMES[slotIndex] or tostring(slotIndex),
                                kind = kind,
                            }
                        end
                    end
                end
            end
        end
    end

    for _, g in pairs(byLine) do
        table.sort(g.entries, function(a, b)
            if a.units ~= b.units then return a.units > b.units end
            return a.slotIndex < b.slotIndex  -- deterministic among equals
        end)
        local total = 0
        for _, en in ipairs(g.entries) do total = total + en.units end
        g.total = total
        g.best = (g.entries[1] and g.entries[1].units) or 0
        g.wastedCount = 0
        if g.stacking == "highest" then
            local top = g.entries[1]
            for idx = 2, #g.entries do
                local en = g.entries[idx]
                en.wasted = true
                en.wastedWhy = (en.units == g.best)
                    and string.format("duplicate of %s", top.itemName)
                    or string.format("beaten by %s (%d)", top.itemName, g.best)
                g.wastedCount = g.wastedCount + 1
            end
        elseif g.stacking == "additive_capped" and g.cap and total > g.cap then
            g.overCap = total - g.cap
        end
        out.lines[g.line] = g.best
        out.groups[#out.groups + 1] = g
    end
    table.sort(out.groups, function(a, b) return a.line < b.line end)
    return out
end

--- Sum of everything the set wastes: highest-line duplicates plus over-cap units.
--- One number for section headers ("2 wasted") and quick health checks.
function M.wasteSummary(built)
    local overlapped, overCap = 0, 0
    for _, g in ipairs((built and built.groups) or {}) do
        overlapped = overlapped + (g.wastedCount or 0)
        overCap = overCap + (g.overCap or 0)
    end
    return overlapped, overCap
end

return M
