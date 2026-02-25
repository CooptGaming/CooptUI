--[[
    Shared UI helpers (Phase 6).
    Single path for refresh buttons across Inventory, Sell, Bank, Augments, etc.
--]]

require('ImGui')

local M = {}

--- Return ImVec4 for Name column sell-status color: green = Keep, red = Will Sell, white = Neutral.
--- Uses ctx.getSellStatusForItem(item) when item.willSell/inKeep not set; otherwise row state.
--- @param ctx table with theme, getSellStatusForItem
--- @param item table row with optional willSell, inKeep (or from getSellStatusForItem)
--- @return ImVec4 color for ImGui.TextColored or PushStyleColor(ImGuiCol.Text, color)
function M.getSellStatusNameColor(ctx, item)
    if not ctx or not item then return ImVec4(1, 1, 1, 1) end
    local willSell, inKeep = item.willSell, item.inKeep
    if willSell == nil or inKeep == nil then
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

return M
