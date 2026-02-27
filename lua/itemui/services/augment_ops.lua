--[[
    ItemUI - Augment Operations Service
    Insert/remove augments: state machines (Task 6.4), no mq.delay in op flow.
    Part of CoOpt UI — EverQuest EMU Companion
--]]

local mq = require('mq')
local itemHelpers = require('itemui.utils.item_helpers')
local constants = require('itemui.constants')

local M = {}
local deps  -- set by init()

-- Per 4.2 state ownership: insert/remove queues and confirmation/cursor state
local state = {
    pendingRemoveAugment = nil,
    pendingInsertAugment = nil,
    waitingForRemoveConfirmation = false,
    waitingForInsertConfirmation = false,
    waitingForInsertCursorClear = false,
    waitingForRemoveCursorPopulated = false,
    insertCursorClearTimeoutAt = nil,
    removeCursorPopulatedTimeoutAt = nil,
    insertConfirmationSetAt = nil,
    removeConfirmationSetAt = nil,
    removeAllQueue = nil,
    optimizeQueue = nil,
}
function M.getState()
    return state
end

local T = constants.TIMING
local INSERT_DELAY_MS = T.AUGMENT_INSERT_DELAY_MS
local REMOVE_OPEN_DELAY_MS = T.AUGMENT_REMOVE_OPEN_DELAY_MS
local REMOVE_AFTER_RIGHTCLICK_MS = 150
local DISPLAY_OPEN_TIMEOUT_MS = T.AUGMENT_DISPLAY_OPEN_TIMEOUT_MS or 4000
local SETTLE_AFTER_CLICK_MS = T.AUGMENT_SETTLE_AFTER_CLICK_MS or 200
local REMOVE_MENU_CONTROL = nil

function M.init(d)
    deps = d
end

-- ============================================================================
-- Helpers
-- ============================================================================

local function resolveItemDisplayWindowName()
    for i = 1, 6 do
        local di = mq.TLO and mq.TLO.DisplayItem and mq.TLO.DisplayItem(i)
        if di and di.Window then
            local win = di.Window
            local ok, nameVal = pcall(function()
                if win.Name then return win.Name() end
                return nil
            end)
            if ok and nameVal and type(nameVal) == "string" and nameVal ~= "" and nameVal ~= "TRUE" then
                return nameVal
            end
        end
    end
    return "ItemDisplayWindow"
end

--- Return true if the game's Item Display window is open.
function M.isItemDisplayWindowOpen()
    local name = resolveItemDisplayWindowName()
    if not name or name == "" then return false end
    local w = mq.TLO and mq.TLO.Window and mq.TLO.Window(name)
    if not w or not w.Open then return false end
    local ok, openVal = pcall(function() return w.Open() end)
    return ok and openVal == true
end

--- Close the game's Item Display window. No-op if already closed.
function M.closeItemDisplayWindow()
    if not M.isItemDisplayWindowOpen() then return end
    local name = resolveItemDisplayWindowName()
    if not name or name == "" then return end
    mq.cmdf('/invoke ${Window[%s].DoClose}', name)
end

-- ============================================================================
-- Insert: state machine (phase_pickup -> settle -> inspect | /insertaug -> wait_display_open -> click_socket -> wait_confirm)
-- ============================================================================

function M.insertAugment(targetItem, augmentItem, slotIndex, targetBag, targetSlot, targetSource)
    if not targetItem or not augmentItem then
        deps.setStatusMessage("No target or augment selected.")
        return false
    end
    local src = (augmentItem.source or "inv"):lower()
    local bag = augmentItem.bag or 0
    local slot = augmentItem.slot or 0
    if bag <= 0 or slot <= 0 then
        deps.setStatusMessage("Invalid augment location.")
        return false
    end
    if src == "bank" and deps.isBankWindowOpen and not deps.isBankWindowOpen() then
        deps.setStatusMessage("Open bank first to use augment from bank.")
        return false
    end
    if deps.hasItemOnCursor and deps.hasItemOnCursor() then
        deps.setStatusMessage("Clear cursor first.")
        return false
    end
    state.pendingInsertAugment = {
        targetItem = targetItem,
        augmentItem = augmentItem,
        slotIndex = slotIndex,
        targetBag = targetBag,
        targetSlot = targetSlot,
        targetSource = targetSource,
        phase = "pickup",
    }
    return true
end

function M.advanceInsert(now)
    local pa = state.pendingInsertAugment
    if not pa then return end
    now = now or mq.gettime()
    local phase = pa.phase or "pickup"
    local src = (pa.augmentItem and (pa.augmentItem.source or "inv")) and (pa.augmentItem.source or "inv"):lower() or "inv"
    local bag = (pa.augmentItem and pa.augmentItem.bag) or 0
    local slot = (pa.augmentItem and pa.augmentItem.slot) or 0

    if phase == "pickup" then
        if deps.hasItemOnCursor and deps.hasItemOnCursor() then
            deps.setStatusMessage("Clear cursor first.")
            state.pendingInsertAugment = nil
            return
        end
        if src == "bank" and deps.isBankWindowOpen and not deps.isBankWindowOpen() then
            deps.setStatusMessage("Open bank first to use augment from bank.")
            state.pendingInsertAugment = nil
            return
        end
        if src == "bank" then
            mq.cmdf('/itemnotify in bank%d %d leftmouseup', bag, slot)
        else
            mq.cmdf('/itemnotify in pack%d %d leftmouseup', bag, slot)
        end
        pa.phase = "settle_pickup"
        pa.phaseEnteredAt = now
        return
    end

    if phase == "settle_pickup" then
        if (now - (pa.phaseEnteredAt or 0)) < INSERT_DELAY_MS then return end
        local slotIndex, targetBag, targetSlot, targetSource = pa.slotIndex, pa.targetBag, pa.targetSlot, pa.targetSource
        if slotIndex and slotIndex >= 1 and slotIndex <= 6 and targetBag and targetSlot and targetSource then
            local it = deps.getItemTLO and deps.getItemTLO(targetBag, targetSlot, targetSource)
            if not it or not it.Inspect then
                deps.setStatusMessage("Could not get target item to inspect.")
                state.pendingInsertAugment = nil
                return
            end
            it.Inspect()
            pa.phase = "wait_display_open"
            pa.phaseEnteredAt = now
        else
            local targetId = (pa.targetItem and (pa.targetItem.id or pa.targetItem.ID)) or 0
            local targetName = (pa.targetItem and (pa.targetItem.name or pa.targetItem.Name)) or ""
            if targetId and targetId ~= 0 then
                mq.cmdf('/insertaug %d', targetId)
            elseif targetName and targetName ~= "" then
                mq.cmdf('/insertaug "%s"', targetName:gsub('"', '\\"'):sub(1, 64))
            else
                deps.setStatusMessage("Target item has no ID or name.")
                state.pendingInsertAugment = nil
                return
            end
            if deps.setWaitingForInsertConfirmation then deps.setWaitingForInsertConfirmation(true) end
            state.insertConfirmationSetAt = now
            state.pendingInsertAugment = nil
            deps.setStatusMessage(string.format("Inserted %s", (pa.augmentItem and pa.augmentItem.name) or "augment"))
        end
        return
    end

    if phase == "wait_display_open" then
        if (now - (pa.phaseEnteredAt or 0)) > DISPLAY_OPEN_TIMEOUT_MS then
            deps.setStatusMessage("Item Display did not open; insert timed out.")
            M.closeItemDisplayWindow()
            state.pendingInsertAugment = nil
            return
        end
        if not M.isItemDisplayWindowOpen() then return end
        if (now - (pa.phaseEnteredAt or 0)) < SETTLE_AFTER_CLICK_MS then return end
        local windowName = resolveItemDisplayWindowName()
        local controlName = string.format("IDW_Socket_Slot_%d_Item", pa.slotIndex or 1)
        mq.cmdf('/notify %s %s leftmouseup', windowName, controlName)
        pa.phase = "settle_after_click"
        pa.phaseEnteredAt = now
        return
    end

    if phase == "settle_after_click" then
        if (now - (pa.phaseEnteredAt or 0)) < SETTLE_AFTER_CLICK_MS then return end
        if deps.setWaitingForInsertConfirmation then deps.setWaitingForInsertConfirmation(true) end
        state.insertConfirmationSetAt = now
        state.pendingInsertAugment = nil
        deps.setStatusMessage(string.format("Inserted %s into slot %d", (pa.augmentItem and pa.augmentItem.name) or "augment", pa.slotIndex or 0))
    end
end

-- ============================================================================
-- Remove: state machine (phase_inspect -> wait_display_open -> click_socket -> settle -> click_remove -> wait_confirm)
-- ============================================================================

function M.removeAugment(bag, slot, source, slotIndex)
    if not bag or not slot or not source or not slotIndex or slotIndex < 1 or slotIndex > 6 then
        deps.setStatusMessage("Invalid slot for remove.")
        return false
    end
    local it = deps.getItemTLO and deps.getItemTLO(bag, slot, source)
    if not it or not it.Inspect then
        deps.setStatusMessage("Could not get item to inspect.")
        return false
    end
    state.pendingRemoveAugment = {
        bag = bag,
        slot = slot,
        source = source,
        slotIndex = slotIndex,
        phase = "inspect",
    }
    return true
end

function M.advanceRemove(now)
    local ra = state.pendingRemoveAugment
    if not ra then return end
    now = now or mq.gettime()
    local phase = ra.phase or "inspect"

    if phase == "inspect" then
        local it = deps.getItemTLO and deps.getItemTLO(ra.bag, ra.slot, ra.source)
        if it and it.Inspect then it.Inspect() end
        ra.phase = "wait_display_open"
        ra.phaseEnteredAt = now
        return
    end

    if phase == "wait_display_open" then
        if (now - (ra.phaseEnteredAt or 0)) > DISPLAY_OPEN_TIMEOUT_MS then
            deps.setStatusMessage("Item Display did not open; remove timed out.")
            M.closeItemDisplayWindow()
            state.pendingRemoveAugment = nil
            return
        end
        if not M.isItemDisplayWindowOpen() then return end
        if (now - (ra.phaseEnteredAt or 0)) < REMOVE_OPEN_DELAY_MS then return end
        local windowName = resolveItemDisplayWindowName()
        local controlName = string.format("IDW_Socket_Slot_%d_Item", ra.slotIndex)
        mq.cmdf('/notify %s %s leftmouseup', windowName, controlName)
        ra.phase = "settle_after_click"
        ra.phaseEnteredAt = now
        return
    end

    if phase == "settle_after_click" then
        if (now - (ra.phaseEnteredAt or 0)) < REMOVE_AFTER_RIGHTCLICK_MS then return end
        if REMOVE_MENU_CONTROL then
            local windowName = resolveItemDisplayWindowName()
            mq.cmdf('/notify %s %s leftmouseup', windowName, REMOVE_MENU_CONTROL)
        end
        ra.phase = "wait_confirm"
        ra.phaseEnteredAt = now
        if deps.setWaitingForRemoveConfirmation then deps.setWaitingForRemoveConfirmation(true) end
        state.removeConfirmationSetAt = now
        state.pendingRemoveAugment = nil
        deps.setStatusMessage(string.format("Remove augment from slot %d (check game window for dialogs)", ra.slotIndex))
    end
end

return M
