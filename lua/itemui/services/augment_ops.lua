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

-- The ornament (aug slot 5 in this UI's TLO reads) renders in a DEDICATED
-- Appearance socket control on RoF2 - IDW_Appearance_Socket_Item, not
-- IDW_Socket_Slot_5_Item (eqlib emu UI.h). Clicking the numbered name hit
-- nothing, which was the field's "cannot place an ornament into it". Removal
-- needs NO distiller server-side (EQEmu Handle_OP_AugmentItem: safe removal iff
-- the aug's AugDistiller == 0, and ornaments ship 0); the Yes/No confirm still
-- appears and the shared confirm machinery answers it. /removeaug is NOT usable
-- for ornaments: it refuses to act without SOME distiller in inventory even
-- though none would be consumed - the /notify path below is the one that works.
local ORNAMENT_SLOT_INDEX = 5  -- keep in sync with tooltip_data.ORNAMENT_SLOT_INDEX
local function socketControlName(slotIndex)
    if (tonumber(slotIndex) or 0) == ORNAMENT_SLOT_INDEX then
        return "IDW_Appearance_Socket_Item"
    end
    return string.format("IDW_Socket_Slot_%d_Item", slotIndex or 1)
end

-- Note: inserts are started by app.lua's ctx.insertAugment, which writes the
-- pendingInsertAugment queue entry directly (proxied to this module's state).
function M.advanceInsert(now)
    local pa = state.pendingInsertAugment
    if not pa then return end
    now = now or mq.gettime()
    local phase = pa.phase or "pickup"
    local src = (pa.augmentItem and (pa.augmentItem.source or "inv")) and (pa.augmentItem.source or "inv"):lower() or "inv"
    local bag = (pa.augmentItem and pa.augmentItem.bag) or 0
    local slot = (pa.augmentItem and pa.augmentItem.slot) or 0

    if phase == "pickup" then
        -- Close any existing Item Display window so our Inspect() opens a clean one
        -- and /notify targets the correct window.
        M.closeItemDisplayWindow()
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
        -- Mark this as an intentional pickup so phase1b click-through protection doesn't autoinv it.
        if deps.markExpectedPickup then deps.markExpectedPickup(bag, slot, src) end
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
        if deps.hasItemOnCursor and not deps.hasItemOnCursor() then
            if (now - (pa.phaseEnteredAt or 0)) > DISPLAY_OPEN_TIMEOUT_MS then
                deps.setStatusMessage("Failed to pick up augment on cursor.")
                state.pendingInsertAugment = nil
            end
            return
        end
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
        -- Match the original, working flow: wait full display-open settle before socket click.
        if (now - (pa.phaseEnteredAt or 0)) < REMOVE_OPEN_DELAY_MS then return end
        local windowName = resolveItemDisplayWindowName()
        local controlName = socketControlName(pa.slotIndex or 1)
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
    end
end

-- ============================================================================
-- Remove: state machine (phase_inspect -> wait_display_open -> click_socket -> settle -> click_remove -> wait_confirm)
-- ============================================================================

-- Note: removes are started by app.lua's ctx.removeAugment, which writes the
-- pendingRemoveAugment queue entry directly (proxied to this module's state).
function M.advanceRemove(now)
    local ra = state.pendingRemoveAugment
    if not ra then return end
    now = now or mq.gettime()
    local phase = ra.phase or "inspect"

    if phase == "inspect" then
        -- Close any existing Item Display window so our Inspect() opens a clean one.
        M.closeItemDisplayWindow()
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
        local controlName = socketControlName(ra.slotIndex)
        mq.cmdf('/notify %s %s leftmouseup', windowName, controlName)
        ra.phase = "settle_after_click"
        ra.phaseEnteredAt = now
        return
    end

    if phase == "settle_after_click" then
        if (now - (ra.phaseEnteredAt or 0)) < REMOVE_AFTER_RIGHTCLICK_MS then return end
        -- Hand-off to the waitingForRemoveConfirmation flag; the queue entry is discarded
        -- below, so no phase transition is written (mirrors advanceInsert).
        if deps.setWaitingForRemoveConfirmation then deps.setWaitingForRemoveConfirmation(true) end
        state.removeConfirmationSetAt = now
        state.pendingRemoveAugment = nil
        deps.setStatusMessage(string.format("Remove augment from slot %d (check game window for dialogs)", ra.slotIndex))
    end
end

return M
