--[[
    Shared UI helpers (Phase 6).
    Single path for refresh buttons across Inventory, Sell, Bank, Augments, etc.
    The right-click context menu lives in components/context_menu.lua (windows pass §7);
    the two render*ContextMenu entries below stay as the stable call surface for views.
--]]

require('ImGui')
local registry = require('itemui.core.registry')
local contextMenu = require('itemui.components.context_menu')

local M = {}

--- Top-right "Lock" checkbox for companion windows. Call right after ImGui.Begin
--- (before other content): draws at the window's top-right, then restores the
--- cursor so the caller's layout is unaffected. Locked windows survive ESC's
--- LIFO close AND every close-all gesture (Shift+Q, /itemui hide, hub X);
--- they close only via their own X or by unticking Lock.
function M.renderWindowLock(ctx, id)
    local cx, cy = ImGui.GetCursorPos()
    -- Right-align by MEASURED width, never past (windowWidth - WindowPadding.x).
    -- A fixed offset here once let the checkbox overshoot the content edge; in an
    -- AlwaysAutoResize window (Command Center) auto-fit then grows the window to the
    -- overshoot every frame — the window widens forever.
    local style = ImGui.GetStyle and ImGui.GetStyle() or nil
    local innerX = (style and style.ItemInnerSpacing and style.ItemInnerSpacing.x) or 4
    local padX = (style and style.WindowPadding and style.WindowPadding.x) or 8
    local boxW = (ImGui.GetFrameHeight and ImGui.GetFrameHeight()) or 20
    local textW = ImGui.CalcTextSize("Lock") or 28
    local x = math.floor(ImGui.GetWindowWidth() - padX - (boxW + innerX + textW))
    if x < cx then x = cx end
    ImGui.SetCursorPos(x, cy)
    local locked = registry.isPinned(id)
    local v = ImGui.Checkbox("Lock##winlock_" .. id, locked)
    if v ~= locked then
        registry.setPinned(id, v)
        if ctx and ctx.scheduleLayoutSave then ctx.scheduleLayoutSave() end
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        local keyName = (ctx and ctx.getItemUIToggleKeyDisplay and ctx.getItemUIToggleKeyDisplay()) or "Shift+Q"
        ImGui.Text(string.format("Lock this window: it stays up while you play. ESC, the toggle keybind (%s),", keyName))
        ImGui.Text("/itemui hide, and the hub's X all leave it open. Close it with its own X, or untick Lock.")
        ImGui.EndTooltip()
    end
    ImGui.SetCursorPos(cx, cy)
end

--- Return ImVec4 for Name column sell-status color: green = Keep, red = Will Sell, white = Neutral.
--- Uses ctx.getSellStatusForItem(item) when item.willSell/inKeep not set; otherwise row state.
--- @param ctx table with theme, getSellStatusForItem
--- @param item table row with optional willSell, inKeep (or from getSellStatusForItem)
--- @return ImVec4 color for ImGui.TextColored or PushStyleColor(ImGuiCol.Text, color)
function M.getSellStatusNameColor(ctx, item)
    if not ctx or not item then return ImVec4(1, 1, 1, 1) end
    -- Fall back to a live status computation only when willSell is unknown.
    -- Stored rows persist inKeep only when true, so nil inKeep just means "not kept".
    local willSell, inKeep = item.willSell, item.inKeep
    if willSell == nil then
        local ok, st, ws, k = pcall(function()
            if ctx.getSellStatusForItem then
                local statusText, w, inKeepVal, inJunkVal = ctx.getSellStatusForItem(item)
                return statusText, w, inKeepVal
            end
            return "", false, false
        end)
        if ok and ws ~= nil then willSell = ws; inKeep = k end
    end
    if willSell then
        return ctx.theme and ctx.theme.ToVec4(ctx.theme.Colors.Error) or ImVec4(0.9, 0.25, 0.25, 1)
    end
    if inKeep then
        return ctx.theme and ctx.theme.ToVec4(ctx.theme.Colors.Success) or ImVec4(0.25, 0.75, 0.35, 1)
    end
    return ImVec4(1, 1, 1, 1)
end

--- Format a sellReason string for display and return the display text + color.
--- Centralizes the Epic→EpicQuest rename and status-specific coloring
--- so views don't duplicate this logic.
--- @param reason string raw sellReason or statusText (e.g. "Epic", "NoDrop", "RerollList")
--- @param willSell boolean whether the item will be sold
--- @param theme table ctx.theme with ToVec4 and Colors
--- @return string displayText, ImVec4 color
function M.formatSellStatus(reason, willSell, theme)
    local text = (reason and reason ~= "") and reason or "\xe2\x80\x94"
    local color = willSell and theme.ToVec4(theme.Colors.Error) or theme.ToVec4(theme.Colors.Success)
    if text == "Epic" then
        text = "EpicQuest"
        color = theme.ToVec4(theme.Colors.EpicQuest or theme.Colors.Muted)
    elseif text == "Favorites" then
        -- rules.lua's raw reason predates the "Clickies" branding
        text = "ClickyList"
    elseif text == "NoDrop" or text == "NoTrade" then
        color = theme.ToVec4(theme.Colors.Error)
    elseif text == "RerollList" and theme.Colors.RerollList then
        color = theme.ToVec4(theme.Colors.RerollList)
    end
    return text, color
end

--- Resolve sellReason/willSell from item row state or fallback to getSellStatusForItem.
--- Returns displayText, color ready for ImGui.TextColored.
--- @param ctx table with theme, getSellStatusForItem
--- @param item table with optional sellReason, willSell
--- @return string displayText, ImVec4 color
function M.resolveSellStatusDisplay(ctx, item)
    local reason, willSell = "", false
    if item.sellReason ~= nil and item.willSell ~= nil then
        reason = item.sellReason or ""
        willSell = item.willSell
    elseif ctx.getSellStatusForItem then
        reason, willSell = ctx.getSellStatusForItem(item)
    end
    return M.formatSellStatus(reason, willSell, ctx.theme)
end

--- Draw a Refresh button with tooltip and optional status messages. Call onRefresh() on click.
--- @param ctx table context (setStatusMessage, etc.)
--- @param id string unique button id (e.g. "Refresh##Inv")
--- @param tooltip string hover tooltip
--- @param onRefresh function() called on click
--- @param opts table optional: width (number), messageBefore (string), messageAfter (string)
function M.renderRefreshButton(ctx, id, tooltip, onRefresh, opts)
    opts = opts or {}
    local w = opts.width or 70
    if ImGui.Button(id, ImVec2(w, 0)) then
        if opts.messageBefore and ctx.setStatusMessage then ctx.setStatusMessage(opts.messageBefore) end
        onRefresh()
        if opts.messageAfter and ctx.setStatusMessage then ctx.setStatusMessage(opts.messageAfter) end
    end
    if tooltip and tooltip ~= "" and ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text(tooltip)
        ImGui.EndTooltip()
    end
end

--- Legacy opts → the builder's env. One translation, both entry points share it.
local function menuEnv(opts)
    return {
        popupId = opts.popupId,
        source = opts.source,
        context = opts.context,
        where = opts.where,
        bankOpen = opts.bankOpen or false,
        hasCursor = opts.hasCursor or false,
        rerollEntryId = opts.rerollEntryId,
        onRemoveFromRerollList = opts.onRemoveFromRerollList,
    }
end

--- Shared right-click context menu for item views. Call after drawing the item (icon) so
--- the last item is the popup trigger. Also supports opening via OpenPopup(popupId) from name column.
--- opts.source: "inv"|"bank"|"sell"|"equipped"|"augments"|"reroll".
--- opts.popupId must be unique per row (e.g. "ItemContextInv_"..rid). opts.bankOpen, opts.hasCursor.
--- Since the windows pass, this is a thin shell over components/context_menu.lua — the one
--- builder — so every host shows the same menu for the same object (§7 rule 7).
function M.renderItemContextMenu(ctx, item, opts)
    if not ctx or not item or not opts or not opts.popupId then return end
    contextMenu.render(ctx, item, menuEnv(opts))
end

--- Menu CONTENTS only (no popup begin/end) - for hosts that manage the popup
--- themselves (e.g. native_hover's Shift+Right-click menu over native slots).
function M.renderItemContextMenuContents(ctx, item, opts)
    if not ctx or not item or not opts then return end
    contextMenu.renderContents(ctx, item, menuEnv(opts))
end

return M
