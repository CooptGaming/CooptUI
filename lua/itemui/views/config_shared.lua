--[[
    Config Shared tab - Valuable list (never sell, always loot).
    Part of ItemUI config view split (Task 07).
--]]

require('ImGui')

local ConfigFilters = require('itemui.views.config_filters')

local ConfigShared = {}

function ConfigShared.render(ctx)
    ConfigFilters.renderBreadcrumb(ctx, "Shared", "Valuable list")
    ImGui.Spacing()
    ImGui.TextColored(ctx.theme.ToVec4(ctx.theme.Colors.Muted), "Items never sold and always looted. Shared between sell.mac and loot.mac.")
    ImGui.Spacing()
    ConfigFilters.renderFiltersSection(ctx, 2, false)
end

return ConfigShared
