--[[
    The one context-menu builder (windows pass §7, mockups 24a/24b).

    Right-click is where most work happens, and before this file each view built its own
    menu block; the same augment offered different verbs in Bags vs Bank vs the slot map.
    Now there is ONE definition. Each row declares which contexts it appears in and what
    disables it; the seven contexts share one skeleton:

        bags · bank · equipped · augInserted · ornament · augEmpty · effect

    Anatomy — fixed, in this order (the eight rules of §7):

        [identity]   icon · name · where it is        (rule 1: you right-clicked one row
        ───────────                                     out of 158 — confirm which)
        LOOK         open, inspect, effects            (rule 2: four groups, fixed order)
        MOVE         send, equip, use
        RULES        keep / sell / reroll / lists      (rule 4: state shows as ✓, not a verb)
        ───────────
        destructive  destroy                           (rule 2: no heading — "past here,
                                                        be careful"; rule 6: hold shift,
                                                        stated in the row, NO confirm dialog)

    Rule 3: blocked rows stay in place and say why IN the row ("Bank it — no banker
    nearby"), never in a tooltip, so positions are stable and the answer is visible.
    Rule 5: submenus re-state their subject in a header row.
    Rule 7: the same object offers the same menu in every window — hosts differ only in
    `env.context`/`env.source`, never in row definitions.
    Rule 8 lives in the windows: anything used constantly ALSO has a button there; that
    duplication is deliberate and no reason to trim rows here.

    Copy style: every phrase is a question or a plain verb ("Anything better in my
    bags?", "Bank it", "Destroy it") — no menu-speak like "Compare" or "Filter".

    Verb parity: every verb of the pre-rebuild menus (ui_common's seven popup ids +
    reroll's) exists here — scripts keep their Alt Currency pair, reroll books their Use,
    consumables Use one/all, the favorites protection still blocks destroy, and the
    mainhand/offhand equip resolution moved over verbatim. The one deliberate behaviour
    change: destroy is shift-gated with NO confirmation dialog (rule 6) — the old
    pendingDestroy dialog path is not called from here.

    TLO note: like the menus this replaces, rows may read live TLOs (equip slots, stack
    sizes) — that code runs only while a menu is OPEN, never per-frame-per-row.
]]

require('ImGui')
local mq = require('mq')
local constants = require('itemui.constants')

local M = {}

M.CONTEXTS = {
    bags = true, bank = true, equipped = true,
    augInserted = true, ornament = true, augEmpty = true, effect = true,
}

--- Legacy opts.source → context. "sell"/"augments" views show items that live in bags.
local SOURCE_TO_CONTEXT = {
    inv = "bags", sell = "bags", augments = "bags",
    bank = "bank", equipped = "equipped", reroll = nil, -- reroll: resolved per item source
}

-- ---------------------------------------------------------------------- helpers

local function trim(s) return (s or ""):match("^%s*(.-)%s*$") or "" end

local function isAugment(item) return trim(item.type) == "Augmentation" end
local function isScriptItem(item) return (item.name or ""):lower():find("script of", 1, true) ~= nil end
local function isRerollBook(item) return (item.name or ""):lower():find("book of mythical reroll", 1, true) ~= nil end

local function whereString(item, env)
    if env.where and env.where ~= "" then return env.where end
    local ctxName = env.context
    if ctxName == "bank" then
        return string.format("Bank %s · Slot %s", tostring(item.bag or "?"), tostring(item.slot or "?"))
    elseif ctxName == "equipped" then
        return "Equipped"
    elseif ctxName == "augInserted" then
        return "In a socket"
    elseif ctxName == "ornament" then
        return "Ornament slot"
    elseif ctxName == "effect" then
        return tostring(item.kind or "effect")
    end
    return string.format("Bag %s · Slot %s", tostring(item.bag or "?"), tostring(item.slot or "?"))
end

--- Run game Inspect on the item (TLO) based on its raw source. Menu-open-only TLO.
local function doInspect(ctx, item, source)
    if not ctx or not item then return end
    if source == "inv" or source == "sell" or source == "augments" then
        local Me = mq.TLO and mq.TLO.Me
        local pack = Me and Me.Inventory and Me.Inventory("pack" .. (item.bag or 0))
        local tlo = pack and pack.Item and pack.Item(item.slot)
        if tlo and tlo.ID and tlo.ID() and tlo.ID() > 0 and tlo.Inspect then tlo.Inspect() end
    elseif source == "bank" then
        local Me = mq.TLO and mq.TLO.Me
        local bn = Me and Me.Bank and Me.Bank(item.bag)
        local sz = bn and bn.Container and bn.Container()
        local it = (bn and sz and sz > 0) and (bn.Item and bn.Item(item.slot)) or bn
        if it and it.ID and it.ID() and it.ID() > 0 and it.Inspect then it.Inspect() end
    elseif source == "equipped" and item.slot ~= nil and ctx.getEquipmentSlotNameForItemNotify then
        local Me = mq.TLO and mq.TLO.Me
        local slotName = ctx.getEquipmentSlotNameForItemNotify(item.slot)
        if slotName and Me and Me.Inventory then
            local inv = Me.Inventory(slotName)
            local slotIt = inv and inv.Item and inv.Item(1)
            if slotIt and slotIt.ID and slotIt.ID() and slotIt.ID() > 0 and slotIt.Inspect then slotIt.Inspect() end
        end
    end
end

--- Best equip slot for a bag item, moved verbatim from the old ui_common menu (the
--- mainhand/offhand pre-clear dance included). Menu-open-only TLO. Returns
--- bestSlotName, preClearSlots (nil when the item isn't wearable / nothing resolves).
local function computeEquipPlan(ctx, item)
    local SLOT_MAINHAND, SLOT_OFFHAND = 13, 14
    local bestSlotName, preClearSlots = nil, nil
    local Me = mq.TLO and mq.TLO.Me
    local pack = Me and Me.Inventory and Me.Inventory("pack" .. item.bag)
    local it = pack and pack.Item and pack.Item(item.slot)
    if not (it and it.WornSlots) then return nil, nil, false end
    local nSlots = it.WornSlots()
    if not (nSlots and nSlots > 0 and nSlots < 20) then return nil, nil, false end

    local validSlots, slotSet = {}, {}
    for i = 1, nSlots do
        local s = it.WornSlot and it.WornSlot(i)
        local idx = s and tonumber(tostring(s))
        if idx ~= nil and not slotSet[idx] then
            slotSet[idx] = true
            validSlots[#validSlots + 1] = idx
        end
    end
    local eqCache = ctx.equipmentCache or {}
    local getSlotName = ctx.getEquipmentSlotNameForItemNotify
    if slotSet[SLOT_MAINHAND] then
        local newIsPrimaryOnly = not slotSet[SLOT_OFFHAND]
        local equippedMHIsPrimaryOnly = false
        if not newIsPrimaryOnly and eqCache[SLOT_MAINHAND + 1] ~= nil then
            local mhInv = Me and Me.Inventory and Me.Inventory("mainhand")
            if mhInv and mhInv.ID and mhInv.ID() and mhInv.ID() > 0 and mhInv.WornSlots then
                local nMhSlots = mhInv.WornSlots()
                if nMhSlots and nMhSlots > 0 and nMhSlots < 20 then
                    local mhSlotSet = {}
                    for i = 1, nMhSlots do
                        local s = mhInv.WornSlot and mhInv.WornSlot(i)
                        local idx = s and tonumber(tostring(s))
                        if idx then mhSlotSet[idx] = true end
                    end
                    equippedMHIsPrimaryOnly = mhSlotSet[SLOT_MAINHAND] and not mhSlotSet[SLOT_OFFHAND]
                end
            end
        end
        if newIsPrimaryOnly or equippedMHIsPrimaryOnly then
            bestSlotName = getSlotName and getSlotName(SLOT_MAINHAND) or nil
            if getSlotName then
                preClearSlots = {}
                local ohName = getSlotName(SLOT_OFFHAND)
                local mhName = getSlotName(SLOT_MAINHAND)
                if ohName then preClearSlots[#preClearSlots + 1] = ohName end
                if mhName then preClearSlots[#preClearSlots + 1] = mhName end
            end
        else
            table.sort(validSlots, function(a, b)
                if a == SLOT_MAINHAND then return true end
                if b == SLOT_MAINHAND then return false end
                return a < b
            end)
            local bestIdx = nil
            for _, idx in ipairs(validSlots) do
                if eqCache[idx + 1] == nil then bestIdx = idx; break end
            end
            if not bestIdx and #validSlots > 0 then bestIdx = validSlots[1] end
            if bestIdx ~= nil then
                bestSlotName = getSlotName and getSlotName(bestIdx) or nil
            end
        end
    else
        table.sort(validSlots, function(a, b) return a < b end)
        local bestIdx = nil
        for _, idx in ipairs(validSlots) do
            if eqCache[idx + 1] == nil then bestIdx = idx; break end
        end
        if not bestIdx and #validSlots > 0 then bestIdx = validSlots[1] end
        if bestIdx ~= nil then
            bestSlotName = getSlotName and getSlotName(bestIdx) or nil
        end
    end
    -- wearable=true even when no slot resolved, so the row can render blocked (rule 3)
    return bestSlotName, preClearSlots, true
end

local function enqueueScriptConsume(ctx, payload)
    if not payload then return end
    if not ctx.uiState.pendingScriptConsume then
        ctx.uiState.pendingScriptConsume = payload
        return
    end
    local q = ctx.uiState.pendingScriptConsumeQueue or {}
    q[#q + 1] = payload
    ctx.uiState.pendingScriptConsumeQueue = q
    if ctx.setStatusMessage then ctx.setStatusMessage(string.format("Alt Currency queued (%d).", #q)) end
end

local function sellListState(ctx, item)
    local inKeep, inJunk = false, false
    if item.inKeep ~= nil and item.inJunk ~= nil then
        inKeep, inJunk = item.inKeep, item.inJunk
    elseif ctx.getSellStatusForItem then
        local _, _, k, j = ctx.getSellStatusForItem(item)
        inKeep, inJunk = k, j
    end
    return inKeep, inJunk
end

--- After an augment-list flip, refresh the item's cached sell status (kept verbatim
--- from the old menu so the Sell window's colours stay live).
local function refreshSellStatusAfterAugListChange(ctx, item)
    local inKeep, inJunk = item.inKeep, item.inJunk
    if ctx.getSellStatusForItem then
        local _, _, k, j = ctx.getSellStatusForItem(item)
        inKeep, inJunk = k, j
    end
    if ctx.updateSellStatusForItemName then ctx.updateSellStatusForItemName(item.name, inKeep, inJunk) end
    if ctx.storage and ctx.inventoryItems then ctx.storage.saveInventory(ctx.inventoryItems) end
end

-- ---------------------------------------------------------------------- row engine

--- One row per verb. Fields:
---   group     'look' | 'move' | 'rules' | 'destroy'
---   contexts  set of context names (nil = every context)
---   applies(ctx, item, env) -> bool     row exists for this subject
---   label(ctx, item, env)   -> string
---   checked(ctx, item, env) -> bool     rules rows: current state as ✓ (rule 4)
---   blocked(ctx, item, env) -> string   reason → row renders disabled with it (rule 3)
---   shiftGated = true                   destroy rows: disabled until shift, row says so (rule 6)
---   submenu(ctx, item, env)             renders its own BeginMenu block (rule 5)
---   action(ctx, item, env)              click handler
---   destructive = true                  red label
local ROWS

--- Subject family gates: scripts and reroll books keep their deliberately small menus
--- (identity + their own verbs); effect rows are their own family (the subject is a
--- buff/song, not an item); everything else gets the full skeleton.
local function subjectFamily(item, env)
    if env.context == "effect" then return "effect" end
    if isScriptItem(item) then return "script" end
    if isRerollBook(item) then return "book" end
    return "item"
end

ROWS = {
    -- ============================================================== LOOK
    {
        id = "open", group = "look", families = { item = true, script = true, book = true },
        contexts = { bags = true, bank = true, equipped = true, augInserted = true, ornament = true },
        applies = function(ctx) return ctx.addItemDisplayTab ~= nil end,
        label = function() return "Open it" end,
        action = function(ctx, item, env) ctx.addItemDisplayTab(item, env.source) end,
    },
    {
        id = "inspect", group = "look", families = { item = true },
        contexts = { bags = true, bank = true, equipped = true },
        applies = function() return true end,
        label = function() return "Inspect it (game window)" end,
        -- Legacy quirk kept on purpose: with an item on the cursor this click clears the
        -- cursor instead (the old menu did this; changing it mid-rebuild would surprise).
        action = function(ctx, item, env)
            if env.hasCursor and ctx.removeItemFromCursor then ctx.removeItemFromCursor()
            else doInspect(ctx, item, env.source) end
        end,
    },

    -- ============================================================== MOVE
    {
        id = "useConsume", group = "move", families = { item = true },
        contexts = { bags = true, bank = true },
        applies = function(ctx, item)
            local nameKey = trim(item.name)
            return ctx.consumables and nameKey ~= "" and ctx.consumables.isConsumable(nameKey)
                and item.bag ~= nil and item.slot ~= nil
        end,
        label = function() return "Use it (one)" end,
        action = function(ctx, item, env)
            local notifyLoc = (env.source == "bank") and "bank" or "pack"
            mq.cmdf('/itemnotify in %s%d %d rightmouseup', notifyLoc, item.bag, item.slot)
            if ctx.consumeItemAtSlot then ctx.consumeItemAtSlot(env.source, item.bag, item.slot) end
            if ctx.setStatusMessage then ctx.setStatusMessage("Used " .. (item.name or "item") .. ".") end
        end,
    },
    {
        id = "useConsumeAll", group = "move", families = { item = true },
        contexts = { bags = true, bank = true },
        applies = function(ctx, item)
            local nameKey = trim(item.name)
            return ctx.consumables and nameKey ~= "" and ctx.consumables.isConsumable(nameKey)
                and item.bag ~= nil and item.slot ~= nil
                and item.stackSize and item.stackSize > 1
        end,
        label = function(_, item) return string.format("Use all (x%d)", item.stackSize) end,
        action = function(ctx, item, env)
            enqueueScriptConsume(ctx, {
                bag = item.bag, slot = item.slot,
                source = (env.source == "augments") and "inv" or env.source,
                totalToConsume = item.stackSize, consumedSoFar = 0, nextClickAt = 0, itemName = item.name,
            })
        end,
    },
    {
        id = "useBook", group = "move", families = { book = true },
        contexts = { bags = true, bank = true },
        applies = function(_, item) return item.bag ~= nil and item.slot ~= nil end,
        label = function() return "Use it — consumed on use" end,
        action = function(ctx, item, env)
            local notifyLoc = (env.source == "bank") and "bank" or "pack"
            mq.cmdf('/itemnotify in %s%d %d rightmouseup', notifyLoc, item.bag, item.slot)
            if ctx.consumeItemAtSlot then ctx.consumeItemAtSlot(env.source, item.bag, item.slot) end
            if ctx.setStatusMessage then ctx.setStatusMessage("Used Book of Mythical Reroll.") end
        end,
    },
    {
        id = "scriptAll", group = "move", families = { script = true },
        contexts = { bags = true, bank = true },
        applies = function(_, item) return item.bag ~= nil and item.slot ~= nil end,
        label = function() return "Add all to Alt Currency" end,
        action = function(ctx, item, env)
            local Me = mq.TLO and mq.TLO.Me
            local it
            if env.source == "bank" then
                local bn = Me and Me.Bank and Me.Bank(item.bag)
                it = bn and bn.Item and bn.Item(item.slot)
            else
                local pack = Me and Me.Inventory and Me.Inventory("pack" .. (item.bag or 0))
                it = pack and pack.Item and pack.Item(item.slot)
            end
            local stack = (it and it.Stack and it.Stack()) or 0
            if stack < 1 then
                if ctx.setStatusMessage then ctx.setStatusMessage("Item not found or stack empty.") end
            else
                enqueueScriptConsume(ctx, {
                    bag = item.bag, slot = item.slot, source = env.source,
                    totalToConsume = stack, consumedSoFar = 0, nextClickAt = 0, itemName = item.name,
                })
            end
        end,
    },
    {
        id = "scriptSome", group = "move", families = { script = true },
        contexts = { bags = true, bank = true },
        applies = function() return true end,
        label = function() return "Add some to Alt Currency…" end,
        action = function(ctx, item, env)
            local maxQty = (item.stackSize and item.stackSize > 0) and item.stackSize or 1
            ctx.uiState.pendingQuantityPickup = {
                bag = item.bag, slot = item.slot,
                source = (env.source == "augments") and "inv" or env.source,
                maxQty = maxQty, itemName = item.name, intent = "script_consume",
            }
            ctx.uiState.pendingQuantityPickupTimeoutAt = mq.gettime()
                + (constants.TIMING and constants.TIMING.QUANTITY_PICKUP_TIMEOUT_MS or 60000)
            ctx.uiState.quantityPickerValue = "1"
            ctx.uiState.quantityPickerMax = maxQty
        end,
    },
    {
        id = "bankIt", group = "move", families = { item = true },
        contexts = { bags = true },
        applies = function(ctx, item)
            return ctx.moveInvToBank ~= nil and item.bag ~= nil and item.slot ~= nil
        end,
        label = function() return "Bank it" end,
        blocked = function(ctx, item, env)
            if not env.bankOpen then return "no banker nearby" end
            return nil
        end,
        action = function(ctx, item) ctx.moveInvToBank(item.bag, item.slot) end,
    },
    {
        id = "takeOut", group = "move", families = { item = true },
        contexts = { bank = true },
        applies = function(ctx, item)
            return ctx.moveBankToInv ~= nil and item.bag ~= nil and item.slot ~= nil
        end,
        label = function() return "Take it out" end,
        blocked = function(ctx, item, env)
            if not env.bankOpen then return "no banker nearby" end
            return nil
        end,
        action = function(ctx, item) ctx.moveBankToInv(item.bag, item.slot) end,
    },
    {
        id = "equip", group = "move", families = { item = true },
        contexts = { bags = true },
        applies = function(ctx, item, env)
            if item.bag == nil or item.slot == nil or isAugment(item) then return false end
            -- One TLO resolution per open menu, cached on env for label/blocked/action.
            if env._equipPlan == nil then
                local slotName, preClear, wearable = computeEquipPlan(ctx, item)
                env._equipPlan = { slotName = slotName, preClear = preClear, wearable = wearable }
            end
            return env._equipPlan.wearable
        end,
        label = function() return "Equip it" end,
        blocked = function(_, _, env)
            if not env._equipPlan.slotName then return "no slot takes it" end
            return nil
        end,
        action = function(ctx, item, env)
            local q = ctx.uiState.cursorActionQueue or {}
            q[#q + 1] = { type = "equip", bag = item.bag, slot = item.slot, name = item.name,
                          targetSlot = env._equipPlan.slotName, attuneable = item.attuneable,
                          preClearSlots = env._equipPlan.preClear }
            ctx.uiState.cursorActionQueue = q
        end,
    },

    -- ============================================================== RULES (rule 4: ✓ = state)
    {
        id = "keep", group = "rules", families = { item = true },
        contexts = { bags = true, bank = true },
        applies = function(ctx, _, env)
            return ctx.applySellListChange ~= nil and env.sellListSource
        end,
        label = function() return "Keep it — never sold" end,
        checked = function(ctx, item) local k = select(1, sellListState(ctx, item)); return k end,
        action = function(ctx, item)
            local inKeep, inJunk = sellListState(ctx, item)
            if inKeep then ctx.applySellListChange(item.name, false, inJunk)
            else ctx.applySellListChange(item.name, true, false) end
        end,
    },
    {
        id = "alwaysSell", group = "rules", families = { item = true },
        contexts = { bags = true, bank = true },
        applies = function(ctx, _, env)
            return ctx.applySellListChange ~= nil and env.sellListSource
        end,
        label = function() return "Always sell it" end,
        checked = function(ctx, item) local _, j = sellListState(ctx, item); return j end,
        action = function(ctx, item)
            local inKeep, inJunk = sellListState(ctx, item)
            if inJunk then ctx.applySellListChange(item.name, inKeep, false)
            else ctx.applySellListChange(item.name, false, true) end
        end,
    },
    {
        id = "reroll", group = "rules", families = { item = true },
        contexts = { bags = true, bank = true },
        applies = function(ctx, item, env)
            if not (ctx.rerollService and trim(item.name) ~= "") then return false end
            env._rerollList = ctx.resolveRerollList and ctx.resolveRerollList(item.name, item.type) or nil
            if not env._rerollList then return false end
            local itemId = item.id or item.ID
            env._onAug, env._onMyth = false, false
            if itemId then
                local augList = ctx.rerollService.getAugList and ctx.rerollService.getAugList() or {}
                local mythList = ctx.rerollService.getMythicalList and ctx.rerollService.getMythicalList() or {}
                for _, e in ipairs(augList) do if e.id == itemId then env._onAug = true; break end end
                for _, e in ipairs(mythList) do if e.id == itemId then env._onMyth = true; break end end
            end
            return true
        end,
        label = function(_, _, env)
            return (env._rerollList == "mythical") and "Reroll it (Mythical)" or "Reroll it (Aug)"
        end,
        checked = function(_, _, env)
            if env._rerollList == "mythical" then return env._onMyth end
            return env._onAug
        end,
        action = function(ctx, item, env)
            local itemId = item.id or item.ID
            local on = (env._rerollList == "mythical") and env._onMyth or env._onAug
            if on then
                if itemId and ctx.removeFromRerollList then ctx.removeFromRerollList(env._rerollList, itemId) end
            elseif ctx.requestAddToRerollList then
                local payload = (env.source == "bank")
                    and { bag = item.bag, slot = item.slot, id = itemId, name = item.name, source = "bank" }
                    or item
                ctx.requestAddToRerollList(env._rerollList, payload)
            end
        end,
    },
    {
        -- Legacy stragglers: membership on the OTHER list from before auto-routing.
        -- Rendered only when it actually happens, so the common case stays one row.
        id = "rerollOther", group = "rules", families = { item = true },
        contexts = { bags = true, bank = true },
        applies = function(_, _, env)
            if not env._rerollList then return false end
            local other = (env._rerollList == "mythical") and env._onAug or env._onMyth
            return other == true
        end,
        label = function(_, _, env)
            return (env._rerollList == "mythical") and "Reroll it (Aug) — old routing" or "Reroll it (Mythical) — old routing"
        end,
        checked = function() return true end,
        action = function(ctx, item, env)
            local itemId = item.id or item.ID
            local otherList = (env._rerollList == "mythical") and "aug" or "mythical"
            if itemId and ctx.removeFromRerollList then ctx.removeFromRerollList(otherList, itemId) end
        end,
    },
    {
        id = "rerollEntry", group = "rules", families = { item = true, script = true, book = true },
        contexts = { bags = true, bank = true },
        applies = function(_, _, env)
            return env.onRemoveFromRerollList ~= nil and env.rerollEntryId ~= nil
        end,
        label = function() return "On the reroll list" end,
        checked = function() return true end,
        action = function(_, _, env) env.onRemoveFromRerollList(env.rerollEntryId) end,
    },
    {
        id = "consumableFlag", group = "rules", families = { item = true },
        contexts = { bags = true, bank = true },
        applies = function(ctx, item)
            return ctx.consumables ~= nil and trim(item.name) ~= ""
        end,
        label = function() return "Treat it as a consumable" end,
        checked = function(ctx, item) return ctx.consumables.isConsumable(trim(item.name)) end,
        action = function(ctx, item)
            local nameKey = trim(item.name)
            if ctx.consumables.isConsumable(nameKey) then ctx.consumables.removeConsumable(nameKey)
            else ctx.consumables.addConsumable(nameKey) end
        end,
    },
    {
        id = "augAlwaysSell", group = "rules", families = { item = true },
        contexts = { bags = true, bank = true, augInserted = true },
        applies = function(ctx, item)
            return isAugment(item) and trim(item.name) ~= "" and ctx.augmentLists ~= nil
        end,
        label = function() return "Always sell this augment" end,
        checked = function(ctx, item)
            return ctx.augmentLists.isInAugmentAlwaysSellList
                and ctx.augmentLists.isInAugmentAlwaysSellList(trim(item.name)) or false
        end,
        action = function(ctx, item)
            local nameKey = trim(item.name)
            if ctx.augmentLists.isInAugmentAlwaysSellList(nameKey) then
                if ctx.augmentLists.removeFromAugmentAlwaysSellList(nameKey) then
                    refreshSellStatusAfterAugListChange(ctx, item)
                end
            else
                if ctx.augmentLists.addToAugmentAlwaysSellList(nameKey) then
                    refreshSellStatusAfterAugListChange(ctx, item)
                end
            end
        end,
    },
    {
        id = "augNeverLoot", group = "rules", families = { item = true },
        contexts = { bags = true, bank = true, augInserted = true },
        applies = function(ctx, item)
            return isAugment(item) and trim(item.name) ~= "" and ctx.augmentLists ~= nil
        end,
        label = function() return "Never loot this augment" end,
        checked = function(ctx, item)
            return ctx.augmentLists.isInAugmentNeverLootList
                and ctx.augmentLists.isInAugmentNeverLootList(trim(item.name)) or false
        end,
        action = function(ctx, item)
            local nameKey = trim(item.name)
            if ctx.augmentLists.isInAugmentNeverLootList(nameKey) then
                if ctx.augmentLists.removeFromAugmentNeverLootList(nameKey) then
                    refreshSellStatusAfterAugListChange(ctx, item)
                end
            else
                if ctx.augmentLists.addToAugmentNeverLootList(nameKey) then
                    refreshSellStatusAfterAugListChange(ctx, item)
                end
            end
        end,
    },
    {
        id = "clickyLists", group = "rules", families = { item = true },
        contexts = { bags = true, bank = true, equipped = true },
        applies = function(ctx, item)
            return ctx.favoritesService ~= nil and tonumber(item.id or item.ID) ~= nil
        end,
        submenu = function(ctx, item)
            if not ImGui.BeginMenu("Clicky lists") then return end
            -- Rule 5: the submenu re-states its subject before offering anything.
            ImGui.MenuItem(tostring(item.name or "?"), nil, false, false)
            ImGui.Separator()
            local fav = ctx.favoritesService
            local favItemId = tonumber(item.id or item.ID)
            local favLists = fav.getLists()
            if #favLists == 0 then
                ImGui.MenuItem("(create lists in the Clickies window)", nil, false, false)
            else
                local containing = fav.listsContaining(favItemId)
                for _, l in ipairs(favLists) do
                    local on = containing[l.name] == true
                    if ImGui.MenuItem(l.name, nil, on) then
                        if on then fav.removeItem(l.name, favItemId)
                        else fav.addItem(l.name, favItemId, item.name or "") end
                    end
                end
            end
            ImGui.EndMenu()
        end,
    },

    -- ============================================================== destructive (no heading)
    {
        -- Effect rows (§7's seventh context): the one verb the Effects window offered,
        -- kept instant — shedding a buff is not destroying property, so no shift gate.
        id = "effectRemove", group = "destroy", families = { effect = true },
        contexts = { effect = true },
        destructive = true,
        applies = function(_, _, env) return env.onRemoveEffect ~= nil end,
        label = function() return "Remove it" end,
        action = function(_, item, env) env.onRemoveEffect(item) end,
    },
    {
        id = "destroy", group = "destroy", families = { item = true },
        contexts = { bags = true, bank = true },
        destructive = true, shiftGated = true,
        applies = function(ctx, item)
            return item.bag ~= nil and item.slot ~= nil
                and ctx.requestDestroyItem ~= nil
        end,
        label = function(_, item)
            local stack = (item.stackSize and item.stackSize > 1) and item.stackSize or nil
            if stack then return string.format("Destroy it — the whole stack of %d", stack) end
            return "Destroy it"
        end,
        blocked = function(ctx, item)
            local favProtected = ctx.favoritesService
                and ctx.favoritesService.isProtected(tonumber(item.id or item.ID)) or false
            if favProtected then return "on a Clicky list" end
            return nil
        end,
        action = function(ctx, item)
            local stackSize = (item.stackSize and item.stackSize > 0) and item.stackSize or 1
            ctx.requestDestroyItem(item.bag, item.slot, item.name, stackSize)
        end,
    },
}

-- ---------------------------------------------------------------------- render

local GROUP_ORDER = { "look", "move", "rules", "destroy" }
local GROUP_HEADINGS = { look = "LOOK", move = "MOVE", rules = "RULES" }  -- destroy: separator only

local function rowVisible(row, ctx, item, env)
    if row.families and not row.families[env.family] then return false end
    if row.contexts and not row.contexts[env.context] then return false end
    if row.applies and not row.applies(ctx, item, env) then return false end
    return true
end

local function renderRow(row, ctx, item, env)
    if row.submenu then
        row.submenu(ctx, item, env)
        return
    end
    local label = row.label(ctx, item, env)
    local reason = row.blocked and row.blocked(ctx, item, env) or nil
    local shiftHeld = true
    if row.shiftGated then
        local io = ImGui.GetIO and ImGui.GetIO()
        shiftHeld = (io and io.KeyShift) and true or false
    end

    if reason then
        -- Rule 3: stays in place, reason in the row, no tooltip.
        ImGui.MenuItem(label .. " — " .. reason, nil, false, false)
        return
    end

    if row.shiftGated and not shiftHeld then
        -- Rule 6: the row itself says which modifier.
        ImGui.MenuItem(label .. " — hold shift", nil, false, false)
        return
    end

    local pushedColor = false
    if row.destructive and ctx.theme then
        ImGui.PushStyleColor(ImGuiCol.Text, ctx.theme.ToVec4(ctx.theme.Kit and ctx.theme.Kit.DestroyText or ctx.theme.Colors.Error))
        pushedColor = true
    end
    local checked = row.checked and (row.checked(ctx, item, env) and true or false) or false
    local clicked = ImGui.MenuItem(label, nil, checked)
    if pushedColor then ImGui.PopStyleColor(1) end
    if clicked and row.action then
        row.action(ctx, item, env)
    end
end

--- Menu CONTENTS only (host owns the popup begin/end). `env`:
---   source     legacy source string: inv|sell|augments|bank|equipped|reroll
---   context    one of M.CONTEXTS (derived from source when absent)
---   where      optional identity location override ("Bag 3 · Slot 7")
---   bankOpen, hasCursor
---   rerollEntryId, onRemoveFromRerollList   (reroll window rows)
function M.renderContents(ctx, item, env)
    if not ctx or not item or not env then return end
    env.source = env.source or "inv"
    env.context = env.context or SOURCE_TO_CONTEXT[env.source] or "bags"
    env.family = subjectFamily(item, env)
    env.sellListSource = env.source == "inv" or env.source == "sell" or env.source == "bank"
        or env.source == "augments" or env.source == "reroll"

    -- Rule 1: identity first, always. Icon · name · where.
    if ctx.drawItemIcon and item.icon and item.icon ~= 0 then
        pcall(function() ctx.drawItemIcon(item.icon, 18) end)
        ImGui.SameLine()
    end
    ImGui.Text(tostring(item.name or "?"))
    if ctx.theme and ctx.theme.TextFurniture then
        ctx.theme.TextFurniture(whereString(item, env))
    else
        ImGui.TextDisabled(whereString(item, env))
    end

    for _, groupName in ipairs(GROUP_ORDER) do
        local visible = {}
        for _, row in ipairs(ROWS) do
            if row.group == groupName and rowVisible(row, ctx, item, env) then
                visible[#visible + 1] = row
            end
        end
        if #visible > 0 then
            ImGui.Separator()
            local heading = GROUP_HEADINGS[groupName]
            if heading then
                if ctx.theme and ctx.theme.TextFurniture then ctx.theme.TextFurniture(heading)
                else ImGui.TextDisabled(heading) end
            end
            for _, row in ipairs(visible) do
                renderRow(row, ctx, item, env)
            end
        end
    end
end

--- Popup wrapper: anchored to the last drawn item (BeginPopupContextItem) or opened by
--- id from elsewhere in the row (OpenPopup + BeginPopup) — both host styles survive.
function M.render(ctx, item, env)
    if not ctx or not item or not env or not env.popupId then return end
    local opened = ImGui.BeginPopupContextItem(env.popupId) or ImGui.BeginPopup(env.popupId)
    if not opened then return end
    M.renderContents(ctx, item, env)
    ImGui.EndPopup()
end

return M
