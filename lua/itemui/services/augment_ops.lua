--[[
    ItemUI - Augment Operations Service
    Insert/remove augments: pickup + /insertaug, open game Item Display + /notify for remove.
    Part of CoOpt UI — EverQuest EMU Companion
--]]

local mq = require('mq')
local itemHelpers = require('itemui.utils.item_helpers')
local constants = require('itemui.constants')
local pluginShim = require('itemui.services.plugin_shim')

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

local INSERT_DELAY_MS = constants.TIMING.AUGMENT_INSERT_DELAY_MS
local REMOVE_OPEN_DELAY_MS = constants.TIMING.AUGMENT_REMOVE_OPEN_DELAY_MS
local REMOVE_AFTER_RIGHTCLICK_MS = 150
-- Control name for "Remove" / "Extract" in the context menu after right-clicking socket. Discover via Window Inspector.
local REMOVE_MENU_CONTROL = nil  -- e.g. "IDW_RemoveAugmentButton" or popup window name + control

function M.init(d)
    deps = d
end

-- ============================================================================
-- Insert augment: put augment on cursor, then either /insertaug target (first slot)
-- or open Item Display and click the selected socket (slotIndex 1-based).
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

--- Return true if the game's Item Display window is open (so we can skip close or clear waiting state).
function M.isItemDisplayWindowOpen()
    local name = resolveItemDisplayWindowName()
    if not name or name == "" then return false end
    local win = pluginShim.window()
    if win and win.isWindowOpen then
        local ok, openVal = pcall(function() return win.isWindowOpen(name) end)
        if ok and openVal == true then return true end
        if ok and openVal == false then return false end
    end
    local w = mq.TLO and mq.TLO.Window and mq.TLO.Window(name)
    if not w or not w.Open then return false end
    local ok, openVal = pcall(function() return w.Open() end)
    return ok and openVal == true
end

--- Close the game's Item Display window. No-op if already closed. Prefer DoClose (reliable on custom UIs).
function M.closeItemDisplayWindow()
    if not M.isItemDisplayWindowOpen() then return end
    local name = resolveItemDisplayWindowName()
    if not name or name == "" then return end
    mq.cmdf('/invoke ${Window[%s].DoClose}', name)
    mq.delay(50)
end

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
    -- Pick up augment (plugin has no pickupItem; use /itemnotify)
    if src == "bank" then
        mq.cmdf('/itemnotify in bank%d %d leftmouseup', bag, slot)
    else
        mq.cmdf('/itemnotify in pack%d %d leftmouseup', bag, slot)
    end
    mq.delay(INSERT_DELAY_MS)

    -- Specific slot: open Item Display for target item, then click that socket (game places cursor item into it)
    if slotIndex and slotIndex >= 1 and slotIndex <= 6 and targetBag and targetSlot and targetSource then
        local it = deps.getItemTLO and deps.getItemTLO(targetBag, targetSlot, targetSource)
        if not it or not it.Inspect then
            deps.setStatusMessage("Could not get target item to inspect.")
            return false
        end
        it.Inspect()
        mq.delay(REMOVE_OPEN_DELAY_MS)
        local windowName = resolveItemDisplayWindowName()
        local controlName = string.format("IDW_Socket_Slot_%d_Item", slotIndex)
        local win = pluginShim.window()
        if win and win.click then
            win.click(windowName, controlName)
        else
            mq.cmdf('/notify %s %s leftmouseup', windowName, controlName)
        end
        mq.delay(200)
        if deps.setWaitingForInsertConfirmation then deps.setWaitingForInsertConfirmation(true) end
        -- Phase 0: no mid-op scan; main loop runs one scan when insert completes (cursor clear)
        deps.setStatusMessage(string.format("Inserted %s into slot %d", augmentItem.name or "augment", slotIndex))
        return true
    end

    -- First-available slot: use /insertaug (no slot parameter)
    local targetId = targetItem.id or targetItem.ID
    local targetName = targetItem.name or targetItem.Name
    if targetId and targetId ~= 0 then
        mq.cmdf('/insertaug %d', targetId)
    elseif targetName and targetName ~= "" then
        mq.cmdf('/insertaug "%s"', targetName:gsub('"', '\\"'):sub(1, 64))
    else
        deps.setStatusMessage("Target item has no ID or name.")
        return false
    end
    mq.delay(200)
    if deps.setWaitingForInsertConfirmation then deps.setWaitingForInsertConfirmation(true) end
    -- Phase 0: no mid-op scan; main loop runs one scan when insert completes (cursor clear)
    deps.setStatusMessage(string.format("Inserted %s", augmentItem.name or "augment"))
    return true
end

-- ============================================================================
-- Remove augment: open game Item Display, right-click socket, click Remove menu
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
    it.Inspect()
    mq.delay(REMOVE_OPEN_DELAY_MS)
    -- Resolve the game Item Display window name: DisplayItem[n].Window.Name (1-based index 1..6)
    local windowName
    for i = 1, 6 do
        local di = mq.TLO and mq.TLO.DisplayItem and mq.TLO.DisplayItem(i)
        if di and di.Window then
            local win = di.Window
            local ok, nameVal = pcall(function()
                if win.Name then return win.Name() end
                return nil
            end)
            if ok and nameVal and type(nameVal) == "string" and nameVal ~= "" and nameVal ~= "TRUE" then
                windowName = nameVal
                break
            end
        end
    end
    if not windowName or windowName == "" then
        windowName = "ItemDisplayWindow"  -- fallback from EQUI_ItemDisplay.xml
    end
    local controlName = string.format("IDW_Socket_Slot_%d_Item", slotIndex)
    -- Use leftmouseup on the socket (per game UI; rightmouseup can be invalid on this control)
    local win = pluginShim.window()
    if win and win.click then
        win.click(windowName, controlName)
    else
        mq.cmdf('/notify %s %s leftmouseup', windowName, controlName)
    end
    mq.delay(REMOVE_AFTER_RIGHTCLICK_MS)
    if REMOVE_MENU_CONTROL then
        mq.cmdf('/notify %s %s leftmouseup', windowName, REMOVE_MENU_CONTROL)
        mq.delay(150)
    end
    -- Confirmation dialog is handled in main loop (waitingForRemoveConfirmation) so we catch it
    -- whenever it appears after user clicks Remove. Tell init we're expecting it.
    if deps.setWaitingForRemoveConfirmation then
        deps.setWaitingForRemoveConfirmation(true)
    end
    -- Phase 0: no mid-op scan; main loop runs one scan when remove completes (cursor has item)
    deps.setStatusMessage(string.format("Remove augment from slot %d (check game window for dialogs)", slotIndex))
    return true
end

return M
