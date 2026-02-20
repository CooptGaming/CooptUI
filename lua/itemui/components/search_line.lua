--[[
    ItemUI Search Line (Phase 5)
    Minimal shared search: label + InputText + clear button + tooltips.
    Use in Inventory, Sell, Bank for one consistent search UI.
--]]

require('ImGui')

local M = {}

--- Render a single search line (Search: [input] [X]).
--- @param id string Unique ID for the input and clear button (e.g. "InvSearch", "BankSearch")
--- @param state string Current search text (e.g. ctx.uiState.searchFilterInv)
--- @param width number Optional width for the input (default 180)
--- @param tooltip string Optional tooltip for the input (default "Filter items by name")
--- @return boolean changed, string newText  If changed, caller should set state to newText
function M.render(id, state, width, tooltip)
    width = width or 180
    tooltip = tooltip or "Filter items by name"
    local s = state or ""
    ImGui.Text("Search:")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(width)
    local changed, newText = ImGui.InputText("##" .. id, s)
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text(tooltip); ImGui.EndTooltip() end
    ImGui.SameLine()
    if ImGui.Button("X##Clear" .. id, ImVec2(22, 0)) then
        return true, ""
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Clear search"); ImGui.EndTooltip() end
    return changed, newText
end

return M
