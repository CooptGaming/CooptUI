--[[
    script_defs.lua — the ONE list of AA script items (25c / windows pass phase 15).

    Three families × five tiers, 1-5 AA each. This used to be a hardcoded table inside
    the standalone Script Tracker; it is shared now so the tracker view, the standalone
    tool, and (later) the sell rules / loot filter all agree on what a script is worth —
    a Legendary must never get vendored because two lists drifted.

    Leaf module: no requires, no state. Names are exact-match ("<tier>Script of
    <family>"), matching the game's item names; the cheap family sniff other code uses
    (context_menu's isScriptItem) is name:find("script of") — both live off the same
    naming scheme.
]]

local M = {}

-- Tier rows, low to high. Lost, Planar and Rebirthed are worth the SAME at a given tier
-- (the existing tool's logic, kept), so tier is the natural display row.
M.TIERS = {
    { label = "Normal",    tierKey = "normal",    prefix = "",           aa = 1 },
    { label = "Enhanced",  tierKey = "enhanced",  prefix = "Enhanced ",  aa = 2 },
    { label = "Rare",      tierKey = "rare",      prefix = "Rare ",      aa = 3 },
    { label = "Epic",      tierKey = "epic",      prefix = "Epic ",      aa = 4 },
    { label = "Legendary", tierKey = "legendary", prefix = "Legendary ", aa = 5 },
}

-- The three families, with the short label the by-tier table shows.
M.FAMILIES = {
    { suffix = "Lost Memories",      short = "Lost" },
    { suffix = "Planar Power",       short = "Planar" },
    { suffix = "Rebirthed Memories", short = "Rebirthed" },
}

-- Flat defs: one entry per (family, tier), with the precomputed exact item name.
M.DEFS = {}
-- Exact item name -> its def, for O(1) classification of a scanned item row.
M.BY_NAME = {}

for _, fam in ipairs(M.FAMILIES) do
    for _, tier in ipairs(M.TIERS) do
        local def = {
            suffix = fam.suffix,
            familyShort = fam.short,
            tierKey = tier.tierKey,
            tierLabel = tier.label,
            aa = tier.aa,
            fullName = tier.prefix .. "Script of " .. fam.suffix,
        }
        M.DEFS[#M.DEFS + 1] = def
        M.BY_NAME[def.fullName] = def
    end
end

--- Classify an itemui item row (needs .name). Returns the def or nil.
function M.classify(item)
    if not item then return nil end
    return M.BY_NAME[item.name or ""]
end

return M
