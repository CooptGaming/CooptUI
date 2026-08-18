-- augmentRestrictionAllowsParent suite - pins the EQEmu server semantics for
-- AugRestrictions (2026-08-17 field round): "Armor Only" means the parent's
-- ItemType IS Armor, not "anything that isn't a weapon". The looser test listed
-- an Armor Only gem for a non-armor parent (Mythical Suffersphere, a charm-class
-- item); the game refused the insert and the gem stranded on the cursor until
-- the queue aborted. Every candidate surface (utility list, ornament probe,
-- Fill-with-Best) funnels through this one function, so these pins are the
-- whole regression net for the class.

local repo = os.getenv('COOPT_REPO') or 'C:/Claude/CooptUI'
package.path = repo .. '/lua/?.lua;' .. repo .. '/lua/?/init.lua;'
    .. repo .. '/scripts/tests/?.lua;' .. package.path

-- item_tlo requires mq at load; the restriction path never touches the TLO tree.
package.loaded['mq'] = { TLO = {} }

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

local helpers = require('itemui.utils.augment_helpers')
local allows = helpers.augmentRestrictionAllowsParent

--- Parent item shaped like the TLO reads parentItemClassify performs (Type/Damage/ItemDelay).
local function fakeItem(typeStr, dmg, delay)
    return {
        Type = function() return typeStr end,
        Damage = function() return dmg or 0 end,
        ItemDelay = function() return delay or 0 end,
    }
end

-- ---------------------------------------------------------------- no restriction
do
    check('restriction 0 allows anything', allows(fakeItem('Charm'), 0))
    check('nil restriction allows anything', allows(fakeItem('Charm'), nil))
    check('nil parent refused when restricted', not allows(nil, 1))
end

-- ---------------------------------------------------------------- 1: Armor Only
do
    check('armor parent passes Armor Only', allows(fakeItem('Armor'), 1))
    -- The field case: a charm is not armor, whatever it is not (it is not a weapon either).
    check('charm parent refused by Armor Only', not allows(fakeItem('Charm'), 1))
    check('jewelry parent refused by Armor Only', not allows(fakeItem('Jewelry'), 1))
    check('misc parent refused by Armor Only', not allows(fakeItem('Miscellaneous'), 1))
    -- EQEmu passes only ItemTypeArmor; shields are their own ItemType.
    check('shield parent refused by Armor Only', not allows(fakeItem('Shield'), 1))
    -- Failed Type read stays excluded (fail-closed beats a stranded cursor).
    check('unreadable type refused by Armor Only', not allows(fakeItem(''), 1))
end

-- ---------------------------------------------------------------- 2: Weapons Only
do
    check('1H slasher passes Weapons Only', allows(fakeItem('1H Slashing', 10, 20), 2))
    check('armor refused by Weapons Only', not allows(fakeItem('Armor'), 2))
end

-- ---------------------------------------------------------------- 13: Shields Only
do
    check('shield passes Shields Only', allows(fakeItem('Shield'), 13))
    check('armor refused by Shields Only', not allows(fakeItem('Armor'), 13))
end

-- ---------------------------------------------------------------- weapon subtypes
do
    check('piercer passes 7', allows(fakeItem('Piercing', 9, 18), 7) and true or false)
    check('h2h passes 8', allows(fakeItem('Hand to Hand', 9, 18), 8) and true or false)
    check('2H blunt passes 10', allows(fakeItem('2H Blunt', 30, 40), 10) and true or false)
    check('1H slasher refused by 4 (2H only)', not allows(fakeItem('1H Slashing', 10, 20), 4))
    check('armor refused by subtype restrictions', not allows(fakeItem('Armor'), 7))
end

print(string.format('%d passed, %d failed', pass, fail))
if fail > 0 then os.exit(1) end
