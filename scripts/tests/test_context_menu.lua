-- Context-menu builder tests (windows pass phase 9, spec §7).
--
-- What this proves, per the eight rules:
--   1. Identity renders first (name + where) for every subject family.
--   2. The four groups appear in order with LOOK/MOVE/RULES headings and an unheaded
--      destructive tail.
--   3. Blocked rows stay in place with the reason IN the row ("Bank it — no banker
--      nearby"), and disabled rows never activate.
--   4. Rules rows carry ✓ state and toggle with the exact legacy list semantics
--      (applySellListChange argument shapes preserved).
--   6. Destroy requires shift, says so in the row, fires requestDestroyItem DIRECTLY
--      (no confirm dialog), and stays blocked for Clicky-list-protected items.
--   7. The same object produces the same row set in every host (acceptance §11.5),
--      modulo the context-owned move rows.
-- Plus verb parity for the special families (scripts, reroll books, consumables).

local repo = os.getenv('COOPT_REPO') or 'C:/Claude/CooptUI'
package.path = repo .. '/lua/?.lua;' .. repo .. '/lua/?/init.lua;'
    .. repo .. '/scripts/tests/?.lua;' .. package.path

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

local stub = require('imgui_stub')
stub.install()
package.loaded['mq'] = stub.newMq()

local menu = require('itemui.components.context_menu')
local uiCommon = require('itemui.components.ui_common')
local theme = require('itemui.utils.theme')

-- ---------------------------------------------------------------- fixtures
local function newSpies()
    return {
        tabs = {}, sellList = {}, destroys = {}, moves = {}, consumed = {},
        rerollAdds = {}, rerollRemoves = {}, favAdd = {}, favRemove = {},
        statusRefresh = {}, saved = 0, cursorCleared = 0,
    }
end

local function newCtx(spies, opts)
    opts = opts or {}
    local consumableSet = opts.consumables or {}
    local augAlwaysSell = opts.augAlwaysSell or {}
    local augNeverLoot = opts.augNeverLoot or {}
    return {
        theme = theme,
        uiState = {},
        drawItemIcon = function() end,
        addItemDisplayTab = function(item, source) spies.tabs[#spies.tabs + 1] = { name = item.name, source = source } end,
        removeItemFromCursor = function() spies.cursorCleared = spies.cursorCleared + 1 end,
        applySellListChange = function(name, k, j) spies.sellList[#spies.sellList + 1] = { name = name, k = k, j = j } end,
        moveInvToBank = function(bag, slot) spies.moves[#spies.moves + 1] = { dir = 'toBank', bag = bag, slot = slot } end,
        moveBankToInv = function(bag, slot) spies.moves[#spies.moves + 1] = { dir = 'toInv', bag = bag, slot = slot } end,
        consumeItemAtSlot = function(source, bag, slot) spies.consumed[#spies.consumed + 1] = { source = source, bag = bag, slot = slot } end,
        requestDestroyItem = function(bag, slot, name, stackSize)
            spies.destroys[#spies.destroys + 1] = { bag = bag, slot = slot, name = name, stackSize = stackSize }
        end,
        favoritesService = {
            isProtected = function() return opts.favProtected == true end,
            getLists = function() return opts.favLists or {} end,
            listsContaining = function() return opts.favContaining or {} end,
            addItem = function(list, id, name) spies.favAdd[#spies.favAdd + 1] = { list = list, id = id, name = name } end,
            removeItem = function(list, id) spies.favRemove[#spies.favRemove + 1] = { list = list, id = id } end,
        },
        consumables = {
            isConsumable = function(n) return consumableSet[n] == true end,
            addConsumable = function(n) consumableSet[n] = true end,
            removeConsumable = function(n) consumableSet[n] = nil end,
        },
        augmentLists = {
            isInAugmentAlwaysSellList = function(n) return augAlwaysSell[n] == true end,
            addToAugmentAlwaysSellList = function(n) augAlwaysSell[n] = true; return true end,
            removeFromAugmentAlwaysSellList = function(n) augAlwaysSell[n] = nil; return true end,
            isInAugmentNeverLootList = function(n) return augNeverLoot[n] == true end,
            addToAugmentNeverLootList = function(n) augNeverLoot[n] = true; return true end,
            removeFromAugmentNeverLootList = function(n) augNeverLoot[n] = nil; return true end,
        },
        rerollService = {
            getAugList = function() return opts.augList or {} end,
            getMythicalList = function() return opts.mythList or {} end,
            -- The real service's O(1) generation-cached membership check
            -- (reroll_service.lua getListStatus). The menu uses THIS rather than
            -- scanning both full lists per row per frame; the fake has to model it or
            -- the menu correctly reads "not on any list" for everything.
            getListStatus = function(kind, id)
                local src = (kind == 'aug') and (opts.augList or {}) or (opts.mythList or {})
                for _, e in ipairs(src) do
                    if e.id == id then return 'listed' end
                end
                return nil
            end,
        },
        resolveRerollList = function() return opts.rerollList end,
        requestAddToRerollList = function(list, payload) spies.rerollAdds[#spies.rerollAdds + 1] = { list = list, payload = payload } end,
        removeFromRerollList = function(list, id) spies.rerollRemoves[#spies.rerollRemoves + 1] = { list = list, id = id } end,
        updateSellStatusForItemName = function(name, k, j) spies.statusRefresh[#spies.statusRefresh + 1] = { name = name, k = k, j = j } end,
        storage = { saveInventory = function() spies.saved = spies.saved + 1 end },
        inventoryItems = {},
    }
end

local function plainItem()
    return { name = 'Rusty Sword', id = 111, bag = 3, slot = 7, type = '1H Slashing',
             stackSize = 1, icon = 0, inKeep = false, inJunk = false }
end
local function augItem()
    return { name = 'Shiny Augment', id = 222, bag = 2, slot = 4, type = 'Augmentation',
             stackSize = 1, icon = 0, inKeep = false, inJunk = false }
end

local function render(ctx, item, env)
    return stub.frame(function() menu.renderContents(ctx, item, env) end)
end

-- ---------------------------------------------------------------- anatomy (rules 1+2)
do
    local spies = newSpies()
    local ctx = newCtx(spies)
    local r = render(ctx, plainItem(), { source = 'inv', bankOpen = false })
    check('anatomy: balanced', stub.balanced(r), stub.imbalance(r))
    check('anatomy: identity name first', r.text[1] == 'Rusty Sword', r.text[1])
    check('anatomy: identity where second', tostring(r.text[2]):find('Bag 3', 1, true) ~= nil, r.text[2])
    check('anatomy: LOOK heading', stub.drew(r, 'LOOK'))
    check('anatomy: MOVE heading', stub.drew(r, 'MOVE'))
    check('anatomy: RULES heading', stub.drew(r, 'RULES'))
    check('anatomy: destructive group has no heading', not stub.drew(r, 'DESTROY'))
    check('anatomy: Item info offered', stub.drew(r, 'Item info'))
    check('anatomy: Inspect offered', stub.drew(r, 'Inspect it'))
    -- Group order: LOOK before MOVE before RULES in the recorded stream.
    local pos = {}
    for i, s in ipairs(r.text) do
        if pos[s] == nil then pos[s] = i end
    end
    check('anatomy: group order LOOK<MOVE<RULES',
        (pos['LOOK'] or 0) < (pos['MOVE'] or 1e9) and (pos['MOVE'] or 0) < (pos['RULES'] or 1e9))
end

-- ---------------------------------------------------------------- rule 3: blocked rows
do
    local spies = newSpies()
    local ctx = newCtx(spies)
    local r = render(ctx, plainItem(), { source = 'inv', bankOpen = false })
    check('blocked: Bank it present with reason', stub.drew(r, 'Bank it — no banker nearby'))

    stub.click = { ['Bank it'] = true }
    render(ctx, plainItem(), { source = 'inv', bankOpen = false })
    stub.click = {}
    check('blocked: disabled Bank it never fires', #spies.moves == 0)

    stub.click = { ['Bank it'] = true }
    render(ctx, plainItem(), { source = 'inv', bankOpen = true })
    stub.click = {}
    check('blocked: Bank it fires when banker is up', #spies.moves == 1
        and spies.moves[1].dir == 'toBank' and spies.moves[1].bag == 3 and spies.moves[1].slot == 7,
        #spies.moves)

    local r2 = render(ctx, plainItem(), { source = 'bank', bankOpen = false })
    check('blocked: Take it out present with reason in bank context', stub.drew(r2, 'Take it out — no banker nearby'))
end

-- ---------------------------------------------------------------- rule 4: ✓ toggles
do
    local spies = newSpies()
    local ctx = newCtx(spies)
    stub.click = { ['Keep it'] = true }
    render(ctx, plainItem(), { source = 'inv' })
    stub.click = {}
    check('rules: keep-on sends (true,false)', #spies.sellList == 1
        and spies.sellList[1].k == true and spies.sellList[1].j == false)

    local kept = plainItem(); kept.inKeep = true; kept.inJunk = false
    stub.click = { ['Keep it'] = true }
    render(ctx, kept, { source = 'inv' })
    stub.click = {}
    check('rules: keep-off sends (false,inJunk)', #spies.sellList == 2
        and spies.sellList[2].k == false and spies.sellList[2].j == false)

    stub.click = { ['Always sell it'] = true }
    render(ctx, plainItem(), { source = 'inv' })
    stub.click = {}
    check('rules: always-sell-on sends (false,true)', #spies.sellList == 3
        and spies.sellList[3].k == false and spies.sellList[3].j == true)

    -- Consumable flag round-trip through the same row.
    stub.click = { ['Treat it as a consumable'] = true }
    render(ctx, plainItem(), { source = 'inv' })
    stub.click = {}
    local r = render(ctx, plainItem(), { source = 'inv' })
    check('rules: consumable flag stuck', stub.drew(r, 'Use it (one)'))
end

-- ---------------------------------------------------------------- rule 6: destroy
do
    local spies = newSpies()
    local ctx = newCtx(spies)
    stub.keys = {}
    local r = render(ctx, plainItem(), { source = 'inv' })
    check('destroy: row says hold shift', stub.drew(r, 'Destroy it — hold shift'))

    stub.click = { ['Destroy it'] = true }
    render(ctx, plainItem(), { source = 'inv' })
    stub.click = {}
    check('destroy: no shift, no destroy', #spies.destroys == 0)

    stub.keys = { Shift = true }
    stub.click = { ['Destroy it'] = true }
    render(ctx, plainItem(), { source = 'inv' })
    stub.click = {}
    stub.keys = {}
    check('destroy: shift-click destroys directly, no dialog', #spies.destroys == 1
        and spies.destroys[1].bag == 3 and spies.destroys[1].slot == 7 and spies.destroys[1].stackSize == 1)

    local stacked = plainItem(); stacked.stackSize = 20
    local r2 = render(ctx, stacked, { source = 'inv' })
    check('destroy: stack cost stated', stub.drew(r2, 'the whole stack of 20'))

    local spies2 = newSpies()
    local ctx2 = newCtx(spies2, { favProtected = true })
    stub.keys = { Shift = true }
    stub.click = { ['Destroy it'] = true }
    local r3 = render(ctx2, plainItem(), { source = 'inv' })
    stub.click = {}
    stub.keys = {}
    check('destroy: Clicky-list protection blocks in-row', stub.drew(r3, 'Destroy it — on a Clicky list'))
    check('destroy: protected never destroys', #spies2.destroys == 0)
end

-- ---------------------------------------------------------------- rule 7: same menu everywhere
do
    local function rowSet(ctx, item, env)
        local r = render(ctx, item, env)
        local set = {}
        for _, label in ipairs(r.buttons) do
            -- Context-owned move rows differ by design; everything else must match.
            if not tostring(label):find('Bank it', 1, true)
                and not tostring(label):find('Take it out', 1, true) then
                set[#set + 1] = tostring(label)
            end
        end
        table.sort(set)
        return table.concat(set, '|')
    end
    local spies = newSpies()
    local opts = { rerollList = 'aug' }
    local inv = rowSet(newCtx(spies, opts), augItem(), { source = 'inv', bankOpen = true })
    local sell = rowSet(newCtx(spies, opts), augItem(), { source = 'sell', bankOpen = true })
    local augs = rowSet(newCtx(spies, opts), augItem(), { source = 'augments', bankOpen = true })
    local bank = rowSet(newCtx(spies, opts), augItem(), { source = 'bank', bankOpen = true })
    check('same-menu: inv == sell', inv == sell, inv .. ' vs ' .. sell)
    check('same-menu: inv == augments', inv == augs)
    check('same-menu: inv == bank (modulo move rows)', inv == bank, inv .. ' vs ' .. bank)
    check('same-menu: aug rules present', inv:find('Always sell this augment', 1, true) ~= nil
        and inv:find('Never loot this augment', 1, true) ~= nil)
    local plainRows = rowSet(newCtx(newSpies()), plainItem(), { source = 'inv', bankOpen = true })
    check('same-menu: non-aug lacks aug rules', plainRows:find('this augment', 1, true) == nil)
end

-- ---------------------------------------------------------------- reroll semantics
do
    local spies = newSpies()
    local ctx = newCtx(spies, { rerollList = 'mythical' })
    stub.click = { ['Reroll it (Mythical)'] = true }
    render(ctx, plainItem(), { source = 'inv' })
    stub.click = {}
    check('reroll: add routes to resolved list', #spies.rerollAdds == 1
        and spies.rerollAdds[1].list == 'mythical')

    stub.click = { ['Reroll it (Mythical)'] = true }
    render(ctx, plainItem(), { source = 'bank' })
    stub.click = {}
    check('reroll: bank payload carries source', #spies.rerollAdds == 2
        and spies.rerollAdds[2].payload.source == 'bank' and spies.rerollAdds[2].payload.id == 111)

    local spies2 = newSpies()
    local ctx2 = newCtx(spies2, { rerollList = 'mythical', mythList = { { id = 111 } } })
    local r = render(ctx2, plainItem(), { source = 'inv' })
    check('reroll: membership shows checked row', stub.drew(r, 'Reroll it (Mythical)'))
    stub.click = { ['Reroll it (Mythical)'] = true }
    render(ctx2, plainItem(), { source = 'inv' })
    stub.click = {}
    check('reroll: checked click removes', #spies2.rerollRemoves == 1
        and spies2.rerollRemoves[1].list == 'mythical' and spies2.rerollRemoves[1].id == 111)

    -- Legacy cross-list membership surfaces the old-routing row.
    local spies3 = newSpies()
    local ctx3 = newCtx(spies3, { rerollList = 'mythical', augList = { { id = 111 } } })
    local r3 = render(ctx3, plainItem(), { source = 'inv' })
    check('reroll: old-routing row appears', stub.drew(r3, 'old routing'))
    stub.click = { ['old routing'] = true }
    render(ctx3, plainItem(), { source = 'inv' })
    stub.click = {}
    check('reroll: old-routing removes from the other list', #spies3.rerollRemoves == 1
        and spies3.rerollRemoves[1].list == 'aug')

    -- Reroll window rows (env-provided).
    local removed = nil
    local r4 = render(newCtx(newSpies()), plainItem(), {
        source = 'reroll', rerollEntryId = 42, onRemoveFromRerollList = function(id) removed = id end,
    })
    check('reroll: window row offered', stub.drew(r4, 'On the reroll list'))
    stub.click = { ['On the reroll list'] = true }
    render(newCtx(newSpies()), plainItem(), {
        source = 'reroll', rerollEntryId = 42, onRemoveFromRerollList = function(id) removed = id end,
    })
    stub.click = {}
    check('reroll: window row removes by entry id', removed == 42)

    -- 20b redundancy collapse: inside the Reroll window a listed row used to offer BOTH
    -- removal verbs in the same RULES group - the instant toggle (fires !augremove on the
    -- spot) and the staged row (arms an inline confirm). One row per meaning now: where
    -- the confirmed row exists, the instant one stands down.
    local ctxOn = newCtx(newSpies(), { rerollList = 'mythical', mythList = { { id = 111 } } })
    local rBoth = render(ctxOn, plainItem(), {
        source = 'reroll', rerollEntryId = 111, onRemoveFromRerollList = function() end,
    })
    check('collapse: the Reroll window offers ONE removal verb, the confirmed one',
        stub.drew(rBoth, 'On the reroll list') and not stub.drew(rBoth, 'Reroll it (Mythical)'),
        table.concat(rBoth.buttons, '|'))

    -- ...and Bags/Bank are untouched: no rerollEntryId there, so the instant toggle stays.
    local rBags = render(ctxOn, plainItem(), { source = 'inv' })
    check('collapse: Bags keeps the instant toggle (no verb lost anywhere)',
        stub.drew(rBags, 'Reroll it (Mythical)'), table.concat(rBags.buttons, '|'))
end

-- ---------------------------------------------------------------- special families
do
    -- Scripts: alt-currency verbs only (plus Open it), no destroy, no keep.
    local spies = newSpies()
    local ctx = newCtx(spies)
    local script = { name = 'Script of Power', id = 333, bag = 1, slot = 2, stackSize = 20 }
    local r = render(ctx, script, { source = 'inv' })
    check('script: identity first', r.text[1] == 'Script of Power', r.text[1])
    check('script: alt currency verbs', stub.drew(r, 'Add all to Alt Currency')
        and stub.drew(r, 'Add some to Alt Currency'))
    check('script: no destroy row', not stub.drew(r, 'Destroy it'))
    check('script: no keep row', not stub.drew(r, 'Keep it'))

    stub.click = { ['Add some to Alt Currency'] = true }
    render(ctx, script, { source = 'inv' })
    stub.click = {}
    check('script: quantity picker armed', ctx.uiState.pendingQuantityPickup ~= nil
        and ctx.uiState.pendingQuantityPickup.intent == 'script_consume'
        and ctx.uiState.pendingQuantityPickup.maxQty == 20)

    -- Book: single Use verb that right-clicks in place and consumes the UI row.
    local spies2 = newSpies()
    local ctx2 = newCtx(spies2)
    local book = { name = 'Book of Mythical Reroll', id = 444, bag = 1, slot = 3 }
    stub.click = { ['Use it — consumed on use'] = true }
    local r2 = render(ctx2, book, { source = 'inv' })
    stub.click = {}
    check('book: use issues the right-click', (function()
        for _, c in ipairs(r2.commands) do
            if c:find('/itemnotify in pack1 3 rightmouseup', 1, true) then return true end
        end
        return false
    end)(), table.concat(r2.commands, ';'))
    check('book: UI row consumed', #spies2.consumed == 1)
    check('book: no keep/destroy rows', not stub.drew(r2, 'Keep it') and not stub.drew(r2, 'Destroy it'))

    -- Consumable-flagged: Use one / Use all in MOVE.
    local spies3 = newSpies()
    local ctx3 = newCtx(spies3, { consumables = { ['Book of Titles'] = true } })
    local titles = { name = 'Book of Titles', id = 555, bag = 5, slot = 6, stackSize = 4,
                     inKeep = false, inJunk = false }
    local r3 = render(ctx3, titles, { source = 'inv' })
    check('consumable: Use one offered', stub.drew(r3, 'Use it (one)'))
    check('consumable: Use all with count', stub.drew(r3, 'Use all (x4)'))
    stub.click = { ['Use it (one)'] = true }
    local r4 = render(ctx3, titles, { source = 'inv' })
    stub.click = {}
    check('consumable: use fires itemnotify + consume', #spies3.consumed == 1 and (function()
        for _, c in ipairs(r4.commands) do
            if c:find('/itemnotify in pack5 6 rightmouseup', 1, true) then return true end
        end
        return false
    end)())
end

-- ---------------------------------------------------------------- equipped context + submenu
do
    local spies = newSpies()
    local ctx = newCtx(spies, { favLists = { { name = 'Burn' } }, favContaining = {} })
    local worn = { name = 'Old Helm', id = 666, slot = 2, type = 'Armor', icon = 0 }
    local r = render(ctx, worn, { source = 'equipped' })
    check('equipped: look verbs offered', stub.drew(r, 'Item info') and stub.drew(r, 'Inspect it'))
    check('equipped: no sell-list rows', not stub.drew(r, 'Keep it') and not stub.drew(r, 'Always sell it'))
    check('equipped: no destroy', not stub.drew(r, 'Destroy it'))
    check('equipped: clicky submenu present', stub.drew(r, 'Clicky lists'))
    -- Rule 5: the submenu re-states the subject.
    check('equipped: submenu restates subject', (function()
        local seen = false
        for i, s in ipairs(r.buttons) do
            if tostring(s) == 'Clicky lists' then
                seen = tostring(r.buttons[i + 1] or ''):find('Old Helm', 1, true) ~= nil
            end
        end
        return seen
    end)(), table.concat(r.buttons, ','))
    stub.click = { Burn = true }
    render(ctx, worn, { source = 'equipped' })
    stub.click = {}
    check('equipped: clicky toggle adds', #spies.favAdd == 1 and spies.favAdd[1].list == 'Burn')
end

-- ---------------------------------------------------------------- popup wrapper (via ui_common)
do
    local spies = newSpies()
    local ctx = newCtx(spies)
    stub.openPopups = {}
    local closedFrame = stub.frame(function()
        uiCommon.renderItemContextMenu(ctx, plainItem(), { popupId = 'ItemContextInv_1', source = 'inv' })
    end)
    check('popup: closed draws nothing', not stub.drew(closedFrame, 'Rusty Sword'))
    check('popup: closed balanced', stub.balanced(closedFrame), stub.imbalance(closedFrame))

    stub.openPopups = { ItemContextInv_ = true }
    local openFrame = stub.frame(function()
        uiCommon.renderItemContextMenu(ctx, plainItem(), { popupId = 'ItemContextInv_1', source = 'inv' })
    end)
    stub.openPopups = {}
    check('popup: open draws the menu', stub.drew(openFrame, 'Rusty Sword') and stub.drew(openFrame, 'LOOK'))
    check('popup: open balanced (EndPopup paired)', stub.balanced(openFrame), stub.imbalance(openFrame))
end

-- ---------------------------------------------------------------- effect context (§7's seventh)
do
    local removed = nil
    local spies = newSpies()
    local ctx = newCtx(spies)
    local buff = { name = 'Spirit of Wolf', kind = 'buff', index = 3 }
    local env = { context = 'effect', where = 'buff',
                  onRemoveEffect = function(e) removed = e.name end }
    local r = render(ctx, buff, env)
    check('effect: identity first', r.text[1] == 'Spirit of Wolf', r.text[1])
    check('effect: where states the kind', r.text[2] == 'buff', r.text[2])
    check('effect: Remove it offered', stub.drew(r, 'Remove it'))
    check('effect: no item verbs leak in', not stub.drew(r, 'Keep it')
        and not stub.drew(r, 'Item info') and not stub.drew(r, 'Destroy it'))
    check('effect: balanced', stub.balanced(r), stub.imbalance(r))
    stub.click = { ['Remove it'] = true }
    render(ctx, buff, { context = 'effect', where = 'buff',
                        onRemoveEffect = function(e) removed = e.name end })
    stub.click = {}
    check('effect: remove fires with the subject', removed == 'Spirit of Wolf')
end

-- ---------------------------------------------------------------- equip row under trap TLO
do
    -- The mq stub's TLO trap returns nil from every call, so WornSlots resolves nil and
    -- the item reads as not wearable: the Equip row must be absent (not blocked).
    local spies = newSpies()
    local r = render(newCtx(spies), plainItem(), { source = 'inv' })
    check('equip: absent for non-wearable resolution', not stub.drew(r, 'Equip it'))
end

-- ---------------------------------------------------------------- summary
local missing = {}
for k, v in pairs(stub.missing) do missing[#missing + 1] = k .. 'x' .. v end
if #missing > 0 then print('\nunstubbed ImGui calls seen: ' .. table.concat(missing, ', ')) end

print(string.format('\n%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
