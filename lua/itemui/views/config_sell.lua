--[[
    Config Sell Rules tab - Keep, Always sell, Never sell by type lists.
    Part of ItemUI config view split (Task 07).
--]]

require('ImGui')

local ConfigFilters = require('itemui.views.config_filters')

local ConfigSell = {}

function ConfigSell.render(ctx)
    ConfigFilters.renderBreadcrumb(ctx, "Sell Rules", "Item lists")
    ImGui.Spacing()
    ImGui.TextColored(ctx.theme.ToVec4(ctx.theme.Colors.Muted), "Keep (never sell), Always sell, Never sell by type. Options are in General > Sell.")
    ImGui.Spacing()
    ConfigFilters.renderFiltersSection(ctx, 1, false)
end

return ConfigSell
