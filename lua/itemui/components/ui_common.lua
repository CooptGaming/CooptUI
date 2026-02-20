--[[
    Shared UI helpers (Phase 6).
    Single path for refresh buttons across Inventory, Sell, Bank, Augments, etc.
--]]

require('ImGui')

local M = {}

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
