--[[
    Augment Ranking - Config-driven scoring for augments (stats, heroic weight,
    effect desirability, restriction bonus, weapon vs armor). Used by Augment Utility
    to sort compatible augments by rank. Config is structured for future UI tuning.

    Ranking is applied only to augments that already passed getCompatibleAugments
    (fits slot, restrictions, equipment slot, and optionally class/race/deity/level).
--]]

local itemHelpers = require('itemui.utils.item_helpers')
local ItemTooltip = require('itemui.utils.item_tooltip')

local M = {}

--- Default config (tunable; future UI can replace/merge).
--- statWeights: optional key = stat field, value = weight (default 1).
--- effectBySpellId: spell ID -> score override; effectTypeDefault: Clicky/Proc/Worn/Focus default score.
function M.getDefaultConfig()
    return {
        heroicMultiplier = 5,
        restrictionBonus = 25,
        statWeights = nil, -- nil = all 1
        effectTypeDefault = { Clicky = 30, Proc = 50, Worn = 20, Focus = 40 },
        effectBySpellId = {},
        weaponDamageMinRatio = 0.05,
        weaponDamageWeight = 100,
    }
end

--- Compute rank score for one augment. parentContext = { bag, slot, source } for target item.
--- ctx must have getItemTLO, getItemSpellId. Returns number (0 on error).
function M.scoreAugment(augment, parentContext, ctx, config)
    if not augment or not ctx then return 0 end
    config = config or M.getDefaultConfig()
    parentContext = parentContext or {}

    local score = 0
    local ok, err = pcall(function()
        local baseKeys, heroicKeys = itemHelpers.getStatKeysForRanking()
        local weights = config.statWeights or {}

        -- Core: base stat sum (weighted)
        for _, key in ipairs(baseKeys) do
            local v = augment[key]
            local num = (type(v) == "number") and v or 0
            score = score + num * (weights[key] or 1)
        end

        -- Heroic stat sum with multiplier
        local heroicSum = 0
        for _, key in ipairs(heroicKeys) do
            local v = augment[key]
            heroicSum = heroicSum + ((type(v) == "number") and v or 0)
        end
        score = score + heroicSum * (config.heroicMultiplier or 5)

        -- Effect desirability (Clicky, Proc, Worn, Focus)
        local effectTypes = { "Clicky", "Proc", "Worn", "Focus" }
        local typeDefaults = config.effectTypeDefault or {}
        local bySpellId = config.effectBySpellId or {}
        for _, key in ipairs(effectTypes) do
            if ctx.getItemSpellId then
                local id = ctx.getItemSpellId(augment, key)
                if id and id > 0 then
                    local effectScore = bySpellId[id]
                    if effectScore == nil then
                        effectScore = typeDefaults[key] or 20
                    end
                    score = score + effectScore
                end
            end
        end

        -- Restriction bonus (class/deity/level restricted and usable by current character)
        local hasRestriction = false
        if (augment.class and augment.class ~= "" and tostring(augment.class):lower() ~= "all") then
            hasRestriction = true
        end
        if (augment.deity and augment.deity ~= "") then hasRestriction = true end
        if (augment.requiredLevel and augment.requiredLevel > 0) then hasRestriction = true end
        if hasRestriction then
            local info = ItemTooltip.getCanUseInfo(augment, augment.source or "inv")
            if info and info.canUse and (config.restrictionBonus or 0) > 0 then
                score = score + config.restrictionBonus
            end
        end

        -- Weapon: damage ratio bonus when parent is weapon and augment adds meaningful damage
        local parentBag = parentContext.bag
        local parentSlot = parentContext.slot
        local parentSrc = parentContext.source or "inv"
        if parentBag and parentSlot and ctx.getItemTLO then
            local parentIt = ctx.getItemTLO(parentBag, parentSlot, parentSrc)
            if parentIt then
                local isWeapon, parentDamage, parentDelay = itemHelpers.getParentWeaponInfo(parentIt)
                if isWeapon and parentDamage and parentDamage > 0 then
                    local augDamage = (type(augment.damage) == "number") and augment.damage or 0
                    local ratio = augDamage / parentDamage
                    local minRatio = config.weaponDamageMinRatio or 0.05
                    local weight = config.weaponDamageWeight or 100
                    if ratio >= minRatio then
                        score = score + ratio * weight
                    end
                end
            end
        end
    end)
    if not ok then return 0 end
    return score
end

return M
